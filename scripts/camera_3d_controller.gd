# Camera3DController.gd
# Caméra isométrique orbitale avec rotation Q/E par pas de 90°,
# zoom molette et pan clic milieu.
extends Node3D

signal camera_rotated

# --- Rotation ---
const ROTATION_DURATION: float = 0.3
const ROTATION_STEP: float = PI / 2.0  # 90°
var _target_rotation_y: float = 0.0
var _is_rotating: bool = false

# --- Zoom ---
const ZOOM_MIN: float = 5.0
const ZOOM_MAX: float = 25.0
const ZOOM_STEP: float = 1.0
var _target_zoom: float = 12.0

# --- Pan ---
var _dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector3 = Vector3.ZERO
const PAN_KEYBOARD_SPEED: float = 15.0

# --- Références ---
@onready var camera_arm: Node3D = $CameraArm
@onready var camera: Camera3D = $CameraArm/Camera3D

func _ready() -> void:
	# Initialiser l'angle de la caméra
	rotation.y = _target_rotation_y
	camera_arm.rotation.x = deg_to_rad(-30)
	_target_rotation_y = deg_to_rad(-13.565)
	rotation.y = _target_rotation_y
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _target_zoom
	camera.position.z = 20
	camera.near = 0.1
	camera.far = 100

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_hovered_control() != null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_rotate_camera(-1)
		elif event.physical_keycode == KEY_E:
			_rotate_camera(1)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if event.pressed:
				_drag_start_mouse = event.position
				_drag_start_pos = position

	if event is InputEventMouseMotion and _dragging:
		var delta = event.position - _drag_start_mouse
		# Convertir le delta en mouvement dans le plan XZ de la caméra
		var cam_right = -global_transform.basis.x
		var cam_forward = -global_transform.basis.z
		# Projeter sur le plan XZ
		cam_right.y = 0
		cam_right = cam_right.normalized()
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		var pan_speed = _target_zoom * 0.003
		position = _drag_start_pos + (cam_right * delta.x + cam_forward * -delta.y) * pan_speed

func _process(delta: float) -> void:
	var input_dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var cam_right = -global_transform.basis.x
		var cam_forward = -global_transform.basis.z
		cam_right.y = 0
		cam_right = cam_right.normalized()
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		position += (cam_right * -input_dir.x + cam_forward * -input_dir.y) * PAN_KEYBOARD_SPEED * delta

func _rotate_camera(direction: int) -> void:
	if _is_rotating:
		return
	_is_rotating = true
	_target_rotation_y += ROTATION_STEP * direction
	var tween = create_tween()
	tween.tween_property(self, "rotation:y", _target_rotation_y, ROTATION_DURATION)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func():
		_is_rotating = false
		camera_rotated.emit()
	)

func _apply_zoom() -> void:
	var tween = create_tween()
	tween.tween_property(camera, "size", _target_zoom, 0.15)\
		.set_trans(Tween.TRANS_SINE)

# Retourne le vecteur "droite" de la caméra projeté sur le plan XZ
func get_camera_right() -> Vector3:
	return -camera.global_transform.basis.x

# Retourne la position du pivot (pour centrer la caméra)
func get_pivot_position() -> Vector3:
	return position
