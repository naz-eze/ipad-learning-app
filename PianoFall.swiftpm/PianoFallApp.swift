import SwiftUI

@main
struct PianoFallApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Wires the MIDI keyboard, the sound engine and playback together.
@Observable
final class AppModel {
    let sound: SoundEngine
    let midi = MIDIInputManager()
    let player: PlaybackEngine

    private(set) var midiDevices: [String] = []
    private(set) var soundFontName: String?
    var errorMessage: String?

    /// Play the MIDI keyboard's notes through the iPad (turn off if the keyboard has speakers).
    private(set) var monitorInput = true

    init() {
        let sound = SoundEngine()
        self.sound = sound
        player = PlaybackEngine(sound: sound)
        soundFontName = sound.soundFontName
        player.load(DemoSong.make())

        midi.onNoteOn = { [weak self] pitch, velocity in
            guard let self else { return }
            sound.inputNoteOn(pitch, velocity: velocity) // straight away, for low latency
            DispatchQueue.main.async { self.player.userNoteOn(pitch) }
        }
        midi.onNoteOff = { [weak self] pitch in
            guard let self else { return }
            sound.inputNoteOff(pitch)
            DispatchQueue.main.async { self.player.userNoteOff(pitch) }
        }
        midi.onSustain = { [weak self] value in
            self?.sound.inputSustain(value)
        }
        midi.onSourcesChanged = { [weak self] names in
            self?.midiDevices = names
        }
        midi.start()
    }

    func setMonitorInput(_ on: Bool) {
        monitorInput = on
        sound.monitorInput = on
    }

    /// On-screen keyboard touches behave like the MIDI keyboard.
    func screenKeyDown(_ pitch: UInt8) {
        sound.noteOn(pitch, velocity: 90, channel: SoundEngine.inputChannel)
        player.userNoteOn(pitch)
    }

    func screenKeyUp(_ pitch: UInt8) {
        sound.noteOff(pitch, channel: SoundEngine.inputChannel)
        player.userNoteOff(pitch)
    }

    func openMIDIFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let song = try MIDIFileParser.parse(data: data, title: url.deletingPathExtension().lastPathComponent)
            guard !song.notes.isEmpty else {
                errorMessage = "That MIDI file has no notes in it."
                return
            }
            player.load(song)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSoundFont(_ url: URL) {
        do {
            try sound.importSoundFont(from: url)
            soundFontName = sound.soundFontName
        } catch {
            errorMessage = "Couldn't load that SoundFont: \(error.localizedDescription)"
        }
    }
}
