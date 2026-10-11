class_name AtmosphereZone
extends Resource

## An area of the world that changes the atmosphere while the camera is in it.
##
## Ported from PlacesOS's atmosphere zones (place-sdk AtmosphereZoneSchema).
## An INSIDE zone is a roofed space: model ambient is scaled, fog thins to 28%,
## and rain and motes stop, because they follow the camera and would otherwise
## fall through the roof. Rendering uses unscaled outdoor fill to keep views
## through windows stable. An OUTSIDE zone is ordinary open air; it exists so a
## small courtyard can punch a hole in a larger inside zone.
##
## Zones are tested in array order and the first match wins -- same rule as
## PlacesOS, where it lets a terrace override the building around it. A camera
## in no zone at all gets the plain outdoor atmosphere.

enum Kind { OUTSIDE, INSIDE }

@export var label: String = "Zone"
@export var kind: Kind = Kind.INSIDE
## Footprint in world XZ, metres. Any simple polygon, either winding.
@export var area: PackedVector2Array = PackedVector2Array()
## Inside zones only: legacy model multiplier; renderer uses outdoor fill.
@export_range(0.0, 2.0) var ambient_scale: float = 0.8
## Opt-in world-space height bounds. Existing resources remain XZ-only.
@export var height_bounded: bool = false
@export var min_height: float = 0.0
@export var max_height: float = 3.0


func contains(point: Vector2) -> bool:
	return area.size() >= 3 and Geometry2D.is_point_in_polygon(point, area)

func contains_3d(point: Vector3) -> bool:
	return (not height_bounded or (point.y >= min_height and point.y < max_height)) \
		and contains(Vector2(point.x,point.z))
