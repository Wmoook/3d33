extends SceneTree
func _check(name: String, m: Mesh, center: Vector3) -> void:
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx = a[Mesh.ARRAY_INDEX]
		var out := 0; var inn := 0
		for i in v.size():
			var d := (v[i] - center)
			if name == "ring":
				var h := Vector3(v[i].x, 0, v[i].z).normalized() * 0.5
				d = v[i] - h
			if d.dot(n[i]) > 0: out += 1
			else: inn += 1
		# winding check on first tri (cross product vs normal): Godot front = clockwise
		var i0 = idx[0] if idx != null and idx.size() > 0 else 0
		print(name, " surf ", s, " verts ", v.size(), " normals out ", out, " in ", inn)
func _init() -> void:
	_check("gem", FxMeshes.gem(), Vector3.ZERO)
	_check("coin", FxMeshes.coin(), Vector3.ZERO)
	_check("shard", FxMeshes.shard(), Vector3(0,-0.04,0.01))
	_check("ring", FxMeshes.ring(0.5,0.05), Vector3.ZERO)
	_check("crown", FxMeshes.crown(), Vector3(0,0.3,0))
	var sm := SphereMesh.new()
	var a := sm.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var p0 := v[idx[0]]; var p1 := v[idx[1]]; var p2 := v[idx[2]]
	var cr := (p1 - p0).cross(p2 - p0)
	print("sphere first tri cross·outward = ", cr.dot((p0+p1+p2)/3.0))
	quit()
