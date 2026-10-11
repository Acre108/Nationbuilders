class_name GrassCarver
extends RefCounted

## One footprint that must stay clear of grass: an oriented rectangle in world
## XZ, grown outwards by `margin` with rounded corners.
##
## The margin exists because a tuft is not a point. A clump card is ~0.25 m in
## radius before instance scaling, so a tuft rooted just outside a rug's edge
## still stands its blades up through the rug. Rounding the grown corners (a
## distance test rather than a bigger rectangle) keeps the cleared patch from
## reading as a cut-out square around round objects.
##
## Plain data with no node access, so carvers can be handed to placement on
## WorkerThreadPool unchanged.

const DEFAULT_MARGIN := 0.2

var center: Vector2
var half_size: Vector2
## Radians about +Y, same sense as Node3D.rotation.y -- so a carver and the
## furniture node it was built for can never disagree about which way is round.
var yaw: float
var margin: float

var _cos: float
var _sin: float
var _bounds: Rect2


func _init(p_center := Vector2.ZERO, p_half_size := Vector2.ZERO, p_yaw := 0.0, p_margin := DEFAULT_MARGIN) -> void:
	center = p_center
	half_size = p_half_size
	yaw = p_yaw
	margin = p_margin
	_cos = cos(yaw)
	_sin = sin(yaw)

	# World AABB of the rotated, grown rectangle: the cheap early-out for both
	# point tests and for deciding which chunks a carve touches.
	var extent := Vector2(
		absf(_cos) * half_size.x + absf(_sin) * half_size.y,
		absf(_sin) * half_size.x + absf(_cos) * half_size.y,
	) + Vector2(margin, margin)
	_bounds = Rect2(center - extent, extent * 2.0)


func bounds() -> Rect2:
	return _bounds


func contains(x: float, z: float) -> bool:
	if not _bounds.has_point(Vector2(x, z)):
		return false
	# Into the rectangle's own frame. This is the inverse of Basis(UP, yaw)
	# applied to (dx, 0, dz), written out so the test stays allocation-free.
	var dx := x - center.x
	var dz := z - center.y
	var lx := dx * _cos - dz * _sin
	var lz := dx * _sin + dz * _cos
	var ox := maxf(absf(lx) - half_size.x, 0.0)
	var oz := maxf(absf(lz) - half_size.y, 0.0)
	return ox * ox + oz * oz <= margin * margin
