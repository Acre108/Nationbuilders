class_name GrassChunk
extends Node3D

## One square of grass, drawn in two distance bands.
##
## Chunking exists for culling, not tidiness. A MultiMeshInstance3D is culled as
## a single unit against the combined AABB of everything it holds, so one
## MultiMesh covering a whole field has an AABB that overlaps the frustum from
## almost anywhere and therefore renders every instance every frame regardless
## of what is actually on screen. Splitting into chunks lets Godot discard whole
## regions. (The PlacesOS spike measured this directly for its tree scatter:
## 260,604 vs 362,402 primitives for the same view, chunked vs not.)
##
## Chunks are also the unit of rebuild: carving furniture out of the grass
## touches only the chunks the footprint overlaps.
##
## Bands: the NEAR band draws every tuft with the full clump mesh. The FAR band
## draws only the tufts whose LOD rank is under `far_keep`, with a much cheaper
## mesh. Which pixels each band actually shows is decided per tuft in
## grass.gdshader; the visibility ranges set here are only a coarse cull so a
## band's MultiMesh is not submitted at all where none of its tufts can show.

## Everything a chunk needs to build itself that is the same for every chunk.
## Built once per rebuild by GrassLayer.
class Style extends RefCounted:
	var chunk_size: float = 16.0
	## Culling-box growth. Wind displaces vertices in the shader, which Godot's
	## computed bounds know nothing about, so without padding tufts near a chunk
	## edge pop out of existence when a gust pushes them past the box.
	var padding: float = 1.0
	var near_grass_mesh: Mesh
	var far_grass_mesh: Mesh
	var near_grass_material: Material
	var far_grass_material: Material
	## Tall grass for lush meadow patches (MeadowPatches.tall_chance()), near
	## band only: in the far band every tuft uses far_grass_mesh. Null = none.
	var near_tall_mesh: Mesh
	var near_tall_material: Material
	## Flower draw sets, each [near mesh, far mesh, near material, far
	## material]. Each flower draws with the set MeadowPatches.flower_set()
	## picks, so drifts are one kind. Empty = no flowers.
	var flower_sets: Array = []
	## Decides tall grass and flower sets per tuft from its position. Null =
	## no tall grass, and flowers spread over the sets by position hash.
	var meadow: MeadowPatches
	## False draws everything in the near band at every distance.
	var lod_enabled: bool = true
	var far_keep: float = 0.4
	## Distance in world units over which the near band hands over to the far
	## band, and the distance at which the far band has fully thinned out.
	var near_end: float = 32.0
	var far_end: float = 90.0
	## Width of the per-tuft swap at near_end, matching grass.gdshader.
	var swap_span: float = 2.0


var coord: Vector2i
var near_grass: MultiMeshInstance3D
var near_tall: MultiMeshInstance3D
var far_grass: MultiMeshInstance3D
## One per Style.flower_sets entry (null where that set has none here).
var near_flowers: Array[MultiMeshInstance3D] = []
var far_flowers: Array[MultiMeshInstance3D] = []

## Instances held by each band, grass and flowers together.
var near_count: int = 0
var far_count: int = 0
var grass_count: int = 0
var flower_count: int = 0
## Of grass_count, the tufts drawn with the tall-grass mesh.
var tall_count: int = 0
## Bumped on every apply(). Lets tests prove a carve left other chunks alone.
var build_serial: int = 0
## The (carved) result this chunk was last filled from. Costs nothing for an
## uncarved chunk -- filter_carved() hands back the cached scatter itself -- and
## lets tests inspect what was drawn: headless Godot's dummy renderer does not
## keep MultiMesh buffers, so reading transforms back from them returns junk.
var shown: GrassPlacer.PlacementResult


func setup(chunk_coord: Vector2i, chunk_size: float) -> void:
	coord = chunk_coord
	position = Vector3(float(coord.x) * chunk_size, 0.0, float(coord.y) * chunk_size)


## Everything about a chunk's instances that can be worked out off the main
## thread: the culling box and every band's packed MultiMesh buffer.
## prepare() builds one on a worker; apply_prepared() only has to create
## MultiMeshes from it.
class Prepared extends RefCounted:
	var aabb: AABB
	var near_grass := PackedFloat32Array()
	var near_grass_count: int = 0
	var near_tall := PackedFloat32Array()
	var near_tall_count: int = 0
	var far_grass := PackedFloat32Array()
	var far_grass_count: int = 0
	## Per flower set: [buffer, count].
	var near_flowers: Array = []
	var far_flowers: Array = []
	var near_flowers_count: int = 0
	var far_flowers_count: int = 0


## Thread-safe: pure data in, pure data out. `origin` is the chunk node's
## world position (see setup()).
static func prepare(result: GrassPlacer.PlacementResult, style: Style, origin: Vector3) -> Prepared:
	var p := Prepared.new()
	p.aabb = culling_box(result, style)
	# Which tufts draw tall is a function of position only (no extra draws,
	# nothing stored in the placement), so carving and refills agree.
	var main: Array[Transform3D] = result.grass_transforms
	var main_custom := result.grass_custom
	var tall: Array[Transform3D] = []
	var tall_custom := PackedColorArray()
	if style.near_tall_mesh != null and style.meadow != null:
		main = []
		main_custom = PackedColorArray()
		for i in result.grass_transforms.size():
			var o := result.grass_transforms[i].origin
			if MeadowPatches.position_hash(o.x, o.z) < style.meadow.tall_chance(o.x, o.z):
				tall.push_back(result.grass_transforms[i])
				tall_custom.push_back(result.grass_custom[i])
			else:
				main.push_back(result.grass_transforms[i])
				main_custom.push_back(result.grass_custom[i])
	p.near_grass = FoliageMultiMesh.pack(main, main_custom, origin)
	p.near_grass_count = main.size()
	p.near_tall = FoliageMultiMesh.pack(tall, tall_custom, origin)
	p.near_tall_count = tall.size()
	if style.lod_enabled:
		var far := _far_subset(result.grass_transforms, result.grass_custom, style.far_keep)
		p.far_grass = FoliageMultiMesh.pack(far[0], far[1], origin)
		p.far_grass_count = far[0].size()

	var sets := style.flower_sets.size()
	var by_set: Array = []
	for k in sets:
		by_set.append([[] as Array[Transform3D], PackedColorArray()])
	for i in result.flower_transforms.size():
		if sets == 0:
			break
		var o := result.flower_transforms[i].origin
		var k := style.meadow.flower_set(o.x, o.z, sets) if style.meadow != null \
			else mini(int(MeadowPatches.position_hash(o.x, o.z) * sets), sets - 1)
		by_set[k][0].push_back(result.flower_transforms[i])
		by_set[k][1].push_back(result.flower_custom[i])
	for k in sets:
		var transforms: Array[Transform3D] = by_set[k][0]
		var custom: PackedColorArray = by_set[k][1]
		p.near_flowers.append([FoliageMultiMesh.pack(transforms, custom, origin), transforms.size()])
		p.near_flowers_count += transforms.size()
		if style.lod_enabled:
			var far := _far_subset(transforms, custom, style.far_keep)
			p.far_flowers.append([FoliageMultiMesh.pack(far[0], far[1], origin), far[0].size()])
			p.far_flowers_count += far[0].size()
		else:
			p.far_flowers.append([PackedFloat32Array(), 0])
	return p


## Fills (or refills) this chunk from a placement result, on the main thread.
func apply(result: GrassPlacer.PlacementResult, style: Style) -> void:
	apply_prepared(prepare(result, style, position), result, style)


## Main thread. `result` is what `prepared` was built from.
func apply_prepared(prepared: Prepared, result: GrassPlacer.PlacementResult, style: Style) -> void:
	build_serial += 1
	shown = result
	grass_count = prepared.near_grass_count + prepared.near_tall_count
	tall_count = prepared.near_tall_count
	flower_count = prepared.near_flowers_count
	near_count = grass_count + flower_count

	var aabb := prepared.aabb
	# Godot measures visibility-range distance to the centre of the instance's
	# AABB. A tuft can sit anywhere in the box, so each range is widened by the
	# box's half-diagonal: the band is then never culled while any of its tufts
	# could still be showing, and the shader does the exact per-tuft cut.
	var reach := aabb.size.length() * 0.5

	var near_range := Vector2(0.0, style.near_end + reach) if style.lod_enabled else Vector2(0.0, 0.0)
	near_grass = _apply_one(near_grass, "NearGrass", style.near_grass_mesh, style.near_grass_material,
		prepared.near_grass, prepared.near_grass_count, aabb, near_range)
	near_tall = _apply_one(near_tall, "NearTallGrass", style.near_tall_mesh, style.near_tall_material,
		prepared.near_tall, prepared.near_tall_count, aabb, near_range)

	var far_range := Vector2(maxf(0.0, style.near_end - style.swap_span - reach), style.far_end + reach)
	far_grass = _apply_one(far_grass, "FarGrass", style.far_grass_mesh, style.far_grass_material,
		prepared.far_grass, prepared.far_grass_count, aabb, far_range)

	var sets := style.flower_sets.size()
	# Free instances for sets that no longer exist (a style with fewer sets).
	for k in range(sets, near_flowers.size()):
		if near_flowers[k] != null:
			near_flowers[k].queue_free()
		if far_flowers[k] != null:
			far_flowers[k].queue_free()
	near_flowers.resize(sets)
	far_flowers.resize(sets)
	for k in sets:
		var set: Array = style.flower_sets[k]
		near_flowers[k] = _apply_one(near_flowers[k], "NearFlowers_%d" % k, set[0], set[2],
			prepared.near_flowers[k][0], prepared.near_flowers[k][1], aabb, near_range)
		far_flowers[k] = _apply_one(far_flowers[k], "FarFlowers_%d" % k, set[1], set[3],
			prepared.far_flowers[k][0], prepared.far_flowers[k][1], aabb, far_range)
	far_count = prepared.far_grass_count + prepared.far_flowers_count


## Local-space box around every tuft a chunk holds.
static func culling_box(result: GrassPlacer.PlacementResult, style: Style) -> AABB:
	var p := style.padding
	var low := result.min_y if result.min_y != INF else 0.0
	var high := result.max_y if result.max_y != -INF else 0.0
	return AABB(
		Vector3(-p, low - p, -p),
		Vector3(style.chunk_size + p * 2.0, (high - low) + p * 2.0, style.chunk_size + p * 2.0),
	)


## The tufts that survive into the far band. Same transforms, same custom data:
## the shader widens them, and keeping the transform identical is what lets a
## near tuft and its far replacement swap in place without jumping.
static func _far_subset(transforms: Array[Transform3D], custom: PackedColorArray, keep: float) -> Array:
	var kept_transforms: Array[Transform3D] = []
	var kept_custom := PackedColorArray()
	for i in transforms.size():
		if custom[i].a < keep:
			kept_transforms.push_back(transforms[i])
			kept_custom.push_back(custom[i])
	return [kept_transforms, kept_custom]


## `vis_range` is (begin, end) for Godot's visibility range; (0, 0) means unlimited.
func _apply_one(
	existing: MultiMeshInstance3D, node_name: String,
	mesh: Mesh, material: Material,
	buffer: PackedFloat32Array, count: int,
	aabb: AABB, vis_range: Vector2,
) -> MultiMeshInstance3D:
	if count == 0 or mesh == null:
		if existing != null:
			existing.queue_free()
		return null

	var instance := existing
	if instance == null:
		instance = MultiMeshInstance3D.new()
		instance.name = node_name
		add_child(instance)

	instance.multimesh = FoliageMultiMesh.from_buffer(mesh, count, buffer)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = aabb
	# A cull, not a fade: the visible transition is per tuft in the shader.
	# Godot's own FADE_SELF would crossfade whole 16 m chunks at once.
	instance.visibility_range_begin = vis_range.x
	instance.visibility_range_end = vis_range.y
	instance.visibility_range_begin_margin = 0.0
	instance.visibility_range_end_margin = 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return instance


## Instances (grass, flowers) the near band submits for a camera at `camera`,
## by the same rule the renderer's visibility range applies.
func in_range_near(camera: Vector3) -> Vector2i:
	var flowers := 0
	for instance in near_flowers:
		flowers += _in_range(instance, camera)
	return Vector2i(_in_range(near_grass, camera) + _in_range(near_tall, camera), flowers)


func in_range_far(camera: Vector3) -> Vector2i:
	var flowers := 0
	for instance in far_flowers:
		flowers += _in_range(instance, camera)
	return Vector2i(_in_range(far_grass, camera), flowers)


func _in_range(instance: MultiMeshInstance3D, camera: Vector3) -> int:
	if instance == null:
		return 0
	var d := camera.distance_to(to_global(instance.custom_aabb.get_center()))
	var end := instance.visibility_range_end
	if d < instance.visibility_range_begin or (end > 0.0 and d > end):
		return 0
	return instance.multimesh.instance_count
