class_name CropCatalogue
extends RefCounted

## The shared crop table (content/crops/crops.json, also read by
## tools/geo/crops.py) and its growth calendars. Fields carry only a crop id;
## what that crop looks like (bare soil, green, flowering, ripe, stubble)
## follows the location's day of year here, at runtime.
const TABLE_PATH := "res://content/crops/crops.json"
## Shader uniform array length; crop ids index it directly (0 = no crop).
const MAX_CROPS := 16
const DAYS := 365.0

static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		if not parsed is Dictionary:
			push_error("CropCatalogue: unreadable " + TABLE_PATH)
			return {}
		_table = parsed
		_table.by_id = {}
		_table.by_name = {}
		for entry: Dictionary in _table.crops:
			_table.by_id[int(entry.id)] = entry
			_table.by_name[entry.name] = entry
	return _table


static func crop(id: int) -> Dictionary:
	return table().get("by_id", {}).get(id, {})


static func id_of(name: String) -> int:
	return int(table().get("by_name", {}).get(name, {}).get("id", 0))


## Calendar day for a location: the table's calendars are northern-hemisphere
## Central European; regions shift them, southern latitudes add half a year.
static func local_day(day_of_year: float, latitude: float, calendar_shift: float) -> float:
	var day := day_of_year - calendar_shift + (DAYS / 2.0 if latitude < 0.0 else 0.0)
	return fposmod(day - 1.0, DAYS) + 1.0


## A crop's appearance on calendar `day` (see local_day()). Keys:
## height_m (0 = no standing plants), plant (Color, recolour target for the
## plant mesh), recolour (0..1; 0 keeps the model's own colours), field
## (Color seen from afar), cover (0..1 of field colour over bare soil).
static func appearance(id: int, day: float) -> Dictionary:
	var entry := crop(id)
	if entry.is_empty():
		return {height_m = 0.0, plant = Color.BLACK, recolour = 0.0, field = soil(), cover = 0.0}
	var frames: Array = entry.calendar
	var day_wrapped := fposmod(day - 1.0, DAYS) + 1.0
	var a: Array = frames[frames.size() - 1]
	var b: Array = frames[0]
	for i in frames.size():
		if float(frames[i][0]) <= day_wrapped:
			a = frames[i]
			b = frames[(i + 1) % frames.size()]
	var span := fposmod(float(b[0]) - float(a[0]), DAYS)
	var t := 0.0 if span <= 0.0 else clampf(fposmod(day_wrapped - float(a[0]), DAYS) / span, 0.0, 1.0)
	var height := lerpf(float(a[1]), float(b[1]), t)
	return {
		height_m = height * float(entry.height_m) if height >= 0.04 else 0.0,
		plant = _colour(a[2]).lerp(_colour(b[2]), t),
		field = _colour(a[3]).lerp(_colour(b[3]), t),
		cover = lerpf(float(a[4]), float(b[4]), t),
		recolour = lerpf(float(a[5]), float(b[5]), t),
	}


static func soil() -> Color:
	return _colour("soil")


static func _colour(name: String) -> Color:
	var rgb: Array = table().palette.get(name, [1, 0, 1])
	return Color(rgb[0], rgb[1], rgb[2])


## Terrain shader arrays for every crop id on `day`: field colour + cover,
## and rows (spacing, stripe width, stripe strength, tramlines).
static func shader_arrays(day: float) -> Dictionary:
	var fields := PackedVector4Array()
	var rows := PackedVector4Array()
	fields.resize(MAX_CROPS)
	rows.resize(MAX_CROPS)
	for id in MAX_CROPS:
		var entry := crop(id)
		if entry.is_empty():
			fields[id] = Vector4(soil().r, soil().g, soil().b, 0.0)
			rows[id] = Vector4(1.0, 0.5, 0.0, 0.0)
			continue
		var look := appearance(id, day)
		var field: Color = look.field
		fields[id] = Vector4(field.r, field.g, field.b, look.cover)
		var r: Dictionary = entry.rows
		rows[id] = Vector4(float(r.spacing), float(r.width), float(r.strength), 1.0 if r.tramlines else 0.0)
	return {fields = fields, rows = rows}
