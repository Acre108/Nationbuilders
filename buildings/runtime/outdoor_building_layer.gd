class_name OutdoorBuildingLayer
extends Node3D

## Runtime half of Studio S3. Authoring supplies pinned instance records; this
## layer validates the entire replacement before changing scenes or exclusions.
signal changed
var terrain: TerrainProvider
var placement_events: FoliagePlacementEvents
var exclusions: FoliageExclusions
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH:
	set(value):
		quality_level = value
		for building in instances.values(): BuildingLocalLights.set_quality(building,value)
var instances: Dictionary = {}
var records: Array = []
var zones: Array[AtmosphereZone] = []
var replaced_ids: Dictionary = {}

func replace_all(next: Array) -> Dictionary:
	next = next.duplicate(true)
	if next.size() > 128: return {"ok":false,"error":"At most 128 outdoor building instances are supported per destination."}
	var prepared: Array = []
	var ids := {}
	var replacements := {}
	for record in next:
		var errors := BuildingPlacement.record_errors(record)
		if not errors.is_empty(): return {"ok":false,"error":"; ".join(errors)}
		if ids.has(record.instance_id): return {"ok":false,"error":"Duplicate building instance ID: "+record.instance_id}
		ids[record.instance_id] = true
		for id in record.get("replaces",[]):
			if replacements.has(id): return {"ok":false,"error":"Two instances replace the same placeholder: "+id}
			if not _known_placeholder(id): return {"ok":false,"error":"Replacement placeholder is missing: "+id}
			replacements[id] = true
		var placement := BuildingPlacement.prepare(record,terrain)
		if not placement.ok: return {"ok":false,"error":str(record.instance_id)+": "+placement.error}
		prepared.append(placement)
	var buildings: Array[Node3D] = []
	for placement in prepared: buildings.append(BuildingPlacement.build(placement))
	_clear()
	records = next.duplicate(true)
	replaced_ids = replacements
	for index in records.size():
		var record: Dictionary = records[index]
		var placement: Dictionary = prepared[index]
		var building := buildings[index]
		building.name = record.instance_id
		building.set_meta("building_instance",record.duplicate(true))
		building.set_meta("building_definition",placement.definition)
		add_child(building)
		building.transform = placement.transform
		instances[record.instance_id] = building
		BuildingLocalLights.set_quality(building,quality_level)
		zones.append_array(BuildingLightingZones.create(placement.definition,building.global_transform))
		var id := StringName("building:"+str(record.instance_id))
		if placement_events != null: placement_events.place(id,placement.footprints)
		if exclusions != null:
			var vegetation: Array[GrassCarver] = []
			for footprint: PolygonGrassCarver in placement.footprints: vegetation.append(PolygonGrassCarver.new(footprint.polygon,1.5))
			exclusions.place(id,vegetation)
	changed.emit()
	return {"ok":true}

## Places every record that validates on its own and skips the rest, for
## Studio sessions whose base changed under authored instances. Returns
## {"ok", "skipped": {instance_id: reason}}. The game uses replace_all().
func replace_valid(next: Array) -> Dictionary:
	var kept: Array = []
	var skipped := {}
	var ids := {}
	var replacements := {}
	for record in next.slice(0,128):
		var errors := BuildingPlacement.record_errors(record)
		var id := str(record.get("instance_id","?")) if record is Dictionary else "?"
		if not errors.is_empty():
			skipped[id] = "; ".join(errors)
			continue
		if ids.has(id):
			skipped[id] = "Duplicate building instance ID."
			continue
		var reason := ""
		for replaced in record.get("replaces",[]):
			if replacements.has(replaced): reason = "Another instance already replaces " + replaced
			elif not _known_placeholder(replaced): reason = "Replacement placeholder is missing: " + replaced
		if reason.is_empty():
			var placement := BuildingPlacement.prepare(record,terrain)
			if not placement.ok: reason = placement.error
		if not reason.is_empty():
			skipped[id] = reason
			continue
		ids[id] = true
		for replaced in record.get("replaces",[]): replacements[replaced] = true
		kept.append(record)
	var result := replace_all(kept)
	result.skipped = skipped
	return result

func set_instance(record: Dictionary) -> Dictionary:
	var next := records.duplicate(true)
	var found := false
	for index in next.size():
		if next[index].instance_id == record.get("instance_id"):
			next[index] = record.duplicate(true)
			found = true
	if not found: next.append(record.duplicate(true))
	return replace_all(next)

func remove_instance(id: String) -> Dictionary:
	return replace_all(records.filter(func(record: Dictionary) -> bool: return record.instance_id != id))

func _known_placeholder(id: String) -> bool:
	if not terrain is HeightmapTerrainProvider or terrain.imported_site == null: return false
	for record in terrain.imported_site.data.buildings:
		if record.source_id == id: return true
	return false

func _clear() -> void:
	for id in instances:
		var key := StringName("building:"+str(id))
		if placement_events != null: placement_events.remove(key)
		if exclusions != null: exclusions.remove(key)
		var building: Node3D = instances[id]
		remove_child(building)
		building.free()
	instances.clear()
	zones.clear()
	replaced_ids.clear()
	records.clear()

func _exit_tree() -> void:
	_clear()
