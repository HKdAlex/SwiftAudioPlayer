import Foundation

/// Whether playback should resume after an audio route disappears and comes back.
///
/// Car Bluetooth and CarPlay often drop `oldDeviceUnavailable` and then
/// `newDeviceAvailable` a few seconds later. A headphone unplug does not bring
/// an external route back, so it stays paused.
struct RouteResumePolicy {
    static let graceSeconds: TimeInterval = 8

    private(set) var resumeUntil: Date?

    mutating func userPaused() {
        cancelPendingResume()
    }

    mutating func cancelPendingResume() {
        resumeUntil = nil
    }

    mutating func externalRouteLost(wasPlaying: Bool, now: Date) {
        guard wasPlaying else { return }
        resumeUntil = now.addingTimeInterval(Self.graceSeconds)
    }

    /// - Returns: `true` when the caller should resume playback.
    mutating func externalRouteReturned(now: Date, outputIsExternal: Bool) -> Bool {
        guard outputIsExternal, let until = resumeUntil else { return false }
        if now > until {
            resumeUntil = nil
            return false
        }
        resumeUntil = nil
        return true
    }

    static func isExternalOutput(portType: String) -> Bool {
        switch portType {
        case "BluetoothA2DPOutput",
             "BluetoothHFP",
             "BluetoothLE",
             "Headphones",
             "HeadsetMic",
             "CarAudio",
             "AirPlay",
             "USBAudio",
             "HDMI",
             "LineOut":
            return true
        default:
            return false
        }
    }
}
