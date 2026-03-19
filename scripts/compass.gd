# Compass.gd
# Boussole N/S/E/O en haut à droite, tourne avec la caméra.
extends CanvasLayer

const COMPASS_SIZE: float = 50.0
const MARGIN: float = 20.0
const NEEDLE_LENGTH: float = 30.0
const LABEL_OFFSET: float = 38.0
const FONT_SIZE_MAIN: int = 16
const FONT_SIZE_SEC: int = 12

var _camera_pivot: Node3D = null
var _compass_control: Control = null

func setup(camera_pivot: Node3D) -> void:
	_camera_pivot = camera_pivot
	_compass_control = Control.new()
	_compass_control.name = "CompassControl"
	_compass_control.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_compass_control.position = Vector2(-COMPASS_SIZE * 2 - MARGIN - 160, MARGIN)
	_compass_control.custom_minimum_size = Vector2(COMPASS_SIZE * 2, COMPASS_SIZE * 2)
	_compass_control.size = Vector2(COMPASS_SIZE * 2, COMPASS_SIZE * 2)
	_compass_control.draw.connect(_on_draw)
	add_child(_compass_control)

func _process(_delta: float) -> void:
	if _compass_control:
		_compass_control.queue_redraw()

func _on_draw() -> void:
	if _camera_pivot == null or _compass_control == null:
		return
	var center = Vector2(COMPASS_SIZE, COMPASS_SIZE)
	var cam_angle = _camera_pivot.rotation.y

	# Fond semi-transparent
	_compass_control.draw_circle(center, COMPASS_SIZE - 4, Color(0, 0, 0, 0.35))
	_compass_control.draw_arc(center, COMPASS_SIZE - 4, 0, TAU, 48, Color(1, 1, 1, 0.3), 1.5)

	# Directions cardinales (tournent avec la caméra)
	var directions = [
		{ "label": "N", "angle": 0.0,       "main": true },
		{ "label": "E", "angle": PI / 2.0,  "main": false },
		{ "label": "S", "angle": PI,        "main": false },
		{ "label": "O", "angle": -PI / 2.0, "main": false },
	]
	var font = ThemeDB.fallback_font

	for dir in directions:
		# L'angle visuel : rotation caméra tourne la boussole
		var visual_angle = dir["angle"] + cam_angle
		# Dans le plan 2D, "nord" pointe vers le haut (-Y)
		var dir_vec = Vector2(sin(visual_angle), -cos(visual_angle))

		# Ligne indicatrice
		var line_len = NEEDLE_LENGTH if dir["main"] else NEEDLE_LENGTH * 0.6
		var line_color: Color
		if dir["main"]:
			line_color = Color(1.0, 0.3, 0.3)  # Nord en rouge
		else:
			line_color = Color(0.85, 0.85, 0.85, 0.7)
		var line_width = 2.5 if dir["main"] else 1.5
		_compass_control.draw_line(center + dir_vec * 6, center + dir_vec * line_len, line_color, line_width)

		# Label
		var font_size = FONT_SIZE_MAIN if dir["main"] else FONT_SIZE_SEC
		var label_pos = center + dir_vec * LABEL_OFFSET
		var text: String = dir["label"]
		var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = label_pos - text_size / 2.0
		var text_color = Color(1.0, 0.4, 0.4) if dir["main"] else Color(0.9, 0.9, 0.9, 0.9)
		_compass_control.draw_string(font, text_pos + Vector2(0, text_size.y * 0.75), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
