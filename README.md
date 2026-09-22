# EX Odyssey

A 3D-rendered reimagining of **"EX Crew Odyssey"**, a level for *Everybody Edits*, built in Godot 4.6.1.
It's the same level, the same controls, and the original EE physics ported tick for tick. It's rendered as a
sculpted, lit diorama with volumetric caves, zone atmospheres, a procedural soundtrack, a best-run ghost and
a map built from the level's own minimap art.

## Play

- Double-click `PLAY.bat`. It launches `build\EX_Odyssey.exe` if it exists, otherwise it runs the project with the Godot 4.6.1 editor binary.
- Build the exe: `Godot_v4.6.1-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/EX_Odyssey.exe`
- Self-test a build: `build\EX_Odyssey.exe --headless --audio-driver Dummy -- --smoke-test` (boots, plays 200 ticks, exits 0).

## Controls

| Key | Action |
|---|---|
| Arrows / WASD | Move (Up/W is "up", as in EE) |
| Space | Jump |
| G | God mode |
| M | Map (corner, then full map: wheel zoom, drag/arrows pan, Space finds you) |
| H | Show/hide the best-run ghost |
| Shift+R | Retry (new run) |
| F3 | Collision overlay (true solid tiles, one-way platforms, your hitbox) |
| Mouse wheel, + / - | Camera zoom |
| F11 | Fullscreen |
| Esc | Pause menu |

A gamepad works too: left stick or d-pad to move, A to jump, Y for god mode, X for the ghost, Start to pause, Back for the map, LB/RB to zoom.

## Settings (Esc, then Settings)

- Master, music and effects volume
- Camera zoom (20-60 tiles)
- Quality preset: Low, Medium, High or Ultra. Ultra is the full authored look; lower presets drop SDFGI/SSIL/SSR and shadows and lower the render scale.
- Fullscreen and control hints
- Show collision (F3)
- High-contrast gameplay glyphs (bigger, brighter keys, arrows and dots)

Settings, first-run tutorial progress and your best run (`best.eerp`) are stored in `%APPDATA%\Godot\app_userdata\EX Odyssey\`.

## Credits

Based on **EX Crew Odyssey**, a level for **Everybody Edits**. The physics are ported from **Everybody Edits Offline**.
This is a fan reimagining and is not affiliated with the original developers.
Fonts: Cinzel, Cormorant Garamond and Rajdhani (SIL Open Font License, `assets/ui/fonts/OFL.txt`).
All music and sound effects are generated procedurally (`assets/audio/gen_audio.py`).
