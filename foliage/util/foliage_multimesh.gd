class_name FoliageMultiMesh
extends RefCounted

## Builds MultiMeshes from world-space transforms via one packed buffer write.
##
## Split in two so streaming can do the expensive half off the main thread:
## pack() is pure data and safe on a worker; from_buffer() creates the
## MultiMesh and must run on the main thread. build() does both, for callers
## that do not stream.
##
## One write instead of two engine calls per instance: for a 2,500-tuft grass
## chunk that was most of a refill's main-thread cost.


static func build(mesh: Mesh, transforms: Array[Transform3D], custom: PackedColorArray, origin: Vector3) -> MultiMesh:
	return from_buffer(mesh, transforms.size(), pack(transforms, custom, origin))


## Thread-safe. `origin` is the world position of the node that will hold the
## MultiMesh; transforms are converted into its local space. Layout per
## instance: the 3x4 transform row-major, then four custom floats (custom data
## on, per-instance colour off).
static func pack(transforms: Array[Transform3D], custom: PackedColorArray, origin: Vector3) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * 16)
	var o := 0
	for i in transforms.size():
		var b := transforms[i].basis
		var p := transforms[i].origin - origin
		var c := custom[i]
		buffer[o] = b.x.x
		buffer[o + 1] = b.y.x
		buffer[o + 2] = b.z.x
		buffer[o + 3] = p.x
		buffer[o + 4] = b.x.y
		buffer[o + 5] = b.y.y
		buffer[o + 6] = b.z.y
		buffer[o + 7] = p.y
		buffer[o + 8] = b.x.z
		buffer[o + 9] = b.y.z
		buffer[o + 10] = b.z.z
		buffer[o + 11] = p.z
		buffer[o + 12] = c.r
		buffer[o + 13] = c.g
		buffer[o + 14] = c.b
		buffer[o + 15] = c.a
		o += 16
	return buffer


## Main thread only.
static func from_buffer(mesh: Mesh, count: int, buffer: PackedFloat32Array) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# Must be set before instance_count or the buffer is allocated without room.
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	if count > 0:
		multimesh.buffer = buffer
	return multimesh
