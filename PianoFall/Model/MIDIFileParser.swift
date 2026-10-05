import Foundation

enum MIDIFileError: LocalizedError {
    case notAMIDIFile
    case truncated
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notAMIDIFile: return "This doesn't look like a MIDI file."
        case .truncated: return "The MIDI file ended unexpectedly."
        case .malformed(let detail): return "The MIDI file is damaged (\(detail))."
        }
    }
}

/// Parses Standard MIDI Files (format 0 and 1) into a `Song`.
enum MIDIFileParser {

    static func parse(data: Data, title: String) throws -> Song {
        var reader = ByteReader(Array(data))

        // Some files are wrapped in a RIFF "RMID" container; find the MThd header.
        guard let headerStart = findHeader(reader.bytes) else { throw MIDIFileError.notAMIDIFile }
        reader.pos = headerStart + 4

        let headerLength = Int(try reader.u32())
        guard headerLength >= 6 else { throw MIDIFileError.malformed("bad header") }
        _ = try reader.u16() // format: 0, 1 and 2 are all handled as parallel tracks
        let trackCount = Int(try reader.u16())
        let division = try reader.u16()
        try reader.skip(headerLength - 6)

        var tracks: [ParsedTrack] = []
        while reader.remaining >= 8 && tracks.count < trackCount {
            let chunkID = try reader.fourCC()
            let length = Int(try reader.u32())
            let chunkEnd = min(reader.pos + length, reader.end)
            if chunkID == "MTrk" {
                var trackReader = ByteReader(reader.bytes, start: reader.pos, end: chunkEnd)
                tracks.append(try parseTrack(&trackReader))
            }
            reader.pos = chunkEnd
        }
        guard !tracks.isEmpty else { throw MIDIFileError.malformed("no tracks") }

        let tempoMap = TempoMap(tempos: tracks.flatMap(\.tempos), division: division)

        // A part is one (track, channel) pair, so format-0 files still split into hands/instruments.
        var partIDs: [Int: Int] = [:]
        var partNames: [Int: String] = [:]
        var rawNotes: [Song.RawNote] = []
        for (trackIndex, track) in tracks.enumerated() {
            let channels = Set(track.notes.map(\.channel))
            for note in track.notes {
                let key = trackIndex * 16 + Int(note.channel)
                let partID: Int
                if let existing = partIDs[key] {
                    partID = existing
                } else {
                    partID = partIDs.count
                    partIDs[key] = partID
                    var name = track.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if name.isEmpty { name = "Track \(trackIndex + 1)" }
                    if channels.count > 1 { name += " (ch \(note.channel + 1))" }
                    partNames[partID] = name
                }
                let start = tempoMap.seconds(at: note.startTick)
                let end = tempoMap.seconds(at: note.endTick)
                rawNotes.append(Song.RawNote(pitch: note.pitch, velocity: note.velocity,
                                             start: start, duration: end - start, partID: partID))
            }
        }

        let lastTick = tracks.map(\.endTick).max() ?? 0
        let measures = measureStarts(timeSignatures: tracks.flatMap(\.timeSignatures),
                                     division: division, lastTick: lastTick, tempoMap: tempoMap)

        return Song(title: title, rawNotes: rawNotes, partNames: partNames,
                    measureStarts: measures, endTime: tempoMap.seconds(at: lastTick))
    }

    // MARK: - Tracks

    private struct ParsedNote {
        var channel: UInt8
        var pitch: UInt8
        var velocity: UInt8
        var startTick: UInt64
        var endTick: UInt64
    }

    private struct ParsedTrack {
        var name: String?
        var notes: [ParsedNote] = []
        var tempos: [(tick: UInt64, microsecondsPerQuarter: UInt32)] = []
        var timeSignatures: [(tick: UInt64, numerator: Int, denominator: Int)] = []
        var endTick: UInt64 = 0
    }

    private static func parseTrack(_ reader: inout ByteReader) throws -> ParsedTrack {
        var track = ParsedTrack()
        var tick: UInt64 = 0
        var runningStatus: UInt8 = 0
        // Key: channel * 128 + pitch. Notes still held, oldest first.
        var openNotes: [Int: [(tick: UInt64, velocity: UInt8)]] = [:]

        func close(channel: UInt8, pitch: UInt8, at tick: UInt64) {
            let key = Int(channel) * 128 + Int(pitch)
            guard var stack = openNotes[key], !stack.isEmpty else { return }
            let opened = stack.removeFirst()
            openNotes[key] = stack
            track.notes.append(ParsedNote(channel: channel, pitch: pitch, velocity: opened.velocity,
                                          startTick: opened.tick, endTick: tick))
        }

        trackLoop: while !reader.atEnd {
            tick += UInt64(try reader.varLen())
            var status = try reader.u8()
            if status < 0x80 {
                // Running status: reuse the previous status byte, this byte is data.
                guard runningStatus != 0 else { throw MIDIFileError.malformed("missing status byte") }
                status = runningStatus
                reader.pos -= 1
            }

            switch status {
            case 0xFF:
                let type = try reader.u8()
                let length = Int(try reader.varLen())
                let data = try reader.read(length)
                switch type {
                case 0x03 where track.name == nil:
                    track.name = String(decoding: data, as: UTF8.self)
                case 0x51 where data.count >= 3:
                    let bytes = Array(data)
                    let tempo = UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
                    if tempo > 0 { track.tempos.append((tick, tempo)) }
                case 0x58 where data.count >= 2:
                    let bytes = Array(data)
                    let denominator = 1 << min(Int(bytes[1]), 6)
                    if bytes[0] > 0 { track.timeSignatures.append((tick, Int(bytes[0]), denominator)) }
                case 0x2F:
                    break trackLoop
                default:
                    break
                }
            case 0xF0, 0xF7:
                try reader.skip(Int(try reader.varLen()))
            case 0xF1...0xFE:
                // System common/real-time messages shouldn't appear in files; skip their data.
                let dataBytes = status == 0xF2 ? 2 : (status == 0xF1 || status == 0xF3 ? 1 : 0)
                try reader.skip(dataBytes)
            default:
                runningStatus = status
                let kind = status & 0xF0
                let channel = status & 0x0F
                let data1 = try reader.u8() & 0x7F
                var data2: UInt8 = 0
                if kind != 0xC0 && kind != 0xD0 {
                    data2 = try reader.u8() & 0x7F
                }
                if kind == 0x90 && data2 > 0 {
                    openNotes[Int(channel) * 128 + Int(data1), default: []].append((tick, data2))
                } else if kind == 0x80 || kind == 0x90 {
                    close(channel: channel, pitch: data1, at: tick)
                }
            }
        }

        track.endTick = tick
        // Close notes that never received a note-off.
        for (key, stack) in openNotes {
            for opened in stack where tick > opened.tick {
                track.notes.append(ParsedNote(channel: UInt8(key / 128), pitch: UInt8(key % 128),
                                              velocity: opened.velocity, startTick: opened.tick, endTick: tick))
            }
        }
        return track
    }

    // MARK: - Bars

    private static func measureStarts(timeSignatures: [(tick: UInt64, numerator: Int, denominator: Int)],
                                      division: UInt16, lastTick: UInt64, tempoMap: TempoMap) -> [Double] {
        guard division & 0x8000 == 0, division > 0 else { return [] } // SMPTE timing has no bars
        let ticksPerQuarter = Int(division)

        // One signature per tick (the last wins), always starting with one at tick 0.
        var byTick: [UInt64: (Int, Int)] = [:]
        for signature in timeSignatures { byTick[signature.tick] = (signature.numerator, signature.denominator) }
        if byTick[0] == nil { byTick[0] = (4, 4) }
        let signatures = byTick.keys.sorted().map { (tick: $0, numerator: byTick[$0]!.0, denominator: byTick[$0]!.1) }

        var result: [Double] = []
        for (index, signature) in signatures.enumerated() {
            let segmentEnd = index + 1 < signatures.count ? signatures[index + 1].tick : lastTick + 1
            let barTicks = UInt64(max(1, ticksPerQuarter * 4 * signature.numerator / signature.denominator))
            var tick = signature.tick
            while tick < segmentEnd && result.count < 20_000 {
                result.append(tempoMap.seconds(at: tick))
                tick += barTicks
            }
        }
        return result
    }

    private static func findHeader(_ bytes: [UInt8]) -> Int? {
        let magic: [UInt8] = Array("MThd".utf8)
        guard bytes.count >= 14 else { return nil }
        let searchLimit = min(bytes.count - 14, 64)
        for index in 0...searchLimit where Array(bytes[index..<index + 4]) == magic {
            return index
        }
        return nil
    }
}

// MARK: - Tempo map

/// Converts MIDI ticks to seconds, taking tempo changes into account.
struct TempoMap {
    private struct Segment {
        var tick: UInt64
        var seconds: Double
        var secondsPerTick: Double
    }

    private var segments: [Segment] = []

    init(tempos: [(tick: UInt64, microsecondsPerQuarter: UInt32)], division: UInt16) {
        if division & 0x8000 != 0 {
            // SMPTE: -framesPerSecond in the high byte, ticks per frame in the low byte.
            let rawFPS = -Int(Int8(bitPattern: UInt8(division >> 8)))
            let fps = rawFPS == 29 ? 29.97 : Double(max(rawFPS, 1))
            let ticksPerFrame = Double(max(Int(division & 0xFF), 1))
            segments = [Segment(tick: 0, seconds: 0, secondsPerTick: 1 / (fps * ticksPerFrame))]
            return
        }

        let ticksPerQuarter = Double(max(Int(division), 1))
        func secondsPerTick(_ microseconds: UInt32) -> Double {
            Double(microseconds) / 1_000_000 / ticksPerQuarter
        }

        segments = [Segment(tick: 0, seconds: 0, secondsPerTick: secondsPerTick(500_000))] // 120 BPM default
        for tempo in tempos.sorted(by: { $0.tick < $1.tick }) {
            let last = segments[segments.count - 1]
            let segment = Segment(tick: tempo.tick,
                                  seconds: last.seconds + Double(tempo.tick - last.tick) * last.secondsPerTick,
                                  secondsPerTick: secondsPerTick(tempo.microsecondsPerQuarter))
            if last.tick == tempo.tick {
                segments[segments.count - 1] = segment
            } else {
                segments.append(segment)
            }
        }
    }

    func seconds(at tick: UInt64) -> Double {
        var low = 0
        var high = segments.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if segments[mid].tick <= tick {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let segment = segments[low]
        return segment.seconds + Double(tick - segment.tick) * segment.secondsPerTick
    }
}

// MARK: - Byte reader

private struct ByteReader {
    let bytes: [UInt8]
    var pos: Int
    let end: Int

    init(_ bytes: [UInt8], start: Int = 0, end: Int? = nil) {
        self.bytes = bytes
        self.pos = start
        self.end = min(end ?? bytes.count, bytes.count)
    }

    var atEnd: Bool { pos >= end }
    var remaining: Int { max(0, end - pos) }

    mutating func u8() throws -> UInt8 {
        guard pos < end else { throw MIDIFileError.truncated }
        defer { pos += 1 }
        return bytes[pos]
    }

    mutating func u16() throws -> UInt16 {
        let high = try u8()
        let low = try u8()
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func u32() throws -> UInt32 {
        let high = try u16()
        let low = try u16()
        return UInt32(high) << 16 | UInt32(low)
    }

    mutating func varLen() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = try u8()
            value = (value << 7) | UInt32(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw MIDIFileError.malformed("bad length")
    }

    mutating func read(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, pos + count <= end else { throw MIDIFileError.truncated }
        defer { pos += count }
        return bytes[pos..<pos + count]
    }

    mutating func skip(_ count: Int) throws {
        _ = try read(count)
    }

    mutating func fourCC() throws -> String {
        String(decoding: try read(4), as: UTF8.self)
    }
}
