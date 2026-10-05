import Foundation

/// A built-in song (Ode to Joy, public domain) so the app works before any MIDI file is loaded.
enum DemoSong {
    static func make() -> Song {
        let secondsPerBeat = 60.0 / 100.0 // 100 BPM, 4/4
        let rightHand = 0
        let leftHand = 1

        // (note, beats); note names use middle C = C4 = 60.
        let melody: [(String, Double)] = [
            ("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1),
            ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
            ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1),
            ("E4", 1.5), ("D4", 0.5), ("D4", 2),
            ("E4", 1), ("E4", 1), ("F4", 1), ("G4", 1),
            ("G4", 1), ("F4", 1), ("E4", 1), ("D4", 1),
            ("C4", 1), ("C4", 1), ("D4", 1), ("E4", 1),
            ("D4", 1.5), ("C4", 0.5), ("C4", 2),
        ]
        // One chord per bar: (notes, beats).
        let chords: [([String], Double)] = [
            (["C3", "G3"], 4), (["G2", "D3"], 4), (["C3", "G3"], 4), (["G2", "D3"], 4),
            (["C3", "G3"], 4), (["G2", "D3"], 4), (["C3", "G3"], 4), (["G2", "D3"], 2), (["C3", "G3"], 2),
        ]

        var notes: [Song.RawNote] = []
        var beat = 0.0
        for (name, length) in melody {
            notes.append(Song.RawNote(pitch: pitch(name), velocity: 90, start: beat * secondsPerBeat,
                                      duration: length * secondsPerBeat * 0.95, partID: rightHand))
            beat += length
        }
        beat = 0
        for (names, length) in chords {
            for name in names {
                notes.append(Song.RawNote(pitch: pitch(name), velocity: 70, start: beat * secondsPerBeat,
                                          duration: length * secondsPerBeat * 0.95, partID: leftHand))
            }
            beat += length
        }

        let bars = Int(beat / 4)
        let measures = (0...bars).map { Double($0) * 4 * secondsPerBeat }
        return Song(title: "Ode to Joy (demo)", rawNotes: notes,
                    partNames: [rightHand: "Right hand", leftHand: "Left hand"],
                    measureStarts: measures, endTime: beat * secondsPerBeat)
    }

    /// "C4" -> 60, "F#3" -> 54
    private static func pitch(_ name: String) -> UInt8 {
        let octave = Int(String(name.last!))!
        let letter = String(name.dropLast())
        let index = Song.noteNames.firstIndex(of: letter)!
        return UInt8((octave + 1) * 12 + index)
    }
}
