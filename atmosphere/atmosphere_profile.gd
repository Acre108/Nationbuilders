class_name AtmosphereProfile
extends Resource

## One location's sky, light and weather, as authored.
##
## The SpacesOS counterpart of PlacesOS's `place.atmosphere` block (preset,
## timeOfDay, weather, zones, overrides) plus the place's `soul.warmth`.
## AtmosphereSystem turns this into a live frame every tick; AtmosphereModel
## holds the actual maths.
##
## What is NOT here, deliberately: the wind direction and base speed. Those stay
## on FoliageProfile, because the grass, terrain and trees already read them
## from there and a second copy would drift. Weather only SCALES that wind (see
## the Wind group), and rain and motes read the direction from the same place,
## so rain always slants the way the grass is bending.

enum Preset { GOLDEN_HOUR, QUIET_EVENING }
## Appended only: saved profiles store the number, so reordering would change
## the weather of every existing .tres.
enum Weather { CLEAR, CLOUDY, RAIN, MIST, STORM }

@export var preset: Preset = Preset.GOLDEN_HOUR

@export_group("Time")
## Hour of day, 0..24, local mean solar time (docs/ATMOSPHERE.md). At a
## geographic destination the sun follows its latitude and date (`latitude`
## below); elsewhere 6 is sunrise, 12 noon (sun at its 58 degree peak) and 18
## sunset -- the PlacesOS sun path.
@export_range(0.0, 24.0, 0.05) var time_of_day: float = 16.5
## Real minutes per in-game day. 0 freezes the clock, which is the PlacesOS
## behaviour: their places were authored at one fixed hour.
@export_range(0.0, 240.0, 0.5) var day_length_minutes: float = 0.0

## The real sun, set at run time by LocationRuntime from the destination
## (not saved): latitude in degrees north, NAN for the PlacesOS sun path;
## the day of the year; and where the world's north is (-1: -Z, the
## current orientation; +1: legacy +Z-north worlds).
var latitude: float = NAN
var day_of_year: float = 172.0
var north_z: float = -1.0

@export_group("Weather")
@export var weather: Weather = Weather.CLEAR
@export_range(0.0, 1.0) var weather_intensity: float = 0.0
## Seconds to fade from one weather state to another. Changing the KIND fades
## the current weather out and the new one in, so there is never a jump.
@export_range(0.0, 60.0, 0.5) var weather_transition_seconds: float = 8.0

@export_group("Identity")
## -1 cold/distant .. 1 warm/fond. A small tint on sky, sun and ambient,
## capped far below the day/night and weather blends -- PlacesOS soul.warmth.
@export_range(-1.0, 1.0) var soul_warmth: float = 0.0
## Replaces the preset's sun strength when 0 or more. PlacesOS overrides.sunIntensity.
@export_range(-1.0, 3.0, 0.05) var sun_intensity_override: float = -1.0
## Inside/outside areas. First match wins; see AtmosphereZone.
@export var zones: Array[AtmosphereZone] = []

@export_group("Wind")
## At FULL intensity of each weather kind, how much harder gusts bend foliage
## (x) and how much faster they travel (y). Clear weather is always 1, 1: the
## FoliageProfile wind as authored. These are the knobs that connect weather to
## the foliage wind -- AtmosphereSystem pushes them into the shared shader
## include through the foliage_gust_scale / foliage_wind_scroll globals.
@export var cloudy_wind: Vector2 = Vector2(1.35, 1.3)
## Steady rain: noticeably windier than clear, well short of a storm.
@export var rain_wind: Vector2 = Vector2(1.5, 1.4)
## Storm: the grass flattens and gusts race across the field. Kept at 2.0:
## past that, short tufts bend further sideways than they are tall.
@export var storm_wind: Vector2 = Vector2(2.0, 1.9)
## Mist is still air: gusts die down.
@export var mist_wind: Vector2 = Vector2(0.5, 0.6)
## Horizontal speed, metres per second, that rain and motes drift at in the
## authored (clear-weather) wind. Multiplied by the current gust scale.
@export_range(0.0, 20.0, 0.1) var wind_drift_speed: float = 2.0

@export_group("Sky")
## Clouds scroll in the wind direction at this many noise tiles per second,
## times the current wind speed multiplier, so storms race and calm days crawl.
@export_range(0.0, 0.1, 0.001) var cloud_speed: float = 0.004
## Cloud cover in clear weather. Cloudy and rain raise it with intensity.
@export_range(0.0, 1.0) var clear_cloud_cover: float = 0.3
## How dark a full cloud shadow is on the ground, in sunlight. Shadows fade out
## as the sky closes over (under overcast there is nothing to contrast with)
## and at night.
@export_range(0.0, 1.0) var cloud_shadow_strength: float = 0.4
## High streaky cirrus in clear weather; it thins as the weather worsens.
@export_range(0.0, 1.0) var cirrus_amount: float = 0.55

@export_group("Ground")
## Seconds of full rain to soak the ground completely. Lighter rain soaks it
## only as far as its intensity.
@export_range(5.0, 600.0, 5.0) var wetting_seconds: float = 90.0
## Minutes to dry from soaked in full sun. Slower under cloud and at night.
@export_range(0.5, 60.0, 0.5) var drying_minutes: float = 5.0
## Wetness mist (and dawn mist) leaves behind, as dew, at full mist.
@export_range(0.0, 1.0) var dew_wetness: float = 0.3

@export_group("Mist")
## Mist that forms by itself around sunrise, 0..1 at its peak (about 06:20).
## 0 for locations that should never have it -- dry heath, high ground.
@export_range(0.0, 1.0) var dawn_mist: float = 0.7
## How far above the location's average ground height the mist layer reaches,
## metres. Hollows below that average fill thickest.
@export_range(0.5, 60.0, 0.5) var mist_depth: float = 6.0
## Metres at which full mist hides everything -- ABSOLUTE, not relative to the
## location's own haze, so clear-air locations get the same mist as a hazy
## meadow. The haze closes in from the location's weather haze to this as mist
## rises (AtmosphereHaze.apply()).
@export_range(80.0, 2000.0, 10.0) var mist_haze_distance: float = 320.0
## Godot height-fog density at full mist: how quickly fog thickens below the
## mist layer's top. Keep it small: Godot's height fog applies at ANY distance,
## so above ~0.03 the grass at your feet washes out as if seen through gauze.
## The distance boost above does the "far things vanish" part.
@export_range(0.0, 0.5, 0.001) var mist_height_density: float = 0.012

@export_group("Lightning")
## Lightning belongs to STORM weather only; RAIN never strikes. The storm's
## intensity is also how close it is: at low intensity it is a distant storm
## -- occasional far flashes and rumbles -- and at full it is overhead.
## Strikes per minute at full storm; a quarter of that at the lightest.
@export_range(0.0, 30.0, 0.5) var lightning_per_minute: float = 4.0
## Never two strikes closer together than this, seconds. Part of keeping the
## flashes photosensitivity-safe (see lightning_flash_scale).
@export_range(1.0, 60.0, 0.5) var lightning_min_gap: float = 4.0
## Strikes land this far away, metres. Distance sets the flash strength, the
## thunder delay (distance / 343 m/s) and near-crack vs far-rumble.
@export var lightning_distance: Vector2 = Vector2(400.0, 7000.0)
## Visual flash strength, 0..1. 0 keeps thunder but removes every flash --
## the accessibility setting for players sensitive to flashing light. Each
## strike is also shaped to stay under 3 flashes per second.
@export_range(0.0, 1.0) var lightning_flash_scale: float = 1.0
## Energy of the brief shadowless light a close strike throws on the scene.
@export_range(0.0, 10.0, 0.1) var lightning_light_energy: float = 3.0

@export_group("Audio")
@export var audio_enabled: bool = true
## Bed levels at full strength, dB. The beds cross-fade with the weather.
@export_range(-60.0, 6.0, 0.5) var rain_volume_db: float = -8.0
@export_range(-60.0, 6.0, 0.5) var wind_volume_db: float = -12.0
## Foliage rustle at full gust AND full local density (see WeatherAudio.
## advance()) -- quieter than the wind bed itself, since it layers on top
## rather than replacing it.
@export_range(-60.0, 6.0, 0.5) var rustle_volume_db: float = -16.0
## Water beds at full gain AND full proximity (see WeatherAudio.advance()
## and AtmosphereSystem._water_proximity()). Wind-roughened water sits above
## the calm bed -- water actually got louder, not just different -- but
## still under the wind bed itself.
@export_range(-60.0, 6.0, 0.5) var water_calm_volume_db: float = -14.0
@export_range(-60.0, 6.0, 0.5) var water_wind_volume_db: float = -10.0
@export_range(-60.0, 6.0, 0.5) var still_air_volume_db: float = -16.0
## A strike at the near end of lightning_distance; farther ones are quieter.
@export_range(-60.0, 6.0, 0.5) var thunder_volume_db: float = -2.0
## Inside (an INSIDE zone, or an indoor location) the whole weather mix is
## low-passed to this and turned down: heard through walls and a roof.
@export_range(200.0, 20000.0, 50.0) var indoor_cutoff_hz: float = 900.0
@export_range(-40.0, 0.0, 0.5) var indoor_volume_db: float = -10.0

@export_group("Particles")
## Rain streaks around the camera at full rain intensity.
@export_range(0, 20000, 100) var rain_drops: int = 6000
## Metres around the camera that rain fills.
@export_range(4.0, 60.0, 1.0) var rain_radius: float = 22.0
## Drifting motes (pollen, seed fluff, dust) in clear daylight. PlacesOS placed
## these by hand as dust volumes inside rooms; outdoors they follow the camera.
@export_range(0, 2000, 10) var motes: int = 220
@export_range(2.0, 40.0, 0.5) var mote_radius: float = 12.0
@export var mote_colour: Color = Color("#fff0cc")


## Gust scale and scroll-speed multiplier for a weather kind at `amount` 0..1.
func wind_multipliers(kind: Weather, amount: float) -> Vector2:
	match kind:
		Weather.CLOUDY:
			return Vector2.ONE.lerp(cloudy_wind, amount)
		Weather.RAIN:
			return Vector2.ONE.lerp(rain_wind, amount)
		Weather.MIST:
			return Vector2.ONE.lerp(mist_wind, amount)
		Weather.STORM:
			return Vector2.ONE.lerp(storm_wind, amount)
	return Vector2.ONE


func cloud_cover(kind: Weather, amount: float) -> float:
	match kind:
		Weather.CLOUDY:
			return lerpf(clear_cloud_cover, 0.78, amount)
		Weather.RAIN:
			return lerpf(clear_cloud_cover, 0.97, amount)
		Weather.STORM:
			return lerpf(clear_cloud_cover, 1.0, amount)
		Weather.MIST:
			# Hazy, not stormy: mist whitens the sky itself (fog_sky_affect)
			# rather than filling it with crisp cloud.
			return lerpf(clear_cloud_cover, 0.4, amount)
	return clear_cloud_cover
