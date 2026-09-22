# Forgotten Veil: route survey (topological)

All coordinates are **tiles** (x right, y down; world = `(x+0.5, -(y+0.5))`). The level is 400x200.
The spawn is (2,56). The finish block **121 is at (394,74)**.

This is a light survey. It is a BFS over tiles, not a physics search: gravity is ignored, key and
switch doors count as open, and coin doors open once enough gold coins have been collected.
Generator: `tests/physics_fv_route.gd`, which runs in about 2 s headless. `WRITE=1` rewrites
`levels/config/forgotten_veil_route.json` (258 sparse waypoints with notes).

## Structure

- **The finish needs all 16 gold coins.** The BFS reaches 121 only through portal 81→82, from (274,188) to
  (350,110), followed by coin door **43 #16** at (349,109). Coin door #16 also stands at (50,55)/(51,55)
  next to the spawn, and at (330,101), (355,109) and (275,188).
- Coin doors #1…#15 are spread across the map. They gate the order of the tour: #3 (68,102) and
  (220,192), #4 (6,184), #7 (111,177), #10 (316,183), #13 (289,134) and (253,177), #8 (201,162).
- The level is a **portal maze**: 187 × 242 and 22 × invisible 381. Many one-way entry portals
  carry id 1 (nothing targets them). Portals with `target == id` or a missing
  target are inert landing pads.
- **Purple switches** (id = rotation): #1 at (199,42), (182,84) and (204,90), #0 at (333,134) and
  (326,135). Each touch toggles, and switches survive death. Id 1 opens the purple door row
  (185-203,89) and (210,88), above the invisible portal row (185-203,90). Those portals (400→401)
  land on (182,83). Id 0 opens doors (331,132-133) and closes gates (287,130) and (330,134).
- **Boost row** 115 at (287-332,133): a rightward launcher next to the id-0 gates and switches
  (287,130), (326-333,134-135).
- **Magenta key** at (218-219,43) and **magenta door** 1006 at (209,88), next to purple door (210,88)
  and pink one-way 1004 (199,88, rotation 0 = passable moving left). The door opens for 5 s.
- The piano column 77 at x=396-397, y=14-49, on the right edge, is sound only (`piano` events).
- Invisible gravity: 412 (up) at (329,21), and the invisible dot column 414 at (186,112-115).
- Blue coins: 8 in total, all reachable. None are needed (there are no blue coin doors).

## Tour (greedy, nearest coin first)

1. Spawn (2,56) → gold coins (26,70) and (13,110).
2. Portal 14→2 at (77,109)→(79,103) → coin (79,80).
3. Portal 92→93 at (1,15)→(195,39), the upper-centre spire area → blue coin (205,24) → coins
   (213,88), (268,84) and (348,86).
4. Back through 93→92 → portal 1→2 at (83,88) → coin door #3 (68,102) → portal 48→47 at (67,103) into
   the bottom corridors at (219,191) → door #3 (220,192) → portal 49→50 at (228,198)→(7,165).
5. Door #4 (6,184) → portal 15→16 at (4,164)→(72,137) → coins (72,138), (61,160) and (85,183)
   (via 98→99) → portals 17/18 → coin (111,168).
6. Door #7 (111,177) → portal 60→59 at (112,176)→(276,195) → 67→68 at (240,177)→(312,183) → door
   #10 (316,183) → coins (315,175), (346,191), (377,163), (332,143) and (324,119).
7. Portal 1→42 at (323,127)→(328,135): **purple switch #0** (326,135) → 1→43 at (325,135)→(285,129)
   → door #13 (289,134) → 74→73 at (288,135)→(254,177) → door #13 (253,177) → 61→62 at
   (224,183)→(199,160) → door #8 (201,162) → coin 16 at (211,174).
8. Back through 62→61 → portal 81→82 at (274,188)→(350,110) → **coin door #16** (349,109) → **121**
   (394,74).

## Caveats

- The survey is topological. It ignores gravity, arrows, boosts and jump height, so it can list
  segments that are physically one-way or unreachable. Unlike the Odyssey survey, no physics
  replay verifies it.
- Key and purple doors are assumed open. In play, a door crossed on the tour needs its key taken
  within 5 s, or its switch in the right state. The tour touches purple switch #0 only once (step 7).
- When several portals share the target id (for example the many id-1 portals), EE picks the exit
  at random. The sim uses a seeded RNG, so a given replay is deterministic, but the arrival point
  can differ from the one BFS chose.
