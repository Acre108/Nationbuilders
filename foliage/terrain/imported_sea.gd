class_name ImportedSea
extends RefCounted

## A real coastline (tools/geo/import_sea.py): where the sea is, the inferred
## seabed under it, and GLO-30 ground out past the world's edge, over a crop
## wider than the world (24 km by default) so the sea reaches the horizon.
##
## The sea plane alone floods every point below WaterProfile.sea_level; this
## is what keeps ground below sea level behind the shore (polders) dry. Its
## `reach` gates the sea plane (water.gdshader), the terrain's shore band
## (terrain.gdshader) and the growth mask (HeightmapTerrainProvider). See
## docs/WATER.md, *Real coastlines*.
##
## Sidecars from SEA5 on add a coast field (docs/SEA_PLAN.md, SEA5): the
## signed distance to the mean-sea-level shoreline and the direction surf
## travels, which coast_texture() hands to the water and terrain shaders.
## Older three-plane sidecars still load, with no coast field and so no surf.
##
## SEA6 adds an optional near grid (tools/geo/sea_detail.py): the sea at
## 10 m over the world and a margin, from OSM's coastline, ETOPO bathymetry,
## mapped beaches and groynes. Its `bed` replaces the ground by `weight`
## (near_shape()), and its `reach` replaces the coarse reach, both fading
## back to the 50 m planes over the last NEAR_FADE metres of the grid.
##
## Both grids may carry a `spill` plane (SEA6): the lowest sea level that
## reaches each cell over the ground in between. The sea draws, and its
## shore band and the growth mask flood, only where the level is above it,
## so a hollow behind a beach crest stays dry until the tide tops the crest.
## Without one the sea floods all its reach below the level, as before.
##
## Planes are stored with row 0 at the crop's -Z edge whatever the location's
## north_axis, so a world (x, z) maps to (x + half, z + half) / extent here and
## in the shaders alike.

## Local height of mean sea level (the manifest's sea.level).
var level: float = 0.0
var extent: float = 0.0
var _resolution: int = 0
var _ground := PackedFloat32Array()
var _seabed := PackedFloat32Array()
var _reach := PackedFloat32Array()
## The coast field, interleaved: per cell (distance, east, north) -- as
## coast_texture holds it. North becomes world Z by coast_z_sign: -1 where
## north is -Z, +1 on legacy +Z worlds (the shaders apply it too).
var _coast_rgb := PackedFloat32Array()
var coast_z_sign: float = -1.0
var _spill := PackedFloat32Array()
var _near_spill := PackedFloat32Array()
## The near grid (SEA6); empty without one.
var near_extent: float = 0.0
var _near_n: int = 0
var _near_bed := PackedFloat32Array()
var _near_weight := PackedFloat32Array()
var _near_reach := PackedFloat32Array()
## R: the near grid's reach, laid out like near_bounds(). Null without one.
## R float: the near grid's reach, and its spill heights, laid out like
## near_bounds(). Null without a near grid (or spill plane).
var near_reach_texture: ImageTexture
var near_spill_texture: ImageTexture
## R float: the reach, and the spill heights (null without a spill plane).
## Separate textures, made straight from the planes' bytes: interleaving
## them value by value cost tens of milliseconds a load.
var reach_texture: ImageTexture
var spill_texture: ImageTexture
## RGB float, laid out like bounds(): R the signed distance to the shoreline
## (metres, + offshore), G and B the direction surf travels (towards the
## shore) as east and north -- world Z is north times coast_z_sign. Null for
## a sidecar without a coast field.
var coast_texture: ImageTexture
## The baked tide (sea.tide, tools/geo/import_tides.py), or null: the sea
## then stays at mean sea level.
var tide: TidePredictor

const BASE_PLANES: Array[String] = ["ground", "seabed", "reach"]
const COAST_PLANES: Array[String] = ["coast", "coast_east", "coast_north"]
const SPILL_PLANES: Array[String] = ["spill"]
const NEAR_PLANES: Array[String] = ["bed", "weight", "reach"]
## Spill heights for a grid without a spill plane: everything in reach floods.
const SPILL_ALWAYS := -10000.0
## The near grid hands back to the 50 m planes over its last this many metres.
const NEAR_FADE := 100.0
const MAX_RESOLUTION := 4096


static func load_file(path: String, entry: Dictionary, world_size: float, north_axis: String) -> ImportedSea:
	var extent_value: Variant = entry.get("extent")
	var resolution: Variant = entry.get("resolution")
	if not (extent_value is float or extent_value is int) or float(extent_value) < world_size \
			or not (resolution is float or resolution is int) or int(resolution) < 2 or int(resolution) > MAX_RESOLUTION \
			or not (entry.get("planes") == BASE_PLANES or entry.get("planes") == BASE_PLANES + COAST_PLANES
				or entry.get("planes") == BASE_PLANES + COAST_PLANES + SPILL_PLANES):
		push_error("ImportedSea: invalid sea entry for " + path)
		return null
	var names: Array = entry.planes
	var planes: int = names.size()
	var n := int(resolution)
	# "f32" (older .r32 sidecars): every plane float32. "f16_u8"
	# (tools/geo/import_sea.py, SIDECAR_ENCODING): half floats, the reach as
	# bytes.
	var encoding := str(entry.get("encoding", "f32"))
	if not encoding in ["f32", "f16_u8"]:
		push_error("ImportedSea: unknown sea encoding " + encoding)
		return null
	var plane := n * n
	# Per plane, in file order, its byte size; in the packed encoding the
	# coast field's three planes are one interleaved RGB half-float block.
	var packed := encoding == "f16_u8"
	var sizes: Array[int] = []
	var labels: Array[String] = []
	var i := 0
	while i < planes:
		if packed and i == 3 and planes >= 6:
			sizes.append(plane * 6)
			labels.append("coast_field")
			i += 3
			continue
		sizes.append(plane * (4 if not packed else (1 if names[i] == "reach" else 2)))
		labels.append(names[i])
		i += 1
	var body := 0
	for size in sizes:
		body += size
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ImportedSea: cannot open " + path)
		return null
	if file.get_length() != 8 + body or file.get_32() != n or file.get_32() != n:
		push_error("ImportedSea: %s is not a %dx%d %d-plane grid" % [path, n, n, planes])
		file.close()
		return null
	var bytes := file.get_buffer(body)
	file.close()
	var read := {}
	var coast_image: Image = null
	var at := 0
	for k in labels.size():
		var chunk := bytes.slice(at, at + sizes[k])
		at += sizes[k]
		var label := labels[k]
		var values: PackedFloat32Array
		if label == "coast_field":
			coast_image = Image.create_from_data(n, n, false, Image.FORMAT_RGBH, chunk)
			coast_image.convert(Image.FORMAT_RGBF)
			values = coast_image.get_data().to_float32_array()
		elif not packed:
			values = chunk.to_float32_array()
		else:
			values = _decode(chunk, Image.FORMAT_L8 if label == "reach" else Image.FORMAT_RH, n)
		read[label] = values
		# Bytes cannot hold a non-finite value; floats (and half floats) can.
		if label != "reach" or not packed:
			for v in values:
				if not is_finite(v):
					push_error("ImportedSea: %s contains a non-finite sample" % path)
					return null
	var sea := ImportedSea.new()
	if entry.has("tide"):
		sea.tide = TidePredictor.from_entry(entry.tide)
		if sea.tide == null:
			push_error("ImportedSea: invalid sea.tide in the manifest for " + path)
			return null
	sea.extent = float(extent_value)
	sea.level = float(entry.get("level", 0.0))
	sea._resolution = n
	sea._ground = sea._oriented(read.ground, north_axis)
	sea._seabed = sea._oriented(read.seabed, north_axis)
	sea._reach = sea._oriented(read.reach, north_axis)
	if read.has("spill"):
		sea._spill = sea._oriented(read.spill, north_axis)
	sea.reach_texture = _plane_texture(n, sea._reach)
	sea.spill_texture = _plane_texture(n, sea._spill) if not sea._spill.is_empty() else null
	sea.coast_z_sign = -1.0 if north_axis == "-Z" else 1.0
	if coast_image == null and read.has("coast"):
		# An older float32 sidecar: interleave its three planes.
		var texels := PackedFloat32Array()
		texels.resize(plane * 3)
		var coast: PackedFloat32Array = read.coast
		var east: PackedFloat32Array = read.coast_east
		var north: PackedFloat32Array = read.coast_north
		for c in plane:
			texels[c * 3] = coast[c]
			texels[c * 3 + 1] = east[c]
			texels[c * 3 + 2] = north[c]
		coast_image = Image.create_from_data(n, n, false, Image.FORMAT_RGBF, texels.to_byte_array())
	if coast_image != null:
		# Raw rows run north to south; legacy +Z-north worlds flip them.
		if north_axis != "-Z":
			coast_image.flip_y()
		sea._coast_rgb = coast_image.get_data().to_float32_array()
		sea.coast_texture = ImageTexture.create_from_image(coast_image)
	if entry.has("near") and not sea._load_near(path.get_base_dir(), entry.near, world_size, north_axis):
		return null
	return sea


func _load_near(dir: String, near: Variant, world_size: float, north_axis: String) -> bool:
	var extent_value: Variant = near.get("extent") if near is Dictionary else null
	var resolution: Variant = near.get("resolution") if near is Dictionary else null
	var file_name: Variant = near.get("path") if near is Dictionary else null
	if not (extent_value is float or extent_value is int) or float(extent_value) < world_size or float(extent_value) > extent \
			or not (resolution is float or resolution is int) or int(resolution) < 2 or int(resolution) > MAX_RESOLUTION \
			or not file_name is String or (file_name as String).get_file() != file_name or (file_name as String).is_empty() \
			or not (near.get("planes") == NEAR_PLANES or near.get("planes") == NEAR_PLANES + SPILL_PLANES):
		push_error("ImportedSea: invalid sea.near entry")
		return false
	var n := int(resolution)
	var planes: int = (near.planes as Array).size()
	# "f32": every plane float32. "f16_u8" (tools/geo/sea_detail.py,
	# NEAR_ENCODING): bed and spill half floats, weight and reach bytes.
	var encoding := str(near.get("encoding", "f32"))
	if not encoding in ["f32", "f16_u8"] or (encoding == "f16_u8" and planes != 4):
		push_error("ImportedSea: unknown sea.near encoding " + encoding)
		return false
	var plane := n * n
	var body := plane * planes * 4 if encoding == "f32" else plane * 6
	var path := dir.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ImportedSea: cannot open " + path)
		return false
	if file.get_length() != 8 + body or file.get_32() != n or file.get_32() != n:
		push_error("ImportedSea: %s is not a %dx%d near grid" % [path, n, n])
		file.close()
		return false
	var bytes := file.get_buffer(body)
	file.close()
	var bed: PackedFloat32Array
	var weight: PackedFloat32Array
	var reach_plane: PackedFloat32Array
	var spill_plane := PackedFloat32Array()
	if encoding == "f32":
		var values := bytes.to_float32_array()
		bed = values.slice(0, plane)
		weight = values.slice(plane, plane * 2)
		reach_plane = values.slice(plane * 2, plane * 3)
		if planes == 4:
			spill_plane = values.slice(plane * 3, plane * 4)
	else:
		bed = _decode(bytes.slice(0, plane * 2), Image.FORMAT_RH, n)
		weight = _decode(bytes.slice(plane * 2, plane * 3), Image.FORMAT_L8, n)
		reach_plane = _decode(bytes.slice(plane * 3, plane * 4), Image.FORMAT_L8, n)
		spill_plane = _decode(bytes.slice(plane * 4, plane * 6), Image.FORMAT_RH, n)
	# Bytes cannot hold a non-finite value; floats (and half floats) can.
	for values in ([bed, weight, reach_plane, spill_plane] if encoding == "f32" else [bed, spill_plane]):
		for v in values:
			if not is_finite(v):
				push_error("ImportedSea: %s contains a non-finite sample" % path)
				return false
	_near_n = n
	near_extent = float(extent_value)
	_near_bed = _oriented_n(bed, north_axis, n)
	_near_weight = _oriented_n(weight, north_axis, n)
	_near_reach = _oriented_n(reach_plane, north_axis, n)
	if not spill_plane.is_empty():
		_near_spill = _oriented_n(spill_plane, north_axis, n)
	near_reach_texture = _plane_texture(n, _near_reach)
	near_spill_texture = _plane_texture(n, _near_spill) if not _near_spill.is_empty() else null
	return true


## An n x n plane of half floats (FORMAT_RH) or bytes (FORMAT_L8, read as
## 0..1) as float32, converted natively rather than value by value.
static func _decode(bytes: PackedByteArray, format: Image.Format, n: int) -> PackedFloat32Array:
	var image := Image.create_from_data(n, n, false, format, bytes)
	image.convert(Image.FORMAT_RF)
	return image.get_data().to_float32_array()


## An n x n float plane as an R float texture, straight from its bytes.
static func _plane_texture(n: int, plane: PackedFloat32Array) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RF, plane.to_byte_array()))


## The lowest sea level that reaches (x, z): the near grid's where it has
## the say, else the sidecar's; SPILL_ALWAYS without a spill plane.
func spill(x: float, z: float) -> float:
	if near_cover(x, z) >= 0.5:
		return _sample_n(_near_spill, _near_n, near_extent, x, z) if not _near_spill.is_empty() else SPILL_ALWAYS
	return _sample(_spill, x, z) if not _spill.is_empty() else SPILL_ALWAYS


func has_near() -> bool:
	return _near_n > 0


## World XZ rectangle (x, z, width, depth) of the near grid, for shaders.
func near_bounds() -> Vector4:
	var half := near_extent * 0.5
	return Vector4(-half, -half, near_extent, near_extent)


## 0..1: how much the near grid has the say here (1 well inside it, fading
## to 0 over its last NEAR_FADE metres).
func near_cover(x: float, z: float) -> float:
	if _near_n == 0:
		return 0.0
	return clampf((near_extent * 0.5 - maxf(absf(x), absf(z))) / NEAR_FADE, 0.0, 1.0)


## (bed, weight) from the near grid: the bed height and how far it replaces
## the ground, weight already faded by near_cover().
func near_shape(x: float, z: float) -> Vector2:
	var cover := near_cover(x, z)
	if cover <= 0.0:
		return Vector2.ZERO
	return Vector2(_sample_n(_near_bed, _near_n, near_extent, x, z), _sample_n(_near_weight, _near_n, near_extent, x, z) * cover)


func has_coast() -> bool:
	return not _coast_rgb.is_empty()


## Signed distance (metres, + offshore) to the mean-sea-level shoreline; 0
## without a coast field.
func coast_distance(x: float, z: float) -> float:
	return _sample_rgb(0, x, z) if not _coast_rgb.is_empty() else 0.0


## The world XZ direction surf travels here (towards the shore at sea,
## inland on land), unit length; zero without a coast field.
func coast_direction(x: float, z: float) -> Vector2:
	if _coast_rgb.is_empty():
		return Vector2.ZERO
	var d := Vector2(_sample_rgb(1, x, z), _sample_rgb(2, x, z) * coast_z_sign)
	return d.normalized() if d.length_squared() > 1e-8 else Vector2.ZERO


## Raw rows run north to south; legacy +Z-north worlds need them reversed.
func _oriented(plane: PackedFloat32Array, north_axis: String) -> PackedFloat32Array:
	return _oriented_n(plane, north_axis, _resolution)


func _oriented_n(plane: PackedFloat32Array, north_axis: String, n: int) -> PackedFloat32Array:
	if north_axis == "-Z":
		return plane
	var flipped := PackedFloat32Array()
	flipped.resize(plane.size())
	for row in n:
		for col in n:
			flipped[(n - 1 - row) * n + col] = plane[row * n + col]
	return flipped


## World XZ rectangle (x, z, width, depth) the planes cover, for shaders.
func bounds() -> Vector4:
	var half := extent * 0.5
	return Vector4(-half, -half, extent, extent)


func ground(x: float, z: float) -> float:
	return _sample(_ground, x, z)


## Metres to lower the ground here (<= 0; 0 on land).
func seabed(x: float, z: float) -> float:
	return _sample(_seabed, x, z)


## 0..1: how far the sea may reach here (1 on the sea, 0 inland): the near
## grid's where it has the say.
func reach(x: float, z: float) -> float:
	var coarse := _sample(_reach, x, z)
	var cover := near_cover(x, z)
	if cover <= 0.0:
		return coarse
	return lerpf(coarse, _sample_n(_near_reach, _near_n, near_extent, x, z), cover)


## The bed under the sea (ground plus seabed), metres, laid out like
## bounds(), in WaterDepthMap's layout: R (still-water depth) 0, G the bed.
## The water shader fades its swell by the depth over this at the live
## level (SeaState), gated by reach, so the level can move without a rebake.
## From the coarse planes alone, which is plenty for a swell fade.
func bed_texture() -> ImageTexture:
	var n := _resolution
	var texels := PackedFloat32Array()
	texels.resize(n * n * 2)
	for i in n * n:
		texels[i * 2 + 1] = _ground[i] + _seabed[i]
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RGF, texels.to_byte_array())
	return ImageTexture.create_from_image(image)


## 0..1: how submerged by the sea at high water ground at `height` is
## here -- WaterProfile.water_mask()'s band, gated by reach(). For baked
## consumers (growth, water_cover()), never the live level.
func submerged(x: float, z: float, height: float, water: WaterProfile) -> float:
	var r := reach(x, z)
	if r <= 0.0:
		return 0.0
	# Ground the sea only reaches over a crest above high water is dry.
	if spill(x, z) > water.sea_high_water() + water.shore_band:
		return 0.0
	return r * water.water_mask(height)


## Bilinear, half-pixel centred, clamped at the crop's edge (the open sea or
## inland ground simply carries on).
func _sample(plane: PackedFloat32Array, x: float, z: float) -> float:
	return _sample_n(plane, _resolution, extent, x, z)


## _sample() of one channel of the interleaved coast field.
func _sample_rgb(channel: int, x: float, z: float) -> float:
	var n := _resolution
	var fx := clampf((x / extent + 0.5) * float(n) - 0.5, 0.0, float(n - 1))
	var fy := clampf((z / extent + 0.5) * float(n) - 0.5, 0.0, float(n - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, n - 1)
	var y1 := mini(y0 + 1, n - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(_coast_rgb[(y0 * n + x0) * 3 + channel], _coast_rgb[(y0 * n + x1) * 3 + channel], tx)
	var bottom := lerpf(_coast_rgb[(y1 * n + x0) * 3 + channel], _coast_rgb[(y1 * n + x1) * 3 + channel], tx)
	return lerpf(top, bottom, ty)


func _sample_n(plane: PackedFloat32Array, n: int, size: float, x: float, z: float) -> float:
	var fx := clampf((x / size + 0.5) * float(n) - 0.5, 0.0, float(n - 1))
	var fy := clampf((z / size + 0.5) * float(n) - 0.5, 0.0, float(n - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, n - 1)
	var y1 := mini(y0 + 1, n - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(plane[y0 * n + x0], plane[y0 * n + x1], tx)
	var bottom := lerpf(plane[y1 * n + x0], plane[y1 * n + x1], tx)
	return lerpf(top, bottom, ty)
