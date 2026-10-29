import AppKit
import IOKit
import IOKit.hid
import Observation

/// The water's surface, modeled as the first sloshing mode of liquid in a bottle.
///
/// Turning the bottle doesn't turn the water: the surface stays level with the world, so relative
/// to the screen it leans by exactly the Mac's roll, with no lag. Sideways acceleration tilts the
/// effective gravity the water feels, and the surface swings toward it as a lightly damped pendulum.
@MainActor
@Observable
final class Slosh {
    static let shared = Slosh()

    /// Angle of the surface relative to the screen, in radians. Positive raises the left side.
    private(set) var tilt = 0.0
    /// Ripple height from shaking, 0 to 1.
    private(set) var agitation = 0.0
    /// How far the bottle itself leans toward the low side, relative to the screen, in radians.
    /// Positive tips its top to the left.
    private(set) var lean = 0.0
    @ObservationIgnored private var leanSpeed = 0.0

    @ObservationIgnored private var roll = 0.0
    /// How far the surface has swung from level with the world, and how fast.
    @ObservationIgnored private var swing = 0.0
    @ObservationIgnored private var swingSpeed = 0.0
    /// Where effective gravity pulls the surface, relative to level, from sideways acceleration.
    @ObservationIgnored private var push = 0.0
    @ObservationIgnored private var timer: Timer?

    /// About one swing a second, which looks right for a bottle this size; water barely damps itself.
    private static let omega = 2 * Double.pi * 1.1
    private static let dampingRatio = 0.16
    private static let maxTilt = Double.pi / 2 + 0.5
    private static let dt = 1.0 / 60
    /// The bottle leans as far as the Mac does, rocking into place with a springy wobble. Past about
    /// 50 degrees it tips over and lies on its side, and it stands back up once the Mac is under 25.
    private static let fallAngle = 50 * Double.pi / 180
    private static let standAngle = 25 * Double.pi / 180
    private static let lyingDown = Double.pi / 2
    private static let leanOmega = 2 * Double.pi * 1.8
    private static let leanDamping = 0.45
    @ObservationIgnored private var fallen = 0.0

    private var leanTarget: Double {
        if fallen != 0 { return fallen * Self.lyingDown }
        return max(-Self.fallAngle, min(Self.fallAngle, roll))
    }

    /// Whether the bottle is on its side, and which way.
    private func updateFall() {
        if fallen == 0, abs(roll) > Self.fallAngle {
            fallen = roll > 0 ? 1 : -1
        } else if fallen != 0, abs(roll) < Self.standAngle {
            fallen = 0
        }
    }

    /// The Mac's roll from level, and the lean of effective gravity from sideways acceleration, in radians.
    func update(roll: Double, push: Double) {
        let roll = max(-Self.lyingDown, min(Self.lyingDown, roll))
        guard abs(roll - self.roll) > 0.001 || abs(push - self.push) > 0.001 else { return }
        self.roll = roll
        self.push = push
        updateFall()
        wake()
    }

    /// A sudden sideways shove, as a change in swing speed (radians per second).
    func kick(_ amount: Double) {
        guard abs(amount) > 0.005 else { return }
        swingSpeed += amount
        leanSpeed += amount * 0.4
        wake()
    }

    /// Ripples without a sideways swing, like a bump from below.
    func ripple(_ amount: Double) {
        guard amount > 0.01 else { return }
        agitation = min(1, agitation + amount)
        wake()
    }

    func splash() {
        swingSpeed += 0.9
        agitation = 1
        wake()
    }

    #if DEBUG
    /// Holds the Mac at a roll with everything settled, for snapshots.
    func settle(roll: Double) {
        self.roll = roll
        swing = 0
        fallen = 0
        updateFall()
        lean = leanTarget
        tilt = roll
    }
    #endif

    private func wake() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.dt, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let dt = Self.dt
        // Semi-implicit Euler stays stable for a lightly damped oscillator at this step size.
        swingSpeed += (-Self.omega * Self.omega * (swing - push) - 2 * Self.dampingRatio * Self.omega * swingSpeed) * dt
        swing = max(-0.5, min(0.5, swing + swingSpeed * dt))
        agitation = max(min(1, abs(swingSpeed) * 0.12), agitation * pow(0.3, dt))

        let target = leanTarget
        leanSpeed += (-Self.leanOmega * Self.leanOmega * (lean - target) - 2 * Self.leanDamping * Self.leanOmega * leanSpeed) * dt
        var nextLean = lean + leanSpeed * dt
        // The ground stops a falling bottle, and it bounces a little.
        if abs(nextLean) > Self.lyingDown {
            nextLean = nextLean > 0 ? Self.lyingDown : -Self.lyingDown
            leanSpeed *= -0.3
            agitation = 1
        }
        if abs(nextLean - lean) > 0.0003 { lean = nextLean }

        let next = max(-Self.maxTilt, min(Self.maxTilt, roll + swing))
        if abs(next - tilt) > 0.0005 { tilt = next }
        if abs(swing - push) < 0.0015, abs(swingSpeed) < 0.003, agitation < 0.01,
           abs(lean - target) < 0.001, abs(leanSpeed) < 0.003 {
            swing = push
            swingSpeed = 0
            if agitation != 0 { agitation = 0 }
            tilt = max(-Self.maxTilt, min(Self.maxTilt, roll + swing))
            leanSpeed = 0
            lean = target
            timer?.invalidate()
            timer = nil
        }
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
    private var felt = (x: 0.0, y: 0.0, z: -1.0)
    #if DEBUG
    var log: FileHandle?
    #endif
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var restore: [(io_object_t, String, CFTypeRef)] = []
    private var remembered = false
    private var lastSample = Date()
    private var keepAlive: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        enableSensorHub()
        openAccelerometer()
        if let device = Self.device(page: 0x20, usage: 0x8A), IOHIDDeviceOpen(device, 0) == kIOReturnSuccess {
            lid = device
            lidTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readLid() }
            }
        }
        // macOS turns the sensor hub's reporting back off after a while, and after sleep. The accelerometer
        // reports constantly while it's on, even when the Mac is still, so silence means it was switched off.
        let keepAlive = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlive() }
        }
        RunLoop.main.add(keepAlive, forMode: .common)
        self.keepAlive = keepAlive
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.enableSensorHub() }
        }
    }

    private func checkAlive() {
        guard accelerometer != nil else { return }
        let silent = Date().timeIntervalSince(lastSample)
        if silent > 6 {
            // Turning reporting back on didn't help; the device itself may have gone away, so open it again.
            closeAccelerometer()
            enableSensorHub()
            openAccelerometer()
            lastSample = Date()
        } else if silent > 1.5 {
            enableSensorHub()
        }
    }

    private func closeAccelerometer() {
        guard let accelerometer else { return }
        IOHIDDeviceUnscheduleFromRunLoop(accelerometer, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(accelerometer, 0)
        self.accelerometer = nil
    }

    private func openAccelerometer() {
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
    }

    func stop() {
        closeAccelerometer()
        keepAlive?.invalidate()
        keepAlive = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        lidTimer?.invalidate()
        lidTimer = nil
        for (service, key, value) in restore {
            IORegistryEntrySetCFProperty(service, key as CFString, value)
            IOObjectRelease(service)
        }
        restore = []
    }

    /// Which way the sensor's x axis points relative to the screen.
    private static let direction = -1.0

    private func receive(_ sample: (Double, Double, Double)) {
        lastSample = Date()
        // At 100 readings a second: gravity settles in about 60 ms, the raw reading in about 15 ms.
        func blend(_ value: inout (x: Double, y: Double, z: Double), _ amount: Double) {
            value = (value.x + (sample.0 - value.x) * amount,
                     value.y + (sample.1 - value.y) * amount,
                     value.z + (sample.2 - value.z) * amount)
        }
        blend(&gravity, 0.15)
        blend(&felt, 0.5)
        func angle(_ v: (x: Double, y: Double, z: Double)) -> Double {
            atan2(v.x, (v.y * v.y + v.z * v.z).squareRoot()) * Self.direction
        }
        let roll = angle(gravity)
        // What the water feels is gravity plus the Mac's own acceleration; the sensor noise stays out.
        var push = angle(felt) - roll
        push = abs(push) < 0.01 ? 0 : push - 0.01 * (push > 0 ? 1 : -1)
        Slosh.shared.update(roll: roll, push: max(-0.4, min(0.4, push)))
        #if DEBUG
        log?.write(Data(String(format: "%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n", ProcessInfo.processInfo.systemUptime,
                               sample.0, sample.1, sample.2, roll, push, Slosh.shared.tilt).utf8))
        #endif
    }

    private func readLid() {
        guard let lid else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        guard IOHIDDeviceGetReport(lid, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess, length >= 3 else { return }
        let angle = Double(Int(report[2]) << 8 | Int(report[1]))
        // Opening or closing the lid rocks the water front to back, which shows as ripples, not a lean.
        if let lastLid, abs(angle - lastLid) >= 1 { Slosh.shared.ripple(abs(angle - lastLid) * 0.04) }
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
                if !remembered, let old = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    IOObjectRetain(service)
                    restore.append((service, key, old))
                }
                IORegistryEntrySetCFProperty(service, key as CFString, value as CFNumber)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        remembered = true
    }

    private static func device(page: Int, usage: Int) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05AC, kIOHIDPrimaryUsagePageKey: page, kIOHIDPrimaryUsageKey: usage] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return nil }
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
    }
}
