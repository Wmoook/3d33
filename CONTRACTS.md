# EX ODYSSEY — Team Contract

We're rebuilding **Everybody Edits — "EX Crew Odyssey"** (`levels/ex_crew_odyssey.eelvl`, 400x200 tiles) as a
**AAA-looking 3D-rendered game** in **Godot 4.6.1 (Forward+)**. Same game, same level, same physics, same
controls. It must **not look like blocks or a grid**. It should look like a high-end 3D render: sculpted
geometry, PBR materials, dramatic dynamic lighting, volumetrics, bloom, GI, and deep, moody caves when you go
underground. Hardware target: RTX 5080 / i9-14900K at 1080p–4K, 60+ fps. Go heavy on quality.

- Godot: `C:\Users\super\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe` (call it `$G`)
- Project: `C:\Users\super\ex-odyssey` (`$G --path C:/Users/super/ex-odyssey`)
- Headless script: `$G --headless --path . -s res://tests/xxx.gd` (script `extends SceneTree`)
- Screenshots need a real window, not headless: run a test scene that waits a few frames, calls
  `get_viewport().get_texture().get_image().save_png("user://shot.png")`, then quits.
  user:// = `%APPDATA%/Godot/app_userdata/EX Odyssey/`. **Look at your screenshots** (the Read tool shows
  images) and iterate until they look great.
- Import new assets: `$G --headless --path . --import`
- Original EE source (AS3): `C:\Users\super\ee-offline`. **The working tree and branch `retick-240` are
  MODIFIED (240Hz retick, HD sprites). Ground truth is upstream: `git -C C:/Users/super/ee-offline show origin/main:src/Player.as`** etc.
- Reference art: `assets/ee_ref/<id>.png` (original 16x16 sprite of every block id used in the level),
  `assets/ee_ref/blocks.json` (package, layer, avg_rgb per id), `assets/ee_ref/level_preview_full.png`
  (6400x3200 render of the whole level with original sprites), `level_preview_small.png`.
- Never kill other people's Godot processes blindly — kill only a PID you started, if needed.

## The level art

The level is a **pixel painting made of blocks**: each block is one "pixel" of a big illustration: a surface
with grass, trees and houses at the top, a huge red-brown earth layer with "The Devil hath taken thy Soul..."
text and the ΣX CREW logo, a purple corrupted cavern, a flaming skull pit, lava/orange rock drips, a bone
pile, a ship's wheel, an ice/snow cavern with icicles, a giant red demon rising from blue water, a tornado on
the left. **Preserve this art**: every region keeps its color and shape. It should read as the same picture
reimagined as a sculpted, lit 3D diorama, not a new map. Colors stay; blockiness goes.

## Coordinate system (EVERYONE uses this)

- EE space: pixels, **y down**, 16 px per tile. Tile (tx,ty) covers px [16tx,16tx+16) x [16ty,16ty+16).
  The player is a 16x16 box; EE `x,y` = its top-left corner, center = (x+8, y+8).
- World space (Godot 3D): **1 tile = 1.0 unit**, x right, **y up**, z toward camera.
  `world = Vector3(px_x / 16.0, -px_y / 16.0, 0.0)`. Tile (tx,ty) spans x∈[tx,tx+1], y∈[-ty-1,-ty].
  Helper: `EECoords` in `scripts/core/ee_coords.gd`.
- **Gameplay plane is z = 0.** The ball (radius 0.5) lives at z=0. Foreground solid geometry must fill its
  tiles' footprint in XY (collision is still exactly the grid) and extend in depth roughly z ∈ [-1.5, +0.8]
  (or deeper) so it reads as a solid 3D mass. It must never visually cover empty air tiles in front of the ball
  more than a tiny bevel (≤0.12). The background layer (layer 1) sits behind at around z ≈ -1.5…-3.
  Beyond that: far parallax/backdrop.
- Camera: perspective, looking down -z, positioned by the game shell (`scripts/game/camera_rig.gd`).
  About 38–44 tiles visible horizontally (the EE view is ~40x30 tiles). Slight 3D parallax is desired.

## Modules and owners (only edit files you own; ask the lead for changes to other files)

| Owner | Files | Responsibility |
|---|---|---|
| lead | `scripts/core/ee_level.gd` (done), `scripts/core/ee_coords.gd`, `CONTRACTS.md` | loader, contract |
| **physics** | `scripts/physics/*`, `tests/physics_*` | exact EE physics + world rules sim |
| **world** | `scripts/render/*`, `shaders/world/*`, `assets/world/*`, `tests/world_*` | terrain, bg, decor, materials, lights, environment/post, atmosphere zones |
| **actors** | `scripts/fx/*`, `shaders/fx/*`, `assets/fx/*`, `tests/fx_*` | 3D player ball, interactive blocks (arrows, keys, doors, gates, coins, coin doors, portals, crown, spawn), particles, trails |
| **shell** | `scripts/game/*`, `scripts/ui/*`, `scenes/*`, `assets/audio/*`, `assets/ui/*`, `tests/game_*`, `project.godot` | main scene, game loop, input, camera, HUD, menu/title, pause, audio/music, integration |

### Physics API (`scripts/physics/ee_sim.gd`, `class_name EESim extends RefCounted`)
```gdscript
var level: EELevel
signal sim_event(kind: StringName, data: Dictionary)   # see event list below
func _init(lvl: EELevel) -> void
func reset() -> void                                    # respawn at spawn (255) / start
func tick(input: EEInput) -> void                       # exactly one original EE physics tick (100 Hz = 10 ms)
# player state (EE px, y down):
var px: float; var py: float                            # top-left of the 16x16 box, like EE Player.x/.y
var prev_px: float; var prev_py: float                  # state before the last tick (for render interpolation)
var speed_x: float; var speed_y: float                  # EE speed units
var gravity_dir: Vector2i                               # current gravity direction from arrow/dot blocks
var on_ground: bool; var is_dead: bool; var in_god_mode: bool
var coins: int; var blue_coins: int; var has_crown: bool
func is_key_active(color: StringName) -> bool           # &"red", &"green", &"blue"
func key_time_left(color: StringName) -> float
func is_tile_solid_now(tx: int, ty: int) -> bool        # current dynamic solidity (doors/gates/coin doors)
func is_coin_collected(tx: int, ty: int) -> bool
func ticks() -> int
```
`EEInput` (`scripts/physics/ee_input.gd`): `left, right, up, down, jump: bool` (jump = Space; held states like EE).
Events (`sim_event`): `&"coin"`, `&"blue_coin"` {tile}, `&"key"` {color}, `&"key_expired"` {color},
`&"portal"` {from, to}, `&"crown"`, `&"death"`, `&"respawn"`, `&"jump"`, `&"land"` {impact_speed},
`&"gravity_changed"` {dir}, `&"door_state"` {kind, open}, `&"checkpoint"`.
The shell calls `tick()` from `_physics_process` (project runs 100 physics ticks/s) and renders with
interpolation `lerp(prev, cur, Engine.get_physics_interpolation_fraction())`.

### World API (`scripts/render/world_view.gd`, `class_name WorldView extends Node3D`)
```gdscript
func build(lvl: EELevel) -> void           # builds everything (may take a few seconds; show loading)
func set_sim(sim: EESim) -> void           # optional: to react to dynamic state
func update_focus(world_pos: Vector3, delta: float) -> void  # player pos: streaming, atmosphere blending
func get_environment() -> Environment      # the WorldEnvironment it created (shell may read it)
```
WorldView owns the WorldEnvironment, sun/moon, world lights, fog volumes and **atmosphere zones** (surface
night sky vs. underground caves vs. hell/fire vs. ice cavern…) blended from the focus position.

### Actors API (`scripts/fx/actors_view.gd`, `class_name ActorsView extends Node3D`)
```gdscript
func build(lvl: EELevel, sim: EESim) -> void   # spawns visuals for interactive blocks, connects sim_event
func update_player(world_pos: Vector3, sim: EESim, delta: float) -> void  # interpolated pos from shell
func get_player_node() -> Node3D
```

### Block ownership by id (level uses these)
- **world**: solid FG 9–21, 29–31, 35, 37–49, 51–55, 87, and 44 (black "secret" solid); passive decoration
  22, 32, 33, 34, 36, 50, 62, 227–240, 244–254; **all background ids 500+**.
- **actors**: gravity 1 (left), 2 (up), 3 (right), 4 (dot/zero-g); crown 5; keys 6/7/8; key doors 23/24/25;
  key gates 26/28; coin door 43; coins 100/101; 121 (brick complete); portals 242/381; spawn 255.
- **physics** decides behavior of every id exactly like EE (solidity, arrows, dots, keys, doors, portals…).
  Doors/gates/coin-doors are dynamic: renderers must ask `sim.is_tile_solid_now()` / listen to events.

## Quality bar
This must look like a AAA game: think *Ori*, *Limbo/Inside*, *Trine*, *Hollow Knight* in 3D-render form.
Smooth sculpted shapes, no visible 16px grid, rich materials, emissive fire/lava that lights the scene,
glowing crystals, wet reflective surfaces, volumetric light shafts, drifting particles (embers, dust, snow),
parallax depth, color grading. Everything reads clearly for gameplay: solid vs. empty must be obvious.
