class_name TreeMeshData
extends RefCounted

## Accumulates one tree part's vertex streams, in the layout every tree shader
## expects:
##
##   UV2   x = normalised height up the tree (0 root, 1 top)
##         y = model-space tree height in metres
##   COLOR leaves: r = interior depth, g = flutter weight, b = palette shift + 0.5
##         bark:   linear RGB bark colour
##
## UV2 is baked identically into canopy, bark and shadow proxy -- it is the
## only way tree_wind.gdshaderinc can give all three the same sway. Anything
## that builds a tree part must go through add_vertex() with the tree's real
## height, or that part will sway out of step with the rest.

var height: float
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var colours := PackedColorArray()
var indices := PackedInt32Array()


func _init(tree_height: float) -> void:
	height = maxf(tree_height, 0.01)


func add_vertex(position: Vector3, normal: Vector3, colour: Color, uv := Vector2.ZERO) -> int:
	verts.push_back(position)
	normals.push_back(normal)
	uvs.push_back(uv)
	uv2s.push_back(Vector2(clampf(position.y / height, 0.0, 1.0), height))
	colours.push_back(colour)
	return verts.size() - 1


func add_triangle(a: int, b: int, c: int) -> void:
	indices.append_array([a, b, c])


func triangle_count() -> int:
	return indices.size() / 3


## A tapered, closed-sided tube from `from` to `to`. Ends are left open: they
## are either buried in the ground, inside another branch, or inside a clump.
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
		# Godot treats clockwise-from-the-viewer as front facing (the terrain's
		# winding note has the same trap), so these are ordered to face OUT:
		# the bark material culls back faces.
		add_triangle(base + i, base + j, base + sides + i)
		add_triangle(base + j, base + sides + j, base + sides + i)


## A coarse ellipsoid, for shadow proxies. `rings` x `segments` quads.
func add_ellipsoid(centre: Vector3, radii: Vector3, segments: int, rings: int, colour: Color) -> void:
	var base := verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segments + 1:
			var theta := TAU * float(s) / float(segments)
			var n := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			add_vertex(centre + n * radii, n, colour)
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
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
