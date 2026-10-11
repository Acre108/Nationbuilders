extends Camera3D
var focus := Vector3(22.0,0,18.0)
var quarter_turn := 0
var zoom_size := 22.0

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
	position = focus + direction * 34.0 + Vector3.UP * 28.0
	look_at(focus)
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
	focus.x = clampf(focus.x,4.0,35.0)
	focus.z = clampf(focus.z,4.0,35.0)
	refresh()

func zoom(direction: int) -> void:
	zoom_size = clampf(zoom_size + direction * 4.0,16.0,48.0)
	refresh()

func cell_at(pixel: Vector2) -> Vector2i:
	var origin := project_ray_origin(pixel)
	var ray := project_ray_normal(pixel)
	var distance := -origin.y / ray.y
	var point := origin + ray * distance
	return Vector2i(floori(point.x),floori(point.z))
