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

## R8, one texel per tile: 255 = tree canopy foliage (see WorldGrass.canopy_column), else 0.
static func canopy_mask(terrain: WorldTerrain) -> Image:
	var W := terrain.W
	var H := terrain.H
	var b := PackedByteArray()
	b.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			if terrain.solid[i] and WorldGrass.is_leafy(terrain.mat_ids[i]) and WorldGrass.canopy_column(terrain, x, y, W, H):
				b[i] = 255
	return Image.create_from_data(W, H, false, Image.FORMAT_R8, b)
