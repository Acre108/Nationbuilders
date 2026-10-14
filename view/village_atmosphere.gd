extends "res://atmosphere/atmosphere_system.gd"
## Art overrides run inside the existing weather update, before sky globals.
var art = preload("res://view/village_art.tres")
var environment_time := 0.0
var wind_time := 0.0

func _apply_light(fp: FoliageProfile) -> void:
	# Preserve night, moon and weather. Daylight keeps one authored sun direction.
	if frame.daylight > 0.0:
		frame.sun_azimuth = art.sun_azimuth
		frame.sun_colour = frame.sun_colour.lerp(Color("ffd395"), art.sun_warmth * frame.daylight)
		frame.ambient_colour = frame.ambient_colour.lerp(art.shadow_tint, frame.daylight * 0.85)
	sun_energy_scale = art.sun_intensity
	ambient_energy_scale_day = art.ambient_fill
	super._apply_light(fp)
	if world_environment != null and world_environment.environment != null:
		world_environment.environment.ambient_light_sky_contribution = 0.08

func _ready() -> void:
	profile.cloud_shadow_strength = art.cloud_shadow_opacity
	profile.cloud_speed = art.cloud_speed
	profile.clear_cloud_cover = 0.48
	# Use the village's crisp, sparse motes instead of the source soft dots.
	profile.motes = 0
	super._ready()
	sun.shadow_opacity = 0.72
	sun.shadow_normal_bias = 0.45
	art.apply_material(_sky_material)
	world_environment.environment.glow_enabled = false
	# Direct palette response preserves amber and terracotta highlights.
	# Vertex colours are decoded to linear in the village mesh factory.
	world_environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment.tonemap_exposure = art.exposure
	world_environment.environment.ssao_radius = 0.35
	world_environment.environment.ssao_intensity = art.ao_strength * 1.6
	world_environment.environment.ambient_light_sky_contribution = 0.08

func reset_art_motion() -> void:
	_cloud_offset = Vector2.ZERO
	_wind_scroll = Vector2.ZERO
	environment_time = 0.0
	wind_time = 0.0
	RenderingServer.global_shader_parameter_set("village_environment_time",0.0)
	RenderingServer.global_shader_parameter_set("village_wind_time",0.0)

func _apply_wind(fp: FoliageProfile, delta: float) -> void:
	super._apply_wind(fp,delta)
	environment_time += delta
	wind_time += delta * wind_speed_scale
	RenderingServer.global_shader_parameter_set("village_environment_time",environment_time)
	RenderingServer.global_shader_parameter_set("village_wind_time",wind_time)

func _apply_sky(fp: FoliageProfile, delta: float) -> void:
	super._apply_sky(fp,delta)
	# Orthographic board overviews expose sky-deck projection streaks. Keep
	# the sky for ambient light and cloud shadows, with a quiet weather-aware
	# backdrop behind the clipped hex rather than perspective cloud rays.
	if grid != null and grid.hex_width > 0.0 and world_environment != null:
		var env: Environment = world_environment.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = frame.fog_colour.lerp(art.shadow_tint,0.55).darkened(0.26)

func wind_at(at: Vector3) -> float:
	# CPU counterpart of village_gust; seeds ride the vegetation's gust fronts.
	var phase: float = Vector2(at.x,at.z).dot(art.wind_direction.normalized())*0.23-wind_time*art.wind_speed*12.0
	var front := pow(maxf(0.0,sin(phase)),2.0)
	var envelope := 0.75+0.25*sin(wind_time*0.17)
	var breeze := 0.22+0.08*sin(phase*0.65)
	return (breeze+front*envelope*0.75)*gust_scale

func _exit_tree() -> void:
	super._exit_tree()
	RenderingServer.global_shader_parameter_set("village_environment_time",0.0)
	RenderingServer.global_shader_parameter_set("village_wind_time",0.0)

# --- Proximity audio ----------------------------------------------------------
# The base system has no layout to sample, so it uses one location-wide foliage
# value and finds no water here. The village knows its grid: sample forest and
# water around the camera focus. Zooming in narrows what you hear to what is
# close and turns it up; zoomed out, a wider area blends in, quieter.

## Set by the view on (re)start.
var grid
## Tree roots occupy about one in three cells inside a dense grove.
const _FULL_FOREST := 0.28
var _proximity_key := ""
var _proximity := Vector2.ZERO

func _foliage_density(fp: FoliageProfile, cam_pos: Vector3 = Vector3.ZERO) -> float:
	if grid == null:
		return super._foliage_density(fp, cam_pos)
	return _sample_proximity(cam_pos).x

func _water_proximity(cam_pos: Vector3) -> float:
	if grid == null:
		return super._water_proximity(cam_pos)
	return _sample_proximity(cam_pos).y

## 0 fully zoomed out .. 1 fully zoomed in.
func zoom_closeness() -> float:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or not "zoom_size" in camera:
		return 0.5
	return clampf(inverse_lerp(48.0, 16.0, camera.zoom_size), 0.0, 1.0)

## x: foliage density, y: water proximity, both 0..1. Recomputed only when the
## focus cell, zoom or grid change.
func _sample_proximity(cam_pos: Vector3) -> Vector2:
	var closeness := zoom_closeness()
	var centre := Vector2i(floori(cam_pos.x), floori(cam_pos.z))
	var key := "%s|%.2f|%d|%d" % [centre, closeness, grid.revision,grid.forest_revision]
	if key == _proximity_key:
		return _proximity
	_proximity_key = key
	# How loud nearby things are: never silent zoomed out, full zoomed in.
	var level := lerpf(0.4, 1.0, closeness)
	var forest_radius := lerpf(10.0, 4.0, closeness)
	var water_range := lerpf(14.0, 6.0, closeness)
	var forest := 0.0
	var weight_total := 0.0
	var nearest_water := INF
	var reach := ceili(maxf(forest_radius, water_range))
	var focus := Vector2(cam_pos.x, cam_pos.z)
	for y in range(centre.y - reach, centre.y + reach + 1):
		for x in range(centre.x - reach, centre.x + reach + 1):
			var cell := Vector2i(x, y)
			var tile: String = grid.terrain_at(cell)
			var distance := focus.distance_to(Vector2(x + 0.5, y + 0.5))
			if grid.is_water(cell):
				nearest_water = minf(nearest_water, distance)
			if distance > forest_radius:
				continue
			var weight := 1.0 - distance / forest_radius
			weight_total += weight
			# Cleared forest (buildings, roads) no longer rustles.
			if grid.trees.has(cell) and not grid.occupied.has(cell) and not grid.roads.has(cell):
				forest += weight
			elif grid.saplings.has(cell):
				forest += weight*0.2
	var density := clampf(forest / maxf(weight_total, 0.001) / _FULL_FOREST, 0.0, 1.0)
	var water := clampf(1.0 - nearest_water / water_range, 0.0, 1.0) if nearest_water < INF else 0.0
	_proximity = Vector2(density * level, water * level)
	return _proximity

# --- Live wind and the weather report -----------------------------------------
# The weather panel's wind controls and stats. Wind is authored on the art
# profile (village shaders, motes, seeds) and copied to the foliage profile
# (clouds, rain drift, grass); both are kept in step here. The shaders take it
# as per-material uniforms, so a change is pushed into every material in the
# world -- only when a control moves, never per frame.

const _COMPASS := ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
var _authored_wind := {}

## 16-point compass name for a bearing in degrees clockwise from north (-Z).
static func compass_name(degrees: float) -> String:
	return _COMPASS[posmod(roundi(degrees / 22.5), 16)]

## Bearing the wind blows FROM, degrees clockwise from north. The direction
## vector is where it blows TO, in world (x, z) with north at -Z.
func wind_from_degrees() -> float:
	var to: Vector2 = art.wind_direction.normalized()
	return fposmod(rad_to_deg(atan2(to.x, -to.y)) + 180.0, 360.0)

## Breeze and gust speed as multiples of the authored wind.
func wind_breeze() -> float:
	_remember_authored_wind()
	return art.wind_strength / maxf(_authored_wind.strength, 0.0001)

func wind_gust_speed() -> float:
	_remember_authored_wind()
	return art.wind_speed / maxf(_authored_wind.speed, 0.0001)

func set_wind(from_degrees: float, breeze: float, gust_speed: float) -> void:
	_remember_authored_wind()
	var to := deg_to_rad(from_degrees + 180.0)
	art.wind_direction = Vector2(sin(to), -cos(to))
	art.wind_strength = _authored_wind.strength * breeze
	art.wind_speed = _authored_wind.speed * gust_speed
	var fp := _foliage_profile()
	if fp != null:
		fp.wind_direction = art.wind_direction
		fp.wind_strength = art.wind_strength
		fp.wind_speed = art.wind_speed
	_push_wind()

## Back to the wind as authored (village restart).
func reset_wind() -> void:
	if _authored_wind.is_empty():
		return
	art.wind_direction = _authored_wind.direction
	set_wind(wind_from_degrees(), 1.0, 1.0)

func _remember_authored_wind() -> void:
	if _authored_wind.is_empty():
		_authored_wind = {"direction": art.wind_direction, "strength": art.wind_strength, "speed": art.wind_speed}

func _push_wind() -> void:
	var materials := {}
	if _sky_material != null:
		materials[_sky_material] = true
	var stack: Array[Node] = [get_parent() if get_parent() != null else self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is GeometryInstance3D:
			continue
		_collect_material(materials, node.material_override)
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = node.mesh
			for i in node.get_surface_override_material_count():
				_collect_material(materials, node.get_surface_override_material(i))
		elif node is MultiMeshInstance3D and node.multimesh != null:
			mesh = node.multimesh.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				_collect_material(materials, mesh.surface_get_material(i))
	var direction: Vector2 = art.wind_direction.normalized()
	for material in materials:
		material.set_shader_parameter("village_wind_direction", direction)
		material.set_shader_parameter("village_wind_strength", art.wind_strength)
		material.set_shader_parameter("village_wind_speed", art.wind_speed)
		material.set_shader_parameter("foliage_wind_direction", art.wind_direction)
		material.set_shader_parameter("foliage_wind_strength", art.wind_strength)
		material.set_shader_parameter("foliage_wind_speed", art.wind_speed)

func _collect_material(into: Dictionary, material: Material) -> void:
	if material is ShaderMaterial:
		into[material] = true

## Everything the weather panel shows: [[title, [[label, value], ...]], ...].
func weather_report() -> Array:
	if frame == null:
		return []
	var target := get_target_weather()
	var fading := target != get_weather() or not is_equal_approx(get_target_amount(), get_weather_amount())
	var now := "%s %d%%" % [weather_name(get_weather()).capitalize(), roundi(get_weather_amount() * 100.0)]
	var weather_rows := [["Now", now]]
	if fading:
		weather_rows.append(["Fading to", "%s %d%%" % [weather_name(target).capitalize(), roundi(get_target_amount() * 100.0)]])
	weather_rows.append_array([
		["Rain", _pct(frame.rain_intensity)],
		["Mist", _pct(frame.mist)],
		["Storm", _pct(frame.storm)],
		["Wet ground", _pct(wetness)],
		["Strikes", str(lightning.strike_count)],
	])
	var from := wind_from_degrees()
	var wind_rows := [
		["From", "%s %d°" % [compass_name(from), roundi(from)]],
		["Gust bend", "%.2f×" % gust_scale],
		["Gust travel", "%.2f×" % wind_speed_scale],
	]
	var cover := profile.cloud_cover(get_weather(), get_weather_amount())
	var sky_rows := [
		["Time", "%s  %s" % [frame.time_label, frame.period]],
		["Daylight", _pct(frame.daylight)],
		["Sun height", "%d°" % roundi(frame.sun_elevation)],
		["Sun bearing", "%s %d°" % [compass_name(frame.sun_azimuth), roundi(fposmod(frame.sun_azimuth, 360.0))]],
		["Cloud cover", _pct(cover)],
		["Cloud shadow", _pct(cloud_shadow)],
		["Haze", "%.2f×" % frame.fog_scale],
	]
	var near := _sample_proximity(weather_focus.global_position) if grid != null and is_instance_valid(weather_focus) else Vector2.ZERO
	var sound_rows := [
		["Near trees", _pct(near.x)],
		["Near water", _pct(near.y)],
		["Wind", _pct(audio.wind_gain)],
		["Leaves", _pct(audio.rustle_gain)],
		["Rain", _pct(audio.rain_gain)],
		["Still air", _pct(audio.still_gain)],
		["Water calm / chop", "%s / %s" % [_pct(audio.water_calm_gain), _pct(audio.water_wind_gain)]],
	]
	if not profile.audio_enabled:
		sound_rows.append(["Audio", "off"])
	return [["Weather", weather_rows], ["Wind", wind_rows], ["Sky & light", sky_rows], ["Sound", sound_rows]]

func _pct(value: float) -> String:
	return "%d%%" % roundi(clampf(value, 0.0, 1.0) * 100.0)
