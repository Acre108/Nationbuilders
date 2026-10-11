class_name HeightmapTerrainProvider
extends TerrainProvider

## A real-world location's ground: heights baked by tools/geo/import_dem.py
## from Copernicus GLO-30, loaded from a flat .r32 file instead of computed
## from noise. See TerrainProvider's class doc -- this is the "imported
## heightmaps for real locations later" it was written to make room for.
##
## Construct with load_from_file(), not .new() directly.
##
## get_height(), growth_mask_for() and tree_mask_factor() are overridden;
## get_normal()/tile()/build_chunk_mesh() keep TerrainProvider's defaults for
## this first pass -- the base class documents overriding them as a
## performance optimisation for a grid-backed provider, not a correctness
## requirement, and H1-H5 were built the same way (correctness first, perf
## overrides only once something is actually slow).
##
## growth_mask_for() multiplies in rock/snow altitude (see `altitude` below)
## when set, on top of the painted mask the base class already gives it;
## get_tree_mask() additionally thins tree-family placement above
## `altitude.treeline`. Deriving a mask from land-cover data is still
## separate work, not done here.

var _heights := PackedFloat32Array()
var _grid_size := Vector2i.ZERO
var _bounds := Rect2()
## New geographic imports use east/+X, south/+Z, up/+Y. Unmarked legacy
## manifests retain their original +Z-north mapping until explicitly migrated.
var north_axis: String = "+Z"
## Real min/max of the loaded grid, metres. Measured once at load time
## (see load_from_file()), not assumed -- used to skip growth_mask_for()'s
## extra height sample when `altitude`'s bands sit above every point this
## heightmap actually reaches, the same "free when out of reach" rule
## LandformTerrainProvider._altitude_active follows for procedural ground.
var _min_height: float = 0.0
var _max_height: float = 0.0

## Optional rock/snow altitude shading. Off by default (null): every
## heightmap location before this kept the plain painted mask, and stays
## that way unless a caller sets this. Reuses TerrainProfile -- the SAME
## resource and SAME altitude_rock()/altitude_snow() formulas a procedural
## LandformTerrainProvider uses, rather than inventing a second altitude
## mechanism just for real terrain. Only
## its Altitude group (rock_line/snow_line/altitude_band/snow_colour/
## rock_scale/rock_facet_strength) means anything here -- its landform
## fields (hills, valleys, ...) are never read, since this class does not
## build a landform from a TerrainProfile the way LandformTerrainProvider
## does. FoliageLocation.build() wires this from FoliageProfile.terrain when
## a location sets one alongside a heightmap (see docs/GEO_IMPORT.md,
## "Asset wishlist").
var altitude: TerrainProfile
## Optional OSM rivers and lakes (heightmap_location_loader.gd). Once
## fitted, their channels, basins and banks are carved into get_height()
## itself, so ground mesh, collision, placement and water all share one
## surface -- the same way LandformTerrainProvider carves its procedural
## rivers. See docs/WATER.md, W4.1 and W4.2.
var imported_rivers: ImportedRivers
## Independent woodland mask: fields and lawns can carry grass without trees.
var imported_site: ImportedSite
## Off: no imported water, carving or foliage exclusion (a WaterProfile with
## river_enabled = false asks for this).
var imported_water_enabled: bool = true
## Optional real coastline (tools/geo/import_sea.py): seabed under the sea
## and real ground past the world's edge, in natural_height() whether or not
## the sea is drawn. See docs/WATER.md, *Real coastlines*.
var imported_sea: ImportedSea
## The location's WaterProfile while its sea is on (FoliageLocation.build()):
## the growth mask then keeps off the seabed, but only within the sea's reach.
var sea_water: WaterProfile

## Sculpted height edits (Location Studio S5), or null: added to the DEM in
## natural_height(), so ground, collision, placement and water fitting all
## see one surface. Immutable; assign through set_height_deltas().
var height_deltas: HeightDeltas:
	set(value):
		height_deltas = value
		var box := value.extent if value != null else Rect2()
		_delta_x0 = box.position.x
		_delta_z0 = box.position.y
		_delta_x1 = box.end.x if value != null else -INF
		_delta_z1 = box.end.y if value != null else -INF
## The sculpted tiles' extent as plain floats, tested inline in
## natural_height(): outside it the hottest path makes no extra call.
var _delta_x0 := INF
var _delta_z0 := INF
var _delta_x1 := -INF
var _delta_z1 := -INF
## Where the rivers sidecar came from ({path, centre, world_size}), so a
## height edit can refit the water from the raw ways (a fit is not
## idempotent: it replaces the ways with fitted chains).
var rivers_source: Dictionary = {}
## The largest delta raise: altitude gates compare against _max_height + it.
var _delta_raise := 0.0

## Metres inside the world's edge over which its DEM hands over to the sea
## sidecar's coarser ground, so the two never meet at a step.
const SEA_EDGE_BLEND := 150.0

const HEADER_BYTES := 8
const BYTES_PER_SAMPLE := 4
## A corrupt header must not be allowed to request an arbitrary allocation.
## 8192x8192 is already a 256 MiB height field and comfortably above the
## 512x512 grids produced by import_dem.py.
const MAX_GRID_DIMENSION := 8192


## `path` is a tools/geo/import_dem.py .r32 file: two little-endian uint32s
## (width, height), then width*height little-endian float32s, row-major.
## Row 0 is the crop's north edge; rows increase southward, columns eastward.
## The manifest's north_axis determines whether north is world -Z (corrected)
## or +Z (legacy). The raster bytes are identical for both conventions.
static func load_from_file(path: String, world_size: float) -> HeightmapTerrainProvider:
	if not is_finite(world_size) or world_size <= 0.0:
		push_error("HeightmapTerrainProvider: world_size must be a positive finite number (got %s)" % world_size)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HeightmapTerrainProvider: cannot open %s (error %s)" % [path, FileAccess.get_open_error()])
		return null

	var file_size := file.get_length()
	if file_size < HEADER_BYTES:
		push_error("HeightmapTerrainProvider: %s is truncated (%d bytes; expected at least an 8-byte header)" % [path, file_size])
		file.close()
		return null

	var width := file.get_32()
	var height := file.get_32()
	if width <= 0 or height <= 0 or width > MAX_GRID_DIMENSION or height > MAX_GRID_DIMENSION:
		push_error(
			"HeightmapTerrainProvider: %s has invalid dimensions %dx%d (each must be 1..%d)"
			% [path, width, height, MAX_GRID_DIMENSION]
		)
		file.close()
		return null

	var sample_count: int = width * height
	var sample_bytes: int = sample_count * BYTES_PER_SAMPLE
	var expected_bytes: int = HEADER_BYTES + sample_bytes
	if file_size != expected_bytes:
		push_error(
			"HeightmapTerrainProvider: %s is %d bytes, expected exactly %d for a %dx%d float32 grid"
			% [path, file_size, expected_bytes, width, height]
		)
		file.close()
		return null

	var bytes := file.get_buffer(sample_bytes)
	file.close()
	if bytes.size() != sample_bytes:
		push_error("HeightmapTerrainProvider: short read from %s (%d of %d data bytes)" % [path, bytes.size(), sample_bytes])
		return null

	var heights := bytes.to_float32_array()
	if heights.size() != sample_count:
		push_error("HeightmapTerrainProvider: could not decode %s as %d float32 samples" % [path, sample_count])
		return null
	for value in heights:
		if not is_finite(value):
			push_error("HeightmapTerrainProvider: %s contains a non-finite height sample" % path)
			return null

	var provider := HeightmapTerrainProvider.new()
	provider._heights = heights
	provider._grid_size = Vector2i(width, height)
	var half := world_size * 0.5
	provider._bounds = Rect2(Vector2(-half, -half), Vector2(world_size, world_size))

	var lo := provider._heights[0]
	var hi := provider._heights[0]
	for h in provider._heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	provider._min_height = lo
	provider._max_height = hi
	return provider


## Bilinear over the loaded grid -- same half-pixel-centred interpolation
## TerrainProvider.sample_painted_mask() already uses, just over heights
## instead of a mask value. Unlike that mask (which returns a 1.0 sentinel
## outside its bounds), u/v are clamped into [0,1] before sampling: past the
## loaded edge the ground repeats its boundary height rather than falling to
## a false 0 or showing a seam, matching TerrainProfile.world_size's own
## promise that "the ground itself carries on so the view never ends in
## void".
func get_height(x: float, z: float) -> float:
	var natural := natural_height(x, z)
	if not has_water_marks():
		return natural
	return _shaped(x, z, natural).x


## Riverbed / damp-bank marks for the terrain shader (TerrainProvider's hook).
func has_water_marks() -> bool:
	return imported_rivers != null and imported_water_enabled and imported_rivers.is_fitted()


func water_marks(x: float, z: float) -> Vector2:
	if not has_water_marks():
		return Vector2.ZERO
	var lake := imported_rivers.lakes.marks_at(x, z)
	var river := imported_rivers.marks_at(x, z)
	return Vector2(maxf(lake.x, river.x), maxf(lake.y, river.y))


## Fitted rivers and lakes as one water field (TerrainProvider's hook).
func has_water_field(area: Rect2) -> bool:
	return has_water_marks() and imported_rivers.has_water_in(area)


func water_sample(x: float, z: float, margin: float, min_width := 0.0) -> PackedFloat32Array:
	if not has_water_marks():
		return PackedFloat32Array()
	return imported_rivers.water_at(x, z, margin, min_width)


## Lake basins first, then river channels into that ground. Under a lake's
## water a river may only deepen it: its banks must not raise a spit out
## into the lake at its mouth. x = height, y = bed, z = damp bank.
func _shaped(x: float, z: float, natural: float) -> Vector3:
	var lake := imported_rivers.lakes.shape_at(x, z, natural)
	var river := imported_rivers.shape_at(x, z, lake.x)
	var height := minf(river.x, lake.x) if lake.w < 0.0 else river.x
	return Vector3(height, maxf(lake.y, river.y), maxf(lake.z, river.z))


## The DEM alone, before imported river channels are carved into it. What
## ImportedRivers.fit_to_terrain() fits its water levels against. With a sea
## sidecar, past the world's edge this is the sidecar's own ground rather than
## the clamped boundary, and under the sea it drops to the inferred seabed.
##
## Sculpted deltas (S5) are added here, on top of the DEM and sea ground.
func natural_height(x: float, z: float) -> float:
	# The DEM directly when there is no sea: the hottest worker path keeps
	# its one call.
	var h := _dem_height(x, z) if imported_sea == null else base_height(x, z)
	if x >= _delta_x0 and x <= _delta_x1 and z >= _delta_z0 and z <= _delta_z1: h += height_deltas.sample(x, z)
	return h


## natural_height() without sculpted deltas: the imported ground.
func base_height(x: float, z: float) -> float:
	if imported_sea == null:
		return _dem_height(x, z)
	var inside := _bounds.size.x * 0.5 - maxf(absf(x), absf(z))
	var h := imported_sea.ground(x, z)
	if inside > 0.0:
		h = lerpf(h, _dem_height(x, z), clampf(inside / SEA_EDGE_BLEND, 0.0, 1.0))
	# The near grid (SEA6), where it has the say: its bed replaces the
	# ground by its weight, in place of the 50 m seabed.
	var near := imported_sea.near_shape(x, z)
	var cover := imported_sea.near_cover(x, z)
	if cover >= 1.0:
		return lerpf(h, near.x, near.y)
	var coarse := h + imported_sea.seabed(x, z)
	if cover <= 0.0:
		return coarse
	return lerpf(coarse, lerpf(h, near.x, near.y / cover), cover)


## Swaps in sculpted deltas (copy-on-write; null or empty removes them). When
## `area` comes within 100 m of rivers or lakes, or `area` is empty (a load),
## the water is refitted from its raw ways onto the new ground. Returns true
## when the water was refitted.
func set_height_deltas(deltas: HeightDeltas, area: Rect2 = Rect2()) -> bool:
	height_deltas = deltas if deltas != null and not deltas.is_empty() else null
	_delta_raise = height_deltas.max_delta if height_deltas != null else 0.0
	if imported_rivers == null or rivers_source.is_empty(): return false
	if area.has_area() and not imported_rivers.has_water_in(area.grow(100.0)): return false
	var fresh := ImportedRivers.load_file(rivers_source.path, rivers_source.centre, rivers_source.world_size, north_axis)
	if fresh == null: return false
	fresh.fit_to_terrain(natural_height)
	imported_rivers = fresh
	_mark_estuaries()
	return true


## How far up rivers the tide is felt (WaterProfile.estuary_reach; SEA8).
## Set by FoliageLocation before the ground builds; refits keep it.
var estuary_reach: float = 0.0


func set_estuary_reach(reach: float) -> void:
	estuary_reach = reach
	_mark_estuaries()


func _mark_estuaries() -> void:
	if imported_rivers == null or not imported_rivers.is_fitted():
		return
	var hat := 0.5
	if imported_sea != null and imported_sea.tide != null:
		hat = float(imported_sea.tide.levels.get("hat", 0.5))
	imported_rivers.mark_tidal(imported_sea, (imported_sea.level if imported_sea != null else 0.0) + hat,
		estuary_reach if imported_sea != null else 0.0)


func _dem_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0

	var u := (x - _bounds.position.x) / _bounds.size.x
	var v := (_bounds.position.y + _bounds.size.y - z) / _bounds.size.y
	if north_axis == "-Z": v = (z - _bounds.position.y) / _bounds.size.y
	u = clampf(u, 0.0, 1.0)
	v = clampf(v, 0.0, 1.0)

	var w := _grid_size.x
	var h := _grid_size.y
	var fx := clampf(u * float(w) - 0.5, 0.0, float(w - 1))
	var fy := clampf(v * float(h) - 0.5, 0.0, float(h - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)

	var top := lerpf(_heights[y0 * w + x0], _heights[y0 * w + x1], tx)
	var bottom := lerpf(_heights[y1 * w + x0], _heights[y1 * w + x1], tx)
	return lerpf(top, bottom, ty)


func grid_size() -> Vector2i:
	return _grid_size


## Real min/max height over the whole loaded grid, metres.
func height_range() -> Vector2:
	return Vector2(_min_height, _max_height)


func growth_mask_for(x: float, z: float, normal: Vector3) -> float:
	var mask := super.growth_mask_for(x, z, normal)
	# Painted rock and bare ground grow nothing.
	if zone_overrides != null and mask > 0.0:
		var painted := zone_overrides.sample(x, z)
		if painted.y > 0.0 and int(painted.x) in ZoneOverrides.BARREN: mask *= 1.0 - painted.y
	if imported_rivers != null and imported_water_enabled:
		mask *= imported_rivers.growth_mask(x, z)
		if imported_rivers.is_fitted():
			mask *= imported_rivers.lakes.growth_mask(x, z)
	if mask > 0.0 and imported_sea != null and sea_water != null:
		mask *= 1.0 - imported_sea.submerged(x, z, get_height(x, z), sea_water)
	if mask <= 0.0 or altitude == null:
		return mask
	# Free when out of reach: this heightmap's real, measured max height,
	# not a guess -- so a heightmap location that never sets `altitude` (or
	# sets bands above its own peak) pays nothing beyond the one comparison
	# below, the same guarantee LandformTerrainProvider._altitude_active
	# makes for procedural ground.
	if minf(altitude.rock_line, altitude.snow_line) - altitude.altitude_band > _max_height + _delta_raise:
		return mask
	var h := get_height(x, z)
	# Same formulas the terrain shader paints with (see
	# TerrainProfile.apply_to_terrain_material and terrain.gdshader's
	# terrain_rock_line/terrain_snow_line), so grass and cushion plants stop
	# exactly where the ground here turns to rock or snow -- mirroring
	# LandformTerrainProvider.growth_mask_for's identical altitude gate.
	return mask * (1.0 - altitude.altitude_rock(h)) * (1.0 - altitude.altitude_snow(h, normal.y))


func north_z() -> float:
	return -1.0 if north_axis == "-Z" else 1.0


func altitude_cover(x: float, z: float, normal: Vector3) -> Vector2:
	if altitude == null or minf(altitude.rock_line, altitude.snow_line) - altitude.altitude_band > _max_height + _delta_raise:
		return Vector2.ZERO
	var h := get_height(x, z)
	return Vector2(altitude.altitude_rock(h), altitude.altitude_snow(h, normal.y))


## See TerrainProvider.get_tree_mask()'s class doc: the ordinary growth mask
## (including any rock/snow thinning above), further thinned above
## `altitude.treeline`. Grass/shrubs/cushion plants call get_growth_mask()
## instead and never see this reduction -- mirrors
## LandformTerrainProvider.tree_mask_factor() exactly, same reasoning, same
## shared TerrainProfile.altitude_treeline() formula.
func tree_mask_factor(x: float, z: float) -> float:
	var factor := imported_site.tree_mask(x, z) if imported_site != null else 1.0
	if zone_overrides != null: factor = _painted_woody(x, z, factor)
	if factor <= 0.0 or altitude == null:
		return factor
	if altitude.treeline - altitude.altitude_band > _max_height + _delta_raise:
		return factor
	return factor * (1.0 - altitude.altitude_treeline(get_height(x, z)))


func has_observed_zones() -> bool:
	return imported_site != null and imported_site.has_zones()


func observed_coverage(x: float, z: float) -> float:
	return imported_site.coverage(x, z) if imported_site != null else 1.0


func observed_zones(x: float, z: float) -> Color:
	return imported_site.zone_cover(x, z) if imported_site != null else Color(0, 0, 0, 0)


func observed_settlement(x: float, z: float) -> Color:
	return imported_site.settlement_cover(x, z) if imported_site != null else Color(0, 0, 0, 0)


func has_observed_habitats() -> bool:
	return imported_site != null and imported_site.has_habitats()


func observed_habitat(x: float, z: float) -> Color:
	return imported_site.habitat_cover(x, z) if imported_site != null else Color(0, 0, 0, 0)


## Mapped zone classes and open water win over the farmland channel, which
## comes partly from WorldCover's coarser cropland class and is painted in
## source order (a field polygon drawn after a pond covers the pond).
func farmland_cover(x: float, z: float) -> float:
	if imported_site == null or not imported_site.has_zones():
		return 0.0
	var mapped := imported_site.zone_cover(x, z)
	var fields := imported_site.farmland(x, z) * (1.0 - maxf(maxf(mapped.r, mapped.g), maxf(mapped.b, mapped.a)))
	return fields * (1.0 - water_cover(x, z)) if fields > 0.0 else 0.0


## The site's woody-growth mask, with painted zones on top: painted woodland
## and scrub allow trees, shrubs and ferns; every other painted zone clears
## them (Location Studio S4).
func site_tree_mask(x: float, z: float) -> float:
	var mask := imported_site.tree_mask(x, z) if imported_site != null else 1.0
	return _painted_woody(x, z, mask) if zone_overrides != null else mask


func _painted_woody(x: float, z: float, mask: float) -> float:
	var painted := zone_overrides.sample(x, z)
	return lerpf(mask, 1.0 if int(painted.x) in ZoneOverrides.WOODY else 0.0, painted.y) if painted.y > 0.0 else mask



## Side of the square terrain crop, metres.
func world_size() -> float:
	return _bounds.size.x




## The river, lake and sea factors growth_mask_for() multiplies in.
func water_cover(x: float, z: float) -> float:
	var dry := 1.0
	if imported_rivers != null and imported_water_enabled:
		dry = imported_rivers.growth_mask(x, z)
		if imported_rivers.is_fitted():
			dry *= imported_rivers.lakes.growth_mask(x, z)
	if imported_sea != null and sea_water != null:
		dry *= 1.0 - imported_sea.submerged(x, z, get_height(x, z), sea_water)
	return 1.0 - dry
