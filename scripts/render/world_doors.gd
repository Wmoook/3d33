class_name WorldDoors
extends Node3D
## Dynamic key doors (23/24/25) and key gates (26/28): one sculpted mesh per connected region, drawn in
## the door's minimap colour with glowing key-coloured seams. Every frame each region asks the sim
## whether it is solid right now (sim.is_tile_solid_now) and swaps between the solid material and a
## translucent "passable" ghost. Without a sim: doors closed, gates open (EE initial state).

const VPT := 12
const KEY_RGB := {&"red": Color(1.0, 0.18, 0.22), &"green": Color(0.25, 1.0, 0.3), &"blue": Color(0.25, 0.45, 1.0)}

var sim: Object
var regions: Array = []      # [{node, tile: Vector2i, id, solid_mat, ghost_mat, solid: bool}]
var sdf_tex: Texture2D
var _level: EELevel

func build(lvl: EELevel, terrain: WorldTerrain) -> void:
	_level = lvl
	var W := lvl.width
	var H := lvl.height
	var mask := PackedByteArray()
	mask.resize(W * H)
	var any := false
	for i in W * H:
		var id: int = lvl.fg[i]
		if not WorldPalette.is_key_door(id):
			continue
		mask[i] = 2 if WorldPalette.is_gate(id) else 1
		any = true
	if not any:
		return
	sdf_tex = ImageTexture.create_from_image(WorldSdfBaker.bake(mask, W, H))
	var mats := {}
	var seen := PackedByteArray()
	seen.resize(W * H)
	for start in W * H:
		var id: int = lvl.fg[start]
		if seen[start] or not WorldPalette.is_key_door(id):
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		var mn := Vector2i(start % W, start / W)
		var mx := mn
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			var y := i / W
			mn = Vector2i(mini(mn.x, x), mini(mn.y, y))
			mx = Vector2i(maxi(mx.x, x), maxi(mx.y, y))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var j := ny * W + nx
					if seen[j] or lvl.fg[j] != id:
						continue
					seen[j] = 1
					comp.append(j)
		if not mats.has(id):
			mats[id] = _materials(id, terrain)
		var mi := MeshInstance3D.new()
		var size := mx - mn + Vector2i(3, 3)
		mi.mesh = _grid(size.x, size.y)
		mi.position = Vector3(mn.x - 1, -(mn.y - 1), 0.0)
		mi.custom_aabb = AABB(Vector3(0, -size.y, -3.0), Vector3(size.x, size.y, 4.5))
		mi.material_override = mats[id][0]
		mi.name = "Door%d_%d_%d" % [id, mn.x, mn.y]
		add_child(mi)
		regions.append({"node": mi, "tile": Vector2i(start % W, start / W), "id": id,
			"solid_mat": mats[id][0], "ghost_mat": mats[id][1], "solid": true})

func _materials(id: int, terrain: WorldTerrain) -> Array:
	var col := Color8(156, 45, 70)
	match id:
		24: col = Color8(55, 156, 48)
		25, 28: col = Color8(45, 68, 156)
	var kc: Color = KEY_RGB[WorldPalette.key_color_of(id)]
	var out := []
	for sh in ["res://shaders/world/door.gdshader", "res://shaders/world/door_ghost.gdshader"]:
		var m := ShaderMaterial.new()
		m.shader = load(sh)
		m.set_shader_parameter("door_sdf", sdf_tex)
		m.set_shader_parameter("level_size", Vector2(terrain.W, terrain.H))
		m.set_shader_parameter("channel", 1 if WorldPalette.is_gate(id) else 0)
		m.set_shader_parameter("base_color", col)
		m.set_shader_parameter("key_color", Vector3(kc.r, kc.g, kc.b))
		out.append(m)
	return out

func _grid(tw: int, th: int) -> ArrayMesh:
	var nx := tw * VPT
	var ny := th * VPT
	var verts := PackedVector3Array()
	verts.resize((nx + 1) * (ny + 1))
	var k := 0
	for j in ny + 1:
		for i in nx + 1:
			verts[k] = Vector3(float(i) / VPT, -float(j) / VPT, 0.0)
			k += 1
	var idx := PackedInt32Array()
	idx.resize(nx * ny * 6)
	k = 0
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			var c := a + nx + 1
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = c + 1
			idx[k + 3] = a; idx[k + 4] = c + 1; idx[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Region solidity right now (all tiles of a region share id -> share state).
func _region_solid(r: Dictionary) -> bool:
	var t: Vector2i = r["tile"]
	if sim and sim.has_method(&"is_tile_solid_now"):
		return sim.is_tile_solid_now(t.x, t.y)
	return not WorldPalette.is_gate(r["id"])

func _process(_delta: float) -> void:
	for r in regions:
		var s := _region_solid(r)
		if s == r["solid"]:
			continue
		r["solid"] = s
		var mi: MeshInstance3D = r["node"]
		mi.material_override = r["solid_mat"] if s else r["ghost_mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func set_mask_mode(on: bool) -> void:
	for r in regions:
		for k in ["solid_mat", "ghost_mat"]:
			(r[k] as ShaderMaterial).set_shader_parameter("mask_mode", on)
