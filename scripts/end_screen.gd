# Affiche l'écran de fin de partie (victoire ou défaite) par dessus la grille.
extends CanvasLayer

@onready var message_label: Label = $Background/VBoxContainer/MessageLabel
@onready var replay_button: Button = $Background/VBoxContainer/ReplayButton

func _ready() -> void:
	hide()
	replay_button.pressed.connect(_on_replay_pressed)

# Affiche le message de fin et rend l'écran visible
func show_end_screen(message: String) -> void:
	message_label.text = message
	show()

func _on_replay_pressed() -> void:
	get_tree().reload_current_scene()
