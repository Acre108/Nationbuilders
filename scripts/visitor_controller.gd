class_name VisitorController
extends CharacterBody3D

const HEIGHT := 1.8
const RADIUS := 0.3
const EYE_HEIGHT := 1.6
var camera: Camera3D
var movement_enabled := false
## Integration checks drive the same collision controller without keyboard input.
var automated_direction := Vector3.ZERO
var _looking := false
var _pitch := 0.0

func _ready() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	collider.shape = capsule
	collider.position.y = HEIGHT / 2
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.near = 0.05
	camera.current = true
	add_child(camera)
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(46)

func _unhandled_input(event: InputEvent) -> void:
	if not movement_enabled: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _looking:
		rotation.y -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.45, 1.45)
		camera.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not movement_enabled: return
	var direction := automated_direction
	if get_viewport().gui_get_focus_owner() == null:
		var keys := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		direction += transform.basis * keys
	var horizontal := direction.normalized() * 3.0
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()

func release_pointer() -> void:
	_looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	release_pointer()
