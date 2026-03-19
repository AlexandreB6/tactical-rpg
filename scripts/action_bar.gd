extends CanvasLayer

signal move_requested
signal attack_requested
signal defend_requested
signal end_turn_requested
signal cancel_requested
signal spell_requested(spell_index: int)

@onready var move_button: Button = $PanelContainer/HBoxContainer/MoveButton
@onready var attack_button: Button = $PanelContainer/HBoxContainer/AttackButton
@onready var defend_button: Button = $PanelContainer/HBoxContainer/DefendButton
@onready var end_turn_button: Button = $PanelContainer/HBoxContainer/EndTurnButton
@onready var cancel_button: Button = $PanelContainer/HBoxContainer/CancelButton
@onready var hbox: HBoxContainer = $PanelContainer/HBoxContainer

var _spell_buttons: Array[Button] = []

const ICONS = {
	"move": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_07.png"),
	"attack": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_05.png"),
	"defend": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_06.png"),
	"end": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_09.png"),
	"cancel": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_08.png"),
}

func _ready() -> void:
	$PanelContainer.theme = UITheme.current_theme
	hide()
	_setup_icon_button(move_button, "Déplacer", ICONS["move"])
	_setup_icon_button(attack_button, "Attaquer", ICONS["attack"])
	_setup_icon_button(defend_button, "Défendre", ICONS["defend"])
	_setup_icon_button(end_turn_button, "Terminer", ICONS["end"])
	_setup_icon_button(cancel_button, "Annuler", ICONS["cancel"])
	move_button.pressed.connect(func(): emit_signal("move_requested"))
	attack_button.pressed.connect(func(): emit_signal("attack_requested"))
	defend_button.pressed.connect(func(): emit_signal("defend_requested"))
	end_turn_button.pressed.connect(func(): emit_signal("end_turn_requested"))
	cancel_button.pressed.connect(func(): emit_signal("cancel_requested"))

func _setup_icon_button(button: Button, text: String, icon_tex: Texture2D) -> void:
	button.text = ""
	# Icône en fond
	var icon = TextureRect.new()
	icon.texture = icon_tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 2
	icon.offset_right = -4
	icon.offset_bottom = -14
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	# Texte en overlay en bas
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	button.add_child(label)

func setup_for_unit(unit) -> void:
	# Supprimer les anciens boutons de sorts
	for btn in _spell_buttons:
		btn.queue_free()
	_spell_buttons.clear()
	# Créer un bouton par sort
	for i in range(unit.spells.size()):
		var spell: SpellData = unit.spells[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		_setup_icon_button(btn, spell.spell_name, spell.icon_texture if spell.icon_texture else ICONS["defend"])
		var idx = i
		btn.pressed.connect(func(): emit_signal("spell_requested", idx))
		# Insérer après attack_button
		var attack_idx = attack_button.get_index()
		hbox.add_child(btn)
		hbox.move_child(btn, attack_idx + 1 + i)
		_spell_buttons.append(btn)

func update_buttons(p_has_moved: bool, p_has_acted: bool = false) -> void:
	move_button.disabled = p_has_moved
	attack_button.disabled = p_has_acted
	defend_button.disabled = p_has_acted
	for btn in _spell_buttons:
		btn.disabled = p_has_acted

func show_bar() -> void:
	show()

func hide_bar() -> void:
	hide()
