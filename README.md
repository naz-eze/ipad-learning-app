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

## Running it (Mac + Xcode)
The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so it's never edited by hand and doesn't cause merge conflicts.

```sh
brew install xcodegen   # once
xcodegen                # creates PianoFall.xcodeproj (re-run after adding/removing files)
open PianoFall.xcodeproj
```

1. In Xcode: **PianoFall target → Signing & Capabilities → Team**, then choose your Apple ID.
   (Or set `DEVELOPMENT_TEAM` in `project.yml` once so it survives regenerating.)
2. Plug in the iPad, select it as the run destination and press **⌘R**.
   The first time, enable **Developer Mode** on the iPad (Settings → Privacy & Security).
3. **⌘U** runs the unit tests (MIDI parser, tempo map, keyboard layout).

A free Apple ID works, but the app must be reinstalled every 7 days. A paid developer
account ($99/yr) removes that limit and allows TestFlight.

## Hardware
- Use Apple's **Lightning to USB 3 Camera Adapter** (or a USB-C hub on newer iPads). The version
  with a charging port also powers keyboards that need USB power.
- If your keyboard has its own speakers, turn off ⚙️ → *Play my keyboard through iPad*.

## Code layout
| Folder | What's in it |
|---|---|
| `project.yml` | XcodeGen spec (targets, bundle ID, iPad-only, iOS 17+) |
| `PianoFall/Model/` | `Song`, a dependency-free Standard MIDI File parser (tempo changes, bars), demo song |
| `PianoFall/MIDI/` | CoreMIDI input that auto-connects keyboards as they're plugged in |
| `PianoFall/Audio/` | `AVAudioEngine` + sampler, SoundFont loading |
| `PianoFall/Playback/` | Clock, speed, looping, wait mode, scheduling of the notes the app plays |
| `PianoFall/Views/` | Control bar, scrubber, falling notes + keyboard (one `Canvas`) |
| `PianoFallTests/` | Unit tests |

## Ideas for next steps
- Chord names over the keyboard
- Scoring and accuracy stats
- Bluetooth MIDI pairing screen
- A song library with saved per-song settings (speed, loop, parts)
- Sheet music view
- A real app icon (`PianoFall/Assets.xcassets/AppIcon.appiconset`)
