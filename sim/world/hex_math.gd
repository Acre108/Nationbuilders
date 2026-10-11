extends RefCounted
## Pointy-top axial hexes in world tile units (docs/WORLD_MAP.md §2).
## Hex (0, 0) is centred on the origin; `point` arguments are tile-space XZ.
const WIDTH := 20.0 # Flat-to-flat.
const RADIUS := WIDTH / sqrt(3.0) # Centre to corner.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1)]

static func centre(hex: Vector2i) -> Vector2:
	return Vector2(WIDTH * (hex.x + hex.y * 0.5), RADIUS * 1.5 * hex.y)

static func from_point(point: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * point.x - point.y / 3.0) / RADIUS
	var r := (2.0 / 3.0 * point.y) / RADIUS
	return _round(q, r)

static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2

static func _round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	if dq > dr and dq > absf(rs - s):
		rq = -rr - rs
	elif dr > absf(rs - s):
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))
