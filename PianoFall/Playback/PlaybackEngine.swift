import Foundation
import Observation
import QuartzCore

/// What happens to each part of the song.
enum PartRole: String, CaseIterable, Identifiable {
    /// The app plays it for you.
    case auto
    /// You play it: shown but silent, and Wait mode waits for these notes.
    case you
    /// Hidden and silent.
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "App plays"
        case .you: return "I play"
        case .off: return "Hidden"
        }
    }
}

/// Drives song playback: the clock, speed, A–B looping, wait mode and which keys are down.
@Observable
final class PlaybackEngine {
    private(set) var song: Song = .empty
    private(set) var roles: [Int: PartRole] = [:]

    /// Song position in seconds. Negative during the lead-in before the first note.
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    /// Playback speed: 1.0 = 100%.
    private(set) var rate: Double = 1.0
    static let minRate = 0.1
    static let maxRate = 1.5

    private(set) var loopStart: Double?
    private(set) var loopEnd: Double?
    var isLooping: Bool {
        guard let start = loopStart, let end = loopEnd else { return false }
        return end > start
    }

    /// When on, the song pauses at each of your notes until you play them.
    private(set) var waitMode = false
    /// True while Wait mode is holding the song for you.
    private(set) var isWaiting = false
    /// Pitches Wait mode is still waiting for.
    private(set) var pendingPitches: Set<UInt8> = []

    /// Keys currently held on the MIDI keyboard (or touched on screen).
    private(set) var pressedKeys: Set<UInt8> = []

    /// How long the run-up is before the first note.
    let leadIn: Double = 2.0

    private let sound: SoundEngine

    // Audio scheduling
    private struct AudioEvent {
        var time: Double
        var pitch: UInt8
        var velocity: UInt8
        var partID: Int
        var isNoteOn: Bool
    }
    @ObservationIgnored private var audioEvents: [AudioEvent] = []
    @ObservationIgnored private var nextAudioEvent = 0
    @ObservationIgnored private var soundingNotes: [UInt8: Int] = [:] // pitch -> count, so overlapping notes end correctly

    // Wait mode
    private struct Chord {
        var time: Double
        var pitches: Set<UInt8>
    }
    @ObservationIgnored private var chords: [Chord] = []
    @ObservationIgnored private var nextChord = 0
    /// Song time each key was last pressed, so slightly early presses still count.
    @ObservationIgnored private var lastPressTime: [UInt8: Double] = [:]
    private let earlyPressWindow = 0.35

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrameTimestamp: CFTimeInterval?

    init(sound: SoundEngine) {
        self.sound = sound
    }

    // MARK: - Loading

    func load(_ song: Song) {
        pause()
        self.song = song
        roles = Dictionary(uniqueKeysWithValues: song.parts.map { ($0.id, PartRole.auto) })
        loopStart = nil
        loopEnd = nil

        audioEvents = song.notes.flatMap { note in
            [AudioEvent(time: note.start, pitch: note.pitch, velocity: note.velocity, partID: note.partID, isNoteOn: true),
             AudioEvent(time: note.end, pitch: note.pitch, velocity: 0, partID: note.partID, isNoteOn: false)]
        }
        // Note-offs before note-ons at the same instant, so repeated notes retrigger.
        audioEvents.sort { $0.time != $1.time ? $0.time < $1.time : (!$0.isNoteOn && $1.isNoteOn) }

        rolesChanged()
        seek(to: -leadIn)
    }

    func role(of partID: Int) -> PartRole {
        roles[partID] ?? .auto
    }

    func setRole(_ role: PartRole, for partID: Int) {
        roles[partID] = role
        rolesChanged()
    }

    private func rolesChanged() {
        silenceSong()
        // Group "you play" notes that start together into chords for Wait mode.
        var built: [Chord] = []
        for note in song.notes where role(of: note.partID) == .you {
            if let last = built.last, note.start - last.time < 0.04 {
                built[built.count - 1].pitches.insert(note.pitch)
            } else {
                built.append(Chord(time: note.start, pitches: [note.pitch]))
            }
        }
        chords = built
        resetWaitState()
    }

    // MARK: - Transport

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        if currentTime >= song.duration {
            seek(to: isLooping ? loopStart! : -leadIn)
        }
        isPlaying = true
        lastFrameTimestamp = nil
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkTarget { [weak self] link in self?.frame(link) },
                                     selector: #selector(DisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func pause() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        silenceSong()
    }

    /// Back to the start of the loop, or the start of the song.
    func restart() {
        seek(to: isLooping ? loopStart! : -leadIn)
    }

    func seek(to time: Double) {
        silenceSong()
        currentTime = min(max(time, -leadIn), song.duration)
        nextAudioEvent = firstAudioEvent(atOrAfter: currentTime)
        resetWaitState()
    }

    func changeRate(by step: Double) {
        setRate(rate + step)
    }

    func setRate(_ newRate: Double) {
        rate = min(max((newRate * 100).rounded() / 100, Self.minRate), Self.maxRate)
    }

    func setWaitMode(_ on: Bool) {
        waitMode = on
        if on && !roles.values.contains(.you) {
            // Nothing is marked "I play" yet, so assume you're playing everything.
            for part in song.parts where roles[part.id] != .off { roles[part.id] = .you }
            rolesChanged()
        }
        resetWaitState()
    }

    // MARK: - Looping

    /// Sets the loop start at the bar the song is currently in.
    func setLoopStart() {
        loopStart = song.measureStart(atOrBefore: max(currentTime, 0))
        if let end = loopEnd, end <= loopStart! { loopEnd = nil }
    }

    /// Sets the loop end at the end of the bar the song is currently in.
    func setLoopEnd() {
        let end = song.measureStart(after: max(currentTime, 0))
        if let start = loopStart, end <= start { return }
        loopEnd = end
        if loopStart == nil { loopStart = song.measureStart(atOrBefore: max(currentTime, 0)) }
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
    }

    // MARK: - Input

    func userNoteOn(_ pitch: UInt8) {
        pressedKeys.insert(pitch)
        lastPressTime[pitch] = currentTime
        if isWaiting {
            pendingPitches.remove(pitch)
            if pendingPitches.isEmpty {
                isWaiting = false
                nextChord += 1
            }
        }
    }

    func userNoteOff(_ pitch: UInt8) {
        pressedKeys.remove(pitch)
    }

    // MARK: - Clock

    private func frame(_ link: CADisplayLink) {
        defer { lastFrameTimestamp = link.timestamp }
        guard isPlaying, let last = lastFrameTimestamp else { return }
        let elapsed = min(link.timestamp - last, 0.1) // don't jump after a hiccup
        advance(by: elapsed * rate)
    }

    private func advance(by delta: Double) {
        if isWaiting { return }
        var newTime = currentTime + delta

        if waitMode, let holdAt = waitPoint(upTo: newTime) {
            newTime = holdAt
        }

        if isLooping, let start = loopStart, let end = loopEnd, newTime >= end {
            playAudioEvents(upTo: end)
            seek(to: start)
            return
        }

        playAudioEvents(upTo: newTime)
        currentTime = newTime

        if currentTime >= song.duration {
            pause()
        }
    }

    /// If a chord you must play is reached before `time`, returns the time to hold at.
    private func waitPoint(upTo time: Double) -> Double? {
        while nextChord < chords.count && chords[nextChord].time <= time {
            let chord = chords[nextChord]
            let pending = chord.pitches.filter { pitch in
                guard let pressed = lastPressTime[pitch] else { return true }
                return pressed < chord.time - earlyPressWindow
            }
            if pending.isEmpty {
                nextChord += 1 // already played (slightly early)
                continue
            }
            pendingPitches = pending
            isWaiting = true
            return chord.time
        }
        return nil
    }

    private func resetWaitState() {
        isWaiting = false
        pendingPitches = []
        lastPressTime = [:]
        var low = 0
        var high = chords.count
        while low < high {
            let mid = (low + high) / 2
            if chords[mid].time < currentTime - 0.001 { low = mid + 1 } else { high = mid }
        }
        nextChord = low
    }

    // MARK: - Audio

    private func playAudioEvents(upTo time: Double) {
        while nextAudioEvent < audioEvents.count && audioEvents[nextAudioEvent].time <= time {
            let event = audioEvents[nextAudioEvent]
            nextAudioEvent += 1
            if event.isNoteOn {
                guard role(of: event.partID) == .auto else { continue }
                if soundingNotes[event.pitch, default: 0] > 0 {
                    sound.noteOff(event.pitch) // retrigger
                }
                sound.noteOn(event.pitch, velocity: event.velocity)
                soundingNotes[event.pitch, default: 0] += 1
            } else if let count = soundingNotes[event.pitch], count > 0, role(of: event.partID) == .auto {
                soundingNotes[event.pitch] = count - 1
                if count == 1 { sound.noteOff(event.pitch) }
            }
        }
    }

    private func silenceSong() {
        if !soundingNotes.isEmpty {
            sound.allSongNotesOff()
            soundingNotes = [:]
        }
    }

    private func firstAudioEvent(atOrAfter time: Double) -> Int {
        var low = 0
        var high = audioEvents.count
        while low < high {
            let mid = (low + high) / 2
            if audioEvents[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// CADisplayLink needs an NSObject target; this forwards each frame to a closure.
private final class DisplayLinkTarget: NSObject {
    private let callback: (CADisplayLink) -> Void

    init(_ callback: @escaping (CADisplayLink) -> Void) {
        self.callback = callback
    }

    @objc func tick(_ link: CADisplayLink) {
        callback(link)
    }
}
