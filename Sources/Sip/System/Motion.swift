import Foundation
import IOKit
import IOKit.hid
import Observation

/// The water's surface: it stays level with the world as the Mac tilts, and sloshes when it's moved.
@MainActor
@Observable
final class Slosh {
    static let shared = Slosh()

    /// Angle of the surface relative to the screen, in radians. Positive raises the left side.
    private(set) var tilt = 0.0
    /// Extra wave height from shaking, 0 to 1.
    private(set) var agitation = 0.0

    @ObservationIgnored private var target = 0.0
    @ObservationIgnored private var velocity = 0.0
    @ObservationIgnored private var timer: Timer?

    private static let stiffness = 55.0
    private static let damping = 3.2
    private static let maxTilt = 0.6

    /// The Mac's roll from level, in radians, from the accelerometer.
    func setRoll(_ roll: Double) {
        let next = max(-Self.maxTilt, min(Self.maxTilt, roll))
        guard abs(next - target) > 0.004 else { return }
        target = next
        wake()
    }

    /// A sideways jolt, in g or in screen points per second squared scaled to match.
    func kick(_ amount: Double) {
        guard abs(amount) > 0.01 else { return }
        velocity += amount
        agitation = min(1, agitation + abs(amount) * 0.08)
        wake()
    }

    func splash() {
        velocity += 1.6
        agitation = 1
        wake()
    }

    private func wake() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(1 / 60) }
        }
    }

    private func step(_ dt: Double) {
        velocity += (-Self.stiffness * (tilt - target) - Self.damping * velocity) * dt
        let next = max(-Self.maxTilt, min(Self.maxTilt, tilt + velocity * dt))
        let calmer = agitation * pow(0.25, dt)
        if abs(next - target) < 0.002, abs(velocity) < 0.004, calmer < 0.01 {
            tilt = target
            agitation = 0
            velocity = 0
            timer?.invalidate()
            timer = nil
            return
        }
        tilt = next
        agitation = calmer
    }
}

/// Reads the MacBook's built-in accelerometer and lid angle sensor, when the Mac has them.
@MainActor
final class MotionSensors {
    private var accelerometer: IOHIDDevice?
    private var lid: IOHIDDevice?
    private var lidTimer: Timer?
    private var lastLid: Double?
    private var gravity = (x: 0.0, y: 0.0, z: -1.0)
    private var lastLateral = 0.0
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var restore: [(io_object_t, String, CFTypeRef)] = []

    func start() {
        enableSensorHub()
        if let device = Self.device(page: 0xFF00, usage: 3), IOHIDDeviceOpen(device, 0) == kIOReturnSuccess {
            accelerometer = device
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
                guard let context, length >= 18 else { return }
                let sensors = Unmanaged<MotionSensors>.fromOpaque(context).takeUnretainedValue()
                func axis(_ offset: Int) -> Double {
                    let raw = UInt32(report[offset]) | UInt32(report[offset + 1]) << 8 | UInt32(report[offset + 2]) << 16 | UInt32(report[offset + 3]) << 24
                    return Double(Int32(bitPattern: raw)) / 65536
                }
                let sample = (axis(6), axis(10), axis(14))
                MainActor.assumeIsolated { sensors.receive(sample) }
            }, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        if let device = Self.device(page: 0x20, usage: 0x8A), IOHIDDeviceOpen(device, 0) == kIOReturnSuccess {
            lid = device
            lidTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readLid() }
            }
        }
    }

    func stop() {
        if let accelerometer {
            IOHIDDeviceUnscheduleFromRunLoop(accelerometer, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(accelerometer, 0)
        }
        accelerometer = nil
        lidTimer?.invalidate()
        lidTimer = nil
        for (service, key, value) in restore {
            IORegistryEntrySetCFProperty(service, key as CFString, value)
            IOObjectRelease(service)
        }
        restore = []
    }

    private func receive(_ sample: (Double, Double, Double)) {
        let blend = 0.08
        gravity = (gravity.x + (sample.0 - gravity.x) * blend,
                   gravity.y + (sample.1 - gravity.y) * blend,
                   gravity.z + (sample.2 - gravity.z) * blend)
        let roll = atan2(gravity.x, (gravity.y * gravity.y + gravity.z * gravity.z).squareRoot())
        Slosh.shared.setRoll(roll)
        // A jolt is how far this reading is from the slowly moving gravity estimate.
        let lateral = sample.0 - gravity.x
        if abs(lateral - lastLateral) > 0.03 { Slosh.shared.kick((lateral - lastLateral) * 6) }
        lastLateral = lateral
    }

    private func readLid() {
        guard let lid else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        guard IOHIDDeviceGetReport(lid, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess, length >= 3 else { return }
        let angle = Double(Int(report[2]) << 8 | Int(report[1]))
        if let lastLid, abs(angle - lastLid) >= 2 { Slosh.shared.kick((angle - lastLid) * 0.05) }
        lastLid = angle
    }

    /// The sensor hub only reports while asked to. Remember what it was set to, and put it back on quit.
    private func enableSensorHub() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            for (key, value) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 10000)] {
                if let old = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    IOObjectRetain(service)
                    restore.append((service, key, old))
                }
                IORegistryEntrySetCFProperty(service, key as CFString, value as CFNumber)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private static func device(page: Int, usage: Int) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: page, kIOHIDPrimaryUsageKey: usage] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return nil }
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
    }
}
