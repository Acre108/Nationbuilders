@tool
class_name GrassLayer
extends Node3D

## The node you add to a location to give it grass.
##
## Part 3 of the brief: indoor locations skip this system entirely by simply not
## having this node (or by setting the profile's `enabled` to false). Nothing
## else in the scene needs to know whether a place has grass.
##
## Chunks are drawn in a near and a far band (see GrassChunk), with furniture
## carved out of them. With `streaming` on they follow a focus point (the
## camera, fed in by FoliageLocation via update_streaming()) out to
## FoliageQuality.streaming_radius; placement and buffer packing run on
## WorkerThreadPool through a ChunkStreamer and only MultiMesh creation touches
## the main thread. With it off, a fixed square of `chunk_radius` chunks round
## the origin -- what the self-tests use.
##
## Carving: every chunk keeps its UNCARVED scatter. A carve filters that cached
## result and refills only the chunks the footprint overlaps -- no terrain
## sampling, no re-placement. Carvers survive a full rebuild (a quality change
## does not bring grass back under the furniture).

signal chunks_rebuilt(chunk_count: int, grass_instances: int, flower_instances: int)
## After a carve, move or uncarve: how many chunks it refilled and how long it
## took on the main thread.
signal area_rebuilt(chunk_count: int, msec: float)

const GRASS_SHADER := preload("res://foliage/shaders/grass.gdshader")
const TERRAIN_SHADER := preload("res://foliage/shaders/terrain.gdshader")

@export var profile: FoliageProfile:
	set(value):
		profile = value
		if is_inside_tree():
			rebuild()

## World units per chunk. Smaller chunks cull more tightly but cost one more
## draw call each; 16 m is a reasonable middle for player-scale outdoor space.
@export_range(4.0, 64.0, 1.0) var chunk_size: float = 16.0

## With streaming off: how many chunks out from the origin to build.
@export_range(1, 24) var chunk_radius: int = 6

## Follow the focus point out to quality.streaming_radius, instead of the fixed
## square.
@export var streaming: bool = false
@export var defer_first_streaming_build: bool = false

@export var quality: FoliageQuality = null

## Off draws every tuft with the full mesh at every distance. For A/B
## comparisons and for the coverage test, which is about close-range density
## and must not be confounded by distant thinning.
@export var lod_enabled: bool = true

## Assigned by the location (or the test scene) before the first build.
var terrain: TerrainProvider = null

## Where carve requests come from. Grass never needs to know who placed what,
## or whether the event arrived over the network.
var placement_events: FoliagePlacementEvents:
	set(value):
		if placement_events != null:
			placement_events.placed.disconnect(carve)
			placement_events.removed.disconnect(uncarve)
		placement_events = value
		if placement_events != null:
			placement_events.placed.connect(carve)
			placement_events.removed.connect(uncarve)

var _chunks: Dictionary = {}          ## Vector2i -> GrassChunk
var _streamer: ChunkStreamer
var focus_point := Vector3.ZERO
var _focus_chunk := Vector2i(1 << 30, 0)
var _counts_dirty := false
var _raw: Dictionary = {}             ## Vector2i -> GrassPlacer.PlacementResult, uncarved
var _carvers: Dictionary = {}         ## StringName -> Array[GrassCarver]
var _style: GrassChunk.Style

var _grass_material: ShaderMaterial
var _flower_material: ShaderMaterial
var _far_grass_material: ShaderMaterial
var _far_flower_material: ShaderMaterial
## Materials made per extra mesh (tall grass, each flower set), copied from the
## four above after their uniforms are set, so they share palette, wind and
## LOD values. Listed so debug toggles reach them too.
var _extra_materials: Array[ShaderMaterial] = []
var _meadow: MeadowPatches
var _terrain_material: ShaderMaterial

## Triangles per instance of each band's mesh, cached at build so the HUD can
## ask every frame without pulling mesh arrays back from the GPU side.
var _tris := {"near_grass": 0, "near_tall": 0, "near_flower": 0, "far_grass": 0, "far_flower": 0}

var last_grass_instances: int = 0
var last_flower_instances: int = 0
var last_tall_instances: int = 0


func _ready() -> void:
	if terrain == null:
		terrain = NoiseTerrainProvider.new()
	rebuild()


## Full rebuild: re-places every chunk. Needed on any settings change; carving
## goes through rebuild_area() instead and never comes here.
func rebuild() -> void:
	if profile == null:
		profile = FoliageProfile.new()
	if terrain == null:
		terrain = NoiseTerrainProvider.new()
	if quality == null:
		quality = FoliageQuality.create(FoliageQuality.Level.HIGH)

	if not profile.enabled:
		_clear()
		chunks_rebuilt.emit(0, 0, 0)
		return

	_build_materials()
	_build_meshes()
	_build_style()

	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit_chunk
		_streamer.release = _release_chunk
	# A fresh job per rebuild: in-flight builds keep the settings they started
	# with and are discarded as stale, never mixed with the new ones.
	var job := _Job.new()
	job.params = _placement_params()
	job.style = _style
	job.terrain = terrain
	_streamer.job = job
	_streamer.invalidate()
	_refresh_wanted(true)
	# First build (or fixed mode): block until done. A settings change on a
	# layer that is already streaming does NOT block: every chunk is marked
	# stale, stays visible, and is replaced within the per-frame budget. A
	# blocking rebuild of a full streamed radius took 2.8 s at High and 10.7 s
	# at Ultra -- far too long to freeze a game on a settings change.
	if not streaming or (_streamer.live_count() == 0 and not defer_first_streaming_build):
		_streamer.flush()

	_recount()
	chunks_rebuilt.emit(_chunks.size(), last_grass_instances, last_flower_instances)


## Streaming tick: call once a frame with the camera position. Frees chunks
## that fell out of range, commits finished ones within the streamer's time
## budget, and queues new ones nearest first.
func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh_wanted(false)
	_streamer.update()
	if _counts_dirty:
		_recount()


## Builds everything wanted at `focus_point` now, blocking, without rebuilding
## materials or anything else. (rebuild() is for settings changes.)
func flush() -> void:
	if _streamer == null:
		return
	_refresh_wanted(true)
	_streamer.flush()
	_recount()


## Chunks wanted but not yet built, for the HUD and for tests that wait for
## streaming to settle.
func pending_chunks() -> int:
	return _streamer.pending_count() if _streamer != null else 0


## Blocks until any in-flight worker build finishes, then frees every chunk.
## Call this before mutating state a background build might still be reading
## -- a caller-supplied TerrainProvider's painted mask, in particular -- and
## before relying on `terrain` being unused. `queue_free()` on this node alone
## is not enough: it only defers freeing to the end of the frame, so a build()
## right after could still race a worker that has not been told to stop.
func stop_streaming() -> void:
	_clear()


func _refresh_wanted(force: bool) -> void:
	if not streaming:
		if force:
			var fixed: Array = ChunkStreamer.square(chunk_radius)
			_streamer.set_wanted(fixed[0], fixed[1])
		return
	# Recomputed only when the focus crosses into another chunk.
	var here := Vector2i(floori(focus_point.x / chunk_size), floori(focus_point.z / chunk_size))
	if here == _focus_chunk and not force:
		return
	_focus_chunk = here
	var set: Array = ChunkStreamer.disc(focus_point, chunk_size, quality.streaming_radius)
	_streamer.set_wanted(set[0], set[1])


## The worker half of a chunk: placement, plus buffers packed for the
## uncarved case. Holds its own references to settings, so a rebuild on the
## main thread cannot change them underneath a running build.
class _Job extends RefCounted:
	var params: GrassPlacer.PlacementParams
	var style: GrassChunk.Style
	var terrain: TerrainProvider

	func run(coord: Vector2i, _variant: int) -> Array:
		var raw := GrassPlacer.place_chunk(coord, params, terrain)
		if raw.total() == 0:
			return [raw, null]
		var origin := Vector3(float(coord.x) * params.chunk_size, 0.0, float(coord.y) * params.chunk_size)
		return [raw, GrassChunk.prepare(raw, style, origin)]


func _commit_chunk(coord: Vector2i, _variant: int, result: Array) -> void:
	var raw: GrassPlacer.PlacementResult = result[0]
	_counts_dirty = true
	if raw.total() == 0:
		_release_chunk(coord)
		return
	_raw[coord] = raw
	var carvers := _carvers_for(coord)
	if not carvers.is_empty():
		# Carved since (or before) the build was queued: carving is main-thread
		# state, so filter and pack here rather than trust the worker's buffers.
		_fill_chunk(coord)
		return
	_chunk_node(coord).apply_prepared(result[1], raw, _style)


func _release_chunk(coord: Vector2i) -> void:
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_chunks.erase(coord)
	_raw.erase(coord)
	_counts_dirty = true


func _chunk_node(coord: Vector2i) -> GrassChunk:
	var chunk: GrassChunk = _chunks.get(coord)
	if chunk == null:
		chunk = GrassChunk.new()
		chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
		chunk.setup(coord, chunk_size)
		add_child(chunk)
		_chunks[coord] = chunk
	return chunk


## Clears grass under `footprints`, registered as `object_id`. Calling again
## with the same id moves it: old and new footprints are refilled together.
##
## Prefer emitting through `placement_events` over calling this directly --
## that bus is where networked placement will attach.
func carve(object_id: StringName, footprints: Array[GrassCarver]) -> void:
	var area := _area_of(footprints)
	if _carvers.has(object_id):
		area = _merge(area, _area_of(_carvers[object_id]))
	_carvers[object_id] = footprints
	rebuild_area(area)


## Lets grass grow back where `object_id` was.
func uncarve(object_id: StringName) -> void:
	if not _carvers.has(object_id):
		return
	var area := _area_of(_carvers[object_id])
	_carvers.erase(object_id)
	rebuild_area(area)


func has_carver(object_id: StringName) -> bool:
	return _carvers.has(object_id)


## Refills every built chunk overlapping `area` (world XZ) from its cached
## scatter and the current carvers. Returns how many chunks it touched; chunks
## outside the area are not visited at all.
func rebuild_area(area: Rect2) -> int:
	if _style == null or not area.has_area():
		return 0
	var started := Time.get_ticks_usec()
	var first := Vector2i((area.position / chunk_size).floor())
	var last := Vector2i((area.end / chunk_size).floor())
	var touched := 0
	for cz in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var coord := Vector2i(cx, cz)
			if _raw.has(coord):
				_fill_chunk(coord)
				touched += 1
	_recount()
	area_rebuilt.emit(touched, (Time.get_ticks_usec() - started) / 1000.0)
	return touched


## Painted zones changed inside `area` (Location Studio S4): re-places the
## grass chunks there with a fresh job; the old chunks stay up until their
## replacements commit.
func rebuild_zone_area(area: Rect2) -> int:
	if _streamer == null: return 0
	var job := _Job.new()
	job.params = _placement_params()
	job.style = _style
	job.terrain = terrain
	_streamer.job = job
	return _streamer.invalidate_area(area, chunk_size)


## The terrain material, so the location can put the SAME material on its ground
## mesh. Handing it out from here rather than letting the caller build one is
## what guarantees grass and terrain share their palette and wind values.
func get_terrain_material() -> ShaderMaterial:
	if _terrain_material == null:
		_build_materials()
	return _terrain_material


func get_grass_material() -> ShaderMaterial:
	if _grass_material == null:
		_build_materials()
	return _grass_material


## Chunk node at `coord`, or null. For tests and debug tools.
func get_chunk(coord: Vector2i) -> GrassChunk:
	return _chunks.get(coord)


func chunk_coords() -> Array:
	return _chunks.keys()


## The uncarved scatter cached for `coord`, or null.
func get_uncarved(coord: Vector2i) -> GrassPlacer.PlacementResult:
	return _raw.get(coord)


## What `coord` shows right now: its cached scatter minus current carvers.
func get_carved(coord: Vector2i) -> GrassPlacer.PlacementResult:
	if not _raw.has(coord):
		return null
	return GrassPlacer.filter_carved(_raw[coord], _carvers_for(coord))


func _fill_chunk(coord: Vector2i) -> void:
	var shown := GrassPlacer.filter_carved(_raw[coord], _carvers_for(coord))
	_chunk_node(coord).apply(shown, _style)


func _carvers_for(coord: Vector2i) -> Array[GrassCarver]:
	var bounds := GrassPlacer.chunk_bounds(coord, chunk_size)
	var out: Array[GrassCarver] = []
	for footprints in _carvers.values():
		for carver in footprints:
			if carver.bounds().intersects(bounds):
				out.append(carver)
	return out


func _area_of(footprints: Array[GrassCarver]) -> Rect2:
	var area := Rect2()
	for carver in footprints:
		area = _merge(area, carver.bounds())
	return area


static func _merge(a: Rect2, b: Rect2) -> Rect2:
	if not a.has_area():
		return b
	if not b.has_area():
		return a
	return a.merge(b)


func _build_materials() -> void:
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER

	_flower_material = ShaderMaterial.new()
	_flower_material.shader = GRASS_SHADER

	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER

	profile.apply_to_materials(_grass_material, _terrain_material, _flower_material)

	# The far band is the same material with different LOD uniforms. Copied
	# AFTER apply_to_materials(), so it cannot miss a palette or wind value --
	# the far band is exactly where a mismatch against the terrain would show.
	_far_grass_material = _grass_material.duplicate()
	_far_flower_material = _flower_material.duplicate()
	_apply_lod_uniforms()


func _apply_lod_uniforms() -> void:
	var q := quality if quality != null else FoliageQuality.create(FoliageQuality.Level.HIGH)
	# Drawing a keep-fraction of the tufts at 1/sqrt(keep) width covers the same
	# ground area. Capped because very wide cards visibly smear the sprite.
	var widen := minf(1.0 / sqrt(maxf(q.lod_far_keep, 0.01)), 1.8)
	var bands := [
		[_grass_material, 1, widen],
		[_flower_material, 1, 1.0],
		[_far_grass_material, 2, widen],
		# Flowers are not widened: a stretched bloom reads as a smear, and a
		# thinner scatter of blooms at range is what a meadow looks like anyway.
		[_far_flower_material, 2, 1.0],
	]
	for entry in bands:
		var material: ShaderMaterial = entry[0]
		material.set_shader_parameter("grass_lod_band", entry[1] if lod_enabled else 0)
		material.set_shader_parameter("grass_lod_near_end", q.lod_near_end)
		material.set_shader_parameter("grass_lod_far_end", q.lod_far_end)
		material.set_shader_parameter("grass_lod_fade", q.lod_fade)
		material.set_shader_parameter("grass_lod_far_keep", q.lod_far_keep)
		material.set_shader_parameter("grass_lod_far_widen", entry[2])
		material.set_shader_parameter("grass_lod_swap_span", _swap_span(q))


static func _swap_span(q: FoliageQuality) -> float:
	return clampf(q.lod_fade * 0.25, 0.5, 3.0)


## Tints the far band so the handover distance can be seen. Debug only.
func set_lod_debug(enabled: bool) -> void:
	for material in [_grass_material, _flower_material, _far_grass_material, _far_flower_material] + _extra_materials:
		if material != null:
			material.set_shader_parameter("grass_lod_debug", enabled)


func _build_meshes() -> void:
	if profile.use_nature_pack:
		_build_nature_meshes()
		return
	var near_grass: Mesh
	var far_grass: Mesh

	if profile.clump_style == FoliageProfile.ClumpStyle.SPRITE_CARDS:
		var card := GrassCardBuilder.CardConfig.new()
		card.height = profile.tuft_height
		card.segments = quality.blade_segments
		# Quads scale with quality, but never below 2 -- a single quad is
		# invisible edge-on and the field visibly flickers as you turn.
		card.quad_count = clampi(quality.blades_per_tuft / 4, 2, 4)
		near_grass = GrassCardBuilder.build_card(card, profile.world_seed)

		# Far band: the minimum that still reads from every angle. One segment
		# means wind shears the card rigidly instead of curving it, which
		# nobody can see at 30 m and beyond.
		var far_card := card.copy()
		far_card.quad_count = 2
		far_card.segments = 1
		far_grass = GrassCardBuilder.build_card(far_card, profile.world_seed)
	else:
		var config := GrassTuftBuilder.TuftConfig.dome_clump()
		if profile.clump_style == FoliageProfile.ClumpStyle.BLADE_FLAT:
			config = GrassTuftBuilder.TuftConfig.flat_meadow()
		config.height = profile.tuft_height
		config.blade_count = quality.blades_per_tuft
		config.segments = quality.blade_segments
		near_grass = GrassTuftBuilder.build_tuft(config, profile.world_seed)

		var far_config := config.copy()
		far_config.blade_count = maxi(3, quality.blades_per_tuft / 3)
		far_config.segments = 1
		far_grass = GrassTuftBuilder.build_tuft(far_config, profile.world_seed)

	# Flowers always use blade geometry, whatever the grass is drawn with: a
	# bloom is a modelled head on a stem, not a sprite.
	var near_flower: Mesh = null
	var far_flower: Mesh = null
	if profile.flower_chance > 0.0:
		var flower_config := GrassTuftBuilder.TuftConfig.flat_meadow()
		flower_config.segments = quality.blade_segments
		flower_config.blade_count = quality.blades_per_tuft
		flower_config.height = profile.tuft_height * 1.15
		near_flower = GrassTuftBuilder.build_flower(flower_config, 5, 0.038, profile.world_seed)

		var far_flower_config := flower_config.copy()
		far_flower_config.blade_count = maxi(2, quality.blades_per_tuft / 3)
		far_flower_config.segments = 1
		far_flower = GrassTuftBuilder.build_flower(far_flower_config, 5, 0.038, profile.world_seed)

	_tris["near_grass"] = _triangles(near_grass)
	_tris["far_grass"] = _triangles(far_grass)
	_tris["near_flower"] = _triangles(near_flower)
	_tris["far_flower"] = _triangles(far_flower)

	_style = GrassChunk.Style.new()
	_style.near_grass_mesh = near_grass
	_style.far_grass_mesh = far_grass
	if near_flower != null:
		_style.flower_sets = [[near_flower, far_flower, _flower_material, _far_flower_material]]


func _build_nature_meshes() -> void:
	_style = GrassChunk.Style.new()
	_extra_materials.clear()
	_style.near_grass_mesh = NatureMeshBuilder.build(NatureAssetCatalogue.grass_asset(profile), profile.tuft_height, profile)
	_style.far_grass_mesh = NatureMeshBuilder.build(NatureAssetCatalogue.grass_asset(profile, true), profile.tuft_height, profile, true)
	_bind_nature(_style.near_grass_mesh, _grass_material, true)
	_bind_nature(_style.far_grass_mesh, _far_grass_material, true)
	_tris["near_grass"] = NatureMeshBuilder.triangles(_style.near_grass_mesh)
	_tris["far_grass"] = NatureMeshBuilder.triangles(_style.far_grass_mesh)
	_tris["near_tall"] = 0
	_tris["near_flower"] = 0
	_tris["far_flower"] = 0

	# Meadow variety (Z4): tall grass in lush patches, flowers in drifts of
	# one kind. Each extra mesh needs its own material for its texture.
	_meadow = MeadowPatches.for_profile(profile)
	if _meadow != null and terrain != null and (terrain.has_observed_zones() or terrain.paintable()):
		_meadow.zones = EnvironmentZones.for_profile(profile, terrain)
	_style.meadow = _meadow
	# Before any copy is made, so the tall-grass material inherits it.
	var contrast := _meadow.patch_contrast() if _meadow != null else 0.0
	_grass_material.set_shader_parameter("grass_patch_contrast", contrast)
	_far_grass_material.set_shader_parameter("grass_patch_contrast", contrast)
	var tall_asset := NatureAssetCatalogue.tall_grass_asset(profile) if _meadow != null and _meadow.tall_share > 0.0 else ""
	if not tall_asset.is_empty():
		_style.near_tall_mesh = NatureMeshBuilder.build(tall_asset, profile.tuft_height * 1.5, profile)
		_style.near_tall_material = _extra(_grass_material, _style.near_tall_mesh, true)
		_tris["near_tall"] = NatureMeshBuilder.triangles(_style.near_tall_mesh)

	if profile.flower_chance > 0.0:
		# Without meadow variety, the one dense flower clump as before.
		var assets: Array = NatureAssetCatalogue.meadow_flowers(profile) if _meadow != null else ["flowers"]
		for asset in assets:
			var height := profile.tuft_height * (1.15 if asset == "flowers" else 1.3)
			var near := NatureMeshBuilder.build(asset, height, profile)
			var far := NatureMeshBuilder.build(asset, height, profile, true)
			if _style.flower_sets.is_empty():
				# The first set uses the layer's own flower materials.
				_bind_nature(near, _flower_material, false)
				_bind_nature(far, _far_flower_material, false)
				_style.flower_sets.append([near, far, _flower_material, _far_flower_material])
			else:
				_style.flower_sets.append([near, far, _extra(_flower_material, near, false), _extra(_far_flower_material, far, false)])
			_tris["near_flower"] = maxi(_tris["near_flower"], NatureMeshBuilder.triangles(near))
			_tris["far_flower"] = maxi(_tris["far_flower"], NatureMeshBuilder.triangles(far))


## Points a grass-shader material at a nature-pack mesh's texture.
func _bind_nature(mesh: Mesh, material: ShaderMaterial, grass: bool) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var source := mesh.surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("nature_pack_mode", true)
	material.set_shader_parameter("grass_sprite_mode", false)
	material.set_shader_parameter("nature_texture", source.get_shader_parameter("nature_texture"))
	material.set_shader_parameter("nature_colour", source.get_shader_parameter("nature_colour"))
	material.set_shader_parameter("nature_palette_tint", 1.0 if grass else 0.0)
	if grass:
		material.set_shader_parameter("nature_mean_colour", NatureMeshBuilder.mean_colour(
			source.get_shader_parameter("nature_texture"), source.get_shader_parameter("nature_colour")))


## A copy of `base` (palette, wind and LOD uniforms already set) bound to
## `mesh`'s texture.
func _extra(base: ShaderMaterial, mesh: Mesh, grass: bool) -> ShaderMaterial:
	var material := base.duplicate() as ShaderMaterial
	_bind_nature(mesh, material, grass)
	_extra_materials.append(material)
	return material


func _build_style() -> void:
	_style.chunk_size = chunk_size
	_style.padding = profile.tuft_height + profile.wind_strength + 0.5
	_style.near_grass_material = _grass_material
	_style.far_grass_material = _far_grass_material
	_style.lod_enabled = lod_enabled
	_style.far_keep = quality.lod_far_keep
	_style.near_end = quality.lod_near_end
	_style.far_end = quality.lod_far_end
	_style.swap_span = _swap_span(quality)


func _placement_params() -> GrassPlacer.PlacementParams:
	var params := GrassPlacer.PlacementParams.new()
	params.world_seed = profile.world_seed
	params.chunk_size = chunk_size
	params.density = profile.base_density * quality.density_scale
	params.flower_chance = profile.flower_chance
	params.slope_align = profile.slope_align
	var zones := EnvironmentZones.for_profile(profile, terrain)
	# Paintable ground keeps zones live: a painted zone's recipe can apply
	# where every unpainted zone's grass is neutral.
	params.zones = null if zones.grass_neutral() and not terrain.paintable() else zones
	params.meadow = MeadowPatches.for_profile(profile) if profile.use_nature_pack else null
	if params.meadow != null and (zones.observed or terrain.paintable()):
		params.meadow.zones = zones
	return params


func _clear() -> void:
	if _streamer != null:
		_streamer.clear()
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()
	_raw.clear()
	last_grass_instances = 0
	last_flower_instances = 0
	last_tall_instances = 0


func _exit_tree() -> void:
	# No worker may still be writing into this layer once it leaves the tree.
	if _streamer != null:
		_streamer.clear()


func _recount() -> void:
	_counts_dirty = false
	last_grass_instances = 0
	last_flower_instances = 0
	last_tall_instances = 0
	for chunk in _chunks.values():
		last_grass_instances += chunk.grass_count
		last_flower_instances += chunk.flower_count
		last_tall_instances += chunk.tall_count


## Counts for the debug overlay and the benchmark.
##
## `grass`, `flowers` and the `triangles_*` pair are totals held by the layer
## (the near band holds every tuft). Given a camera position, it also reports
## what each band is actually submitting to the renderer from there -- instances
## whose chunk passes that band's visibility range. That is the number that
## costs vertex work; the frustum then culls further.
func debug_counts(camera: Variant = null) -> Dictionary:
	var counts := {
		"chunks": _chunks.size(),
		"grass": last_grass_instances,
		"flowers": last_flower_instances,
		"triangles_grass": (last_grass_instances - last_tall_instances) * _tris["near_grass"] + last_tall_instances * _tris["near_tall"],
		"tall_grass": last_tall_instances,
		"triangles_flowers": last_flower_instances * _tris["near_flower"],
		"carvers": _carvers.size(),
	}
	if camera is Vector3:
		var near := Vector2i.ZERO
		var far := Vector2i.ZERO
		for chunk in _chunks.values():
			near += chunk.in_range_near(camera)
			far += chunk.in_range_far(camera)
		counts["near_in_range"] = near.x + near.y
		counts["far_in_range"] = far.x + far.y
		counts["triangles_in_range"] = (
			near.x * _tris["near_grass"] + near.y * _tris["near_flower"]
			+ far.x * _tris["far_grass"] + far.y * _tris["far_flower"]
		)
	return counts


func _triangles(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3
	return total
