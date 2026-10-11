class_name TreeImpostorBaker
extends Node

## Renders every tree variant into one impostor atlas, at runtime.
##
## Runtime rather than offline because the trees are: card trees are generated
## per location and quality level, and their colours come from the location's
## palette. Baking takes a fraction of a second, asynchronously; until it is
## done TreeLayer simply draws full trees at every distance.
##
## Two atlases, same layout -- one row per variant, FRAMES columns, one per view
## angle round the tree (camera at azimuth column * TAU / FRAMES, looking at the
## trunk horizontally):
##   albedo  the tree's colour, unlit, alpha = coverage
##   normal  the clump normals, model space, encoded 0..1
## tree_impostor.gdshader lights them live, so impostors match their trees
## under any sun.
##
## The bake renders in its own World3D with no lights and black ambient; the
## tree materials write albedo or normal to EMISSION (tree_bake_mode), so what
## lands in the viewport is exactly the value, with a linear tonemap.
##
## Needs a real renderer: under --headless there is nothing to read back, and
## TreeLayer skips baking.

const FRAMES := 8
const FRAME_PX := 192

class Atlas extends RefCounted:
	var albedo: Texture2D
	var normal: Texture2D
	var rows: int
	## Per row: (frame size in metres, frame centre height above the root).
	var row_size := PackedVector2Array()


## `variants[i]` is baked into row i with `leaf_materials[i]` on its canopy.
## Materials are copied and put into bake mode here; the originals are not
## touched.
##
## Albedo and normal render at the same time, in two viewports, so each view
## angle costs one frame: rows x FRAMES frames in all.
func bake(variants: Array, leaf_materials: Array, bark_material: ShaderMaterial) -> Atlas:
	var passes: Array = [_make_pass(1, bark_material), _make_pass(2, bark_material)]
	var atlas := Atlas.new()
	atlas.rows = variants.size()
	var images: Array = []
	for i in 2:
		images.append(Image.create(FRAME_PX * FRAMES, FRAME_PX * atlas.rows, false, Image.FORMAT_RGBA8))

	for row in atlas.rows:
		var variant: TreeVariant = variants[row]
		var bounds := variant.canopy_mesh.get_aabb()
		if variant.bark_mesh.get_surface_count() > 0:
			bounds = bounds.merge(variant.bark_mesh.get_aabb())
		var radius := maxf(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z)))
		# Square frame, big enough for the tree's height and its widest
		# swing round the trunk. Frames are shared by all angles, so the
		# widest angle sets the size.
		var size := maxf(bounds.size.y, radius * 2.0) * 1.04
		var centre := bounds.position.y + bounds.size.y * 0.5
		atlas.row_size.push_back(Vector2(size, centre))
		for pass_data in passes:
			var leaf := _bake_copy(leaf_materials[row])
			leaf.set_shader_parameter("tree_bake_mode", pass_data["mode"])
			if not variant.source_asset.is_empty():
				var mesh: ArrayMesh = variant.canopy_mesh.duplicate()
				for s in mesh.get_surface_count():
					var material := _bake_copy(mesh.surface_get_material(s))
					material.set_shader_parameter("tree_bake_mode", pass_data["mode"])
					mesh.surface_set_material(s, material)
				pass_data["canopy"].mesh = mesh
				pass_data["canopy"].material_override = null
			else:
				pass_data["canopy"].mesh = variant.canopy_mesh
				pass_data["canopy"].material_override = leaf
			pass_data["bark"].mesh = variant.bark_mesh
			pass_data["camera"].size = size

		for column in FRAMES:
			var azimuth := TAU * float(column) / float(FRAMES)
			var direction := Vector3(sin(azimuth), 0.0, cos(azimuth))
			for pass_data in passes:
				var camera: Camera3D = pass_data["camera"]
				camera.position = direction * (radius + 100.0) + Vector3(0.0, centre, 0.0)
				camera.look_at(Vector3(0.0, centre, 0.0))
			# The frame after this one has been drawn with the new camera.
			await RenderingServer.frame_post_draw
			for i in 2:
				var image: Image = passes[i]["viewport"].get_texture().get_image()
				image.convert(Image.FORMAT_RGBA8)
				images[i].blit_rect(image, Rect2i(0, 0, FRAME_PX, FRAME_PX), Vector2i(column * FRAME_PX, row * FRAME_PX))

	for pass_data in passes:
		pass_data["viewport"].queue_free()

	# Bleed colour into transparent texels before mipmapping, or distant
	# impostors grow a dark fringe from the black clear colour.
	for image in images:
		image.fix_alpha_edges()
		image.generate_mipmaps()
	atlas.albedo = ImageTexture.create_from_image(images[0])
	atlas.normal = ImageTexture.create_from_image(images[1])
	return atlas


## One unlit bake viewport writing `mode` (1 albedo, 2 normal).
func _make_pass(mode: int, bark_material: ShaderMaterial) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(FRAME_PX, FRAME_PX)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 500.0
	viewport.add_child(camera)
	camera.current = true

	var canopy := MeshInstance3D.new()
	var bark := MeshInstance3D.new()
	var bark_bake := _bake_copy(bark_material)
	bark_bake.set_shader_parameter("tree_bake_mode", mode)
	bark.material_override = bark_bake
	viewport.add_child(canopy)
	viewport.add_child(bark)
	return {"mode": mode, "viewport": viewport, "camera": camera, "canopy": canopy, "bark": bark}


## A still, unfaded copy of a tree material for baking: no sway, no flutter,
## no impostor handover.
static func _bake_copy(material: ShaderMaterial) -> ShaderMaterial:
	var copy: ShaderMaterial = material.duplicate()
	copy.set_shader_parameter("tree_sway_strength", 0.0)
	copy.set_shader_parameter("tree_flutter_strength", 0.0)
	copy.set_shader_parameter("tree_impostor_start", 0.0)
	# Tint is applied live on the impostor, by its own distance.
	copy.set_shader_parameter("foliage_distance_tint_strength", 0.0)
	# Live weather too (cloud shadows, wetness): world-state, never part of the tree.
	copy.set_shader_parameter("foliage_live_weather_weight", 0.0)
	return copy
