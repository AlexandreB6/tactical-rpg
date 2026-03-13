# Affiche les statistiques d'une unité en bas à droite de l'écran au clic.
extends CanvasLayer

@onready var avatar: TextureRect = $PanelContainer/MarginContainer/HBoxContainer/Avatar
@onready var close_button: Button = $CloseButton
@onready var name_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/NameLabel
@onready var hp_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/HpLabel
@onready var attack_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/AttackLabel
@onready var defense_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/DefenseLabel
@onready var move_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/MoveLabel
@onready var description_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/DescriptionLabel
@onready var defend_bonus_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/DefendBonusLabel
@onready var terrain_label: Label = $PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/TerrainLabel

# Signal émis quand le panel est fermé (pour effacer le highlight dans World)
signal panel_closed

func _ready() -> void:
	# Le thème root ne se propage pas à travers CanvasLayer, on l'applique manuellement
	$PanelContainer.theme = UITheme.current_theme
	hide()
	close_button.pressed.connect(_on_close_pressed)

# Remplit et affiche le panel avec les stats de l'unité cliquée
func show_stats(unit: Unit, terrain_text: String = "") -> void:
	name_label.text = unit.unit_name
	hp_label.text = "HP : " + str(unit.hp) + "/" + str(unit.max_hp)
	attack_label.text = "ATK : " + str(unit.attack)
	defense_label.text = "DEF : " + str(unit.defense)
	defend_bonus_label.visible = unit.is_defending
	terrain_label.text = terrain_text
	terrain_label.visible = terrain_text != ""
	move_label.text = "Mouvement : " + str(unit.move_range)
	var class_text = "Moine (Magie)" if unit.class_type == 1 else "Guerrier (Physique)"
	var spells_text = ""
	for spell in unit.spells:
		if spells_text != "":
			spells_text += ", "
		spells_text += spell.spell_name + " (portée " + str(spell.spell_range) + ")"
	var desc = unit.description
	if spells_text != "":
		desc += "\nClasse : " + class_text + "\nSorts : " + spells_text
	description_label.text = desc
	if unit.avatar_texture:
		avatar.texture = unit.avatar_texture
	else:
		avatar.texture = unit.body.texture
	show()
	await get_tree().process_frame
	$PanelContainer.reset_size()
	await get_tree().process_frame
	var viewport = get_viewport().get_visible_rect().size
	var panel = $PanelContainer
	panel.position = Vector2(viewport.x - panel.size.x - 10, viewport.y - panel.size.y - 10)
	close_button.position = Vector2(panel.position.x + panel.size.x - close_button.size.x - 2, panel.position.y + 2)

func _on_close_pressed() -> void:
	emit_signal("panel_closed")
	hide()
