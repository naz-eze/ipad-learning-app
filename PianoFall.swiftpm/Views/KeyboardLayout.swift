import SwiftUI

/// Maps MIDI pitches to horizontal positions on the on-screen piano,
/// shared by the falling notes and the keyboard so they line up exactly.
struct KeyboardLayout {
    let lowest: Int
    let highest: Int
    let width: CGFloat

    private let whiteKeyCount: Int

    init(range: ClosedRange<Int>, width: CGFloat) {
        lowest = range.lowerBound
        highest = range.upperBound
        self.width = width
        whiteKeyCount = (range.lowerBound...range.upperBound).filter { !Self.isBlack($0) }.count
    }

    var whiteKeyWidth: CGFloat { width / CGFloat(max(whiteKeyCount, 1)) }
    var blackKeyWidth: CGFloat { whiteKeyWidth * 0.6 }

    static func isBlack(_ pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(pitch % 12)
    }

    /// Number of white keys to the left of `pitch`.
    private func whiteKeysBefore(_ pitch: Int) -> Int {
        var count = 0
        var key = lowest
        while key < pitch {
            if !Self.isBlack(key) { count += 1 }
            key += 1
        }
        return count
    }

    /// Left edge and width of the key for `pitch`.
    func keyFrame(_ pitch: Int) -> (x: CGFloat, width: CGFloat) {
        let whitesBefore = CGFloat(whiteKeysBefore(pitch))
        if Self.isBlack(pitch) {
            // Black keys sit centred on the line between two white keys.
            return (whitesBefore * whiteKeyWidth - blackKeyWidth / 2, blackKeyWidth)
        }
        return (whitesBefore * whiteKeyWidth, whiteKeyWidth)
    }

    /// The key under a touch point. `y` is relative to the top of the keyboard.
    func pitch(at point: CGPoint, blackKeyHeight: CGFloat) -> Int? {
        guard point.x >= 0, point.x < width else { return nil }
        if point.y < blackKeyHeight {
            for pitch in lowest...highest where Self.isBlack(pitch) {
                let frame = keyFrame(pitch)
                if point.x >= frame.x && point.x < frame.x + frame.width { return pitch }
            }
        }
        let whiteIndex = Int(point.x / whiteKeyWidth)
        var count = 0
        for pitch in lowest...highest where !Self.isBlack(pitch) {
            if count == whiteIndex { return pitch }
            count += 1
        }
        return nil
    }

    /// A keyboard range that fits the song with a little room either side
    /// (at least three octaves, edges on white keys), or the full 88 keys.
    static func range(for song: Song, fitToSong: Bool) -> ClosedRange<Int> {
        let fullRange = 21...108
        guard fitToSong, !song.notes.isEmpty else { return fullRange }
        var low = Int(song.lowestPitch) - 2
        var high = Int(song.highestPitch) + 2
        while high - low < 36 {
            low -= 1
            high += 1
        }
        low = max(low, fullRange.lowerBound)
        high = min(high, fullRange.upperBound)
        if isBlack(low) { low -= 1 }
        if isBlack(high) { high += 1 }
        return low...high
    }
}

/// Colours for parts, in order: highest part (usually right hand) first.
enum PartPalette {
    static let colors: [Color] = [
        Color(red: 0.55, green: 0.85, blue: 0.25), // green – right hand
        Color(red: 0.45, green: 0.70, blue: 0.95), // blue – left hand
        Color(red: 0.98, green: 0.65, blue: 0.25),
        Color(red: 0.80, green: 0.50, blue: 0.95),
        Color(red: 0.95, green: 0.45, blue: 0.60),
        Color(red: 0.35, green: 0.85, blue: 0.80),
    ]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }

    /// Wrong/extra notes you play.
    static let wrongNote = Color(red: 0.95, green: 0.35, blue: 0.30)
}
