# DroidHeroV2

**DroidHeroV2** is a 60 FPS, 5-fret Guitar Hero / Clone Hero style rhythm game built for **Android** using **Godot Engine 4.7**. Designed natively for **Portrait HD (`720×1600`)** smartphones, it features direct in-game chart browsing and downloads from **enchor.us**, ray-lit 3D cut-jewel note gems, tactile raised 3D frets with sustain friction sparks, customizable concert arena themes, and drum-reactive stage lighting.

---

## Features

### 1. Native Portrait HD Smartphone Experience (`720×1600` + 4× MSAA)
- Purpose-built **Portrait HD** single-column mobile interface with large thumb-friendly arcade controls, smooth screen transitions, and Android Back button navigation.
- **Ultra-Wide 5-Fret Highway** spanning **95.6%–99.6%** of the screen width at the touch zone, providing comfortable multi-touch chords and a long vertical sightline.
- **Procedural HD Visuals:** Pre-baked mipmapped 8-facet 3D cut-jewel gems in brushed metallic bezels, selectable HD fretboard surfaces (**Carbon Fiber**, **Rosewood**, **Obsidian Metal**), horizon fade-in, and expanding hit shockwaves.

### 2. Direct `enchor.us` Integration & Local Imports
- Browse and search **85,000+ community guitar charts** directly in-game via `api.enchor.us` with album cover previews.
- **One-Tap `.sng` Download:** Downloads and saves song packages automatically (`files.enchor.us`) with full support for **Ogg Opus** (via `OpusGdextension`), **Ogg Vorbis**, **MP3**, and **WAV** (including multi-stem audio).
- **Local Song Import:** Import your own `.sng` packages or `.zip` chart archives from device storage.
- **Built-In Offline Track:** Includes *Neon Overdrive (DroidHero Anthem)* ready to play out of the box without an internet connection.

### 3. Complete 5-Fret Rhythm Mechanics
- **Multi-Touch & Keyboard Support:** Simultaneous multi-finger chords, slides, and desktop keyboard bindings (`A S D F G` / `1 2 3 4 5`, `Space` for Star Power, `Shift` for Whammy).
- **4 Difficulty Tiers:** *Easy, Medium, Hard,* and *Expert* (with automatic downcharting when a chart only includes *Expert*).
- **Full Note Types:** Standard Strum Gems, **HOPO (Hammer-On / Pull-Off)** with bright pearl-white crowns, **Tap Notes**, **Chords**, and **Sustain Ribbons**.
- **Tactile 3D Raised Frets & Sustain Friction FX:** Each fret pops upward in 3D when tapped. On long sustain notes, the round 3D note gem locks and vibrates on the raised fret while the sustain ribbon grinds into its upper rim with a glowing contact seam and continuous friction sparks.
- **Star Power Overdrive (2× Multiplier) & Whammy Bar:** Build Star Power from star notes and streaks, deploy for up to **8×** scoring and blue-white plasma flames, and hold Whammy during sustains for pitch bend and extra Star Power charge.
- **Guitar Solo Tracker & Live Accuracy:** Automatic solo sections with live hit percentage and end-of-solo score bonuses.
- **Practice Mode, Hit Windows & Audio Calibration:** Adjustable playback speed (`50%`, `75%`, `100%`, `125%`), **No-Fail** toggle, **Strict / Normal / Lenient** timing windows, haptic vibration feedback, tap-to-calibrate audio offset (`-150 ms` to `+150 ms`), and one-tap timing adjustment tips on the results screen.

### 4. Drum-Reactive Concert Stage Lighting (60 FPS)
- 8 overhead moving-head volumetric spotlights, snare strobe blinders, criss-crossing cymbal lasers, dual pulsing subwoofer stacks, and a 16-band real-time LED spectrum wall.
- Synchronizes with both `[ExpertDrums]` / `PART DRUMS` chart cues and real-time audio spectrum analysis (`AudioEffectSpectrumAnalyzer`), remaining calm and static whenever no music is playing.
- **5 Selectable Concert Arena Themes:**
  - `NEON CYBERPUNK` — Electric Cyan & Magenta Laser Arena
  - `INFERNO STADIUM` — Pyrotechnic Crimson & Molten Gold
  - `EMERALD OVERDRIVE` — Toxic Lime & Acid Cyber Stage
  - `ROYAL GOLD VIP` — Velvet Violet & Champagne Gold
  - `SYNTHWAVE SUNSET` — 80s Outrun Horizon & Laser Grid

---

## Download & Installation

1. Go to the **[Releases](https://github.com/ipungsx/DroidHerov2/releases/latest)** page and download **`DroidHeroV2.apk`**.
2. Transfer or open the APK on your Android device (ARM64 / ARMv7 / x86_64).
3. Allow installation from unknown sources if prompted, then install and launch **DroidHeroV2**.

> **Note:** If upgrading from an older build and Android reports a signature mismatch, uninstall the previous version before installing the latest APK.

---

## Controls

| Action | Android Touch | Keyboard (Testing) |
| --- | --- | --- |
| 5 Fret Lanes (G / R / Y / B / O) | Tap / hold lower fretboard lanes (multi-touch) | `A S D F G` or `1 2 3 4 5` |
| Star Power Overdrive | Tap **STAR** button (upper-left, at ≥ 50%) | `Space` |
| Whammy Bar | Hold **WHAMMY** button (upper-right) during sustains | `Shift` |
| Pause / Back | Tap **II** button (upper-right) / Android Back | `Esc` |

---

## Building from Source

### Requirements
- **Godot Engine 4.7.2** (standard binary + matching Android export templates)
- **Java 21 (JDK 21)**
- **Android SDK** with Build-Tools and Platform-Tools installed

### Build Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/ipungsx/DroidHerov2.git
   cd DroidHerov2
   ```
2. Open the project in Godot 4.7.2 (or run headless import) and configure your Android SDK & debug keystore paths in Editor Settings.
3. Export using the included `Android` preset (`export_presets.cfg`):
   ```bash
   godot --headless --import
   godot --headless --export-debug "Android" build/DroidHeroV2.apk
   ```

Automated APK builds for tagged releases (`v*`) are also configured in `.github/workflows/release.yml`.

---

## Project Structure

```text
DroidHerov2/
├── project.godot              # Godot 4.7 config (Portrait HD 720x1600, 60 FPS, 4x MSAA)
├── export_presets.cfg         # Android APK export preset (ARM64, ARMv7, x86_64)
├── addons/OpusGdextension/    # Ogg Opus audio decoder GDExtension
├── assets/
│   ├── bundled/               # Built-in offline track (neon_overdrive.chart & .wav)
│   └── fonts/                 # Orbitron & Rajdhani UI fonts
├── scenes/                    # MainMenu.tscn, Gameplay.tscn, Results.tscn
└── scripts/
    ├── HDAssets.gd            # Procedural HD 3D cut-jewel gem & fretboard texture baker
    ├── ThemeManager.gd        # 5 concert arena themes & mobile UI styling
    ├── GameState.gd           # Persistent settings, highscores, audio bus & song library
    ├── EnchorClient.gd        # enchor.us REST search client & .sng downloader
    ├── SngParser.gd           # Binary .sng (XOR unmasking), .zip & multi-stem audio loader
    ├── ChartParser.gd         # notes.chart & notes.mid parser (tempo map, HOPO, SP, drums)
    ├── ConcertStage.gd        # 60 FPS drum-reactive stage lights & spectrum wall
    ├── MainMenu.gd            # Portrait smartphone game hub, song select, store & settings
    ├── Gameplay.gd            # 5-fret highway renderer, multi-touch input & sustain FX
    └── Results.gd             # Post-song rank screen, stats breakdown & timing assistant
```

---

## License & Third-Party Credits

- **OpusGdextension** by Joy-less (included under `addons/OpusGdextension/LICENSE.md`)
- Community charts and metadata provided via **[enchor.us](https://www.enchor.us/)**
