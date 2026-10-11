class_name BuildingSnapshotStore
extends RefCounted

const DIRECTORY := "res://content/buildings/placed"

## Pins are immutable files, loaded by exact path without user-save precedence.
static func snapshot(definition: BuildingDefinition, directory: String = DIRECTORY) -> Dictionary:
	if not valid_directory(directory): return {"ok":false,"error":"Snapshots must be stored in a placed-buildings directory."}
	var copy := _pinnable(definition)
	var errors := copy.validate()
	if not errors.is_empty() or copy.is_grid_draft(): return {"ok":false,"error":"Only a valid resolved building can be pinned. " + "; ".join(errors)}
	var contents := JSON.stringify(copy.data,"",true,true)
	var path := directory.path_join(str(copy.data.id)+"."+contents.sha256_text().left(12)+".json")
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_string(path) != contents: return {"ok":false,"error":"Existing snapshot differs; immutable pin was not overwritten."}
	else:
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK: return {"ok":false,"error":"Cannot create snapshot directory: "+error_string(error)}
		var temporary := path+".tmp"
		var file := FileAccess.open(temporary,FileAccess.WRITE)
		if file == null: return {"ok":false,"error":"Cannot write building snapshot: "+error_string(FileAccess.get_open_error())}
		file.store_string(contents)
		file.close()
		if FileAccess.get_sha256(temporary) != contents.sha256_text(): return {"ok":false,"error":"Snapshot write failed verification; no pin was published."}
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(temporary)
			if FileAccess.get_file_as_string(path) != contents: return {"ok":false,"error":"Snapshot appeared during publication; immutable pin was not overwritten."}
		else:
			error = DirAccess.rename_absolute(temporary,path)
			if error != OK: return {"ok":false,"error":"Cannot publish building snapshot: "+error_string(error)}
	return {"ok":true,"path":path,"source_building_id":copy.data.id}

## The 12-hex digest a snapshot of `definition` would carry; equal to
## pin_digest() of an existing pin when the design is unchanged.
static func digest(definition: BuildingDefinition) -> String:
	return JSON.stringify(_pinnable(definition).data,"",true,true).sha256_text().left(12)

static func pin_digest(path: String) -> String:
	return path.get_file().get_basename().get_extension()

static func _pinnable(definition: BuildingDefinition) -> BuildingDefinition:
	var copy := definition.copy()
	copy.data.erase("geographic_placement")
	return copy

static func valid_path(path: Variant) -> bool:
	if not path is String: return false
	if not valid_directory(path.get_base_dir()): return false
	var filename: String = path.get_file()
	if not filename.ends_with(".json"): return false
	var stem := filename.get_basename()
	var split := stem.rfind(".")
	return split > 0 and BuildingDefinition.valid_id(stem.left(split)) and stem.substr(split+1).length() == 12 and stem.substr(split+1).is_valid_hex_number()

static func valid_directory(directory: String) -> bool:
	if directory == DIRECTORY: return true
	if not directory.begins_with("user://") or not directory.ends_with("/placed"): return false
	for segment in directory.trim_prefix("user://").split("/"):
		if not BuildingDefinition.valid_id(segment): return false
	return true

static func load_pin(path: String) -> Dictionary:
	if not valid_path(path): return {"ok":false,"error":"Invalid pinned building path: "+path}
	var expected := path.get_file().get_basename().get_extension()
	if FileAccess.get_sha256(path).left(12) != expected: return {"ok":false,"error":"Missing or changed immutable building snapshot: "+path}
	var loaded := BuildingStore.load_path(path)
	if loaded.ok and loaded.definition.is_grid_draft(): return {"ok":false,"error":"Snapshot has no resolved shell."}
	return loaded
