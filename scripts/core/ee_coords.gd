class_name EECoords
## EE pixel space (y down, 16 px/tile) <-> Godot world space (1 unit/tile, y up, gameplay plane z = 0).

const TILE := 16.0

static func px_to_world(px_x: float, px_y: float, z: float = 0.0) -> Vector3:
	return Vector3(px_x / TILE, -px_y / TILE, z)

## Center of the 16x16 player box whose top-left is (px_x, px_y).
static func player_center(px_x: float, px_y: float, z: float = 0.0) -> Vector3:
	return Vector3((px_x + 8.0) / TILE, -(px_y + 8.0) / TILE, z)

## Center of tile (tx, ty).
static func tile_center(tx: int, ty: int, z: float = 0.0) -> Vector3:
	return Vector3(tx + 0.5, -ty - 0.5, z)

static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x), floori(-p.y))
