class_name BuildingStore
extends RefCounted

const DIRECTORY := "user://buildings"

static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "Building file does not exist: " + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Could not read building: " + error_string(FileAccess.get_open_error())}
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(contents)
	if parse_error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "Invalid building JSON. Source file is unchanged."}
	var definition := BuildingDefinition.new(parser.data)
	var errors := definition.validate()
	if not errors.is_empty(): return {"ok": false, "error": "\n".join(errors)}
	return {"ok": true, "definition": definition, "path": path}

static func load_id(id: String) -> Dictionary:
	if not BuildingDefinition.valid_id(id): return {"ok": false, "error": "Invalid building ID."}
	var user_path := DIRECTORY.path_join(id + ".json")
	return load_path(user_path if FileAccess.file_exists(user_path) else "res://content/buildings/".path_join(id + ".json"))

static func save(definition: BuildingDefinition, directory: String = DIRECTORY) -> Dictionary:
	var errors := definition.validate()
	if not errors.is_empty(): return {"ok": false, "error": "\n".join(errors)}
	return DocumentStore.save_json(directory.path_join(str(definition.data.id) + ".json"), definition.data, load_path)

static func list_saved() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var filenames := {}
	var directory := DirAccess.open(DIRECTORY)
	var user_files := directory.get_files() if directory != null else PackedStringArray()
	for filename in user_files:
		if not filename.ends_with(".json"): continue
		filenames[filename] = true
		var path := DIRECTORY.path_join(filename)
		var loaded := load_path(path)
		results.append({"path": path, "name": loaded.definition.data.name if loaded.ok else filename + " (unavailable)", "error": "" if loaded.ok else loaded.error})
	var shipped := DirAccess.open("res://content/buildings")
	if shipped != null:
		for filename in shipped.get_files():
			if not filename.ends_with(".json") or filenames.has(filename): continue
			var path := "res://content/buildings/".path_join(filename)
			var loaded := load_path(path)
			results.append({"path":path,"name":loaded.definition.data.name + " (built-in)" if loaded.ok else filename + " (unavailable)","error":"" if loaded.ok else loaded.error})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return results
