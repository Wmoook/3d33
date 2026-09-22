# FORGOTTEN VEIL: Level Bible (lead)

Read this before touching FV. Tile coords (x right, y down). 400x200. Spawn (2,56). Finish 121 at (394,74).
It is a **brutally hard EE minigame level**: 16 trial rooms, each rewarding one gold coin; all 16 open the
coin door #16 → finish. Don't try to route or test the gameplay, but make every place look incredible and
make every mechanic read instantly.

## The map, west → east

| Area (zone) | Tiles (approx) | What it is in the painting | Design intent / what must move |
|---|---|---|---|
| **The Elder Grove** | x0-85, y25-62 | Mountain peaks (x0-30, x45-55) above a dense broadleaf canopy + one tall dark pine (x60-66); under the canopy a DARK hollow with trunk columns (y48-58). Spawn sits here (2,56). Coin door #16 at (50-51,55). | Sun-dappled canopy, leaves drifting, dappled light cookies in the hollow, fireflies in the hollow's shade, birds on the peaks. The hollow is the cozy "start" space. |
| **The Hollow Halls** | x0-110, y60-110 | Earth mass with grey stone temple halls: arrow-conveyor corridors (y75-85), a vertical shaft chamber with the big "X" glass-window motif (x75-95, y78-105), columned galleries. | Stone temple interior, cool shade, dust in the shafts of light from the openings. The arrow fields are the trials' machinery: currents of air/"wind glyphs" that pulse in their direction. |
| **The Sunken West Halls** | x0-140, y110-200 | Long arcaded corridor (y145-155) with fern pots, arrow conveyors; lower chambers (y175-195) packed with arrows + dot columns + portal columns; an aqueduct with a pool at (0-10, 175-195). Dark root-veins in the earth (y120-175). | Deep interior, torch-less: light comes from the gameplay glyphs, portals and cracks. Water in channels flows. Roots look organic. |
| **The Veiled Falls** | x78-170, y125-180 | A water channel runs east along y≈130 (x80-150) and pours off the cliff at x≈133-137 as a tall waterfall into a POOL (x125-170, y165-176); a lone ruined pylon + tree on a stone arm (x140-160, y140-150). | HERO VISTA. Flowing channel surface (west→east), foaming falling sheet, mist, spray, splash rings, rainbow in the spray on sunny side, sun glints on the pool, caustics on the nearby stone. |
| **The Great Spire** | x175-218, y24-175 | The tallest ruin: a tree + twisted dead tree on the summit (y24-40, blue coin at (205,24)), a vast interior SHAFT full of up/left arrows (an updraft machine, y42-88), purple switch-door row (y89), wings with hanging vines, lower tower down to the ground; huge vine drapes. | The monument. Updraft shaft = visible rising air (motes/leaves streaming up the arrow field), vines swaying from every ledge, god rays through the windows, birds circling the top. |
| **The Hanging Gardens / vine bridges** | x215-250, y60-95 | Sagging vine bridges between the two spires (y≈62-66 and y≈88-92), draped with moss. | Vines sway, leaves flutter off, butterflies. |
| **The Twin Spire** | x228-268, y50-185 | Second tower: tree on top (y50-65), rows of portals (the light-blue orbs) inside at y80-82 and y90-92, a vertical portal/arrow column down the core. | Portals are "veils": shimmering membranes between worlds, the level's signature visual. |
| **The Ruined Keep** | x285-320, y75-110 | Broken, jagged towers with a tree in its courtyard, collapsed arches. | Dramatic silhouette against sky; debris, crows/birds, moss. |
| **The Great Hall** | x325-375, y78-112 | A big walled hall with arrow tracks (y87, y92-98), inner fountain/pillar (x355-365, y95-105). | Grand interior; light shafts from the crenellations. |
| **The Eastern Wood** | x370-400, y85-110 | Forest with a dark hollow (like the grove). | Same dappled treatment as the grove. |
| **The Summit Shrine** | x385-400, y70-85 | A small earth PEAK with the **finish trophy 121 on its tip (394,74)**. | FINALE: make the peak a shrine. A soft pillar of light rising from the trophy into the sky (visible from far away), wind-swept grass, the trophy gleaming. The victory moment happens here. |
| **The Lower Sanctum + Sunken Aqueducts** | x140-400, y100-200 | Colonnaded galleries (y110-125), a long boost row (287-332,133) with the purple switch #0, rooms of vertical portal/dot columns, deep aqueducts with water channels and falls (x345-375, y165-195), buried root veins. | Flowing water in every channel (direction from the painting), dripping, echo-y cool light, caustics on ceilings above water. |
| **The ΣX logo** | x300-345, y14-42 | Mossy stone letters with CROWN tiles as gold inlays and blue UP ARROWS under them. | Gilded letters glint; the blue arrow row under it = updraft. |
| **The Winners' Scroll** | x350-397, y0-72 | A huge parchment scroll hanging in the sky; the names are written with CROWNS (gold) and RED KEYS (vermilion) on brown parchment. | ILLUMINATED MANUSCRIPT: crowns = gold-leaf ink, red keys = vermilion ink. They must render as legible LETTERING (flat, inked into the parchment, softly gilded), NOT as floating gems. Keys still flare on touch. |
| **"LOL"** | x215-223, y1-6 | Tiny joke text at the top centre. | Keep it (a wink), stone letters. |
| **Sky** | all | Pastel sky (531) with painted clouds (540) and painted snowy mountain ranges (541/542) behind everything; small white "V" bird shapes (decor) everywhere. | Deep-blue morning gradient, soft cumulus, distant snowy ranges with aerial haze, parallax; the painted "V" birds become real distant birds gliding. |

## Mechanics as art (FV-specific look, readability first)
- **Arrows (gravity 1-3)** fill the trial rooms: keep crisp chevrons, but in FV give the current a "wind" feel
  (pale gold streaks + drifting motes along the flow). **Dots (4)**: calm floating motes.
- **Portals (242, 187 of them) = the Veil**: shimmering vertical membranes/rings of light, rippling when you pass.
  Invisible portals (381): a faint heat-shimmer only.
- **Purple switches/doors (113/184/185)**: rune levers + rune-sealed stone that dissolves.
- **Coin doors (43)**: golden portcullis with its number; **coin door #16**: grand sealed gate.
- **Boost (115)**: carved runner stones with a rushing light streak.
- **Keys**: red (6) mostly used as scroll ink; blue key (8) + magenta (409) are real pickups.
- **Pianos (77)** on the far east edge column (x396-397, y14-49): chime stones.
- Gold coins = relics in 16 trial chambers (world_trials carved runes).

## Ownership reminder
world: terrain, sky, backdrop, water bodies' surfaces as terrain, zones, trials, lighting.
actors2: glyphs, portals, coins, FX (waterfall, channel flow, spray, motes, vines, creatures, shrine beam).
shell: HUD, titles, audio, camera.
