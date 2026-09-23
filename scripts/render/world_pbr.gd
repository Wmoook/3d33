class_name WorldPbr
extends RefCounted
## Binds the photoscanned PBR detail library (shaders/world/pbr_detail.gdshaderinc) to a material.
## The arrays hold detail only (grey-balanced luminance, height, AO, roughness, normal); every hue stays
## the painting's. See assets/world/pbr/LICENSES.md (all CC0, Poly Haven).

const DETAIL_TEX := "res://assets/world/pbr/pbr_detail.png"   # Texture2DArray, 13 layers (see the include)

static var _tex: TextureLayered

## odyssey: selects the red-earth soil scan for the Odyssey earth layer. terrain (optional): builds the
## per-tile canopy mask so tree crowns get the leaf scan and ground mantles the lawn scan.
static func bind(material: ShaderMaterial, odyssey := false, strength := 1.0, terrain: WorldTerrain = null) -> void:
	if _tex == null:
		_tex = load(DETAIL_TEX)
	material.set_shader_parameter("pbr_tex", _tex)
	material.set_shader_parameter("pbr_level", 1 if odyssey else 0)
	material.set_shader_parameter("pbr_strength", strength)
	if terrain:
		material.set_shader_parameter("pbr_canopy_tex", ImageTexture.create_from_image(canopy_mask(terrain)))
		material.set_shader_parameter("pbr_level_size", Vector2(terrain.W, terrain.H))

## RGBA8, one texel per tile (bilinear in the shader):
##   R = 255 for tree-crown foliage (WorldGrass.canopy_map)
##   G = leaf-litter weight on the ground under / beside crowns (WorldFoliage.litter_map)
##   B = lawn depth below its open top (0 at the top tile .. 255 at >= 4 tiles): turf side, roots lower down
##   A = ruin-ledge weight (stone with open air above = 255, the tile under it ~110; open sides ~70): where
##       moss / lichen gathers
static func canopy_mask(terrain: WorldTerrain) -> Image:
	var W := terrain.W
	var H := terrain.H
	var cm := WorldGrass.canopy_map(terrain)
	var lm := WorldFoliage.litter_map(terrain)
	var b := PackedByteArray()
	b.resize(W * H * 4)
	for x in W:
		var depth := -1
		for y in H:
			var i := y * W + x
			b[i * 4] = 255 if cm[i] else 0
			b[i * 4 + 1] = lm[i]
			var m: int = terrain.mat_ids[i]
			if terrain.solid[i] and not cm[i] and WorldGrass.is_leafy(m):
				depth = 0 if (y == 0 or not terrain.solid[i - W]) else (depth + 1 if depth >= 0 else 4)
				b[i * 4 + 2] = clampi(depth * 64, 0, 255)
			else:
				depth = -1
				b[i * 4 + 2] = 255 if terrain.solid[i] else 0
			if terrain.solid[i] and m == WorldPalette.M_RUIN:
				var w := 0
				if y > 0 and not terrain.solid[i - W]:
					w = 255
				elif y > 1 and terrain.solid[i - W] and not terrain.solid[i - 2 * W]:
					w = 110
				if w < 70 and ((x > 0 and not terrain.solid[i - 1]) or (x < W - 1 and not terrain.solid[i + 1])):
					w = 70
				b[i * 4 + 3] = w
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, b)
