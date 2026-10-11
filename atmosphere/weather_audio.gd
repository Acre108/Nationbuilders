class_name WeatherAudio
extends Node

## Weather ambience: rain, wind, foliage rustle and still-air beds that
## cross-fade with the weather, muffled indoors.
##
## Port of PlacesOS apps/client/src/audio/ambience.ts. There, one Web Audio
## noise source was re-filtered per weather (rain high-passed at 720 Hz, quiet
## evening low-passed with a 68 Hz tone). Here the recipes are baked into
## looping WAVs by tools/audio/make_weather_audio.py and mixed live, so a
## change of weather cross-fades instead of switching.
##
## The rustle and water beds are the exceptions to "weather-only": both scale
## by something local, not just the weather kind. Rustle is wind_loop's same
## gust envelope, re-filtered up into leaves/grass's register (1.4-4.2 kHz, a
## "shhh" of many small things, against wind_loop's low roar) AND scaled by
## how much foliage is actually nearby -- see
## AtmosphereSystem._foliage_density(). Water is two beds -- calm (gentle
## lapping, always present near water) and wind-roughened (chop and small
## breaking crests, rising with the gust) -- both scaled by
## AtmosphereSystem._water_proximity(), a live per-frame read of distance to
## the sea/nearest lake/nearest river, since water (unlike foliage cover) is
## a localized feature, not a location-wide density. A storm over open water,
## the same storm through a spruce forest, and the same storm on dry high
## ground should not sound identical.
##
## Everything -- beds and thunder -- goes through the "Weather" bus, created
## here with a low-pass filter. Inside (an INSIDE zone or an indoor
## location) that filter closes to AtmosphereProfile.indoor_cutoff_hz and the
## bus turns down to indoor_volume_db: the weather heard through a roof.
## AtmosphereSystem calls advance() once per frame.

const BUS := &"Weather"
## dB treated as silent. Players keep running below it (cheap, and restarting
## a loop would audibly jump its phase).
const SILENT_DB := -60.0
## How fast a bed follows its target, per second. Weather already fades over
## seconds; this only removes zipper steps.
const GAIN_RATE := 0.8
const INSIDE_RATE := 2.0

var profile: AtmosphereProfile
## Current linear gains 0..1, before each bed's volume. Exposed for tests/HUD.
var rain_gain: float = 0.0
var wind_gain: float = 0.0
var rustle_gain: float = 0.0
var water_calm_gain: float = 0.0
var water_wind_gain: float = 0.0
var still_gain: float = 0.0
var inside_amount: float = 0.0

var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _rustle: AudioStreamPlayer
var _water_calm: AudioStreamPlayer
var _water_wind: AudioStreamPlayer
var _still: AudioStreamPlayer
var _bus_index: int = -1
var _created_bus := false
var _lowpass: AudioEffectLowPassFilter


func _ready() -> void:
	_bus_index = AudioServer.get_bus_index(BUS)
	if _bus_index == -1:
		AudioServer.add_bus()
		_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_index, BUS)
		AudioServer.set_bus_send(_bus_index, &"Master")
		_created_bus = true
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_bus_index, _lowpass)

	_rain = _make_player("rain_loop")
	_wind = _make_player("wind_loop")
	_rustle = _make_player("foliage_rustle_loop")
	_water_calm = _make_player("water_calm_loop")
	_water_wind = _make_player("water_wind_loop")
	_still = _make_player("still_air_loop")


func _exit_tree() -> void:
	# Known exit-time warning: if the whole app quits while the loops play
	# (seen under --quit-after), Godot may report the loops "still in use" -- the audio thread releases a stopped playback on
	# its next mix, and at quit there is none. Removing the atmosphere while
	# the game runs leaks nothing; --wind-check proves that.
	# Leave no trace in the audio server for whatever scene comes next.
	if _bus_index != -1 and AudioServer.get_bus_index(BUS) == _bus_index:
		if _created_bus:
			AudioServer.remove_bus(_bus_index)
		else:
			for i in range(AudioServer.get_bus_effect_count(_bus_index) - 1, -1, -1):
				if AudioServer.get_bus_effect(_bus_index, i) == _lowpass:
					AudioServer.remove_bus_effect(_bus_index, i)


## One frame. `gust_scale` is the weather's foliage gust multiplier, so wind
## is heard exactly as hard as the grass is seen to bend. `foliage_density`
## (0..1, see AtmosphereSystem._foliage_density()) is how much tree/shrub/
## conifer/fern canopy is around the listener right now -- the rustle bed is
## silent at 0 no matter how hard the wind blows, since there is nothing
## there to rustle. `water_proximity` (0..1, see
## AtmosphereSystem._water_proximity()) is the same idea for the sea/lake/
## river beds: silent on dry ground no matter the weather.
func advance(delta: float, frame: AtmosphereModel.Frame, gust_scale: float, foliage_density: float, water_proximity: float) -> void:
	var rain := frame.rain_intensity
	# Rain: square root so light rain is already clearly audible.
	var rain_target := sqrt(rain)
	# Wind: only weather that blows harder than the authored wind is heard --
	# silent when clear or misty, about a third in full cloud, half in rain,
	# full in a storm (gust 2). A clear day's breeze is heard in the trees
	# (rustle below), not as an open-air roar everywhere.
	var wind_target := clampf(gust_scale - 1.0, 0.0, 1.0)
	# Rustle: a soft base so trees are audible in the authored breeze, rising
	# with the gust, scaled by density so an open field never rustles no
	# matter how hard it blows.
	var rustle_target := clampf(0.35 + (gust_scale - 1.0) * 0.9, 0.0, 1.0) * foliage_density
	# Water: calm lapping is present near water at almost any wind (never
	# below 35% of full even in a storm -- it never fully vanishes, chop just
	# dominates over it); the wind-roughened bed rises from nothing in the
	# authored wind to full in a storm, layering on top rather than replacing
	# the calm bed, the same "layer, don't switch" shape rustle uses.
	var water_calm_target := clampf(1.0 - maxf(gust_scale - 1.0, 0.0) * 0.5, 0.35, 1.0) * water_proximity
	var water_wind_target := clampf((gust_scale - 1.0) * 1.2, 0.0, 1.0) * water_proximity
	# Still air is mist's muffled hush. It is low-passed noise much like the
	# wind bed, so it is not used to fill calm clear weather: that read as a
	# wind that never stopped.
	var still_target := clampf(frame.mist * (1.0 - rain), 0.0, 1.0)

	rain_gain = move_toward(rain_gain, rain_target, GAIN_RATE * delta)
	wind_gain = move_toward(wind_gain, wind_target, GAIN_RATE * delta)
	rustle_gain = move_toward(rustle_gain, rustle_target, GAIN_RATE * delta)
	water_calm_gain = move_toward(water_calm_gain, water_calm_target, GAIN_RATE * delta)
	water_wind_gain = move_toward(water_wind_gain, water_wind_target, GAIN_RATE * delta)
	still_gain = move_toward(still_gain, still_target, GAIN_RATE * delta)
	inside_amount = move_toward(inside_amount, 1.0 if frame.is_inside() else 0.0, INSIDE_RATE * delta)

	var on := profile.audio_enabled
	_set_gain(_rain, rain_gain if on else 0.0, profile.rain_volume_db)
	_set_gain(_wind, wind_gain if on else 0.0, profile.wind_volume_db)
	_set_gain(_rustle, rustle_gain if on else 0.0, profile.rustle_volume_db)
	_set_gain(_water_calm, water_calm_gain if on else 0.0, profile.water_calm_volume_db)
	_set_gain(_water_wind, water_wind_gain if on else 0.0, profile.water_wind_volume_db)
	_set_gain(_still, still_gain if on else 0.0, profile.still_air_volume_db)

	# Exponential sweep, so the muffle closes evenly to the ear.
	_lowpass.cutoff_hz = 20000.0 * pow(profile.indoor_cutoff_hz / 20000.0, inside_amount)
	AudioServer.set_bus_volume_db(_bus_index, profile.indoor_volume_db * inside_amount)


func bus_cutoff_hz() -> float:
	return _lowpass.cutoff_hz


func _set_gain(player: AudioStreamPlayer, gain: float, bed_db: float) -> void:
	if player == null:
		return
	player.volume_db = maxf(bed_db + linear_to_db(maxf(gain, 0.00001)), SILENT_DB)


func _make_player(sound: String) -> AudioStreamPlayer:
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		push_error("Weather sound missing at %s -- run tools/audio/make_weather_audio.py" % path)
		return null
	var player := AudioStreamPlayer.new()
	player.name = sound.to_pascal_case()
	player.stream = load(path)
	player.bus = BUS
	player.volume_db = SILENT_DB
	add_child(player)
	player.play()
	return player
