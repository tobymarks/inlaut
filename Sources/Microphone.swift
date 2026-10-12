import CoreAudio

/// Which input device a dictation records from.
enum MicrophoneChoice: Hashable {
    /// The system's input, unless that is a Bluetooth headset and the Mac has
    /// its own microphone: a headset switches to its hands-free profile when
    /// the microphone opens and delivers silence for about 1.5 s (measured
    /// with AirPods: first signal after 1.6–1.7 s, built-in 0.3–0.4 s).
    case automatic
    case systemDefault
    case device(uid: String)

    init(stored: String?) {
        switch stored {
        case nil, "automatic": self = .automatic
        case "system": self = .systemDefault
        case let uid?: self = .device(uid: uid)
        }
    }

    var stored: String {
        switch self {
        case .automatic: "automatic"
        case .systemDefault: "system"
        case .device(let uid): uid
        }
    }
}

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
}

enum Microphones {
    /// Every device that can record, in the order Core Audio lists them.
    static func all() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device)
    }

    static func systemDefault() -> InputDevice? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr
        else { return nil }
        return device(id)
    }

    /// The device to record from; nil if nothing can record. A chosen device
    /// that is not connected falls back to the automatic choice.
    static func resolve(_ choice: MicrophoneChoice) -> InputDevice? {
        resolve(choice, current: systemDefault(), among: all())
    }

    static func resolve(_ choice: MicrophoneChoice, current: InputDevice?, among devices: [InputDevice]) -> InputDevice? {
        switch choice {
        case .systemDefault:
            return current
        case .device(let uid):
            return devices.first { $0.uid == uid } ?? resolve(.automatic, current: current, among: devices)
        case .automatic:
            guard let current, current.isBluetooth else { return current }
            return devices.first(where: \.isBuiltIn) ?? current
        }
    }

    private static func device(_ id: AudioDeviceID) -> InputDevice? {
        guard inputChannels(id) > 0,
              let uid = string(id, kAudioDevicePropertyDeviceUID),
              let name = string(id, kAudioObjectPropertyName) else { return nil }
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return InputDevice(id: id, uid: uid, name: name, transport: transport)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
