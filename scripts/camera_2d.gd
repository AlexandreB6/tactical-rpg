extends Camera2D

const ZOOM_MIN = 0.3
const ZOOM_MAX = 3.0
const ZOOM_STEP = 0.1
const PAN_SPEED = 10.0

var _dragging = false
var _drag_origin = Vector2.ZERO

func _ready() -> void:
	zoom = Vector2(1.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	# Ignore les inputs si la souris est sur un élément UI
	if get_viewport().gui_get_hovered_control() != null:
		return

	# Zoom molette
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom + Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(
				Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom - Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(
				Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			_drag_origin = get_global_mouse_position()

	if event is InputEventMouseMotion and _dragging:
		position -= (get_global_mouse_position() - _drag_origin)
