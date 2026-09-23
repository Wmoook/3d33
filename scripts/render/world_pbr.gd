class_name WorldPbr
extends RefCounted
## Binds the photoscanned PBR detail library (shaders/world/pbr_detail.gdshaderinc) to a material.
## The arrays hold detail only (grey-balanced luminance, height, AO, roughness, normal); every hue stays
## the painting's. See assets/world/pbr/LICENSES.md (all CC0, Poly Haven).

const MAT_TEX := "res://assets/world/pbr/pbr_mat.png"
const NRM_TEX := "res://assets/world/pbr/pbr_nrm.png"

static var _mat: Texture2DArray
static var _nrm: Texture2DArray

## odyssey: selects the red-earth soil scan for the Odyssey earth layer.
static func bind(material: ShaderMaterial, odyssey := false, strength := 1.0) -> void:
	if _mat == null:
		_mat = load(MAT_TEX)
		_nrm = load(NRM_TEX)
	material.set_shader_parameter("pbr_mat_tex", _mat)
	material.set_shader_parameter("pbr_nrm_tex", _nrm)
	material.set_shader_parameter("pbr_level", 1 if odyssey else 0)
	material.set_shader_parameter("pbr_strength", strength)
