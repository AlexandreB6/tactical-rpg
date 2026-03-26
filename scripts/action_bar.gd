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
@onready var panel: PanelContainer = $PanelContainer

var _spells_button: Button = null
var _spells_panel: PanelContainer = null
var _spells_hbox: HBoxContainer = null
var _spell_buttons: Array[Button] = []
var _spells_open: bool = false

const ICONS = {
	"move": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_07.png"),
	"attack": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_05.png"),
	"defend": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_06.png"),
	"end": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_09.png"),
	"cancel": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_08.png"),
	"spells": preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_06.png"),
}

const HIGHLIGHT_COLOR = Color(1, 0.85, 0.3, 0.25)

func _ready() -> void:
	panel.theme = UITheme.current_theme
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

func setup_for_unit(unit: Unit) -> void:
	_close_spells_panel()
	# Nettoyer l'ancien bouton Sorts
	if _spells_button != null:
		_spells_button.queue_free()
		_spells_button = null
	_spell_buttons.clear()

	if unit.spells.is_empty():
		return

	# Créer le bouton "Sorts" dans la barre principale
	_spells_button = Button.new()
	_spells_button.custom_minimum_size = Vector2(86, 64)
	_spells_button.theme_type_variation = "BtnGhost"
	_setup_icon_button(_spells_button, "Sorts", ICONS["spells"])
	_spells_button.pressed.connect(_toggle_spells_panel)
	var attack_idx = attack_button.get_index()
	hbox.add_child(_spells_button)
	hbox.move_child(_spells_button, attack_idx + 1)

	# Créer le sous-panel de sorts (caché)
	_spells_panel = PanelContainer.new()
	_spells_panel.theme = UITheme.current_theme
	_spells_panel.visible = false
	_spells_hbox = HBoxContainer.new()
	_spells_hbox.add_theme_constant_override("separation", 6)
	_spells_panel.add_child(_spells_hbox)

	for i in range(unit.spells.size()):
		var spell: SpellData = unit.spells[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(86, 64)
		btn.theme_type_variation = "BtnGhost"
		_setup_icon_button(btn, spell.spell_name, spell.icon_texture if spell.icon_texture else ICONS["spells"])
		var idx = i
		btn.pressed.connect(func():
			emit_signal("spell_requested", idx)
			_close_spells_panel()
		)
		_spells_hbox.add_child(btn)
		_spell_buttons.append(btn)

	add_child(_spells_panel)

func _toggle_spells_panel() -> void:
	if _spells_open:
		_close_spells_panel()
	else:
		_open_spells_panel()

func _open_spells_panel() -> void:
	if _spells_panel == null:
		return
	_spells_open = true
	_spells_panel.visible = true
	_update_spells_highlight()
	# Positionner au-dessus du bouton Sorts, centré
	await get_tree().process_frame
	_reposition_spells_panel()

func _close_spells_panel() -> void:
	_spells_open = false
	if _spells_panel != null:
		_spells_panel.visible = false
	_update_spells_highlight()

func _reposition_spells_panel() -> void:
	if _spells_panel == null or _spells_button == null:
		return
	var btn_rect = _spells_button.get_global_rect()
	var panel_size = _spells_panel.size
	# Centrer horizontalement sur le bouton Sorts
	var x = btn_rect.position.x + btn_rect.size.x / 2.0 - panel_size.x / 2.0
	# Au-dessus de la barre principale avec un petit espace
	var y = panel.position.y - panel_size.y - 8
	_spells_panel.position = Vector2(x, y)

func _update_spells_highlight() -> void:
	if _spells_button == null:
		return
	if _spells_open:
		_spells_button.modulate = Color(1, 0.9, 0.5)
	else:
		_spells_button.modulate = Color(1, 1, 1)

func update_buttons(p_has_moved: bool, p_has_acted: bool = false) -> void:
	move_button.disabled = p_has_moved
	attack_button.disabled = p_has_acted
	defend_button.disabled = p_has_acted
	if _spells_button != null:
		_spells_button.disabled = p_has_acted
		if p_has_acted:
			_close_spells_panel()
	for btn in _spell_buttons:
		btn.disabled = p_has_acted

func show_bar() -> void:
	show()

func hide_bar() -> void:
	_close_spells_panel()
	hide()
