class_name TidePredictor
extends RefCounted

## The tide from a manifest's baked constituents (sea.tide,
## tools/geo/import_tides.py; docs/SEA_PLAN.md, SEA3). A port of that tool's
## predict(), which matches pyTMD's FES-corrected prediction:
##
##   h(t) = sum f * A * cos(G + u - g)   metres about mean sea level
##
## G is each constituent's Doodson coefficients dotted with (tau, s, h, p,
## N, p_s, 90): mean lunar time and the mean longitudes of the Moon, Sun,
## lunar perigee, lunar node and solar perigee, in degrees. f and u, the nodal
## factor and angle, change over the 18.6-year node cycle; they are
## recomputed once per day (under 0.1 mm of error). Time is UTC as a Modified
## Julian Day; the arguments use TT (UTC + tt_minus_ut1_s).

const MJD_J2000 := 51544.5
const NODAL_KEYS := ["none", "m2", "m4", "o1", "j1", "oo1", "k1", "k2", "mf", "mm", "l2", "l2b", "eta2"]

var model: String
## Destination longitude (degrees east), for SeaState's solar-time clock.
var longitude: float = 0.0
## LAT, MLWS, MSL, MHWS, HAT about mean sea level, metres.
var levels: Dictionary = {}
var tt_minus_ut1_days: float = 0.0
var _amplitude := PackedFloat64Array()
var _phase := PackedFloat64Array()  # radians
var _doodson: Array[PackedFloat64Array] = []
var _nodal: PackedInt32Array = PackedInt32Array()
var _f := PackedFloat64Array()
var _u := PackedFloat64Array()
var _nodal_day: float = NAN


## Validates a manifest's sea.tide entry. Null (with an error) if malformed.
static func from_entry(tide: Variant) -> TidePredictor:
	if not tide is Dictionary or not tide.get("constituents") is Array or (tide.constituents as Array).is_empty():
		push_error("TidePredictor: sea.tide needs a constituents list")
		return null
	var p := TidePredictor.new()
	p.model = str(tide.get("model", ""))
	var dt: Variant = tide.get("tt_minus_ut1_s", 69.2)
	if not (dt is float or dt is int) or absf(float(dt)) > 200.0:
		push_error("TidePredictor: bad tt_minus_ut1_s")
		return null
	p.tt_minus_ut1_days = float(dt) / 86400.0
	for c: Variant in tide.constituents:
		if not c is Dictionary:
			push_error("TidePredictor: constituent is not an object")
			return null
		var amp: Variant = c.get("amplitude_m")
		var phase: Variant = c.get("phase_deg")
		var doodson: Variant = c.get("doodson")
		var key := NODAL_KEYS.find(str(c.get("nodal", "")))
		if not (amp is float or amp is int) or float(amp) < 0.0 or float(amp) > 20.0 \
				or not (phase is float or phase is int) or not is_finite(float(phase)) \
				or not doodson is Array or (doodson as Array).size() != 7 or key < 0:
			push_error("TidePredictor: malformed constituent %s" % str(c.get("name", "?")))
			return null
		var row := PackedFloat64Array()
		for v: Variant in doodson:
			if not (v is float or v is int):
				push_error("TidePredictor: non-numeric Doodson coefficient in %s" % str(c.get("name", "?")))
				return null
			row.append(float(v))
		p._amplitude.append(float(amp))
		p._phase.append(deg_to_rad(float(phase)))
		p._doodson.append(row)
		p._nodal.append(key)
	var lv: Variant = tide.get("levels", {})
	if lv is Dictionary:
		for name in ["lat", "mlws", "msl", "mhws", "hat"]:
			if lv.get(name) is float or lv.get(name) is int:
				p.levels[name] = float(lv[name])
	p._f.resize(p._amplitude.size())
	p._u.resize(p._amplitude.size())
	return p


func constituent_count() -> int:
	return _amplitude.size()


## Tide height (metres about mean sea level) at UTC Modified Julian Day `mjd`.
func height(mjd: float) -> float:
	var ml := mean_longitudes(mjd + tt_minus_ut1_days)
	var s: float = ml[0]
	var h: float = ml[1]
	var tau := 360.0 * fposmod(mjd, 1.0) - s + h
	var args := PackedFloat64Array([tau, s, h, ml[2], ml[3], ml[4], 90.0])
	var day := floorf(mjd)
	if day != _nodal_day:
		_update_nodal(ml[2], ml[3])
		_nodal_day = day
	var total := 0.0
	for i in _amplitude.size():
		var row := _doodson[i]
		var g := 0.0
		for k in 7:
			g += row[k] * args[k]
		total += _f[i] * _amplitude[i] * cos(deg_to_rad(g) - _phase[i] + _u[i])
	return total


## The next high and low water after `mjd`: {"high": [mjd, metres],
## "low": [mjd, metres]}, searched over the next 30 hours in 6-minute steps
## and refined by a parabola through the turning point.
func next_extremes(mjd: float) -> Dictionary:
	const STEP := 6.0 / 1440.0
	var out := {}
	var a := height(mjd)
	var b := height(mjd + STEP)
	var t := mjd + STEP
	for i in 300:
		var c := height(t + STEP)
		var kind := ""
		if b >= a and b > c:
			kind = "high"
		elif b <= a and b < c:
			kind = "low"
		if not kind.is_empty() and not out.has(kind):
			var denom := a - 2.0 * b + c
			var shift := 0.5 * (a - c) / denom if absf(denom) > 1e-12 else 0.0
			var at := t + shift * STEP
			out[kind] = [at, height(at)]
			if out.size() == 2:
				break
		a = b
		b = c
		t += STEP
	return out


func _update_nodal(p_deg: float, n_deg: float) -> void:
	var sch := schureman(p_deg, n_deg)
	for i in _amplitude.size():
		var fu := nodal(_nodal[i], sch)
		_f[i] = fu.x
		_u[i] = fu.y


## (s, h, p, N, p_s) in degrees at Modified Julian Day `mjd` (TT): the ASTRO5
## polynomials.
static func mean_longitudes(mjd: float) -> PackedFloat64Array:
	var T := (mjd - MJD_J2000) / 36525.0
	var s := _poly([218.3164477, 481267.88123421, -1.5786e-3, 1.855835e-6, -1.53388e-8], T)
	var elongation := _poly([297.8501921, 445267.1114034, -1.8819e-3, 1.83195e-6, -8.8445e-9], T)
	var h := s - elongation
	var p := _poly([83.3532465, 4069.0137287, -1.032e-2, -1.249172e-5], T)
	var n := _poly([125.04452, -1934.136261, 2.0708e-3, 2.22222e-6], T)
	var ps := 282.94 + 1.7192 * T
	return PackedFloat64Array([fposmod(s, 360.0), fposmod(h, 360.0), fposmod(p, 360.0), fposmod(n, 360.0), fposmod(ps, 360.0)])


static func _poly(c: Array, T: float) -> float:
	var total := 0.0
	var power := 1.0
	for k: float in c:
		total += k * power
		power *= T
	return total


## Schureman's lunar-orbit terms: I, xi, nu, nu', nu'' (radians), Ra (a
## factor), Ru (radians) and N (radians).
static func schureman(p_deg: float, n_deg: float) -> Dictionary:
	var P := deg_to_rad(p_deg)
	var N := deg_to_rad(n_deg)
	var I := acos(0.913694997 - 0.035692561 * cos(N))
	var at1 := atan(1.01883 * tan(N / 2.0))
	var at2 := atan(0.64412 * tan(N / 2.0))
	var xi := -at1 - at2 + N
	xi = atan2(sin(xi), cos(xi))
	var nu := at1 - at2
	var pp := P - xi
	var t2 := tan(I / 2.0)
	var Ru := atan(sin(2.0 * pp) / (1.0 / (t2 * t2) / 6.0 - cos(2.0 * pp)))
	var Ra := pow(1.0 - 12.0 * t2 * t2 * cos(2.0 * pp) + 36.0 * pow(t2, 4.0), -0.5)
	var nu_p := atan(sin(2.0 * I) * sin(nu) / (sin(2.0 * I) * cos(nu) + 0.3347))
	var nu_s := 0.5 * atan(sin(I) * sin(I) * sin(2.0 * nu) / (sin(I) * sin(I) * cos(2.0 * nu) + 0.0727))
	return {"I": I, "xi": xi, "nu": nu, "nu_p": nu_p, "nu_s": nu_s, "Ra": Ra, "Ru": Ru, "N": N}


## (f, u radians) for a nodal key index into NODAL_KEYS: FES's scheme.
static func nodal(key: int, a: Dictionary) -> Vector2:
	var I: float = a.I
	var xi: float = a.xi
	var nu: float = a.nu
	match NODAL_KEYS[key]:
		"none":
			return Vector2(1.0, 0.0)
		"m2":
			return Vector2(pow(cos(I / 2.0), 4.0) / 0.9154, 2.0 * xi - 2.0 * nu)
		"m4":
			var m2 := nodal(1, a)
			return Vector2(m2.x * m2.x, 2.0 * m2.y)
		"o1":
			return Vector2(sin(I) * pow(cos(I / 2.0), 2.0) / 0.38, 2.0 * xi - nu)
		"j1":
			return Vector2(sin(2.0 * I) / 0.7214, -nu)
		"oo1":
			return Vector2(sin(I) * pow(sin(I / 2.0), 2.0) / 0.01640, -2.0 * xi - nu)
		"k1":
			return Vector2(sqrt(0.8965 * pow(sin(2.0 * I), 2.0) + 0.6001 * sin(2.0 * I) * cos(nu) + 0.1006), -float(a.nu_p))
		"k2":
			return Vector2(sqrt(19.0444 * pow(sin(I), 4.0) + 2.7702 * pow(sin(I), 2.0) * cos(2.0 * nu) + 0.0981), -2.0 * float(a.nu_s))
		"mf":
			return Vector2(pow(sin(I), 2.0) / 0.1578, -2.0 * xi)
		"mm":
			return Vector2((2.0 / 3.0 - pow(sin(I), 2.0)) / 0.5021, 0.0)
		"l2":
			var m2 := nodal(1, a)
			return Vector2(m2.x / float(a.Ra), m2.y - float(a.Ru))
		"l2b":
			var N: float = a.N
			return Vector2(Vector2(1.0 + 0.441 * cos(N), 0.441 * sin(N)).length(), atan2(-0.441 * sin(N), 1.0 + 0.441 * cos(N)))
		"eta2":
			return Vector2(pow(sin(I), 2.0) / 0.1565, -2.0 * nu)
	return Vector2(1.0, 0.0)
