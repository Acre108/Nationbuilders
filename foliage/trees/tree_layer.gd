class_name TreeLayer
extends Node3D

## The node you add to a location to give it trees, shrubs, conifers, fir,
## ferns AND alpine cushion plants. Optional, like GrassLayer: a location
## without any of the six has none and nothing else needs to know. All six
## are the same mechanism at different sizes -- nine species in all (oak,
## birch, rounded-shrub, low-hedge, spruce, pine, fir, fern, alpine-cushion),
## placed by TreePlacer as six independent families (see its class comment),
## rendered from POLY Nature Pack models by default. The procedural builders
## remain available for profiles with use_nature_pack disabled. The
## species list itself comes from FoliageFamily.all_species(), the single
## registry an importer also reads to guess a starting cover per Koppen
## climate group (see its class comment) -- TreeLayer never hand-lists
## species itself.
## Broadleaf and needle masses share a paint atlas but use separate palettes;
## ferns and cushion plants retain their sprite atlases. `profile.shrub_cover`,
## `profile.tree_cover`, `profile.conifer_cover`, `profile.fir_cover`,
## `profile.fern_cover` and `profile.cushion_cover` are independent: a
## location can have any of the six without the others.
##
## Per chunk, plants are grouped by (species, variant) and each group is
## three MultiMeshes -- canopy, bark, shadow proxy -- plus ONE impostor
## MultiMesh for every plant in the chunk (all variants share one impostor
## atlas, so distant trees AND shrubs together cost one draw call per chunk).
##
## Distance: full trees out to FoliageQuality.tree_impostor_distance, then a
## dithered handover (tree_lod.gdshaderinc) to impostors, which run out to
## view_distance. Impostors are baked at runtime by TreeImpostorBaker, once the
## variants exist; until the bake lands -- and always under --headless, where
## there is nothing to bake with -- full trees draw at every distance. When a
## bake lands, every chunk on screen is redrawn in the same call, from data
## already in hand (see _bake_impostors()): the materials that decide the
## fade are shared across all chunks, so a chunk left un-redrawn would have
## its full trees fading into nothing rather than into an impostor.
##
## Shadows come ONLY from the proxies. The visible canopy and bark never cast:
## a card canopy's own shadow is hundreds of alpha-tested cards in every
## cascade, the most expensive and noisiest option. A nature-pack tree's
## proxy is its own model's far LOD (NatureMeshBuilder.tree()), so its shadow
## matches the tree drawn. The proxy's visibility range is
## tree_shadow_distance, so beyond it trees stop casting.
##
## Streaming: with `streaming` on, chunks follow the focus point out to
## quality.view_distance; placement and buffer packing run on WorkerThreadPool.
## Off, a fixed square of `chunk_radius` chunks round the origin.

signal trees_rebuilt(tree_count: int)
signal impostors_ready

const LEAF_SHADER := preload("res://foliage/shaders/tree_leaf.gdshader")
const BARK_SHADER := preload("res://foliage/shaders/tree_bark.gdshader")
const IMPOSTOR_SHADER := preload("res://foliage/shaders/tree_impostor.gdshader")
const PAINTED_SHADER := preload("res://foliage/shaders/tree_painted.gdshader")
const PAINT_ATLAS := preload("res://assets/foliage/legacy/tree_paint.svg")
const VARIANTS_PER_SPECIES := 3
## Regrowth (young trees, species 9) is understorey: hidden under the canopy
## from afar, so it draws only near the camera and never becomes impostors.
const REGROWTH_SPECIES := 9
const REGROWTH_RANGE := 80.0
const REGROWTH_SHADOW_RANGE := 40.0
## Width of the full-tree -> impostor dither band, metres.
const IMPOSTOR_BAND := 12.0

@export var profile: FoliageProfile
@export var quality: FoliageQuality
@export_range(8.0, 256.0, 1.0) var chunk_size: float = 64.0
## Streaming off: chunks out from the origin.
@export_range(0, 16) var chunk_radius: int = 2
@export var streaming: bool = false
@export var defer_first_streaming_build: bool = false
## Bake and use impostors when a renderer is available.
@export var impostors_enabled: bool = true
## Only the art regression scene enables the former woody card geometry.
## Not exported: the archived art comparison opts into the former cards.
var legacy_cards_for_comparison: bool = false

var terrain: TerrainProvider = null

var _species: Array[TreeCardBuilder.Species] = []
## [species] -> Array[TreeVariant]
var _variants: Array = []
## Impostor atlas rows, in order: Vector2i(species, variant).
var _rows: Array[Vector2i] = []
var _leaf_broadleaf: ShaderMaterial
var _leaf_needles: ShaderMaterial
var _leaf_ferns: ShaderMaterial
var _leaf_cushion: ShaderMaterial
var _bark: ShaderMaterial
## Shadow proxies: the bark material without the impostor handover, which in
## the shadow pass would measure distance from the light and discard them.
var _proxy: ShaderMaterial
var _impostor: ShaderMaterial
var _impostors_ready := false
var _bake_serial := 0

var _streamer: ChunkStreamer
var _chunks: Dictionary = {}          ## Vector2i -> Node3D
var _chunk_stats: Dictionary = {}     ## Vector2i -> {trees, triangles, proxy_triangles}
## Vector2i -> the Dictionary _commit_chunk() built that chunk from. Kept so
## an impostor bake landing can redraw every live chunk from data already in
## hand -- see _bake_impostors().
var _chunk_result: Dictionary = {}
var focus_point := Vector3.ZERO
var _focus_chunk := Vector2i(1 << 30, 0)
var _stats_dirty := false

var tree_count: int = 0
var _stats: Dictionary = {}


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

	if not profile.enabled or (
		profile.tree_cover <= 0.0 and profile.shrub_cover <= 0.0 and profile.conifer_cover <= 0.0
		and profile.fir_cover <= 0.0 and profile.fern_cover <= 0.0 and profile.cushion_cover <= 0.0
		and not terrain.paintable()
	):
		_clear()
		trees_rebuilt.emit(0)
		return

	_build_materials()
	_build_variants()
	# New variants (canopy detail follows quality) need a new bake; until it
	# lands, full trees draw everywhere.
	_impostors_ready = false

	if _streamer == null:
		_streamer = ChunkStreamer.new()
		_streamer.commit = _commit_chunk
		_streamer.release = _release_chunk
	_streamer.job = _make_job()
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
	trees_rebuilt.emit(tree_count)

	if impostors_enabled and DisplayServer.get_name() != "headless":
		_bake_impostors()


func update_streaming(focus: Vector3) -> void:
	if _streamer == null or not streaming:
		return
	focus_point = focus
	_refresh_wanted(false)
	_streamer.update()
	if _stats_dirty:
		_recount()


## Builds everything wanted at `focus_point` now, blocking, without rebuilding
## materials or anything else. (rebuild() is for settings changes.)
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


func has_impostors() -> bool:
	return _impostors_ready


## A single variant, for tools that want to show one tree on its own (the
## test scene's lineup). Builds materials and variants if needed.
func get_variant(species_index: int, variant_index: int) -> TreeVariant:
	if _variants.is_empty():
		_build_materials()
		_build_variants()
	return _variants[species_index][variant_index]


## Conifers, ferns and cushion plants each draw from their own atlas rather
## than the broadleaf leaf atlas.
func leaf_material_for(species_index: int) -> ShaderMaterial:
	if species_index >= 0 and species_index < _species.size():
		var species := _species[species_index]
		if species.is_conifer:
			return _leaf_needles
		if species.is_fern:
			return _leaf_ferns
		if species.is_cushion:
			return _leaf_cushion
	return _leaf_broadleaf


func bark_material() -> ShaderMaterial:
	return _bark


func proxy_material() -> ShaderMaterial:
	return _proxy


func impostor_material() -> ShaderMaterial:
	return _impostor


## Applies the full-tree <-> impostor handover to every material that draws a
## visible plant. Kept as one operation so a newly added leaf family cannot
## silently remain fully visible on top of its impostor through the band.
func _set_impostor_transition(start: float, band: float) -> void:
	for material in [
		_leaf_broadleaf, _leaf_needles, _leaf_ferns, _leaf_cushion, _bark, _impostor,
	]:
		material.set_shader_parameter("tree_impostor_start", start)
		material.set_shader_parameter("tree_impostor_band", band)
	if profile.use_nature_pack and not legacy_cards_for_comparison:
		for variants in _variants:
			for variant: TreeVariant in variants:
				for surface in variant.canopy_mesh.get_surface_count():
					var material := variant.canopy_mesh.surface_get_material(surface) as ShaderMaterial
					material.set_shader_parameter("tree_impostor_start", start)
					material.set_shader_parameter("tree_impostor_band", band)


func debug_counts() -> Dictionary:
	return {
		"trees": tree_count,
		"triangles": _stats.get("triangles", 0),
		"proxy_triangles": _stats.get("proxy_triangles", 0),
		"impostors": _impostors_ready,
	}


func _build_materials() -> void:
	_leaf_broadleaf = ShaderMaterial.new()
	_leaf_broadleaf.shader = LEAF_SHADER if legacy_cards_for_comparison else PAINTED_SHADER
	_bark = ShaderMaterial.new()
	_bark.shader = BARK_SHADER
	_leaf_needles = ShaderMaterial.new()
	_leaf_needles.shader = LEAF_SHADER if legacy_cards_for_comparison else PAINTED_SHADER
	_leaf_ferns = ShaderMaterial.new()
	_leaf_ferns.shader = LEAF_SHADER
	_leaf_cushion = ShaderMaterial.new()
	_leaf_cushion.shader = LEAF_SHADER
	profile.apply_to_tree_materials(_leaf_broadleaf, _bark, _leaf_needles, _leaf_ferns, _leaf_cushion)
	if not legacy_cards_for_comparison:
		for painted in [_leaf_broadleaf, _leaf_needles]:
			painted.set_shader_parameter("tree_paint_atlas", PAINT_ATLAS)
		_bark.set_shader_parameter("tree_paint_atlas", PAINT_ATLAS)
		_bark.set_shader_parameter("bark_paint_strength", 1.0)
	else:
		_leaf_broadleaf.set_shader_parameter("leaf_sprite_mode", true)
		_leaf_broadleaf.set_shader_parameter("leaf_sprite_atlas", FoliageTextures.leaf_atlas())
		_leaf_needles.set_shader_parameter("leaf_sprite_mode", true)
		_leaf_needles.set_shader_parameter("leaf_sprite_atlas", FoliageTextures.needle_atlas())
	_leaf_ferns.set_shader_parameter("leaf_sprite_mode", true)
	_leaf_ferns.set_shader_parameter("leaf_sprite_atlas", FoliageTextures.fern_atlas())
	_leaf_cushion.set_shader_parameter("leaf_sprite_mode", true)
	_leaf_cushion.set_shader_parameter("leaf_sprite_atlas", FoliageTextures.cushion_atlas())
	_proxy = _bark.duplicate()

	# The impostor shares the wind and palette uniforms (it includes the same
	# files), so it takes the same profile push.
	_impostor = ShaderMaterial.new()
	_impostor.shader = IMPOSTOR_SHADER
	# Passed as both roles: it needs the leaf palette's shared values and the
	# sway; uniforms it does not declare are simply ignored.
	profile.apply_to_tree_materials(_impostor, _impostor)


func _build_variants() -> void:
	# Fixed order, from FoliageFamily.all_species(): TreePlacer's species
	# indices are positional (0=oak, 1=birch, 2=rounded-shrub, 3=low-hedge,
	# 4=spruce, 5=pine, 6=fir, 7=fern, 8=alpine-cushion -- see its class
	# comment), so this list is never reordered or filtered, even for a
	# location with one family at 0 cover. The unused family's meshes just
	# never get placed; building them anyway is a small, one-off cost, not a
	# per-instance one.
	_species = FoliageFamily.all_species()
	_variants = []
	_rows.clear()
	for s in _species.size():
		var species := _species[s]
		var card_list: Array[TreeVariant] = []
		for v in VARIANTS_PER_SPECIES:
			var seed_value := profile.world_seed + s * 101 + v * 7
			if profile.use_nature_pack and not legacy_cards_for_comparison:
				card_list.append(NatureMeshBuilder.tree(species, s, v, profile))
			elif not legacy_cards_for_comparison and TreeLowPolyBuilder.supports(species):
				card_list.append(TreeLowPolyBuilder.build(species, seed_value))
			else:
				card_list.append(TreeCardBuilder.build(species, seed_value, quality.tree_canopy_detail))
			_rows.append(Vector2i(s, v))
		_variants.append(card_list)
	# Match the full canopy's backlight / surface response per atlas row.
	# One global value made painted conifers brighten at the handover.
	var surfaces := PackedVector3Array()
	surfaces.resize(32)
	for i in _rows.size():
		var leaf := leaf_material_for(_rows[i].x)
		var painted := leaf.shader == PAINTED_SHADER
		var translucency := float(leaf.get_shader_parameter("leaf_translucency"))
		if profile.use_nature_pack and not legacy_cards_for_comparison:
			var surface := _variants[_rows[i].x][_rows[i].y].canopy_mesh.surface_get_material(0) as ShaderMaterial
			surfaces[i] = Vector3(float(surface.get_shader_parameter("leaf_translucency")), 0.9, 0.08)
		else:
			surfaces[i] = Vector3(translucency * (0.4 if painted else 1.0), 0.96 if painted else 0.85, 0.08 if painted else 0.15)
	_impostor.set_shader_parameter("impostor_surface", surfaces)


## Painted zones changed inside `area` (Location Studio S4): rebuilds the tree
## chunks there; the old ones stay up until their replacements commit.
func rebuild_zone_area(area: Rect2) -> int:
	if _streamer == null: return 0
	_streamer.job = _make_job()
	return _streamer.invalidate_area(area, chunk_size)


## Worker-side settings, snapshotted so a rebuild cannot change them under a
## running build.
func _make_job() -> _Job:
	var job := _Job.new()
	job.params = TreePlacer.Params.new()
	job.params.woodland_cover = profile.woodland_cover()
	job.params.woodland_density = profile.woodland_floor_density
	job.params.woodland_spacing = profile.woodland_bush_spacing
	job.params.world_seed = profile.world_seed
	job.params.chunk_size = chunk_size
	job.params.spacing = profile.tree_spacing
	job.params.cover = profile.tree_cover
	job.params.oak_share = profile.tree_oak_share
	job.params.shrub_spacing = profile.shrub_spacing
	job.params.shrub_cover = profile.shrub_cover
	job.params.shrub_share = profile.shrub_share
	job.params.conifer_spacing = profile.conifer_spacing
	job.params.conifer_cover = profile.conifer_cover
	job.params.conifer_spruce_share = profile.conifer_spruce_share
	job.params.fir_spacing = profile.fir_spacing
	job.params.fir_cover = profile.fir_cover
	job.params.fern_spacing = profile.fern_spacing
	job.params.fern_cover = profile.fern_cover
	job.params.cushion_spacing = profile.cushion_spacing
	job.params.cushion_cover = profile.cushion_cover
	job.params.regrowth_cover = profile.regrowth_cover if profile.enabled else 0.0
	job.params.regrowth_spacing = profile.regrowth_spacing
	job.params.scale_min = profile.tree_scale_min
	job.params.scale_max = profile.tree_scale_max
	job.params.conifer_scale_min = profile.conifer_scale_min
	job.params.conifer_scale_max = profile.conifer_scale_max
	job.params.jitter = profile.tree_jitter
	job.params.mantle_cover = profile.mantle_cover if profile.enabled else 0.0
	job.params.mantle_width = profile.mantle_width
	job.params.mantle_spacing = profile.mantle_spacing
	job.params.variants_per_species = VARIANTS_PER_SPECIES
	job.params.groves = TreePlacer.grove_noise(profile.world_seed)
	job.params.zones = EnvironmentZones.for_profile(profile, terrain)
	job.terrain = terrain
	job.rows = _rows.duplicate()
	return job


class _Job extends RefCounted:
	var params: TreePlacer.Params
	var terrain: TerrainProvider
	var rows: Array[Vector2i]

	## Returns {groups: {Vector2i key: [transforms, custom]}, impostor: [count,
	## buffer], trees: int}. Transforms stay unpacked for the groups: commit
	## needs them for the culling box anyway, and packing there is cheap next to
	## placement.
	func run(coord: Vector2i, _variant: int) -> Dictionary:
		var placement := TreePlacer.place_chunk(coord, params, terrain)
		var origin := Vector3(float(coord.x), 0.0, float(coord.y)) * params.chunk_size
		var groups := {}
		var impostor_transforms: Array[Transform3D] = []
		var impostor_custom := PackedColorArray()
		for i in placement.transforms.size():
			var key := Vector2i(placement.species[i], placement.variant[i])
			if not groups.has(key):
				groups[key] = [[], []]
			groups[key][0].append(placement.transforms[i])
			groups[key][1].append(placement.custom[i])
			if key.x == REGROWTH_SPECIES:
				continue
			# The impostor's atlas row rides in custom.b.
			var custom: Color = placement.custom[i]
			custom.b = (float(rows.find(key)) + 0.0) / float(maxi(rows.size(), 1))
			impostor_transforms.append(placement.transforms[i])
			impostor_custom.append(custom)
		var packed := {}
		for key in groups:
			var transforms: Array[Transform3D] = []
			transforms.assign(groups[key][0])
			var custom := PackedColorArray(groups[key][1])
			packed[key] = [transforms.size(), FoliageMultiMesh.pack(transforms, custom, origin)]
		return {
			"groups": packed,
			"impostor": [impostor_transforms.size(), FoliageMultiMesh.pack(impostor_transforms, impostor_custom, origin)],
			"trees": placement.transforms.size(),
		}


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
	if exclusions != null: result = exclusions.filter_result(result,Vector3(coord.x,0,coord.y)*chunk_size,"trees",chunk_size)
	if result["trees"] == 0:
		return
	var chunk := Node3D.new()
	chunk.name = "Trees_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector3(float(coord.x), 0.0, float(coord.y)) * chunk_size
	add_child(chunk)
	_chunks[coord] = chunk

	var impostor_start := quality.tree_impostor_distance if _impostors_ready else 0.0
	var stats := {"trees": 0, "triangles": 0, "proxy_triangles": 0}
	var groups: Dictionary = result["groups"]
	for key in groups:
		var variant: TreeVariant = _variants[key.x][key.y]
		var count: int = groups[key][0]
		var buffer: PackedFloat32Array = groups[key][1]
		# Full trees stop just past the end of the dither band.
		var full_end := impostor_start + IMPOSTOR_BAND if impostor_start > 0.0 else 0.0
		var shadow_end := quality.tree_shadow_distance
		if key.x == REGROWTH_SPECIES:
			full_end = REGROWTH_RANGE
			shadow_end = minf(shadow_end, REGROWTH_SHADOW_RANGE)
		_add_part(chunk, "Canopy", variant.canopy_mesh, leaf_material_for(key.x), count, buffer,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, full_end)
		_add_part(chunk, "Bark", variant.bark_mesh, _bark, count, buffer,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, 0.0, full_end)
		_add_part(chunk, "ShadowProxy", variant.proxy_mesh, _proxy, count, buffer,
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, 0.0, shadow_end)

		stats["trees"] += count
		stats["triangles"] += count * variant.triangles
		stats["proxy_triangles"] += count * variant.proxy_triangles

	if impostor_start > 0.0:
		var impostor: Array = result["impostor"]
		_add_part(chunk, "Impostors", _impostor_quad(), _impostor, impostor[0], impostor[1],
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, impostor_start, 0.0)

	_chunk_stats[coord] = stats
	# Cheap to keep (a few packed buffers) and it is what lets an impostor
	# bake landing redraw this chunk without a worker round trip -- see
	# _bake_impostors().
	_stats_dirty = true


## `range_begin` / `range_end` > 0 limit the part by distance, widened by the
## box's reach since Godot measures to the AABB centre (see GrassChunk).
func _add_part(
	chunk: Node3D, part: String, mesh: Mesh, material: Material,
	count: int, buffer: PackedFloat32Array,
	shadow_mode: GeometryInstance3D.ShadowCastingSetting, range_begin: float, range_end: float,
) -> void:
	if mesh == null or mesh.get_surface_count() == 0 or count == 0:
		return
	var instance := MultiMeshInstance3D.new()
	instance.name = part
	instance.multimesh = FoliageMultiMesh.from_buffer(mesh, count, buffer)
	# Nature-pack canopies and shadow casters carry their own per-surface
	# materials (source textures and alpha cuts).
	var own_materials := profile.use_nature_pack and not legacy_cards_for_comparison and part in ["Canopy", "ShadowProxy"]
	instance.material_override = null if own_materials else material
	instance.cast_shadow = shadow_mode
	# Sway moves vertices past the computed bounds; a metre covers it. The
	# impostor quad is built in the shader, so its box is grown by a tree.
	var grow := 12.0 if part == "Impostors" else 1.0
	instance.custom_aabb = instance.multimesh.get_aabb().grow(grow)
	var reach := instance.custom_aabb.size.length() * 0.5
	if range_begin > 0.0:
		instance.visibility_range_begin = maxf(0.0, range_begin - reach)
	if range_end > 0.0:
		instance.visibility_range_end = range_end + reach
	chunk.add_child(instance)


var _quad: ArrayMesh

## A unit quad with UV (0,0) top-left; tree_impostor.gdshader positions it.
func _impostor_quad() -> ArrayMesh:
	if _quad != null:
		return _quad
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 1, 0), Vector3(0.5, 1, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad = ArrayMesh.new()
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


func _bake_impostors() -> void:
	_bake_serial += 1
	var serial := _bake_serial
	var variants: Array = []
	var leaves: Array = []
	for row in _rows:
		variants.append(_variants[row.x][row.y])
		leaves.append(leaf_material_for(row.x))
	var baker := TreeImpostorBaker.new()
	baker.name = "ImpostorBaker"
	add_child(baker)
	var started := Time.get_ticks_msec()
	var atlas: TreeImpostorBaker.Atlas = await baker.bake(variants, leaves, _bark)
	baker.queue_free()
	if serial != _bake_serial or not is_inside_tree():
		return    # a newer rebuild started its own bake
	_impostor.set_shader_parameter("impostor_albedo", atlas.albedo)
	_impostor.set_shader_parameter("impostor_normal", atlas.normal)
	_impostor.set_shader_parameter("impostor_rows", atlas.rows)
	_impostor.set_shader_parameter("impostor_frames", TreeImpostorBaker.FRAMES)
	_impostor.set_shader_parameter("impostor_row_size", atlas.row_size)
	_set_impostor_transition(quality.tree_impostor_distance, IMPOSTOR_BAND)
	_impostors_ready = true
	# Redraw every chunk currently on screen from the data it was already
	# committed with -- no worker round trip, since placement has not changed,
	# only how each tree is drawn at distance. This has to happen NOW, not
	# progressively: the materials above just started fading full trees past
	# tree_impostor_distance on EVERY chunk (materials are shared, not
	# per-chunk), but only a chunk's Impostors part covers what that fade
	# reveals. A chunk left un-redrawn would have neither: its full trees
	# fading out with nothing behind them, until whenever the streamer next
	# happened to rebuild it. Chunks the worker streams in later, and any
	# still in flight right now, pick up _impostors_ready from _commit_chunk
	# on their own.
	for coord in _chunk_result.keys():
		if _chunks.has(coord):
			_commit_chunk(coord, 0, _chunk_result[coord])
	_recount()
	print("[foliage] tree impostors baked: %d rows in %d ms" % [atlas.rows, Time.get_ticks_msec() - started])
	impostors_ready.emit()


func _release_chunk(coord: Vector2i) -> void:
	if _chunks.has(coord):
		_chunks[coord].queue_free()
		_chunks.erase(coord)
	_chunk_result.erase(coord)
	if _chunk_stats.erase(coord):
		_stats_dirty = true


func _recount() -> void:
	_stats_dirty = false
	tree_count = 0
	_stats = {"trees": 0, "triangles": 0, "proxy_triangles": 0}
	for stats in _chunk_stats.values():
		for k in stats:
			_stats[k] += stats[k]
		tree_count += stats["trees"]


func _clear() -> void:
	_bake_serial += 1
	if _streamer != null:
		_streamer.clear()
	for chunk in _chunks.values():
		chunk.queue_free()
	_chunks.clear()
	_chunk_stats.clear()
	_chunk_result.clear()
	tree_count = 0
	_stats.clear()


func _exit_tree() -> void:
	if exclusions != null and exclusions.changed.is_connected(_exclusions_changed): exclusions.changed.disconnect(_exclusions_changed)
	_bake_serial += 1
	if _streamer != null:
		_streamer.clear()
