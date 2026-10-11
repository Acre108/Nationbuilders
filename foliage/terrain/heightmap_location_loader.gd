class_name HeightmapLocationLoader

## Reads a tools/geo/import_dem.py manifest (<name>.json next to its
## <name>.r32 heightmap) and builds the HeightmapTerrainProvider it
## describes.
##
## Deliberately kept separate from FoliageProfile/TerrainProfile rather than
## widening FoliageProfile.terrain's type: that field's own doc comment
## already says "a scene that supplies its own provider ignores this", so a
## real-world location just leaves profile.terrain null and a caller does
## `location.terrain = HeightmapLocationLoader.load(manifest_path)` before
## add_child() -- the injection point docs/FOLIAGE.md already documents for
## "real elevation data".


## Parses and validates the manifest JSON into a plain Dictionary. Returns {}
## (and logs an error) if the file is missing, malformed, incomplete, or
## references a missing heightmap, so callers fail at the content boundary
## rather than through a null-dereference later in location construction.
static func load_manifest(manifest_path: String) -> Dictionary:
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("HeightmapLocationLoader: cannot open %s (error %s)" % [manifest_path, FileAccess.get_open_error()])
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("HeightmapLocationLoader: %s is not a JSON object" % manifest_path)
		return {}
	if not _validate_manifest(parsed, manifest_path):
		return {}
	return parsed


static func _validate_manifest(manifest: Dictionary, manifest_path: String) -> bool:
	if manifest.get("north_axis", "+Z") not in ["+Z", "-Z"]:
		return _manifest_error(manifest_path, "north_axis must be +Z or -Z")
	var name = manifest.get("name")
	if typeof(name) != TYPE_STRING or String(name).strip_edges().is_empty():
		return _manifest_error(manifest_path, "name must be a non-empty string")

	var centre = manifest.get("centre")
	if typeof(centre) != TYPE_DICTIONARY:
		return _manifest_error(manifest_path, "centre must be an object with lat and lon")
	var lat = centre.get("lat")
	var lon = centre.get("lon")
	if not _finite_number(lat) or float(lat) < -90.0 or float(lat) > 90.0:
		return _manifest_error(manifest_path, "centre.lat must be a finite number in [-90, 90]")
	if not _finite_number(lon) or float(lon) < -180.0 or float(lon) > 180.0:
		return _manifest_error(manifest_path, "centre.lon must be a finite number in [-180, 180]")

	var world_size = manifest.get("world_size")
	if not _finite_number(world_size) or float(world_size) <= 0.0:
		return _manifest_error(manifest_path, "world_size must be a positive finite number")

	var heightmap = manifest.get("heightmap")
	if typeof(heightmap) != TYPE_DICTIONARY:
		return _manifest_error(manifest_path, "heightmap must be an object")
	var heightmap_name = heightmap.get("path")
	if typeof(heightmap_name) != TYPE_STRING or String(heightmap_name).strip_edges().is_empty():
		return _manifest_error(manifest_path, "heightmap.path must be a non-empty string")
	var resolution = heightmap.get("resolution")
	# Godot's JSON parser represents JSON numbers as floats even when their
	# spelling has no decimal point, so validate integer-valued rather than
	# requiring the Variant itself to be TYPE_INT.
	if (
		not _finite_number(resolution)
		or float(resolution) != floorf(float(resolution))
		or int(resolution) <= 0
		or int(resolution) > HeightmapTerrainProvider.MAX_GRID_DIMENSION
	):
		return _manifest_error(
			manifest_path,
			"heightmap.resolution must be an integer in 1..%d" % HeightmapTerrainProvider.MAX_GRID_DIMENSION,
		)

	var heightmap_path := manifest_path.get_base_dir().path_join(String(heightmap_name))
	if not FileAccess.file_exists(heightmap_path):
		return _manifest_error(manifest_path, "referenced heightmap does not exist: %s" % heightmap_path)
	return true


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _manifest_error(manifest_path: String, detail: String) -> bool:
	push_error("HeightmapLocationLoader: %s: %s" % [manifest_path, detail])
	return false


## `manifest_path` is the .json file; the .r32 heightmap it names is resolved
## relative to the manifest's own directory -- both are written side by side
## into content/terrain/heightmaps/ by import_dem.py.
static func load(manifest_path: String) -> HeightmapTerrainProvider:
	var manifest := load_manifest(manifest_path)
	if manifest.is_empty():
		return null

	var heightmap_name: String = manifest["heightmap"]["path"]
	var expected_resolution: int = manifest["heightmap"]["resolution"]
	var world_size: float = float(manifest["world_size"])
	var heightmap_path := manifest_path.get_base_dir().path_join(heightmap_name)
	var provider := HeightmapTerrainProvider.load_from_file(heightmap_path, world_size)
	if provider == null:
		return null
	provider.north_axis = manifest.get("north_axis", "+Z")
	if provider.grid_size() != Vector2i(expected_resolution, expected_resolution):
		push_error(
			"HeightmapLocationLoader: %s declares resolution %d but %s contains a %dx%d grid"
			% [manifest_path, expected_resolution, heightmap_path, provider.grid_size().x, provider.grid_size().y]
		)
		return null
	# Before rivers: they fit their levels to natural_height(), which the sea
	# reshapes at the coast and past the world's edge.
	if manifest.has("sea"):
		var sea: Variant = manifest.sea
		if not sea is Dictionary or not sea.get("path") is String or sea.path.get_file() != sea.path or sea.path.is_empty():
			_manifest_error(manifest_path, "sea.path must be a sidecar filename")
			return null
		provider.imported_sea = ImportedSea.load_file(manifest_path.get_base_dir().path_join(sea.path), sea, world_size, provider.north_axis)
		if provider.imported_sea == null:
			return null
		if provider.imported_sea.tide != null:
			# The tide clock runs on the location's solar time (SeaState).
			provider.imported_sea.tide.longitude = float(manifest.get("centre", {}).get("lon", 0.0))
	if manifest.has("rivers"):
		var rivers: Variant = manifest.rivers
		if not rivers is Dictionary or not rivers.get("path") is String or rivers.path.get_file() != rivers.path or rivers.path.is_empty():
			_manifest_error(manifest_path, "rivers.path must be a sidecar filename")
			return null
		provider.imported_rivers = ImportedRivers.load_file(manifest_path.get_base_dir().path_join(rivers.path), manifest.centre, world_size, provider.north_axis)
		if provider.imported_rivers == null:
			return null
		provider.rivers_source = {"path": manifest_path.get_base_dir().path_join(rivers.path), "centre": manifest.centre, "world_size": world_size}
		provider.imported_rivers.fit_to_terrain(provider.natural_height)
	if manifest.has("site"):
		var site: Variant = manifest.site
		if not site is Dictionary or not site.get("path") is String or site.path.get_file() != site.path or site.path.is_empty():
			_manifest_error(manifest_path, "site.path must be a sidecar filename")
			return null
		provider.imported_site = ImportedSite.load_file(manifest_path.get_base_dir().path_join(site.path), manifest.centre, world_size, provider.north_axis)
		if provider.imported_site == null: return null
	return provider


## The Koppen class code baked into the manifest (e.g. "Cfb"), or "" if this
## location has none. Convenience for a location-build script picking
## FoliageProfile.grass_palette via FoliageProfile.palette_for_koppen().
static func climate_zone(manifest_path: String) -> String:
	var manifest := load_manifest(manifest_path)
	return manifest.get("climate", {}).get("code", "")
