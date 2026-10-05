import CoreMIDI
import Foundation

/// Listens to every connected MIDI keyboard (USB via the Lightning/USB-C camera adapter,
/// or any other CoreMIDI source) and reports notes.
///
/// `onNoteOn`, `onNoteOff` and `onSustain` are called on CoreMIDI's background thread
/// so sound can be played with minimal latency. `onSourcesChanged` is called on the main thread.
final class MIDIInputManager {
    var onNoteOn: ((_ pitch: UInt8, _ velocity: UInt8) -> Void)?
    var onNoteOff: ((_ pitch: UInt8) -> Void)?
    var onSustain: ((_ value: UInt8) -> Void)?
    var onSourcesChanged: ((_ names: [String]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    /// Number of 32-bit words in a Universal MIDI Packet, by message type (top 4 bits).
    private static let wordCounts = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    func start() {
        let clientStatus = MIDIClientCreateWithBlock("PianoFall" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.connectAllSources() }
            }
        }
        guard clientStatus == noErr else {
            print("MIDI client error \(clientStatus)")
            return
        }

        let portStatus = MIDIInputPortCreateWithProtocol(client, "PianoFall Input" as CFString,
                                                         ._1_0, &inputPort) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
        guard portStatus == noErr else {
            print("MIDI port error \(portStatus)")
            return
        }
        connectAllSources()
    }

    private func connectAllSources() {
        var names: [String] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            // Disconnect first so a source is never connected twice.
            MIDIPortDisconnectSource(inputPort, source)
            MIDIPortConnectSource(inputPort, source, nil)
            names.append(Self.displayName(of: source))
        }
        onSourcesChanged?(names)
    }

    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        for packet in eventList.unsafeSequence() {
            let wordCount = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var index = 0
                while index < min(wordCount, words.count) {
                    let word = words[index]
                    let messageType = Int(word >> 28)
                    if messageType == 0x2 {
                        handleMIDI1ChannelMessage(word)
                    }
                    index += Self.wordCounts[messageType]
                }
            }
        }
    }

    private func handleMIDI1ChannelMessage(_ word: UInt32) {
        let status = UInt8((word >> 16) & 0xF0)
        let data1 = UInt8((word >> 8) & 0x7F)
        let data2 = UInt8(word & 0x7F)
        switch status {
        case 0x90 where data2 > 0:
            onNoteOn?(data1, data2)
        case 0x80, 0x90:
            onNoteOff?(data1)
        case 0xB0 where data1 == 64:
            onSustain?(data2)
        default:
            break
        }
    }

    private static func displayName(of object: MIDIObjectRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &name) == noErr,
           let value = name?.takeRetainedValue() {
            return value as String
        }
        return "MIDI device"
    }
}
