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

## RG8, one texel per tile: R = 255 for tree-crown foliage (WorldGrass.canopy_map), G = leaf-litter
## weight on the ground under / beside crowns (WorldFoliage.litter_map).
static func canopy_mask(terrain: WorldTerrain) -> Image:
	var W := terrain.W
	var H := terrain.H
	var cm := WorldGrass.canopy_map(terrain)
	var lm := WorldFoliage.litter_map(terrain)
	var b := PackedByteArray()
	b.resize(W * H * 2)
	for i in W * H:
		b[i * 2] = 255 if cm[i] else 0
		b[i * 2 + 1] = lm[i]
	return Image.create_from_data(W, H, false, Image.FORMAT_RG8, b)
