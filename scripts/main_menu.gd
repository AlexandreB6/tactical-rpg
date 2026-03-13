# Menu principal — sélection de niveau ou accès à l'éditeur
extends Control

var _level_list: ItemList
var _play_btn: Button
var _editor_btn: Button
var _levels: Array[String] = []

func _ready() -> void:
	_build_ui()
	_scan_levels()

func _build_ui() -> void:
	# Fond sombre
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.14, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Container centré
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 450)
	center.add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	# Titre
	var title = Label.new()
	title.text = "Tactical RPG"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var subtitle = Label.new()
	subtitle.text = "Choisir une mission"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(subtitle)
	vbox.add_child(HSeparator.new())
	# Liste des niveaux
	_level_list = ItemList.new()
	_level_list.custom_minimum_size.y = 200
	_level_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_level_list.item_activated.connect(_on_level_activated)
	vbox.add_child(_level_list)
	# Boutons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)
	_play_btn = Button.new()
	_play_btn.text = "Jouer"
	_play_btn.custom_minimum_size = Vector2(140, 40)
	_play_btn.pressed.connect(_on_play_pressed)
	btn_hbox.add_child(_play_btn)
	_editor_btn = Button.new()
	_editor_btn.text = "Editeur de niveau"
	_editor_btn.custom_minimum_size = Vector2(180, 40)
	_editor_btn.pressed.connect(_on_editor_pressed)
	btn_hbox.add_child(_editor_btn)
	# Quitter
	var quit_btn = Button.new()
	quit_btn.text = "Quitter"
	quit_btn.custom_minimum_size = Vector2(100, 40)
	quit_btn.pressed.connect(func(): get_tree().quit())
	btn_hbox.add_child(quit_btn)

func _scan_levels() -> void:
	_levels.clear()
	_level_list.clear()
	var dir = DirAccess.open("res://data/levels")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_names: Array[String] = []
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	for fname in file_names:
		var path = "res://data/levels/" + fname
		var display_name = _get_level_display_name(path)
		_level_list.add_item(display_name)
		_levels.append(path)
	if _level_list.item_count > 0:
		_level_list.select(0)

func _get_level_display_name(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return path.get_file()
	var json = JSON.new()
	json.parse(file.get_as_text())
	if json.data is Dictionary and json.data.has("name"):
		return json.data["name"]
	return path.get_file()

func _on_play_pressed() -> void:
	var selected = _level_list.get_selected_items()
	if selected.is_empty():
		return
	var path = _levels[selected[0]]
	# Passer le chemin du niveau à World via un autoload ou meta
	_start_level(path)

func _on_level_activated(_index: int) -> void:
	_on_play_pressed()

func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/editor/LevelEditor.tscn")

func _start_level(level_path: String) -> void:
	GameState.selected_level_path = level_path
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")
