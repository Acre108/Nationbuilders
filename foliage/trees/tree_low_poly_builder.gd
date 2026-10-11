class_name TreeLowPolyBuilder
extends RefCounted

## Painted woody foliage. Same root, vertex channels and TreeVariant
## contract as the card builder; placement and species order are untouched.
static func supports(species: TreeCardBuilder.Species) -> bool:
	return species.name in ["oak", "birch", "spruce", "fir", "pine", "rounded-shrub", "low-hedge"]


static func build(species: TreeCardBuilder.Species, seed: int) -> TreeVariant:
	assert(supports(species))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var h := species.height * rng.randf_range(0.92, 1.08)
	var canopy := TreeMeshData.new(h)
	var bark := TreeMeshData.new(h)
	var proxy := TreeMeshData.new(h)
	var colour := species.bark_colour.srgb_to_linear()
	var shrub := species.name in ["rounded-shrub", "low-hedge"]
	var birch := species.name == "birch"
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.25, 0.25)) * (0.12 if shrub else 1.0)
	var mid := Vector3(0, h * (0.22 if shrub else 0.38), 0) + lean * 0.4
	var top := Vector3(0, h * (0.62 if shrub else 0.94), 0) + lean
	var root := Vector3(0, -minf(0.25, h * 0.15), 0)
	var tip_radius := minf(0.025, species.trunk_radius * 0.3)
	_tube(bark, root, mid, species.trunk_radius * 1.4, species.trunk_radius, colour, birch)
	_tube(bark, mid, top, species.trunk_radius, tip_radius, colour, birch)
	proxy.add_tube(root, top, species.trunk_radius, tip_radius, 5, colour)
	if species.name == "oak":
		# Authored proportions, seeded small deviations. Different heights and
		# overlapping shoulders leave pockets of sky between the lower masses.
		var centres := [Vector3(-0.22, 0.56, 0.03), Vector3(0.23, 0.60, 0.02),
			Vector3(-0.08, 0.65, -0.21), Vector3(0.10, 0.52, 0.22),
			Vector3(-0.17, 0.75, 0.13), Vector3(0.15, 0.77, -0.10), Vector3(0.0, 0.85, 0.01)]
		for i in centres.size():
			var centre: Vector3 = centres[i] * h + lean
			centre += Vector3(rng.randf_range(-0.025, 0.025), rng.randf_range(-0.018, 0.018), rng.randf_range(-0.025, 0.025)) * h
			var r := h * rng.randf_range(0.18, 0.215)
			if i == 6:
				r *= 0.79
			var radii := Vector3(r * 1.12, r * 0.82, r)
			_mass(canopy, centre, radii, rng, false, rng.randf_range(-0.065, 0.065))
			# Fit inside the planar faces, not merely inside their bounding box.
			# An 88% ellipsoid protrudes through the narrower lower shoulders.
			proxy.add_ellipsoid(centre, radii * 0.66, 5, 3, colour)
			var start := mid.lerp(top, clampf((centre.y / h - 0.4) * 0.65, 0, 1))
			_tube(bark, start, centre, species.trunk_radius * 0.64, 0.055, colour)
	elif birch or species.name == "pine":
		# Birch: a slim, upright crown on a pale stem. Pine: exposed trunk
		# and broad, flattened pads, clustered into an open upper crown.
		var centres := [Vector3(-0.09, 0.48, 0.02), Vector3(0.10, 0.59, 0.04),
			Vector3(-0.07, 0.67, -0.08), Vector3(0.10, 0.74, -0.03),
			Vector3(-0.08, 0.80, 0.06), Vector3(0.05, 0.86, 0.04), Vector3(0.0, 0.91, 0.0)] if birch else [
			Vector3(-0.18, 0.57, 0.03), Vector3(0.15, 0.67, 0.08),
			Vector3(-0.07, 0.77, -0.17), Vector3(0.10, 0.85, -0.02), Vector3(-0.04, 0.94, 0.04)]
		for i in centres.size():
			var centre: Vector3 = centres[i] * h + lean
			centre += Vector3(rng.randf_range(-0.018, 0.018), rng.randf_range(-0.012, 0.012), rng.randf_range(-0.018, 0.018)) * h
			var r := h * rng.randf_range(0.105, 0.125) if birch else h * rng.randf_range(0.17, 0.20)
			if i == centres.size() - 1:
				r *= 0.7
			var radii := Vector3(r, r * 1.2, r * 0.9) if birch else Vector3(r * 1.15, r * 0.43, r)
			_mass(canopy, centre, radii, rng, false, species.palette_shift + rng.randf_range(-0.05, 0.05), not birch)
			proxy.add_ellipsoid(centre, radii * 0.66, 5, 3, colour)
			var start := mid.lerp(top, clampf((centre.y / h - 0.4) * 0.75, 0, 1))
			_tube(bark, start, centre, species.trunk_radius * 0.6, species.trunk_radius * 0.18, colour, birch)
	elif shrub:
		var hedge := species.name == "low-hedge"
		for i in 4:
			var angle := float(i) * TAU / 4.0 + 0.4
			var centre := Vector3(cos(angle) * 0.29, 0.48 + (0.0 if hedge else rng.randf_range(-0.05, 0.12)), sin(angle) * 0.23) * h
			var radii := Vector3(0.48 if hedge else 0.43, 0.46 if hedge else 0.49, 0.43) * h
			radii *= rng.randf_range(0.94, 1.06)
			_mass(canopy, centre, radii, rng, false, species.palette_shift + rng.randf_range(-0.04, 0.04))
			proxy.add_ellipsoid(centre, radii * 0.66, 5, 3, colour)
	else:
		var fir := species.name == "fir"
		var tiers := 9 if fir else 8
		for tier in tiers:
			var f := float(tier) / float(tiers - 1)
			var y := lerpf(0.15 if fir else 0.17, 0.86, f) * h
			var r := h * lerpf(0.285 if fir else 0.235, 0.055 if fir else 0.047, f) * rng.randf_range(0.94, 1.06)
			var centre := Vector3(lean.x * f, y, lean.z * f)
			if fir:
				centre += Vector3(sin(tier * 2.4), 0, cos(tier * 2.4)) * h * 0.018 * (1.0 - f)
			var radii := Vector3(r, h * lerpf(0.18, 0.14, f), r * rng.randf_range(0.85, 1.05))
			_mass(canopy, centre, radii, rng, true, rng.randf_range(-0.05, 0.05))
			proxy.add_ellipsoid(centre - Vector3(0, radii.y * 0.18, 0), radii * Vector3(0.61, 0.43, 0.61), 5, 3, colour)
	var result := TreeVariant.new()
	result.species = species.name
	result.height = h
	result.canopy_mesh = canopy.commit()
	result.bark_mesh = bark.commit()
	result.proxy_mesh = proxy.commit()
	result.triangles = canopy.triangle_count() + bark.triangle_count()
	result.proxy_triangles = proxy.triangle_count()
	return result


static func _mass(mesh: TreeMeshData, centre: Vector3, radii: Vector3, rng: RandomNumberGenerator, conifer: bool, shift: float, needle_paint: bool = false) -> void:
	const SIDES := 7
	var spin := rng.randf() * TAU
	var rings: Array[PackedVector3Array] = []
	# Spruce's widest skirt sits low, tapering into the tier above.
	var ys := [-0.49, -0.27, 0.36] if conifer else [-0.68, 0.03, 0.67]
	var rs := [0.68, 1.0, 0.50] if conifer else [0.64, 1.0, 0.70]
	var rim := PackedFloat32Array()
	for s in SIDES:
		rim.append(rng.randf_range(0.82, 1.15))
	for ring in 3:
		var points := PackedVector3Array()
		for s in SIDES:
			var angle := TAU * float(s) / SIDES + spin
			var p := Vector3(cos(angle) * float(rs[ring]) * rim[s], float(ys[ring]) + rng.randf_range(-0.10, 0.10), sin(angle) * float(rs[ring]) * rim[s])
			points.append(centre + p * radii)
		rings.append(points)
	var bottom := centre - Vector3(0, radii.y * 0.82, 0)
	var tip := centre + Vector3(radii.x * 0.08, radii.y, radii.z * 0.03)
	for s in SIDES:
		var next := (s + 1) % SIDES
		_face(mesh, bottom, rings[0][next], rings[0][s], centre, radii, shift, conifer or needle_paint)
		for ring in 2:
			_face(mesh, rings[ring][s], rings[ring][next], rings[ring + 1][s], centre, radii, shift, conifer or needle_paint)
			_face(mesh, rings[ring][next], rings[ring + 1][next], rings[ring + 1][s], centre, radii, shift, conifer or needle_paint)
		_face(mesh, rings[2][s], rings[2][next], tip, centre, radii, shift, conifer or needle_paint)


static func _face(mesh: TreeMeshData, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, radii: Vector3, shift: float, conifer: bool) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - centre) < 0:
		normal = -normal
	else:
		# Godot front faces are clockwise.
		var swap := b
		b = c
		c = swap
	var ids := PackedInt32Array()
	for p in [a, b, c]:
		var radial: Vector3 = (p - centre) / radii
		var n := normal.lerp(radial.normalized(), 0.30).normalized()
		var interior := clampf(0.45 - radial.y * 0.45, 0, 1)
		# Alpha carries warm top-plane paint. Flutter stays near zero.
		var colour := Color(interior, 0.025, 0.5 + shift, clampf(radial.y * 0.5 + 0.5, 0, 1))
		# Local planar UVs remain attached to each crown mass in wind.
		var projection := Vector2(radial.z if absf(normal.x) > absf(normal.z) else radial.x, radial.y)
		if normal.y > 0.7:
			projection = Vector2(radial.x, radial.z)
		var uv := projection * Vector2(0.20, -0.20) + Vector2(0.25, 0.25)
		if conifer:
			uv.x += 0.5
		ids.append(mesh.add_vertex(p, n, colour, uv))
	mesh.add_triangle(ids[0], ids[1], ids[2])


static func _tube(mesh: TreeMeshData, from: Vector3, to: Vector3, r0: float, r1: float, colour: Color, birch: bool = false) -> void:
	var axis := (to - from).normalized()
	var u := axis.cross(Vector3.RIGHT if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var v := u.cross(axis).normalized()
	for side in 6:
		var angle := float(side) * TAU / 6.0
		var next := float(side + 1) * TAU / 6.0
		var a := u * cos(angle) + v * sin(angle)
		var b := u * cos(next) + v * sin(next)
		var n := (a + b).normalized()
		var tint := colour * (0.92 + float(side % 3) * 0.08)
		tint.a = 0.5 # opts only this geometry into the painted bark atlas
		var start := mesh.verts.size()
		var tile_x := 0.54 if birch else 0.04
		mesh.add_vertex(from + a * r0, n, tint, Vector2(tile_x + side * 0.065, 0.96))
		mesh.add_vertex(from + b * r0, n, tint, Vector2(tile_x + (side + 1) * 0.065, 0.96))
		mesh.add_vertex(to + a * r1, n, tint, Vector2(tile_x + side * 0.065, 0.54))
		mesh.add_vertex(to + b * r1, n, tint, Vector2(tile_x + (side + 1) * 0.065, 0.54))
		mesh.add_triangle(start, start + 1, start + 2)
		mesh.add_triangle(start + 1, start + 3, start + 2)
