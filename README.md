# PianoFall

A Synthesia-style piano learning app for iPad. Connect a MIDI keyboard, load a MIDI file
and play along to falling notes.

## Features
- **MIDI keyboard input** through the Lightning/USB-C camera adapter (any class-compliant USB MIDI keyboard)
- **Load any `.mid` file** from the Files app (plus a built-in *Ode to Joy* demo)
- **Falling notes** coloured per hand (green = right/higher part, blue = left/lower), with note names
- **On-screen keyboard** lights up the song's notes and the keys you press. You can also tap it to play.
- **Speed control** from 10% to 150% in 5% steps. Double-tap the % to reset to 100%.
- **A–B loop** to repeat a section. A and B snap to bar lines.
- **Wait mode**: the song pauses until you play the right notes
- **Parts**: choose who plays each part (*App plays* / *I play* / *Hidden*) in ⚙️
- **Scrub** by dragging up/down on the falling notes or along the progress bar
- **Realistic piano**: load any piano `.sf2` SoundFont (⚙️ → Sound). The built-in sound is basic.

## Running it
`PianoFall.swiftpm` is a Swift Playgrounds app package.

**On the iPad (no Mac needed):**
1. Install **Swift Playgrounds** from the App Store.
2. Get this folder onto the iPad. For example, download the repo as a ZIP on GitHub, open it in Files and unzip it.
3. Open `PianoFall.swiftpm` in Swift Playgrounds and press ▶︎ Run.

**On a Mac:** open `PianoFall.swiftpm` in Xcode, pick your iPad as the run destination, then Run.
You'll need to choose a development team under Signing.

## Hardware
- Use Apple's **Lightning to USB 3 Camera Adapter** (or a USB-C hub on newer iPads). The version
  with a charging port also powers keyboards that need USB power.
- If your keyboard has its own speakers, turn off ⚙️ → *Play my keyboard through iPad*.

## Code layout
| Folder | What's in it |
|---|---|
| `Model/` | `Song`, a dependency-free Standard MIDI File parser (tempo changes, bars), demo song |
| `MIDI/` | CoreMIDI input that auto-connects keyboards as they're plugged in |
| `Audio/` | `AVAudioEngine` + sampler, SoundFont loading |
| `Playback/` | Clock, speed, looping, wait mode, scheduling of the notes the app plays |
| `Views/` | Control bar, scrubber, falling notes + keyboard (one `Canvas`) |

## Ideas for next steps
- Chord names over the keyboard
- Scoring and accuracy stats
- Bluetooth MIDI pairing screen
- A song library with saved per-song settings (speed, loop, parts)
- Sheet music view
