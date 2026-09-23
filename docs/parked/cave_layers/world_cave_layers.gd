class_name WorldCaveLayers
extends Node3D
## Forgotten Veil earth caves as DEEP SPACES (the cave version of WorldForest's layered slabs): the cave's
## back wall is pushed far back (WorldDepth, CAVE_EXTRA), and between the play plane and that wall stand
## big rock MASSES derived from the cave's own shape, seen face-on at clearly different depths:
##   layer 0 (near, front z ~ -4.2): stalactites hanging from the ceiling line and stalagmites rising from
##     the floor line, tile-stepped, tapering
##   layer 1 (mid, front z ~ -8.5): full-height rock pillars every 7-11 tiles plus strata shelves along the
##     ceiling
## Each layer's cells greedy-merge into box slabs (one colour per layer, world-space rock texture in
## cave_rock.gdshader, fog toward the cave gloom per layer). Everything stays inside the cave's own tiles
## (never over solids, never in front of the play plane) and casts no shadow. Blocky, tile-aligned.

const LAYER_FRONT: Array[float] = [-3.6, -7.0]
const LAYER_DEPTH: Array[float] = [1.4, 1.8]
const LAYER_FOG: Array[float] = [0.08, 0.25]
const MIN_CAVE := 30          # tiles: smaller earth rooms get no masses

var stats := {}
var _grid := {}               # Vector3i(x, y, layer) -> true
var _rng := RandomNumberGenerator.new()

func build(depth: WorldDepth) -> void:
	var t := depth.terrain
	var W := t.W
	var H := t.H
	_rng.seed = 4711
	var n := W * H
	var earth := PackedByteArray()
	earth.resize(n)
	for i in n:
		earth[i] = 1 if depth.room[i] != 0 and depth.room_earth[i] and not depth.win[i] and not t.solid[i] else 0
	# connected earth-cave regions
	var seen := PackedByteArray()
	seen.resize(n)
	var caves := 0
	for start in n:
		if seen[start] or not earth[start]:
			continue
		var comp := PackedInt32Array([start])
		seen[start] = 1
		var qi := 0
		while qi < comp.size():
			var i := comp[qi]; qi += 1
			var x := i % W
			for o in [-1, 1, -W, W]:
				var j: int = i + o
				if j < 0 or j >= n or (o == -1 and x == 0) or (o == 1 and x == W - 1):
					continue
				if not seen[j] and earth[j]:
					seen[j] = 1
					comp.append(j)
		if comp.size() < MIN_CAVE:
			continue
		caves += 1
		_cave_masses(comp, earth, W, H)
	_build_mesh(depth)
	stats = {"caves": caves, "cells": _grid.size()}

## Masses of one cave from its column profile (ceiling / floor rows of each column's air runs).
func _cave_masses(comp: PackedInt32Array, earth: PackedByteArray, W: int, _H: int) -> void:
	var cols := {}
	for i in comp:
		var x := i % W
		var y := i / W
		if not cols.has(x):
			cols[x] = []
		(cols[x] as Array).append(y)
	var xs := cols.keys()
	xs.sort()
	# runs per column: [top, bottom] of contiguous cave air
	var runs := {}
	for x in xs:
		var ys: Array = cols[x]
		ys.sort()
		var rr: Array = []
		var a: int = ys[0]
		var b: int = ys[0]
		for k in range(1, ys.size()):
			if ys[k] == b + 1:
				b = ys[k]
			else:
				rr.append(Vector2i(a, b))
				a = ys[k]
				b = ys[k]
		rr.append(Vector2i(a, b))
		runs[x] = rr
	# layer 1: pillars every 7-11 tiles (2-3 wide) through tall runs; ceiling strata shelves elsewhere
	var next_pillar: int = int(xs[0]) + 3 + _rng.randi() % 5
	var shelf_h := 1
	for x in xs:
		for r: Vector2i in runs[x]:
			var h := r.y - r.x + 1
			if h < 3:
				continue
			if x >= next_pillar and x < next_pillar + 3 and h >= 5:
				for y in range(r.x, r.y + 1):
					_add(x, y, 1, earth, W)
			else:
				# ceiling shelf, its lower edge wandering 1-2 tiles; never deeper than a third of the run
				var sh := mini(shelf_h, h / 3)
				for y in range(r.x, r.x + sh):
					_add(x, y, 1, earth, W)
				# stalagmite hummocks on the floor of the mid layer
				if _rng.randf() < 0.3:
					_add(x, r.y, 1, earth, W)
		if x >= next_pillar + 2 + _rng.randi() % 2:
			next_pillar = x + 7 + _rng.randi() % 5
		if _rng.randf() < 0.3:
			shelf_h = clampi(shelf_h + (1 if _rng.randf() < 0.5 else -1), 1, 3)
	# layer 0: stalactites / stalagmites, tile-stepped cones, sparse
	var i2 := 0
	while i2 < xs.size():
		var x: int = xs[i2]
		var step := 4 + _rng.randi() % 5
		for r: Vector2i in runs[x]:
			var h := r.y - r.x + 1
			if h < 5:
				continue
			var down := _rng.randf() < 0.65
			var ln := clampi(int(h * _rng.randf_range(0.25, 0.45)), 2, 6)
			var w := 2 + _rng.randi() % 2
			for k in ln:
				var ww := maxi(1, w - (k * w) / ln)
				var y := r.x + k if down else r.y - k
				for dx in ww:
					_add(x + dx, y, 0, earth, W)
		i2 += step

func _add(x: int, y: int, layer: int, earth: PackedByteArray, W: int) -> void:
	if x < 0 or x >= W or y < 0:
		return
	var i := y * W + x
	if i >= earth.size() or not earth[i]:
		return   # masses stay inside the cave's own tiles
	_grid[Vector3i(x, y, layer)] = true

## Greedy merge (row runs, stacked downward) -> one MultiMesh of box slabs per layer.
func _build_mesh(depth: WorldDepth) -> void:
	var done := {}
	var keys := _grid.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var per_layer := [[], []]
	for key: Vector3i in keys:
		if done.has(key):
			continue
		var w := 1
		while _grid.has(key + Vector3i(w, 0, 0)) and not done.has(key + Vector3i(w, 0, 0)):
			w += 1
		var h := 1
		while true:
			var ok := true
			for dx in w:
				var k2 := key + Vector3i(dx, h, 0)
				if not _grid.has(k2) or done.has(k2):
					ok = false
					break
			if not ok:
				break
			h += 1
		for dy in h:
			for dx in w:
				done[key + Vector3i(dx, dy, 0)] = true
		per_layer[key.z].append(Rect2i(key.x, key.y, w, h))
	var sh := load("res://shaders/world/cave_rock.gdshader")
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for li in 2:
		var rects: Array = per_layer[li]
		if rects.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = rects.size()
		var d: float = LAYER_DEPTH[li]
		for k in rects.size():
			var r: Rect2i = rects[k]
			var c := Vector3(r.position.x + r.size.x * 0.5, -r.position.y - r.size.y * 0.5, LAYER_FRONT[li] - d * 0.5)
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(r.size.x, r.size.y, d)), c))
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("fog", LAYER_FOG[li])
		m.set_shader_parameter("level_size", Vector2(depth.W, depth.H))
		m.set_shader_parameter("bg_space_tex", WorldBgSpace.texture(depth.terrain))
		m.set_shader_parameter("bg_space_aux", WorldBgSpace.aux_texture(depth.terrain))
		var mi := MultiMeshInstance3D.new()
		mi.name = "CaveLayer%d" % li
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		stats["slabs_%d" % li] = rects.size()
