import Foundation
import CoreAudio

/// A lightweight description of a CoreAudio device.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID          // CoreAudio numeric ID
    let uid: String                // Persistent UID stored in settings
    let name: String
    let hasInput:  Bool
    let hasOutput: Bool
}

extension AudioDevice {
    static let systemDefault = AudioDevice(
        id:        kAudioObjectUnknown,
        uid:       "",
        name:      "System Default",
        hasInput:  true,
        hasOutput: true
    )
}
