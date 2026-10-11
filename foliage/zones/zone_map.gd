class_name ZoneMap
extends RefCounted

## EnvironmentZones' inputs baked into a texture for the terrain shader, which
## cannot call GDScript. Replaces the old GroveMap.
##
## The shader recomputes zone weights from these inputs with the same formulas
## EnvironmentZones uses, rather than reading baked weights, because the cheap
## masks (slope rock, altitude, painted, site) are already evaluated per pixel
## there and a cover change then needs no re-bake.
##
## Channels:
##   R: raw grove noise, -1..1 mapped to 0..1 (TreePlacer.grove_noise()). The
##      shader applies GroveScatter.grove_value()'s remap and each family's
##      cover threshold, exactly as EnvironmentZones.families() does.
##   G, B, A: reserved for observed zone inputs (ESA WorldCover, OSM land use;
##      plan phase Z6). Not baked yet, so the image is single-channel.
##
## Baked with FastNoiseLite.get_image() (native, about 1 ms per 10,000 pixels)
## on a copy of the grove noise rescaled so one pixel covers
## `bounds.size / size` metres. At 1024 over the 12 km horizon area that is
## about 12 m a pixel: enough for 70 m groves seen from 600 m and further.

## Pixels across the near-range map over the playable world: 8 km at 2048 is
## about 4 m a pixel, fine enough for the woodland floor tint at head height.
const NEAR_SIZE := 2048


static func build(world_seed: int, bounds: Rect2, size: int = 1024) -> ImageTexture:
	var noise := TreePlacer.grove_noise(world_seed)
	var metres_per_pixel := bounds.size.x / float(size)
	# get_image() samples at pixel coordinates plus `offset`, at the noise's
	# frequency; scaling both maps pixels onto world metres. The extra half
	# pixel puts each sample at its pixel's centre, where the shader's
	# bilinear lookup reads it back -- without it the map sat half a pixel
	# (6 m at 1024) off the noise.
	noise.frequency *= metres_per_pixel
	noise.offset = Vector3(bounds.position.x, bounds.position.y, 0.0) / metres_per_pixel + Vector3(0.5, 0.5, 0.0)
	var image := noise.get_image(size, size, false, false, false)
	return ImageTexture.create_from_image(image)


## The R channel at a world XZ as a raw noise value (-1..1), read back the way
## the shader samples it (bilinear). For tests comparing map and sampler.
static func sample_noise(texture: ImageTexture, bounds: Rect2, x: float, z: float) -> float:
	var image := texture.get_image()
	var uv := (Vector2(x, z) - bounds.position) / bounds.size
	var p := uv * Vector2(image.get_size()) - Vector2(0.5, 0.5)
	var p0 := Vector2i(floori(p.x), floori(p.y))
	var t := p - Vector2(p0)
	var last := image.get_size() - Vector2i.ONE
	var c00 := image.get_pixel(clampi(p0.x, 0, last.x), clampi(p0.y, 0, last.y)).r
	var c10 := image.get_pixel(clampi(p0.x + 1, 0, last.x), clampi(p0.y, 0, last.y)).r
	var c01 := image.get_pixel(clampi(p0.x, 0, last.x), clampi(p0.y + 1, 0, last.y)).r
	var c11 := image.get_pixel(clampi(p0.x + 1, 0, last.x), clampi(p0.y + 1, 0, last.y)).r
	var r := lerpf(lerpf(c00, c10, t.x), lerpf(c01, c11, t.x), t.y)
	return r * 2.0 - 1.0
