class_name DebrisMeshData
extends RefCounted

## Accumulates one debris part's vertex streams. The non-swaying cousin of
## TreeMeshData: rocks and fallen logs are static geometry, so there is no
## UV2 height/wind baking here, only position, normal, UV and a per-vertex
## COLOR the shader reads as albedo. add_tube() is ported verbatim from
## TreeMeshData (see it for the winding note) rather than shared, since the
## two classes' add_vertex() write different attributes and a common base
## would need one of them to carry data the other never uses.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colours := PackedColorArray()
var indices := PackedInt32Array()


func add_vertex(position: Vector3, normal: Vector3, colour: Color, uv := Vector2.ZERO) -> int:
	verts.push_back(position)
	normals.push_back(normal)
	uvs.push_back(uv)
	colours.push_back(colour)
	return verts.size() - 1


func add_triangle(a: int, b: int, c: int) -> void:
	indices.append_array([a, b, c])


func triangle_count() -> int:
	return indices.size() / 3


## A tapered, closed-sided tube from `from` to `to`. Ends are left open --
## for a log, buried in the ground or capped by a root-ball blob instead.
func add_tube(from: Vector3, to: Vector3, radius_from: float, radius_to: float, sides: int, colour: Color) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	var base := verts.size()
	for ring in 2:
		var centre := from if ring == 0 else to
		var radius := radius_from if ring == 0 else radius_to
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var n := (side * cos(a) + up * sin(a)).normalized()
			add_vertex(centre + n * radius, n, colour)
	for i in sides:
		var j := (i + 1) % sides
		# Godot treats clockwise-from-the-viewer as front facing (see
		# TreeMeshData.add_tube()), so these face OUT: debris is solid,
		# not cull_disabled, and a flipped face would show as a black hole.
		add_triangle(base + i, base + j, base + sides + i)
		add_triangle(base + j, base + sides + j, base + sides + i)


## A rounded, gently lumpy blob -- a boulder, or a log's root-ball. The bumps
## come from 3D value noise sampled by direction, not per-vertex independent
## jitter, so neighbouring vertices correlate into smooth undulations instead
## of a spiky mess. Normals are left as the unbumped sphere direction: a
## small approximation, in the same spirit as the clump-normal shading the
## rest of the system already leans on for a soft, painterly read rather than
## an exactly-correct one.
func add_lumpy_blob(centre: Vector3, radii: Vector3, segments: int, rings: int, bumpiness: float, seed: int, colour: Color) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.seed = seed
	noise.frequency = 1.4
	var base := verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segments + 1:
			var theta := TAU * float(s) / float(segments)
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var bump := 1.0 + noise.get_noise_3dv(dir * 3.0) * bumpiness
			add_vertex(centre + dir * radii * bump, dir, colour, Vector2(float(s) / float(segments), float(r) / float(rings)))
	var row := segments + 1
	for r in rings:
		for s in segments:
			var a := base + r * row + s
			add_triangle(a, a + row, a + 1)
			add_triangle(a + 1, a + row, a + row + 1)


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
