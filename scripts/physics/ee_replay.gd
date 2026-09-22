class_name EEReplay
extends RefCounted
## Deterministic per-tick input recorder / replayer for EESim.
## EESim is fully deterministic (no wall clock; the portal RNG is seeded in reset()), so replaying
## the recorded inputs from sim.reset() reproduces a run bit-exactly.
##
## Record:   rep.record(input) right BEFORE sim.tick(input), for every tick after sim.reset().
## Replay:   rep.start(sim) once, then each physics step: rep.step(sim) (returns false at the end),
##           or rep.play_all(sim) to run everything at once.
## Storage:  one byte per tick (bit flags), run-length encoded -> tiny files (a minute of play
##           is typically a few hundred bytes). save()/load_file() use user:// paths.

const MAGIC := 0x50524545     # "EERP" little-endian
const VERSION := 1

const B_LEFT := 1
const B_RIGHT := 2
const B_UP := 4
const B_DOWN := 8
const B_JUMP := 16
const B_JUMP_PRESSED := 32
const B_GOD := 64

## Raw per-tick input bytes.
var frames := PackedByteArray()
## Optional metadata (level name, label, final state hash...). Saved with the replay.
var meta := {}

var cursor := 0
var _inp := EEInput.new()


# ---------------------------------------------------------------- recording

func clear() -> void:
	frames = PackedByteArray()
	cursor = 0


## Call once per tick, before sim.tick(input) (tick() consumes the one-shot flags).
func record(input: EEInput) -> void:
	frames.append(encode_input(input))


func tick_count() -> int:
	return frames.size()


static func encode_input(i: EEInput) -> int:
	var b := 0
	if i.left: b |= B_LEFT
	if i.right: b |= B_RIGHT
	if i.up: b |= B_UP
	if i.down: b |= B_DOWN
	if i.jump: b |= B_JUMP
	if i.jump_pressed: b |= B_JUMP_PRESSED
	if i.god_toggle: b |= B_GOD
	return b


static func decode_input(b: int, out: EEInput) -> void:
	out.left = b & B_LEFT != 0
	out.right = b & B_RIGHT != 0
	out.up = b & B_UP != 0
	out.down = b & B_DOWN != 0
	out.jump = b & B_JUMP != 0
	out.jump_pressed = b & B_JUMP_PRESSED != 0
	out.god_toggle = b & B_GOD != 0


func input_at(tick_index: int, out: EEInput) -> void:
	decode_input(frames[tick_index], out)


# ---------------------------------------------------------------- playback

## Resets the sim and rewinds the cursor.
func start(sim: EESim) -> void:
	sim.reset()
	cursor = 0


## Plays one recorded tick. Returns false (and does nothing) when the replay is finished.
func step(sim: EESim) -> bool:
	if cursor >= frames.size():
		return false
	decode_input(frames[cursor], _inp)
	cursor += 1
	sim.tick(_inp)
	return true


func is_finished() -> bool:
	return cursor >= frames.size()


## Reset + play every tick (or up to `until` ticks).
func play_all(sim: EESim, until := -1) -> void:
	start(sim)
	var n := frames.size() if until < 0 else mini(until, frames.size())
	while cursor < n:
		step(sim)


# ---------------------------------------------------------------- serialization

func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, MAGIC)
	out.encode_u32(4, VERSION)
	out.encode_u32(8, frames.size())
	var m := var_to_bytes(meta)
	_put_varint(out, m.size())
	out.append_array(m)
	# RLE: (byte value, varint run length)
	var i := 0
	var n := frames.size()
	while i < n:
		var v := frames[i]
		var j := i + 1
		while j < n and frames[j] == v:
			j += 1
		out.append(v)
		_put_varint(out, j - i)
		i = j
	return out


static func from_bytes(b: PackedByteArray) -> EEReplay:
	if b.size() < 12 or b.decode_u32(0) != MAGIC or b.decode_u32(4) != VERSION:
		push_error("EEReplay: bad data")
		return null
	var r := EEReplay.new()
	var total := b.decode_u32(8)
	var p := [12]
	var ml := _get_varint(b, p)
	var m: Variant = bytes_to_var(b.slice(p[0], p[0] + ml))
	r.meta = m if m is Dictionary else {}
	p[0] += ml
	r.frames.resize(total)
	var k := 0
	while p[0] < b.size() and k < total:
		var v := b[p[0]]
		p[0] += 1
		var run := _get_varint(b, p)
		for q in run:
			r.frames[k] = v
			k += 1
	if k != total:
		push_error("EEReplay: truncated data")
		return null
	return r


func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes())
	f.close()
	return OK


static func load_file(path: String) -> EEReplay:
	var b := FileAccess.get_file_as_bytes(path)
	if b.is_empty():
		return null
	return from_bytes(b)


static func _put_varint(out: PackedByteArray, v: int) -> void:
	while v >= 0x80:
		out.append((v & 0x7F) | 0x80)
		v >>= 7
	out.append(v)


static func _get_varint(b: PackedByteArray, p: Array) -> int:
	var v := 0
	var shift := 0
	while true:
		var c := b[p[0]]
		p[0] += 1
		v |= (c & 0x7F) << shift
		if c & 0x80 == 0:
			break
		shift += 7
	return v
