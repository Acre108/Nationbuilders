class_name GrassTuftBuilder
extends RefCounted

## Procedural grass tuft meshes.
##
## Three deliberate choices here drive everything downstream:
##
## 1. Blades are TAPERED GEOMETRY, not alpha-cut cards. A card needs an alpha
##    texture, which forces either a discard (breaks early-Z, costs a depth
##    prepass) or alpha blending (sorting artefacts on a surface with hundreds
##    of thousands of overlapping quads). Tapered geometry costs a handful of
##    extra triangles per tuft and buys a fully opaque grass pass. At the
##    densities this system targets, that trade is not close.
##
## 2. Normals are forced to +Y, per the brief. A blade's true normal points
##    sideways, so a field of them lights as thousands of separately shaded
##    slivers -- noisy, and it flickers as the camera moves. Forcing +Y makes
##    the field light as one soft surface, which is the whole stylised look.
##    grass.gdshader re-asserts this in world space for slope-aligned tufts.
##
## 3. Vertex colour red marks petals: 0 on stems and blades, 1 on flower heads.
##    grass.gdshader uses it to blend between the grass palette and the petal
##    palette, which is how one mesh, one material and one MultiMesh can render
##    a coloured bloom on a green stem. Plain grass carries an all-zero colour
##    array rather than none at all -- an absent ARRAY_COLOR reads as white in
##    the shader, which would paint every blade with the petal palette.
##
## Meshes are generated rather than imported so LOD variants are the same shape
## with fewer blades and segments -- an imported LOD chain would need three
## hand-authored meshes kept visually in sync. adopt_imported_mesh() exists for
## when you do want to supply your own .glb tuft.

const UP := Vector3.UP
const STEM_COLOUR := Color(0.0, 0.0, 0.0, 1.0)
const PETAL_COLOUR := Color(1.0, 1.0, 1.0, 1.0)


## One LOD's worth of tuft geometry settings.
##
## `spread_ratio` and `lean_ratio` are expressed as fractions of `height` rather
## than in world units, so changing a location's `tuft_height` rescales the
## whole clump instead of turning tall grass into a narrow spike or short grass
## into a flat starfish.
class TuftConfig extends RefCounted:
	var blade_count: int = 11      ## Shoots (ramets) per clump.
	var segments: int = 4          ## Quads up each blade. 1 = flat card.
	var height: float = 0.45
	var width: float = 0.045
	## Shape of the blade along its length. Width follows
	## `1 - t^tip_sharpness`, so the blade holds most of its width up the stalk
	## and then narrows quickly near the tip -- higher values hold width longer.
	## A plain `(1-t)^k` falloff instead makes every blade a wedge that is widest
	## at the root, which reads as a shark fin once blades are wide enough to see.
	var tip_sharpness: float = 2.2
	## Outward arc of a shoot at the rim of the clump, as a fraction of height.
	## This is what makes neighbouring clumps overlap rather than sit as separate
	## fans with bare ground between them.
	var lean_ratio: float = 0.62
	## Radius shoots are scattered over, as a fraction of height.
	var spread_ratio: float = 0.40
	var height_jitter: float = 0.3
	## Height of a rim shoot relative to a centre one. Shorter shoots at the
	## edge give the clump a dome silhouette, so overlapping neighbours read as
	## one continuous surface instead of a pile of intersecting fans.
	var outer_height_scale: float = 0.55

	## Fraction of shoots laid almost flat to form a ground-hugging mat under the
	## upright ones. These are what actually stop you seeing soil between clumps
	## when you look down from head height -- upright blades leave sightlines
	## straight to the ground no matter how many of them there are, because you
	## are looking down their length.
	var mat_ratio: float = 0.0
	## How far a mat shoot is pushed over towards horizontal, 1 = flat.
	var mat_flatness: float = 0.85
	## Mat shoots are broader and longer than upright ones -- real procumbent
	## leaves are, and it is by far the cheapest way to buy ground coverage:
	## widening a blade costs no extra triangles at all, while adding shoots
	## costs `segments * 2` each.
	var mat_width_scale: float = 2.2
	var mat_length_scale: float = 1.5

	func copy() -> TuftConfig:
		var c := TuftConfig.new()
		c.blade_count = blade_count
		c.segments = segments
		c.height = height
		c.width = width
		c.tip_sharpness = tip_sharpness
		c.lean_ratio = lean_ratio
		c.spread_ratio = spread_ratio
		c.height_jitter = height_jitter
		c.outer_height_scale = outer_height_scale
		c.mat_ratio = mat_ratio
		c.mat_flatness = mat_flatness
		c.mat_width_scale = mat_width_scale
		c.mat_length_scale = mat_length_scale
		return c


	## Wide, flat-topped clump with a ground-hugging mat. The default for ordinary
	## meadow grass: shoots stay near-upright and roughly equal height, the clump
	## spreads wider than it is tall, and the mat closes the sightlines to soil.
	static func flat_meadow() -> TuftConfig:
		var c := TuftConfig.new()
		c.spread_ratio = 0.78
		c.lean_ratio = 0.30
		c.outer_height_scale = 0.82
		c.height_jitter = 0.45
		c.tip_sharpness = 3.4
		c.width = 0.05
		# No mat: the ground-hugging procumbent layer closed the soil off well
		# (14% visible vs 45%) but read as flat papery sheets at grazing angles,
		# which looked worse than the gaps it fixed. Sprite cards are the route to
		# coverage instead -- see grass_card_builder.gd.
		c.mat_ratio = 0.0
		return c


	## Rounded dome of shoots, tall in the centre and splaying low at the rim.
	## Reads as a distinct tussock rather than continuous sward -- kept for
	## tussocky or scrubby biomes where clumps should be individually legible.
	static func dome_clump() -> TuftConfig:
		var c := TuftConfig.new()
		c.spread_ratio = 0.40
		c.lean_ratio = 0.62
		c.outer_height_scale = 0.55
		c.height_jitter = 0.3
		c.tip_sharpness = 2.2
		c.width = 0.045
		c.mat_ratio = 0.0
		return c


## Accumulates surface arrays while a tuft is assembled.
class _Surface extends RefCounted:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## Builds one tuft. `seed` fixes the blade layout so a given LOD is identical
## everywhere -- per-instance variety comes from the placer's transforms, not
## from every tuft having unique geometry, which would defeat MultiMesh.
static func build_tuft(config: TuftConfig, seed: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var surface := _Surface.new()
	_append_tuft_blades(surface, config, config.blade_count, rng)
	return surface.commit()


## Flower: a short tuft of blades with a small radial bloom on top.
##
## The head is built from tapered petals arranged around a centre and tilted
## up, rather than the crossed squares an earlier pass used -- flat squares read
## as paper tags stuck on sticks at any distance where you can still resolve
## them, which is most of the distance a flower is visible at all.
static func build_flower(config: TuftConfig, petal_count: int = 5, head_size: float = 0.038, seed: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 977

	var surface := _Surface.new()
	# Fewer, straighter blades than a grass tuft: a bloom needs a readable stem,
	# not a bush, or the head looks like it is sitting on the ground.
	var stem_config := config.copy()
	stem_config.lean_ratio = config.lean_ratio * 0.3
	stem_config.spread_ratio = config.spread_ratio * 0.35
	stem_config.height_jitter = 0.15
	# A bloom needs its stems to reach the head, so the dome falloff that shapes
	# a grass clump is almost switched off here.
	stem_config.outer_height_scale = 0.9
	_append_tuft_blades(surface, stem_config, maxi(2, config.blade_count / 3), rng)

	var centre := Vector3(0.0, config.height * rng.randf_range(0.92, 1.04), 0.0)
	var tilt := rng.randf_range(0.25, 0.45)

	for petal in petal_count:
		var angle := (float(petal) / float(petal_count)) * TAU + rng.randf_range(-0.15, 0.15)
		var outward := Vector3(sin(angle), 0.0, cos(angle))
		var side := Vector3(outward.z, 0.0, -outward.x)

		var inner := centre + outward * head_size * 0.18
		var outer := centre + outward * head_size + Vector3(0.0, head_size * tilt, 0.0)
		var inner_half := head_size * 0.22
		var outer_half := head_size * 0.42

		var base := surface.verts.size()
		for spec in [
			[inner, -inner_half, 0.0], [inner, inner_half, 0.0],
			[outer, -outer_half, 1.0], [outer, outer_half, 1.0],
		]:
			var anchor: Vector3 = spec[0]
			surface.verts.push_back(anchor + side * float(spec[1]))
			surface.normals.push_back(UP)
			# UV.y = 1 across the head so the shader treats it as blade tip and
			# bends it with full wind weight, keeping blooms attached to their
			# stems instead of shearing off them.
			surface.uvs.push_back(Vector2(float(spec[2]), 1.0))
			surface.colours.push_back(PETAL_COLOUR)

		surface.indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

	return surface.commit()


## Scatters one clump of shoots into a dome.
##
## Shoots are distributed over the clump's area, not along its radius: a shoot's
## distance from centre is `spread * sqrt(random)`, because using `random`
## directly biases shoots towards the middle and leaves the rim -- the part that
## has to overlap the neighbouring clump -- thin.
##
## Distance from centre then drives both height and outward arc, so centre
## shoots stand tall and straight while rim shoots are shorter and splay
## outward. That dome shape is what lets clumps interlock into a continuous
## surface rather than reading as separate fans on bare ground.
static func _append_tuft_blades(surface: _Surface, config: TuftConfig, blade_count: int, rng: RandomNumberGenerator) -> void:
	var spread := config.height * config.spread_ratio
	var lean := config.height * config.lean_ratio

	for blade in blade_count:
		# Even angular spacing plus jitter. Pure random angles leave visible
		# gaps and clumps at these blade counts.
		var base_angle := (float(blade) / float(blade_count)) * TAU
		var angle := base_angle + rng.randf_range(-0.45, 0.45)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var right := Vector3(dir.z, 0.0, -dir.x)

		var radial := sqrt(rng.randf())
		var height := config.height
		height *= lerpf(1.0, config.outer_height_scale, radial)
		height *= 1.0 + rng.randf_range(-config.height_jitter, config.height_jitter)

		# Mat shoots are laid over towards horizontal and start nearer the centre,
		# so they sweep outward across the gap to the neighbouring clump rather
		# than fanning from the rim where they would leave the middle open.
		var is_mat := float(blade) < float(blade_count) * config.mat_ratio
		var flatten := 0.0
		var root_radial := radial
		var width := config.width
		if is_mat:
			flatten = config.mat_flatness * rng.randf_range(0.85, 1.0)
			# Mat shoots start near the centre and sweep outward across the gap to
			# the neighbouring clump. Rooting them at the rim instead would leave
			# the middle of the clump open, which is where you look straight down.
			root_radial = radial * 0.3
			height *= config.mat_length_scale
			width *= config.mat_width_scale

		_append_blade(
			surface,
			dir * (spread * root_radial), dir, right,
			height, width, config.tip_sharpness,
			# Rim shoots arc out hard, centre shoots stay near-vertical.
			lean * radial * rng.randf_range(0.7, 1.3),
			config.segments, flatten,
		)


## One blade: a tapered strip of `segments` quads.
##
## UV.x runs across the blade, UV.y is normalised height (0 root, 1 tip). The
## shader reads UV.y as its wind bend weight, which is why it must be normalised
## here rather than derived from VERTEX.y -- randomly scaled instances would
## otherwise bend by differing amounts.
static func _append_blade(
	surface: _Surface,
	root: Vector3, dir: Vector3, right: Vector3,
	height: float, width: float, tip_sharpness: float, lean: float, segments: int,
	flatten: float = 0.0
) -> void:
	var base := surface.verts.size()
	var rings := maxi(1, segments)

	for i in rings + 1:
		var t := float(i) / float(rings)
		# Quadratic curve, so the blade leans over near the tip rather than
		# tilting as a straight stick from the root.
		# `flatten` trades vertical reach for outward reach, turning an upright
		# shoot into a procumbent one that lies across the soil. At 0 this is the
		# plain upright blade; at 1 it is almost flat on the ground.
		var rise := height * t * (1.0 - flatten)
		var reach := lean * t * t + height * t * flatten
		var pos := root + Vector3(0.0, rise, 0.0) + dir * reach
		var half := width * 0.5 * (1.0 - pow(t, tip_sharpness))

		surface.verts.push_back(pos - right * half)
		surface.verts.push_back(pos + right * half)
		surface.normals.push_back(UP)
		surface.normals.push_back(UP)
		surface.uvs.push_back(Vector2(0.0, t))
		surface.uvs.push_back(Vector2(1.0, t))
		surface.colours.push_back(STEM_COLOUR)
		surface.colours.push_back(STEM_COLOUR)

	for i in rings:
		var a := base + i * 2
		surface.indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])


## Adopts an imported mesh (your own .glb tuft) into this system: forces every
## normal to +Y, rewrites UV.y to normalised height, and stamps a stem vertex
## colour, so the wind bend weight and palette selection the shader expects are
## present whatever the source authored.
static func adopt_imported_mesh(source: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface_index in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface_index)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]

		var max_y := 0.0
		for v in verts:
			max_y = maxf(max_y, v.y)
		if max_y <= 0.0:
			max_y = 1.0

		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(UP)
		arrays[Mesh.ARRAY_NORMAL] = normals

		var existing := PackedVector2Array()
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			existing = arrays[Mesh.ARRAY_TEX_UV]
		var uvs := PackedVector2Array()
		uvs.resize(verts.size())
		for i in verts.size():
			var u := 0.5
			if i < existing.size():
				u = existing[i].x
			uvs[i] = Vector2(u, clampf(verts[i].y / max_y, 0.0, 1.0))
		arrays[Mesh.ARRAY_TEX_UV] = uvs

		var colours := PackedColorArray()
		colours.resize(verts.size())
		colours.fill(STEM_COLOUR)
		arrays[Mesh.ARRAY_COLOR] = colours

		# Tangents are meaningless once every normal is +Y, and a stale tangent
		# array makes Godot warn on load.
		arrays[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
