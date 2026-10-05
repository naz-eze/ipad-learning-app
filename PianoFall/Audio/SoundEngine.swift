import AVFoundation
import AudioToolbox

/// Plays piano notes through the iPad speakers/headphones.
///
/// Uses Apple's built-in sampler. Without a SoundFont it sounds like a basic synth;
/// import a piano `.sf2` file (Settings menu) for a realistic piano.
final class SoundEngine {
    /// Channel used for notes the app plays from the song.
    static let songChannel: UInt8 = 0
    /// Channel used for notes you play, so the song never cuts off your notes.
    static let inputChannel: UInt8 = 1

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    /// When true, notes from the MIDI keyboard are played through the iPad.
    /// Turn off if your keyboard has its own speakers.
    var monitorInput = true

    private(set) var soundFontName: String?

    private static var soundFontURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("piano.sf2")
    }

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        configureSession()
        startEngine()
        if FileManager.default.fileExists(atPath: Self.soundFontURL.path) {
            try? loadSoundFont(Self.soundFontURL)
            soundFontName = UserDefaults.standard.string(forKey: "soundFontName") ?? "Custom SoundFont"
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.startEngine()
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: engine, queue: .main) { [weak self] _ in
            self?.startEngine()
        }
    }

    // MARK: Notes

    func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8 = SoundEngine.songChannel) {
        sampler.startNote(pitch, withVelocity: velocity, onChannel: channel)
    }

    func noteOff(_ pitch: UInt8, channel: UInt8 = SoundEngine.songChannel) {
        sampler.stopNote(pitch, onChannel: channel)
    }

    func inputNoteOn(_ pitch: UInt8, velocity: UInt8) {
        guard monitorInput else { return }
        noteOn(pitch, velocity: velocity, channel: Self.inputChannel)
    }

    func inputNoteOff(_ pitch: UInt8) {
        guard monitorInput else { return }
        noteOff(pitch, channel: Self.inputChannel)
    }

    func inputSustain(_ value: UInt8) {
        guard monitorInput else { return }
        sampler.sendController(64, withValue: value, onChannel: Self.inputChannel)
    }

    func allSongNotesOff() {
        for pitch in 0...127 {
            sampler.stopNote(UInt8(pitch), onChannel: Self.songChannel)
        }
    }

    // MARK: SoundFont

    /// Copies a user-picked `.sf2` file into the app and loads it.
    func importSoundFont(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let destination = Self.soundFontURL
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        try loadSoundFont(destination)
        soundFontName = url.deletingPathExtension().lastPathComponent
        UserDefaults.standard.set(soundFontName, forKey: "soundFontName")
    }

    private func loadSoundFont(_ url: URL) throws {
        try sampler.loadSoundBankInstrument(at: url,
                                            program: 0,
                                            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                            bankLSB: UInt8(kAUSampler_DefaultBankLSB))
    }

    // MARK: Engine

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the silent switch; a short buffer keeps latency low.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }
}
