import XCTest
@testable import PianoFall

final class MIDIFileParserTests: XCTestCase {

    /// Format 1, 480 ticks per quarter. Track 1: tempo 120 BPM, then 60 BPM at tick 960.
    /// Track 2: C4 for ticks 0–480, then D4 for ticks 480–1440 (uses running status).
    private func twoTempoFile() -> Data {
        let header: [UInt8] = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, 2, 0x01, 0xE0]
        let tempoTrack: [UInt8] = [
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // 500,000 µs per quarter = 120 BPM
            0x87, 0x40, 0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40, // +960: 1,000,000 µs = 60 BPM
            0x00, 0xFF, 0x2F, 0x00,
        ]
        let noteTrack: [UInt8] = [
            0x00, 0xFF, 0x03, 0x05, 0x50, 0x69, 0x61, 0x6E, 0x6F, // name "Piano"
            0x00, 0x90, 0x3C, 0x64, // C4 on
            0x83, 0x60, 0x3C, 0x00, // +480: C4 off (running status, velocity 0)
            0x00, 0x3E, 0x50, // D4 on (running status)
            0x87, 0x40, 0x80, 0x3E, 0x00, // +960: D4 off
            0x00, 0xFF, 0x2F, 0x00,
        ]
        return Data(header + chunk(tempoTrack) + chunk(noteTrack))
    }

    private func chunk(_ body: [UInt8]) -> [UInt8] {
        let length = UInt32(body.count)
        return [0x4D, 0x54, 0x72, 0x6B,
                UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)] + body
    }

    func testNotesAndTempoChanges() throws {
        let song = try MIDIFileParser.parse(data: twoTempoFile(), title: "Test")

        XCTAssertEqual(song.notes.count, 2)
        let c4 = song.notes[0]
        XCTAssertEqual(c4.pitch, 60)
        XCTAssertEqual(c4.velocity, 100)
        XCTAssertEqual(c4.start, 0, accuracy: 1e-9)
        XCTAssertEqual(c4.duration, 0.5, accuracy: 1e-9)

        // 480 ticks at 120 BPM (0.5 s) + 480 ticks at 60 BPM (1 s).
        let d4 = song.notes[1]
        XCTAssertEqual(d4.pitch, 62)
        XCTAssertEqual(d4.start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d4.end, 2.0, accuracy: 1e-9)

        XCTAssertEqual(song.duration, 2.0, accuracy: 1e-9)
        XCTAssertEqual(song.parts.map(\.name), ["Piano"])
        XCTAssertEqual(song.measureStarts, [0])
    }

    func testRejectsNonMIDIData() {
        XCTAssertThrowsError(try MIDIFileParser.parse(data: Data("hello, not a midi file".utf8), title: "x"))
    }

    func testTempoMapDefaultsTo120BPM() {
        let map = TempoMap(tempos: [], division: 480)
        XCTAssertEqual(map.seconds(at: 480), 0.5, accuracy: 1e-9)
        XCTAssertEqual(map.seconds(at: 1920), 2.0, accuracy: 1e-9)
    }

    func testDemoSongHasTwoHands() {
        let song = DemoSong.make()
        XCTAssertEqual(song.parts.count, 2)
        // Right hand is higher, so it gets the first (green) colour.
        let right = song.parts.first { $0.name == "Right hand" }
        XCTAssertEqual(right?.colorIndex, 0)
    }

    func testKeyboardLayoutFullRange() {
        let layout = KeyboardLayout(range: 21...108, width: 520)
        XCTAssertEqual(layout.whiteKeyWidth, 10, accuracy: 1e-9) // 52 white keys
        XCTAssertEqual(layout.keyFrame(21).x, 0, accuracy: 1e-9) // A0
        XCTAssertEqual(layout.keyFrame(108).x, 510, accuracy: 1e-9) // C8
        // A#0 is centred on the line between A0 and B0.
        XCTAssertEqual(layout.keyFrame(22).x + layout.blackKeyWidth / 2, 10, accuracy: 1e-9)
    }
}
