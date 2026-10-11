class_name HeightDeltas
extends RefCounted

## Sculpted height edits (Location Studio S5, docs/LOCATION_EDITOR_PLAN.md §4):
## sparse 128 m tiles of 129 x 129 float deltas at 1 m spacing over a
## location's terrain crop. Effective ground = DEM + delta, so a DEM refresh
## keeps the edits. Neighbouring tiles share their edge row and column.
##
## get_height() is the hottest worker path: tiles sit in a flat array indexed
## by tile coordinate (no Dictionary lookups), and a provider without deltas
## never calls in here.
##
## Worker-safe and immutable, like ZoneOverrides: with_tiles() returns a new
## object sharing unchanged tiles; the owner swaps the reference, then
## rebuilds what stands on the changed ground (copy-on-write).

const TILE_SIZE := 128.0
const SPACING := 1.0
const TILE_VERTICES := 129
const TILE_SAMPLES := TILE_VERTICES * TILE_VERTICES
const TILE_BYTES := TILE_SAMPLES * 4
## Deltas are clamped to ±LIMIT metres.
const LIMIT := 50.0

var origin := Vector2.ZERO
var columns := 0
var rows := 0
## The largest raise and deepest cut, metres (0 when empty).
var min_delta := 0.0
var max_delta := 0.0
## World rect of the sculpted tiles (empty when none): the provider tests it
## before calling sample(), so unsculpted ground pays no call.
var extent := Rect2()
## Flat [tz * columns + tx] -> PackedFloat32Array (TILE_SAMPLES) or null.
var _tiles: Array = []
var _count := 0


static func create(world_size: float) -> HeightDeltas:
	var result := HeightDeltas.new()
	result.origin = Vector2(-world_size * 0.5, -world_size * 0.5)
	result.columns = ceili(world_size / TILE_SIZE)
	result.rows = result.columns
	result._tiles.resize(result.columns * result.rows)
	return result


func is_empty() -> bool:
	return _count == 0


## Bilinear delta at a world XZ; 0 outside painted tiles.
func sample(x: float, z: float) -> float:
	if _count == 0: return 0.0
	var px := x - origin.x
	var pz := z - origin.y
	if px < 0.0 or pz < 0.0: return 0.0
	var tx := mini(int(px / TILE_SIZE), columns - 1)
	var tz := mini(int(pz / TILE_SIZE), rows - 1)
	if tx >= columns or tz >= rows: return 0.0
	var tile: Variant = _tiles[tz * columns + tx]
	if tile == null: return 0.0
	var lx := px - tx * TILE_SIZE
	var lz := pz - tz * TILE_SIZE
	if lx > TILE_SIZE or lz > TILE_SIZE: return 0.0
	var i := mini(int(lx), TILE_VERTICES - 2)
	var j := mini(int(lz), TILE_VERTICES - 2)
	var fx := lx - i
	var fz := lz - j
	var data: PackedFloat32Array = tile
	var k := j * TILE_VERTICES + i
	var top := lerpf(data[k], data[k + 1], fx)
	var bottom := lerpf(data[k + TILE_VERTICES], data[k + TILE_VERTICES + 1], fx)
	return lerpf(top, bottom, fz)


## The delta at global vertex (gx, gz) (whole metres from the origin).
func vertex(gx: int, gz: int) -> float:
	for owner in owners(gx, gz):
		var tile: Variant = _tiles[owner.y * columns + owner.x]
		if tile != null: return (tile as PackedFloat32Array)[local_index(owner, gx, gz)]
	return 0.0


## Tiles holding global vertex (gx, gz): up to four on shared edges.
func owners(gx: int, gz: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var n := TILE_VERTICES - 1
	var xs := [gx / n]
	if gx % n == 0 and gx > 0: xs.append(gx / n - 1)
	var zs := [gz / n]
	if gz % n == 0 and gz > 0: zs.append(gz / n - 1)
	for tz in zs:
		for tx in xs:
			if tx >= 0 and tz >= 0 and tx < columns and tz < rows: result.append(Vector2i(tx, tz))
	return result


## Index of global vertex (gx, gz) inside tile `owner`.
static func local_index(owner: Vector2i, gx: int, gz: int) -> int:
	var n := TILE_VERTICES - 1
	return (gz - owner.y * n) * TILE_VERTICES + (gx - owner.x * n)


func tile(key: String) -> PackedFloat32Array:
	var coord := ZoneOverrides.parse_key(key)
	if coord.x < 0 or coord.x >= columns or coord.y < 0 or coord.y >= rows: return PackedFloat32Array()
	var value: Variant = _tiles[coord.y * columns + coord.x]
	return value if value != null else PackedFloat32Array()


func keys() -> PackedStringArray:
	var result := PackedStringArray()
	for index in _tiles.size():
		if _tiles[index] != null: result.append("%d_%d" % [index % columns, index / columns])
	return result


func tile_rect(key: String) -> Rect2:
	var coord := ZoneOverrides.parse_key(key)
	return Rect2(origin + Vector2(coord) * TILE_SIZE, Vector2.ONE * TILE_SIZE)


## A new object with `changes` ({key: PackedFloat32Array, or empty to clear})
## applied; a tile of all zeros is dropped. This object is not modified.
func with_tiles(changes: Dictionary) -> HeightDeltas:
	var result := HeightDeltas.new()
	result.origin = origin
	result.columns = columns
	result.rows = rows
	result._tiles = _tiles.duplicate()
	for key in changes:
		var coord := ZoneOverrides.parse_key(key)
		if coord.x < 0 or coord.x >= columns or coord.y < 0 or coord.y >= rows: continue
		var values: PackedFloat32Array = changes[key]
		var keep := values.size() == TILE_SAMPLES and _has_any(values)
		result._tiles[coord.y * columns + coord.x] = values if keep else null
	for index in result._tiles.size():
		var value: Variant = result._tiles[index]
		if value == null: continue
		var rect := Rect2(result.origin + Vector2(index % columns, index / columns) * TILE_SIZE, Vector2.ONE * TILE_SIZE)
		result.extent = rect if result._count == 0 else result.extent.merge(rect)
		result._count += 1
		for h in value as PackedFloat32Array:
			result.min_delta = minf(result.min_delta, h)
			result.max_delta = maxf(result.max_delta, h)
	return result


static func _has_any(values: PackedFloat32Array) -> bool:
	for h in values:
		if h != 0.0: return true
	return false


# --- Sidecars and the edits section ------------------------------------------

static func tile_path(key: String, values: PackedFloat32Array) -> String:
	return EditTileFiles.path_for("heights", "heights", key, values.to_byte_array())


static func load_section(section: Dictionary, edits_path: String, world_size: float, pending: Dictionary = {}) -> Dictionary:
	var result := create(world_size)
	var read := EditTileFiles.read_all(section.get("tiles", {}), edits_path, TILE_BYTES, pending)
	if not read.ok: return read
	var changes := {}
	for key in read.tiles: changes[key] = (read.tiles[key] as PackedByteArray).to_float32_array()
	return {"ok": true, "deltas": result.with_tiles(changes) if not changes.is_empty() else result}


static func section_errors(section: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not section is Dictionary:
		errors.append("heights must be an object")
		return errors
	if section.is_empty(): return errors
	for key in section:
		if not key in ["tile_size", "spacing", "tiles", "flattened"]: errors.append("heights: unknown field " + str(key))
	if not HeightmapLocationLoader._finite_number(section.get("tile_size")) or float(section.tile_size) != TILE_SIZE:
		errors.append("heights.tile_size must be %d" % TILE_SIZE)
	if not HeightmapLocationLoader._finite_number(section.get("spacing")) or float(section.spacing) != SPACING:
		errors.append("heights.spacing must be %d" % SPACING)
	var tiles: Variant = section.get("tiles")
	if not tiles is Dictionary:
		errors.append("heights.tiles must be an object")
	else:
		for key in tiles:
			var coord := ZoneOverrides.parse_key(str(key))
			if coord.x < 0 or coord.y < 0: errors.append("heights.tiles: invalid tile key %s" % key)
			elif not EditTileFiles.valid_path("heights", "heights", str(key), tiles[key]): errors.append("heights.tiles.%s must be heights/%s.<sha12>.heights" % [key, key])
	var flattened: Variant = section.get("flattened", [])
	if not flattened is Array:
		errors.append("heights.flattened must be an array")
	else:
		for record in flattened:
			if not record is Dictionary or not BuildingDefinition.numbers(record.get("centre"), 2) \
					or not HeightmapLocationLoader._finite_number(record.get("radius")) or not HeightmapLocationLoader._finite_number(record.get("target_m")) \
					or not record.get("basis") is String:
				errors.append("heights.flattened records need centre [x, z], radius, target_m and basis")
				break
	return errors


## Flattened areas whose effective height has drifted from their recorded
## target by more than `tolerance` metres (a DEM refresh moved the ground
## under the deltas): [{record, height}].
static func drifted(flattened: Array, height_at: Callable, tolerance: float = 0.1) -> Array:
	var result := []
	for record in flattened:
		var h: float = height_at.call(float(record.centre[0]), float(record.centre[1]))
		if absf(h - float(record.target_m)) > tolerance: result.append({"record": record, "height": h})
	return result
