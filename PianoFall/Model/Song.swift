import Foundation

/// A single note in a song, with times in seconds (at 100% speed).
struct NoteEvent: Identifiable, Hashable {
    var id: Int
    let pitch: UInt8
    let velocity: UInt8
    let start: Double
    let duration: Double
    let partID: Int

    var end: Double { start + duration }
}

/// A playable part of the song (one MIDI track/channel), e.g. right hand or left hand.
struct Part: Identifiable, Hashable {
    let id: Int
    var name: String
    var noteCount: Int
    var averagePitch: Double
    /// Index into `PartPalette`; the highest part gets 0 (green), the next 1 (blue), ...
    var colorIndex: Int
}

struct Song {
    var title: String
    /// Sorted by start time, then pitch.
    let notes: [NoteEvent]
    let parts: [Part]
    /// Start time (seconds) of every bar, used to draw bar lines and snap loops.
    let measureStarts: [Double]
    let duration: Double
    let maxNoteDuration: Double
    let lowestPitch: UInt8
    let highestPitch: UInt8

    struct RawNote {
        var pitch: UInt8
        var velocity: UInt8
        var start: Double
        var duration: Double
        var partID: Int
    }

    init(title: String, rawNotes: [RawNote], partNames: [Int: String], measureStarts: [Double], endTime: Double) {
        self.title = title

        let sorted = rawNotes
            .filter { $0.duration > 0 }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.pitch < $1.pitch }
        notes = sorted.enumerated().map { index, raw in
            NoteEvent(id: index, pitch: raw.pitch, velocity: raw.velocity,
                      start: raw.start, duration: raw.duration, partID: raw.partID)
        }

        var counts: [Int: Int] = [:]
        var pitchSums: [Int: Double] = [:]
        for note in notes {
            counts[note.partID, default: 0] += 1
            pitchSums[note.partID, default: 0] += Double(note.pitch)
        }
        var parts = counts.keys.sorted().map { id in
            Part(id: id,
                 name: partNames[id] ?? "Part \(id + 1)",
                 noteCount: counts[id]!,
                 averagePitch: pitchSums[id]! / Double(counts[id]!),
                 colorIndex: 0)
        }
        let byPitch = parts.indices.sorted { parts[$0].averagePitch > parts[$1].averagePitch }
        for (rank, index) in byPitch.enumerated() {
            parts[index].colorIndex = rank
        }
        self.parts = parts

        let lastEnd = notes.map(\.end).max() ?? 0
        duration = max(lastEnd, endTime)
        maxNoteDuration = notes.map(\.duration).max() ?? 0
        lowestPitch = notes.map(\.pitch).min() ?? 60
        highestPitch = notes.map(\.pitch).max() ?? 72
        self.measureStarts = measureStarts.filter { $0 <= duration + 0.001 }
    }

    func part(_ id: Int) -> Part? {
        parts.first { $0.id == id }
    }

    /// Indices of notes that overlap the time window [from, to].
    func noteIndices(overlapping from: Double, _ to: Double) -> Range<Int> {
        let lower = firstNoteIndex(startingAtOrAfter: from - maxNoteDuration)
        var upper = lower
        while upper < notes.count && notes[upper].start <= to {
            upper += 1
        }
        return lower..<upper
    }

    func firstNoteIndex(startingAtOrAfter time: Double) -> Int {
        var low = 0
        var high = notes.count
        while low < high {
            let mid = (low + high) / 2
            if notes[mid].start < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Start of the bar containing `time` (or `time` itself if the song has no bars).
    func measureStart(atOrBefore time: Double) -> Double {
        measureStarts.last { $0 <= time + 0.001 } ?? max(0, time)
    }

    /// Start of the next bar after `time` (or the song end).
    func measureStart(after time: Double) -> Double {
        measureStarts.first { $0 > time + 0.001 } ?? duration
    }

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func noteName(_ pitch: UInt8) -> String {
        noteNames[Int(pitch) % 12]
    }

    static let empty = Song(title: "No song", rawNotes: [], partNames: [:], measureStarts: [], endTime: 0)
}
