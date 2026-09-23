# PBR detail library: sources and licences

All source scans are from **Poly Haven** (https://polyhaven.com) and are released under **CC0 1.0**
(public domain, no attribution required; credited here anyway). Downloaded 2026-09-22 at 2K (JPG) via
the Poly Haven API (`https://api.polyhaven.com/files/<id>`), then processed by the surface-detail agent:
resized to 1024 px, luminance extracted and grey-balanced (large-scale tone removed, contrast normalised,
mean = 0.5), cavity AO multiplied in, height normalised (1st-99th percentile), OpenGL normals kept.
No colour (hue) is kept: the terrain tints every layer with the painting's per-tile colour.

## `pbr_detail.png` (Texture2DArray, 13 layers of 1024x1024, stacked vertically)
R = luminance x0.5 (x AO), G = height, B/A = normal x/y (GL).

| Layer | Constant | Poly Haven asset | URL |
|---|---|---|---|
| 0 | PBR_GRASS | leafy_grass | https://polyhaven.com/a/leafy_grass |
| 1 | PBR_MOSS | mossy_rock | https://polyhaven.com/a/mossy_rock |
| 2 | PBR_ASHLAR | castle_wall_varriation | https://polyhaven.com/a/castle_wall_varriation |
| 3 | PBR_STRATA | cliff_side | https://polyhaven.com/a/cliff_side |
| 4 | PBR_ROCK | rock_face_03 | https://polyhaven.com/a/rock_face_03 |
| 5 | PBR_BARK | bark_brown_02 | https://polyhaven.com/a/bark_brown_02 |
| 6 | PBR_LITTER | forest_leaves_02 | https://polyhaven.com/a/forest_leaves_02 |
| 7 | PBR_SOIL | brown_mud | https://polyhaven.com/a/brown_mud |
| 8 | PBR_SAND | sand_01 | https://polyhaven.com/a/sand_01 |
| 9 | PBR_MARBLE | marble_rock_01 | https://polyhaven.com/a/marble_rock_01 |
| 10 | PBR_BASALT | dark_rock | https://polyhaven.com/a/dark_rock |
| 11 | PBR_REDEARTH | red_dirt_mud_01 | https://polyhaven.com/a/red_dirt_mud_01 |
| 12 | PBR_LICHEN | lichen_rock | https://polyhaven.com/a/lichen_rock |

## Leaf textures
Composited from the individual leaf scans of the **shrub_04** model (https://polyhaven.com/a/shrub_04,
CC0): diffuse, alpha and GL normal maps, leaves cut out by alpha, rotated and layered into clusters.
- `leaf_cluster_albedo.png` (2048, 2x2 cluster variants): R = leaf luminance (0.5 = mean), G = translucency /
  depth, B = luminance, A = coverage.
- `leaf_cluster_normal.png`: RGB = card-space normal (GL, rotated with each leaf, cupped along the midrib), A = coverage.
- `leaf_single_strip.png` (8 cells of 256): single leaves (R/G/B = luminance, A = coverage) for falling-leaf FX.
