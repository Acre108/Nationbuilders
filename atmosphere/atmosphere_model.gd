class_name AtmosphereModel
extends RefCounted

## Time-of-day, weather and sky colour maths. Pure: no nodes, no rendering.
##
## Ported from PlacesOS apps/client/src/world/atmosphere-model.ts
## (calculateAtmosphereFrame) and skybox.ts (skyboxStyle). The numbers are
## theirs -- palettes, the 58 degree sun arc, weather dimming, soul tint -- so a
## PlacesOS place and a SpacesOS location lit at the same hour agree. A
## destination with a latitude has the real sun instead (solar_position()).
##
## Where this deliberately differs from the source, and why:
##
## * Fog is darkened at night. PlacesOS kept one fog colour all day, which was
##   harmless in a room at their tiny fog density; across a SpacesOS landscape a
##   pale night fog makes the whole horizon glow.
## * Fog is a MULTIPLIER on the location's own haze (FoliageProfile.haze_amount,
##   drawn as depth haze by AtmosphereHaze), not the preset's absolute density.
##   The preset values (0.006 / 0.012) were tuned for rooms a few metres across
##   and would white out a landscape.
## * Sky colours blend continuously. skybox.ts switched on a discrete day
##   period (night/dawn/day/dusk) and rebuilt a cubemap at each switch, which
##   was fine for a clock that never moved. SpacesOS can run the clock, so the
##   same tints are weighted by smooth night and twilight amounts instead.
## * The place-seeded mountain silhouette painted into the PlacesOS skybox is
##   not ported: SpacesOS has real terrain on the horizon.
## * Warmth comes from the light, not the sky (cosy pass, Oct 2026). Golden
##   hour's midday sky is a soft blue instead of PlacesOS's beige, which read
##   as haze over a whole landscape; its ambient is warmer; the sun warms
##   towards the horizon colour from 50 degrees rather than 34, so the
##   afternoon turns amber; and soul warmth may tint up to 30%, at half
##   strength on the sky.
## * Night (Oct 2026): a full moon rides opposite the sun and takes over the
##   directional light once the sun is 6 degrees down, so night has shape and
##   shadows. Fill fades through civil twilight (to -10 degrees, not -5) and
##   direct sun stops at the horizon, so the ground stays readable at dusk;
##   stars wait for the sun to sink past about 5 degrees. The night fill is
##   bluer, and overcast skies darken after dark instead of staying day-grey.

const _PALETTES := {
	AtmosphereProfile.Preset.GOLDEN_HOUR: {
		"ambient_day": "#c9b899", "ambient_night": "#5a6f9e",
		"sky_day": "#9ec0dc", "sky_night": "#111a2c",
		"sun": "#ffe3b3", "fog": "#ece5d6",
		"sun_intensity": 1.45,
	},
	AtmosphereProfile.Preset.QUIET_EVENING: {
		"ambient_day": "#9aa7b6", "ambient_night": "#5a6f9e",
		"sky_day": "#bcc7cf", "sky_night": "#111827",
		"sun": "#f6c792", "fog": "#c5c9c9",
		"sun_intensity": 0.8,
	},
}

## Per weather kind at full intensity: sun and ambient multipliers, fog
## multiplier, and the colour the sky greys towards. From atmosphere-model.ts
## for cloudy and rain; MIST and STORM are SpacesOS's own.
const _WEATHER := {
	AtmosphereProfile.Weather.CLOUDY: {"sun": 0.42, "ambient": 0.86, "fog": 1.35, "sky": "#aab2b5"},
	AtmosphereProfile.Weather.RAIN: {"sun": 0.28, "ambient": 0.72, "fog": 1.9, "sky": "#778594"},
	AtmosphereProfile.Weather.MIST: {"sun": 0.6, "ambient": 0.92, "fog": 1.0, "sky": "#c4c8c4"},
	# Storm: SpacesOS's own. Darker and heavier than rain throughout.
	AtmosphereProfile.Weather.STORM: {"sun": 0.16, "ambient": 0.6, "fog": 2.3, "sky": "#5d6874"},
}
const _CLOUDY_SKY := "#aab2b5"
## Mist lit by day, as a colour the fog leans towards.
const _MIST := "#dcdfdb"
const _HORIZON_WARM := "#ff9567"
const _SOUL_WARM := "#ffb066"
const _SOUL_COOL := "#7fa2c9"
const _SOUL_WARMTH_MAX_BLEND := 0.3
## Pale midday horizon the clear sky fades to, before any twilight peach.
const _HORIZON_DAY := "#e4e6e0"
## Dusky rose the fill leans towards in twilight, after the sun has gone.
const _TWILIGHT_FILL := "#b8949a"
## Overcast sky after dark: dark slate, not the daytime cloud grey.
const _NIGHT_OVERCAST := "#1b2029"
const _MOON := "#8ea6d6"
## Moon's directional strength under a clear sky, before sun_energy_scale.
const MOON_INTENSITY := 0.12
## Peak sun elevation at noon, degrees.
const SUN_PEAK := 58.0


class Frame:
	var hour: float
	var time_label: String
	## "night", "dawn", "day" or "dusk" -- for labels and HUDs only; nothing
	## visual switches on it.
	var period: String
	var zone: AtmosphereZone
	var weather: AtmosphereProfile.Weather
	var weather_amount: float
	## 0 at night .. 1 in full day.
	var daylight: float
	var ambient_colour: Color
	var ambient_intensity: float
	## Lighting uses the unzoned value so camera containment cannot dim outdoors.
	## ambient_intensity retains the legacy zone-scaled model value for callers.
	var ambient_outdoor_intensity: float
	var sky_colour: Color
	var fog_colour: Color
	## Multiplies the location's haze (AtmosphereHaze.apply()'s `weather`).
	var fog_scale: float
	## 0..1: how strongly the haze glows towards the sun. Strongest with a low
	## sun in clear air -- the amber bloom of a late afternoon -- faint at
	## midday, gone under heavy cloud and after sunset.
	var haze_glow: float
	var sun_colour: Color
	var sun_intensity: float
	var sun_elevation: float
	var sun_azimuth: float
	## Full moon, opposite the sun. Takes the directional light when brighter.
	var moon_colour: Color
	var moon_intensity: float
	var moon_elevation: float
	var moon_azimuth: float
	var moon_lit: bool
	## 0..1: how far artificial lights (street lamps, lit windows) are on.
	## Switches on through sunset and is full once the sun is 3 degrees down.
	var lights_on: float
	var rain_intensity: float
	## 0..1 in STORM weather, else 0. Drives lightning and the darker clouds.
	var storm: float
	# skybox.ts's three-band gradient, plus how much of its star field shows.
	var sky_zenith: Color
	var sky_horizon: Color
	var sky_ground: Color
	var star_amount: float
	## 0..1, peaks with the sun near the horizon and lingers a little after it
	## sets -- the afterglow. Drives the sky's sunward horizon glow and the warm
	## underside of clouds. New in SpacesOS; PlacesOS had no sun-facing glow.
	var twilight: float
	## 0..1: mist from MIST weather or from dawn, whichever is thicker. Drives
	## height fog and a distance-fog boost in AtmosphereSystem.
	var mist: float

	func is_inside() -> bool:
		return zone != null and zone.kind == AtmosphereZone.Kind.INSIDE


static func smoothstep_range(from: float, to: float, value: float) -> float:
	var t := clampf((value - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func wrap_hour(hour: float) -> float:
	return fposmod(hour, 24.0)


static func format_time(hour: float) -> String:
	var minutes := int(round(wrap_hour(hour) * 60.0)) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## The real sun at `latitude` (degrees north) on `day_of_year` at local
## mean solar time `hour`: Vector3(elevation, azimuth clockwise from north,
## sunrise hour), degrees and hours. NOAA's general solar position
## formulae (fractional-year series for the declination and the equation of
## time, under a minute and 0.1 degree out), without refraction. Sunrise is
## when the disc's top meets the horizon (-0.833 degrees), with that day's
## noon declination; NAN in polar day or night.
static func solar_position(latitude: float, day_of_year: float, hour: float) -> Vector3:
	var g := TAU / 365.0 * (day_of_year - 1.0 + (hour - 12.0) / 24.0)
	var eq_minutes := _equation_of_time(g)
	var decl := _declination(g)
	var lat := deg_to_rad(latitude)
	var ha := deg_to_rad((hour * 60.0 + eq_minutes) / 4.0 - 180.0)
	var sin_el := sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)
	var elevation := rad_to_deg(asin(clampf(sin_el, -1.0, 1.0)))
	var azimuth := fposmod(rad_to_deg(atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat))) + 180.0, 360.0)
	var g_noon := TAU / 365.0 * (day_of_year - 1.0)
	var decl_noon := _declination(g_noon)
	var cos_h0 := (sin(deg_to_rad(-0.833)) - sin(lat) * sin(decl_noon)) / (cos(lat) * cos(decl_noon))
	var sunrise := NAN
	if absf(cos_h0) <= 1.0:
		sunrise = 12.0 - rad_to_deg(acos(cos_h0)) / 15.0 - _equation_of_time(g_noon) / 60.0
	return Vector3(elevation, azimuth, sunrise)


## Vector2(sunrise, sunset) hours for the profile's place and date: 6 and 18
## on the PlacesOS sun path, NAN in polar day or night.
static func daylight(profile: AtmosphereProfile) -> Vector2:
	if is_nan(profile.latitude):
		return Vector2(6.0, 18.0)
	var sunrise := solar_position(profile.latitude, profile.day_of_year, 12.0).z
	if is_nan(sunrise):
		return Vector2(NAN, NAN)
	var noon := 12.0 - _equation_of_time(TAU / 365.0 * (profile.day_of_year - 1.0)) / 60.0
	return Vector2(sunrise, 2.0 * noon - sunrise)


## In-game hours per real second at `hour`. With night_minutes set, the
## daylight hours share the rest of the day's minutes and the night hours
## share night_minutes; otherwise every hour runs at the same pace.
static func clock_rate(profile: AtmosphereProfile, hour: float) -> float:
	var minutes := profile.day_length_minutes
	if minutes <= 0.0:
		return 0.0
	var span := daylight(profile)
	if profile.night_minutes <= 0.0 or profile.night_minutes >= minutes or is_nan(span.x):
		return 24.0 / (minutes * 60.0)
	var h := wrap_hour(hour)
	var light := span.y - span.x
	if h >= span.x and h < span.y:
		return light / ((minutes - profile.night_minutes) * 60.0)
	return (24.0 - light) / (profile.night_minutes * 60.0)


static func _declination(g: float) -> float:
	return 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) 		+ 0.000907 * sin(2.0 * g) - 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)


## Apparent minus mean solar time, minutes.
static func _equation_of_time(g: float) -> float:
	return 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))


## Vector3(elevation, yaw, sunrise hour) for the frame. Yaw turns the sun
## node (Godot lights shine along -Z): the direction towards the sun is
## Basis.from_euler(Vector3(-elevation, yaw, 0)).z, so with X east a compass
## azimuth A is yaw 180 - A where north is -Z, A where north is +Z. Without
## a latitude, the PlacesOS arc: a 58 degree peak, sunrise at 06:00.
static func sun_angles(profile: AtmosphereProfile, hour: float) -> Vector3:
	if is_nan(profile.latitude):
		return Vector3(sin(((hour - 6.0) / 12.0) * PI) * SUN_PEAK, -105.0 + ((hour - 6.0) / 12.0) * 210.0, 6.0)
	var sun := solar_position(profile.latitude, profile.day_of_year, hour)
	var yaw := sun.y if profile.north_z > 0.0 else 180.0 - sun.y
	return Vector3(sun.x, wrapf(yaw, -180.0, 180.0), sun.z)


static func day_period(hour: float) -> String:
	var h := wrap_hour(hour)
	if h < 5.5 or h >= 20.5:
		return "night"
	if h < 8.0:
		return "dawn"
	if h < 17.0:
		return "day"
	return "dusk"


## First zone containing the point, or null. Ordered, as in PlacesOS.
static func find_zone(zones: Array[AtmosphereZone], point: Vector2) -> AtmosphereZone:
	for zone in zones:
		if zone != null and zone.contains(point):
			return zone
	return null

static func find_zone_3d(zones: Array[AtmosphereZone], point: Vector3) -> AtmosphereZone:
	for zone in zones:
		if zone != null and zone.contains_3d(point): return zone
	return null


static func preset_fog_colour(preset: AtmosphereProfile.Preset) -> Color:
	return Color(_PALETTES[preset]["fog"])


## calculateAtmosphereFrame. `weather` and `amount` are passed separately from
## the profile because AtmosphereSystem fades between weather states.
## `fog_base` is the daytime fog colour -- the location's own when it has one.
static func calculate(
	profile: AtmosphereProfile,
	hour: float,
	weather: AtmosphereProfile.Weather,
	amount: float,
	zone: AtmosphereZone,
	fog_base: Color,
	place_seed: int = 0,
) -> Frame:
	var palette: Dictionary = _PALETTES[profile.preset]
	var warmth := clampf(profile.soul_warmth, -1.0, 1.0)
	var soul_tint := Color(_SOUL_WARM if warmth >= 0.0 else _SOUL_COOL)
	var soul_amount := absf(warmth) * _SOUL_WARMTH_MAX_BLEND
	var soul := func(c: Color) -> Color: return c.lerp(soul_tint, soul_amount)
	var soul_sky := func(c: Color) -> Color: return c.lerp(soul_tint, soul_amount * 0.5)

	var f := Frame.new()
	f.hour = wrap_hour(hour)
	f.time_label = format_time(f.hour)
	f.period = day_period(f.hour)
	f.zone = zone
	f.weather = weather
	f.weather_amount = amount

	var sun := sun_angles(profile, f.hour)
	f.sun_elevation = sun.x
	f.sun_azimuth = sun.y
	if not is_nan(profile.latitude):
		# Labels by the real sun: civil night below -6 degrees.
		f.period = "night" if sun.x < -6.0 else ("day" if sun.x >= 10.0 else ("dawn" if f.hour < 12.0 else "dusk"))
	# Fill/sky daylight runs through civil twilight; direct sun needs the disc up.
	var daylight := smoothstep_range(-10.0, 14.0, f.sun_elevation)
	var sun_up := smoothstep_range(-1.0, 10.0, f.sun_elevation)
	var horizon_warmth := daylight * (1.0 - smoothstep_range(10.0, 50.0, absf(f.sun_elevation)))
	f.daylight = daylight

	var clear := weather == AtmosphereProfile.Weather.CLEAR
	var w: Dictionary = _WEATHER.get(weather, {"sun": 1.0, "ambient": 1.0, "fog": 1.0, "sky": _CLOUDY_SKY})
	var weather_sun := lerpf(1.0, w["sun"], amount)
	var weather_ambient := lerpf(1.0, w["ambient"], amount)
	var weather_fog := lerpf(1.0, w["fog"], amount)
	var cloudy_sky := Color(w["sky"]).lerp(Color(_NIGHT_OVERCAST), (1.0 - daylight) * 0.85)
	var sky_weather := 0.0 if clear else amount * 0.7
	var inside := zone != null and zone.kind == AtmosphereZone.Kind.INSIDE

	# Low sun warms the fill as well as the sun, so shade glows rather than greys.
	f.ambient_colour = soul.call(Color(palette["ambient_night"]).lerp(Color(palette["ambient_day"]), daylight)
		.lerp(Color(_SOUL_WARM), horizon_warmth * 0.22))
	f.ambient_outdoor_intensity = lerpf(0.62, 0.74, daylight) * weather_ambient
	f.ambient_intensity = f.ambient_outdoor_intensity * (zone.ambient_scale if inside else 1.0)
	var sky_night := Color(palette["sky_night"])
	f.sky_colour = soul_sky.call(sky_night.lerp(Color(palette["sky_day"]), daylight).lerp(cloudy_sky, sky_weather))
	# Deviation: darkened at night (see header).
	f.fog_colour = fog_base.lerp(cloudy_sky, sky_weather * 0.75).lerp(sky_night, (1.0 - daylight) * 0.85)
	f.fog_scale = weather_fog * (0.28 if inside else 1.0)
	f.sun_colour = soul.call(Color(palette["sun"]).lerp(Color(_HORIZON_WARM), horizon_warmth * 0.78))
	var sun_strength: float = profile.sun_intensity_override if profile.sun_intensity_override >= 0.0 else palette["sun_intensity"]
	f.sun_intensity = sun_strength * sun_up * weather_sun
	f.haze_glow = (0.15 + 0.85 * horizon_warmth) * sun_up * weather_sun * (0.28 if inside else 1.0)
	f.moon_colour = Color(_MOON)
	f.moon_elevation = -f.sun_elevation
	f.moon_azimuth = f.sun_azimuth + 180.0
	f.moon_intensity = MOON_INTENSITY * smoothstep_range(6.0, 16.0, -f.sun_elevation) * weather_sun
	f.moon_lit = f.moon_intensity > f.sun_intensity
	f.lights_on = 1.0 - smoothstep_range(-3.0, 4.0, f.sun_elevation)
	# A storm rains as hard as its intensity, like rain: same streaks, same
	# soaking, same rain sound. What it adds is wind, darkness and lightning.
	var rains := weather == AtmosphereProfile.Weather.RAIN or weather == AtmosphereProfile.Weather.STORM
	f.rain_intensity = amount if rains else 0.0
	f.storm = amount if weather == AtmosphereProfile.Weather.STORM else 0.0

	var low_sun := 1.0 - smoothstep_range(3.0, 24.0, absf(f.sun_elevation))
	f.twilight = low_sun * smoothstep_range(-12.0, -2.0, f.sun_elevation)
	# After sunset the sky, not the sun, lights the ground: a dusky rose fill.
	f.ambient_colour = f.ambient_colour.lerp(Color(_TWILIGHT_FILL), f.twilight * (1.0 - sun_up) * 0.4)
	# Mist: the weather's own, or dawn mist -- a bell 20 minutes after
	# sunrise that rain washes out (none in polar day or night). Indoors
	# there is none.
	var weather_mist := amount if weather == AtmosphereProfile.Weather.MIST else 0.0
	var dawn := 0.0
	if not is_nan(sun.z):
		dawn = profile.dawn_mist * exp(-pow((f.hour - sun.z - 0.3) / 1.4, 2.0)) * (1.0 - f.rain_intensity)
	f.mist = 0.0 if inside else clampf(maxf(weather_mist, dawn), 0.0, 1.0)
	# Mist whitens the fog -- dimly at night, so it never glows in the dark,
	# but it catches the dawn: twilight lights it well before full daylight.
	var mist_light := lerpf(0.25, 1.0, maxf(daylight, f.twilight * 0.8))
	f.fog_colour = f.fog_colour.lerp(Color(_MIST) * mist_light, f.mist * 0.6)

	_sky_bands(f, place_seed, horizon_warmth)
	return f


## skyboxStyle, made continuous. The source picks tint amounts by period; here
## `night` and `twilight` weights blend between those same amounts.
static func _sky_bands(f: Frame, place_seed: int, horizon_warmth: float) -> void:
	# A small place-seeded tint, cool or warm, so neighbouring locations' skies
	# are not identical. Same formula as skybox.ts: ((seed % 19) - 9) / 100.
	var local_tint := float(posmod(place_seed, 19) - 9) / 100.0
	var warmed := f.sky_colour.lerp(
		Color8(119, 150, 181) if local_tint < 0.0 else Color8(238, 181, 137), absf(local_tint))
	var night := 1.0 - f.daylight
	# Twilight: the source's dawn/dusk periods. horizon_warmth already peaks
	# when the sun is low, so it is reused rather than inventing a new curve.
	var twilight := clampf(horizon_warmth * 2.0, 0.0, 1.0)
	var morning := f.hour < 12.0
	f.sky_zenith = warmed.lerp(Color8(23, 38, 67), lerpf(0.16, 0.24, night))
	f.sky_horizon = warmed.lerp(Color(_HORIZON_DAY), 0.5 * f.daylight * (1.0 - twilight)).lerp(
		Color8(255, 194, 151) if morning else Color8(244, 154, 112), lerpf(0.08, 0.45, twilight))
	f.sky_ground = warmed.lerp(Color8(35, 43, 50), 0.68)
	f.star_amount = smoothstep_range(5.0, 14.0, -f.sun_elevation)
