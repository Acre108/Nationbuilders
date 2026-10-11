class_name LocationBuildingOverrides
extends RefCounted

## Studio S2: authored appearance for imported placeholder buildings
## (docs/LOCATION_EDITOR_PLAN.md §6). Overrides live in
## LocationEdits.building_overrides, keyed by the record's geographic
## `source_id`; outlines stay observed and are never edited.
##
##   "osm/way/67654594": {
##     "materials": {"exterior_wall": "render:#d8cdb4", "roof": "roof-tiles"},
##     "height": {"value": 9.5, "basis": "street photo estimate"}
##   }
##
## A material value is a BuildingMaterials family ("brick"), a colour
## ("#d8cdb4") or a family tinted with a colour ("render:#d8cdb4").

const SLOTS := ["exterior_wall", "roof"]
## Families offered per slot; every one is a shared BuildingMaterials family.
const SLOT_FAMILIES := {
	"exterior_wall": ["render", "painted-wall", "brick", "stone", "concrete", "warm-wood", "dark-wood", "metal"],
	"roof": ["roof-tiles", "slate", "thatch", "metal", "concrete", "dark-wood"],
}
## Families drawn with roof_tiles.gdshader instead of a flat material.
const TILED := ["roof-tiles"]
const HEIGHT_RANGE := Vector2(1.0, 300.0)
const MAX_OVERRIDES := 20000
## Tag keys too specific to group buildings by in Apply to similar.
const UNGROUPED_TAGS := ["addr:housenumber", "name", "ref"]


## {"family", "colour"} for a material value, or {} when it is invalid.
## `colour` is the tint ("" when the family's own colour applies).
static func parse(value: Variant) -> Dictionary:
	if not value is String: return {}
	var text := String(value)
	var family := text
	var colour := ""
	if text.begins_with("#"):
		family = ""
		colour = text
	elif text.contains(":"):
		family = text.get_slice(":", 0)
		colour = text.get_slice(":", 1)
	if not family.is_empty() and not BuildingMaterials.FAMILIES.has(family): return {}
	if not colour.is_empty() and (not colour.begins_with("#") or not Color.html_is_valid(colour)): return {}
	if family.is_empty() and colour.is_empty(): return {}
	return {"family": family, "colour": colour}


static func compose(family: String, colour: String) -> String:
	if family.is_empty(): return colour
	if colour.is_empty() or Color(colour).is_equal_approx(family_colour(family)): return family
	return "%s:%s" % [family, colour]


static func family_colour(family: String) -> Color:
	return Color(BuildingMaterials.FAMILIES[family][0]) if BuildingMaterials.FAMILIES.has(family) else Color.WHITE


## The colour a material value renders with.
static func colour_of(value: String) -> Color:
	var parsed := parse(value)
	if parsed.is_empty(): return Color.WHITE
	return Color(parsed.colour) if not parsed.colour.is_empty() else family_colour(parsed.family)


static func roughness_of(value: String) -> float:
	var parsed := parse(value)
	return float(BuildingMaterials.FAMILIES[parsed.family][1]) if not parsed.is_empty() and not parsed.family.is_empty() else 0.95


static func is_tiled(value: String) -> bool:
	return parse(value).get("family", "") in TILED


static func errors(overrides: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not overrides is Dictionary:
		result.append("building_overrides must be an object")
		return result
	if overrides.size() > MAX_OVERRIDES: result.append("At most %d building overrides are supported." % MAX_OVERRIDES)
	for id in overrides:
		result.append_array(record_errors(id, overrides[id]))
		if result.size() > 20: break
	return result


static func record_errors(id: Variant, override: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not id is String or not String(id).contains("/"):
		result.append("Building override keys must be geographic source IDs such as osm/way/123: %s" % str(id))
		return result
	var label := "building_overrides.%s" % id
	if not override is Dictionary or override.is_empty():
		result.append(label + " must be a non-empty object")
		return result
	for key in override:
		if not key in ["materials", "height"]: result.append("%s: unknown field %s" % [label, key])
	if override.has("materials"):
		var materials: Variant = override.materials
		if not materials is Dictionary or materials.is_empty():
			result.append(label + ".materials must be a non-empty object")
		else:
			for slot in materials:
				if not slot in SLOTS: result.append("%s.materials: unknown slot %s" % [label, slot])
				elif parse(materials[slot]).is_empty(): result.append("%s.materials.%s must be a material family, #colour or family:#colour" % [label, slot])
	if override.has("height"):
		var height: Variant = override.height
		if not height is Dictionary: result.append(label + ".height must be an object")
		else:
			for key in height:
				if not key in ["value", "basis"]: result.append("%s.height: unknown field %s" % [label, key])
			var value: Variant = height.get("value")
			if not HeightmapLocationLoader._finite_number(value) or float(value) < HEIGHT_RANGE.x or float(value) > HEIGHT_RANGE.y:
				result.append("%s.height.value must be %d–%d m" % [label, HEIGHT_RANGE.x, HEIGHT_RANGE.y])
			if not height.get("basis") is String or String(height.get("basis")).strip_edges().is_empty():
				result.append(label + ".height needs a basis")
	return result


## The record as drawn: the observed record with an authored height applied.
## The observed record itself is never changed.
static func effective_record(record: Dictionary, override: Dictionary) -> Dictionary:
	if not override.has("height"): return record
	var result := record.duplicate()
	result.height = float(override.height.value)
	result.height_basis = "authored: " + String(override.height.basis)
	return result


## The materials a placeholder is drawn with: the record's imported
## `materials` (import_site.py, building_materials.py) with authored slots on
## top. Invalid imported values are dropped, leaving the slot's default.
static func drawn_materials(record: Dictionary, override: Dictionary) -> Dictionary:
	var result := {}
	var imported: Variant = record.get("materials", {})
	if imported is Dictionary:
		for slot in SLOTS:
			if imported.has(slot) and not parse(imported[slot]).is_empty(): result[slot] = imported[slot]
	result.merge(override.get("materials", {}), true)
	return result


## Override IDs that no base record carries any more (kept, never deleted).
static func orphans(overrides: Dictionary, records: Array) -> PackedStringArray:
	var known := {}
	for record in records: known[record.get("source_id")] = true
	var result := PackedStringArray()
	for id in overrides:
		if not known.has(id): result.append(id)
	result.sort()
	return result


## Source IDs of other records sharing `record`'s value for tag `key`.
static func similar(records: Array, record: Dictionary, key: String) -> PackedStringArray:
	var result := PackedStringArray()
	var tags: Dictionary = record.get("tags", {})
	if not tags.has(key): return result
	for other in records:
		if other.get("source_id") != record.get("source_id") and other.get("tags", {}).has(key) and str(other.tags[key]) == str(tags[key]):
			result.append(other.source_id)
	return result


## Tag keys of `record` that group it with at least one other building.
static func grouping_keys(records: Array, record: Dictionary) -> Array:
	var result := []
	for key in record.get("tags", {}):
		if key in UNGROUPED_TAGS: continue
		var count := similar(records, record, key).size()
		if count > 0: result.append({"key": key, "value": str(record.tags[key]), "count": count})
	# "building" first, then alphabetical.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.key == "building" or b.key == "building": return a.key == "building" and b.key != "building"
		return a.key < b.key)
	return result
