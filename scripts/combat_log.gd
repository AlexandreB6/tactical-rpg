# Historique des actions de combat, positionné en haut à gauche.
# Contient un bouton pour minimiser/agrandir le log + poignée de redimensionnement.
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var scroll: ScrollContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer
@onready var log_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/LogLabel
@onready var toggle_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ToggleButton
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/TitleLabel
@onready var resize_handle: Control = $PanelContainer/MarginContainer/VBoxContainer/ResizeHandle

var lines: Array = []
const MAX_LINES = 50
var minimized: bool = false
var _last_unit: String = ""

# Redimensionnement
var _resizing: bool = false
var _resize_start_mouse: Vector2
var _resize_start_size: Vector2
const MIN_SCROLL_HEIGHT = 80.0
const MAX_SCROLL_HEIGHT = 600.0
const MIN_PANEL_WIDTH = 260.0
const MAX_PANEL_WIDTH = 600.0
var _expanded_height: float = 140.0
var _panel_width: float = 260.0

func _ready() -> void:
	# Le thème root ne se propage pas à travers CanvasLayer, on l'applique manuellement
	panel.theme = UITheme.current_theme
	log_label.text = ""
	toggle_button.pressed.connect(_on_toggle_pressed)
	resize_handle.gui_input.connect(_on_resize_handle_input)
	# Démarre minimisé
	minimized = true
	scroll.visible = false
	scroll.custom_minimum_size = Vector2.ZERO
	resize_handle.visible = false
	toggle_button.text = "▶"
	await get_tree().process_frame
	panel.reset_size()
	_reposition()

# Ajoute une ligne au log et scrolle vers le bas
# unit_name : si fourni, insère un saut de ligne quand l'unité change
func add_entry(text: String, unit_name: String = "") -> void:
	if unit_name != "" and unit_name != _last_unit and lines.size() > 0:
		lines.append("")
	if unit_name != "":
		_last_unit = unit_name
	else:
		_last_unit = ""
	lines.append(text)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	log_label.text = "\n".join(lines)
	toggle_button.disabled = false
	# Auto-scroll vers le bas
	if not minimized:
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

# Bascule entre minimisé et agrandi
func _on_toggle_pressed() -> void:
	minimized = !minimized
	toggle_button.text = "▶" if minimized else "▼"
	toggle_button.disabled = true  # Évite les double-clics pendant l'animation

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if minimized:
		# Fermeture : rétrécit la hauteur jusqu'à 0
		resize_handle.visible = false
		tween.tween_property(scroll, "custom_minimum_size:y", 0.0, 0.2)
		await tween.finished
		scroll.visible = false
	else:
		# Ouverture : affiche et agrandit jusqu'à la hauteur sauvegardée
		scroll.visible = true
		scroll.custom_minimum_size.y = 0.0
		tween.tween_property(scroll, "custom_minimum_size:y", _expanded_height, 0.2)
		await tween.finished
		resize_handle.visible = true
		# Reset le scroll vers le bas pour voir les dernières entrées
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

	await get_tree().process_frame
	panel.reset_size()
	toggle_button.disabled = false
	_reposition()

# Gère le drag de la poignée de redimensionnement
func _on_resize_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_start_mouse = event.global_position
			_resize_start_size = Vector2(_panel_width, _expanded_height)
		else:
			_resizing = false
	elif event is InputEventMouseMotion and _resizing:
		var delta = event.global_position - _resize_start_mouse
		# Redimensionner hauteur et largeur
		_expanded_height = clamp(_resize_start_size.y + delta.y, MIN_SCROLL_HEIGHT, MAX_SCROLL_HEIGHT)
		_panel_width = clamp(_resize_start_size.x + delta.x, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
		scroll.custom_minimum_size.y = _expanded_height
		panel.custom_minimum_size.x = _panel_width
		scroll.custom_minimum_size.x = _panel_width - 16  # marges
		panel.reset_size()

# Positionne le panel en haut à gauche de l'écran
func _reposition() -> void:
	panel.position = Vector2(10, 10)

# Numéro du tour
func set_turn(turn: int) -> void:
	title_label.text = "Combat Log — Tour " + str(turn)
