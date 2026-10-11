class_name ZoneOverrides
extends RefCounted

## Painted environment-zone overrides (Location Studio S4, see
## docs/LOCATION_EDITOR_PLAN.md §3): sparse 256 m tiles at 2 m a pixel over a
## location's terrain crop. Each pixel holds a target zone (EnvironmentZones.Zone)
## and an override strength; unpainted pixels (strength 0) change nothing.
##
## Worker-safe and immutable: placement workers sample it concurrently, so an
## edit never mutates tiles a worker can see. with_tiles() returns a new
## object sharing the unchanged tiles; the owner swaps the reference and then
## rebuilds the affected chunks (copy-on-write).
##
## Stored as raw rasters, never stroke replays: one sidecar per tile,
## `<slug>.edits/zones/<tx>_<tz>.<sha12>.zones` (zstd of R zone, G strength
## bytes), content-addressed so a saved tile is never overwritten.

const TILE_SIZE := 256.0
const PIXEL_SIZE := 2.0
const TILE_PIXELS := 128
const TILE_BYTES := TILE_PIXELS * TILE_PIXELS * 2
## Zones a brush may paint. SHORE follows water and SNOW altitude; the
## settlement, road and habitat zones come from observed data.
const PAINTABLE := [
	EnvironmentZones.Zone.MEADOW, EnvironmentZones.Zone.WOODLAND_CONIFER, EnvironmentZones.Zone.WOODLAND_BROADLEAF,
	EnvironmentZones.Zone.ROCK, EnvironmentZones.Zone.BARE, EnvironmentZones.Zone.WETLAND,
	EnvironmentZones.Zone.FARMLAND, EnvironmentZones.Zone.GARDEN, EnvironmentZones.Zone.SCRUB,
]
## Painted zones that grow nothing: they thin the growth mask.
const BARREN := [EnvironmentZones.Zone.ROCK, EnvironmentZones.Zone.BARE]
## Painted zones where woody growth (trees, shrubs, ferns) may stand.
const WOODY := [EnvironmentZones.Zone.WOODLAND_CONIFER, EnvironmentZones.Zone.WOODLAND_BROADLEAF, EnvironmentZones.Zone.SCRUB]

## The crop's minimum corner; tile (0, 0) starts here.
var origin := Vector2.ZERO
var columns := 0
var rows := 0
## Flat [tz * columns + tx] -> PackedByteArray (TILE_BYTES) or null.
var _tiles: Array = []
## Tile key "tx_tz" -> {zone: true} painted in it, for chunk-level skips.
var _zones_in: Dictionary = {}
var _count := 0


static func create(world_size: float) -> ZoneOverrides:
	var result := ZoneOverrides.new()
	result.origin = Vector2(-world_size * 0.5, -world_size * 0.5)
	result.columns = ceili(world_size / TILE_SIZE)
	result.rows = result.columns
	result._tiles.resize(result.columns * result.rows)
	return result


func is_empty() -> bool:
	return _count == 0


## {zone, strength 0..1} at a world XZ, nearest pixel; Vector2(-1, 0) unpainted.
func sample(x: float, z: float) -> Vector2:
	if _count == 0: return Vector2(-1.0, 0.0)
	var px := floori((x - origin.x) / PIXEL_SIZE)
	var pz := floori((z - origin.y) / PIXEL_SIZE)
	var tx := px / TILE_PIXELS if px >= 0 else -1
	var tz := pz / TILE_PIXELS if pz >= 0 else -1
	if tx < 0 or tz < 0 or tx >= columns or tz >= rows: return Vector2(-1.0, 0.0)
	var tile: Variant = _tiles[tz * columns + tx]
	if tile == null: return Vector2(-1.0, 0.0)
	var index := ((pz - tz * TILE_PIXELS) * TILE_PIXELS + (px - tx * TILE_PIXELS)) * 2
	var strength: int = (tile as PackedByteArray)[index + 1]
	if strength == 0: return Vector2(-1.0, 0.0)
	return Vector2(float((tile as PackedByteArray)[index]), float(strength) / 255.0)


## True when any painted tile overlaps `area` (world XZ).
func intersects(area: Rect2) -> bool:
	return not zones_in(area).is_empty()


## The zones painted in tiles overlapping `area`: {zone: true}.
func zones_in(area: Rect2) -> Dictionary:
	var result := {}
	if _count == 0: return result
	var first := Vector2i(((area.position - origin) / TILE_SIZE).floor())
	var last := Vector2i(((area.end - origin) / TILE_SIZE).floor())
	for tz in range(maxi(first.y, 0), mini(last.y, rows - 1) + 1):
		for tx in range(maxi(first.x, 0), mini(last.x, columns - 1) + 1):
			result.merge(_zones_in.get("%d_%d" % [tx, tz], {}))
	return result


func tile(key: String) -> PackedByteArray:
	var coord := parse_key(key)
	if coord.x < 0 or coord.x >= columns or coord.y < 0 or coord.y >= rows: return PackedByteArray()
	var value: Variant = _tiles[coord.y * columns + coord.x]
	return value if value != null else PackedByteArray()


func keys() -> PackedStringArray:
	var result := PackedStringArray()
	for index in _tiles.size():
		if _tiles[index] != null: result.append("%d_%d" % [index % columns, index / columns])
	return result


func tile_rect(key: String) -> Rect2:
	var coord := parse_key(key)
	return Rect2(origin + Vector2(coord) * TILE_SIZE, Vector2.ONE * TILE_SIZE)


## A new object with `changes` ({key: PackedByteArray, or empty to clear})
## applied; unchanged tiles are shared. This object is not modified.
func with_tiles(changes: Dictionary) -> ZoneOverrides:
	var result := ZoneOverrides.new()
	result.origin = origin
	result.columns = columns
	result.rows = rows
	result._tiles = _tiles.duplicate()
	result._zones_in = _zones_in.duplicate()
	for key in changes:
		var coord := parse_key(key)
		if coord.x < 0 or coord.x >= columns or coord.y < 0 or coord.y >= rows: continue
		var bytes: PackedByteArray = changes[key]
		var painted := _painted_zones(bytes) if bytes.size() == TILE_BYTES else {}
		result._tiles[coord.y * columns + coord.x] = bytes if not painted.is_empty() else null
		if painted.is_empty(): result._zones_in.erase(key)
		else: result._zones_in[key] = painted
	for value in result._tiles:
		if value != null: result._count += 1
	return result


static func parse_key(key: String) -> Vector2i:
	var parts := key.split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func _painted_zones(bytes: PackedByteArray) -> Dictionary:
	var result := {}
	for index in range(0, bytes.size(), 2):
		if bytes[index + 1] > 0: result[int(bytes[index])] = true
	return result


## RG8 image of the painted tiles' bounding box for terrain.gdshader, with
## its world rect: {image, rect}. Empty image when nothing is painted.
func shader_image() -> Dictionary:
	var keys_now := keys()
	if keys_now.is_empty(): return {"image": Image.create(1, 1, false, Image.FORMAT_RG8), "rect": Rect2(origin, Vector2.ONE * PIXEL_SIZE)}
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-1, -1)
	for key in keys_now:
		var coord := parse_key(key)
		low = Vector2i(mini(low.x, coord.x), mini(low.y, coord.y))
		high = Vector2i(maxi(high.x, coord.x), maxi(high.y, coord.y))
	var span := high - low + Vector2i.ONE
	var image := Image.create(span.x * TILE_PIXELS, span.y * TILE_PIXELS, false, Image.FORMAT_RG8)
	for key in keys_now:
		var piece := Image.create_from_data(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_RG8, tile(key))
		image.blit_rect(piece, Rect2i(0, 0, TILE_PIXELS, TILE_PIXELS), (parse_key(key) - low) * TILE_PIXELS)
	return {"image": image, "rect": Rect2(origin + Vector2(low) * TILE_SIZE, Vector2(span) * TILE_SIZE)}


# --- Sidecar files (EditTileFiles) ---------------------------------------------

static func sidecar_directory(edits_path: String) -> String:
	return EditTileFiles.directory_for(edits_path)


static func digest(bytes: PackedByteArray) -> String:
	return EditTileFiles.digest(bytes)


## The relative sidecar path for a tile's bytes.
static func tile_path(key: String, bytes: PackedByteArray) -> String:
	return EditTileFiles.path_for("zones", "zones", key, bytes)


static func valid_tile_path(key: String, path: Variant) -> bool:
	return EditTileFiles.valid_path("zones", "zones", key, path)


static func write_tile(directory: String, path: String, bytes: PackedByteArray) -> String:
	return EditTileFiles.write(directory, path, bytes)


static func read_tile(full: String) -> Dictionary:
	return EditTileFiles.read(full, TILE_BYTES)


## Builds the overrides an edits document's `zones` section describes.
## `pending` ({path: bytes}) supplies tiles not yet saved (Studio).
static func load_section(section: Dictionary, edits_path: String, world_size: float, pending: Dictionary = {}) -> Dictionary:
	var result := create(world_size)
	var read := EditTileFiles.read_all(section.get("tiles", {}), edits_path, TILE_BYTES, pending)
	if not read.ok: return read
	return {"ok": true, "overrides": result.with_tiles(read.tiles) if not read.tiles.is_empty() else result}


static func section_errors(section: Variant, world_size: float = 0.0) -> PackedStringArray:
	var errors := PackedStringArray()
	if not section is Dictionary:
		errors.append("zones must be an object")
		return errors
	if section.is_empty(): return errors
	for key in section:
		if not key in ["tile_size", "pixel_size", "tiles"]: errors.append("zones: unknown field " + str(key))
	if not HeightmapLocationLoader._finite_number(section.get("tile_size")) or float(section.tile_size) != TILE_SIZE:
		errors.append("zones.tile_size must be %d" % TILE_SIZE)
	if not HeightmapLocationLoader._finite_number(section.get("pixel_size")) or float(section.pixel_size) != PIXEL_SIZE:
		errors.append("zones.pixel_size must be %d" % PIXEL_SIZE)
	var tiles: Variant = section.get("tiles")
	if not tiles is Dictionary:
		errors.append("zones.tiles must be an object")
		return errors
	var limit := ceili(world_size / TILE_SIZE) if world_size > 0.0 else 1 << 20
	for key in tiles:
		var coord := parse_key(str(key))
		if coord.x < 0 or coord.y < 0 or coord.x >= limit or coord.y >= limit: errors.append("zones.tiles: invalid tile key %s" % key)
		elif not valid_tile_path(str(key), tiles[key]): errors.append("zones.tiles.%s must be zones/%s.<sha12>.zones" % [key, key])
	return errors
