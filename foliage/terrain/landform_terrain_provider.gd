class_name LandformTerrainProvider
extends NoiseTerrainProvider

## Ground built from a TerrainProfile: the rolling ground of NoiseTerrainProvider
## (inherited unchanged, so a profile with every other layer off is
## bit-identical to it), plus hills, valleys and a raised world edge.
##
##   height = rolling + hills * (1 - valley) - valley_depth * valley + edge
##
## Hills come from warped fractal simplex noise. Everything below a threshold
## stays flat low ground, and above it the noise is eased into a rounded hill,
## so hills stand out of level floors instead of the whole world undulating. A
## broad region field scales them, so the world has hill country and open
## plains. Valleys are the zero-crossings of a second, meandering noise field:
## near a crossing the ground is pulled down to a flat floor, cutting through
## any hill in the way.
##
## The thresholds are MEASURED from the noise when the provider is configured,
## by sampling it across the world, not assumed from its nominal range. So
## `hill_cover = 0.3` really raises 30% of hill country, whatever the octave
## count or warp does to the noise's distribution.
##
## Every noise call is native FastNoiseLite and read-only after _configure(),
## so sampling is safe on WorkerThreadPool. Chunk work reads the ground
## through TerrainTile, so these extra layers are paid once per grid point,
## not once per tuft.

## Grid of samples per side used to measure the noise's distribution.
const MEASURE_GRID := 64
## Step for the valley field's local gradient, metres.
const VALLEY_EPSILON := 1.0
## Grid of samples per side for the water bake (sea + lakes; see
## _build_water_depth()), across the whole world regardless of world_size --
## same fixed-resolution simplification MEASURE_GRID already makes. On
## rolling_hills' 8 km world that is ~62 m a cell: coarse, enough for a basin
## the size of a pond or small lake, not for the shore's exact shape (the
## shore-band blend in growth_mask_for() and terrain.gdshader softens the
## resulting blockiness, and the terrain's own much finer mesh -- not this
## grid -- is still what actually shapes the shoreline you see; see
## docs/WATER.md, *Terrain-aware water*).
const WATER_GRID := 128
## RiverTracer parameters (see _trace_rivers()). Coarser than WATER_GRID on
## purpose: seeding only has to land within convergence range of a contour
## (recurring roughly every 0.6 valley_spacing wavelengths), not resolve the
## river's own width -- the walk that follows from each seed is what actually
## traces the shape, at RIVER_STEP resolution, however fine that needs to be.
const RIVER_SEED_GRID := 48
## Distance walked per trace step, world units -- also the ribbon mesh's
## along-the-river vertex spacing (WaterLayer).
const RIVER_STEP := 24.0
## Generous upper bound per walk direction so a valley spanning the world
## diagonally, or one that loops, is never cut short; RiverTracer's own loop
## and bounds checks are what actually end a walk in practice.
const RIVER_MAX_STEPS := 600
## A seed within this of an already-traced point is on that same contour.
const RIVER_DEDUP_RADIUS := 16.0
## Softening band at a river's bank, metres -- a hard cutoff at exactly
## river_width would show as a knife edge; the same reasoning as
## WaterProfile.shore_band, just not authored per-location since a river's
## width is already a location knob.
const RIVER_BANK_SOFTNESS := 1.0

var profile: TerrainProfile
## Where the sea sits, if anywhere (W2 of the water system). Also drives
## lakes (W3): if `water.lakes_enabled`, _configure() floods the height field
## once (see _build_water_depth()) and keeps whatever survives LakeBasins'
## filtering. Null = no water at all: growth_mask_for() adds nothing beyond
## what NoiseTerrainProvider already does.
var water: WaterProfile
## Retained lake basins after _build_water_depth(), each {"bounds": Rect2
## (world XZ), "level": float, "area": float}. Empty when lakes are off, or
## none survive WaterProfile's lake_min_area / lake_max_depth filters.
var _lake_basins: Array[Dictionary] = []
## Bilinear-sampled by lake_depth_at(): 0 outside any retained basin, the
## depth of standing water above the raw ground inside one. Kept separate
## from the sea's water_mask(h), which is a pure function of height and
## needs no baked data -- a lake's level is NOT a function of height alone,
## it depends on which basin (if any) a point falls in. Lake-only (unlike
## _water_depth below) because it is used to gate growth, which already has
## its own O(1) height-based path for the sea.
var _lake_depth := PackedFloat32Array()
## Combined sea + lake depth on the same WATER_GRID lattice: whichever is
## deeper at each cell. This is what water_depth_grid() hands to
## WaterDepthMap for the water shader -- the water surface itself does not
## care which body it belongs to, only how deep it is here (see
## docs/WATER.md, *Terrain-aware water*).
var _water_depth := PackedFloat32Array()
## Height of the bed the sea stands on, same lattice: the raw ground where
## the sea is on, DRY_BED (never under any sea) where it is off. WaterDepthMap
## hands it to the water shader, which takes the sea's depth against the
## live level (SeaState) -- docs/SEA_PLAN.md, SEA1.
var _water_bed := PackedFloat32Array()
const DRY_BED := 100000.0
## Traced valley centrelines kept as rivers (W4), each a world-XZ polyline --
## see _trace_rivers(). Empty when rivers are off, or `valley_depth <= 0`
## (there is no valley network for a river to ride at all).
var _river_paths: Array[PackedVector2Array] = []
## A floor for the gradient river_strength() divides by, measured from the
## noise (see _measure_river_gradient_floor()) rather than assumed. Warped
## noise has rare, real patches where its own gradient is locally almost
## zero near a zero-crossing -- not a bug, just a flat stretch of an
## otherwise wiggly field -- and valley_strength()'s 30 m+ threshold never
## notices the resulting distance estimate blow up there, but a river's
## few-metre threshold does: a point sampled exactly ON a traced river can
## otherwise come back reading as if it were metres away from its own
## centreline.
var _river_gradient_floor: float = 0.000001

var _hills := FastNoiseLite.new()
var _region := FastNoiseLite.new()
var _valleys := FastNoiseLite.new()

## Measured in _configure(); see the class comment.
var _hill_floor: float = 0.0
var _hill_top: float = 1.0
var _region_low: float = 0.0
var _region_high: float = 0.0
var _half_world: float = 4000.0
## False when the altitude bands start above the highest ground this profile
## can make, so the grass mask skips the extra height sample (the common case
## until mountains exist).
var _altitude_active := false
## Same "free when out of reach" guard as _altitude_active, for
## TerrainProfile.treeline -- get_tree_mask()'s own extra height sample.
var _treeline_active := false


## The parent's constructor has already run with its default seed by the time
## this body runs, and configured nothing of ours. Setting `seed` reconfigures
## everything with the profile in place.
func _init(terrain_profile: TerrainProfile = null, initial_seed: int = 1337, water_profile: WaterProfile = null) -> void:
	profile = terrain_profile if terrain_profile != null else TerrainProfile.new()
	water = water_profile
	seed = initial_seed


func _configure() -> void:
	if profile == null:
		return
	landform_amplitude = profile.landform_amplitude
	landform_scale = profile.landform_scale
	detail_amplitude = profile.detail_amplitude
	detail_scale = profile.detail_scale
	super._configure()
	_half_world = profile.world_size * 0.5
	var highest := profile.landform_amplitude + profile.detail_amplitude + profile.hill_height + profile.edge_rise
	_altitude_active = minf(profile.rock_line, profile.snow_line) - profile.altitude_band < highest
	_treeline_active = profile.treeline - profile.altitude_band < highest

	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.seed = seed + 101
	_hills.frequency = 1.0 / profile.hill_scale
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = profile.hill_octaves
	# Below the usual 0.5: extra octaves add knobbly shape without each one
	# steepening the flanks as much.
	_hills.fractal_gain = 0.4
	_hills.domain_warp_enabled = profile.hill_warp > 0.0
	_hills.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_hills.domain_warp_amplitude = profile.hill_warp
	_hills.domain_warp_frequency = 0.5 / profile.hill_scale
	_hills.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE

	_region.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_region.seed = seed + 202
	_region.frequency = 1.0 / profile.region_scale
	_region.fractal_type = FastNoiseLite.FRACTAL_FBM
	_region.fractal_octaves = 2

	_valleys.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_valleys.seed = seed + 303
	# Zero-crossings of simplex noise fall about 0.6 wavelengths apart.
	_valleys.frequency = 0.6 / profile.valley_spacing
	_valleys.fractal_type = FastNoiseLite.FRACTAL_FBM
	_valleys.fractal_octaves = 2
	_valleys.domain_warp_enabled = profile.valley_meander > 0.0
	_valleys.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_valleys.domain_warp_amplitude = profile.valley_meander
	_valleys.domain_warp_frequency = 0.5 / profile.valley_spacing
	_valleys.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE

	if profile.hill_height > 0.0:
		var hills := _measure(_hills)
		_hill_floor = _quantile(hills, 1.0 - profile.hill_cover)
		_hill_top = maxf(_quantile(hills, 0.995), _hill_floor + 0.001)
		# The region edge is a band 20% of the land wide, so hill country
		# fades into plain over a few hundred metres, not along a line.
		var region := _measure(_region)
		var split := 1.0 - profile.hill_country
		_region_low = _quantile(region, split - 0.1)
		_region_high = maxf(_quantile(region, split + 0.1), _region_low + 0.001)

	_lake_basins = []
	_lake_depth = PackedFloat32Array()
	_water_depth = PackedFloat32Array()
	_water_bed = PackedFloat32Array()
	_river_paths = []
	if water != null and (water.sea_enabled or water.lakes_enabled):
		# Must run last: hill_strength()/valley_strength() need _hill_floor
		# etc. above already set, and get_height() (called per grid point
		# below) goes through both.
		_build_water_depth()
	_river_gradient_floor = 0.000001
	if water != null and water.river_enabled and profile.valley_depth > 0.0:
		# A river with no valley to sit in is not meaningful -- see
		# WaterProfile.river_enabled's own comment.
		_measure_river_gradient_floor()
		_trace_rivers()


func get_height(x: float, z: float) -> float:
	var h := super.get_height(x, z)
	if profile == null:
		return h
	var hills := 0.0
	if profile.hill_height > 0.0:
		hills = profile.hill_height * hill_strength(x, z)
	if profile.valley_depth > 0.0:
		var v := valley_strength(x, z, hills)
		h += hills * (1.0 - v) - profile.valley_depth * v
		if water != null and water.river_enabled:
			# A shallow channel cut into the already-flat valley floor -- a
			# second, narrower and much shallower valley_depth, not a second
			# landform. Scaled by the SAME v: a river only carves where the
			# valley floor it rides already reached full strength, so the
			# channel never pokes out through a valley's own sloped walls.
			h -= water.river_carve_depth * river_strength(x, z) * v
	else:
		h += hills
	if profile.edge_rise > 0.0:
		var inside := _half_world - maxf(absf(x), absf(z))
		h += profile.edge_rise * (1.0 - smoothstep(0.0, profile.edge_width, inside))
	return h


## 0..1: how much of a full hill stands here, region scaling included.
func hill_strength(x: float, z: float) -> float:
	var region := smoothstep(_region_low, _region_high, _region.get_noise_2d(x, z))
	if region <= 0.0:
		return 0.0
	var u := clampf((_hills.get_noise_2d(x, z) - _hill_floor) / (_hill_top - _hill_floor), 0.0, 1.0)
	# Eased at both ends: the toe meets the low ground level, and summits
	# round over rather than peak.
	return u * u * (3.0 - 2.0 * u) * region


## Distance to the nearest valley's centreline (the meander field's own
## zero-crossing), metres. Shared by valley_strength() (the whole floor) and
## river_strength() (a much narrower ribbon down its middle) -- and, via
## _valley_field(), by RiverTracer, which walks this same field's contour
## directly rather than sampling distance from it.
##
## |value| / |gradient|, with the gradient taken HERE rather than a
## world-wide average: an average was tried and made valleys vary 2-3x in
## width, because the warped noise is much steeper in some places than
## others.
func _valley_distance(x: float, z: float) -> float:
	var n := _valleys.get_noise_2d(x, z)
	var gx := _valleys.get_noise_2d(x + VALLEY_EPSILON, z) - n
	var gz := _valleys.get_noise_2d(x, z + VALLEY_EPSILON) - n
	var gradient := maxf(Vector2(gx, gz).length() / VALLEY_EPSILON, 0.000001)
	return absf(n) / gradient


## RiverTracer's field Callable: the raw meander value (not the distance --
## a contour tracer needs the signed field to find its zero-crossing and
## gradient, the same value _valley_distance() already divides by).
func _valley_field(p: Vector2) -> float:
	return _valleys.get_noise_2d(p.x, p.y)


## 0..1: 1 on a valley floor, 0 beyond its walls. `cut` is the height of hill
## the valley has to remove here; the walls widen by enough run to keep that
## drop near valley_wall_slope. (1.5x: a smoothstep wall is 1.5 times steeper
## at its middle than its average.)
func valley_strength(x: float, z: float, cut: float = 0.0) -> float:
	var distance := _valley_distance(x, z)
	var floor_half := profile.valley_width * 0.5 * profile.valley_floor
	var run := profile.valley_width * 0.5 * (1.0 - profile.valley_floor)
	run = maxf(run, 1.5 * (cut + profile.valley_depth) / tan(deg_to_rad(profile.valley_wall_slope)))
	return 1.0 - smoothstep(floor_half, floor_half + run, distance)


## 0..1: 1 on a river's own centreline, 0 beyond river_width/2 -- a much
## narrower ribbon down the middle of a valley than valley_strength()'s whole
## floor. 0 outright when rivers are off, or there is no valley network for
## one to ride (valley_depth <= 0 -- see WaterProfile.river_enabled), so
## callers do not need to repeat either guard.
func river_strength(x: float, z: float) -> float:
	if water == null or not water.river_enabled or profile == null or profile.valley_depth <= 0.0:
		return 0.0
	var n := _valleys.get_noise_2d(x, z)
	var gx := _valleys.get_noise_2d(x + VALLEY_EPSILON, z) - n
	var gz := _valleys.get_noise_2d(x, z + VALLEY_EPSILON) - n
	# _river_gradient_floor here, not _valley_distance()'s own tiny constant
	# floor -- see that var's comment for why the difference only matters at
	# a river's narrow scale.
	var gradient := maxf(Vector2(gx, gz).length() / VALLEY_EPSILON, _river_gradient_floor)
	var distance := absf(n) / gradient
	return 1.0 - smoothstep(water.river_width * 0.5, water.river_width * 0.5 + RIVER_BANK_SOFTNESS, distance)


## Measures a robust floor for river_strength()'s gradient from the noise
## itself -- see _river_gradient_floor's own comment for why a tiny fixed
## constant is not safe at a river's narrow scale. A LOW PERCENTILE, not the
## minimum: the minimum of a sampled grid could itself be a once-in-a-grid
## fluke, and this needs to sit meaningfully below TYPICAL gradients (so an
## ordinary near-river point still gets an accurate distance) while still
## being high enough to catch the rare near-zero outliers.
func _measure_river_gradient_floor() -> void:
	var magnitudes := PackedFloat32Array()
	magnitudes.resize(MEASURE_GRID * MEASURE_GRID)
	var step := profile.world_size / float(MEASURE_GRID)
	for j in MEASURE_GRID:
		for i in MEASURE_GRID:
			var x := -_half_world + (float(i) + 0.5) * step
			var z := -_half_world + (float(j) + 0.5) * step
			var n := _valleys.get_noise_2d(x, z)
			var gx := _valleys.get_noise_2d(x + VALLEY_EPSILON, z) - n
			var gz := _valleys.get_noise_2d(x, z + VALLEY_EPSILON) - n
			magnitudes[j * MEASURE_GRID + i] = Vector2(gx, gz).length() / VALLEY_EPSILON
	magnitudes.sort()
	_river_gradient_floor = maxf(_quantile(magnitudes, 0.1), 0.000001)


func growth_mask_for(x: float, z: float, normal: Vector3) -> float:
	# Nothing grows outside the world. The ground carries on out there so the
	# view never ends in void, but it is scenery, not land.
	if profile != null and maxf(absf(x), absf(z)) > _half_world:
		return 0.0
	var mask := super.growth_mask_for(x, z, normal)
	if mask <= 0.0:
		return 0.0
	# Free when out of reach: only pay for a height sample if something here
	# actually needs one. Lakes do not: _lake_depth already bakes in ground
	# height, so lake_depth_at() needs only x, z.
	var altitude_relevant := profile != null and _altitude_active
	var sea_relevant := water != null and water.sea_enabled
	if altitude_relevant or sea_relevant:
		var h := get_height(x, z)
		if altitude_relevant:
			# Nothing grows on high rock or under snow. Same formulas the
			# terrain shader paints with, so grass stops exactly where the
			# ground turns.
			mask *= (1.0 - profile.altitude_rock(h)) * (1.0 - profile.altitude_snow(h, normal.y))
		if sea_relevant:
			# Nothing grows underwater either. Same formula terrain.gdshader
			# uses for the shoreline (WaterProfile.water_mask()).
			mask *= (1.0 - water.water_mask(h))
	if not _lake_depth.is_empty():
		var lake_d := lake_depth_at(x, z)
		if lake_d > 0.0:
			# Same band width as the sea's shore, banded on depth instead of
			# height -- a lake's bed is not flat, so "how far below sea_level"
			# does not apply, but "how deep is the water right here" does.
			mask *= (1.0 - smoothstep(0.0, water.shore_band, lake_d))
	if water != null and water.river_enabled:
		# Nothing grows in the channel either. river_strength() already
		# guards river_enabled/valley_depth and is banded by
		# RIVER_BANK_SOFTNESS, so this is a direct multiply, not another
		# smoothstep on top of one.
		mask *= (1.0 - river_strength(x, z))
	return mask


## The sea, lake and river factors growth_mask_for() multiplies in.
func water_cover(x: float, z: float) -> float:
	var dry := 1.0
	if water != null and water.sea_enabled:
		dry *= 1.0 - water.water_mask(get_height(x, z))
	if not _lake_depth.is_empty():
		var lake_d := lake_depth_at(x, z)
		if lake_d > 0.0:
			dry *= 1.0 - smoothstep(0.0, water.shore_band, lake_d)
	if water != null and water.river_enabled:
		dry *= 1.0 - river_strength(x, z)
	return 1.0 - dry


func altitude_cover(x: float, z: float, normal: Vector3) -> Vector2:
	if profile == null or not _altitude_active:
		return Vector2.ZERO
	var h := get_height(x, z)
	return Vector2(profile.altitude_rock(h), profile.altitude_snow(h, normal.y))


## See TerrainProvider.get_tree_mask()'s class doc: the ordinary growth mask,
## further thinned above TerrainProfile.treeline. Grass/shrubs/cushion plants
## call get_growth_mask() instead and never see this reduction.
func tree_mask_factor(x: float, z: float) -> float:
	if profile == null or not _treeline_active:
		return 1.0
	return 1.0 - profile.altitude_treeline(get_height(x, z))


## Basins found by _build_water_depth() and kept by WaterProfile's filters.
## Empty when lakes are off, or none survive.
func lake_basins() -> Array[Dictionary]:
	return _lake_basins


## Traced river centrelines (_trace_rivers()), each a world-XZ polyline.
## Empty when rivers are off, or there is no valley network to ride.
func river_paths() -> Array[PackedVector2Array]:
	return _river_paths


## Traces the valley meander field's zero-contours (RiverTracer) and keeps
## the ones at least WaterProfile.river_min_length long -- warped, meandering
## noise fragments into as many short, disconnected pieces as it forms long
## recognisable valleys, and a short piece reads as noise, not a river worth
## the name (the same reasoning LakeBasins.lake_min_area filters basins by).
func _trace_rivers() -> void:
	var traced := RiverTracer.trace(
		Callable(self, "_valley_field"), profile.bounds(),
		RIVER_SEED_GRID, RIVER_STEP, RIVER_MAX_STEPS, RIVER_DEDUP_RADIUS)
	_river_paths = []
	for path: PackedVector2Array in traced:
		var length := 0.0
		for i in path.size() - 1:
			length += path[i].distance_to(path[i + 1])
		if length >= water.river_min_length:
			_river_paths.append(path)


## 0 outside any retained basin; otherwise how deep the standing water sits
## above the raw ground here, bilinearly interpolated from the WATER_GRID
## bake -- the same interpolation style as sample_painted_mask(), over a grid
## that spans the whole world instead of an arbitrary painted rectangle.
func lake_depth_at(x: float, z: float) -> float:
	return _sample_grid(_lake_depth, x, z)


## Combined sea + lake depth grid, WATER_GRID x WATER_GRID, row-major (x
## fastest) -- see _water_depth's own comment. For WaterDepthMap to bake into
## a texture the water shader can sample; not meant to be queried a point at
## a time (lake_depth_at() and WaterProfile.water_mask() already cover that
## for the growth mask).
func water_depth_grid() -> PackedFloat32Array:
	return _water_depth


## Lake depth on the WATER_GRID lattice (lake_depth_at()'s data); all 0 when
## lakes are off. For WaterDepthMap.
func lake_depth_grid() -> PackedFloat32Array:
	return _lake_depth


## See _water_bed. For WaterDepthMap.
func water_bed_grid() -> PackedFloat32Array:
	return _water_bed


## Bilinear sample of a WATER_GRID-shaped array, world XZ in.
func _sample_grid(grid: PackedFloat32Array, x: float, z: float) -> float:
	if grid.is_empty():
		return 0.0
	var n := WATER_GRID
	var step := profile.world_size / float(n)
	var fx := clampf((x + _half_world) / step - 0.5, 0.0, float(n - 1))
	var fz := clampf((z + _half_world) / step - 0.5, 0.0, float(n - 1))
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, n - 1)
	var z1 := mini(z0 + 1, n - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var top := lerpf(grid[z0 * n + x0], grid[z0 * n + x1], tx)
	var bottom := lerpf(grid[z1 * n + x0], grid[z1 * n + x1], tx)
	return lerpf(top, bottom, tz)


## Floods the height field once (LakeBasins.fill_depressions) if lakes are
## on, keeps the basins WaterProfile's filters accept, and records: the
## per-cell lake depth (lake_depth_at(), the growth-mask query), each kept
## basin's world bounds and level (for WaterLayer to build a lake surface
## from -- see FoliageLocation._build_water()), and the combined sea + lake
## depth (water_depth_grid(), for WaterDepthMap -- see docs/WATER.md,
## *Terrain-aware water*). Sea depth needs no flood-fill: it is `sea_level -
## height`, the same formula WaterProfile.water_mask() already uses, just
## evaluated across the grid instead of at one point.
func _build_water_depth() -> void:
	var n := WATER_GRID
	var step := profile.world_size / float(n)
	var origin := -_half_world
	var raw := PackedFloat32Array()
	raw.resize(n * n)
	for j in n:
		for i in n:
			raw[j * n + i] = get_height(origin + (float(i) + 0.5) * step, origin + (float(j) + 0.5) * step)

	var lake_depth := PackedFloat32Array()
	lake_depth.resize(n * n)
	if water.lakes_enabled:
		var fill := LakeBasins.fill_depressions(raw, n)
		var result := LakeBasins.extract_basins(raw, fill, n, step, water.lake_min_area, water.lake_max_depth)
		lake_depth = result["depth"]
		for basin: Dictionary in result["basins"]:
			var cells: Rect2i = basin["cell_bounds"]
			var world_min := Vector2(origin + float(cells.position.x) * step, origin + float(cells.position.y) * step)
			_lake_basins.append({
				"bounds": Rect2(world_min, Vector2(cells.size) * step),
				"level": basin["level"],
				"area": basin["area"],
			})
	_lake_depth = lake_depth

	var combined := PackedFloat32Array()
	combined.resize(n * n)
	var bed := PackedFloat32Array()
	bed.resize(n * n)
	for idx in n * n:
		var depth: float = lake_depth[idx]
		bed[idx] = DRY_BED
		if water.sea_enabled:
			# At high water, the design level everything baked uses.
			depth = maxf(depth, water.sea_high_water() - raw[idx])
			bed[idx] = raw[idx]
		combined[idx] = maxf(depth, 0.0)
	_water_depth = combined
	_water_bed = bed


## Sorted samples of `noise` on a grid across the world.
func _measure(noise: FastNoiseLite) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(MEASURE_GRID * MEASURE_GRID)
	var step := profile.world_size / float(MEASURE_GRID)
	for j in MEASURE_GRID:
		for i in MEASURE_GRID:
			values[j * MEASURE_GRID + i] = noise.get_noise_2d(
				-_half_world + (float(i) + 0.5) * step, -_half_world + (float(j) + 0.5) * step)
	values.sort()
	return values


static func _quantile(sorted: PackedFloat32Array, q: float) -> float:
	var i := clampi(int(q * float(sorted.size())), 0, sorted.size() - 1)
	return sorted[i]
