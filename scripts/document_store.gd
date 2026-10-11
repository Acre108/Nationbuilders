class_name DocumentStore
extends RefCounted

## Safe JSON document writes shared by building saves and location edits.
## A save is staged in `<path>.tmp`, re-read through the caller's loader,
## then swapped in while the previous file is retained as `<path>.bak`.
## Existing files the loader rejects (corrupt or future versions) are never
## overwritten, so their bytes remain recoverable.

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok": false, "error": "File does not exist: " + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Could not read %s: %s" % [path, error_string(FileAccess.get_open_error())]}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "Invalid JSON in %s. Source file is unchanged." % path}
	return {"ok": true, "data": parser.data}


## `loader(path) -> {ok, error}` validates a file on disk. It runs against the
## existing save before anything is replaced and against the staged copy.
static func save_json(path: String, data: Dictionary, loader: Callable) -> Dictionary:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if mkdir_error != OK: return _failure("Could not create directory", mkdir_error)
	var temporary := path + ".tmp"
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		var current: Dictionary = loader.call(path)
		if not current.ok: return {"ok": false, "error": "Existing save was not overwritten. " + current.error}
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _failure("Could not write temporary save", FileAccess.get_open_error())
	# Full precision: authored coordinates must not drift on every save.
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return _failure("Temporary save failed", write_error)
	var staged: Dictionary = loader.call(temporary)
	if not staged.ok: return {"ok": false, "error": "Temporary save validation failed: " + staged.error}
	var had_previous := FileAccess.file_exists(path)
	if had_previous:
		if FileAccess.file_exists(backup):
			var remove_error := DirAccess.remove_absolute(backup)
			if remove_error != OK: return _failure("Could not replace backup", remove_error)
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK: return _failure("Could not retain previous save", backup_error)
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		if had_previous:
			var restore_error := DirAccess.rename_absolute(backup, path)
			if restore_error != OK: return {"ok": false, "error": "Save replacement failed; recover the previous document from " + backup}
		return _failure("Could not replace save; previous document retained", replace_error)
	return {"ok": true, "path": path}


static func _failure(message: String, code: Error) -> Dictionary:
	return {"ok": false, "error": message + ": " + error_string(code)}
