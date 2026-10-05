import SwiftUI

/// The falling notes and the on-screen keyboard.
///
/// Drag up/down on the notes to scrub. Touch the keyboard to play without a MIDI keyboard.
struct PianoRollView: View {
    @Environment(AppModel.self) private var model
    var fitToSong: Bool
    var showNoteNames: Bool
    /// Seconds of music visible above the keyboard (bigger = notes fall slower).
    var visibleSeconds: Double

    @State private var touchedKey: Int?
    @State private var scrubStartTime: Double?

    var body: some View {
        let player = model.player
        let song = player.song

        GeometryReader { geometry in
            let keyboardHeight = min(max(geometry.size.height * 0.2, 90), 200)
            let rollHeight = geometry.size.height - keyboardHeight
            let layout = KeyboardLayout(range: KeyboardLayout.range(for: song, fitToSong: fitToSong),
                                        width: geometry.size.width)
            let renderer = PianoRollRenderer(
                song: song,
                time: player.currentTime,
                roles: player.roles,
                pressed: player.pressedKeys,
                loopStart: player.loopStart,
                loopEnd: player.loopEnd,
                layout: layout,
                rollHeight: rollHeight,
                keyboardHeight: keyboardHeight,
                visibleSeconds: visibleSeconds,
                showNoteNames: showNoteNames
            )

            ZStack(alignment: .top) {
                Canvas { context, size in
                    renderer.draw(in: &context, size: size)
                }

                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(height: rollHeight)
                        .gesture(scrubGesture(pointsPerSecond: rollHeight / visibleSeconds))
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(height: keyboardHeight)
                        .gesture(keyboardGesture(layout: layout, keyboardHeight: keyboardHeight))
                }
            }
        }
    }

    private func scrubGesture(pointsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let player = model.player
                if scrubStartTime == nil { scrubStartTime = player.currentTime }
                // Dragging down pulls the notes towards the keyboard, i.e. forwards in time.
                player.seek(to: scrubStartTime! + Double(value.translation.height / pointsPerSecond))
            }
            .onEnded { _ in scrubStartTime = nil }
    }

    private func keyboardGesture(layout: KeyboardLayout, keyboardHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let key = layout.pitch(at: value.location, blackKeyHeight: keyboardHeight * PianoRollRenderer.blackKeyRatio)
                guard key != touchedKey else { return }
                if let old = touchedKey { model.screenKeyUp(UInt8(old)) }
                if let key { model.screenKeyDown(UInt8(key)) }
                touchedKey = key
            }
            .onEnded { _ in
                if let old = touchedKey { model.screenKeyUp(UInt8(old)) }
                touchedKey = nil
            }
    }
}

/// Draws one frame of the piano roll. A plain value so the Canvas only sees a snapshot of state.
struct PianoRollRenderer {
    static let blackKeyRatio: CGFloat = 0.62

    let song: Song
    let time: Double
    let roles: [Int: PartRole]
    let pressed: Set<UInt8>
    let loopStart: Double?
    let loopEnd: Double?
    let layout: KeyboardLayout
    let rollHeight: CGFloat
    let keyboardHeight: CGFloat
    let visibleSeconds: Double
    let showNoteNames: Bool

    private var pointsPerSecond: CGFloat { rollHeight / visibleSeconds }

    private func y(_ songTime: Double) -> CGFloat {
        rollHeight - CGFloat(songTime - time) * pointsPerSecond
    }

    private func role(_ partID: Int) -> PartRole {
        roles[partID] ?? .auto
    }

    private func color(forPart partID: Int) -> Color {
        PartPalette.color(song.part(partID)?.colorIndex ?? 0)
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let rollRect = CGRect(x: 0, y: 0, width: size.width, height: rollHeight)
        context.fill(Path(rollRect), with: .color(Color(white: 0.16)))

        drawGuides(in: &context, rollRect: rollRect)
        drawNotes(in: &context, rollRect: rollRect)
        drawKeyboard(in: &context, width: size.width)
    }

    // MARK: Background

    private func drawGuides(in context: inout GraphicsContext, rollRect: CGRect) {
        // Vertical lines at every C (brighter) and F, like a keyboard's octave groups.
        for pitch in layout.lowest...layout.highest where pitch % 12 == 0 || pitch % 12 == 5 {
            let x = layout.keyFrame(pitch).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: rollHeight))
            context.stroke(line, with: .color(.white.opacity(pitch % 12 == 0 ? 0.22 : 0.09)), lineWidth: 1)
        }

        // Loop region.
        if let start = loopStart, let end = loopEnd, end > start {
            let band = CGRect(x: 0, y: y(end), width: rollRect.width, height: y(start) - y(end)).intersection(rollRect)
            if !band.isNull {
                context.fill(Path(band), with: .color(Color.yellow.opacity(0.06)))
            }
            for edge in [start, end] where y(edge) >= 0 && y(edge) <= rollHeight {
                context.fill(Path(CGRect(x: 0, y: y(edge) - 1, width: rollRect.width, height: 2)),
                             with: .color(Color.yellow.opacity(0.7)))
            }
        }

        // Bar lines.
        for barTime in song.measureStarts where barTime >= time && barTime <= time + visibleSeconds {
            context.fill(Path(CGRect(x: 0, y: y(barTime), width: rollRect.width, height: 1)),
                         with: .color(.white.opacity(0.12)))
        }
    }

    // MARK: Falling notes

    private func drawNotes(in context: inout GraphicsContext, rollRect: CGRect) {
        let indices = song.noteIndices(overlapping: time, time + visibleSeconds)
        // White-key notes first so black-key notes draw on top of them.
        for blackPass in [false, true] {
            for index in indices {
                let note = song.notes[index]
                let pitch = Int(note.pitch)
                guard KeyboardLayout.isBlack(pitch) == blackPass,
                      pitch >= layout.lowest, pitch <= layout.highest,
                      role(note.partID) != .off else { continue }

                let top = y(note.end)
                let bottom = y(note.start)
                guard bottom > 0, top < rollHeight else { continue }

                let key = layout.keyFrame(pitch)
                let inset: CGFloat = blackPass ? 0.5 : 1.5
                let rect = CGRect(x: key.x + inset, y: top, width: key.width - inset * 2, height: bottom - top)
                    .intersection(rollRect)
                guard !rect.isNull, rect.height > 0 else { continue }

                let shape = RoundedRectangle(cornerRadius: min(4, rect.width / 3)).path(in: rect)
                context.fill(shape, with: .color(color(forPart: note.partID)))
                if blackPass {
                    context.fill(shape, with: .color(.black.opacity(0.28)))
                }
                context.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 1)

                if showNoteNames && rect.height > 18 && rect.width > 9 {
                    let label = Text(Song.noteName(note.pitch))
                        .font(.system(size: min(13, key.width * 0.75), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - 3), anchor: .bottom)
                }
            }
        }
    }

    // MARK: Keyboard

    private func drawKeyboard(in context: inout GraphicsContext, width: CGFloat) {
        let top = rollHeight
        let blackHeight = keyboardHeight * Self.blackKeyRatio

        // Which keys light up: song notes sounding now, and keys you're pressing.
        // pitch -> (part colour, whether it's one of your notes)
        var expected: [Int: (color: Color, isYours: Bool)] = [:]
        for index in song.noteIndices(overlapping: time, time) {
            let note = song.notes[index]
            guard note.start <= time + 0.001, note.end > time else { continue }
            switch role(note.partID) {
            case .auto: expected[Int(note.pitch)] = (color(forPart: note.partID), false)
            case .you: expected[Int(note.pitch)] = (color(forPart: note.partID), true)
            case .off: break
            }
        }
        func keyColor(_ pitch: Int, base: Color) -> Color {
            if pressed.contains(UInt8(pitch)) {
                if let hit = expected[pitch] { return hit.color }
                return Color(red: 1.0, green: 0.82, blue: 0.3) // you're playing a note the song isn't
            }
            guard let hit = expected[pitch] else { return base }
            // Your notes show faintly until you press them.
            return hit.isYours ? hit.color.opacity(0.5) : hit.color
        }

        context.fill(Path(CGRect(x: 0, y: top, width: width, height: keyboardHeight)), with: .color(.black))

        for pitch in layout.lowest...layout.highest where !KeyboardLayout.isBlack(pitch) {
            let key = layout.keyFrame(pitch)
            let rect = CGRect(x: key.x + 0.5, y: top, width: key.width - 1, height: keyboardHeight - 1)
            context.fill(RoundedRectangle(cornerRadius: 3).path(in: rect), with: .color(keyColor(pitch, base: .white)))
            if pitch % 12 == 0 && key.width > 12 {
                let label = Text("C\(pitch / 12 - 1)").font(.system(size: min(11, key.width * 0.5)))
                    .foregroundColor(.gray)
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - 4), anchor: .bottom)
            }
        }
        for pitch in layout.lowest...layout.highest where KeyboardLayout.isBlack(pitch) {
            let key = layout.keyFrame(pitch)
            let rect = CGRect(x: key.x, y: top, width: key.width, height: blackHeight)
            context.fill(RoundedRectangle(cornerRadius: 2).path(in: rect),
                         with: .color(keyColor(pitch, base: Color(white: 0.12))))
        }

        // Red felt strip along the top of the keys.
        context.fill(Path(CGRect(x: 0, y: top, width: width, height: 3)), with: .color(Color(red: 0.75, green: 0.1, blue: 0.1)))
    }
}
