class_name GrassCardBuilder
extends RefCounted

## Crossed-quad grass clump cards, textured from the sprite atlas that
## `tools/blender/make_grass_sprites.py` renders.
##
## This replaces the per-blade geometry in GrassTuftBuilder as the default. The
## trade it makes, stated plainly because it reverses an earlier decision:
##
##   Geometry blades   -- fully opaque, no sorting, no discard. ~88 triangles per
##                        clump, and closing the ground needed a procumbent mat
##                        that read as flat papery sheets.
##   Sprite cards      -- ~24 triangles per clump, and coverage comes from the
##                        texture rather than from more geometry. Costs an alpha
##                        scissor, so grass now needs a depth prepass.
##
## At the densities here the triangle saving is worth the prepass, and the sprite
## is simply a better way to draw a clump than trying to model one.
##
## Atlas addressing: each quad carries a quad index in UV2.x, and the shader
## picks its tile as `(instance_variant + quad_index) mod 4`. So one card shows
## three DIFFERENT clump sprites crossed, and which three depends on the
## instance -- giving variety from a single mesh and a single MultiMesh, rather
## than needing four meshes and four draw calls per chunk.

const UP := Vector3.UP
const ATLAS_TILES := 4


class CardConfig extends RefCounted:
	## Quads crossed through the clump centre. 3 reads well from any angle; 2 is
	## visibly flat when you orbit; 4 rarely earns its triangles.
	var quad_count: int = 3
	## Vertical subdivisions. Needed so wind bends the card in a curve rather
	## than shearing it as a rigid parallelogram.
	var segments: int = 4
	var height: float = 0.45
	## Card width as a multiple of height. The atlas tiles are square and the
	## clump fills its tile, so ~1.0 keeps the sprite undistorted.
	var aspect: float = 1.1

	func copy() -> CardConfig:
		var c := CardConfig.new()
		c.quad_count = quad_count
		c.segments = segments
		c.height = height
		c.aspect = aspect
		return c


## Builds one clump card.
##
## `seed` only jitters the quad angles, so every instance can share this mesh --
## per-clump variety comes from the placer's transform and from the per-instance
## atlas tile, not from unique geometry, which would defeat MultiMesh entirely.
static func build_card(config: CardConfig, seed: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	var half_width := config.height * config.aspect * 0.5
	var rings := maxi(1, config.segments)

	for quad in config.quad_count:
		# Spread quads evenly over a half turn, not a full one: a quad and its
		# 180-degree twin are the same plane, so a full turn would build
		# duplicate coplanar geometry.
		var angle := (float(quad) / float(config.quad_count)) * PI + rng.randf_range(-0.12, 0.12)
		var right := Vector3(sin(angle), 0.0, cos(angle))
		var base := verts.size()

		for i in rings + 1:
			var t := float(i) / float(rings)
			var y := config.height * t
			for side in [-1.0, 1.0]:
				verts.push_back(right * (half_width * side) + Vector3(0.0, y, 0.0))
				# Forced +Y, same as the geometry path and for the same reason:
				# it makes a field of cards light as one soft surface instead of
				# thousands of separately shaded planes.
				normals.push_back(UP)
				# UV.y is normalised HEIGHT (0 root, 1 tip), not texture V. The
				# shader flips it when addressing the atlas. Keeping height here
				# preserves the wind bend-weight contract every other part of the
				# system relies on.
				uvs.push_back(Vector2(side * 0.5 + 0.5, t))
				uv2s.push_back(Vector2(float(quad), 0.0))
				# Vertex colour red marks petals for the flower path; cards are
				# never petals, and a missing colour array would read as white.
				colours.push_back(Color(0.0, 0.0, 0.0, 1.0))

		for i in rings:
			var a := base + i * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Encodes an atlas tile index into the 0..1 range MultiMesh custom data carries.
## Divided rather than stored raw so the value stays inside 0..1 and cannot be
## clipped by anything that treats custom data as a colour.
static func encode_variant(variant: int) -> float:
	return float(variant % ATLAS_TILES) / float(ATLAS_TILES)
