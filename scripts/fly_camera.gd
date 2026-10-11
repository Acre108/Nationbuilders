class_name FlyCamera
extends Camera3D

## Debug fly camera for the foliage test scenes.
##
## Hold right mouse to look, WASD to move, Q/E down/up, Shift to sprint. Sprint
## is deliberately very fast: the large-landscape test needs to cross kilometres
## quickly, because streaming hitches only show up when you outrun the chunk
## generator.

@export var speed: float = 12.0
@export var sprint_multiplier: float = 8.0
@export var look_sensitivity: float = 0.0025
## Runtime loading keeps this false until visible ground and collision exist at
## the authored arrival point.
@export var movement_enabled: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _looking: bool = false


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if not movement_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clampf(_pitch - event.relative.y * look_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not movement_enabled:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move -= transform.basis.z
	if Input.is_key_pressed(KEY_S): move += transform.basis.z
	if Input.is_key_pressed(KEY_A): move -= transform.basis.x
	if Input.is_key_pressed(KEY_D): move += transform.basis.x
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP

	if move == Vector3.ZERO:
		return
	var current := speed
	if Input.is_key_pressed(KEY_SHIFT):
		current *= sprint_multiplier
	position += move.normalized() * current * delta


## Metres per second the camera is actually covering, for the streaming
## benchmark readout.
func current_speed() -> float:
	return speed * (sprint_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)

func release_pointer() -> void:
	_looking = false
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
