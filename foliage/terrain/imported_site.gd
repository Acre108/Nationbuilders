class_name ImportedSite
extends RefCounted

## Normalized offline records, kept for replacement by the building editor.
var data: Dictionary
var mask: Texture2D
var _pixels := PackedByteArray()
var _resolution: int
## Side of the detailed site square every mask covers, centred on the origin.
## Equal to the terrain crop for older sidecars; smaller (4 km by default) for
## Location Studio imports, which leave the rest of the crop to inferred zones.
var _size: float
var _world_size: float
## Metres inside a partial site's edge over which observed data fades into the
## inferred zones beyond (coverage()).
const SITE_FADE := 200.0
## Observed environment zones (zone_mask, tools/geo/import_site.py): RGBA =
## wetland, garden, scrub, forest. Empty when the sidecar has none.
var zone_texture: Texture2D
var _zone_pixels := PackedByteArray()
var _zone_resolution: int = 0
## Field crops (fields_mask, tools/geo/crops.py): RG planted field index
## (UNMAPPED_FIELD for WorldCover-only cropland, 0 headland or none), B crop
## id (CropCatalogue), A row angle (0..255 = 0..PI from +X toward +Z).
var fields_texture: Texture2D
## Settlements and roadside (settlement_mask, tools/geo/settlements.py): RGBA =
## village, town, roadside verge, verge road context (0 rural, 128 village,
## 255 town). Empty when the sidecar has none.
var _settlement_pixels := PackedByteArray()
var _settlement_resolution: int = 0
var _field_pixels := PackedByteArray()
var _field_resolution: int = 0
## Coastal and heath habitats (habitat_mask, tools/geo/import_site.py): RGB =
## dune grassland, heath, open sand or beach. Empty when the sidecar has none.
var habitat_texture: Texture2D
var _habitat_pixels := PackedByteArray()
var _habitat_resolution: int = 0
const UNMAPPED_FIELD := 65535

static func load_file(path: String, centre: Dictionary, world_size: float, north_axis: String = "+Z") -> ImportedSite:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024:
		push_error("ImportedSite: missing or oversized sidecar " + path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("schema_version") != 1.0:
		push_error("ImportedSite: invalid schema " + path)
		return null
	if parsed.get("centre") != centre or parsed.get("world_size") != world_size:
		push_error("ImportedSite: sidecar crop does not match heightmap")
		return null
	if parsed.get("north_axis", "+Z") != north_axis or parsed.get("mask", {}).get("row_zero") != ("north" if north_axis == "-Z" else "south"):
		push_error("ImportedSite: sidecar axis/mask orientation does not match heightmap")
		return null
	for key in ["buildings", "roads", "props", "trees"]:
		if not parsed.get(key) is Array:
			return null
	for record in parsed.buildings + parsed.roads:
		if not record is Dictionary: return null
		var points: Variant = record.get("outline", record.get("points"))
		if not points is Array or points.size() < 2: return null
		for p in points:
			if not _point_valid(p, world_size): return null
	for record in parsed.props + parsed.trees:
		if not record is Dictionary or not _point_valid(record.get("xz"), world_size): return null
	var fields: Variant = parsed.get("fields", [])
	if not fields is Array or fields.size() > 65000: return null
	for record in fields:
		if not record is Dictionary or CropCatalogue.id_of(String(record.get("crop", ""))) == 0: return null
		if not _point_valid(record.get("row_direction"), 2): return null
	var filename: Variant = parsed.get("mask", {}).get("path")
	if not filename is String or filename.get_file() != filename: return null
	var texture := load(path.get_base_dir().path_join(filename)) as Texture2D
	if texture == null: return null
	var image := texture.get_image()
	if image == null or image.get_width() != image.get_height() or image.get_width() > 4096: return null
	image.convert(Image.FORMAT_RGB8)
	var result := ImportedSite.new()
	result.data = parsed
	result.mask = texture
	result._pixels = image.get_data()
	result._resolution = image.get_width()
	var site_size: Variant = parsed.get("site_size", world_size)
	if not HeightmapLocationLoader._finite_number(site_size) or float(site_size) < 500.0 or float(site_size) > world_size:
		push_error("ImportedSite: site_size must be 500 m up to the terrain world_size")
		return null
	result._size = float(site_size)
	result._world_size = world_size
	if parsed.has("zone_mask"):
		var zones: Variant = parsed.zone_mask
		if not zones is Dictionary or zones.get("row_zero") != parsed.mask.get("row_zero"):
			push_error("ImportedSite: zone mask orientation does not match the site mask")
			return null
		var zone_file: Variant = zones.get("path")
		if not zone_file is String or zone_file.get_file() != zone_file: return null
		var zone_texture := load(path.get_base_dir().path_join(zone_file)) as Texture2D
		if zone_texture == null: return null
		var zone_image := zone_texture.get_image()
		if zone_image == null or zone_image.get_width() != zone_image.get_height() or zone_image.get_width() > 4096: return null
		if zone_image.is_compressed(): zone_image.decompress()
		zone_image.convert(Image.FORMAT_RGBA8)
		result.zone_texture = zone_texture
		result._zone_pixels = zone_image.get_data()
		result._zone_resolution = zone_image.get_width()
	if parsed.has("settlement_mask"):
		var settled: Variant = parsed.settlement_mask
		if not settled is Dictionary or settled.get("row_zero") != parsed.mask.get("row_zero"):
			push_error("ImportedSite: settlement mask orientation does not match the site mask")
			return null
		var settled_file: Variant = settled.get("path")
		if not settled_file is String or settled_file.get_file() != settled_file: return null
		var settled_texture := load(path.get_base_dir().path_join(settled_file)) as Texture2D
		if settled_texture == null: return null
		var settled_image := settled_texture.get_image()
		if settled_image == null or settled_image.get_width() != settled_image.get_height() or settled_image.get_width() > 4096: return null
		if settled_image.is_compressed(): settled_image.decompress()
		settled_image.convert(Image.FORMAT_RGBA8)
		result._settlement_pixels = settled_image.get_data()
		result._settlement_resolution = settled_image.get_width()
	if parsed.has("habitat_mask"):
		var habitat_texture := _mask_texture(parsed, "habitat_mask", path)
		if habitat_texture == null: return null
		var habitat_image := habitat_texture.get_image()
		if habitat_image.is_compressed(): habitat_image.decompress()
		habitat_image.convert(Image.FORMAT_RGBA8)
		result.habitat_texture = habitat_texture
		result._habitat_pixels = habitat_image.get_data()
		result._habitat_resolution = habitat_image.get_width()
	if parsed.has("fields_mask"):
		var spec: Variant = parsed.fields_mask
		if not spec is Dictionary or spec.get("row_zero") != parsed.mask.get("row_zero"):
			push_error("ImportedSite: fields mask orientation does not match the site mask")
			return null
		var field_file: Variant = spec.get("path")
		if not field_file is String or field_file.get_file() != field_file: return null
		var field_texture := load(path.get_base_dir().path_join(field_file)) as Texture2D
		if field_texture == null: return null
		var field_image := field_texture.get_image()
		if field_image == null or field_image.get_width() != field_image.get_height() or field_image.get_width() > 4096: return null
		if field_image.is_compressed(): field_image.decompress()
		field_image.convert(Image.FORMAT_RGBA8)
		result.fields_texture = field_texture
		result._field_pixels = field_image.get_data()
		result._field_resolution = field_image.get_width()
	return result

## A square site-aligned mask named by sidecar entry `key`, or null (with an
## error for a mismatched orientation).
static func _mask_texture(parsed: Dictionary, key: String, path: String) -> Texture2D:
	var spec: Variant = parsed[key]
	if not spec is Dictionary or spec.get("row_zero") != parsed.mask.get("row_zero"):
		push_error("ImportedSite: %s orientation does not match the site mask" % key)
		return null
	var file: Variant = spec.get("path")
	if not file is String or file.get_file() != file: return null
	var texture := load(path.get_base_dir().path_join(file)) as Texture2D
	if texture == null: return null
	var image := texture.get_image()
	if image == null or image.get_width() != image.get_height() or image.get_width() > 4096: return null
	return texture

static func _point_valid(point: Variant, size: float) -> bool:
	if not point is Array or point.size() != 2: return false
	for value in point:
		if not HeightmapLocationLoader._finite_number(value) or absf(float(value)) > size / 2 + 1: return false
	return true

## Immutable bytes are safe for worker threads. Row 0 is the -Z edge;
## geographically north for corrected imports, south for legacy imports.
func has_zones() -> bool:
	return _zone_resolution > 0


## World XZ rectangle every site mask covers (the detailed site).
func bounds() -> Rect2:
	return Rect2(-_size / 2.0, -_size / 2.0, _size, _size)


## True when the detailed site covers only the middle of the terrain crop.
func is_partial() -> bool:
	return _size < _world_size


## How much observed site data applies at a world XZ: 1 inside the site,
## easing to 0 over SITE_FADE at its edge and 0 beyond, where zones are
## inferred. Always 1 for a site covering the whole crop, so older sidecars
## behave exactly as before. Mirrored by terrain.gdshader (site_coverage()).
func coverage(x: float, z: float) -> float:
	if not is_partial():
		return 1.0
	return smoothstep(0.0, SITE_FADE, _size / 2.0 - maxf(absf(x), absf(z)))


## SITE_FADE for a partial site, 0 when the site covers the crop.
func fade_distance() -> float:
	return SITE_FADE if is_partial() else 0.0


## Observed zone weights at a world XZ: r wetland, g garden, b scrub, a forest,
## each 0..1. Zero outside the crop or without a zone mask.
func zone_cover(x: float, z: float) -> Color:
	if _zone_resolution == 0:
		return Color(0, 0, 0, 0)
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	if u < 0 or u > 1 or v < 0 or v > 1: return Color(0, 0, 0, 0)
	var ix := clampi(int(u * _zone_resolution), 0, _zone_resolution - 1)
	var iz := clampi(int(v * _zone_resolution), 0, _zone_resolution - 1)
	var i := (iz * _zone_resolution + ix) * 4
	return Color(_zone_pixels[i] / 255.0, _zone_pixels[i + 1] / 255.0, _zone_pixels[i + 2] / 255.0, _zone_pixels[i + 3] / 255.0)


func has_settlements() -> bool:
	return _settlement_resolution > 0


## Settlement mask at a world XZ: r village, g town, b roadside verge, a the
## verge's road context (0 rural, ~0.5 village, 1 town). Zero outside.
func settlement_cover(x: float, z: float) -> Color:
	if _settlement_resolution == 0:
		return Color(0, 0, 0, 0)
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	if u < 0 or u > 1 or v < 0 or v > 1: return Color(0, 0, 0, 0)
	var ix := clampi(int(u * _settlement_resolution), 0, _settlement_resolution - 1)
	var iz := clampi(int(v * _settlement_resolution), 0, _settlement_resolution - 1)
	var i := (iz * _settlement_resolution + ix) * 4
	return Color(_settlement_pixels[i] / 255.0, _settlement_pixels[i + 1] / 255.0, _settlement_pixels[i + 2] / 255.0, _settlement_pixels[i + 3] / 255.0)


func has_habitats() -> bool:
	return _habitat_resolution > 0


## Habitat mask at a world XZ: r dune grassland, g heath, b open sand or
## beach, each 0..1. Zero outside the site or without a habitat mask.
func habitat_cover(x: float, z: float) -> Color:
	if _habitat_resolution == 0:
		return Color(0, 0, 0, 0)
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	if u < 0 or u > 1 or v < 0 or v > 1: return Color(0, 0, 0, 0)
	var ix := clampi(int(u * _habitat_resolution), 0, _habitat_resolution - 1)
	var iz := clampi(int(v * _habitat_resolution), 0, _habitat_resolution - 1)
	var i := (iz * _habitat_resolution + ix) * 4
	return Color(_habitat_pixels[i] / 255.0, _habitat_pixels[i + 1] / 255.0, _habitat_pixels[i + 2] / 255.0, 0.0)


func has_fields() -> bool:
	return _field_resolution > 0


## Fields mask at a world XZ: x planted field index, y crop id, z row angle
## byte. Zero outside the crop or without a fields mask.
func field_at(x: float, z: float) -> Vector3i:
	if _field_resolution == 0:
		return Vector3i.ZERO
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	if u < 0 or u > 1 or v < 0 or v > 1: return Vector3i.ZERO
	var ix := clampi(int(u * _field_resolution), 0, _field_resolution - 1)
	var iz := clampi(int(v * _field_resolution), 0, _field_resolution - 1)
	var i := (iz * _field_resolution + ix) * 4
	return Vector3i(_field_pixels[i] | (_field_pixels[i + 1] << 8), _field_pixels[i + 2], _field_pixels[i + 3])


## Metres per fields-mask texel.
func field_texel_metres() -> float:
	return _size / maxf(_field_resolution, 1)


## World XZ unit row direction for a fields-mask angle byte.
static func row_direction(angle_byte: int) -> Vector2:
	var angle := float(angle_byte) / 255.0 * PI
	return Vector2(cos(angle), sin(angle))


## Calendar day for this site's crops (CropCatalogue.local_day()).
func crop_day(day_of_year: float) -> float:
	var region: Dictionary = data.get("crop_region", {})
	return CropCatalogue.local_day(day_of_year, float(data.get("centre", {}).get("lat", 0.0)), float(region.get("calendar_shift", 0)))


## The site mask's farmland channel (B), 0..1.
func farmland(x: float, z: float) -> float:
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	if u < 0 or u > 1 or v < 0 or v > 1: return 0.0
	var ix := clampi(int(u * _resolution), 0, _resolution - 1)
	var iz := clampi(int(v * _resolution), 0, _resolution - 1)
	return float(_pixels[(iz * _resolution + ix) * 3 + 2]) / 255.0


## Site tree habitat (mask G). Beyond a partial site trees are unrestricted,
## blending in over the site's fade band; a whole-crop site keeps 0 outside.
func tree_mask(x: float, z: float) -> float:
	var u := (x + _size / 2) / _size
	var v := (z + _size / 2) / _size
	var mapped := 0.0
	if u >= 0 and u <= 1 and v >= 0 and v <= 1:
		var ix := clampi(int(u * _resolution), 0, _resolution - 1)
		var iz := clampi(int(v * _resolution), 0, _resolution - 1)
		mapped = float(_pixels[(iz * _resolution + ix) * 3 + 1]) / 255.0
	if not is_partial(): return mapped
	return lerpf(1.0, mapped, coverage(x, z))
