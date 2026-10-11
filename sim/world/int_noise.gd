extends RefCounted
## Portable integer-hash noise for world generation. Pure 32-bit integer mixing,
## so a seed gives the same world on every engine version and platform, and no
## result depends on the order things were generated in.
const MASK := 0xFFFFFFFF

## 32-bit hash of a seed, two coordinates and a channel. Multipliers stay below
## 2^31 so every product fits in a 64-bit int before masking.
static func mix(seed_value: int, x: int, y: int, channel: int = 0) -> int:
	var h := (seed_value * 374761393 + x * 668265263 + y * 1274126177 + channel * 1103515245) & MASK
	h = ((h ^ (h >> 15)) * 1934705263) & MASK
	h = ((h ^ (h >> 13)) * 1274126177) & MASK
	return h ^ (h >> 16)

## Uniform in [0, 1).
static func unit(seed_value: int, x: int, y: int, channel: int = 0) -> float:
	return float(mix(seed_value, x, y, channel)) / 4294967296.0

## Smooth value noise in [0, 1] at a continuous point.
static func value(seed_value: int, channel: int, point: Vector2) -> float:
	var cell := Vector2i(floori(point.x), floori(point.y))
	var f := point - Vector2(cell)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := unit(seed_value, cell.x, cell.y, channel)
	var b := unit(seed_value, cell.x + 1, cell.y, channel)
	var c := unit(seed_value, cell.x, cell.y + 1, channel)
	var d := unit(seed_value, cell.x + 1, cell.y + 1, channel)
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

## Fractal sum of value noise, normalised to [0, 1].
static func fbm(seed_value: int, channel: int, point: Vector2, octaves: int = 4) -> float:
	var total := 0.0
	var amplitude := 1.0
	var norm := 0.0
	for octave in octaves:
		total += value(seed_value, channel + octave * 101, point) * amplitude
		norm += amplitude
		amplitude *= 0.5
		point *= 2.0
	return total / norm

## Ridged fractal noise in [0, 1]: sharp crests where the noise crosses 0.5.
static func ridge(seed_value: int, channel: int, point: Vector2, octaves: int = 3) -> float:
	var total := 0.0
	var amplitude := 1.0
	var norm := 0.0
	for octave in octaves:
		var crest := 1.0 - absf(value(seed_value, channel + octave * 101, point) * 2.0 - 1.0)
		total += crest * crest * amplitude
		norm += amplitude
		amplitude *= 0.5
		point *= 2.0
	return total / norm
