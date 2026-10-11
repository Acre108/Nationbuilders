class_name SurfAudio
extends Node3D

## The surf heard from a beach (docs/SEA_PLAN.md, SEA7). A few positional
## emitters of assets/audio/surf_loop.wav (tools/audio/make_weather_audio.py)
## stand on the breaking line nearest the listener: where the shoaling wave
## of sea_surf.gdshaderinc reaches the breaking ratio, at the live sea level
## and sea state. So the sound comes from where the foam is, walks out with
## the ebb and in with the flood, and moves offshore in a storm, when bigger
## waves break in deeper water.
##
## Finding the line: from the listener, along the coast field
## (ImportedSea.coast_direction(): the way surf travels), towards deeper
## water if it is shallower than the breaking depth here, towards the shore
## if it is deeper, until the depth crosses the breaking depth. The centre
## emitter takes that point; the others search from points SPACING metres
## either way along the shore, so the sound spreads along the beach rather
## than coming from one spot. Searched every UPDATE_SECONDS; the emitters
## glide to their new places.
##
## Gain follows the sea state: the same calm height and storm gain as the
## waves (WaterProfile surf_*), through foliage_gust_scale, set here by
## AtmosphereSystem as `gust_scale`. Inland the surf is muffled -- a low-pass
## (the emitters' attenuation filter) closing as the listener goes further
## from the coast, standing in for the dunes in between.
##
## Through the Weather bus, so a roof muffles it like the rain; without an
## atmosphere that bus does not exist and Godot plays it on Master.

const SOUND_PATH := "res://assets/audio/surf_loop.wav"
const EMITTERS := 3
## Along-shore spacing of the outer emitters from the centre one, metres.
const SPACING := 70.0
## Search step and furthest reach along the surf direction, metres. The
## crossing is then bisected to REFINE_STEPS halvings (20 m to 2.5 m).
const SEARCH_STEP := 20.0
const REFINE_STEPS := 3
const SEARCH_RANGE := 900.0
## Listeners further inland than this (coast distance) hear no surf.
const AUDIBLE_INLAND := 1600.0
const UPDATE_SECONDS := 0.25
## How fast emitters glide to a new breaking point, metres per second.
const GLIDE_SPEED := 25.0
## Volume at the calm sea state and in a full storm, dB.
const CALM_DB := -8.0
const STORM_DB := 3.0
const MAX_DISTANCE := 1800.0
const UNIT_SIZE := 25.0
## Muffle: open on the shore, closing to MUFFLE_CUTOFF_HZ from MUFFLE_START
## to MUFFLE_FULL metres inland.
const OPEN_CUTOFF_HZ := 9000.0
const MUFFLE_CUTOFF_HZ := 650.0
const MUFFLE_START := 40.0
const MUFFLE_FULL := 450.0
## Sea_surf.gdshaderinc's breaking ratio and reference depth.
const BREAKING := 0.78

var sea: ImportedSea
var terrain: TerrainProvider
var water: WaterProfile
## Where the listener is (the focus), and the sea's live level.
var listener := Vector3.ZERO
var level: float = 0.0
## foliage_gust_scale: 1 clear .. 2 storm.
var gust_scale: float = 1.0
var muted := false
## The breaking points last found (world XZ, y = level), centre first; empty
## when there is no surf within reach of the listener.
var breaking_points := PackedVector3Array()
## The muffle's current cutoff, for tests and the HUD.
var cutoff_hz: float = OPEN_CUTOFF_HZ

var _players: Array[AudioStreamPlayer3D] = []
var _timer := 0.0
var _placed := false


func _ready() -> void:
	if not ResourceLoader.exists(SOUND_PATH):
		push_error("Surf sound missing at %s -- run tools/audio/make_weather_audio.py" % SOUND_PATH)
		return
	var stream: AudioStream = load(SOUND_PATH)
	for i in EMITTERS:
		var player := AudioStreamPlayer3D.new()
		player.name = "Surf%d" % i
		player.stream = stream
		player.bus = WeatherAudio.BUS
		player.max_distance = MAX_DISTANCE
		player.unit_size = UNIT_SIZE
		player.attenuation_filter_cutoff_hz = OPEN_CUTOFF_HZ
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		player.volume_db = -80.0
		add_child(player)
		# Each starts a third of the loop apart, so the three never break in
		# step (and never comb-filter into one tone).
		player.play(stream.get_length() * float(i) / EMITTERS)
		_players.append(player)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_SECONDS
		refresh()
	_apply(delta)


## Offshore wave height now (sea_surf.gdshaderinc's surf_sea_height()).
func sea_height() -> float:
	return water.surf_height * (1.0 + water.surf_storm_gain * clampf(gust_scale - 1.0, 0.0, 1.0))


## Depth at which the wave breaks: Green's law meeting the breaking cap,
## H0 (h_ref / h)^(1/4) = 0.78 h, so h = (H0 h_ref^(1/4) / 0.78)^(4/5).
func breaking_depth() -> float:
	return pow(sea_height() * pow(8.0, 0.25) / BREAKING, 0.8)


## Re-finds the breaking line round the listener: breaking_points and the
## muffle. Called every UPDATE_SECONDS; tests call it directly.
func refresh() -> void:
	breaking_points.clear()
	if sea == null or terrain == null or water == null or not sea.has_coast():
		return
	var at := Vector2(listener.x, listener.z)
	var inland := -sea.coast_distance(at.x, at.y)
	var t := clampf((inland - MUFFLE_START) / (MUFFLE_FULL - MUFFLE_START), 0.0, 1.0)
	cutoff_hz = OPEN_CUTOFF_HZ * pow(MUFFLE_CUTOFF_HZ / OPEN_CUTOFF_HZ, t)
	if inland > AUDIBLE_INLAND:
		return
	var depth := breaking_depth()
	var centre := find_break(at, depth)
	if not centre.is_finite():
		return
	breaking_points.append(Vector3(centre.x, level, centre.y))
	var dir := sea.coast_direction(centre.x, centre.y)
	var along := Vector2(-dir.y, dir.x)
	for side in [-1.0, 1.0]:
		var p := find_break(centre + along * SPACING * side, depth)
		if p.is_finite():
			breaking_points.append(Vector3(p.x, level, p.y))


## The breaking point found from `from` (world XZ) along the surf direction:
## where the depth at the live level crosses `depth`. Vector2(INF, INF) when
## there is none within SEARCH_RANGE (a cliff straight into deep water also
## counts: the break is at its foot).
func find_break(from: Vector2, depth: float) -> Vector2:
	var p := from
	# Most of the way to the shoreline in one jump when far from it.
	var d := sea.coast_distance(p.x, p.y)
	var dir := sea.coast_direction(p.x, p.y)
	if dir == Vector2.ZERO:
		return Vector2(INF, INF)
	if d < -50.0:
		p -= dir * (-d - 30.0)
	elif d > 600.0:
		p += dir * (d - 500.0)
	var start := _depth(p)
	# Shallower than the break: go out to sea; deeper: come in.
	var outward := start < depth
	var travelled := 0.0
	var prev := p
	var prev_depth := start
	while travelled < SEARCH_RANGE:
		dir = sea.coast_direction(p.x, p.y)
		if dir == Vector2.ZERO:
			break
		p += (-dir if outward else dir) * SEARCH_STEP
		travelled += SEARCH_STEP
		var here := _depth(p)
		if (outward and here >= depth) or (not outward and here < depth):
			# Bisect between the last two points, then interpolate.
			var a := prev
			var b := p
			var da := prev_depth
			var db := here
			for i in REFINE_STEPS:
				var m := a.lerp(b, 0.5)
				var dm := _depth(m)
				if (outward and dm >= depth) or (not outward and dm < depth):
					b = m
					db = dm
				else:
					a = m
					da = dm
			var f := (depth - da) / (db - da) if not is_equal_approx(db, da) else 0.5
			return a.lerp(b, clampf(f, 0.0, 1.0))
		prev = p
		prev_depth = here
	return Vector2(INF, INF)


## Water depth at the live level, 0 on dry ground or where the sea does not
## reach (beyond its reach, or behind a crest above the level).
func _depth(p: Vector2) -> float:
	if sea.reach(p.x, p.y) < 0.5 or sea.spill(p.x, p.y) > level:
		return 0.0
	return maxf(level - terrain.get_height(p.x, p.y), 0.0)


func _apply(delta: float) -> void:
	if _players.is_empty():
		return
	var storm := clampf(gust_scale - 1.0, 0.0, 1.0)
	var db := lerpf(CALM_DB, STORM_DB, storm)
	for i in _players.size():
		var player := _players[i]
		if muted or i >= breaking_points.size():
			player.volume_db = move_toward(player.volume_db, -80.0, 40.0 * delta)
			continue
		var target := breaking_points[i]
		player.position = target if not _placed else player.position.move_toward(target, GLIDE_SPEED * delta)
		player.volume_db = move_toward(player.volume_db, db, 20.0 * delta)
		player.attenuation_filter_cutoff_hz = cutoff_hz
	_placed = _placed or not breaking_points.is_empty()
