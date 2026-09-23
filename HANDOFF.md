# EX Odyssey — handoff (pick up on another PC)

Read this first, then `CONTRACTS.md` (module ownership + every user directive) and
`levels/config/FORGOTTEN_VEIL_BIBLE.md` (level 2 art bible). Last updated 2026-09-23.

## Setup on a new machine
1. Install **Godot 4.6.1** (exact version). Default location the scripts look for:
   `%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64(.exe|_console.exe)`.
   Anywhere else: set the env var `GODOT_BIN` to the exe (console exe for tests).
2. `git clone https://github.com/Wmoook/3d33.git ex-odyssey`
3. First launch re-imports every asset (the `.godot/` cache is not in git) — takes a few minutes.
   Headless: `Godot_v4.6.1-stable_win64_console.exe --headless --path . --import`
4. Play: `PLAY.bat` (or `Godot --path .`). Build an exe: see `README.md`.
5. Tests: `bash tools_run_test.sh res://tests/<name>.tscn [-- args]` — runs INVISIBLY and SILENTLY via an
   auto-created mirror project `<repo>-test` next to the repo (junctions). Touch `.tests_visible` in the repo
   root to watch tests render. Needs Git Bash + Python on PATH.

Not in git (per-machine): saves/settings/best run in `%APPDATA%\Godot\app_userdata\EX Odyssey\`, the `.godot/`
import cache, `build/`.

## The project
Godot 4.6.1 Forward+ remake of two Everybody Edits levels with an exact 100 Hz port of EE Offline physics,
rendered as a lit 3D diorama. Levels: "EX Crew Odyssey" (`levels/ex_crew_odyssey.eelvl`) and
"Forgotten Veil" (FV, `levels/forgotten_veil.eelvl`, 400x200, 16 trial rooms).
Typed GDScript, warnings are errors.

## User preferences (learned the hard way — respect these)
- The EE minimap (`assets/ee_ref*/minimap_ee.png`) is the canonical art. Where it shows sky, the game shows
  sky (FV: large sealed sky-painted regions render open — spire gap / Lower Sanctum / bay; 0 mismatches >=20 tiles).
- Camera stays EE-exact straight-on (FOV 34), no tilt. Blocky, tile-aligned depth (not smooth).
- Gameplay readability > art: solid looks solid, passable looks passable.
- Forest depth is built from the level's OWN tree blocks, only inside forests (now 3 merged slab layers).
- Very sensitive to: pale sky-blue slivers, z-fighting flicker, black lines/specks, "floating" depth pieces,
  flat untextured planes. Verify with measured checks (fv_audit, isolation via hide=) before calling
  anything fixed; they got frustrated when fixes were declared early.
- No ball trail, no replay ghost by default, zone/trial title card only on first visit, portals = 3D EE
  portal blocks + instant camera cut, god-mode ball always drawn in front of blocks.
- Plays at 1440p 143 Hz (RTX 5080) with OBS: game caps at 120 fps, audio 48 kHz / 40 ms.
- When they want to play: stop all background tests, launch `--path .`. Tests must never pop up windows
  or play sound. Never kill Godot by name (it kills their game) — only `*-test` mirror processes.
- Commit specific files only (never `git add -A` over others' WIP).

## Verification tools
- `tests/fv_audit.tscn` + `tests/fv_audit_report.py`: level-wide scanner (sentinel-magenta sky leak,
  flicker via 1e-5 camera nudge, shimmer via 0.45 px move, black lines, exact-black, pale; `hide=<node>` for
  owner isolation, `out=<dir>`, `only=`, `spots=grid`). Reports land in `%APPDATA%/.../EX Odyssey/<out>/report.txt`.
  Last full runs: audit_full4 -> full6 (sky 6->4, flicker 1->1, shimmer 2->0, black lines 6->1, exact-black 248->65).
  A final `audit_full7` on 818315e was started but stopped when the user wanted to play — run it first.
- `tests/world_game_shot.tscn -- level=forgotten_veil at=X,Y zoom=N name=foo` single shots,
  `tests/detail_shots.tscn`, `tests/sky_bg_shots.tscn` (bg before/after sheets), `tests/trial_order.tscn`.
- Runtime A/B flags (no file swaps!): env `BG_SPACE_OFF=1`, `BG_POOLS_OFF=1`.

## State at handoff (HEAD on master)
Done this session (see git log): forest background overhaul (WorldForest 3-layer greedy slabs via
`scripts/render/slab_merge.gd`, world-space leaf/bark, green-teal haze), WorldBgSpace regional bg tone +
class materials + interior light pools, first-cave shaft fixes, roofless brick bays solid-fronted, open
painted sky matching the minimap, Ruined Keep wall, many exact-black fixes, trial numbering in play order,
trial caption once, god-mode ball on top, audit frame-border exclusion.

Open / ideas:
- Run `audit_full7` and fix anything new.
- Known won't-fix: 1-2 px sky specks at rounded rock corners (129,143),(130,139),(92,79),(94,85);
  flicker on the terrain diagonal staircase (208,27).
- Caves are better but not "dramatic". A layered cave-rock prototype is PARKED in
  `docs/parked/cave_layers/` (patch + 2 new files; read as ok but added dark blotches in low tunnels —
  apply with `git apply docs/parked/cave_layers/cave_layers.patch` and copy the files into scripts/render
  and shaders/world). Stone-hall bay recesses and dark-rimmed air pockets were not started.
- Asked the user (no answer yet): remove the near-camera dark hanging-root silhouettes
  (`world_decor.gd _build_near_silhouettes`) from FV? They may read as "floating lines".
