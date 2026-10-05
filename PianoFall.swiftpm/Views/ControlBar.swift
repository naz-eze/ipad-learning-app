import SwiftUI

/// Top bar: songs, transport, speed, A–B loop, wait mode and settings.
struct ControlBar: View {
    @Environment(AppModel.self) private var model

    @Binding var fitKeyboard: Bool
    @Binding var showNoteNames: Bool
    @Binding var visibleSeconds: Double
    var openMIDIFile: () -> Void
    var openSoundFont: () -> Void

    var body: some View {
        let player = model.player

        HStack(spacing: 18) {
            Menu {
                Button("Open MIDI file…", systemImage: "folder", action: openMIDIFile)
                Button("Ode to Joy (demo)", systemImage: "music.note") { player.load(DemoSong.make()) }
            } label: {
                Image(systemName: "music.note.list").font(.title2)
            }

            Text(player.song.title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)

            Spacer(minLength: 0)

            // Transport
            Button { player.restart() } label: {
                Image(systemName: "backward.end.fill").font(.title2)
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .frame(width: 44)
            }

            divider

            // Speed
            HStack(spacing: 8) {
                Button { player.changeRate(by: -0.05) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                VStack(spacing: 0) {
                    Text("\(Int((player.rate * 100).rounded()))%")
                        .font(.headline.monospacedDigit())
                    Text("speed").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 52)
                .onTapGesture(count: 2) { player.setRate(1.0) }
                Button { player.changeRate(by: 0.05) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
            }

            divider

            // A–B loop (snaps to bars)
            HStack(spacing: 8) {
                Image(systemName: "repeat")
                    .foregroundStyle(player.isLooping ? Color.yellow : Color.secondary)
                Button("A") { player.setLoopStart() }
                    .font(.headline)
                    .foregroundStyle(player.loopStart != nil ? Color.yellow : Color.accentColor)
                Button("B") { player.setLoopEnd() }
                    .font(.headline)
                    .foregroundStyle(player.loopEnd != nil ? Color.yellow : Color.accentColor)
                Button { player.clearLoop() } label: { Image(systemName: "xmark.circle.fill") }
                    .disabled(player.loopStart == nil && player.loopEnd == nil)
            }

            divider

            Button { player.setWaitMode(!player.waitMode) } label: {
                Label("Wait", systemImage: "hand.raised.fill")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(player.waitMode ? Color.accentColor.opacity(0.3) : Color.clear, in: Capsule())
            }

            settingsMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
    }

    private var divider: some View {
        Rectangle().fill(Color(white: 0.3)).frame(width: 1, height: 28)
    }

    private var settingsMenu: some View {
        let player = model.player
        return Menu {
            Section("Parts – who plays what") {
                ForEach(player.song.parts) { part in
                    Picker(part.name, selection: Binding(get: { player.role(of: part.id) },
                                                         set: { player.setRole($0, for: part.id) })) {
                        ForEach(PartRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section("Display") {
                Toggle("Fit keyboard to song", isOn: $fitKeyboard)
                Toggle("Show note names", isOn: $showNoteNames)
                Picker("Note spacing", selection: $visibleSeconds) {
                    Text("Wide").tag(5.0)
                    Text("Normal").tag(3.0)
                    Text("Tight").tag(2.0)
                }
                .pickerStyle(.menu)
            }
            Section("Sound") {
                Toggle("Play my keyboard through iPad",
                       isOn: Binding(get: { model.monitorInput }, set: { model.setMonitorInput($0) }))
                Button("Load piano SoundFont (.sf2)…", systemImage: "pianokeys", action: openSoundFont)
                Text("Sound: \(model.soundFontName ?? "Built-in (basic)")")
            }
            Section("MIDI keyboards") {
                if model.midiDevices.isEmpty {
                    Text("None connected")
                } else {
                    ForEach(model.midiDevices, id: \.self) { Text($0) }
                }
            }
        } label: {
            Image(systemName: "gearshape.fill").font(.title2)
        }
    }
}
