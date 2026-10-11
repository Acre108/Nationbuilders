class_name RiverTracer
extends RefCounted

## Traces a scalar field's zero-contours into polylines -- what a river rides
## on top of (LandformTerrainProvider's valley meander field crosses zero
## exactly on a valley's centreline, the same field valley_strength() already
## measures distance from). Pulled out as a pure algorithm, taking the field
## as a Callable rather than reading LandformTerrainProvider directly, the
## same reasoning LakeBasins operates on plain arrays: it can be tested
## against a simple, known field (see the class's own tests) instead of only
## against noise.
##
## Rivers cannot use the flat-plane-plus-occlusion trick the sea and lakes
## use (WaterLayer): a river's surface must follow its valley's slope, not
## sit at one constant height, so there is no shortcut around actually
## knowing where it runs. And the WATER_GRID bake LakeBasins/WaterDepthMap
## use is far too coarse for a feature this narrow (a river a few metres wide
## against a ~62 m grid cell on an 8 km world) -- baking a finer grid over
## the WHOLE world would cost far more than tracing the much smaller set of
## points actually on a river.
##
## The method: seed candidates on a coarse grid wherever the field is already
## close to zero, snap each to the exact contour by a few Newton steps along
## the gradient, then walk the contour's tangent (perpendicular to the
## gradient) in both directions in fixed steps, re-snapping after each one
## so the walk does not drift off the true curve. Seeds that land on a
## contour some earlier trace already covers are skipped, so one continuous
## valley is traced once, however many seeds happen to fall on it.

const NEWTON_STEPS := 4
## Snapping uses central differences over this step, world units -- the same
## role VALLEY_EPSILON plays in LandformTerrainProvider.valley_strength().
const GRADIENT_EPSILON := 1.0
## A converged Newton step lands within machine precision of zero; this is
## already generous next to that. Anything snapped no closer than this was
## not actually near a root -- see _is_on_contour()'s own comment for why
## that check matters and is not just a nice-to-have.
const ON_CONTOUR_TOLERANCE := 0.001


## `field`: Callable(Vector2) -> float. `bounds`: world XZ to search.
## `seed_grid`: samples per side for finding candidate starting points.
## `step`: distance walked per trace step, world units. `max_steps`: per
## direction (a trace walks both ways from its seed), so a closed loop or an
## edge-to-edge line is bounded. `dedup_radius`: a seed within this of an
## already-traced point is assumed to be on that same contour and skipped.
##
## Returns Array[PackedVector2Array], one polyline per contour found, each
## ordered along the walk (not necessarily a simple end-to-end path if the
## contour loops, but always a connected sequence of points ~step apart).
##
## Every seed is snapped, not pre-filtered by how close it starts: with
## zero-crossings recurring roughly every 0.6 wavelengths of the field (see
## LandformTerrainProvider._valleys' own comment), Newton's method converges
## to the nearest one from anywhere in a seed cell, so a coarse seed_grid
## still finds every contour -- the dedup check below is what keeps that from
## meaning "trace the same valley once per seed that landed on it".
static func trace(field: Callable, bounds: Rect2, seed_grid: int, step: float, max_steps: int, dedup_radius: float) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	var covered: Array[Vector2] = []

	var cell := Vector2(bounds.size.x / float(seed_grid), bounds.size.y / float(seed_grid))
	for j in seed_grid:
		for i in seed_grid:
			var seed := bounds.position + Vector2((float(i) + 0.5) * cell.x, (float(j) + 0.5) * cell.y)
			var on_contour := _snap(field, seed, NEWTON_STEPS)
			if not bounds.has_point(on_contour) or not _is_on_contour(field, on_contour):
				continue
			if _near_any(on_contour, covered, dedup_radius):
				continue

			var path := _walk(field, on_contour, bounds, step, max_steps)
			if path.size() < 2:
				continue
			paths.append(path)
			for p in path:
				covered.append(p)
	return paths


## Central-difference gradient of `field` at `p`.
static func _gradient(field: Callable, p: Vector2) -> Vector2:
	var e := GRADIENT_EPSILON
	var gx: float = field.call(Vector2(p.x + e, p.y)) - field.call(Vector2(p.x - e, p.y))
	var gz: float = field.call(Vector2(p.x, p.y + e)) - field.call(Vector2(p.x, p.y - e))
	return Vector2(gx, gz) / (2.0 * e)


## Newton's method along the gradient: the field is locally linear near a
## simple zero, so `p - value * gradient / |gradient|^2` converges fast.
static func _snap(field: Callable, p: Vector2, iterations: int) -> Vector2:
	var point := p
	for i in iterations:
		var gradient := _gradient(field, point)
		var g2 := gradient.length_squared()
		if g2 < 0.000001:
			break
		var value: float = field.call(point)
		point -= gradient * (value / g2)
	return point


## True when `p` is genuinely near a zero of `field`, not just wherever
## Newton's method happened to stop. This matters because _snap() can fail
## quietly: where the field is nearly flat (gradient close to zero) but not
## actually near a root, Newton's own correction term (value / |gradient|^2)
## explodes, and without this check a field with NO zero-crossing at all --
## or a real field's saddle points, where two valleys' contours almost
## touch -- can still produce a "contour" that is really just the walk
## wandering through flat, off-contour ground for its full step budget.
static func _is_on_contour(field: Callable, p: Vector2) -> bool:
	return absf(field.call(p)) <= ON_CONTOUR_TOLERANCE


static func _near_any(p: Vector2, points: Array[Vector2], radius: float) -> bool:
	for q in points:
		if p.distance_to(q) <= radius:
			return true
	return false


## Walks the contour through `start` in both tangent directions, snapping
## back onto it after each step. Stops a direction early if it leaves
## `bounds`, or loops back near its own start (a closed contour).
static func _walk(field: Callable, start: Vector2, bounds: Rect2, step: float, max_steps: int) -> PackedVector2Array:
	var forward := _walk_one_way(field, start, bounds, step, max_steps, 1.0)
	var backward := _walk_one_way(field, start, bounds, step, max_steps, -1.0)
	backward.reverse()
	var path := PackedVector2Array()
	path.append_array(backward)
	path.append(start)
	path.append_array(forward)
	return path


static func _walk_one_way(field: Callable, start: Vector2, bounds: Rect2, step: float, max_steps: int, sign: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var point := start
	# Consistent turning direction along the walk: without carrying the
	# previous tangent, rotating a gradient by +-90 degrees has no memory of
	# which way "forward" was, and the walk can double back on itself at the
	# first step.
	var previous_tangent := Vector2.ZERO
	for i in max_steps:
		var gradient := _gradient(field, point)
		if gradient.length() < 0.000001:
			break
		var tangent := Vector2(-gradient.y, gradient.x).normalized()
		if previous_tangent != Vector2.ZERO and tangent.dot(previous_tangent) < 0.0:
			tangent = -tangent
		previous_tangent = tangent
		var next_point := _snap(field, point + tangent * step * sign, NEWTON_STEPS)
		if not bounds.has_point(next_point) or not _is_on_contour(field, next_point):
			break
		if i > 2 and next_point.distance_to(start) < step * 0.5:
			break    # closed loop: back near where the whole trace began
		out.append(next_point)
		point = next_point
	return out
