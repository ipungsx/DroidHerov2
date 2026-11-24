# DroidHeroV2 🎸🔥

**DroidHeroV2** adalah game ritme bergaya **Guitar Hero / Clone Hero** untuk **Android (APK)** yang dibangun menggunakan **Godot Engine 4.7** dengan target performa stabil **60 FPS**, integrasi pencarian & unduhan lagu langsung dari **enchor.us**, desain UI glassmorphic modern dengan **5 pilihan tema konser**, serta panggung konser interaktif yang lampu-lampunya mengikuti irama dentuman drum secara *real-time*.

---

## ✨ Fitur Utama

1. **Integrasi Langsung `enchor.us` + Lagu Bawaan**
   - Cari lebih dari **85.000+ chart** langsung di tab **ENCHOR.US CHARTS** (`api.enchor.us`).
   - Unduh paket lagu `.sng` otomatis ke penyimpanan aplikasi (`files.enchor.us`) lengkap dengan *cover art* dan dekoder audio **Ogg Opus (`AudioStreamOpus`), Ogg Vorbis, MP3, dan WAV**.
   - Mendukung juga **Import `.sng` / `.zip` lokal** dan sudah dilengkapi lagu bawaan siap main (*Neon Overdrive - DroidHero Anthem*) bahkan saat *offline*.

2. **Mekanik Lengkap ala Guitar Hero**
   - **5-Lane Perspective Highway** (Green, Red, Yellow, Blue, Orange) dengan dukungan *multi-touch* layar sentuh Android & *keyboard* (`A S D F G` / `1 2 3 4 5`).
   - **4 Tingkat Kesulitan**: *Easy, Medium, Hard, Expert* (otomatis *auto-downchart* jika chart komunitas hanya menyediakan *Expert*).
   - **Tipe Nada Lengkap**: Strum Gems, **HOPO (Hammer-On / Pull-Off)** tanpa perlu tap ulang saat ditahan, **Tap Notes**, **Chords**, dan **Sustain Trails** panjang.
   - **Star Power Overdrive (2x Multiplier)** & **Whammy Bar** (goyangan *pitch-bend* + pengisi energi Star Power ekstra pada nada panjang).
   - **Combo Streak (1x – 4x, hingga 8x saat Star Power)**, **Rock Meter** (plus opsi *No-Fail*), skor per lagu, **Rating Bintang 1–5**, dan lencana **FULL COMBO (FC)**.
   - **Practice Mode** (75% & 50% kecepatan latihan, atau 125% *Hyperspeed*) dan **Kalibrasi Latency Audio/Touch** otomatis dengan ketukan bit.

3. **Panggung Konser Meriah Sinkron Dentuman Drum (60 FPS)**
   - **8 Moving-Head Volumetric Spotlights** di atas *truss* konser, **Snare Strobe Blinders**, **Laser Cymbal Silang**, **2 Subwoofer Cones** yang memompa saat *kick drum*, **16-Band LED Equalizer Wall**, dan siluet penonton konser yang melompat mengikuti *beat*.
   - Menggabungkan *event* `[ExpertDrums]`/`PART DRUMS` dari chart dengan detektor frekuensi *sub-bass* (35–135 Hz) & *snare* (180–4800 Hz) `AudioEffectSpectrumAnalyzer` secara *real-time*.

4. **5 Pilihan Tema Fancy**
   - `NEON CYBERPUNK` (Electric Cyan & Magenta Laser Arena)
   - `INFERNO STADIUM` (Pyrotechnic Crimson & Molten Gold)
   - `EMERALD OVERDRIVE` (Toxic Lime & Acid Cyber Stage)
   - `ROYAL GOLD VIP` (Velvet Violet & Champagne Gold)
   - `SYNTHWAVE SUNSET` (80s Outrun Horizon & Laser Grid)

---

## 📦 Unduh APK Siap Pasang

File APK Android yang sudah ditandatangani (siap di-install di perangkat Android ARM64 / ARMv7) tersedia di halaman **[Releases](https://github.com/ipungsx/DroidHerov2/releases/latest)** (`DroidHeroV2.apk`).

## 🛠️ Struktur Proyek

- `project.godot` — Konfigurasi engine Godot 4.7 (Landscape, 60 FPS VSync, Mobile Renderer)
- `scripts/ThemeManager.gd` — Sistem 5 tema arena konser & komponen UI glassmorphic
- `scripts/GameState.gd` — Penyimpanan skor tertinggi, pengaturan, bus spektrum audio, & pustaka lagu
- `scripts/EnchorClient.gd` — Klien REST `api.enchor.us` & pengunduh paket `.sng`
- `scripts/SngParser.gd` — Dekoder kontainer biner `.sng` (XOR unmasking) & `.zip` + multi-stem Opus/Ogg/MP3/WAV
- `scripts/ChartParser.gd` — Parser `notes.chart` & `notes.mid` lengkap dengan *tempo map*, HOPO, Star Power, dan trek drum
- `scripts/ConcertStage.gd` — Visualizer lampu panggung konser 60 FPS reaktif terhadap dentuman drum
- `scripts/Gameplay.gd` — Mesin utama permainan 5-fret Guitar Hero
- `scripts/MainMenu.gd` & `scripts/Results.gd` — Antarmuka menu utama & layar hasil bintang
