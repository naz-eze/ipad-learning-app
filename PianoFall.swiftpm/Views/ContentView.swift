import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @AppStorage("fitKeyboard") private var fitKeyboard = true
    @AppStorage("showNoteNames") private var showNoteNames = true
    @AppStorage("visibleSeconds") private var visibleSeconds = 3.0

    private enum ImportKind { case midi, soundFont }
    @State private var importKind = ImportKind.midi
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(fitKeyboard: $fitKeyboard,
                       showNoteNames: $showNoteNames,
                       visibleSeconds: $visibleSeconds,
                       openMIDIFile: { present(.midi) },
                       openSoundFont: { present(.soundFont) })
            ScrubberView()
            PianoRollView(fitToSong: fitKeyboard, showNoteNames: showNoteNames, visibleSeconds: visibleSeconds)
                .overlay(alignment: .top) {
                    if model.player.isWaiting {
                        Label("Waiting for you…", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
        .background(Color.black)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: allowedTypes) { result in
            guard case .success(let url) = result else { return }
            switch importKind {
            case .midi: model.openMIDIFile(url)
            case .soundFont: model.importSoundFont(url)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var allowedTypes: [UTType] {
        switch importKind {
        case .midi:
            return [.midi] + ["mid", "midi", "kar"].compactMap { UTType(filenameExtension: $0) }
        case .soundFont:
            return [UTType(filenameExtension: "sf2") ?? .data]
        }
    }

    private func present(_ kind: ImportKind) {
        importKind = kind
        showImporter = true
    }
}

/// Song progress, loop region and seeking.
struct ScrubberView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let duration = max(player.song.duration, 0.1)

        HStack(spacing: 12) {
            Text(Self.format(player.currentTime))
                .font(.caption.monospacedDigit())
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.25)).frame(height: 6)
                    Capsule().fill(Color.green).frame(width: Self.x(player.currentTime, duration, width), height: 6)
                    if let start = player.loopStart, let end = player.loopEnd {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.yellow.opacity(0.35))
                            .frame(width: max(2, Self.x(end, duration, width) - Self.x(start, duration, width)), height: 16)
                            .offset(x: Self.x(start, duration, width))
                    }
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: Self.x(player.currentTime, duration, width) - 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    player.seek(to: Double(value.location.x / max(width, 1)) * duration)
                })
            }
            .frame(height: 24)
            Text(Self.format(duration))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(white: 0.12))
    }

    private static func x(_ time: Double, _ duration: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(time / duration, 0), 1)) * width
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
