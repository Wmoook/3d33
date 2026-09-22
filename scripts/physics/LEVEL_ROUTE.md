# EX Crew Odyssey: gameplay survey and route

All coordinates are **tiles** (x right, y down; world = `(x+0.5, -(y+0.5))`). The level is 400x200.
The spawn is (65,11), and the only completion block, **121, is at (54,9)**.

## Verdict (short)

- The **designer's route** is topologically complete and is listed below. The flyover waypoints are
  in `route_waypoints.json`.
- **Under exact EE rules, legit play from the spawn cannot finish this level.** Exhaustive search on
  our sim finds the reachable area closes at a one-way arrow valve in the upper-earth cave
  (x≈244-262, y≈43-56). The spawn and the coin door beside it depend on the only gold coin, and that
  coin lies beyond this valve. So the route is circular without the valve.
- **Physically verified:** spawn → surface → tentacle → cave → west through the red-door band, ending
  at (293,45). `route_descent.eerp` is a bit-exact replay of it (34 s).
- **Also verified:** the corridor after the valve, from the x=262 wall column to the blue keys.
- **Not reachable:** only the step *onto* that wall column. Details are in "Blocking point".

## Key objects

| What | Where |
|---|---|
| Spawn (255) | (65,11), a pocket under the spawn house |
| Completion block 121 | (54,9), in the house attic, between arrows `<` (53,9) and `>` (55,9) with `^` (54,8) above |
| The only gold coin (100) | (331,141), inside a diamond of blue doors (25) at (330-332,139-141) with blue keys (8) around it |
| Coin door 43 (needs 1 coin) | (62,14),(63,14). It joins the spawn pocket to the house interior, which opens at (44-48,10) into the attic with 121 |
| Other coin doors | 91 more, all "1". They are mostly picture pixels. (281,58) sits on top of portal 90 |
| Blue coins (101) | (384,6) (208,18) (233,50) (217,77) (225,91) (192,133) (322,137) (55,144) (222,167) (176,180) (154,196) |
| Keys | Red 6 ×4929, green 7 ×111, blue 8 ×1094, crown 5 ×848. They are mostly picture pixels. Touching any one activates that colour for 5 s |
| Key doors / gates | Red doors 23 ×1203, green doors 24 ×11, blue doors 25 ×299, red gates 26 ×63, blue gates 28 ×8 |

Coin door 43 at (62,14) is the level's "…and Return!": the spawn pocket and the house interior
share it. The house interior is connected to the attic (121) and to the whole top-left zone (hub,
left sky).

## Portals (id → target, positions)

Portals whose target does not exist are inert: the target is 0, and no portal has id 0. Portals
with `target == id` are also inert.

| id | target | rot | type | positions | effect |
|---|---|---|---|---|---|
| 50 | 51 | 2 | 242 | (15,10) | hub → (374,178) bottom-right lake |
| 51 | 50 | 0 | 242 | (374,178) | back to hub (15,10) |
| 52 | 53 | 2 | 242 | (16,10) | hub → (7,75) under the sign |
| 53 | 52 | 0 | 242 | (7,75) | **underground (west) → hub (16,10)** |
| 54 | 55 | 2 | 242 | (17,10) | hub → (185,101) |
| 55 | 54 | 0 | 242 | (185,101) | back to hub |
| 56 | 57 | 2 | 242 | (18,10) | hub → (153,195) |
| 57 | 56 | 2 | 242 | (153,195) | back to hub |
| 58 | 59 | 2 | 242 | (12,10) | hub → (221,171) |
| 59 | 58 | 0 | 242 | (221,171) | back to hub |
| 64 | 65 | 2 | 242 | (18,15) | hub → (336,95) |
| 65 | 64 | 0 | 242 | (336,95) | back to hub (18,15) |
| 60 | 61 | 2 | 242 | (52,1) | **left sky above the spawn house → (321,137) next to the gold coin** |
| 61 | 60 | 0 | 242 | (321,137) | **coin area → (52,1) (the return)** |
| 90 | 91 | 2 | 242 | (281,59) | under coin door (281,58) → (296,44) |
| 91 | 0 | 2 | 242 | (296,44) | inert (arrival only) |
| 35 | 36 | 1 | 242 | (150,42) | → (194,37) |
| 36 | 0 | 0 | 242 | (194,37) | inert |
| 2 | 0 | 0 | 242 | (212,57) | inert (arrival only: the "anvil") |
| 3 | 2 | 3/2/1 | 381 (invisible) | (218,83) (217,84) (217,85) (203-206,92) (217,98) (216,113) (215,114) (215,115) (214,116) | lower world → (212,57) |
| 3 | 4 | 3/1 | 381 (invisible) | (189,90) (187,100-103) (193,116) (193,117) (194,118) (195,118) | → (205,125) |
| 4 | 4 | 2 | 381 (invisible) | (205,125) | inert (target == id) |
| 10 | 10 | 2 | 242 | (386,135) | inert |
| 11 | 10 | 2 | 242 | (388,155) (370,158) … (348-355,183) (23 tiles) | → (386,135) |
| 20 | 21 | 2 | 242 | (315-317,184) | → (272-273,185) |
| 21 | 30 | 0 | 242 | (272,185) (273,185) | inert (no id 30) |
| 22 | 23 | 2 | 242 | (272,183) (273,183) | → (272-273,181) |
| 23 | 30 | 0 | 242 | (272,181) (273,181) | inert |
| 25 | 10 | 3 | 242 | (275,181) | → (386,135) |

When a target id has several portals, EE picks one at random. EESim uses a seeded RNG. Crossing a
portal rotates the momentum ×1.42 whenever the two rotations differ.

## The designer's route (topological), in order

1. **Spawn (65,11)** → drop into the pocket → run east along rows 13-14 → **red key (78,10)** → **red
   doors (79-81,9-10)** → the east surface.
2. **Surface east.** Tree 2's trunk has red doors (156,10),(156-157,11), with the key (154,12)
   directly before it. Pick up the key, jump, then drop into the 1-tile hole. Tree 3's trunk has red
   doors (279-282,11),(282,10). The canopy of tree 2 touches the ceiling, and so does the roof apex
   (53-54,1), so the **sky is split**: the spawn side cannot walk over to the top-left zone.
3. **Purple tentacle (x≈389-396, y 14-35).** A 1-wide channel with `>`/`<` arrows on both sides
   keeps the ball centred while it falls. A diagonal staircase chute (393,28)→(388,35) follows. At
   the bottom, x=387 rows 36-43 is a column of **up-arrows** (36, 38, 41, 42, 43) with a ceiling
   over (387,36). You get down by **jumping inside the up-arrows**: EE jumps away from gravity, so
   in an up-arrow a jump points down. You land in the big cave at (387,44).
4. **Upper-earth cave (x 245-392, y 37-63).** Go west through the diagonal **red-door band**
   (296-303, 36-44), which has red keys inside it, behind a right-arrow wall.
5. **Arrow valve / shaft (x 253-262, y 40-56).** Everything east of it is physically verified.
   Climb the **right-arrow wall column (262,43-45)**: the side gravity lets you walk up the wall.
   Jump west (away from gravity), then follow the **left-arrow conveyor** (257-258,43) and (250-252,43)
   and the **zero-g dot bridge** (239-249, 43-45) to the **blue keys (235-238,45)** and the
   blue-door **pond (194-240, 44-60)**.
6. Blue pond → the "anvil" shaft (≈206, 52-75) → the lower world (198, 83-121) → west along row 84
   → up through the key corridors (rows 70-72) → **portal 53 at (7,75)**.
7. **Portal 53 → hub (16,10).** The hub is the top-left house and holds the portals to all the deep
   areas: 50/52/54/56/58/64. Those are optional side trips for the blue coins, and each one returns
   to the hub.
8. Hub → the left sky (x 11-51, y 1-9, with dots at (43,2),(45,2),(44,3)) → **portal 60 at (52,1)**.
9. **Portal 60 → (321,137).** Take a blue key (the `j` tiles around the diamond), then pass the
   **blue doors** → **gold coin (331,141)**.
10. Back to **portal 61 (321,137) → (52,1)**. Then the left sky → down the west side
    (35-39, 1-14; `<` arrows at (35-39,13-14)) → row 16-18 corridor → the **x=42 up-arrow elevator**
    (42,10-17, ending in a dot at (42,10)) → the attic (43-66, 3-9) → run right along row 9 through
    `<` (53,9) → **121 at (54,9)**. Alternative ending: the coin now opens **coin door (62-63,14)**
    next to the spawn, and the house interior leads up through (44-48,10) into the attic. This is the
    "Go… and Return!".

Key waypoints (tiles): (65,11) spawn · (78,10) red key · (80,9) red doors · (154,12) key /
(156,11) trunk · (281,11) trunk · (394,20) tentacle · (387,44) cave · (300,40) red band ·
(262,44) wall column · (240,45) dot bridge · (215,50) pond · (206,65) anvil shaft ·
(198,100) lower world · (113,84) · (45,72) · (7,75) portal 53 · (16,10) hub · (52,1) portal 60 ·
(321,137) portal 61 · (331,141) gold coin · (52,1) return · (42,17) elevator · (54,9) **121**.

## Blocking point (why EESim can't finish from the spawn)

The shaft (x 253-262, y 44-56) has right-arrows (`>`) on its west side. The band runs diagonally
through x 244-253, y 47-58 and pushes into the shaft, so it is a valve for **eastbound** travel.
There is a left-arrow `<` at (262,47-48) and plain air at (262,46). The only way west is the
right-arrow wall column (262,43-45), which has a solid wall at x=263. The top of the shaft
(245-261, 40-42) is closed above.

To stand on the column you have to enter it at row 43-45. Under the ported rules:

- **Jumping:** the floor is ~13 tiles below and a jump reaches 3.96 tiles.
- **Side-gravity tricks:** there is no wall to push against in the `<`/`>` tiles below the column.
- **What the search found:** the physics search reaches (259-261,44) moving upward. A 460k-node
  fine search (1-tick macros, 0.5 px position resolution) from that exact state still cannot steer
  the ball into x=262.

The corridor itself works. From (262,44), climb (Up), jump (west), then drift with Left, and the
ball reaches the blue keys (238,45) in 57 macros (`ROUTE_LOCAL=262,44,238,45,2,medium`).

Possible explanations:

- An EE online mechanic outside this offline port.
- The designer intended god mode here, or a different spawn (EE "world portal spawn").
- An intended trick my searches don't cover. They are extensive but not a formal proof.

Every ported rule in this area (arrow queue, side-gravity walking and jumping, dots) is covered by
the regression tests.

## Physics-verified reachable area from the spawn

Exhaustive coarse novelty-BFS over EESim (`ROUTE_EXPLORE=1`, 116k expansions until the queue ran
out) reaches 4591 cells and uses **no portal**:

- the east surface (x 65-399, y 1-16);
- the tentacle;
- the upper-earth cave (x 245-392, y 37-63).

## Files

- `route_waypoints.json`: ordered flyover waypoints (119 tiles), from `tests/physics_route_topo.gd`.
  Every segment's first waypoint carries a `note`. Also includes `physics_verified_replay`,
  `physics_verified_until` and `physics_blocked_at`.
- `route_descent.eerp`: an EEReplay of the verified part, 3426 ticks, spawn → (293,45). Its `meta`
  holds the final state hash and a coarse trajectory. Play it with
  `EEReplay.load_file(path).play_all(sim)` or `start(sim)` + `step(sim)` per tick.
- Tools, all under `tests/physics_*`:
  - `physics_route.gd`: leg search with modes `ROUTE_EXPLORE`, `ROUTE_LOCAL`, `ROUTE_PIVOT`,
    `ROUTE_RESUME` and `ROUTE_EXPORT`.
  - `physics_topology.gd`: component graph with door clusters.
  - `physics_dump.gd`, `physics_dump_ids.gd`, `physics_overlay.gd`: region maps.
