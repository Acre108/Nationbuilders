class_name ImportedRivers
extends RefCounted

## Validated offline surface water -- rivers here, lakes in `lakes`
## (ImportedLakes), waterfall points in `waterfalls` -- plus a read-only
## spatial index for foliage workers. WaterLayer renders these same paths.
## No network at runtime.
##
## Raw OSM centre lines know nothing about the ground: draped over a 15 m DEM
## they climb over every bump the DEM did not resolve and read as paint on the
## hillside. fit_to_terrain() turns them into water the terrain can hold:
##
## - Ways are merged into continuous chains (OSM splits a stream into many
##   ways; fitting each alone leaves steps where they meet) and densified.
## - Each chain gets a water-surface profile that never rises downstream: an
##   isotonic (least-squares, non-increasing) fit of the ground under it, so a
##   bump is cut half-way and a dip filled half-way rather than all of one.
##   Tributaries are then levelled to the stem they join.
## - shape_at() carves a channel and banks around that profile, which
##   HeightmapTerrainProvider.get_height() applies -- so the drawn ground,
##   collision, foliage placement and the water all agree on one surface.
const CELL_SIZE := 32.0
## Fitted chains are resampled at this spacing; also the ribbon's step.
const PROFILE_STEP := 4.0
## The near ground lattice is 1.33 m (TerrainProvider.TILE_SPACING): a
## channel much narrower than that falls between its vertices and vanishes,
## so none is carved narrower than this, before width variation.
const MIN_HALF_WIDTH := 0.9
## A stream with no mapped width (OSM's width_source "estimated_by_waterway_type")
## is drawn this wide: most are brooks, not the importer's 2 m default.
const ESTIMATED_STREAM_WIDTH := 1.8
## Along each river its width wanders by up to this fraction either way, over
## a few tens of metres, so no channel runs at one exact width like a ditch.
const WIDTH_WANDER := 0.22
## Banks: on the outside of a bend the bank is steeper, with a small cut step
## at the waterline (up to CUT_BANK m); on the inside it shelves gently (a
## point bar). BEND_RADIUS is the bend radius at which this is at full effect.
const CUT_BANK := 0.35
const BEND_RADIUS := 25.0
## Chains are rounded off (Chaikin corner cutting, this many passes) before
## fitting: OSM draws streams as straight lines between nodes tens of metres
## apart. Nodes other ways start or end at stay put, so confluences hold.
const SMOOTH_PASSES := 3
## Water surface below the fitted ground line, metres.
const FREEBOARD := 0.3
## Flat, full-strength bank beyond the waterline before blending into the
## natural ground, and the rise of the bank over it (m per m).
const BANK_INNER := 1.2
const BANK_SLOPE := 0.45
## Blend from the shaped bank back to natural ground: at least BANK_MIN wide,
## wider where the two differ a lot (max ~1:1.6 slope), never beyond BANK_MAX.
const BANK_MIN := 3.0
const BANK_MAX := 12.0
## Where the fitted water would sit deeper than MAX_CUT below the natural
## ground, or higher than MAX_FILL above it, the OSM line and the DEM simply
## disagree (a culvert under an embankment, a line drawn through a hill the
## 30 m DEM smoothed). Carving a gorge or raising a dyke there looks worse
## than the stream briefly going underground, so the water stops and resumes.
const MAX_CUT := 6.0
const MAX_FILL := 2.0
## Shortest run of water worth drawing after such a split.
const MIN_RUN_POINTS := 4
## River points this far inside a lake are the lake's water, not the river's:
## OSM often draws a river's line on through the lake it feeds.
const LAKE_INSET := 2.0
## The water field (water_at()) reaches this far past a river's waterline or
## a lake's shore, beyond the caller's own margin: there it is under the
## bank, which hides it, but a mesh needs those vertices to close its edge.
const WATER_REACH := 1.0
## Below a waterfall's lip this many points foam (the plunge).
const PLUNGE_FOAM_POINTS := 3
## water_at()'s "width" for lake water: wide enough for any shading scale.
const LAKE_WIDTH := 1000.0
## A river line ending this close to a shore is taken to run into that lake.
const MOUTH_SNAP := 8.0
## Over its last stretch into a lake -- this many river widths, within the
## bounds below -- a river's bed rises to the lake's shelf: a delta. A full-depth
## channel cut into the shallow shelf read as a dark trench ending in pale
## shallows.
const MOUTH_TAPER_WIDTHS := 3.0
const MOUTH_TAPER_MIN := 16.0
const MOUTH_TAPER_MAX := 60.0
## An OSM waterfall within this distance of a fitted chain belongs to it.
const FALL_SNAP := 15.0
## Two waterfalls this close along a chain are one drop (OSM often maps a
## cascade's name and its numbered tiers as separate nodes).
const FALL_MERGE := 10.0
## A waterfall's drop is gathered from at most this far downstream into one
## step at the lip; less than FALL_MIN_DROP is no waterfall at all.
const FALL_REACH := 80.0
const FALL_MIN_DROP := 2.0
## Without an OSM height, the drop is what the fitted level loses over this.
const FALL_DEFAULT_SPAN := 24.0
## Ground sampled this far either side of the centre line when fitting; the
## lowest of the three wins, so a line drawn slightly up a valley wall still
## settles toward the valley floor.
const LATERAL_SAMPLE := 4.0
## Two chain ends closer than this are the same OSM node.
const NODE_SNAP := 0.05

var paths: Array[PackedVector2Array] = []
var widths := PackedFloat32Array()
## After fit_to_terrain(): water-surface height per path point, and the
## channel's half-width/depth per path. Empty before (draped fallback).
var surfaces: Array[PackedFloat32Array] = []
var half_widths := PackedFloat32Array()
var depths := PackedFloat32Array()
var attribution := ""
## Lakes and reservoirs from the same sidecar (empty in older sidecars).
var lakes := ImportedLakes.new()
## OSM waterfall points: {"name", "point": Vector2, "height_m": float or null}.
var waterfalls: Array[Dictionary] = []
## Waterfalls placed on fitted paths (fit_to_terrain()), one per drop:
## {"path", "index" (the lip: the drop is between index and index + 1),
## "top", "bottom" (water levels above and below), "pool" (metres of flat
## plunge pool after the lip), "name"}. WaterLayer draws each as a curtain.
var falls: Array[Dictionary] = []
## Points left dry by the MAX_CUT/MAX_FILL plausibility split.
var dropped_points := 0
## Spatial index, packed for the hot path (get_height() on worker threads):
## per segment its ends, (half, surface at a, surface at b, path; path -1 =
## unfitted, foliage mask only) and query bounds (min x, min z, max x, max z).
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_info := PackedVector4Array()
var _seg_bounds := PackedVector4Array()
## Channel depth at each segment's ends (it tapers at lake mouths).
var _seg_depth := PackedVector2Array()
## Fitted segments' water: (downstream direction x, z, speed m/s, foam 0..1;
## foam < 0 = a waterfall's drop, which the curtain draws instead), and the
## index of the path point each starts from.
var _seg_flow := PackedVector4Array()
var _seg_point := PackedInt32Array()
## Fitted segments' banks: (left slope, right slope, left cut step, right cut
## step), "left" being the side where cross(direction, offset) > 0 -- the
## side a positive angle_to() turns towards.
var _seg_bank := PackedVector4Array()
## Fitted segments' tidal weight at each end (mark_tidal(), SEA8): 1 at a
## mouth on the sea, fading upstream; 0 off the tide.
var _seg_tide := PackedVector2Array()
## Paths reached by the tide (mark_tidal()), for tests and the HUD.
var tidal_paths := 0
## Per source path: true where its width was the importer's estimate.
var estimated := PackedByteArray()
var _cells: Dictionary = {}
var _no_segments := PackedInt32Array()
var _fitted := false
var _stream_field := {}
var _stream_field_built := false


static func load_file(path: String, centre: Dictionary, world_size: float, north_axis: String = "+Z") -> ImportedRivers:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024:
		push_error("ImportedRivers: missing or oversized sidecar: " + path)
		return null
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not _valid_data(data, centre, world_size, north_axis):
		push_error("ImportedRivers: invalid sidecar or mismatched location: " + path)
		return null
	var result := ImportedRivers.new()
	result.attribution = data.attribution
	result.lakes = ImportedLakes.from_data(data.get("lakes", []), world_size)
	for fall in data.get("waterfalls", []):
		result.waterfalls.append({"name": fall.get("name", ""), "point": Vector2(fall.point[0], fall.point[1]),
			"height_m": fall.get("height_m")})
	for river in data.rivers:
		var points := PackedVector2Array()
		for point in river.points:
			points.append(Vector2(point[0], point[1]))
		result.paths.append(points)
		result.widths.append(river.width_m)
		result.estimated.append(1 if river.get("width_source", "") == "estimated_by_waterway_type" else 0)
		for i in range(points.size() - 1):
			result._index_segment(points[i], points[i + 1], river.width_m * 0.5, 0.0, 0.0, -1)
	return result


static func _valid_data(data: Variant, centre: Dictionary, world_size: float, north_axis: String = "+Z") -> bool:
	var coordinates := "local_metres_x_east_z_south" if north_axis == "-Z" else "local_metres_x_east_z_north"
	if not data is Dictionary or data.get("version") != 1 or data.get("coordinates") != coordinates:
		return false
	if data.get("centre") != centre or not _number(data.get("world_size")) or not is_equal_approx(float(data.world_size), world_size):
		return false
	if not data.get("attribution") is String or data.attribution.is_empty():
		return false
	if not data.get("rivers") is Array or data.rivers.size() > 5000:
		return false
	var count := 0
	for river in data.rivers:
		if not river is Dictionary or not _number(river.get("width_m")) or river.width_m < 0.5 or river.width_m > 100.0:
			return false
		if not river.get("points") is Array or river.points.size() < 2:
			return false
		count += river.points.size()
		if count > 200000:
			return false
		var previous := Vector2(INF, INF)
		for point in river.points:
			if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]):
				return false
			var p := Vector2(point[0], point[1])
			if absf(p.x) > world_size * 0.5 + 0.01 or absf(p.y) > world_size * 0.5 + 0.01 or p.distance_squared_to(previous) < 0.000001:
				return false
			previous = p
	if not ImportedLakes.valid_data(data.get("lakes", []), world_size):
		return false
	var falls: Variant = data.get("waterfalls", [])
	if not falls is Array or falls.size() > 2000:
		return false
	for fall in falls:
		if not fall is Dictionary or not fall.get("point") is Array or fall.point.size() != 2:
			return false
		if not _number(fall.point[0]) or not _number(fall.point[1]):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func is_fitted() -> bool:
	return _fitted


## Replaces the raw OSM ways with fitted, carved chains, after fitting the
## lakes they flow through. `ground` is the uncarved height Callable(x, z) ->
## float. Call once, before any worker thread reads this object.
func fit_to_terrain(ground: Callable) -> void:
	_fitted = true
	_stream_field = {}
	_stream_field_built = false
	lakes.fit(ground)
	var chains := _merge_chains()
	# Nodes where ways start or end: confluences, which smoothing keeps.
	var anchors := {}
	for chain in chains:
		anchors[_node_key(chain.points[0])] = true
		anchors[_node_key(chain.points[chain.points.size() - 1])] = true
	var fitted: Array[Dictionary] = []
	for chain in chains:
		var dense := _reach_into_lakes(_densify(_smooth(chain.points, anchors)))
		var lows := PackedFloat32Array()
		for i in dense.size():
			lows.append(_lowest_ground(dense, i, ground))
		var falling := _isotonic(lows, true)
		var rising := _isotonic(lows, false)
		# OSM ways point downstream; trust that unless the ground says
		# clearly otherwise (a mistagged way would flood its whole valley).
		if _residual(lows, rising) < _residual(lows, falling) * 0.5:
			dense.reverse()
			rising.reverse()
			falling = rising
		var lips := _find_falls(dense)
		var surface := _smooth_monotone(falling, lips)
		var chain_falls := _gather_drops(surface, lips)
		var allowance := PackedFloat32Array()
		allowance.resize(dense.size())
		for fall in chain_falls:
			# The plunge pool sits below ground the DEM still slopes through:
			# that cut is the gorge a waterfall carves, not an implausible fit.
			for k in range(fall.index + 1, fall.end + 1):
				allowance[k] = fall.top - fall.bottom
		for i in surface.size():
			surface[i] -= FREEBOARD
		var width: float = ESTIMATED_STREAM_WIDTH if chain.estimated else chain.width
		fitted.append({"points": dense, "surface": surface, "width": width, "length": _length(dense),
			"falls": chain_falls, "allowance": allowance})

	# Stems before tributaries: a tributary's last point is levelled to the
	# water already fitted where it joins, so confluences do not step.
	fitted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.length > b.length)
	var levels := {}
	for chain in fitted:
		var points: PackedVector2Array = chain.points
		var surface: PackedFloat32Array = chain.surface
		var end_key := _node_key(points[points.size() - 1])
		var start_key := _node_key(points[0])
		if levels.has(end_key):
			var floor_level: float = levels[end_key]
			for i in surface.size():
				surface[i] = maxf(surface[i], floor_level)
		if levels.has(start_key):
			var ceiling: float = levels[start_key]
			for i in surface.size():
				surface[i] = minf(surface[i], ceiling)
		for i in points.size():
			var key := _node_key(points[i])
			if not levels.has(key):
				levels[key] = surface[i]

	paths.clear()
	widths = PackedFloat32Array()
	surfaces.clear()
	half_widths = PackedFloat32Array()
	depths = PackedFloat32Array()
	_seg_a = PackedVector2Array()
	_seg_b = PackedVector2Array()
	_seg_info = PackedVector4Array()
	_seg_bounds = PackedVector4Array()
	_seg_depth = PackedVector2Array()
	_seg_flow = PackedVector4Array()
	_seg_point = PackedInt32Array()
	_seg_bank = PackedVector4Array()
	_cells.clear()
	falls.clear()
	dropped_points = 0
	for chain in fitted:
		var points: PackedVector2Array = chain.points
		var surface: PackedFloat32Array = chain.surface
		var allowance: PackedFloat32Array = chain.allowance
		var lake_of := PackedInt32Array()
		for p in points:
			var sd := lakes.signed_distance(p.x, p.y)
			lake_of.append(int(sd.y) if sd.x < -LAKE_INSET else -1)
		_meet_lakes(surface, lake_of)
		var run_start := 0
		for i in points.size() + 1:
			var keep := false
			if i < points.size() and lake_of[i] < 0:
				var natural: float = ground.call(points[i].x, points[i].y)
				keep = natural - surface[i] <= MAX_CUT + allowance[i] and surface[i] - natural <= MAX_FILL
				if not keep:
					dropped_points += 1
			if keep:
				continue
			if i - run_start >= MIN_RUN_POINTS:
				var run := points.slice(run_start, i)
				var run_surface := surface.slice(run_start, i)
				var shift := 0
				# Carry the ribbon to LAKE_INSET inside the shore, so it meets
				# the lake's own (outward-grown) water instead of a dry gap.
				if i < points.size() and lake_of[i] >= 0:
					run.append(_mouth(points[i - 1], points[i]))
					run_surface.append(lakes.levels[lake_of[i]])
				if run_start > 0 and lake_of[run_start - 1] >= 0:
					run.insert(0, _mouth(points[run_start], points[run_start - 1]))
					run_surface.insert(0, lakes.levels[lake_of[run_start - 1]])
					shift = 1
				var path_index := paths.size()
				_add_fitted(run, run_surface, chain.width, i < points.size() and lake_of[i] >= 0, shift == 1)
				for fall in chain.falls:
					# Only a drop whose lip and foot both stayed wet is drawn.
					if fall.index >= run_start and fall.index + 1 < i:
						var lip: int = fall.index - run_start + shift
						falls.append({"path": path_index, "index": lip, "top": run_surface[lip],
							"bottom": run_surface[lip + 1], "pool": float(fall.end - fall.index) * PROFILE_STEP,
							"name": fall.name})
			run_start = i + 1
	_mark_falls()


## Lip indices of the OSM waterfalls on a chain, in order downstream:
## [{"index", "height" (OSM's, or -1), "name"}]. Nodes closer together than
## FALL_MERGE are one drop; the one with a height wins.
func _find_falls(points: PackedVector2Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for fall in waterfalls:
		var best := FALL_SNAP
		var at := -1
		for i in points.size() - 1:
			var d := points[i].distance_to(fall.point)
			if d < best:
				best = d
				at = i
		if at < 0:
			continue
		var height: float = float(fall.height_m) if fall.height_m != null else -1.0
		found.append({"index": at, "height": height, "name": fall.name})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
	var merged: Array[Dictionary] = []
	for fall in found:
		if not merged.is_empty() and float(fall.index - merged[-1].index) * PROFILE_STEP < FALL_MERGE:
			if merged[-1].height < 0.0 and fall.height >= 0.0:
				merged[-1] = fall
			continue
		merged.append(fall)
	return merged


## Gathers each waterfall's drop into one step at its lip: the level holds
## until the lip, then the water below it is held flat (the plunge pool) as
## far downstream as it takes to lose the fall's height -- OSM's, or what
## the fit loses over FALL_DEFAULT_SPAN -- within FALL_REACH and before the
## next fall. The DEM smears a 30 m cliff over several cells; real water
## does not. Returns the drops kept: {"index", "end", "top", "bottom", "name"}.
func _gather_drops(surface: PackedFloat32Array, lips: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for n in lips.size():
		var lip: int = lips[n].index
		var limit := mini(surface.size() - 1, lips[n + 1].index if n + 1 < lips.size() else surface.size() - 1)
		var wanted: float = lips[n].height
		if wanted < 0.0:
			wanted = surface[lip] - surface[mini(lip + int(FALL_DEFAULT_SPAN / PROFILE_STEP), limit)]
		var end := lip + 1
		while end < limit and surface[lip] - surface[end] < wanted * 0.9 and float(end - lip) * PROFILE_STEP < FALL_REACH:
			end += 1
		if end > limit or surface[lip] - surface[end] < FALL_MIN_DROP:
			continue
		var bottom := surface[end]
		for k in range(lip + 1, end):
			surface[k] = bottom
		kept.append({"index": lip, "end": end, "top": surface[lip], "bottom": bottom, "name": lips[n].name})
	return kept


## OSM often stops a river's line exactly at the shore. An end within
## MOUTH_SNAP of a lake is carried on along its last direction until it is
## LAKE_INSET inside, so _meet_lakes() and _mouth() see it reach the water.
func _reach_into_lakes(points: PackedVector2Array) -> PackedVector2Array:
	for at_end in [true, false]:
		var tip := points[points.size() - 1] if at_end else points[0]
		var back := points[points.size() - 2] if at_end else points[1]
		var sd := lakes.signed_distance(tip.x, tip.y)
		if int(sd.y) < 0 or sd.x >= MOUTH_SNAP or sd.x < -LAKE_INSET or tip.distance_to(back) < 0.001:
			continue
		var direction := (tip - back).normalized()
		var extra := PackedVector2Array()
		for k in range(1, int(MOUTH_SNAP + LAKE_INSET * 2.0)):
			var p := tip + direction * float(k)
			extra.append(p)
			if lakes.signed_distance(p.x, p.y).x < -LAKE_INSET * 2.0:
				break
		if at_end:
			points.append_array(extra)
		else:
			extra.reverse()
			extra.append_array(points)
			points = extra
	return points


## A river flowing into a lake cannot end below the lake's surface, and one
## flowing out cannot start above it: level each stretch between lakes to the
## lake downstream (raise) and upstream (lower). Both keep it non-increasing.
func _meet_lakes(surface: PackedFloat32Array, lake_of: PackedInt32Array) -> void:
	var start := 0
	while start < surface.size():
		if lake_of[start] >= 0:
			start += 1
			continue
		var end := start
		while end + 1 < surface.size() and lake_of[end + 1] < 0:
			end += 1
		if end + 1 < surface.size():
			var downstream := lakes.levels[lake_of[end + 1]]
			for k in range(start, end + 1):
				surface[k] = maxf(surface[k], downstream)
		if start > 0:
			var upstream := lakes.levels[lake_of[start - 1]]
			for k in range(start, end + 1):
				surface[k] = minf(surface[k], upstream)
		start = end + 1


## The point between `outside` and `inside` exactly LAKE_INSET into the lake.
func _mouth(outside: Vector2, inside: Vector2) -> Vector2:
	var a := outside
	var b := inside
	for i in 16:
		var mid := (a + b) * 0.5
		if lakes.signed_distance(mid.x, mid.y).x < -LAKE_INSET:
			b = mid
		else:
			a = mid
	return b


## `mouth_end` / `mouth_start`: that end runs into a lake, so the bed rises
## to the lake's shelf over the last MOUTH_TAPER_WIDTHS widths.
func _add_fitted(points: PackedVector2Array, surface: PackedFloat32Array, width: float,
		mouth_end := false, mouth_start := false) -> void:
	var half := maxf(width * 0.5, MIN_HALF_WIDTH)
	var index := paths.size()
	var depth := clampf(half * 0.45, 0.6, 2.5)
	paths.append(points)
	widths.append(width)
	surfaces.append(surface)
	half_widths.append(half)
	depths.append(depth)
	var point_depth := PackedFloat32Array()
	point_depth.resize(points.size())
	point_depth.fill(depth)
	var taper := clampf(half * 2.0 * MOUTH_TAPER_WIDTHS, MOUTH_TAPER_MIN, MOUTH_TAPER_MAX)
	var shelf := minf(depth, LAKE_INSET * ImportedLakes.SHORE_SLOPE)
	for end in 2:
		if not (mouth_start if end == 0 else mouth_end):
			continue
		var k := 0 if end == 0 else points.size() - 1
		var step := 1 if end == 0 else -1
		var along := 0.0
		while k >= 0 and k < points.size() and along < taper:
			point_depth[k] = minf(point_depth[k], lerpf(shelf, depth, along / taper))
			along += points[k].distance_to(points[clampi(k + step, 0, points.size() - 1)])
			k += step
	var speed := flow_speed(index)
	var shape := _wander(points, half, index)
	var halves: PackedFloat32Array = shape[0]
	var banks: PackedVector4Array = shape[1]
	for i in range(points.size() - 1):
		var run := maxf(points[i].distance_to(points[i + 1]), 0.001)
		var flow := Vector4(0.0, 0.0, speed, clampf((surface[i] - surface[i + 1]) / run * 12.0, 0.0, 1.0))
		var direction := (points[i + 1] - points[i]) / run
		flow.x = direction.x
		flow.y = direction.y
		var first := _seg_a.size()
		_index_segment(points[i], points[i + 1], (halves[i] + halves[i + 1]) * 0.5, surface[i], surface[i + 1], index,
			point_depth[i], point_depth[i + 1], flow, i)
		for k in range(first, _seg_a.size()):
			_seg_bank[k] = (banks[i] + banks[i + 1]) * 0.5


## Per point of a fitted path: its half-width, wandering by WIDTH_WANDER along
## it, and its banks (as in _seg_bank): steeper with a cut step on the outside
## of a bend, gentler on the inside, and a little irregular everywhere.
## Deterministic per path. [PackedFloat32Array, PackedVector4Array].
func _wander(points: PackedVector2Array, half: float, index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(points[0].x), roundi(points[0].y))) ^ index
	var phases := PackedFloat32Array()
	for k in 6:
		phases.append(rng.randf() * TAU)
	var halves := PackedFloat32Array()
	var banks := PackedVector4Array()
	var along := 0.0
	for i in points.size():
		if i > 0:
			along += points[i - 1].distance_to(points[i])
		var wander := 0.6 * sin(TAU * along / 41.0 + phases[0]) + 0.4 * sin(TAU * along / 15.0 + phases[1])
		halves.append(maxf(half * (1.0 + WIDTH_WANDER * wander), MIN_HALF_WIDTH * 0.8))
		# Signed curvature over a few points either side: > 0 turns left.
		var a := points[maxi(i - 2, 0)]
		var b := points[i]
		var c := points[mini(i + 2, points.size() - 1)]
		var turn := 0.0
		if a != b and b != c:
			var span := a.distance_to(b) + b.distance_to(c)
			turn = (b - a).normalized().angle_to((c - b).normalized()) / maxf(span * 0.5, 0.001)
		var bend := clampf(absf(turn) * BEND_RADIUS, 0.0, 1.0)
		var rough_l := 1.0 + 0.2 * sin(TAU * along / 23.0 + phases[2])
		var rough_r := 1.0 + 0.2 * sin(TAU * along / 19.0 + phases[3])
		var cut_l := 0.5 + 0.5 * sin(TAU * along / 31.0 + phases[4])
		var cut_r := 0.5 + 0.5 * sin(TAU * along / 29.0 + phases[5])
		# Turning left (turn > 0), the right bank is the outside of the bend.
		var outer_left := turn < 0.0
		var steep_l := (1.0 + 0.8 * bend) if outer_left else (1.0 - 0.45 * bend)
		var steep_r := (1.0 - 0.45 * bend) if outer_left else (1.0 + 0.8 * bend)
		banks.append(Vector4(
			BANK_SLOPE * steep_l * rough_l, BANK_SLOPE * steep_r * rough_r,
			CUT_BANK * cut_l * (0.3 + 0.7 * (bend if outer_left else 0.0)),
			CUT_BANK * cut_r * (0.3 + 0.7 * (0.0 if outer_left else bend))))
	return [halves, banks]


## Waterfalls in the flow field: the drop itself carries no water (the
## curtain draws it) and the first PLUNGE_FOAM_POINTS of the pool foam.
func _mark_falls() -> void:
	var lips := {}
	for fall in falls:
		lips[fall.path] = lips.get(fall.path, []) + [fall.index]
	for index in _seg_info.size():
		var path := int(_seg_info[index].w)
		if not lips.has(path):
			continue
		for lip: int in lips[path]:
			var k := _seg_point[index]
			if k == lip:
				_seg_flow[index].w = -1.0
			elif k > lip and k <= lip + PLUNGE_FOAM_POINTS:
				_seg_flow[index].w = 1.0


## Downstream flow speed for a path, m/s, from its mean surface gradient --
## used only to animate the water.
func flow_speed(index: int) -> float:
	var surface: PackedFloat32Array = surfaces[index]
	var length := _length(paths[index])
	if length < 1.0:
		return 0.6
	var drop := surface[0] - surface[surface.size() - 1]
	return clampf(0.5 + drop / length * 40.0, 0.5, 2.5)


## Carved terrain at (x, z) given the natural ground there, plus how wet it
## reads: x = height, y = riverbed (1 under water), z = damp bank.
## Returns (natural, 0, 0) away from any fitted river.
func shape_at(x: float, z: float, natural: float) -> Vector3:
	var cell: PackedInt32Array = _cells.get(Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE)), _no_segments)
	if cell.is_empty():
		return Vector3(natural, 0.0, 0.0)
	var point := Vector2(x, z)
	var best_score := INF
	var best_height := natural
	var bed := 0.0
	var damp := 0.0
	for index in cell:
		var box := _seg_bounds[index]
		if x < box.x or z < box.y or x > box.z or z > box.w:
			continue
		var info := _seg_info[index]
		if info.w < 0.0:
			continue
		var a := _seg_a[index]
		var ab := _seg_b[index] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var d := point.distance_to(a + ab * t)
		var half := info.x
		var span := _seg_depth[index]
		var depth := lerpf(span.x, span.y, t)
		var surface := lerpf(info.y, info.z, t)
		var target: float
		if d < half:
			var r := d / half
			target = surface - depth * (1.0 - r * r * r * r)
		else:
			var bank := _seg_bank[index]
			var left := ab.x * (point.y - a.y) - ab.y * (point.x - a.x) > 0.0
			var slope := bank.x if left else bank.y
			var cut := bank.z if left else bank.w
			target = surface + (d - half) * slope + cut * smoothstep(0.0, 0.5, d - half)
		var inner := half + BANK_INNER
		var blend := clampf(absf(natural - target) * 1.6, BANK_MIN, BANK_MAX)
		var weight := 1.0 - smoothstep(inner, inner + blend, d)
		if weight <= 0.0:
			continue
		var height := lerpf(natural, target, weight)
		# Where channels meet: inside any channel the lowest bed wins, so
		# water is never left standing on another stream's bank; on the
		# inner banks, the channel this point is closest to (a tributary's
		# own bank still buries its ribbon edge up to the stem); out in the
		# bank blends, the strongest pull.
		var score: float
		if d < half:
			score = -1.0e6 + height
		elif d < inner:
			score = d - half
		else:
			score = BANK_MAX + 1.0 - weight
		if score < best_score:
			best_score = score
			best_height = height
		bed = maxf(bed, 1.0 - smoothstep(half - 0.4, half + 0.3, d))
		damp = maxf(damp, 1.0 - smoothstep(half, half + _damp_reach(half), d))
	return Vector3(best_height, bed, damp)


## The water at (x, z), as one field over every fitted river and lake, for
## meshing water on the terrain's own lattice (TerrainProvider.build_water_arrays()):
## [level, flow x, flow z (m/s), foam 0..1, width (m, for shading), wet,
## tidal weight (mark_tidal(); 0 off the tide and on lakes)].
## Empty where there is no water within `margin` + WATER_REACH. `wet` is 1
## inside a channel or lake, or within half of `margin` of one (a lattice
## that spans a narrow stream still meshes it), 0 further out on its bank,
## where the level carries on (under ground) so a mesh can close its edge.
## Channels narrower than `min_width` are left out: coarse lattices cannot
## hold them, and the terrain shader paints them instead (stream_field()).
##
## The level is the channel this point is deepest inside (rivers meeting are
## levelled to each other, and to the lakes they run into, by the fit). Flow,
## foam and width blend between every channel in reach, weighted towards
## their centres, and lake water pulls the flow to rest, so a confluence or a
## river mouth is one continuous surface rather than two meeting.
func water_at(x: float, z: float, margin: float, min_width := 0.0) -> PackedFloat32Array:
	var point := Vector2(x, z)
	var level := NAN
	var best := -INF
	var flow := Vector2.ZERO
	var foam := 0.0
	var width := 0.0
	var weight := 0.0
	var tide := 0.0
	for index in _cells.get(Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE)), _no_segments):
		var info := _seg_info[index]
		if info.w < 0.0:
			continue
		var motion := _seg_flow[index]
		var a := _seg_a[index]
		var ab := _seg_b[index] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var d := point.distance_to(a + ab * t)
		var half := info.x
		var reach := half + margin + WATER_REACH
		if d > reach or motion.w < 0.0 or half * 2.0 < min_width:
			continue
		if half - d > best:
			best = half - d
			level = lerpf(info.y, info.z, t)
			var seg_tide := _seg_tide[index]
			tide = lerpf(seg_tide.x, seg_tide.y, t)
		var w := 1.0 - smoothstep(half * 0.5, reach, d)
		w *= w
		flow += Vector2(motion.x, motion.y) * motion.z * w
		foam += motion.w * w
		width += half * 2.0 * w
		weight += w
	var shore := lakes.signed_distance(x, z)
	var lake := int(shore.y)
	if lake >= 0 and shore.x < margin + WATER_REACH:
		if -shore.x > best:
			best = -shore.x
			level = lakes.levels[lake]
			tide = 0.0
		# Rivers keep their flow for a little way out into the lake.
		var w := smoothstep(0.0, 12.0, -shore.x) * 4.0 + 0.001
		width += LAKE_WIDTH * w
		weight += w
	if is_nan(level):
		return PackedFloat32Array()
	flow /= maxf(weight, 0.001)
	return PackedFloat32Array([level, flow.x, flow.y, foam / maxf(weight, 0.001), width / maxf(weight, 0.001),
		1.0 if best > -margin * 0.5 else 0.0, tide])


## Estuaries (docs/SEA_PLAN.md, SEA8): which fitted rivers the tide comes
## up, and how strongly. A path whose mouth (its last point -- paths run
## downstream) lies in the sea's reach, and which the sea reaches by HAT
## (its spill), is tidal from there; a tributary joining a tidal path within
## TIDE_JOIN metres takes up the distance from the sea where it joins. The
## weight falls from 1 at the mouth to 0 `reach` metres upstream (smoothly),
## and the water shader raises the river towards the live sea level by it --
## never lowers it, so a river standing above the tide is untouched. Call
## after fit_to_terrain(); `hat` is the highest tide's height (local).
const TIDE_JOIN := 16.0


func mark_tidal(sea: ImportedSea, hat: float, reach: float) -> void:
	_seg_tide.fill(Vector2.ZERO)
	tidal_paths = 0
	if sea == null or reach <= 0.0 or surfaces.is_empty():
		return
	# Per path, metres from each point down to its own last point.
	var to_end: Array[PackedFloat32Array] = []
	for points in paths:
		var d := PackedFloat32Array()
		d.resize(points.size())
		var run := 0.0
		for i in range(points.size() - 1, -1, -1):
			if i < points.size() - 1:
				run += points[i].distance_to(points[i + 1])
			d[i] = run
		to_end.append(d)
	# Per path, metres from its last point on to the sea (INF: not tidal).
	var offset := PackedFloat32Array()
	offset.resize(paths.size())
	offset.fill(INF)
	for p in paths.size():
		var mouth := paths[p][paths[p].size() - 1]
		if sea.reach(mouth.x, mouth.y) >= 0.5 and sea.spill(mouth.x, mouth.y) <= hat + 0.5:
			offset[p] = 0.0
	for pass_index in 8:
		var changed := false
		for p in paths.size():
			var mouth := paths[p][paths[p].size() - 1]
			for q in paths.size():
				if q == p or not is_finite(offset[q]):
					continue
				var points := paths[q]
				for j in points.size():
					if points[j].distance_to(mouth) <= TIDE_JOIN:
						var via := offset[q] + to_end[q][j]
						if via < offset[p]:
							offset[p] = via
							changed = true
						break
		if not changed:
			break
	for p in paths.size():
		if is_finite(offset[p]) and offset[p] < reach:
			tidal_paths += 1
	for k in _seg_a.size():
		var p := int(_seg_info[k].w)
		var i := _seg_point[k]
		if p < 0 or i < 0 or p >= paths.size() or not is_finite(offset[p]):
			continue
		var start := offset[p] + to_end[p][i] - paths[p][i].distance_to(_seg_a[k])
		var end := offset[p] + to_end[p][i] - paths[p][i].distance_to(_seg_b[k])
		_seg_tide[k] = Vector2(1.0 - smoothstep(0.0, reach, start), 1.0 - smoothstep(0.0, reach, end))


## The tidal weight (mark_tidal()) of the fitted channel at (x, z): the
## nearest channel's, 0 off the tide.
func tide_weight(x: float, z: float) -> float:
	var sample := water_at(x, z, 0.0)
	return sample[6] if sample.size() > 6 else 0.0


## Whether any fitted water might lie in `area` (world XZ): its index cells
## hold a fitted channel, or a lake's shore or interior.
func has_water_in(area: Rect2) -> bool:
	for cz in range(floori(area.position.y / CELL_SIZE), floori(area.end.y / CELL_SIZE) + 1):
		for cx in range(floori(area.position.x / CELL_SIZE), floori(area.end.x / CELL_SIZE) + 1):
			for index in _cells.get(Vector2i(cx, cz), _no_segments):
				if _seg_info[index].w >= 0.0:
					return true
	return lakes.has_water_in(area)


## Painted streams (stream_field()): channels narrower than this, the widest a
## far (8 m) ground lattice cannot mesh; texel size, metres; and how far
## beyond a channel's waterline a texel still records it.
const PAINT_MAX_WIDTH := 16.0
const PAINT_TEXEL := 4.0
const PAINT_REACH := 6.0


## Narrow channels for the terrain shader to paint where the ground is too
## coarse to mesh their water (beyond the near ring; see TerrainProvider.
## build_water_arrays()'s min_width). Per texel: RG = the offset (m, world XZ)
## from the texel's centre to the nearest point on such a channel's centre
## line, B = that channel's half-width, A = 1 where one is within reach.
## Offsets, not distances: an offset to a straight line is linear in
## position, so bilinear filtering reconstructs it exactly between texels,
## and even a 1.5 m stream paints crisply on 4 m texels -- a filtered
## distance never reaches zero on a line narrower than a texel.
## {"image": Image (RGBAH), "bounds": Rect2}, or {} when there is nothing to
## paint. Built once and cached.
func stream_field() -> Dictionary:
	if _stream_field_built:
		return _stream_field
	_stream_field_built = true
	var bounds := Rect2()
	var any := false
	for index in _seg_info.size():
		var info := _seg_info[index]
		if info.w < 0.0 or info.x * 2.0 >= PAINT_MAX_WIDTH:
			continue
		var box := Rect2(_seg_a[index], Vector2.ZERO).expand(_seg_b[index])
		bounds = box if not any else bounds.merge(box)
		any = true
	if not any:
		return _stream_field
	bounds = bounds.grow(PAINT_MAX_WIDTH + PAINT_REACH + PAINT_TEXEL)
	var w := mini(ceili(bounds.size.x / PAINT_TEXEL), 4096)
	var h := mini(ceili(bounds.size.y / PAINT_TEXEL), 4096)
	var texel := Vector2(bounds.size.x / w, bounds.size.y / h)
	var best := PackedFloat32Array()
	best.resize(w * h)
	best.fill(INF)
	var data := PackedFloat32Array()
	data.resize(w * h * 4)
	for index in _seg_info.size():
		var info := _seg_info[index]
		var half := info.x
		if info.w < 0.0 or half * 2.0 >= PAINT_MAX_WIDTH:
			continue
		var a := _seg_a[index]
		var b := _seg_b[index]
		var reach := half + PAINT_REACH
		var lo := ((Rect2(a, Vector2.ZERO).expand(b).position - Vector2.ONE * reach - bounds.position) / texel).floor()
		var hi := ((Rect2(a, Vector2.ZERO).expand(b).end + Vector2.ONE * reach - bounds.position) / texel).ceil()
		for ty in range(maxi(int(lo.y), 0), mini(int(hi.y), h - 1) + 1):
			for tx in range(maxi(int(lo.x), 0), mini(int(hi.x), w - 1) + 1):
				var centre := bounds.position + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * texel
				var nearest := Geometry2D.get_closest_point_to_segment(centre, a, b)
				var d := centre.distance_to(nearest) - half
				var i := ty * w + tx
				if d < best[i] and d < PAINT_REACH:
					best[i] = d
					data[i * 4] = nearest.x - centre.x
					data[i * 4 + 1] = nearest.y - centre.y
					data[i * 4 + 2] = half
					data[i * 4 + 3] = 1.0
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, data.to_byte_array())
	image.convert(Image.FORMAT_RGBAH)
	_stream_field = {"image": image, "bounds": bounds}
	return _stream_field


## How far (x, z) lies inside the nearest fitted channel, not counting the
## paths in `exclude`: x = metres in from its waterline (negative outside
## every channel), y = that channel's half-width, z = its path (-1: none).
## WaterLayer fades a river's ribbon out where it runs into another's.
func channel_inside(x: float, z: float, exclude: PackedInt32Array) -> Vector3:
	var point := Vector2(x, z)
	var best := Vector3(-INF, 0.0, -1.0)
	for index in _cells.get(Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE)), _no_segments):
		var info := _seg_info[index]
		if info.w < 0.0 or exclude.has(int(info.w)):
			continue
		var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point, _seg_a[index], _seg_b[index]))
		if info.x - d > best.x:
			best = Vector3(info.x - d, info.x, info.w)
	return best


## shape_at()'s bed/bank marks alone (they depend only on distance, not on
## the ground), for the terrain mesh's vertex colour: x = riverbed, y = damp.
func marks_at(x: float, z: float) -> Vector2:
	var point := Vector2(x, z)
	var marks := Vector2.ZERO
	for index in _cells.get(Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE)), _no_segments):
		var box := _seg_bounds[index]
		if x < box.x or z < box.y or x > box.z or z > box.w:
			continue
		var info := _seg_info[index]
		if info.w < 0.0:
			continue
		var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point, _seg_a[index], _seg_b[index]))
		var half := info.x
		marks.x = maxf(marks.x, 1.0 - smoothstep(half - 0.4, half + 0.3, d))
		marks.y = maxf(marks.y, 1.0 - smoothstep(half, half + _damp_reach(half), d))
	return marks


## How far past its waterline a channel's bank reads damp (and, nearest the
## water, bare): in proportion to the stream, so a brook does not run beside a
## band of bare earth like a track.
static func _damp_reach(half: float) -> float:
	return clampf(half * 1.5, 1.0, BANK_INNER + 2.5)


func growth_mask(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var mask := 1.0
	for index in _cells.get(Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE)), _no_segments):
		var box := _seg_bounds[index]
		if x < box.x or z < box.y or x > box.z or z > box.w:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(point, _seg_a[index], _seg_b[index])
		var half := _seg_info[index].x
		mask = minf(mask, smoothstep(half, half + 1.5, point.distance_to(nearest)))
	return mask


## Pre-fit segments (`path` -1) only mask foliage; fitted ones also carry the
## water surface at each end and reach out over the whole bank blend.
func _index_segment(a: Vector2, b: Vector2, half_width: float, sa: float, sb: float, path: int,
		da := 0.0, db := 0.0, flow := Vector4.ZERO, point := -1) -> void:
	var reach := half_width + 2.0 if path < 0 else half_width + BANK_INNER + BANK_MAX
	# Subdivide long source segments before indexing; their diagonal bounding
	# boxes must not fill thousands of unrelated cells.
	var steps := maxi(1, ceili(a.distance_to(b) / CELL_SIZE))
	for step in steps:
		var start := a.lerp(b, float(step) / steps)
		var end := a.lerp(b, float(step + 1) / steps)
		var index := _seg_a.size()
		var bounds := Rect2(start, Vector2.ZERO).expand(end).grow(reach)
		_seg_a.append(start)
		_seg_b.append(end)
		_seg_info.append(Vector4(half_width, lerpf(sa, sb, float(step) / steps),
			lerpf(sa, sb, float(step + 1) / steps), float(path)))
		_seg_bounds.append(Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y))
		_seg_depth.append(Vector2(lerpf(da, db, float(step) / steps), lerpf(da, db, float(step + 1) / steps)))
		_seg_flow.append(flow)
		_seg_point.append(point)
		_seg_bank.append(Vector4(BANK_SLOPE, BANK_SLOPE, 0.0, 0.0))
		_seg_tide.append(Vector2.ZERO)
		for z in range(floori(bounds.position.y / CELL_SIZE), floori(bounds.end.y / CELL_SIZE) + 1):
			for x in range(floori(bounds.position.x / CELL_SIZE), floori(bounds.end.x / CELL_SIZE) + 1):
				var key := Vector2i(x, z)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				# Shared by reference: appending here updates the stored array.
				var list: PackedInt32Array = _cells[key]
				list.append(index)


## Joins ways end-to-start wherever one starts at a node and a way of the
## same width ends there -- a stream split into OSM ways. At a confluence
## (several end there) the longest same-width way carries on through it, so
## the main stem stays one chain and only the tributary ends; the stem split
## there drew two ribbons meeting with a seam and, often, a step. A fork
## (several start) is never joined.
func _merge_chains() -> Array[Dictionary]:
	var starts := {}
	var ends := {}
	for i in paths.size():
		var start_key := _node_key(paths[i][0])
		var end_key := _node_key(paths[i][paths[i].size() - 1])
		starts[start_key] = starts.get(start_key, []) + [i]
		ends[end_key] = ends.get(end_key, []) + [i]
	var next := {}
	var has_previous := {}
	for key in ends:
		if starts.get(key, []).size() != 1:
			continue
		var to: int = starts[key][0]
		var from := -1
		for candidate: int in ends[key]:
			if candidate != to and is_equal_approx(widths[candidate], widths[to]) and (
					from < 0 or _length(paths[candidate]) > _length(paths[from])):
				from = candidate
		if from >= 0:
			next[from] = to
			has_previous[to] = true
	var used := {}
	var chains: Array[Dictionary] = []
	# Heads first, then whatever is left (closed loops).
	var order: Array = []
	for i in paths.size():
		if not has_previous.has(i):
			order.append(i)
	for i in paths.size():
		if has_previous.has(i):
			order.append(i)
	for head in order:
		if used.has(head):
			continue
		var points := PackedVector2Array(paths[head])
		used[head] = true
		var current: int = head
		while next.has(current) and not used.has(next[current]):
			current = next[current]
			used[current] = true
			var tail: PackedVector2Array = paths[current]
			points.append_array(tail.slice(1))
		chains.append({"points": points, "width": widths[head],
			"estimated": head < estimated.size() and estimated[head] == 1})
	return chains


## Chaikin corner cutting, SMOOTH_PASSES times, keeping the ends and every
## point at an `anchors` node key fixed (each stretch between them is cut on
## its own).
static func _smooth(points: PackedVector2Array, anchors: Dictionary) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var result := PackedVector2Array([points[0]])
	var start := 0
	for i in range(1, points.size()):
		if i == points.size() - 1 or anchors.has(_node_key(points[i])):
			var piece := points.slice(start, i + 1)
			for n in SMOOTH_PASSES:
				piece = _chaikin(piece)
			result.append_array(piece.slice(1))
			start = i
	return result


static func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if i > 0:
			out.append(a.lerp(b, 0.25))
		if i < points.size() - 2:
			out.append(a.lerp(b, 0.75))
	out.append(points[points.size() - 1])
	return out


static func _densify(points: PackedVector2Array) -> PackedVector2Array:
	var dense := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var steps := maxi(1, ceili(a.distance_to(b) / PROFILE_STEP))
		for step in range(1, steps + 1):
			dense.append(a.lerp(b, float(step) / steps))
	return dense


static func _lowest_ground(points: PackedVector2Array, i: int, ground: Callable) -> float:
	var prev := points[maxi(i - 1, 0)]
	var next := points[mini(i + 1, points.size() - 1)]
	var tangent := next - prev
	var across := Vector2(-tangent.y, tangent.x).normalized() * LATERAL_SAMPLE if tangent.length_squared() > 0.0 else Vector2.ZERO
	var p := points[i]
	return minf(float(ground.call(p.x, p.y)), minf(
		float(ground.call(p.x + across.x, p.y + across.y)), float(ground.call(p.x - across.x, p.y - across.y))))


## Pool-adjacent-violators: the least-squares fit to `values` that never
## rises (falling) or never falls (rising) along the array.
static func _isotonic(values: PackedFloat32Array, falling: bool) -> PackedFloat32Array:
	var sign := -1.0 if falling else 1.0
	var means := PackedFloat64Array()
	var counts := PackedInt32Array()
	for v in values:
		means.append(v * sign)
		counts.append(1)
		while means.size() > 1 and means[means.size() - 2] > means[means.size() - 1]:
			var n := means.size()
			var total := counts[n - 2] + counts[n - 1]
			means[n - 2] = (means[n - 2] * counts[n - 2] + means[n - 1] * counts[n - 1]) / total
			counts[n - 2] = total
			means.resize(n - 1)
			counts.resize(n - 1)
	var result := PackedFloat32Array()
	for block in means.size():
		for k in counts[block]:
			result.append(means[block] * sign)
	return result


## A centred moving average keeps a non-increasing sequence non-increasing,
## and rounds PAVA's flat pools and sudden drops into a gentler gradient.
## It never averages across a waterfall's lip: the drop there stays a step.
static func _smooth_monotone(values: PackedFloat32Array, lips: Array[Dictionary] = []) -> PackedFloat32Array:
	const RADIUS := 5
	var segment := PackedInt32Array()
	segment.resize(values.size())
	var current := 0
	var next_lip := 0
	for i in values.size():
		segment[i] = current
		if next_lip < lips.size() and i == lips[next_lip].index:
			current += 1
			next_lip += 1
	var result := PackedFloat32Array()
	result.resize(values.size())
	for i in values.size():
		# Shrink the window evenly as it nears a lip: a one-sided window on a
		# steep reach would average only the water above (or below) and lift
		# (or sink) the level metres off the ground right at the waterfall.
		var radius := RADIUS
		while radius > 0 and (segment[maxi(0, i - radius)] != segment[i] 				or segment[mini(values.size() - 1, i + radius)] != segment[i]):
			radius -= 1
		var total := 0.0
		var n := 0
		for k in range(maxi(0, i - radius), mini(values.size(), i + radius + 1)):
			total += values[k]
			n += 1
		result[i] = total / n
	# The window shrinks at the ends; pin them so the average cannot lift the
	# first point above the second or drop the last below its neighbour.
	for i in range(1, result.size()):
		result[i] = minf(result[i], result[i - 1])
	return result


static func _residual(values: PackedFloat32Array, fit: PackedFloat32Array) -> float:
	var total := 0.0
	for i in values.size():
		total += (values[i] - fit[i]) * (values[i] - fit[i])
	return total


static func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


static func _node_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / NODE_SNAP), roundi(p.y / NODE_SNAP))
