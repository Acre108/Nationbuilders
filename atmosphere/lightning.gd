class_name Lightning
extends Node3D

## Lightning and thunder, in STORM weather.
##
## Only STORM strikes; RAIN never does. The storm's intensity sets both how
## often it strikes and how close: a light storm is a distant one -- rare far
## flashes, thunder that only rumbles, long after -- and a full storm is
## overhead. AtmosphereSystem calls advance() once per frame and reads
## `flash` / `flash_direction` back to light the sky and ambient.
##
## A strike picks a direction and a distance. From those:
##   * the flash -- sky brightening towards the strike, a brief shadowless
##     scene light from that side, an ambient lift -- weaker with distance;
##   * thunder after distance / 343 s, a near crack or a far rumble, quieter
##     with distance, panned towards the strike.
##
## PHOTOSENSITIVITY. Real lightning flickers several times inside half a
## second. Large bright flashes faster than 3 per second are a seizure risk
## (WCAG 2.3.1), so each strike is at most a main flash and one re-flash at
## least 0.34 s later, strikes are lightning_min_gap apart, and
## lightning_flash_scale can dim or remove the flash entirely while keeping
## the thunder.
##
## Strike timing is random, not networked: like the rest of the atmosphere
## (netcode deliberately deferred), each client would see its own strikes.

signal struck(direction: Vector3, distance: float)
signal thunder_played(distance: float, near: bool)

const SPEED_OF_SOUND := 343.0
## Below this distance a strike cracks; beyond it, it only rumbles.
const NEAR_THUNDER_DISTANCE := 1800.0

var profile: AtmosphereProfile
## Current flash, 0..1, already scaled by distance and lightning_flash_scale.
var flash: float = 0.0
## Unit vector from the listener towards the current strike, a little upward.
var flash_direction := Vector3(0, 0.5, -1).normalized()
## Strikes per second right now (0 below the threshold). Exposed for tests/HUD.
var rate: float = 0.0
var strike_count: int = 0
## Thunder still on its way: {time_left, distance, direction}.
var pending_thunder: Array[Dictionary] = []

var _storm: float = 1.0
var _rng := RandomNumberGenerator.new()
var _next_strike: float = -1.0
var _flash_time: float = 99.0
var _pulses: Array = []  # [start, decay, peak]
var _strength: float = 0.0
var _light: DirectionalLight3D
var _thunder_players: Array[AudioStreamPlayer3D] = []
var _near_streams: Array[AudioStream] = []
var _far_streams: Array[AudioStream] = []


func _ready() -> void:
	_rng.randomize()
	_light = DirectionalLight3D.new()
	_light.name = "LightningLight"
	_light.light_color = Color(0.78, 0.84, 1.0)
	# Shadowless: a 0.1 s flash does not earn a second shadow pass.
	_light.shadow_enabled = false
	# Lights the scene only. Left visible to the sky shader, at night (sun
	# hidden) it becomes LIGHT0 and the sky draws a sun disc at the strike.
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)

	_near_streams = _load_streams(["thunder_near_1", "thunder_near_2"])
	_far_streams = _load_streams(["thunder_far_1", "thunder_far_2"])
	# A small pool: thunder rolls for seconds and strikes can overlap.
	for i in 3:
		var player := AudioStreamPlayer3D.new()
		player.name = "Thunder%d" % i
		player.bus = WeatherAudio.BUS
		# Distance is applied as volume below; the 3D player is here only so
		# the thunder pans towards the strike.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 0.0
		player.panning_strength = 0.8
		add_child(player)
		_thunder_players.append(player)


## One frame. `storm` is the current storm intensity (0 outside STORM),
## `listener` the camera.
func advance(delta: float, storm: float, listener: Vector3, inside: bool) -> void:
	_storm = storm
	rate = 0.0 if storm <= 0.001 else lerpf(0.25, 1.0, storm) * profile.lightning_per_minute / 60.0

	if rate > 0.0:
		if _next_strike < 0.0:
			_next_strike = _sample_gap()
		_next_strike -= delta
		if _next_strike <= 0.0:
			strike()
			_next_strike = _sample_gap()
	else:
		_next_strike = -1.0

	_advance_flash(delta, listener, inside)
	_advance_thunder(delta, listener)


## Strikes now. Direction and distance random unless given; tests and the
## debug key pass them.
func strike(direction: Vector3 = Vector3.ZERO, distance: float = -1.0) -> void:
	if direction == Vector3.ZERO:
		var angle := _rng.randf() * TAU
		direction = Vector3(cos(angle), 0.0, sin(angle))
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	if distance < 0.0:
		# Uniform over area, not distance: far strikes are far more common.
		# A light storm is a distant one: its nearest strikes stay far off,
		# closing in to the full near distance as the storm arrives.
		var d := profile.lightning_distance
		var nearest := lerpf(d.y * 0.45, d.x, _storm)
		distance = sqrt(lerpf(nearest * nearest, d.y * d.y, _rng.randf()))
	strike_count += 1
	# Seen low in the sky over the strike: the flash lights the cloud base.
	flash_direction = (flat + Vector3(0.0, lerpf(0.55, 0.15, _distance_t(distance)), 0.0)).normalized()
	_strength = lerpf(1.0, 0.22, _distance_t(distance)) * profile.lightning_flash_scale
	_flash_time = 0.0
	_pulses = [[0.0, 0.06, 1.0]]
	# At most one re-flash, >= 0.34 s later: stays under 3 flashes a second.
	if _rng.randf() < 0.6:
		_pulses.append([_rng.randf_range(0.34, 0.6), 0.05, _rng.randf_range(0.35, 0.75)])
	pending_thunder.append({
		"time_left": distance / SPEED_OF_SOUND,
		"distance": distance,
		"direction": flat,
	})
	struck.emit(flat, distance)


func _advance_flash(delta: float, listener: Vector3, inside: bool) -> void:
	_flash_time += delta
	var value := 0.0
	for p in _pulses:
		var x: float = _flash_time - p[0]
		if x >= 0.0:
			value = maxf(value, p[2] * exp(-x / p[1]))
	flash = value * _strength
	if flash < 0.003:
		flash = 0.0
	# The scene light comes from the strike's side, down onto the land. Not
	# indoors: there the flash reaches the room only as ambient.
	var energy := 0.0 if inside else flash * profile.lightning_light_energy
	_light.visible = energy > 0.001
	_light.light_energy = energy
	if _light.visible:
		_light.global_position = listener
		_light.global_transform.basis = Basis.looking_at(-flash_direction, Vector3.UP)


func _advance_thunder(delta: float, listener: Vector3) -> void:
	for i in range(pending_thunder.size() - 1, -1, -1):
		var t: Dictionary = pending_thunder[i]
		t["time_left"] -= delta
		if t["time_left"] <= 0.0:
			_play_thunder(t["distance"], t["direction"], listener)
			pending_thunder.remove_at(i)


func _play_thunder(distance: float, direction: Vector3, listener: Vector3) -> void:
	var near := distance < NEAR_THUNDER_DISTANCE
	var pool := _near_streams if near else _far_streams
	thunder_played.emit(distance, near)
	if pool.is_empty() or not profile.audio_enabled:
		return
	var player := _free_player()
	player.stream = pool[_rng.randi() % pool.size()]
	player.volume_db = profile.thunder_volume_db - 20.0 * _distance_t(distance)
	# Far thunder a touch lower as well as quieter.
	player.pitch_scale = _rng.randf_range(0.92, 1.06) * lerpf(1.0, 0.9, _distance_t(distance))
	# Close to the listener, on the strike's side: panning only (no attenuation).
	player.global_position = listener + direction * 20.0
	player.play()


func _free_player() -> AudioStreamPlayer3D:
	for p in _thunder_players:
		if not p.playing:
			return p
	# All busy: reuse the one that has played longest.
	var oldest := _thunder_players[0]
	for p in _thunder_players:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func _sample_gap() -> float:
	# Poisson arrivals at `rate`, but never closer than the minimum gap.
	return profile.lightning_min_gap + -log(1.0 - _rng.randf()) / maxf(rate, 0.0001)


func _distance_t(distance: float) -> float:
	var d := profile.lightning_distance
	return clampf((distance - d.x) / maxf(d.y - d.x, 1.0), 0.0, 1.0)


func _load_streams(names: Array) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for n in names:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			out.append(load(path))
		else:
			push_error("Thunder sound missing at %s -- run tools/audio/make_weather_audio.py" % path)
	return out
