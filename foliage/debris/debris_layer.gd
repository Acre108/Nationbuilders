class_name DebrisLayer
extends Node3D

## The node you add to a location to give it rocks, logs and fallen trees.
## Optional, like GrassLayer and TreeLayer: a location without it has none and
## nothing else needs to know.
##
## Deliberately the simplest of the three layers. Debris does not sway, so it
## needs no wind uniforms; it is not living, so it needs no palette; it is
## cheap (a few dozen triangles) and already opaque geometry, so it casts its
## OWN shadow directly instead of standing in a coarse proxy the way trees do.
## No impostors either: past the point a rock or log is worth billboarding,
## it is small enough on screen that culling it by distance costs nothing
## visible, unlike a tree's silhouette. All of that means one MultiMesh per
## (species, variant) group per chunk -- no canopy/bark/proxy/impostor split
## to track.
##
## Streaming: with `streaming` on, chunks follow the focus point out to
## quality.view_distance, the same radius trees and ground use; placement and
## buffer packing run on WorkerThreadPool through a ChunkStreamer, exactly as
## GrassLayer and TreeLayer do. Off, a fixed square of `chunk_radius` chunks
## round the origin.

signal debris_rebuilt(count: int)

const DEBRIS_SHADER := preload("res://foliage/shaders/debris.gdshader")
const VARIANTS_PER_SPECIES := 3
## How far forest-floor cover is drawn, by GroundCoverScatter category.
## Small things vanish long before trees do; drawing a mushroom 400 m away
## costs triangles nobody can see. Measured from the chunk, so each is
## padded by half a chunk diagonal when applied.
const FLOOR_RANGES := {"moss": 90.0, "litter": 70.0, "stump": 160.0, "mushroom": 30.0, "reed": 140.0, "bush": 220.0,
	"marram": 120.0, "heather": 90.0, "buckthorn": 220.0}

@export var profile: FoliageProfile
@export var quality: FoliageQuality
@export_range(8.0, 256.0, 1.0) var chunk_size: float = 64.0
## Streaming off: chunks out from the origin.
@export_range(0, 16) var chunk_radius: int = 2
@export var streaming: bool = false
@export var defer_first_streaming_build: bool = false

var terrain: TerrainProvider = null

## [species][variant] -> DebrisVariant. species 0 = rock, 1 = deadwood, then
## GroundCoverScatter's moss, litter, stump, mushroom.
var _variants: Array = []
## Visibility range end per species; 0 = whole view distance.
var _ranges: Array = []
var _material: ShaderMaterial

var _streamer: ChunkStreamer
var _chunk_result: Dictionary = {}
var _chunks: Dictionary = {}          ## Vector2i -> Node3D
var _chunk_stats: Dictionary = {}     ## Vector2i -> {trees: 0} shaped like TreeLayer's, count and triangles
var focus_point := Vector3.ZERO
var _focus_chunk := Vector2i(1 << 30, 0)
var _stats_dirty := false

var count: int = 0
var _triangles: int = 0


var exclusions: FoliageExclusions

func _exclusions_changed(area: Rect2) -> void:
	for coord: Vector2i in _chunk_result.keys():
		if Rect2(Vector2(coord)*chunk_size,Vector2.ONE*chunk_size).intersects(area):
			_commit_chunk(coord,0,_chunk_result[coord])

func _ready() -> void:
	if exclusions != null: exclusions.changed.connect(_exclusions_changed)
	rebuild()


func rebuild() -> void:
	if profile == null:
		profile = FoliageProfile.new()
	if quality == null:
		quality = FoliageQuality.create(FoliageQuality.Level.HIGH)
	if terrain == null:
		terrain = NoiseTerrainProvider.new()

	if not profile.enabled or (profile.debris_cover <= 0.0 and profile.woodland_cover() <= 0.0 and not profile.floor_cover_wanted(terrain.has_observed_zones()) and not terrain.paintable()):
		_clear()
		debris_rebuilt.emit(0)
		return

	_build_material()
	_build_variants()

	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit_chunk
		_streamer.release = _release_chunk
	_streamer.job = _make_job()
	_streamer.invalidate()
	_refresh_wanted(true)
	# First build (or fixed mode): block until done. See GrassLayer.rebuild()
	# for why a settings change on an already-streaming layer does not.
	if not streaming or (_streamer.live_count() == 0 and not defer_first_streaming_build):
		_streamer.flush()
	_recount()
	debris_rebuilt.emit(count)


func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh_wanted(false)
	_streamer.update()
	if _stats_dirty:
		_recount()


## Builds everything wanted at `focus_point` now, blocking. (rebuild() is for
## settings changes.)
func flush() -> void:
	if _streamer == null:
		return
	_refresh_wanted(true)
	_streamer.flush()
	_recount()


func pending_chunks() -> int:
	return _streamer.pending_count() if _streamer != null else 0


## Blocks until any in-flight worker build finishes, then frees every chunk.
## See GrassLayer.stop_streaming() for why this has to be synchronous rather
## than left to queue_free().
func stop_streaming() -> void:
	_clear()


func debug_counts() -> Dictionary:
	return {"count": count, "triangles": _triangles}


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = DEBRIS_SHADER
	profile.apply_to_debris_material(_material)


func _build_variants() -> void:
	var rocks: Array[DebrisVariant] = []
	var deadwood: Array[DebrisVariant] = []
	var rock_assets := NatureAssetCatalogue.debris_assets(profile, true)
	var log_assets := NatureAssetCatalogue.debris_assets(profile, false)
	for v in VARIANTS_PER_SPECIES:
		if profile.use_nature_pack:
			var rock_height := 1.0 + v * 0.3 if profile.nature_asset_set == "lake_brienz" else 0.6
			var wood_height: float = NatureAssetCatalogue.DEADWOOD_HEIGHTS.get(log_assets[v], 0.5)
			for entry in [[rock_assets[v], rock_height, rocks, "rock"], [log_assets[v], wood_height, deadwood, "deadwood"]]:
				var variant := DebrisVariant.new()
				variant.species = entry[3]
				variant.source_asset = entry[0]
				variant.mesh = NatureMeshBuilder.build(entry[0], entry[1], profile, true, true)
				variant.triangles = NatureMeshBuilder.triangles(variant.mesh)
				entry[2].append(variant)
		else:
			rocks.append(DebrisBuilder.build_rock(v, profile.world_seed + v * 11))
			deadwood.append(DebrisBuilder.build_deadwood(v, profile.world_seed + 500 + v * 13))
	_variants = [rocks, deadwood]
	_ranges = [0.0, 0.0]
	for category in GroundCoverScatter.CATEGORIES:
		var floor: Array[DebrisVariant] = []
		# Only categories some zone recipe places: unused dune and heath
		# meshes are not built for every location.
		# Paintable ground (Studio S4) needs every category a painted zone uses.
		if (profile.floor_cover_wanted(terrain.has_observed_zones()) or (terrain.paintable() and profile.use_nature_pack)) and profile.floor_category_used(category):
			for asset in NatureAssetCatalogue.floor_assets(profile, category):
				var variant := DebrisVariant.new()
				variant.species = category
				variant.source_asset = asset
				# Near LOD: these are only ever seen up close.
				variant.mesh = NatureMeshBuilder.build(asset, NatureAssetCatalogue.FLOOR_HEIGHTS[asset], profile, false, true)
				variant.triangles = NatureMeshBuilder.triangles(variant.mesh)
				floor.append(variant)
		_variants.append(floor)
		_ranges.append(FLOOR_RANGES[category])


## Painted zones changed inside `area` (Location Studio S4): rebuilds the
## rock, deadwood and floor-cover chunks there.
func rebuild_zone_area(area: Rect2) -> int:
	if _streamer == null: return 0
	_streamer.job = _make_job()
	return _streamer.invalidate_area(area, chunk_size)


func _make_job() -> _Job:
	var job := _Job.new()
	job.params = DebrisPlacer.Params.new()
	job.params.woodland_cover = profile.woodland_cover()
	job.params.woodland_density = profile.woodland_floor_density
	job.params.woodland_spacing = profile.woodland_debris_spacing
	job.params.world_seed = profile.world_seed
	job.params.chunk_size = chunk_size
	job.params.spacing = profile.debris_spacing
	job.params.cover = profile.debris_cover
	job.params.rock_share = profile.debris_rock_share
	job.params.variants_per_species = VARIANTS_PER_SPECIES
	job.params.groves = TreePlacer.grove_noise(profile.world_seed)
	if profile.floor_cover_wanted(terrain.has_observed_zones()) or terrain.has_observed_zones() or terrain.paintable():
		job.params.zones = EnvironmentZones.for_profile(profile, terrain)
		for c in GroundCoverScatter.CATEGORIES.size():
			job.params.floor_variants[c] = _variants[GroundCoverScatter.MOSS + c].size()
	job.terrain = terrain
	return job


class _Job extends RefCounted:
	var params: DebrisPlacer.Params
	var terrain: TerrainProvider

	## Returns {groups: {Vector2i(species, variant) key: [count, buffer]}, count: int}.
	func run(coord: Vector2i, _variant: int) -> Dictionary:
		var placement := DebrisPlacer.place_chunk(coord, params, terrain)
		var origin := Vector3(float(coord.x), 0.0, float(coord.y)) * params.chunk_size
		var groups := {}
		for i in placement.transforms.size():
			var key := Vector2i(placement.species[i], placement.variant[i])
			if not groups.has(key):
				groups[key] = [[], []]
			groups[key][0].append(placement.transforms[i])
			groups[key][1].append(placement.custom[i])
		var packed := {}
		for key in groups:
			var transforms: Array[Transform3D] = []
			transforms.assign(groups[key][0])
			var custom := PackedColorArray(groups[key][1])
			packed[key] = [transforms.size(), FoliageMultiMesh.pack(transforms, custom, origin)]
		return {"groups": packed, "count": placement.transforms.size()}


func _refresh_wanted(force: bool) -> void:
	if not streaming:
		if force:
			var fixed: Array = ChunkStreamer.square(chunk_radius)
			_streamer.set_wanted(fixed[0], fixed[1])
		return
	var here := Vector2i(floori(focus_point.x / chunk_size), floori(focus_point.z / chunk_size))
	if here == _focus_chunk and not force:
		return
	_focus_chunk = here
	var set: Array = ChunkStreamer.disc(focus_point, chunk_size, quality.view_distance)
	_streamer.set_wanted(set[0], set[1])


func _commit_chunk(coord: Vector2i, _variant: int, result: Dictionary) -> void:
	_release_chunk(coord)
	_chunk_result[coord] = result
	if exclusions != null: result = exclusions.filter_result(result,Vector3(coord.x,0,coord.y)*chunk_size,"count",chunk_size)
	if result["count"] == 0:
		return
	var chunk := Node3D.new()
	chunk.name = "Debris_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector3(float(coord.x), 0.0, float(coord.y)) * chunk_size
	add_child(chunk)
	_chunks[coord] = chunk

	var groups: Dictionary = result["groups"]
	var stats := {"count": 0, "triangles": 0}
	for key in groups:
		var variant: DebrisVariant = _variants[key.x][key.y]
		var group_count: int = groups[key][0]
		var buffer: PackedFloat32Array = groups[key][1]
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%d" % [variant.species, key.y]
		instance.multimesh = FoliageMultiMesh.from_buffer(variant.mesh, group_count, buffer)
		instance.material_override = null if profile.use_nature_pack else _material
		# Cheap solid geometry: casts its own shadow rather than standing in
		# a proxy the way trees do (see the class comment).
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.custom_aabb = instance.multimesh.get_aabb().grow(0.5)
		var range_end: float = _ranges[key.x] if key.x < _ranges.size() else 0.0
		if range_end > 0.0:
			instance.visibility_range_end = range_end + chunk_size * 0.71
			instance.visibility_range_end_margin = 8.0
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if key.x in [GroundCoverScatter.MOSS, GroundCoverScatter.MUSHROOM, GroundCoverScatter.REED, GroundCoverScatter.MARRAM, GroundCoverScatter.HEATHER]:
			# Flat or tiny: their shadows are invisible but not free.
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(instance)

		stats["count"] += group_count
		stats["triangles"] += group_count * variant.triangles

	_chunk_stats[coord] = stats
	_stats_dirty = true


func _release_chunk(coord: Vector2i) -> void:
	_chunk_result.erase(coord)
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_chunks.erase(coord)
	if _chunk_stats.erase(coord):
		_stats_dirty = true


func _recount() -> void:
	_stats_dirty = false
	count = 0
	_triangles = 0
	for stats in _chunk_stats.values():
		count += stats["count"]
		_triangles += stats["triangles"]


func _clear() -> void:
	if _streamer != null:
		_streamer.clear()
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()
	_chunk_result.clear()
	_chunk_stats.clear()
	count = 0
	_triangles = 0


func _exit_tree() -> void:
	if exclusions != null and exclusions.changed.is_connected(_exclusions_changed): exclusions.changed.disconnect(_exclusions_changed)
	if _streamer != null:
		_streamer.clear()
