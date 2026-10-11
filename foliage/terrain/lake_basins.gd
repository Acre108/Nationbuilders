class_name LakeBasins
extends RefCounted

## Depression filling and basin extraction for procedural lakes (W3 of the
## water system). Pulled out of LandformTerrainProvider as a pure grid
## algorithm, the same reasoning GroveScatter was split out of TreePlacer:
## easier to verify against a small hand-built grid with a known answer than
## against noise.
##
## fill_depressions() is priority-flood depression filling (Barnes, Lehman &
## Mulla 2014). Seeded from the grid's own boundary -- treated as already
## draining, the same assumption sea_level and the world's edge make -- it
## finds, for every interior cell, the lowest height water would have to
## reach to escape to that boundary: an enclosed basin's true rim height.
## Where that sits above the raw ground, there is a lake candidate.
##
## extract_basins() then groups the result into connected basins and drops
## the ones that are not really lakes: too small to matter, or so deep that
## filling them is more likely a noise artefact (a sinkhole) than an actual
## pond.

const _DX: PackedInt32Array = [-1, 1, 0, 0]
const _DZ: PackedInt32Array = [0, 0, -1, 1]
## Below this, "the fill sits above the ground" is treated as float noise
## from the algorithm rather than a real basin.
const DEPTH_EPS := 0.02


## Priority-flood over an n x n grid (row-major, x fastest, `raw[z * n + x]`).
## Returns the FILL height per cell: equal to `raw` wherever the ground
## already drains to the edge, and higher than `raw` inside an enclosed
## basin.
static func fill_depressions(raw: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var fill := PackedFloat32Array()
	fill.resize(n * n)
	var resolved := PackedByteArray()
	resolved.resize(n * n)

	# Binary min-heap of (height, index), as two parallel Packed arrays --
	# GDScript has no built-in heap, and this is cheap enough in plain arrays
	# not to need one for a grid this size.
	var heap_h := PackedFloat32Array()
	var heap_i := PackedInt32Array()

	for j in n:
		for i in n:
			if i == 0 or j == 0 or i == n - 1 or j == n - 1:
				var idx := j * n + i
				fill[idx] = raw[idx]
				resolved[idx] = 1
				_heap_push(heap_h, heap_i, raw[idx], idx)

	while not heap_h.is_empty():
		var top_h: float = heap_h[0]
		var idx: int = heap_i[0]
		_heap_pop(heap_h, heap_i)
		var ix := idx % n
		var iz := idx / n
		for k in 4:
			var nx := ix + _DX[k]
			var nz := iz + _DZ[k]
			if nx < 0 or nx >= n or nz < 0 or nz >= n:
				continue
			var nidx := nz * n + nx
			if resolved[nidx]:
				continue
			resolved[nidx] = 1
			# A neighbour either keeps its own height (it already drains
			# somewhere at or below the current water front) or is pulled up
			# to that front (it is inside the basin the front just entered).
			var h: float = maxf(raw[nidx], top_h)
			fill[nidx] = h
			_heap_push(heap_h, heap_i, h, nidx)
	return fill


## Connected components of `fill - raw > DEPTH_EPS`, filtered to
## `area >= min_area` (world units^2) and `max depth in the basin <=
## max_depth` (world units). `cell_size` converts one grid cell to world
## metres for the area calculation.
##
## Returns {"depth": PackedFloat32Array (n*n, zeroed outside kept basins),
## "basins": Array[Dictionary] of {"cell_bounds": Rect2i, "level": float,
## "area": float}}.
static func extract_basins(raw: PackedFloat32Array, fill: PackedFloat32Array, n: int, cell_size: float, min_area: float, max_depth: float) -> Dictionary:
	var depth := PackedFloat32Array()
	depth.resize(n * n)
	var visited := PackedByteArray()
	visited.resize(n * n)
	var cell_area := cell_size * cell_size
	var basins: Array[Dictionary] = []

	for start in n * n:
		if visited[start]:
			continue
		if fill[start] - raw[start] <= DEPTH_EPS:
			visited[start] = 1
			continue

		var members: Array[int] = [start]
		var stack: Array[int] = [start]
		visited[start] = 1
		var min_ix := start % n
		var max_ix := min_ix
		var min_iz := start / n
		var max_iz := min_iz
		var basin_max_depth: float = fill[start] - raw[start]

		while not stack.is_empty():
			var idx: int = stack.pop_back()
			var ix := idx % n
			var iz := idx / n
			for k in 4:
				var nx := ix + _DX[k]
				var nz := iz + _DZ[k]
				if nx < 0 or nx >= n or nz < 0 or nz >= n:
					continue
				var nidx := nz * n + nx
				if visited[nidx]:
					continue
				visited[nidx] = 1
				if fill[nidx] - raw[nidx] <= DEPTH_EPS:
					continue
				members.append(nidx)
				stack.append(nidx)
				min_ix = mini(min_ix, nx)
				max_ix = maxi(max_ix, nx)
				min_iz = mini(min_iz, nz)
				max_iz = maxi(max_iz, nz)
				basin_max_depth = maxf(basin_max_depth, fill[nidx] - raw[nidx])

		var area := float(members.size()) * cell_area
		if area >= min_area and basin_max_depth <= max_depth:
			for idx in members:
				depth[idx] = fill[idx] - raw[idx]
			basins.append({
				"cell_bounds": Rect2i(min_ix, min_iz, max_ix - min_ix + 1, max_iz - min_iz + 1),
				"level": fill[start],
				"area": area,
			})
	return {"depth": depth, "basins": basins}


static func _heap_push(heap_h: PackedFloat32Array, heap_i: PackedInt32Array, h: float, idx: int) -> void:
	heap_h.append(h)
	heap_i.append(idx)
	var c := heap_h.size() - 1
	while c > 0:
		var p := (c - 1) / 2
		if heap_h[p] <= heap_h[c]:
			break
		var th := heap_h[p]; heap_h[p] = heap_h[c]; heap_h[c] = th
		var ti := heap_i[p]; heap_i[p] = heap_i[c]; heap_i[c] = ti
		c = p


static func _heap_pop(heap_h: PackedFloat32Array, heap_i: PackedInt32Array) -> void:
	var last := heap_h.size() - 1
	heap_h[0] = heap_h[last]
	heap_i[0] = heap_i[last]
	heap_h.resize(last)
	heap_i.resize(last)
	var p := 0
	while true:
		var l := p * 2 + 1
		var r := p * 2 + 2
		var smallest := p
		if l < heap_h.size() and heap_h[l] < heap_h[smallest]:
			smallest = l
		if r < heap_h.size() and heap_h[r] < heap_h[smallest]:
			smallest = r
		if smallest == p:
			break
		var th := heap_h[p]; heap_h[p] = heap_h[smallest]; heap_h[smallest] = th
		var ti := heap_i[p]; heap_i[p] = heap_i[smallest]; heap_i[smallest] = ti
		p = smallest
