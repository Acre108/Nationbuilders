class_name AtmosphereSystem
extends Node3D

## Runs a location's sky, light and weather, and drives the foliage wind from it.
##
## Port of PlacesOS apps/client/src/world/atmosphere.ts (AtmosphereSystem +
## RainField), skybox.ts, and the DustField from environmental-effects.ts.
## Every frame it:
##
##   1. advances the clock (if the profile's day length is non-zero) and fades
##      any weather change in progress;
##   2. finds the zone the camera stands in, and treats an indoor
##      FoliageLocation as inside, so the Phase 4 indoor skip needs no zone;
##   3. computes an AtmosphereModel.Frame and pushes it into the sun, the
##      WorldEnvironment (ambient, fog) and the sky shader;
##   4. CONNECTS TO THE FOLIAGE WIND: sets the foliage_gust_scale and
##      foliage_wind_scroll shader globals that foliage_common.gdshaderinc
##      reads, so grass, flowers, terrain and both tree styles bend harder and
##      gust faster as the weather worsens. Rain, motes and clouds drift along
##      the same FoliageProfile wind direction at the same multipliers.
##
## What it does NOT port: PlacesOS window lights and local lamp lights. Both
## were generated from `place.json` geometry, which SpacesOS deliberately does
## not carry over (see docs/ATMOSPHERE.md).
##
## Leaving the tree resets the globals, so a scene loaded afterwards without an
## atmosphere gets the authored FoliageProfile wind, not the last storm.

signal weather_changed(kind: AtmosphereProfile.Weather, intensity: float)

## Derived roof volumes, owned by the current scene, never written to profiles.
var building_zones: Array[AtmosphereZone] = []

@export var profile: AtmosphereProfile
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## Supplies the wind direction/speed, the base fog, the place seed and the
## indoor flag. Optional; `foliage_profile` is used when there is no location.
@export var foliage_location: FoliageLocation
@export var foliage_profile: FoliageProfile
## Optional ground focus for orthographic strategy cameras (Nation Builder).
@export var weather_focus: Node3D

@export_group("Graphics")
## Shared lighting defaults; per-scene overrides remain supported.
@export var sun_energy_scale: float = LightingSettings.SUN_SCALE
@export var ambient_energy_scale_day: float = LightingSettings.AMBIENT_DAY_SCALE
@export var ambient_energy_scale_night: float = LightingSettings.AMBIENT_NIGHT_SCALE
## Haze amount when there is no FoliageProfile to take it from. See
## FoliageProfile.haze_amount and AtmosphereHaze.
@export_range(0.0, 1.0) var fallback_haze_amount: float = 0.85

var frame: AtmosphereModel.Frame
## Applied landscape cloud-shadow strength, independent of camera containment.
var cloud_shadow: float = 0.0
var gust_scale: float = 1.0
var wind_speed_scale: float = 1.0
## 0 dry .. 1 soaked. Integrated over time: rain wets, mist leaves dew, sun
## dries. Pushed to the atmosphere_wetness shader global each frame.
var wetness: float = 0.0
## Multiplies only the clock's pace: the village sets it to the game speed,
## so the sun stops when the game is paused and runs faster at 3x.
var clock_scale: float = 1.0
## Lightning and thunder (STORM only) and the ambience beds. Children,
## advanced from _tick() so they always see this frame's weather.
var lightning: Lightning
var audio: WeatherAudio

var _hour: float
var _kind: AtmosphereProfile.Weather
var _amount: float
var _target_kind: AtmosphereProfile.Weather
var _target_amount: float
var _wind_scroll := Vector2.ZERO
var _cloud_offset := Vector2.ZERO
var _sky_material: ShaderMaterial
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _rain_material: StandardMaterial3D
var _motes: GPUParticles3D
var _mote_process: ParticleProcessMaterial

const _RAIN_FALL_SPEED := 11.0
const _RAIN_HEIGHT := 14.0


func _ready() -> void:
	if profile == null:
		profile = AtmosphereProfile.new()
	_hour = profile.time_of_day
	_kind = profile.weather
	_amount = profile.weather_intensity
	_target_kind = _kind
	_target_amount = _amount
	_build_sky()
	if world_environment != null and world_environment.environment != null:
		LightingSettings.apply_display(world_environment.environment)
	_build_rain()
	_build_motes()
	lightning = Lightning.new()
	lightning.name = "Lightning"
	lightning.profile = profile
	add_child(lightning)
	audio = WeatherAudio.new()
	audio.name = "WeatherAudio"
	audio.profile = profile
	add_child(audio)
	_tick(0.0)


## Mirrors Frame.lights_on for scripted lights (street lamps), which cannot
## read the global shader parameter without stalling the renderer. 0 with no
## atmosphere in the tree: lamps stay off and windows stay dark.
static var night_lights: float = 0.0


func _exit_tree() -> void:
	night_lights = 0.0
	RenderingServer.global_shader_parameter_set(&"atmosphere_night_lights", 0.0)
	RenderingServer.global_shader_parameter_set(&"foliage_gust_scale", 1.0)
	RenderingServer.global_shader_parameter_set(&"foliage_wind_scroll", Vector2.ZERO)
	# No atmosphere, no cloud shadows on the ground and no wet ground.
	cloud_shadow = 0.0
	RenderingServer.global_shader_parameter_set(&"atmosphere_cloud_shadow", 0.0)
	RenderingServer.global_shader_parameter_set(&"atmosphere_wetness", 0.0)


## Longest step one frame may take. A loading hitch (the tree impostor bake
## stalls a frame for over a second) would otherwise leap the weather fade and
## the clock forward in one go.
const _MAX_STEP := 0.1

func _process(delta: float) -> void:
	_tick(minf(delta, _MAX_STEP))


# --- Public API --------------------------------------------------------------

func set_time_of_day(hour: float) -> void:
	_hour = AtmosphereModel.wrap_hour(hour)


func get_time_of_day() -> float:
	return _hour


## Fades to new weather over the profile's transition time. A change of KIND
## first fades the current weather to nothing, then the new one in.
## `instant` skips the fade (tests, loading a saved game).
func set_weather(kind: AtmosphereProfile.Weather, intensity: float, instant: bool = false) -> void:
	_target_kind = kind
	_target_amount = clampf(intensity, 0.0, 1.0)
	if kind == AtmosphereProfile.Weather.CLEAR:
		_target_amount = 0.0
	if instant:
		_kind = _target_kind
		_amount = _target_amount


func get_weather() -> AtmosphereProfile.Weather:
	return _kind


func get_weather_amount() -> float:
	return _amount


## What set_weather() last asked for; differs from get_weather() mid-fade.
func get_target_weather() -> AtmosphereProfile.Weather:
	return _target_kind


func get_target_amount() -> float:
	return _target_amount


## One-line readout for debug HUDs.
func status_line() -> String:
	if frame == null:
		return "atmosphere: starting"
	return "atmosphere: %s (%s)    %s %.2f    gust x%.2f  gust speed x%.2f    wet %.2f  mist %.2f    strikes %d%s%s" % [
		frame.time_label, frame.period,
		weather_name(frame.weather), frame.weather_amount,
		gust_scale, wind_speed_scale, wetness, frame.mist, lightning.strike_count,
		"    clock running" if profile.day_length_minutes > 0.0 else "",
		"    INSIDE" if frame.is_inside() else "",
	]


static func weather_name(kind: AtmosphereProfile.Weather) -> String:
	return ["clear", "cloudy", "rain", "mist", "storm"][kind]


## Help text for the keys handle_debug_key() takes.
const DEBUG_KEYS_HELP := "[ ] hour · ; ' 15 min · 0 run clock · 5 6 7 8 9 storm/mist/clear/cloudy/rain · - = intensity · B bolt · \\ dry/soak"

var _debug_intensity := 0.8

## Shared debug controls for the test scenes. Returns true if the key was used.
## The bracket and semicolon keys are the ones the foliage scene used to turn
## the sun by hand; with an atmosphere the sun follows the clock, so they move
## the clock instead.
func handle_debug_key(keycode: Key) -> bool:
	match keycode:
		KEY_BRACKETLEFT:
			set_time_of_day(_hour - 1.0)
		KEY_BRACKETRIGHT:
			set_time_of_day(_hour + 1.0)
		KEY_SEMICOLON:
			set_time_of_day(_hour - 0.25)
		KEY_APOSTROPHE:
			set_time_of_day(_hour + 0.25)
		KEY_0:
			# A two-minute day: long enough to watch, short enough to see dusk.
			profile.day_length_minutes = 0.0 if profile.day_length_minutes > 0.0 else 2.0
		KEY_5:
			set_weather(AtmosphereProfile.Weather.STORM, _debug_intensity)
		KEY_B:
			# A bolt now, whatever the weather: to see and hear one on demand.
			lightning.strike()
		KEY_6:
			set_weather(AtmosphereProfile.Weather.MIST, _debug_intensity)
		KEY_BACKSLASH:
			# Skip the wait: toggle straight between bone dry and soaked, to
			# judge the wet look without sitting through a minute of rain.
			wetness = 0.0 if wetness > 0.5 else 1.0
		KEY_7:
			set_weather(AtmosphereProfile.Weather.CLEAR, 0.0)
		KEY_8:
			set_weather(AtmosphereProfile.Weather.CLOUDY, _debug_intensity)
		KEY_9:
			set_weather(AtmosphereProfile.Weather.RAIN, _debug_intensity)
		KEY_MINUS, KEY_EQUAL:
			_debug_intensity = clampf(_debug_intensity + (0.2 if keycode == KEY_EQUAL else -0.2), 0.0, 1.0)
			if _target_kind != AtmosphereProfile.Weather.CLEAR:
				set_weather(_target_kind, _debug_intensity)
		_:
			return false
	return true


## The foliage_wind_scroll value last pushed. Shader globals cannot be read back
## outside the editor, so tests check this and `gust_scale` instead.
func get_wind_scroll() -> Vector2:
	return _wind_scroll


# --- Per-frame ---------------------------------------------------------------

func _tick(delta: float) -> void:
	if profile.day_length_minutes > 0.0:
		_hour = AtmosphereModel.wrap_hour(_hour + delta * clock_scale * AtmosphereModel.clock_rate(profile, _hour))
	# The tide follows the clock, running or scrubbed (SeaState); the sun
	# follows the location's date.
	if is_instance_valid(foliage_location):
		foliage_location.set_clock_hour(_hour)
		profile.day_of_year = foliage_location.day_of_year
	_advance_weather(delta)

	var fp := _foliage_profile()
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_pos: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	if is_instance_valid(weather_focus): cam_pos = weather_focus.global_position
	var zone := AtmosphereModel.find_zone_3d(profile.zones, cam_pos)
	if zone == null: zone = AtmosphereModel.find_zone_3d(building_zones,cam_pos)
	if zone == null and foliage_location != null and foliage_location.is_indoor():
		zone = _indoor_zone()

	var fog_base: Color = fp.fog_colour if fp != null else AtmosphereModel.preset_fog_colour(profile.preset)
	var place_seed: int = fp.world_seed if fp != null else 0
	frame = AtmosphereModel.calculate(profile, _hour, _kind, _amount, zone, fog_base, place_seed)

	_advance_wetness(delta)
	lightning.advance(delta, frame.storm, cam_pos, frame.is_inside())
	_apply_light(fp)
	_apply_haze(fp, cam_pos)
	_apply_wind(fp, delta)
	audio.advance(delta, frame, gust_scale, _foliage_density(fp, cam_pos), _water_proximity(cam_pos))
	# Storm surge (SEA8) follows the storm.
	if is_instance_valid(foliage_location):
		foliage_location.set_sea_storm(frame.storm, delta)
	# The surf (SEA7) swells with the same storm the waves do.
	var water_layer: WaterLayer = foliage_location.water if is_instance_valid(foliage_location) else null
	if water_layer != null and water_layer.surf_audio != null:
		water_layer.surf_audio.gust_scale = gust_scale
		water_layer.surf_audio.muted = not profile.audio_enabled
	_apply_sky(fp, delta)
	_apply_particles(fp, cam_pos)


func _advance_weather(delta: float) -> void:
	var before_kind := _kind
	var before_amount := _amount
	var rate := 1.0 / maxf(profile.weather_transition_seconds, 0.001)
	if _kind != _target_kind:
		_amount = move_toward(_amount, 0.0, rate * delta)
		# CLEAR has no intensity to fade, so it can switch immediately.
		if _amount <= 0.0 or _kind == AtmosphereProfile.Weather.CLEAR:
			_kind = _target_kind
			_amount = 0.0
	else:
		_amount = move_toward(_amount, _target_amount, rate * delta)
	if _kind != before_kind or not is_equal_approx(_amount, before_amount):
		weather_changed.emit(_kind, _amount)


## Rain soaks the ground towards its intensity; mist tops it up to dew level;
## otherwise it dries, fastest under a clear midday sun. Rising is fast
## (profile.wetting_seconds) and drying slow (profile.drying_minutes), which is
## what makes the ground still glisten after a shower has passed.
func _advance_wetness(delta: float) -> void:
	var target := maxf(frame.rain_intensity, frame.mist * profile.dew_wetness)
	if wetness < target:
		wetness = move_toward(wetness, target, delta / profile.wetting_seconds)
	else:
		var cover := profile.cloud_cover(_kind, _amount)
		var sun := lerpf(0.3, 1.0, frame.daylight) * (1.0 - cover * 0.5)
		wetness = move_toward(wetness, target, delta * sun / (profile.drying_minutes * 60.0))
	RenderingServer.global_shader_parameter_set(&"atmosphere_wetness", wetness)


func _apply_light(fp: FoliageProfile) -> void:
	night_lights = frame.lights_on
	RenderingServer.global_shader_parameter_set(&"atmosphere_night_lights", night_lights)
	if sun != null:
		# One directional light: the sun by day, the moon by night. Sharing the
		# node keeps a single directional shadow pass.
		var moon := frame.moon_lit
		sun.light_color = frame.moon_colour if moon else frame.sun_colour
		sun.light_energy = (frame.moon_intensity if moon else frame.sun_intensity) * sun_energy_scale
		var elevation := frame.moon_elevation if moon else frame.sun_elevation
		var azimuth := frame.moon_azimuth if moon else frame.sun_azimuth
		# Godot lights shine along -Z: pitch down by the elevation, yaw by azimuth.
		sun.rotation = Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0)
		# Off at night instead of energy 0, so the shadow pass is skipped too.
		sun.visible = sun.light_energy > 0.005

	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	# Containment controls local rain/audio. The shared lighting policy uses
	# outdoor fill so the landscape through a window keeps its illumination.
	LightingSettings.apply_atmosphere(env, frame, ambient_energy_scale_day,
		ambient_energy_scale_night, lightning.flash)


## Distance haze (AtmosphereHaze), mist and the sky veil.
func _apply_haze(fp: FoliageProfile, cam_pos: Vector3) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	# Weather haze is relative to the location's own clear-air haze; mist
	# closes in to the same absolute distance everywhere, so it looks alike
	# in a hazy meadow and on clear hills (and still appears where a location
	# has haze turned off).
	var amount := fp.haze_amount if fp != null else fallback_haze_amount
	AtmosphereHaze.apply(env, frame.fog_colour, amount, AtmosphereHaze.reach(foliage_location, cam_pos),
		frame.fog_scale, frame.mist, profile.mist_haze_distance, frame.haze_glow)
	# Mist also fills hollows and valley floors first, through Godot's height
	# fog below the mist layer's top.
	env.fog_height = _mist_ground_height(fp) + profile.mist_depth
	env.fog_height_density = frame.mist * profile.mist_height_density
	# Clear air leaves the sky alone (our shader draws its horizon). Mist veils
	# it, so the sky and the fogged distance meet in one soft white.
	env.fog_sky_affect = frame.mist * 0.7


## The one place weather reaches the foliage wind.
func _apply_wind(fp: FoliageProfile, delta: float) -> void:
	var mult := profile.wind_multipliers(_kind, _amount)
	gust_scale = mult.x
	wind_speed_scale = mult.y
	if fp != null and delta > 0.0:
		# The shader already scrolls at the authored speed; add only the extra.
		_wind_scroll += _wind_dir(fp) * fp.wind_speed * (wind_speed_scale - 1.0) * delta
		# Keep it small so float precision never degrades; the wind texture
		# repeats every 1.0 in UV, so wrapping is invisible.
		_wind_scroll = Vector2(fposmod(_wind_scroll.x, 1.0), fposmod(_wind_scroll.y, 1.0))
	RenderingServer.global_shader_parameter_set(&"foliage_gust_scale", gust_scale)
	RenderingServer.global_shader_parameter_set(&"foliage_wind_scroll", _wind_scroll)


## Sky uniforms, plus the cloud globals the ground reads for its shadows (see
## atmosphere/shaders/atmosphere_clouds.gdshaderinc).
func _apply_sky(fp: FoliageProfile, delta: float) -> void:
	var wind := _wind_dir(fp)
	_cloud_offset += wind * profile.cloud_speed * wind_speed_scale * delta
	_cloud_offset = Vector2(fposmod(_cloud_offset.x, 1.0), fposmod(_cloud_offset.y, 1.0))
	var cover := profile.cloud_cover(_kind, _amount)
	# Towards the sun, from the same angles the sun node is turned by. Computed
	# rather than read off the node so it is right even with no sun node, and
	# after sunset when the node is hidden (the afterglow still needs it).
	var sun_dir := Basis.from_euler(Vector3(
		deg_to_rad(-frame.sun_elevation), deg_to_rad(frame.sun_azimuth), 0.0)).z
	# Shadows need sun to be cast by, and something to contrast with: they fade
	# at night and under a closing sky. These globals also shade the landscape
	# visible through windows, so camera containment must not disable them.
	cloud_shadow = profile.cloud_shadow_strength * frame.daylight * clampf((1.0 - cover) * 3.0, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"atmosphere_cloud_offset", _cloud_offset)
	RenderingServer.global_shader_parameter_set(&"atmosphere_cloud_cover", cover)
	RenderingServer.global_shader_parameter_set(&"atmosphere_cloud_shadow", cloud_shadow)
	RenderingServer.global_shader_parameter_set(&"atmosphere_sun_direction", sun_dir)

	# Clouds lit by the day, greyer and darker in rain, dim blue-grey at night.
	var lit := frame.sky_colour.lerp(Color(1.0, 0.98, 0.95), 0.75 * frame.daylight)
	lit = lit.lerp(frame.sun_colour, 0.25 * frame.daylight) * lerpf(0.35, 1.0, frame.daylight)
	lit = lit.darkened(frame.rain_intensity * 0.35 + frame.storm * 0.25)
	var shade := lit.darkened(0.3).lerp(frame.sky_colour, 0.3)
	# Dawn/dusk glow: the warm horizon colour pulled towards the sun's own.
	var glow := Color("#ff9a5c").lerp(frame.sun_colour, 0.3)
	var belt := Color("#d9a0b0").lerp(frame.sky_zenith, 0.4)
	# Weather hides the glow along with the sun.
	var glow_amount := frame.twilight * (1.0 - clampf(cover - 0.4, 0.0, 0.6) / 0.6 * 0.85)

	var m := _sky_material
	m.set_shader_parameter("sky_zenith", frame.sky_zenith)
	m.set_shader_parameter("sky_horizon", frame.sky_horizon)
	m.set_shader_parameter("sky_ground", frame.sky_ground)
	m.set_shader_parameter("horizon_glow", glow_amount)
	m.set_shader_parameter("glow_colour", glow)
	m.set_shader_parameter("belt_colour", belt)
	m.set_shader_parameter("star_amount", frame.star_amount)
	m.set_shader_parameter("star_seed", float(posmod(fp.world_seed if fp != null else 0, 997)))
	m.set_shader_parameter("sun_disc_colour", Color("#e3e9f2") if frame.moon_lit else frame.sun_colour.lerp(Color(1, 1, 1), 0.3))
	m.set_shader_parameter("moon_disc", 1.0 if frame.moon_lit else 0.0)
	m.set_shader_parameter("cloud_lit", lit)
	m.set_shader_parameter("cloud_shade", shade)
	m.set_shader_parameter("cirrus_amount", profile.cirrus_amount * (1.0 - _amount if _kind != AtmosphereProfile.Weather.CLEAR else 1.0))
	m.set_shader_parameter("cirrus_direction", wind)
	m.set_shader_parameter("lightning_flash", lightning.flash)
	m.set_shader_parameter("lightning_direction", lightning.flash_direction)


func _apply_particles(fp: FoliageProfile, cam_pos: Vector3) -> void:
	var dir := _wind_dir(fp)
	var drift := Vector3(dir.x, 0.0, dir.y) * profile.wind_drift_speed * gust_scale
	var inside := frame.is_inside()

	# Rain: off indoors, since it follows the camera and would fall through the
	# roof. Emitted upwind so drops land around the camera, not downwind of it.
	var rain := 0.0 if inside else frame.rain_intensity
	_rain.emitting = rain > 0.01
	_rain.amount_ratio = rain
	var life := _rain.lifetime
	_rain.global_position = cam_pos + Vector3(0.0, _RAIN_HEIGHT, 0.0) - drift * life * 0.5
	var velocity := Vector3(drift.x, -_RAIN_FALL_SPEED, drift.z)
	_rain_process.direction = velocity.normalized()
	_rain_process.initial_velocity_min = velocity.length() * 0.92
	_rain_process.initial_velocity_max = velocity.length() * 1.08
	# RainField opacity curve, dimmed at night since the streaks are unshaded.
	var rain_colour := Color(0.68, 0.79, 0.9) * lerpf(0.3, 1.0, frame.daylight)
	rain_colour.a = 0.22 + rain * 0.5
	_rain_material.albedo_color = rain_colour

	# Motes: daylight only, thinned by any weather, and in still air indoors.
	# Squared so they are gone well before the stars come out.
	var motes := frame.daylight * frame.daylight * (1.0 - _amount if _kind != AtmosphereProfile.Weather.CLEAR else 1.0)
	_motes.emitting = profile.motes > 0 and motes > 0.02
	_motes.amount_ratio = clampf(motes, 0.0, 1.0)
	_motes.global_position = cam_pos
	var mote_drift := Vector3.ZERO if inside else drift * 0.35
	_mote_process.direction = mote_drift.normalized() if mote_drift.length() > 0.001 else Vector3.UP
	_mote_process.initial_velocity_min = mote_drift.length() * 0.7
	_mote_process.initial_velocity_max = mote_drift.length() * 1.3 + 0.05


# --- Construction ------------------------------------------------------------

func _build_sky() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("res://atmosphere/shaders/sky.gdshader")
	var fp := _foliage_profile()
	var place_seed: int = fp.world_seed if fp != null else 0
	# A global, not a sky uniform: the ground samples it too, for cloud shadows.
	var cloud_noise := FoliageTextures.noise_texture(place_seed + 9001, 0.008, 512, 5)
	RenderingServer.global_shader_parameter_set(&"atmosphere_cloud_noise", cloud_noise.get_rid())
	if world_environment == null:
		return
	if world_environment.environment == null:
		world_environment.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material
	# Uniforms change every frame (clouds drift, the clock may run); incremental
	# mode spreads the radiance update over several frames instead of redoing
	# it all each frame.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := world_environment.environment
	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = maxi(1, profile.rain_drops)
	_rain.lifetime = (_RAIN_HEIGHT + 12.0) / _RAIN_FALL_SPEED
	_rain.local_coords = false
	_rain.emitting = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := profile.rain_radius
	_rain.visibility_aabb = AABB(Vector3(-r - 20.0, -40.0, -r - 20.0), Vector3(2.0 * r + 40.0, 50.0, 2.0 * r + 40.0))

	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = Vector3(r, 1.0, r)
	_rain_process.gravity = Vector3.ZERO
	_rain_process.spread = 2.0
	# Streaks point along their velocity, so wind slants them.
	_rain_process.particle_flag_align_y = true
	_rain_process.scale_min = 0.7
	_rain_process.scale_max = 1.2
	_rain.process_material = _rain_process

	_rain_material = StandardMaterial3D.new()
	_rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_material.albedo_color = Color(0.68, 0.79, 0.9, 0.5)
	# Streaks passing within a metre or two of the lens are huge and read as
	# scratches on the screen, not rain. Fade them out up close.
	_rain_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_rain_material.distance_fade_min_distance = 0.8
	_rain_material.distance_fade_max_distance = 4.0
	var mesh := _crossed_streak(0.012, 0.42)
	mesh.surface_set_material(0, _rain_material)
	_rain.draw_pass_1 = mesh
	add_child(_rain)


## Two crossed thin quads, Y up: a streak that reads from any side without
## needing a camera-facing billboard (which would undo align_y's slant).
func _crossed_streak(width: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := width * 0.5
	for axis in [Vector3(h, 0, 0), Vector3(0, 0, h)]:
		var a: Vector3 = -axis
		var b: Vector3 = axis
		var up := Vector3(0.0, length, 0.0)
		for v in [a, b, b + up, a, b + up, a + up]:
			st.add_vertex(v)
	return st.commit()


func _build_motes() -> void:
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = maxi(1, profile.motes)
	_motes.lifetime = 9.0
	_motes.local_coords = false
	_motes.emitting = false
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := profile.mote_radius
	_motes.visibility_aabb = AABB(Vector3(-r - 10.0, -r, -r - 10.0), Vector3(2.0 * r + 20.0, 2.0 * r, 2.0 * r + 20.0))

	_mote_process = ParticleProcessMaterial.new()
	_mote_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_mote_process.emission_box_extents = Vector3(r, r * 0.35, r)
	_mote_process.gravity = Vector3(0.0, -0.02, 0.0)
	_mote_process.spread = 25.0
	# The slow wander of DustField's sine drift, done by the GPU.
	_mote_process.turbulence_enabled = true
	_mote_process.turbulence_noise_strength = 1.2
	_mote_process.turbulence_noise_scale = 4.0
	_mote_process.turbulence_influence_min = 0.03
	_mote_process.turbulence_influence_max = 0.08
	_mote_process.scale_min = 0.6
	_mote_process.scale_max = 1.3
	# Fade in and out rather than popping at birth and death.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_mote_process.color_ramp = ramp
	_motes.process_material = _mote_process

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	var colour := profile.mote_colour
	colour.a = 0.55
	material.albedo_color = colour
	# A soft round dot. An untextured quad reads as a hard white square, and
	# at dusk those pass for oversized stars.
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = falloff
	material.albedo_texture = dot
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = material
	_motes.draw_pass_1 = quad
	add_child(_motes)


# --- Helpers -----------------------------------------------------------------

func _foliage_profile() -> FoliageProfile:
	if foliage_location != null and foliage_location.profile != null:
		return foliage_location.profile
	return foliage_profile


func _wind_dir(fp: FoliageProfile) -> Vector2:
	var d := fp.wind_direction if fp != null else Vector2(1.0, 0.35)
	return d.normalized() if d.length() > 0.0001 else Vector2.RIGHT


var _foliage_density_profile: FoliageProfile
var _foliage_density_value: float = 0.0

## 0..1 "how much rustle-able foliage is around here", for WeatherAudio's
## rustle bed. A location-level proxy from the profile's own cover fields,
## not sampled at the live camera position -- the same "worth doing simply"
## trade-off _mist_ground_height() below makes for the mist layer. Weighted
## so a dense conifer canopy rustles more than the same numeric cover of
## alpine cushion plants (small, stiff leaves barely move); a broadleaf tree
## or shrub sits at its own literal cover value. Cached per profile: these
## fields never change at runtime, so there is nothing to recompute per frame.
## `_cam_pos` is unused here; subclasses with a known layout (the village grid)
## override this to sample around the listener instead.
func _foliage_density(fp: FoliageProfile, _cam_pos: Vector3 = Vector3.ZERO) -> float:
	if fp == null:
		return 0.0
	if fp == _foliage_density_profile:
		return _foliage_density_value
	_foliage_density_profile = fp
	_foliage_density_value = clampf(
		fp.tree_cover + fp.conifer_cover * 1.1 + fp.shrub_cover * 0.6
		+ fp.fern_cover * 0.4 + fp.cushion_cover * 0.2,
		0.0, 1.0,
	)
	return _foliage_density_value


## Metres from water at which its ambient beds fade to nothing.
const WATER_HEAR_RANGE := 45.0

## 0..1: how close the camera is to open water (sea, a lake, or a river) --
## the water beds' gate (WeatherAudio.advance()). Live per-frame, unlike
## _foliage_density(): water is a localized feature (a lake occupies a few
## hundred metres, not a whole location), so a cached location-wide scalar
## would put waves in the middle of a dry meadow the way it is fine to spread
## tree-canopy rustle evenly through a whole forest.
##
## Approximate, deliberately, in three different ways: sea proximity is read
## from vertical distance to sea_level, not true distance to the shoreline --
## the sea plane's reach (WaterLayer.reach, kilometres) makes it, in
## practice, everywhere at low elevation in any location that has one, so
## height is a cheap stand-in for "near the shore" without an actual
## nearest-point-on-a-huge-plane query. Lake proximity is distance to a
## basin's bounding RECTANGLE, not its actual (often irregular) shoreline.
## River proximity is distance to the nearest traced VERTEX, not the true
## nearest point along the ribbon between vertices. All three are good
## enough for an ambient bed's gain -- nothing else reads this value.
func _water_proximity(cam_pos: Vector3) -> float:
	var water: WaterLayer = foliage_location.water if foliage_location != null else null
	if water == null or water.profile == null:
		return 0.0
	var wp := water.profile
	var closest := INF
	if wp.sea_enabled:
		closest = absf(cam_pos.y - (wp.sea_level if is_nan(water.sea_level_now) else water.sea_level_now))
	var p := Vector2(cam_pos.x, cam_pos.z)
	for basin in water.lake_basins:
		var bounds: Rect2 = basin["bounds"]
		var dx := maxf(maxf(bounds.position.x - p.x, p.x - bounds.end.x), 0.0)
		var dz := maxf(maxf(bounds.position.y - p.y, p.y - bounds.end.y), 0.0)
		closest = minf(closest, Vector2(dx, dz).length())
	for path in water.river_paths:
		for v in path:
			closest = minf(closest, p.distance_to(v))
	if closest == INF:
		return 0.0
	return clampf(1.0 - closest / WATER_HEAR_RANGE, 0.0, 1.0)


var _mist_ground_profile: FoliageProfile
var _mist_ground: float = 0.0

## Average ground height over the location's central square, once per
## location. The mist layer sits a fixed depth above it, so it stays put as the
## camera climbs -- ground BELOW the average (valleys, hollows) fills thickest.
func _mist_ground_height(fp: FoliageProfile) -> float:
	if fp == _mist_ground_profile:
		return _mist_ground
	_mist_ground_profile = fp
	_mist_ground = 0.0
	var terrain: TerrainProvider = foliage_location.terrain if foliage_location != null else null
	if terrain != null:
		var total := 0.0
		for z in range(-2, 3):
			for x in range(-2, 3):
				total += terrain.get_height(x * 150.0, z * 150.0)
		_mist_ground = total / 25.0
	return _mist_ground


var _indoor_zone_cache: AtmosphereZone

func _indoor_zone() -> AtmosphereZone:
	if _indoor_zone_cache == null:
		_indoor_zone_cache = AtmosphereZone.new()
		_indoor_zone_cache.label = "Indoor location"
		_indoor_zone_cache.kind = AtmosphereZone.Kind.INSIDE
	return _indoor_zone_cache
