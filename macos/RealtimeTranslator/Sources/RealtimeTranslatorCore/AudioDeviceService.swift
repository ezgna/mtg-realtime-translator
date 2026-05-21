import AudioToolbox
import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let hasInput: Bool
    public let hasOutput: Bool

    public init(id: AudioDeviceID, name: String, uid: String, hasInput: Bool, hasOutput: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.hasInput = hasInput
        self.hasOutput = hasOutput
    }
}

public enum AudioDeviceService {
    public static func defaultInputDevice() -> AudioDevice? {
        defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    public static func defaultOutputDevice() -> AudioDevice? {
        defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    public static func inputDevices() -> [AudioDevice] {
        allDevices().filter(\.hasInput)
    }

    public static func outputDevices() -> [AudioDevice] {
        allDevices().filter(\.hasOutput)
    }

    public static func allDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id in
            let inputChannels = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = channelCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput)
            guard inputChannels > 0 || outputChannels > 0 else {
                return nil
            }
            return AudioDevice(
                id: id,
                name: stringProperty(deviceID: id, selector: kAudioObjectPropertyName) ?? "Device \(id)",
                uid: stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID) ?? "\(id)",
                hasInput: inputChannels > 0,
                hasOutput: outputChannels > 0
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector) -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return device(deviceID: deviceID)
    }

    private static func device(deviceID: AudioDeviceID) -> AudioDevice? {
        let inputChannels = channelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
        let outputChannels = channelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
        guard inputChannels > 0 || outputChannels > 0 else {
            return nil
        }
        return AudioDevice(
            id: deviceID,
            name: stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? "Device \(deviceID)",
            uid: stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)",
            hasInput: inputChannels > 0,
            hasOutput: outputChannels > 0
        )
    }

    private static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            return nil
        }
        return value as String
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer {
            bufferList.deallocate()
        }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }

        let audioBufferList = bufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }
    }
}
