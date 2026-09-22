# EE physics (`EESim`, `EEInput`)

A direct port of upstream **Everybody Edits Offline** player physics (`git show origin/main:src/...`), not
the 240 Hz retick branch. Sources: `Player.as` (tick), `Me.as` (input, touchBlock), `World.as`
(overlaps, update, setKey), `PlayState.as` (tick, enterFrame queues, switchKey, crown checks),
`Config.as`, `ItemId.as`, `Lookup.as`, `blitter/BlGame.as` (tick driving).

Tests: `$G --headless --path C:/Users/super/ex-odyssey -s res://tests/physics_test.gd`

## Units
- `px, py`: top-left of the 16x16 box in EE pixels, y down (AS3 `Player.x/.y`).
- `speed_x, speed_y`: the AS3 internal `_speedX/_speedY`, i.e. **pixels per tick**. EE's public
  `speedX` getter is this value times 7.752. The +-16 clamp applies to these. Terminal fall speed is
  13.5531 px/tick, max walking speed 6.7766 px/tick, and the jump impulse is -52/7.752 = -6.7079.
- One `tick()` is one 10 ms EE tick. The shell runs it at 100 Hz.

## Rules implemented (same order of operations as the AS3)
- **Tick order**: `PlayState.tick` (coin/blue-coin/death gate visibility with the overlap revert, G
  god toggle), then `World.update` (offset += 0.3, time doors every 5 s, key expiry), then
  `Player.tick`, then the `PlayState.enterFrame` queues (crown/orange-switch queue, then the key
  queue), then the death-animation respawn.
- **Physics constants**: all drags are `pow(x, 10) * 1.00016093` (base, no-modifier, ice, ice-no-mod,
  water, mud, lava, toxic). Jump 26, gravity 2, boost 16, the buoyancies, and multiplier 7.752 (the
  modifiers and speeds go through the same getter/setter scaling).
- **Gravity queue** (`physics_queue_length` = 2): `delayed = queue.shift(); push(current)`. Dots
  (4/414) and climbables shift twice. `morx/mory` (int) come from the current tile and `mox/moy`
  (Number) from the delayed tile. Arrows take effect on the 3rd tick inside them and dots on the 2nd.
- **Tile gravity switches**: arrows 1/2/3 (+411-413, 1518/1519), dots 4/414, speed arrows 114-117
  (zero gravity plus a boost that sets the speed to +-16 directly), water/mud/lava/toxic buoyancy
  (with int truncation on `mory`), climbables (120, 118, 98, 99, 424, 459, 460, 472, 1534, 1146, 1563,
  1602), spikes and fire (kill), and toxic (kill).
- **Gravity rotation**: `flipGravity` rotation (EFFECT_GRAVITY 1517) with the `rotateGravitymo/mor`
  flags.
- **Movement axes**: horizontal/vertical input is restricted to the axis perpendicular to gravity
  (both axes in liquids or zero gravity). Speed/gravity multipliers apply (run effect, low gravity,
  world gravity).
- **Drag selection**: the full if/else chain, including the reverse-direction no-modifier drag,
  liquids, and ice slipperiness (`slippery` 2 decaying by 0.2 per tick, from the tile "below" in the
  gravity direction, with the original `getCurrentBelow` case quirks). Clamp at +-16. Speeds under
  1e-4 are zeroed.
- **Sub-stepping**: `stepx`/`stepy` exactly as written. They step to integer boundaries with `x>>=0`.
  Moving left from an integer x takes one step unless on a boost. On collision they revert to
  `ox/oy`, zero the speed and set `grounded` only when moving *into* gravity. `currentS = osx` then
  lets a blocked axis retry on later loop iterations (EE corner sliding). `processPortals` runs on
  every loop iteration using the tick-start center tile.
- **Portals 242 / 381**: skipped when `target == id`. `lastPortal` blocks ping-pong and starts
  non-null, like the AS3. Targets are all portals whose `id == target` (random pick). The rotation
  delta `old<new ? old+4 : old` maps to 90/180/270 degree rotation of speed, modifier, remainder and
  current step, all times 1.42. Position is set to the target's top-left.
- **Jumping**: `spacejustdown` / held-space timers use `lastJump = -now` on press. Held space
  repeats 750 ms after the press, then every 150 ms (a sim clock of ticks x 10 ms stands in for
  `Date.time`). `jumpCount`/`maxJumps` apply, with multi-jump (461) resetting them. The jump
  requires `grounded` from this tick's collisions. Jumps work in x or y (sideways gravity), with the
  jump multiplier (jump effect, ice x0.88).
- **Grid snap**: `imx = _speedX<<8` (int truncation), not in liquids, only when `|modifier| < 0.1`.
  Within 2 px of an edge it slides by tx/15 and truncates under 0.2 / over 15.8.
- **World.overlaps**: out-of-world counts as solid. It scans the tiles covered by the box using
  `ItemId.isSolid` (9-97 except 77/83, 122-217, 1001-1499, minus climbables) and strict rectangle
  intersection. It covers one-way blocks (canJumpThroughFromBelow, incl. **62**, with the
  `overlapa` bookkeeping and the `oy+15` rule), rotatable one-ways (1001-1004, 1052-1056, 1092,
  1155, 4 directions), half blocks and the door/gate switch:
  - key doors 23/24/25 and gates 26/27/28 (plus cyan/magenta/yellow 1005-1010)
  - time door/gate 156/157
  - purple and orange switch doors
  - gold door/gate 200/201 (no gold smiley)
  - crown and silver crown doors
  - **coin door 43** (`number <= coins`), blue coin door 213 and death door 1011
  - coin, blue coin and death gates (165/214/1012) using the deferred `showCoinGate` values
  - team doors (team 0) and zombie doors
  - secret reveal for 50 (solid) and 243 (non-solid)
- **Keys 6/7/8 (+408-410)**: `switchKey` sets the key and `keysTimer = offset`. If that would put a
  gate on the player, it is reverted and re-queued (`fromqueue` retries only within the 5 s window).
  Keys expire when `(offset - timer)/30 >= 5` (500-501 ticks from float accumulation), and that
  expiry is also deferred while the player is inside a door that would close. Re-touching a key
  restarts its timer.
- **Coins 100/101**: collected from the tick-start center tile, which becomes 110/111. Blue coins
  count separately.
- **Crown 5 / brick complete 121**: `removeCrown` + `checkCrown(true)` (queued while overlapping a
  crown door), and a silver crown that stops the run timer.
- **Other touch blocks**: checkpoint 360, purple/orange switches and resets, and the effects jump
  417, run 419, protection 420, low gravity 453, multi-jump 461, gravity 1517 and reset 1618. Lava
  sets fire, with death after 2 s + 2 x ping (0.2), as in `setEffect`. Water/mud/toxic extinguish
  it. Touch effects fire only when entering a tile (`pastx/pasty`), except coins.
- **Death**: `killPlayer` (not in god mode). While dead, input and speed are zeroed. `deadoffset`
  goes up 0.3 per tick, and after it passes 16 (54 ticks) comes `respawn()` (checkpoint or spawn,
  keeping the gravity queue and `lastPortal`) and deaths++.
- **Spawn**: `placeAtSpawn` cycles spawn points (id 255), falls back to (1,1), and uses the
  checkpoint on respawn.
- **God mode**: `isFlying` skips all tile gravity/boosts/portals/deaths/touch effects except coins,
  and `overlaps` returns 0 except at the world edge. Drag is the plain god-mode drag chain, so the
  player glides like EE.

## Events (`sim_event`)
`coin`/`blue_coin` {tile}, `key` {color, tile} (on every key touch), `key_expired` {color},
`portal` {from, to} (tiles), `crown` {tile}, `death` {pos}, `respawn` {pos}, `jump` {pos},
`land` {impact_speed} (px/tick along gravity when grounding after being airborne),
`gravity_changed` {dir} (sign of the *applied* gravity mox/moy, zero in dots), `checkpoint` {tile}.

`door_state` {kind, open}: kind is `&"red"`…`&"yellow"` (open=true means that color's doors are open
and its gates closed). For coin doors, kind is `&"coin"`/`&"blue_coin"` with `count` = the door number
crossed. `&"time"` is emitted only if the level has time doors.

Added events: `complete` {tile, ticks} (121), `secret` {tile}, `god_mode` {on}.

## Added members (beyond CONTRACTS.md)
- **State**: `teleported` (the last tick jumped discontinuously, so skip interpolation),
  `has_silver_crown`, `deaths`, `checkpoint`, `current_tile`, `modifier_x/y`, `morx/mory/mox/moy`,
  `run_ticks`.
- **Methods**: `is_tile_one_way()`, `is_secret_revealed()`, `get_tile()`, `get_portal()`,
  `set_god_mode()`, `respawn()`, `kill_player()`.
- **EEInput**: `jump_pressed` (a press edge, for taps shorter than a tick) and `god_toggle`.

## Deviations (none change behaviour for the blocks EX Crew Odyssey uses)
- **Tick driving**: EE runs `tick()` from wall-clock catch-up (`BlGame`, max 15 per frame) and reads
  `Date.time`. Here the shell calls one tick per physics step, and time = ticks x 10 ms.
- **Queues**: the `enterFrame` queues (deferred key/crown/orange switches) are drained after every
  tick instead of once per rendered frame. That is the same when a frame has at most one tick.
- **Death respawn**: happens at the end of the tick in which `deadoffset > 16`. EE does it in the
  next `draw()`.
- **Randomness**: when several portals share a target id, the pick uses a seeded RNG (EE uses
  `Math.random` and unordered for-in).
- **Spawn order**: multiple spawns are cycled in scan order, not file order. The level has only one
  spawn.
- **Not implemented** (not in this level): world portals 374, reset point 466 (needs the "risky"
  key), levitation 418, curse/zombie/poison/team effects and player tagging, god block 1516, map
  block, NPCs, music blocks. Gold-smiley doors assume no gold smiley. `is_tile_solid_now` reports
  one-ways and half blocks as solid (directional logic lives only in the collision).

## Note for renderers: EE solidity of "decoration-looking" ids
Per `ItemId.isSolid`, **22, 32, 33, 34, 36 and 50 are solid** (9-97), and **62 is a one-way platform**
(solid from above). 44 is solid. 227-255, 121, 100/101, 5-8 and 242/381 are not solid.

## Keys vs. a player standing in a door or gate (tested)
- **Expiry while inside a red door:** when the key's 5 s are up and turning it off would trap the
  player, `switchKey(false)` is reverted. That revert calls `setKey(true)`, which **restarts the key
  timer**. The off-switch is queued and retried every frame. So the doors stay open as long as the
  player's box overlaps any door of that colour, and the player can move around inside and through
  them. The key turns off, and `key_expired` plus `door_state{open:false}` fire, **in the same tick
  the box has fully left the door tiles**. It never happens earlier, even if the box straddles two
  door tiles.
- **Renderer API during that hold:** `is_key_active()` returns true, `is_tile_solid_now(door)`
  returns false, `key_expiry_pending()` returns true, and `key_time_left()` returns 0.
- **Pickup while inside a gate:** same rule in reverse. The key stays inactive and the gate stays
  open until the box leaves the gate. The key then activates in that tick, with the timer from the
  original pickup. EE quirk: if the player stays in the gate for 5 s or more, the queued activation
  is dropped (`setKey` with `fromqueue` returns early).

## Replays, snapshots, determinism
- `EESim.snapshot() -> Array` / `restore(s)`: the full mutable state. You can restore any snapshot any
  number of times, in any order, and continue bit-identically. `state_hash()` hashes the whole
  state. **Packed arrays are shared by reference in Godot 4**, so the sim never writes `tiles`,
  `_lookup` or `_secrets` in place. It swaps in a modified copy instead (rare: coin pickups and
  secret reveals), which makes the snapshots cheap. Renderers should therefore read `sim.tiles`
  fresh and not cache the array.
- `EEReplay` (`ee_replay.gd`): call `record(input)` before each `sim.tick(input)`. To play back, call
  `start(sim)` (it resets the sim), then `step(sim)` once per physics tick, or `play_all(sim)`. Use
  `save(path)` / `EEReplay.load_file(path)` for files, and `meta` for arbitrary metadata. The format
  is one flag byte per tick, run-length encoded: 3000 random-input ticks come to 367 bytes. The sim
  has no wall clock and a seeded portal RNG, so replays are bit-exact (tested).
- `scripts/physics/route_descent.eerp`: a physics-verified run from spawn to the upper-earth cave
  (see `LEVEL_ROUTE.md`).
