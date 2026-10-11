class_name SeaState
extends RefCounted

## The sea's live level (docs/SEA_PLAN.md, SEA1 and SEA3). Owned by
## FoliageLocation whenever its WaterProfile has a sea. Moving the level
## changes uniforms and the sea plane's height only -- never chunks, foliage
## or textures. Anything baked reads the fixed high-water design level instead
## (WaterProfile.sea_high_water()).
##
## Consumers of level_now:
##   - water.gdshader `water_sea_level_now`: the swell fade's depth, computed
##     against the bed-height map (ImportedSea.bed_texture(), WaterDepthMap).
##   - terrain.gdshader `terrain_water_level`: the submerged and damp bands.
##   - WaterLayer.follow(): the sea plane's Y.
##
## With a tide it also keeps `history` for the terrain's wet-sand memory
## (SEA4): history[k] is the highest level over the last k * HISTORY_STEP
## hours (history[0] = level_now), so the shader can tell how long ago the
## ground at a given height was last covered. hours_since_covered() is the
## shader's formula, for tests.
##
## Storm surge (SEA8): in a storm the sea stands higher -- the low pressure
## lifts it (WaterProfile.surge_pressure, the inverse barometer) and an
## onshore wind piles it against the coast (surge_wind, times `onshore`: the
## wind's direction against the coast field's, -1 offshore .. 1 onshore).
## FoliageLocation sets the storm (AtmosphereModel.Frame.storm) every frame;
## the surge eases towards its target at surge_rate.
##
## level_now = sea_level + tide + surge + offset. The tide comes from the manifest's
## baked constituents (TidePredictor) at the destination's date and the
## atmosphere's clock; without a tide entry it is 0. `offset` is 0 except
## while a test or debug key shifts the level.
##
## The clock: `time_of_day` is local mean solar time at the location, so UTC
## = hour - longitude / 15 (docs/ATMOSPHERE.md). The hour wraps at midnight
## but the date is fixed per destination, so set_clock() unwraps it: running
## or scrubbing past midnight carries on into the next (or previous) day
## instead of jumping the tide back a day.

## Smallest level change pushed to the shaders and the sea plane, metres.
const PUSH_STEP := 0.01
## Wet-sand memory (SEA4): the history's length and spacing (4 h back), the
## grid its tide samples are cached on, and how often the clock alone (with
## the level near still, around slack water) refreshes it.
const HISTORY_SIZE := 9
const HISTORY_STEP := 0.5
const HISTORY_GRID := 0.25
const HISTORY_REFRESH := 0.1

var profile: WaterProfile
var predictor: TidePredictor
var year: int = 2026
var day_of_year: int = 196
## Metres added on top of the tide; tests and debugging only.
var offset: float = 0.0
var level_now: float = 0.0
## The storm surge now and where it is heading, metres; `onshore` as above.
var surge: float = 0.0
var surge_target: float = 0.0
var onshore: float = 0.0
## The tide alone (metres about mean sea level) at the current clock.
var tide_now: float = 0.0
var _hour: float = NAN
var _hours := 0.0
var _extremes := {}
var _extremes_hours: float = NAN
## Running maximum of the level, HISTORY_STEP hours apart; see the class doc.
var history := PackedFloat32Array()
## Tide heights on the HISTORY_GRID, by grid index, for the history window.
var _grid := {}
var _history_hours: float = NAN


func _init(water: WaterProfile, tide: TidePredictor = null) -> void:
	profile = water
	predictor = tide
	level_now = water.sea_level
	history.resize(HISTORY_SIZE)
	history.fill(level_now)


func has_tide() -> bool:
	return predictor != null


## Follows the location's clock (hours, wrapping at 24). True when it moved.
func set_clock(hour: float) -> bool:
	if is_nan(_hour):
		_hour = hour
		_hours = hour
		return true
	var step := fposmod(hour - _hour + 12.0, 24.0) - 12.0
	_hour = hour
	_hours += step
	return step != 0.0


## The date changed: the clock restarts on it at the current hour.
func set_date(new_year: int, new_day: int) -> void:
	year = new_year
	day_of_year = new_day
	if not is_nan(_hour):
		_hours = _hour


## UTC Modified Julian Day of the current clock.
func utc_mjd() -> float:
	var hours := (0.0 if is_nan(_hour) else _hours)
	var longitude := predictor.longitude if predictor != null else 0.0
	return start_of_year_mjd(year) + float(day_of_year - 1) + (hours - longitude / 15.0) / 24.0


static func start_of_year_mjd(y: int) -> float:
	return 40587.0 + Time.get_unix_time_from_datetime_dict({"year": y, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}) / 86400.0


## Recomputes level_now. True when it moved by PUSH_STEP or more (or
## `force`, or the wet-sand history is HISTORY_REFRESH hours old), and so
## needs apply().
func update(force: bool = false) -> bool:
	tide_now = predictor.height(utc_mjd()) if predictor != null else 0.0
	var level := profile.sea_level + tide_now + surge + offset
	var stale := predictor != null and not is_nan(_hour) and (is_nan(_history_hours) or absf(_hours - _history_hours) >= HISTORY_REFRESH)
	if not force and not stale and absf(level - level_now) < PUSH_STEP:
		return false
	level_now = level
	_update_history()
	return true


## history[] for the current clock: tide samples on a fixed HISTORY_GRID
## (cached, so each refresh costs about one new prediction), each counted
## from the first history step whose window reaches back to it, then made a
## running maximum. Peaks between grid samples are missed by at most a few
## centimetres.
func _update_history() -> void:
	history.fill(level_now)
	if predictor == null or is_nan(_hour):
		return
	_history_hours = _hours
	var base := profile.sea_level + surge + offset
	var now := utc_mjd()
	var step := HISTORY_GRID / 24.0
	var newest := floori(now / step)
	var span := ceili(float(HISTORY_SIZE - 1) * HISTORY_STEP / HISTORY_GRID)
	var kept := {}
	for j in range(newest, newest - span - 1, -1):
		var h: float = _grid[j] if _grid.has(j) else predictor.height(float(j) * step)
		kept[j] = h
		var k := maxi(ceili((now - float(j) * step) * 24.0 / HISTORY_STEP - 1e-6), 1)
		if k < HISTORY_SIZE:
			history[k] = maxf(history[k], base + h)
	_grid = kept
	for k in range(1, HISTORY_SIZE):
		history[k] = maxf(history[k], history[k - 1])


## Hours since ground at height `y` was last under the sea: 0 when it is
## now, interpolated through history[], INF if not within the window.
## terrain.gdshader's tide_hours_since_covered(), for tests.
func hours_since_covered(y: float) -> float:
	var prev := history[0]
	if y <= prev:
		return 0.0
	for k in range(1, HISTORY_SIZE):
		var m := history[k]
		if m >= y:
			return (float(k - 1) + (y - prev) / maxf(m - prev, 0.0001)) * HISTORY_STEP
		prev = m
	return INF


## The storm (0..1) drives the surge's target; True when the surge moved
## enough that the level needs update() and apply().
func advance_surge(storm: float, delta: float) -> bool:
	surge_target = clampf(storm, 0.0, 1.0) * (profile.surge_pressure + profile.surge_wind * onshore)
	if is_equal_approx(surge, surge_target):
		return false
	var before := surge
	surge = move_toward(surge, surge_target, profile.surge_rate * delta)
	return absf(surge - before) > 0.0


## Pushes level_now everywhere it is drawn. Cheap: two uniforms and a node
## position.
func apply(water: WaterLayer, terrain_material: ShaderMaterial) -> void:
	if water != null:
		water.sea_level_now = level_now
		if water.material != null:
			water.material.set_shader_parameter("water_sea_level_now", level_now)
		water.follow(water.focus_point)
	if terrain_material != null:
		profile.apply_to_terrain_material(terrain_material, level_now)
		terrain_material.set_shader_parameter("terrain_sea_tidal", predictor != null)
		terrain_material.set_shader_parameter("terrain_tide_history", history.duplicate())
		terrain_material.set_shader_parameter("terrain_tide_history_step", HISTORY_STEP)


## Rising or falling, and the next high and low water, for the commands
## panel. Cached until the clock moves a tenth of an hour.
func status_line() -> String:
	if predictor == null or is_nan(_hour):
		return "surge %+.2f m" % surge if absf(surge) >= 0.01 else ""
	if is_nan(_extremes_hours) or absf(_hours - _extremes_hours) > 0.1:
		_extremes = predictor.next_extremes(utc_mjd())
		_extremes_hours = _hours
	var rising: bool = _extremes.has("high") and (not _extremes.has("low") or _extremes.high[0] < _extremes.low[0])
	var parts := ["tide: %+.2f m %s" % [tide_now, "rising" if rising else "falling"]]
	if absf(surge) >= 0.01:
		parts.append("surge %+.2f m" % surge)
	for kind in ["high", "low"]:
		if _extremes.has(kind):
			parts.append("%s water %s (%+.2f m)" % [kind, _clock_label(_extremes[kind][0]), _extremes[kind][1]])
	return "    ".join(parts)


## A UTC MJD as the location's solar clock time, "+1d" if not today.
func _clock_label(mjd: float) -> String:
	var hours := (mjd - utc_mjd()) * 24.0 + _hour
	var day := floori(hours / 24.0)
	var h := fposmod(hours, 24.0)
	var label := "%02d:%02d" % [int(h), int(fposmod(h * 60.0, 60.0))]
	return label + ("" if day == 0 else " %+dd" % day)
