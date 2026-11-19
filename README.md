# KeySight

**Learn piano on your own piano, in mixed reality.** KeySight is an open-source app for the
Valve **Steam Frame** that runs natively on the headset (Godot 4.6, Linux ARM64, OpenXR). It
reads your digital piano over USB-MIDI and uses passthrough to drop falling notes straight onto
your real keys.

![Menu](docs/menu.png)

> **Status: early.** This is a hobby project that one person has tested on one setup
> (Steam Frame + Yamaha Clavinova CLP-230). Expect rough edges. Feedback and pull requests are
> very welcome.

## Features

- **Falling notes on your real keys**, in the style of Synthesia. A bar's bottom edge reaches
  the key exactly when you should play it, and its length is the note length. Notes are drawn
  as glowing neon tiles (left hand cyan, right hand violet) with a soft light beam towards the
  key and a glow where they land; edges are anti-aliased (MSAA). The target key lights up just
  before the note arrives, then turns green when you hit it and red for a wrong key.
- **Sheet music view** (optional): a grand staff on the panel above the keys, where a paper
  score would stand. Note values with stems and flags, clefs, key signature (from the file or
  estimated), time signature and bar lines, a cursor and a page turn per system. Played notes
  turn green, missed ones red. Choose falling notes, score, or both with *View*
  (Falling notes / Score / Both); with both, the falling notes get shorter so they don't touch
  the score. The panel's height and tilt can be adjusted under *Adjust*. Notation from MIDI
  is an approximation: quantised to 16ths, no ties or beams, simplified rests.
- **Wait mode**: the song pauses at every chord until you've played all of its notes. The clock
  starts on your first correct key.
- **Play-along mode** at 30-150 % tempo, with timing measured per note.
- **Practise one hand**: the other hand's notes are shown dimmed and aren't required.
- **Your own MIDI files** (`.mid`, format 0 and 1). Hands are taken from the two note tracks,
  or split at middle C if there's only one track.
- **Feedback**: hit/wrong/missed per note, plus a results card with accuracy, timing, the
  hardest passage and one practice tip. A full report covers early/late tendency, swapped
  keys, left vs right hand, black vs white keys, note release, dynamics and pedalling.
  Each song keeps your best score.
- **Calibration by touching keys**: press a few real keys with the controller tip, and since
  MIDI tells the app exactly which key it was, a least-squares fit lines up all 88 keys,
  including your piano's exact width. You can fine-tune the result with the thumbsticks.
- **Refresh rate** 72 / 90 / 120 Hz (button *Hz*), holding a steady 90 fps with all effects.
- **Tested**: a self-test (MIDI parsing, calibration maths, scoring, notation, a regression test
  for MIDI dropping out) plus a [hardware checklist](docs/HARDWARE_TEST.md) for the headset.
- **Loop a passage**: press *Loop* in the lesson bar to mark the start bar, again to mark
  the end bar, and the passage repeats with a one-bar lead-in. Each pass is scored, so you
  can watch it improve; press *Loop off* to carry on.
- **Metronome and count-in** (*Click* next to Tempo): *Off*, *Count-in* (one bar before
  the first note and before each loop pass) or *On*. The click follows the tempo setting, accents
  beat 1, and a beat indicator in the lesson bar shows where you are in the bar.
- **Hands-free controls**: the middle (sostenuto) pedal starts and pauses. In the menu, the
  lowest A and B keys choose the previous or next song.

| Lesson (falling notes + score) | Score view |
|---|---|
| ![Lesson: neon falling notes with the score above](docs/lesson.png) | ![Score view](docs/score.png) |

![Results card](docs/results.png)

*Screenshots are from the desktop build. On the headset you see your room and piano behind the overlay.*

## Requirements

- Valve Steam Frame with **Developer Mode** enabled (to copy files over SSH)
- A digital piano or keyboard with **USB-MIDI** (class compliant), plus a cable to the headset's
  USB-C port. Some full-speed (USB 1.1) instruments only work through a small USB hub.
- To build: [Godot 4.6.2](https://godotengine.org/download/archive/4.6.2-stable/) with its export
  templates (they include `linux_release.arm64`)

## Build

```bash
cd step2-leren
godot --headless --path . --import
godot --headless --path . -- --selftest            # MIDI parsing, calibration maths, scoring
godot --path . -- --demo --song 3 --nowait           # desktop demo that plays by itself
godot --headless --path . --export-release "Steam Frame Arm64"
# -> step2-leren/build/frame-arm64/KeySight.arm64 (a single file with the game data inside)
```

## Install on the headset

1. On the Frame, turn on Developer Mode and set a password, then enable SSH.
2. Copy the binary and make it executable:
   ```bash
   ssh steamos@<headset-ip> "mkdir -p ~/keysight/songs"
   scp step2-leren/build/frame-arm64/KeySight.arm64 steamos@<headset-ip>:keysight/
   ssh steamos@<headset-ip> "chmod +x ~/keysight/KeySight.arm64"
   ```
   Optionally copy `step2-leren/tools/keysight.sh` next to it (`chmod +x`) and start that
   instead: it writes a log, installs staged updates and applies the *Hz* choice.
3. Add it (or `keysight.sh`) to Steam as a **non-Steam game**, for example with the SteamOS Devkit Client
   (Title Upload, start command `KeySight.arm64`), or from desktop mode. KeySight runs fine
   without a Steam Linux Runtime.
4. Plug the piano into the headset and start KeySight from your library.

**Your own songs:** put `.mid` files in a `songs/` folder next to `KeySight.arm64`, or in
`~/.local/share/KeySight/songs/`. Settings, calibration, scores and reports are stored in
`~/.local/share/KeySight/`.

## Controls

| Where | Action |
|---|---|
| Controller | Point at the panel and pull the trigger. The stick scrolls the song list. A/X start or pause, B/Y restart. |
| Menu options | *Mode* (wait / play along), *Hands* (both / left / right), *Tempo*, *View* (falling notes / score / both), *Hz* (72 / 90 / 120), *Keys* (how visible the virtual keys are), *Passthrough* |
| Piano only | Middle pedal starts, pauses or restarts. In the menu, the lowest A selects the previous song and the lowest B the next one. |
| Desktop (testing) | Mouse on the panel, Space, arrow keys (song/tempo), W, H, R, B (-5 s), K, P, L (loop), M (metronome), Esc |

**Calibration:** press *Calibrate*, hold a controller and use the yellow dot to press real keys one
at a time, near their front edge: first far left, then far right, then a few in the middle.
Then press *Done*. Use *Adjust* to nudge the keyboard with the sticks (right stick: sideways
and depth, left stick: height and rotation), and to move the panel higher or lower or tilt it.

## Known limits

- **No hand tracking** on the Frame (yet), so you put the controllers down while you play.
- **Refresh rate**: by default SteamVR offers a non-Steam app only 72 Hz. The *Hz* button saves
  72, 90 or 120 Hz; the launcher script then sets that as SteamVR's per-app preference
  (`steam.app.<appid>.preferredRefreshRate` via `vrcmd`), so it applies from the next start.
  The neon effects and score run at a steady 90 fps (11.1 ms) on the Frame.
- Apps can't access the cameras, so calibration works by touching keys rather than by
  recognising the keyboard visually.
- **No sound and no MIDI output**: your piano makes the sound, and Godot has no MIDI out, so
  there's no accompaniment playback.

## Troubleshooting

- **No MIDI device / audio driver "Dummy"**: Godot only loads ALSA MIDI with a real audio driver.
  Add `--audio-driver ALSA` to the launch options.
- **Piano not detected**: check `cat /proc/asound/cards` over SSH. Full-speed USB instruments
  sometimes fail on the direct port; try a USB 2.0 hub (with power delivery so the headset
  keeps charging).
- **Keyboard overlay in the wrong place**: run *Calibrate* again. The overlay is stored relative
  to the SteamVR play area, so recentring can move it.
- Logs: start the binary from a shell, or wrap it in a script that writes stdout to a file.

## Repository

| Folder | Contents |
|---|---|
| `step2-leren/` | **KeySight** (Godot project). Scripts are in `scripts/`; `tools/make_songs.py` generates the bundled songs. |
| `step1-midi-test/` | The first prototype: checks that USB-MIDI and passthrough work on the Frame, with a diagnostics panel. |
| `artwork/` | Steam library artwork plus the script that makes it |
| `docs/` | Screenshots and the hardware checklist |

## Roadmap

- Hand tracking once the Frame offers it
- Finger numbers (MusicXML import)
- Accompaniment / other hand played back through the piano (raw MIDI out)
- Simpler installation (a ready-made release)

## Contributing

Issues and pull requests are welcome, especially reports from other pianos and keyboards: tell
us whether it was detected, and the output of `cat /proc/asound/cards`. Please run the self-test, and the hardware checklist in [docs/HARDWARE_TEST.md](docs/HARDWARE_TEST.md) if you have a headset,
before sending a PR. Songs you contribute must be public-domain compositions in your own
arrangement, or come with a licence that allows redistribution.

## Credits and licences

- Code: MIT, see [LICENSE](LICENSE). Built with the help of Claude (Anthropic).
- The falling-tile idea and per-hand colours were inspired by
  [piARno](https://github.com/piARn0/piARnoApp) (MIT). See [THIRD_PARTY.md](THIRD_PARTY.md).
- Font: Atkinson Hyperlegible (SIL Open Font License 1.1).
- Bundled songs: a C major scale, *Twinkle Twinkle Little Star* and *Frère Jacques*
  (traditional), Beethoven's *Ode to Joy* and the opening of *Für Elise*. All are public-domain
  compositions in new arrangements made for this project (MIT), generated by
  `step2-leren/tools/make_songs.py`.
- Artwork: AI-generated (ChatGPT) for this project.

## Nederlands

KeySight is een gratis app voor de Steam Frame om piano te leren op je eigen piano. Vallende
noten komen via passthrough op je echte toetsen, met een wachtmodus, tempo en oefenen per
hand. Je kunt eigen MIDI-bestanden gebruiken, je krijgt feedback, en je kalibreert door een
paar toetsen aan te raken. De interface is in het Nederlands. Nog vroeg, getest op één
Yamaha CLP-230.
