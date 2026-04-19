import Foundation
import CoreAudio
import AVFoundation

/// Enumerates CoreAudio devices and routes audio output to a specific device.
final class AudioRouterService: ObservableObject {

    @Published private(set) var inputDevices:  [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []

    init() { refresh() }

    // MARK: - Enumeration

    func refresh() {
        let all = allDevices()
        inputDevices  = [.systemDefault] + all.filter(\.hasInput)
        outputDevices = [.systemDefault] + all.filter(\.hasOutput)
    }

    private func allDevices() -> [AudioDevice] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard let name = deviceName(for: deviceID),
                  let uid  = deviceUID(for: deviceID)
            else { return nil }

            return AudioDevice(
                id:        deviceID,
                uid:       uid,
                name:      name,
                hasInput:  channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)  > 0,
                hasOutput: channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0
            )
        }
    }

    // MARK: - Property helpers

    private func deviceName(for id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var cfName: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfName) == noErr,
              let name = cfName as String?
        else { return nil }
        return name
    }

    private func deviceUID(for id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var cfUID: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfUID) == noErr,
              let uid = cfUID as String?
        else { return nil }
        return uid
    }

    private func channelCount(for id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    scope,
            mElement:  kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return 0 }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &dataSize, bufferList) == noErr
        else { return 0 }

        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        return ablPointer.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: - Routing

    /// Set the macOS system default output device to the device identified by `uid`.
    /// Pass an empty string to leave the system default unchanged.
    @discardableResult
    func setSystemOutputDevice(uid: String) -> Bool {
        guard !uid.isEmpty,
              let device = outputDevices.first(where: { $0.uid == uid })
        else { return true }  // empty UID = use system default, always succeeds
        return setDefaultOutputDevice(id: device.id)
    }

    @discardableResult
    func setSystemInputDevice(uid: String) -> Bool {
        guard !uid.isEmpty,
              let device = inputDevices.first(where: { $0.uid == uid })
        else { return true }
        return setDefaultInputDevice(id: device.id)
    }

    private func setDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var deviceID = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        ) == noErr
    }

    private func setDefaultInputDevice(id: AudioDeviceID) -> Bool {
        var deviceID = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        ) == noErr
    }

    /// Return the AudioDeviceID for the given persistent UID, or nil.
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return (inputDevices + outputDevices).first(where: { $0.uid == uid })?.id
    }
}
