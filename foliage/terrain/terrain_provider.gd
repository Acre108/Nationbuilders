class_name TerrainProvider
extends RefCounted

## The one interface the grass system uses to ask questions about the ground.
##
## Everything that scatters grass goes through this, so swapping how terrain is
## authored -- procedural noise now, imported heightmaps for real locations
## later -- never touches the placer, the chunk manager or the shaders. This is
## also why we chose a custom chunked mesh over Terrain3D: this interface stays
## ours, and so does the terrain material, which Part 4 needs in order to share
## its palette and wind uniforms with the grass.
##
## Subclasses override get_height(), and optionally get_normal() and
## growth_mask_for(). Chunk-sized work (placement, ground meshes) goes through a
## TerrainTile, which samples get_height() once per grid point; `tile()` and
## `build_chunk_mesh()` have working defaults that are correct for any provider,
## but a heightmap-backed one should override them and read its data directly.

## Ground height in world units at a world XZ.
func get_height(_x: float, _z: float) -> float:
	return 0.0


## Surface normal at a world XZ.
##
## Default is central differences over get_height(). Providers that know their
## surface analytically should override, but the default is accurate enough for
## slope masking and for tilting tufts to follow the ground.
func get_normal(x: float, z: float, epsilon: float = 0.35) -> Vector3:
	var hl := get_height(x - epsilon, z)
	var hr := get_height(x + epsilon, z)
	var hd := get_height(x, z - epsilon)
	var hu := get_height(x, z + epsilon)
	return Vector3(hl - hr, 2.0 * epsilon, hd - hu).normalized()


## Surface-water marks the ground mesh carries to the terrain shader as vertex
## colour: x = riverbed (1 under a channel's water), y = damp bank. Only
## providers that carve their own channels (HeightmapTerrainProvider with
## imported rivers) report any; everyone else builds colourless meshes.
func has_water_marks() -> bool:
	return false


func water_marks(_x: float, _z: float) -> Vector2:
	return Vector2.ZERO


## Surface water as a field (rivers and lakes as one surface), for
## build_water_arrays(): whether `area` (world XZ) may hold any, and the water
## at a point -- see ImportedRivers.water_at() for the layout. Only
## HeightmapTerrainProvider with fitted imports has one.
func has_water_field(_area: Rect2) -> bool:
	return false


func water_sample(_x: float, _z: float, _margin: float, _min_width := 0.0) -> PackedFloat32Array:
	return PackedFloat32Array()


## Growth mask in 0..1 at a world XZ. 0 means no grass here at all.
##
## This is where paths, water, indoor footprints and painted bare patches come
## from. Returning a float rather than a bool lets the placer thin grass out
## towards an edge instead of cutting a hard line, which is what stops paths
## looking like they were stamped with a cookie cutter.
##
## Subclasses override growth_mask_for(), not this.
func get_growth_mask(x: float, z: float) -> float:
	return growth_mask_for(x, z, get_normal(x, z))


## The growth mask given the ground normal already in hand. Split out so a
## TerrainTile can supply the normal from its grid instead of the provider
## differencing four more heights for it.
##
## The default is the painted mask alone (see set_painted_mask). Subclasses
## multiply in their own limits -- NoiseTerrainProvider adds slope -- and should
## keep multiplying in sample_painted_mask(), or the location's painted mask
## stops applying.
func growth_mask_for(x: float, z: float, _normal: Vector3) -> float:
	return sample_painted_mask(x, z)


## Growth mask for TREE-family placement specifically (TreePlacer's trees and
## conifers) -- deliberately separate from get_growth_mask(). A real
## mountain's treeline can sit hundreds of metres below where bare rock
## starts (see TerrainProfile.treeline), and grass/shrubs/cushion plants must
## NOT be gated by it -- alpine meadow lives between the treeline and the
## rock line. Folding a treeline into growth_mask_for() would wrongly thin
## every family at once instead of only the tree canopy.
##
## Always the growth mask times tree_mask_factor(): subclasses override the
## factor, not this, so EnvironmentZones can reuse a growth mask it already
## has. A provider with no notion of a treeline (NoiseTerrainProvider, or any
## provider that never sets one) keeps the factor at 1.
func get_tree_mask(x: float, z: float) -> float:
	var mask := get_growth_mask(x, z)
	return mask * tree_mask_factor(x, z) if mask > 0.0 else mask


## World Z sign of north: +1 when north is +Z, -1 when it is -Z. Procedural
## ground has no real north and keeps +Z. Used for aspect (north-facing moss).
func north_z() -> float:
	return 1.0


## What get_tree_mask() adds on top of the growth mask, 0..1: the treeline,
## and an imported site's tree mask. Default 1.
func tree_mask_factor(_x: float, _z: float) -> float:
	return 1.0


## An imported site's mask for woody growth (trees, shrubs, ferns), 0..1:
## lawns, yards and paved ground mapped as no-trees. Default 1. Part of
## tree_mask_factor(); EnvironmentZones.understorey_mask() uses it alone, so
## shrubs and ferns follow the site but not the treeline.
func site_tree_mask(_x: float, _z: float) -> float:
	return 1.0


## Painted zone overrides (Location Studio S4), or null. Declared here, not
## on HeightmapTerrainProvider, so hot paths can test it with a typed null
## check before any call. Immutable: an edit assigns a new object
## (copy-on-write), so workers never see a half-applied edit.
var zone_overrides: ZoneOverrides


## A painted environment-zone override at a world XZ (ZoneOverrides):
## Vector2(zone, strength 0..1), or Vector2(-1, 0) where nothing is painted.
func zone_override(x: float, z: float) -> Vector2:
	return zone_overrides.sample(x, z) if zone_overrides != null else Vector2(-1.0, 0.0)


## True when this ground can carry painted zones (Location Studio S4): its
## layers keep zone sampling live even where recipes look neutral.
func paintable() -> bool:
	return zone_overrides != null


## Painted overrides overlapping a world rect, {zone: true}; empty when none.
## Lets placers skip per-point override work in unpainted chunks.
func painted_zones_in(area: Rect2) -> Dictionary:
	return zone_overrides.zones_in(area) if zone_overrides != null else {}


## Whether this ground carries observed zone data (an imported site's zone
## mask). Without it, EnvironmentZones infers everything from noise and
## terrain, as for procedural locations.
func has_observed_zones() -> bool:
	return false


## How much the observed data applies at a world XZ (0..1): 1 where it covers
## the ground, fading to 0 beyond a partial imported site, where zones are
## inferred as for procedural ground.
func observed_coverage(_x: float, _z: float) -> float:
	return 1.0


## Observed zone weights (r wetland, g garden, b scrub, a forest), 0..1 each.
func observed_zones(_x: float, _z: float) -> Color:
	return Color(0, 0, 0, 0)


## Observed settlements and roadside: r village, g town, b roadside verge,
## a the verge's road context (0 rural, ~0.5 village, 1 town).
func observed_settlement(_x: float, _z: float) -> Color:
	return Color(0, 0, 0, 0)


## Whether the observed site carries a habitat mask (DUNE, HEATH zones).
func has_observed_habitats() -> bool:
	return false


## Observed coastal and heath habitats: r dune grassland, g heath, b open
## sand or beach, each 0..1.
func observed_habitat(_x: float, _z: float) -> Color:
	return Color(0, 0, 0, 0)


## Mapped farmland (arable fields), 0..1.
func farmland_cover(_x: float, _z: float) -> float:
	return 0.0


## How much open water (imported or procedural rivers, lakes, sea) takes
## from the growth mask here, 0..1: the water part of growth_mask_for()'s
## exclusions, reported separately for EnvironmentZones. Default none.
func water_cover(_x: float, _z: float) -> float:
	return 0.0


## The altitude bands growth_mask_for() already multiplied in, reported
## separately for EnvironmentZones: x = high rock, y = snow, each 0..1.
## Default none: a provider with no altitude bands has neither.
func altitude_cover(_x: float, _z: float, _normal: Vector3) -> Vector2:
	return Vector2.ZERO


## The location's painted growth mask: red channel, 1 = grass, 0 = bare,
## stretched across `bounds` in world XZ. Comes from FoliageProfile.growth_mask
## via FoliageLocation. Null clears it.
##
## Copied into a flat float array once, rather than sampled with
## Image.get_pixel(): placement asks for the mask a few hundred thousand times
## per build, and this also keeps sampling free of Image calls for the streaming
## worker threads.
func set_painted_mask(image: Image, bounds: Rect2) -> void:
	_mask_bounds = bounds
	_mask = PackedFloat32Array()
	_mask_size = Vector2i.ZERO
	if image == null:
		return
	var source := image
	if source.is_compressed():
		source = image.duplicate()
		source.decompress()
	_mask_size = Vector2i(source.get_width(), source.get_height())
	_mask.resize(_mask_size.x * _mask_size.y)
	for y in _mask_size.y:
		for x in _mask_size.x:
			_mask[y * _mask_size.x + x] = source.get_pixel(x, y).r


func has_painted_mask() -> bool:
	return not _mask.is_empty()


## Bilinear, so a soft-edged painted path thins grass smoothly rather than in
## pixel-sized steps. 1.0 outside the mask's bounds: an unpainted world grows.
func sample_painted_mask(x: float, z: float) -> float:
	if _mask.is_empty():
		return 1.0
	var u := (x - _mask_bounds.position.x) / _mask_bounds.size.x
	var v := (z - _mask_bounds.position.y) / _mask_bounds.size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return 1.0
	# Pixel centres sit at half-pixel offsets, matching how the terrain shader
	# samples the same texture with filter_linear.
	var fx := clampf(u * float(_mask_size.x) - 0.5, 0.0, float(_mask_size.x - 1))
	var fy := clampf(v * float(_mask_size.y) - 0.5, 0.0, float(_mask_size.y - 1))
	var x0 := int(fx)
	var y0 := int(fy)
	var x1 := mini(x0 + 1, _mask_size.x - 1)
	var y1 := mini(y0 + 1, _mask_size.y - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var w := _mask_size.x
	var top := lerpf(_mask[y0 * w + x0], _mask[y0 * w + x1], tx)
	var bottom := lerpf(_mask[y1 * w + x0], _mask[y1 * w + x1], tx)
	return lerpf(top, bottom, ty)


var _mask := PackedFloat32Array()
var _mask_size := Vector2i.ZERO
var _mask_bounds := Rect2()


## Convenience: the full placement query in one call, so the placer does not
## pay for three separate virtual dispatches per candidate tuft.
## Returns {position: Vector3, normal: Vector3, mask: float}.
func sample(x: float, z: float) -> Dictionary:
	return {
		"position": Vector3(x, get_height(x, z), z),
		"normal": get_normal(x, z),
		"mask": get_growth_mask(x, z),
	}


## Grid spacing of the finest ground mesh: TerrainLayer's 64 m chunks at 48
## quads a side. Placement tiles use the same lattice, so grass stands on the
## triangles that are actually drawn. Change it with TerrainLayer.RESOLUTIONS.
const TILE_SPACING := 64.0 / 48.0

## Coarser than this, ground meshes take vertex normals from get_normal()
## rather than their grid (see TerrainTile.build's exact_normals). Keeps the
## middle and far rings lit like the near ring where they meet.
const GRID_NORMAL_MAX_SPACING := 2.0


## This provider's ground over `area`, sampled once onto the TILE_SPACING
## lattice, for code that is about to ask many questions inside it -- chunk
## placement. A provider with its own grid (a heightmap) can override this to
## hand out views of that grid instead.
func tile(area: Rect2) -> TerrainTile:
	return TerrainTile.covering(self, area, TILE_SPACING)


## Visible ground geometry for one chunk, as a flat grid sampled from
## get_height(). `resolution` is quads per side.
func build_chunk_mesh(origin: Vector2, size: float, resolution: int, skirt_depth: float = 0.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, build_chunk_arrays(origin, size, resolution, skirt_depth))
	return mesh


## The vertex arrays behind build_chunk_mesh(), without creating the mesh --
## so streaming can sample the terrain on a worker thread and leave only mesh
## creation to the main thread. Safe on a worker as long as get_height() and
## get_normal() are (they are for NoiseTerrainProvider).
##
## `skirt_depth` > 0 hangs a vertical strip that deep below every edge. Chunks
## at different detail levels do not meet exactly -- a coarse edge cuts
## straight across bumps a fine neighbour follows -- and without skirts the
## gap shows sky. The skirt fills it with ground-coloured wall that nobody
## notices. `skirt_depth` < 0 measures the depth instead (see _edge_error()):
## deep enough for this chunk's own edges on this terrain, and no deeper.
##
## `grid_normals` forces normals from the grid even when it is coarser than
## GRID_NORMAL_MAX_SPACING. The horizon ring uses it: out there the lighting
## difference cannot be seen, and exact normals would quadruple the samples.
func build_chunk_arrays(origin: Vector2, size: float, resolution: int, skirt_depth: float = 0.0, grid_normals: bool = false) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var step := size / float(resolution)
	# Each height sampled once, and normals differenced from the same grid
	# rather than four more samples per vertex. Placement tiles are laid on
	# this lattice too (TILE_SPACING), which is what makes them agree with
	# the drawn surface.
	var grid := TerrainTile.build(self, origin, step, resolution, resolution, step > GRID_NORMAL_MAX_SPACING and not grid_normals)
	var marked := has_water_marks()
	var colours := PackedColorArray()
	for iz in resolution + 1:
		for ix in resolution + 1:
			# Local space, so the mesh can be reused under a translated node and
			# so large-coordinate locations do not push float precision in the
			# vertex buffer.
			verts.push_back(Vector3(float(ix) * step, grid.height_at(ix, iz), float(iz) * step))
			normals.push_back(grid.normal_at(ix, iz))
			uvs.push_back(Vector2(float(ix) / float(resolution), float(iz) / float(resolution)))
			if marked:
				var marks := water_marks(origin.x + float(ix) * step, origin.y + float(iz) * step)
				colours.push_back(Color(marks.x, marks.y, 0.0, 1.0))

	# Winding matters: Godot culls back faces on the terrain material (grass is
	# cull_disabled, terrain is not, because double-siding a surface this large
	# is wasted fill). Emitting these in the other order makes the whole terrain
	# face downwards and vanish, leaving the sky's ground hemisphere showing
	# through the grass -- which looks like a white ground rather than a missing
	# one, so it does not read as a culling bug at first glance.
	var row := resolution + 1
	for iz in resolution:
		for ix in resolution:
			var a := iz * row + ix
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])

	if skirt_depth < 0.0:
		skirt_depth = _edge_error(grid) * 2.0 + 0.5
	if skirt_depth > 0.0:
		var edges := [
			[range(0, row), Vector3(0, 0, -1)],                                # z = 0
			[range(resolution * row, row * row), Vector3(0, 0, 1)],             # z = size
			[range(0, row * row, row), Vector3(-1, 0, 0)],                      # x = 0
			[range(resolution, row * row, row), Vector3(1, 0, 0)],              # x = size
		]
		for edge in edges:
			var along: Array = edge[0]
			var outward: Vector3 = edge[1]
			var base := verts.size()
			for i in along:
				verts.push_back(verts[i] - Vector3(0.0, skirt_depth, 0.0))
				normals.push_back(normals[i])
				uvs.push_back(uvs[i])
				if marked:
					colours.push_back(colours[i])
			for k in along.size() - 1:
				var a: int = along[k]
				var b: int = along[k + 1]
				var c := base + k + 1
				var d := base + k
				# Face the skirt outwards whatever order the edge runs in:
				# Godot's front face has cross(b - a, c - a) pointing AWAY from
				# the viewer, i.e. inwards here.
				var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
				if n.dot(outward) < 0.0:
					indices.append_array([a, b, c, a, c, d])
				else:
					indices.append_array([a, c, b, a, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if marked:
		arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Flow is packed into vertex colour as rg = flow / WATER_FLOW_RANGE * 0.5 + 0.5
## (water.gdshader unpacks it with the same range).
const WATER_FLOW_RANGE := 4.0
## Adjacent water vertices further apart in level than this (plus a share of
## the lattice spacing, for steep reaches on coarse rings) are either side of
## a waterfall: no surface between them, the curtain draws the drop.
const WATER_STEP_MAX := 1.5
## Lattices finer than this mesh every channel; coarser ones only channels
## at least two cells wide.
const WATER_FINE_SPACING := 2.0


## One chunk's surface water, on the same lattice as its ground
## (build_chunk_arrays()): every quad half with at least one wet vertex, at
## the field's level, so rivers, their confluences and the lakes they run into
## are one mesh with no ends or overlaps. Vertex colour carries flow (rg) and
## foam (b), UV2.x the water's width (for shading). Empty when the chunk holds
## no water.
func build_water_arrays(origin: Vector2, size: float, resolution: int) -> Array:
	var step := size / float(resolution)
	if not has_water_field(Rect2(origin, Vector2.ONE * size).grow(step * 2.0)):
		return []
	# Vertices this far beyond the waterline still take the level, so a quad
	# reaching out of the water closes under the bank.
	var margin := step * 1.5
	# A coarse lattice cannot hold a channel under two cells wide: past the
	# near ring those are painted into the ground instead (terrain.gdshader).
	var min_width := step * 2.0 if step > WATER_FINE_SPACING else 0.0
	var row := resolution + 1
	var levels := PackedFloat32Array()
	levels.resize(row * row)
	var wet := PackedByteArray()
	wet.resize(row * row)
	var samples: Array[PackedFloat32Array] = []
	samples.resize(row * row)
	var any_wet := false
	for iz in row:
		for ix in row:
			var i := iz * row + ix
			var sample := water_sample(origin.x + float(ix) * step, origin.y + float(iz) * step, margin, min_width)
			samples[i] = sample
			levels[i] = NAN if sample.is_empty() else sample[0]
			if not sample.is_empty() and sample[5] > 0.5:
				wet[i] = 1
				any_wet = true
	if not any_wet:
		return []
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var remap := PackedInt32Array()
	remap.resize(row * row)
	remap.fill(-1)
	var step_max := WATER_STEP_MAX + step * 0.25
	for iz in resolution:
		for ix in resolution:
			var a := iz * row + ix
			# Same diagonal and winding as build_chunk_arrays().
			for tri in [[a, a + 1, a + row], [a + 1, a + row + 1, a + row]]:
				if not (wet[tri[0]] or wet[tri[1]] or wet[tri[2]]):
					continue
				var la: float = levels[tri[0]]
				var lb: float = levels[tri[1]]
				var lc: float = levels[tri[2]]
				if is_nan(la) or is_nan(lb) or is_nan(lc):
					continue
				if maxf(la, maxf(lb, lc)) - minf(la, minf(lb, lc)) > step_max:
					continue
				for v: int in tri:
					if remap[v] < 0:
						remap[v] = verts.size()
						var sample := samples[v]
						verts.push_back(Vector3(float(v % row) * step, sample[0], float(v / row) * step))
						normals.push_back(Vector3.UP)
						colours.push_back(Color(
							clampf(sample[1] / WATER_FLOW_RANGE * 0.5 + 0.5, 0.0, 1.0),
							clampf(sample[2] / WATER_FLOW_RANGE * 0.5 + 0.5, 0.0, 1.0),
							sample[3], 1.0))
						# UV2.y: the tidal weight (ImportedRivers.mark_tidal(), SEA8).
						uv2s.push_back(Vector2(sample[4], sample[6] if sample.size() > 6 else 0.0))
					indices.append(remap[v])
	if indices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Largest height difference between this chunk's edge (straight lines between
## its edge vertices) and the true ground under it, sampled at quarter points.
##
## A finer neighbour's edge follows the true ground more closely, so the gap
## between the two is at most this plus the neighbour's own (smaller) error --
## which is why the skirt is twice it. Measured rather than derived from the
## grid spacing: the old spacing-based formula hung 13 m skirts on flat
## meadow and would still be too shallow on a steep valley wall.
func _edge_error(grid: TerrainTile) -> float:
	var worst := 0.0
	var step := grid.spacing
	for side in 4:
		for k in grid.cells_x:
			var a := Vector2i(k, 0)
			var b := Vector2i(k + 1, 0)
			match side:
				1:
					a = Vector2i(k, grid.cells_z)
					b = Vector2i(k + 1, grid.cells_z)
				2:
					a = Vector2i(0, k)
					b = Vector2i(0, k + 1)
				3:
					a = Vector2i(grid.cells_x, k)
					b = Vector2i(grid.cells_x, k + 1)
			var ha := grid.height_at(a.x, a.y)
			var hb := grid.height_at(b.x, b.y)
			for q: float in [0.25, 0.5, 0.75]:
				var p := grid.origin + (Vector2(a) + Vector2(b - a) * q) * step
				worst = maxf(worst, absf(get_height(p.x, p.y) - lerpf(ha, hb, q)))
	return worst
