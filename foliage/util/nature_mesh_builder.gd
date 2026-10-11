class_name NatureMeshBuilder
extends RefCounted

const SHADER := preload("res://foliage/shaders/nature_pack.gdshader")
static var _scenes: Dictionary = {}
static var _means: Dictionary = {}
static var _cutouts: Dictionary = {}

## Trees are normalised so their lowest vertex (the tips of the root flare)
## sits on the ground, which leaves the roots perched on top of it. Sink each
## tree by this fraction of its height so the flare is buried in the soil.
const TREE_ROOT_SINK := 0.03
## Measured where each model's root flare meets the trunk (fraction of total
## height, reference/nature_pack/tree_bases.png), less a little visible flare.
## The oak's arching roots and the spruce's buttress stood on stilts at 3%.
const TREE_ROOT_SINKS := {"oak": 0.13, "spruce": 0.08, "birch_2": 0.045, "aspen": 0.035, "tall_spruce": 0.035}

static func root_sink(asset: String) -> float:
	return TREE_ROOT_SINKS.get(asset, TREE_ROOT_SINK)

## Flatten ONLY the selected authored LOD into one instanced mesh, preserving
## every source surface/texture. Normalise to root-at-ground and metres.
## `shadow_caster` builds a shadows-only copy: it keeps the alpha cut and the
## sway, so the shadow matches the drawn plant, but skips the impostor fade,
## which in the shadow pass would measure from the light and cull it.
## `sink` lowers the whole mesh that many metres below the ground.
static func build(asset: String, target_height: float, profile: FoliageProfile, far: bool = false, static_mesh: bool = false, shadow_caster: bool = false, sink: float = 0.0) -> ArrayMesh:
	if not _scenes.has(asset):
		_scenes[asset] = load(NatureAssetCatalogue.asset_path(asset))
	var packed: PackedScene = _scenes[asset]
	if packed == null:
		push_error("Missing nature asset: " + asset)
		return ArrayMesh.new()
	var root := packed.instantiate()
	var group := root.find_child("Far" if far else "Near", true, false)
	var parts: Array[MeshInstance3D] = []
	_collect(group, parts)
	var bounds := AABB()
	var first := true
	for part in parts:
		var box := _transform(part, root) * part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var scale_value := target_height / maxf(bounds.size.y, 0.001)
	var offset := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var mesh := ArrayMesh.new()
	for part in parts:
		var transform := _transform(part, root)
		for s in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var heights := PackedVector2Array()
			var colours := PackedColorArray()
			var source := part.get_active_material(s) as StandardMaterial3D
			# Some opaque bark materials (birch, aspen) are flagged alpha-scissor in
			# the pack; treating them as foliage made whole trunks sway and flutter.
			var leafy := source != null and source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED 					and has_cutout(source.albedo_texture)
			for i in vertices.size():
				vertices[i] = (transform * vertices[i] - offset) * scale_value - Vector3(0.0, sink, 0.0)
				normals[i] = (transform.basis.inverse().transposed() * normals[i]).normalized()
				heights.append(Vector2(clampf(vertices[i].y / target_height, 0.0, 1.0), target_height))
				colours.append(Color(1.0, 1.0 if leafy else 0.0, 1.0, 1.0))
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV2] = heights
			arrays[Mesh.ARRAY_COLOR] = colours
			arrays[Mesh.ARRAY_TANGENT] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := ShaderMaterial.new()
			material.shader = SHADER
			profile.apply_to_tree_materials(material, material)
			if source != null:
				material.set_shader_parameter("nature_texture", source.albedo_texture)
				material.set_shader_parameter("nature_colour", source.albedo_color * NatureAssetCatalogue.ASSET_TINTS.get(asset, Color.WHITE))
				if NatureAssetCatalogue.ASSET_RECOLOURS.has(asset):
					material.set_shader_parameter("nature_recolour", NatureAssetCatalogue.ASSET_RECOLOURS[asset])
			material.set_shader_parameter("nature_alpha_cut", 0.5 if leafy else 0.0)
			material.set_shader_parameter("leaf_translucency", profile.tree_translucency * (0.4 if "spruce" in asset or asset == "pine" else 1.0))
			material.set_shader_parameter("nature_shadow_caster", shadow_caster)
			if static_mesh:
				material.set_shader_parameter("tree_sway_strength", 0.0)
				material.set_shader_parameter("tree_flutter_strength", 0.0)
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	root.free()
	return mesh

## A texture's mean colour over its opaque texels, times `tint`, as linear
## RGB (shader space: the texture is sampled as source_color). Cached.
static func mean_colour(texture: Texture2D, tint: Color = Color.WHITE) -> Vector3:
	if texture == null:
		return Vector3(tint.r, tint.g, tint.b)
	if not _means.has(texture):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(64, 64, Image.INTERPOLATE_BILINEAR)
		var sum := Vector3.ZERO
		var weight := 0.0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var linear := c.srgb_to_linear()
				sum += Vector3(linear.r, linear.g, linear.b)
				weight += 1.0
		_means[texture] = sum / maxf(weight, 1.0) if weight > 0.0 else Vector3.ONE * 0.5
	var mean: Vector3 = _means[texture]
	var t := tint.srgb_to_linear()
	return mean * Vector3(t.r, t.g, t.b)

static func tree(species: TreeCardBuilder.Species, slot: int, variant: int, profile: FoliageProfile) -> TreeVariant:
	var selected := NatureAssetCatalogue.choices(profile, slot)
	var asset: String = selected[variant % selected.size()]
	var result := TreeVariant.new()
	result.species = species.name
	result.source_asset = asset
	result.height = species.height * (0.9 + 0.1 * variant)
	var sink := result.height * root_sink(asset)
	result.canopy_mesh = build(asset, result.height, profile, false, false, false, sink)
	result.bark_mesh = ArrayMesh.new() # source bark stays in its original surface
	# The shadow comes from the same model's authored far LOD: the same
	# silhouette and leaf cut-outs as the tree drawn, at fewer triangles.
	result.proxy_mesh = build(asset, result.height, profile, true, false, true, sink)
	result.triangles = triangles(result.canopy_mesh)
	result.proxy_triangles = triangles(result.proxy_mesh)
	return result

## True when a texture has cut-out texels (leaf cards); opaque bark has none.
## No texture: trust the material's transparency flag. Cached.
static func has_cutout(texture: Texture2D) -> bool:
	if texture == null:
		return true
	if not _cutouts.has(texture):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.resize(64, 64, Image.INTERPOLATE_NEAREST)
		var clear := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a < 0.5:
					clear += 1
		_cutouts[texture] = clear > 0.1 * image.get_width() * image.get_height()
	return _cutouts[texture]

static func triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return count

static func _collect(node: Node, parts: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		parts.append(node)
	for child in node.get_children():
		_collect(child, parts)

static func _transform(node: Node3D, root: Node) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result
