class_name AtmosphereHaze
extends RefCounted

## Distance haze: Godot's depth fog, clear near the camera and thickening to
## the edge of the drawn ground, where it hides the end of the horizon ring.
##
## Replaced exponential fog after the October 2026 location review. Exponential
## fog front-loads its haze: at the old 0.0015 default it was 78% opaque at
## 1 km and 95% at 2 km, so Brienz's mountain walls and Buchenhain's fields
## faded to grey long before the 6-8 km of horizon ground that was being
## drawn. Depth fog ramps over the whole distance instead (on High, roughly 9%
## at 1 km, 27% at 2 km, 66% at 4 km), so the view keeps its depth cue without
## washing out. Neither fog mode costs anything measurable; the horizon ring is
## the real cost, and the haze now follows it per quality level.
##
## Most of the haze colour comes from the sky behind it (aerial perspective),
## so distant ridges fade into the horizon sky behind them rather than a flat
## grey band in front of it, and take the horizon's peach at dusk.

## Below 1 the haze gathers a little sooner than the smoothstep ramp alone,
## so middle distance (1-3 km) still reads as far away.
const CURVE := 0.85
## Mist pulls the curve further down: thick close in, not just at the end.
const MIST_CURVE := 0.6
## The haze never completes nearer than this, however close the world's edge.
const MIN_DISTANCE := 1500.0
## How far ground is drawn when there is no location to ask.
const FALLBACK_DISTANCE := 6000.0
## Share of the haze colour taken from the sky behind it.
const AERIAL_PERSPECTIVE := 0.85
## fog_sun_scatter at full glow: the warm bloom in the haze towards a low sun.
const SUN_SCATTER := 0.35


## Where the haze is complete, seen from `point`: how far ground is drawn
## there (FoliageLocation.drawn_ground_distance()), or FALLBACK_DISTANCE.
static func reach(location: FoliageLocation, point: Vector3) -> float:
	if location == null:
		return FALLBACK_DISTANCE
	return maxf(location.drawn_ground_distance(point), MIN_DISTANCE)


## Writes the haze into `env`.
##
## `amount` is the location's haze at the end of its reach, 0..1 (0 = none).
## `weather` multiplies the haze the way the weather's fog_scale always has:
## rain and storm (>1) pull the end in and thicken it; indoors (<1) thins it.
## `mist` 0..1 closes the haze in towards `mist_distance` metres, fully opaque.
## `glow` 0..1 is AtmosphereModel.Frame.haze_glow.
static func apply(env: Environment, colour: Color, amount: float, distance: float,
		weather: float = 1.0, mist: float = 0.0, mist_distance: float = 320.0,
		glow: float = 0.0) -> void:
	env.fog_enabled = amount > 0.0 or mist > 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = colour
	env.fog_aerial_perspective = AERIAL_PERSPECTIVE
	env.fog_sun_scatter = SUN_SCATTER * clampf(glow, 0.0, 1.0)
	var end := distance / maxf(weather, 0.01)
	var strength := minf(amount * weather, 1.0)
	if mist > 0.0 and mist_distance < end:
		# Geometric, so the haze closes in evenly as the mist thickens rather
		# than staying far off until the very end.
		end *= pow(mist_distance / end, mist)
	env.fog_depth_begin = 0.0
	env.fog_depth_end = end
	env.fog_depth_curve = lerpf(CURVE, MIST_CURVE, mist)
	# In depth mode fog_density is the haze's strength at fog_depth_end.
	env.fog_density = lerpf(strength, 1.0, mist)
