import AppKit
import CoreAudio
import CoreMediaIO

/// Whether you're at the Mac, and whether you're on a call, so the lock never lands at a bad moment.
@MainActor
final class Presence {
    private var screenLocked = false
    private var asleep = false

    init() {
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = false }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false }
        }
    }

    /// Five minutes without a key press or mouse move counts as away.
    var isAway: Bool {
        screenLocked || asleep || CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) > 300
    }

    var inCall: Bool { Self.microphoneInUse || Self.cameraInUse }

    private static var microphoneInUse: Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static var cameraInUse: Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        for device in devices {
            var running: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                           mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                           mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }
}
