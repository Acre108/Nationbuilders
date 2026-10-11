class_name TerrainTile
extends TerrainProvider

## A patch of another provider's ground, sampled once onto a grid and then
## answered from the grid.
##
## Placement asks for the height, the normal and the growth mask of every
## candidate tuft, and on NoiseTerrainProvider that is about nine noise
## evaluations each (the normal and the slope mask each difference four
## heights). A tile samples each grid point once, so the cost of a chunk scales
## with its area in grid cells, not with its tuft count. That matters more as
## the landform gets richer: mountains and valleys add noise layers, and every
## one of them would otherwise be paid per tuft.
##
## Between grid points it interpolates across the SAME two triangles per cell
## that TerrainProvider.build_chunk_arrays() emits, and its normals are the
## mesh's vertex normals interpolated the way the GPU does. So on a tile laid
## on the ground mesh's own lattice, a tuft's root lies exactly on the rendered
## surface, and the slope the grass placer thins by is the slope the terrain
## shader paints rock by.
##
## A tile holds no reference to nodes or servers and is built and read on one
## worker thread; the source provider is only read.
##
## Queries outside the tile fall through to the source, so a caller that
## strays past its chunk edge gets the right answer, just not the fast one.

var source: TerrainProvider
## World XZ of grid point (0, 0).
var origin := Vector2.ZERO
var spacing: float = 1.0
## Cells per side; grid points run 0..cells_x inclusive.
var cells_x: int = 0
var cells_z: int = 0

## Heights with a one-point margin all round, for the central differences at
## the edges: grid point (ix, iz) is at [(iz + 1) * _stride + ix + 1].
var _heights := PackedFloat32Array()
var _stride: int = 0
## Unit normals for grid points 0..cells inclusive, [iz * (cells_x + 1) + ix].
var _normals := PackedVector3Array()


## Samples `cells_x` x `cells_z` cells of `spacing` starting at `origin`.
##
## `exact_normals` takes vertex normals from source.get_normal() instead of
## differencing the grid. Grid normals are accurate while the spacing is fine
## next to the landform's features; on a coarse grid they smooth hills away,
## and the lighting would then change where a coarse ground chunk meets a
## finer one.
static func build(from: TerrainProvider, at: Vector2, step: float, count_x: int, count_z: int, exact_normals: bool = false) -> TerrainTile:
	var tile := TerrainTile.new()
	tile.source = from
	tile.origin = at
	tile.spacing = step
	tile.cells_x = count_x
	tile.cells_z = count_z
	tile._fill(exact_normals)
	return tile


## The smallest tile on the world lattice of `step` (grid points at whole
## multiples of it) that covers `area`. Two tiles over neighbouring areas share
## their edge points exactly, so nothing steps at a chunk seam.
static func covering(from: TerrainProvider, area: Rect2, step: float) -> TerrainTile:
	# The small bias keeps an edge that is a whole multiple of the step on
	# that point: 16.0 / (64.0 / 48.0) is 11.999..., not 12.
	var i0 := floori(area.position.x / step + 0.0001)
	var j0 := floori(area.position.y / step + 0.0001)
	var i1 := ceili(area.end.x / step - 0.0001)
	var j1 := ceili(area.end.y / step - 0.0001)
	return build(from, Vector2(float(i0), float(j0)) * step, step, maxi(i1 - i0, 1), maxi(j1 - j0, 1))


func _fill(exact_normals: bool) -> void:
	_stride = cells_x + 3
	_heights.resize(_stride * (cells_z + 3))
	for iz in range(-1, cells_z + 2):
		var wz := origin.y + float(iz) * spacing
		var row := (iz + 1) * _stride + 1
		for ix in range(-1, cells_x + 2):
			_heights[row + ix] = source.get_height(origin.x + float(ix) * spacing, wz)

	var points_x := cells_x + 1
	_normals.resize(points_x * (cells_z + 1))
	for iz in cells_z + 1:
		for ix in points_x:
			if exact_normals:
				_normals[iz * points_x + ix] = source.get_normal(origin.x + float(ix) * spacing, origin.y + float(iz) * spacing)
				continue
			# Same convention as TerrainProvider.get_normal().
			var hl := height_at(ix - 1, iz)
			var hr := height_at(ix + 1, iz)
			var hd := height_at(ix, iz - 1)
			var hu := height_at(ix, iz + 1)
			_normals[iz * points_x + ix] = Vector3(hl - hr, 2.0 * spacing, hd - hu).normalized()


## Height at grid point (ix, iz); -1 and cells + 1 are the margin.
func height_at(ix: int, iz: int) -> float:
	return _heights[(iz + 1) * _stride + ix + 1]


## Vertex normal at grid point (ix, iz), 0..cells inclusive.
func normal_at(ix: int, iz: int) -> Vector3:
	return _normals[iz * (cells_x + 1) + ix]


func get_height(x: float, z: float) -> float:
	var fx := (x - origin.x) / spacing
	var fz := (z - origin.y) / spacing
	if not _inside(fx, fz):
		return source.get_height(x, z)
	var ix := clampi(floori(fx), 0, cells_x - 1)
	var iz := clampi(floori(fz), 0, cells_z - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	# The quad's diagonal runs from (1, 0) to (0, 1), as in build_chunk_arrays().
	if tx + tz <= 1.0:
		var h00 := height_at(ix, iz)
		return h00 + (height_at(ix + 1, iz) - h00) * tx + (height_at(ix, iz + 1) - h00) * tz
	var h11 := height_at(ix + 1, iz + 1)
	return h11 + (height_at(ix, iz + 1) - h11) * (1.0 - tx) + (height_at(ix + 1, iz) - h11) * (1.0 - tz)


func get_normal(x: float, z: float, _epsilon: float = 0.35) -> Vector3:
	var fx := (x - origin.x) / spacing
	var fz := (z - origin.y) / spacing
	if not _inside(fx, fz):
		return source.get_normal(x, z)
	var ix := clampi(floori(fx), 0, cells_x - 1)
	var iz := clampi(floori(fz), 0, cells_z - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	if tx + tz <= 1.0:
		var n00 := normal_at(ix, iz)
		return (n00 + (normal_at(ix + 1, iz) - n00) * tx + (normal_at(ix, iz + 1) - n00) * tz).normalized()
	var n11 := normal_at(ix + 1, iz + 1)
	return (n11 + (normal_at(ix, iz + 1) - n11) * (1.0 - tx) + (normal_at(ix + 1, iz) - n11) * (1.0 - tz)).normalized()


func growth_mask_for(x: float, z: float, normal: Vector3) -> float:
	return source.growth_mask_for(x, z, normal)


func sample_painted_mask(x: float, z: float) -> float:
	return source.sample_painted_mask(x, z)


func has_painted_mask() -> bool:
	return source.has_painted_mask()


func _inside(fx: float, fz: float) -> bool:
	return fx >= -0.001 and fz >= -0.001 and fx <= float(cells_x) + 0.001 and fz <= float(cells_z) + 0.001
