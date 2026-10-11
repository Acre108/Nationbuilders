class_name EditTileFiles
extends RefCounted

## Location Studio raster sidecars (zone and height tiles) beside
## `<slug>.edits.json`, in `<slug>.edits/`: zstd-compressed raw bytes, named
## by the SHA-256 of those bytes, so a saved tile is never overwritten and an
## undo step only ever swaps paths. See docs/LOCATION_STUDIO.md.


## `<slug>.edits` beside `<slug>.edits.json`.
static func directory_for(edits_path: String) -> String:
	return edits_path.get_basename()


static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().left(12)


## "<folder>/<key>.<sha12>.<extension>"
static func path_for(folder: String, extension: String, key: String, bytes: PackedByteArray) -> String:
	return "%s/%s.%s.%s" % [folder, key, digest(bytes), extension]


static func valid_path(folder: String, extension: String, key: String, path: Variant) -> bool:
	if not path is String: return false
	var text: String = path
	var prefix := folder + "/" + key + "."
	if not text.begins_with(prefix) or not text.ends_with("." + extension): return false
	var sha := text.trim_prefix(prefix).trim_suffix("." + extension)
	return sha.length() == 12 and sha.is_valid_hex_number()


## Writes a tile unless the identical file exists; never overwrites.
static func write(directory: String, path: String, bytes: PackedByteArray) -> String:
	var full := directory.path_join(path)
	if FileAccess.file_exists(full): return ""
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var temporary := full + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Cannot write tile %s: %s" % [full, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	file.close()
	var check := read(temporary, bytes.size())
	if not check.ok or digest(check.bytes) != digest(bytes):
		DirAccess.remove_absolute(temporary)
		return "Tile write failed verification: " + full
	var error := DirAccess.rename_absolute(temporary, full)
	return "" if error == OK else "Cannot publish tile %s: %s" % [full, error_string(error)]


static func read(full: String, expected_bytes: int) -> Dictionary:
	if not FileAccess.file_exists(full): return {"ok": false, "error": "Missing tile: " + full}
	var bytes := FileAccess.get_file_as_bytes(full).decompress(expected_bytes, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != expected_bytes: return {"ok": false, "error": "Tile is corrupt: " + full}
	return {"ok": true, "bytes": bytes}


## Reads every tile of a `tiles` map ({key: path}), preferring `pending`
## ({path: bytes}) for tiles not yet saved, and checks each digest.
static func read_all(tiles: Dictionary, edits_path: String, expected_bytes: int, pending: Dictionary = {}) -> Dictionary:
	var directory := directory_for(edits_path)
	var result := {}
	for key in tiles:
		var path: String = tiles[key]
		var bytes: PackedByteArray
		if pending.has(path): bytes = pending[path]
		else:
			var loaded := read(directory.path_join(path), expected_bytes)
			if not loaded.ok: return loaded
			bytes = loaded.bytes
		if not path.contains("." + digest(bytes) + "."): return {"ok": false, "error": "Tile does not match its digest: " + path}
		result[key] = bytes
	return {"ok": true, "tiles": result}
