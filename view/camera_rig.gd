extends Camera3D
var focus := Vector3(22.0,0,18.0)
var quarter_turn := 0
var zoom_size := 22.0
var zoom_min := 16.0
var zoom_max := 48.0
var pixel_snap_enabled := true
## Where the focus may pan; the view sets it from the site's size.
var bounds := Rect2(4.0, 4.0, 31.0, 31.0)

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	near = 0.1
	far = 180.0
	current = true
	refresh()

func refresh() -> void:
	size = zoom_size
	var angle := deg_to_rad(45.0 + quarter_turn * 90.0)
	var direction := Vector3(sin(angle),0,cos(angle))
	var distance_scale := maxf(1.0, zoom_size / 48.0)
	far = 180.0 * distance_scale
	position = focus + direction * 34.0 * distance_scale + Vector3.UP * 28.0 * distance_scale
	look_at(focus)
	if not pixel_snap_enabled: return
	# Snap camera translation in its screen-space basis at native resolution.
	var units_per_pixel := size / 360.0
	var right := global_basis.x
	var up := global_basis.y
	global_position += right * (snappedf(global_position.dot(right),units_per_pixel) - global_position.dot(right))
	global_position += up * (snappedf(global_position.dot(up),units_per_pixel) - global_position.dot(up))

func rotate_quarter(direction: int) -> void:
	quarter_turn = posmod(quarter_turn + direction,4)
	refresh()

func pan(direction: Vector2, seconds: float) -> void:
	var right := global_basis.x
	var forward := Vector3(global_basis.y.x,0,global_basis.y.z).normalized()
	focus += (right * direction.x + forward * direction.y) * seconds * 12.0
	focus.x = clampf(focus.x,bounds.position.x,bounds.end.x)
	focus.z = clampf(focus.z,bounds.position.y,bounds.end.y)
	refresh()

func zoom(direction: int) -> void:
	zoom_size = clampf(zoom_size + direction * 4.0,zoom_min,zoom_max)
	refresh()

## Without a height function this picks on the y = 0 plane. With one
## (Callable(Vector2) -> float), it marches down the ray from `top` and refines
## the first crossing, so raised ground and cliff faces pick the right tile.
func cell_at(pixel: Vector2, height_at: Callable = Callable(), top: float = 0.0) -> Vector2i:
	var origin := project_ray_origin(pixel)
	var ray := project_ray_normal(pixel)
	var distance := -origin.y / ray.y
	if height_at.is_valid():
		var near_distance := (origin.y - top - 0.5) / -ray.y
		var far_distance := (origin.y + 0.5) / -ray.y
		var step := 0.05
		var previous := near_distance
		var probe := near_distance
		while probe <= far_distance:
			var at := origin + ray * probe
			if at.y <= float(height_at.call(Vector2(at.x,at.z))):
				var above := previous
				var below := probe
				for iteration in 12:
					var middle := (above + below) * 0.5
					var mid_point := origin + ray * middle
					if mid_point.y <= float(height_at.call(Vector2(mid_point.x,mid_point.z))): below = middle
					else: above = middle
				distance = below
				break
			previous = probe
			probe += step
	var point := origin + ray * distance
	return Vector2i(floori(point.x),floori(point.z))
