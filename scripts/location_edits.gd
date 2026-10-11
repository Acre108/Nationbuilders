class_name LocationEdits
extends RefCounted

## Authored edits layered over a location's base bake (docs/LOCATION_EDITOR_PLAN.md).
## The importer writes the base (.r32, rivers, site, masks); only Location
## Studio writes this document, and the runtime applies it at load. A missing
## file means no edits, and an empty document must change nothing.
##
## Each section arrives with its Studio phase. Until a build can apply a
## section, a document that fills it is rejected rather than half-applied.
## Building-instance runtime support arrived in M6 ahead of S3 authoring;
## building overrides arrived with S2 (LocationBuildingOverrides), painted
## zones with S4 (ZoneOverrides: tiles in <slug>.edits/zones/), heights
## with S5 (HeightDeltas: tiles in <slug>.edits/heights/).

const SCHEMA_VERSION := 1
const DIRECTORY := "res://content/locations"
## Section -> [empty value, plan phase that implements it].
const SECTIONS := {
	"zones": [{}, "S4"],
	"heights": [{}, "S5"],
	"water": [{}, "S6"],
	"building_overrides": [{}, "S2"],
	"building_instances": [[], "S3"],
}
## Files the edits were authored against. The manifest names the others.
const BASE_FILES := ["manifest", "heightmap", "rivers", "site"]

var data: Dictionary


func _init(source: Dictionary = {}) -> void:
	data = source


static func create(slug: String, north_axis: String, base: Dictionary = {}) -> LocationEdits:
	var source := {"schema_version": SCHEMA_VERSION, "slug": slug, "north_axis": north_axis, "base": base, "history": []}
	for section in SECTIONS:
		source[section] = SECTIONS[section][0].duplicate()
	return LocationEdits.new(source)


static func default_path(slug: String) -> String:
	return DIRECTORY.path_join(slug + ".edits.json")


static func path_for(definition: LocationDefinition) -> String:
	return definition.edits_path if not definition.edits_path.is_empty() else default_path(definition.slug)


## Validates the document, optionally against the destination it belongs to.
func validate(expected_slug: String = "", expected_north_axis: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	var allowed := ["schema_version", "slug", "north_axis", "base", "history"] + SECTIONS.keys()
	for key in data:
		if not key in allowed: errors.append("Unknown location edits field: %s" % key)
	if not HeightmapLocationLoader._finite_number(data.get("schema_version")) or int(data.schema_version) != SCHEMA_VERSION:
		errors.append("Unsupported location edits schema %s; this build reads schema %d." % [str(data.get("schema_version")), SCHEMA_VERSION])
		return errors
	var slug: Variant = data.get("slug")
	if not slug is String or String(slug).strip_edges().is_empty():
		errors.append("slug must be a non-empty string")
	elif not expected_slug.is_empty() and slug != expected_slug:
		errors.append("Edits belong to '%s', not '%s'." % [slug, expected_slug])
	var axis: Variant = data.get("north_axis")
	if not axis in ["+Z", "-Z"]:
		errors.append("north_axis must be +Z or -Z")
	elif not expected_north_axis.is_empty() and axis != expected_north_axis:
		errors.append("Edits use north_axis %s but the terrain uses %s." % [axis, expected_north_axis])
	var base: Variant = data.get("base")
	if not base is Dictionary:
		errors.append("base must be an object of file digests")
	else:
		for key in base:
			if not key in BASE_FILES: errors.append("Unknown base file: %s" % key)
			elif not _digest(base[key]): errors.append("base.%s must be a SHA-256 hex digest" % key)
	var history: Variant = data.get("history")
	if not history is Array:
		errors.append("history must be an array")
	else:
		for entry in history:
			if not entry is Dictionary or not entry.get("date") is String or not entry.get("summary") is String:
				errors.append("history entries need date and summary strings")
				break
	for section in SECTIONS:
		var empty: Variant = SECTIONS[section][0]
		var value: Variant = data.get(section)
		if typeof(value) != typeof(empty):
			errors.append("%s must be %s" % [section, "an object" if empty is Dictionary else "an array"])
		elif section == "building_overrides":
			errors.append_array(LocationBuildingOverrides.errors(value))
		elif section == "zones":
			errors.append_array(ZoneOverrides.section_errors(value))
		elif section == "heights":
			errors.append_array(HeightDeltas.section_errors(value))
		elif section == "building_instances":
			if value.size() > 128: errors.append("At most 128 building instances are supported.")
			var ids := {}
			var replacements := {}
			for record in value:
				var issues := BuildingPlacement.record_errors(record)
				errors.append_array(issues)
				if not issues.is_empty(): continue
				if ids.has(record.instance_id): errors.append("Duplicate building instance ID: " + record.instance_id)
				ids[record.instance_id] = true
				for id in record.get("replaces",[]):
					if replacements.has(id): errors.append("Duplicate replaced placeholder: " + id)
					replacements[id] = true
		elif not value.is_empty():
			errors.append("%s edits need Location Studio phase %s; this build cannot apply them." % [section, SECTIONS[section][1]])
	return errors


func is_empty() -> bool:
	for section in SECTIONS:
		var value: Variant = data.get(section, SECTIONS[section][0])
		if section in ["zones", "heights"] and value is Dictionary and value.get("tiles", {}).is_empty() and value.get("flattened", []).is_empty(): continue
		if not value.is_empty(): return false
	return true


## Base files whose digest differs from `current` (see base_digests()).
func stale_base(current: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	var recorded: Dictionary = data.get("base", {})
	for key in BASE_FILES:
		if recorded.get(key, "") != current.get(key, ""): changed.append(key)
	return changed


static func load_path(path: String, expected_slug: String = "", expected_north_axis: String = "") -> Dictionary:
	var read := DocumentStore.read_json(path)
	if not read.ok: return read
	var edits := LocationEdits.new(read.data)
	# JSON numbers parse as floats; keep the schema integer like a fresh document.
	if HeightmapLocationLoader._finite_number(edits.data.get("schema_version")):
		edits.data.schema_version = int(edits.data.schema_version)
	var errors := edits.validate(expected_slug, expected_north_axis)
	if not errors.is_empty(): return {"ok": false, "error": "%s: %s" % [path, "\n".join(errors)]}
	return {"ok": true, "edits": edits, "path": path}


## The destination's edits. A missing file is not an error: `edits` is null.
static func load_for(definition: LocationDefinition, north_axis: String = "") -> Dictionary:
	var path := path_for(definition)
	if not FileAccess.file_exists(path): return {"ok": true, "edits": null, "path": path}
	return load_path(path, definition.slug, north_axis)


## Whether a destination is drawn from its import alone or has had a
## Location Studio pass, for the landing screen: {"edited", "short", "text"}.
static func provenance_note(definition: LocationDefinition) -> Dictionary:
	var loaded := load_for(definition)
	if not loaded.ok:
		return {"edited": true, "short": "Studio edits (unreadable)",
			"text": "Location Studio edits could not be read: " + String(loaded.error).get_slice("
", 0)}
	var edits: LocationEdits = loaded.edits
	if edits == null or edits.is_empty():
		return {"edited": false, "short": "Imported data only", "text": "Imported data only. No Location Studio pass yet."}
	return {"edited": true, "short": "Location Studio edits", "text": "Imported data with a Location Studio pass: " + edits.summary() + "."}


## What the document changes, e.g. "12 restyled buildings, painted zones,
## last edit 2026-10-07 (Recoloured farm roofs)".
func summary() -> String:
	var parts := PackedStringArray()
	var overrides: Dictionary = data.get("building_overrides", {})
	if not overrides.is_empty(): parts.append("%d restyled building%s" % [overrides.size(), "" if overrides.size() == 1 else "s"])
	var instances: Array = data.get("building_instances", [])
	if not instances.is_empty(): parts.append("%d placed building%s" % [instances.size(), "" if instances.size() == 1 else "s"])
	for section in [["zones", "painted zones"], ["heights", "sculpted heights"], ["water", "edited water"]]:
		var value: Variant = data.get(section[0], {})
		if value is Dictionary and (not value.get("tiles", {}).is_empty() or not value.get("flattened", []).is_empty() or (section[0] == "water" and not value.is_empty())):
			parts.append(section[1])
	var history: Array = data.get("history", [])
	if not history.is_empty():
		var last: Dictionary = history.back()
		parts.append("last edit %s (%s)" % [last.date, last.summary])
	return ", ".join(parts)


func save(path: String) -> Dictionary:
	var errors := validate()
	if not errors.is_empty(): return {"ok": false, "error": "\n".join(errors)}
	return DocumentStore.save_json(path, data, func(file: String) -> Dictionary: return load_path(file, String(data.slug)))


## SHA-256 of the manifest and the base files it names. Only Studio pays for
## this; the runtime never hashes at load.
static func base_digests(manifest_path: String) -> Dictionary:
	var manifest := HeightmapLocationLoader.load_manifest(manifest_path)
	if manifest.is_empty(): return {}
	var directory := manifest_path.get_base_dir()
	var result := {"manifest": FileAccess.get_sha256(manifest_path)}
	result.heightmap = FileAccess.get_sha256(directory.path_join(manifest.heightmap.path))
	for key in ["rivers", "site"]:
		if manifest.has(key): result[key] = FileAccess.get_sha256(directory.path_join(manifest[key].path))
	return result


static func _digest(value: Variant) -> bool:
	if not value is String or String(value).length() != 64: return false
	return String(value).is_valid_hex_number()
