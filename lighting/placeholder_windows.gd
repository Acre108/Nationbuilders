class_name PlaceholderWindows
extends RefCounted

## Generic procedural windows for geographic placeholder buildings, lit warm
## after dusk. Material only: the placeholder keeps its footprint, height and
## source record, so the future building editor replaces it unchanged.
## Authored buildings (BuildingDefinition) never use this.

## OSM building values that are not lived in: no windows, nothing lit.
const UNLIT := ["barn", "garage", "garages", "shed", "sty", "digester", "farm_auxiliary",
	"demolished", "boathouse", "greenhouse", "roof", "carport", "hut", "silo",
	"storage_tank", "church", "chapel", "cowshed", "stable", "ruins", "transformer_tower"]
## Footprints smaller than this are treated as sheds even when only "yes".
const MIN_AREA := 40.0
const SHADER := preload("res://lighting/placeholder_windows.gdshader")
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material

## True when the record looks like a lived-in building.
static func eligible(record: Dictionary) -> bool:
	var kind := str(record.get("tags", {}).get("building", "yes"))
	if kind in UNLIT: return false
	return absf(_area(record.outline)) >= MIN_AREA and float(record.get("height", 0)) >= 2.7

## Replace the wall mesh with the same geometry plus window UVs. `low`/`top`
## and the winding match LocationSiteLayer's placeholder walls.
static func apply(wall: MeshInstance3D, record: Dictionary, low: float, top: float, north_axis: String) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wall_arrays(record, low, top, north_axis))
	wall.mesh = mesh
	wall.material_override = material()

## Thread-safe wall surface arrays with window UVs: the placeholder's walls,
## and (its triangles) their collision.
static func wall_arrays(record: Dictionary, low: float, top: float, north_axis: String) -> Array:
	var seed := float(hash(str(record.get("source_id", ""))) % 997) if eligible(record) else -1.0
	var base := low - 0.5
	var height := top - base
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in [record.outline] + record.get("holes", []):
		for i in ring.size():
			var a: Array = ring[i]
			var b: Array = ring[(i + 1) % ring.size()]
			var length := Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))
			var corners := {
				"ab": [Vector3(a[0], base, a[1]), Vector2(0.0, 0.0)],
				"bb": [Vector3(b[0], base, b[1]), Vector2(length, 0.0)],
				"at": [Vector3(a[0], top, a[1]), Vector2(0.0, height)],
				"bt": [Vector3(b[0], top, b[1]), Vector2(length, height)],
			}
			var order := ["ab", "bb", "bt", "ab", "bt", "at"] if north_axis == "-Z" \
				else ["ab", "bt", "bb", "ab", "at", "bt"]
			for key in order:
				st.set_uv(corners[key][1])
				st.set_uv2(Vector2(length, seed))
				st.set_color(Color(height / 64.0, 0.0, 0.0))
				st.add_vertex(corners[key][0])
	st.generate_normals()
	return st.commit_to_arrays()

static func _area(outline: Array) -> float:
	var sum := 0.0
	for i in outline.size():
		var a: Array = outline[i]
		var b: Array = outline[(i + 1) % outline.size()]
		sum += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return sum * 0.5
