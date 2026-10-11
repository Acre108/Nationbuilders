class_name PolygonGrassCarver
extends GrassCarver

## Exact resolved footprint, including concave outlines; margin clears cards
## rooted just outside the edge. Buildings pass floor polygons, never furniture.
var polygon: PackedVector2Array

func _init(points: PackedVector2Array = PackedVector2Array(), clearance: float = 0.2) -> void:
	polygon = points.duplicate()
	margin = clearance
	_bounds = Rect2()
	if polygon.is_empty(): return
	_bounds = Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: _bounds = _bounds.expand(point)
	_bounds = _bounds.grow(margin + 0.001)

func contains(x: float, z: float) -> bool:
	var point := Vector2(x,z)
	if polygon.size() < 3 or not _bounds.has_point(point): return false
	if Geometry2D.is_point_in_polygon(point,polygon): return true
	for index in polygon.size():
		if point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()])) <= margin*margin:
			return true
	return false
