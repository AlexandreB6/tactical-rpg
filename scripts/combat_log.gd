# Historique des actions de combat, positionné en haut à droite.
# Contient un bouton pour minimiser/agrandir le log.
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var scroll: ScrollContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer
@onready var log_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/LogLabel
@onready var toggle_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ToggleButton
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/TitleLabel

var lines: Array = []
const MAX_LINES = 8
var minimized: bool = false
	
func _ready() -> void:
	log_label.text = ""
	toggle_button.pressed.connect(_on_toggle_pressed)
	# Démarre minimisé
	minimized = true
	scroll.visible = false
	scroll.custom_minimum_size = Vector2.ZERO
	toggle_button.text = "▶"
	await get_tree().process_frame
	panel.reset_size()
	_reposition()

# Ajoute une ligne au log et scrolle vers le bas
func add_entry(text: String) -> void:
	lines.append(text)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	log_label.text = "\n".join(lines)
	toggle_button.disabled = false

# Bascule entre minimisé et agrandi
func _on_toggle_pressed() -> void:
	minimized = !minimized
	toggle_button.text = "▶" if minimized else "▼"
	toggle_button.disabled = true  # Évite les double-clics pendant l'animation

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if minimized:
		# Fermeture : rétrécit la hauteur jusqu'à 0
		tween.tween_property(scroll, "custom_minimum_size:y", 0.0, 0.2)
		await tween.finished
		scroll.visible = false
	else:
		# Ouverture : affiche et agrandit la hauteur jusqu'à 140
		scroll.visible = true
		scroll.custom_minimum_size.y = 0.0
		tween.tween_property(scroll, "custom_minimum_size:y", 140.0, 0.2)
		await tween.finished
		# Reset le scroll vers le bas pour voir les dernières entrées
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

	await get_tree().process_frame
	panel.reset_size()
	toggle_button.disabled = false
	_reposition()

# Positionne le panel en haut à droite de l'écran
func _reposition() -> void:
	panel.position = Vector2(10, 10)
	
# Numéro du tour
func set_turn(turn: int) -> void:
	title_label.text = "Combat Log — Tour " + str(turn)
