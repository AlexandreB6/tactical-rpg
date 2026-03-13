# Éditeur de niveaux — permet de peindre le terrain, placer des unités et sauvegarder en JSON
extends Node2D

@onready var hex_grid: Node2D = $HexGrid
@onready var camera: Camera2D = $Camera2D

# Mode d'édition
enum Mode { TERRAIN, UNITS }
var current_mode: Mode = Mode.TERRAIN

# Terrain sélectionné dans la palette
var current_terrain: int = 0  # HexGrid.Terrain.PLAINS
# Unité sélectionnée dans la palette
var current_unit_type: String = ""
# Dimensions de la grille
var grid_width: int = 10
var grid_height: int = 8
# Nom du niveau
var level_name: String = "Nouveau niveau"
# Painting
var _painting: bool = false
var _last_painted_cell: Vector2i = Vector2i(-1, -1)

# Unités placées : Vector2i → { "data": String }
var placed_units: Dictionary = {}
# Marqueurs visuels des unités (Vector2i → Node2D)
var _unit_markers: Dictionary = {}

# Liste des types d'unités disponibles (nom fichier sans .tres)
var _available_units: Array[String] = []

# UI
var _ui_layer: CanvasLayer
var _palette_container: VBoxContainer
var _terrain_buttons: Array[Button] = []
var _unit_buttons: Array[Button] = []
var _terrain_palette: VBoxContainer
var _unit_palette: VBoxContainer
var _mode_terrain_btn: Button
var _mode_units_btn: Button
var _name_input: LineEdit
var _width_spin: SpinBox
var _height_spin: SpinBox
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _status_label: Label
var _current_file_path: String = ""
var _erase_mode_btn: Button

# Mapping terrain enum → caractère pour le JSON
const TERRAIN_TO_CHAR = {0: "P", 1: "F", 2: "H", 3: "M", 4: "W"}
const TERRAIN_NAMES = {0: "Plaine", 1: "Foret", 2: "Colline", 3: "Montagne", 4: "Eau"}

# Couleurs des marqueurs par équipe
const MARKER_COLOR_PLAYER = Color(0.2, 0.5, 1.0, 0.85)
const MARKER_COLOR_ENEMY = Color(1.0, 0.25, 0.2, 0.85)
const MARKER_COLOR_UNKNOWN = Color(0.8, 0.8, 0.2, 0.85)

func _ready() -> void:
	_scan_available_units()
	_build_ui()
	_generate_empty_grid()

func _scan_available_units() -> void:
	_available_units.clear()
	var dir = DirAccess.open("res://data/units")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			_available_units.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	_available_units.sort()

func _generate_empty_grid() -> void:
	var rows: Array = []
	for r in range(grid_height):
		rows.append("P".repeat(grid_width))
	await hex_grid.load_terrain(rows, grid_width, grid_height)

func _regenerate_grid() -> void:
	var rows: Array = []
	var frows: Array = []
	for r in range(grid_height):
		var row = ""
		var frow = ""
		for q in range(grid_width):
			var cell = Vector2i(q, r)
			var terrain = hex_grid.terrain_map.get(cell, 0)
			row += TERRAIN_TO_CHAR.get(terrain, "P")
			frow += "F" if hex_grid.forest_map.has(cell) else "."
		rows.append(row)
		frows.append(frow)
	await hex_grid.load_terrain(rows, grid_width, grid_height, frows)
	_redraw_all_unit_markers()

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_hovered_control() != null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if current_mode == Mode.TERRAIN:
					_painting = true
					_last_painted_cell = Vector2i(-1, -1)
					_try_paint(get_global_mouse_position())
				elif current_mode == Mode.UNITS:
					_try_place_unit(get_global_mouse_position())
			else:
				_painting = false
				_last_painted_cell = Vector2i(-1, -1)
	if event is InputEventMouseMotion and _painting and current_mode == Mode.TERRAIN:
		_try_paint(get_global_mouse_position())

func _try_paint(global_pos: Vector2) -> void:
	var cell = hex_grid.pixel_to_hex(global_pos)
	if not hex_grid.is_valid_cell(cell):
		return
	if cell == _last_painted_cell:
		return
	_last_painted_cell = cell
	if current_terrain == 1:  # Terrain.FOREST
		# Forêt = overlay, on ne change pas le terrain de base
		if hex_grid.forest_map.has(cell):
			return
		hex_grid.forest_map[cell] = true
	else:
		var old_terrain = hex_grid.terrain_map.get(cell, 0)
		var had_forest = hex_grid.forest_map.has(cell)
		if old_terrain == current_terrain and not had_forest:
			return
		hex_grid.terrain_map[cell] = current_terrain
		hex_grid.forest_map.erase(cell)
	await _regenerate_grid()

func _try_place_unit(global_pos: Vector2) -> void:
	var cell = hex_grid.pixel_to_hex(global_pos)
	if not hex_grid.is_valid_cell(cell):
		return
	# Mode effacer : supprimer l'unité sur la case
	if current_unit_type == "":
		if placed_units.has(cell):
			placed_units.erase(cell)
			_remove_unit_marker(cell)
			_status_label.text = "Unite retiree en (%d, %d)" % [cell.x, cell.y]
		return
	# Si une unité est déjà là, la remplacer
	if placed_units.has(cell):
		placed_units.erase(cell)
		_remove_unit_marker(cell)
	placed_units[cell] = {"data": current_unit_type}
	_create_unit_marker(cell, current_unit_type)
	_status_label.text = "%s place en (%d, %d)" % [current_unit_type, cell.x, cell.y]

# --- Marqueurs visuels des unités ---

func _create_unit_marker(cell: Vector2i, unit_type: String) -> void:
	_remove_unit_marker(cell)
	var marker = Node2D.new()
	var h = hex_grid.get_height_at(cell)
	var pos = hex_grid.hex_to_pixel(cell.x, cell.y) + hex_grid.position + Vector2(0, -h * hex_grid.ELEVATION_PX)
	marker.position = pos
	var zi = (cell.y * 2 + (cell.x % 2)) * 2 + 1
	marker.z_index = zi
	marker.z_as_relative = false
	# Cercle coloré selon l'équipe
	var color = _get_unit_color(unit_type)
	var circle = _create_circle_polygon(14.0, color)
	marker.add_child(circle)
	# Label avec le nom de l'unité
	var label = Label.new()
	label.text = _get_unit_short_name(unit_type)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-20, -24)
	label.z_index = zi + 1
	label.z_as_relative = false
	marker.add_child(label)
	add_child(marker)
	_unit_markers[cell] = marker

func _create_circle_polygon(radius: float, color: Color) -> Polygon2D:
	var poly = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(16):
		var angle = TAU * i / 16.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * hex_grid.ISO_Y_SCALE))
	poly.polygon = points
	poly.color = color
	return poly

func _remove_unit_marker(cell: Vector2i) -> void:
	if _unit_markers.has(cell):
		_unit_markers[cell].queue_free()
		_unit_markers.erase(cell)

func _clear_all_unit_markers() -> void:
	for cell in _unit_markers:
		_unit_markers[cell].queue_free()
	_unit_markers.clear()

func _redraw_all_unit_markers() -> void:
	_clear_all_unit_markers()
	for cell in placed_units:
		if hex_grid.is_valid_cell(cell):
			_create_unit_marker(cell, placed_units[cell]["data"])

func _get_unit_color(unit_type: String) -> Color:
	if unit_type.begins_with("enemy"):
		return MARKER_COLOR_ENEMY
	# Charger le .tres pour vérifier l'équipe
	var path = "res://data/units/" + unit_type + ".tres"
	var data = load(path)
	if data and data.team == "enemy":
		return MARKER_COLOR_ENEMY
	elif data and data.team == "player":
		return MARKER_COLOR_PLAYER
	return MARKER_COLOR_UNKNOWN

func _get_unit_short_name(unit_type: String) -> String:
	# Première lettre en majuscule, sans "enemy_"
	var display = unit_type.replace("enemy_", "E:")
	return display.substr(0, 8)

# --- Construction de l'UI ---

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	# Panel gauche
	var panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_right = 200
	_ui_layer.add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	# ScrollContainer pour gérer le dépassement
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	# Titre
	var title = Label.new()
	title.text = "Editeur de niveau"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	# Nom du niveau
	var name_label = Label.new()
	name_label.text = "Nom :"
	vbox.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.text = level_name
	_name_input.text_changed.connect(func(t): level_name = t)
	vbox.add_child(_name_input)
	# Dimensions
	vbox.add_child(HSeparator.new())
	var dim_label = Label.new()
	dim_label.text = "Dimensions :"
	vbox.add_child(dim_label)
	var w_hbox = HBoxContainer.new()
	var w_label = Label.new()
	w_label.text = "Largeur:"
	w_label.custom_minimum_size.x = 70
	w_hbox.add_child(w_label)
	_width_spin = SpinBox.new()
	_width_spin.min_value = 3
	_width_spin.max_value = 30
	_width_spin.value = grid_width
	_width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_hbox.add_child(_width_spin)
	vbox.add_child(w_hbox)
	var h_hbox = HBoxContainer.new()
	var h_label = Label.new()
	h_label.text = "Hauteur:"
	h_label.custom_minimum_size.x = 70
	h_hbox.add_child(h_label)
	_height_spin = SpinBox.new()
	_height_spin.min_value = 3
	_height_spin.max_value = 30
	_height_spin.value = grid_height
	_height_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_hbox.add_child(_height_spin)
	vbox.add_child(h_hbox)
	var resize_btn = Button.new()
	resize_btn.text = "Redimensionner"
	resize_btn.pressed.connect(_on_resize)
	vbox.add_child(resize_btn)
	# --- Mode toggle ---
	vbox.add_child(HSeparator.new())
	var mode_label = Label.new()
	mode_label.text = "Mode :"
	vbox.add_child(mode_label)
	var mode_hbox = HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(mode_hbox)
	_mode_terrain_btn = Button.new()
	_mode_terrain_btn.text = "Terrain"
	_mode_terrain_btn.toggle_mode = true
	_mode_terrain_btn.button_pressed = true
	_mode_terrain_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_terrain_btn.pressed.connect(_on_mode_terrain)
	mode_hbox.add_child(_mode_terrain_btn)
	_mode_units_btn = Button.new()
	_mode_units_btn.text = "Unites"
	_mode_units_btn.toggle_mode = true
	_mode_units_btn.button_pressed = false
	_mode_units_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_units_btn.pressed.connect(_on_mode_units)
	mode_hbox.add_child(_mode_units_btn)
	# --- Palette terrain ---
	_terrain_palette = VBoxContainer.new()
	_terrain_palette.add_theme_constant_override("separation", 2)
	vbox.add_child(_terrain_palette)
	var terrain_title = Label.new()
	terrain_title.text = "Terrain :"
	_terrain_palette.add_child(terrain_title)
	for terrain_id in TERRAIN_NAMES:
		var btn = Button.new()
		btn.text = TERRAIN_NAMES[terrain_id]
		btn.toggle_mode = true
		btn.button_pressed = (terrain_id == current_terrain)
		btn.pressed.connect(_on_terrain_selected.bind(terrain_id))
		_terrain_palette.add_child(btn)
		_terrain_buttons.append(btn)
	# --- Palette unités ---
	_unit_palette = VBoxContainer.new()
	_unit_palette.add_theme_constant_override("separation", 2)
	_unit_palette.visible = false
	vbox.add_child(_unit_palette)
	var unit_title = Label.new()
	unit_title.text = "Unites :"
	_unit_palette.add_child(unit_title)
	# Bouton effacer
	_erase_mode_btn = Button.new()
	_erase_mode_btn.text = "Effacer"
	_erase_mode_btn.toggle_mode = true
	_erase_mode_btn.button_pressed = false
	_erase_mode_btn.pressed.connect(_on_unit_selected.bind(""))
	_unit_palette.add_child(_erase_mode_btn)
	# Boutons unités
	for unit_name in _available_units:
		var btn = Button.new()
		btn.text = unit_name
		btn.toggle_mode = true
		btn.pressed.connect(_on_unit_selected.bind(unit_name))
		_unit_palette.add_child(btn)
		_unit_buttons.append(btn)
	# Sélectionner la première unité par défaut
	if not _available_units.is_empty():
		current_unit_type = _available_units[0]
		_unit_buttons[0].button_pressed = true
	# Boutons save/load
	vbox.add_child(HSeparator.new())
	var save_btn = Button.new()
	save_btn.text = "Sauvegarder"
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)
	var saveas_btn = Button.new()
	saveas_btn.text = "Sauvegarder sous..."
	saveas_btn.pressed.connect(func(): _save_dialog.popup_centered())
	vbox.add_child(saveas_btn)
	var load_btn = Button.new()
	load_btn.text = "Charger"
	load_btn.pressed.connect(_on_load_pressed)
	vbox.add_child(load_btn)
	# Bouton retour menu
	vbox.add_child(HSeparator.new())
	var menu_btn = Button.new()
	menu_btn.text = "Retour au menu"
	menu_btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(menu_btn)
	# Status bar
	_status_label = Label.new()
	_status_label.text = "Pret"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_status_label)
	# Dialogs save/load
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.filters = PackedStringArray(["*.json ; Fichiers JSON"])
	_save_dialog.current_dir = "res://data/levels"
	_save_dialog.title = "Sauvegarder le niveau"
	_save_dialog.size = Vector2i(600, 400)
	_save_dialog.file_selected.connect(_on_save_file_selected)
	_ui_layer.add_child(_save_dialog)
	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_RESOURCES
	_load_dialog.filters = PackedStringArray(["*.json ; Fichiers JSON"])
	_load_dialog.current_dir = "res://data/levels"
	_load_dialog.title = "Charger un niveau"
	_load_dialog.size = Vector2i(600, 400)
	_load_dialog.file_selected.connect(_on_load_file_selected)
	_ui_layer.add_child(_load_dialog)

# --- Callbacks ---

func _on_mode_terrain() -> void:
	current_mode = Mode.TERRAIN
	_mode_terrain_btn.button_pressed = true
	_mode_units_btn.button_pressed = false
	_terrain_palette.visible = true
	_unit_palette.visible = false

func _on_mode_units() -> void:
	current_mode = Mode.UNITS
	_mode_terrain_btn.button_pressed = false
	_mode_units_btn.button_pressed = true
	_terrain_palette.visible = false
	_unit_palette.visible = true

func _on_terrain_selected(terrain_id: int) -> void:
	current_terrain = terrain_id
	for i in range(_terrain_buttons.size()):
		_terrain_buttons[i].button_pressed = (i == terrain_id)

func _on_unit_selected(unit_name: String) -> void:
	current_unit_type = unit_name
	_erase_mode_btn.button_pressed = (unit_name == "")
	for i in range(_unit_buttons.size()):
		_unit_buttons[i].button_pressed = (_available_units[i] == unit_name)

func _on_resize() -> void:
	var new_w = int(_width_spin.value)
	var new_h = int(_height_spin.value)
	var old_map = hex_grid.terrain_map.duplicate()
	grid_width = new_w
	grid_height = new_h
	# Supprimer les unités hors de la nouvelle grille
	var to_remove: Array[Vector2i] = []
	for cell in placed_units:
		if cell.x >= grid_width or cell.y >= grid_height:
			to_remove.append(cell)
	for cell in to_remove:
		placed_units.erase(cell)
	var old_forest = hex_grid.forest_map.duplicate()
	var rows: Array = []
	var frows: Array = []
	for r in range(grid_height):
		var row = ""
		var frow = ""
		for q in range(grid_width):
			var cell = Vector2i(q, r)
			var terrain = old_map.get(cell, 0)
			row += TERRAIN_TO_CHAR.get(terrain, "P")
			frow += "F" if old_forest.has(cell) else "."
		rows.append(row)
		frows.append(frow)
	await hex_grid.load_terrain(rows, grid_width, grid_height, frows)
	_redraw_all_unit_markers()
	_status_label.text = "Grille : %dx%d" % [grid_width, grid_height]

func _on_save_pressed() -> void:
	if _current_file_path != "":
		_save_to_file(_current_file_path)
	else:
		_save_dialog.popup_centered()

func _on_load_pressed() -> void:
	_load_dialog.popup_centered()

func _on_save_file_selected(path: String) -> void:
	_save_to_file(path)

func _on_load_file_selected(path: String) -> void:
	_load_from_file(path)

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# --- Save / Load ---

func _save_to_file(path: String) -> void:
	var terrain_rows: Array = []
	var forest_rows: Array = []
	var has_forest = false
	for r in range(grid_height):
		var row = ""
		var frow = ""
		for q in range(grid_width):
			var cell = Vector2i(q, r)
			var terrain = hex_grid.terrain_map.get(cell, 0)
			row += TERRAIN_TO_CHAR.get(terrain, "P")
			if hex_grid.forest_map.has(cell):
				frow += "F"
				has_forest = true
			else:
				frow += "."
		terrain_rows.append(row)
		forest_rows.append(frow)
	var units_array: Array = []
	for cell in placed_units:
		units_array.append({
			"data": placed_units[cell]["data"],
			"pos": [cell.x, cell.y]
		})
	var data = {
		"name": level_name,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"terrain": terrain_rows,
		"units": units_array
	}
	if has_forest:
		data["forest"] = forest_rows
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status_label.text = "Erreur sauvegarde !"
		return
	file.store_string(json_str)
	file.close()
	_current_file_path = path
	_status_label.text = "Sauvegarde : " + path.get_file()

func _load_from_file(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_status_label.text = "Erreur chargement !"
		return
	var json = JSON.new()
	json.parse(file.get_as_text())
	var data: Dictionary = json.data
	level_name = data.get("name", "Sans nom")
	grid_width = data.get("grid_width", 10)
	grid_height = data.get("grid_height", 8)
	_name_input.text = level_name
	_width_spin.value = grid_width
	_height_spin.value = grid_height
	# Charger le terrain
	var terrain_rows: Array = data["terrain"]
	var forest_rows: Array = data.get("forest", [])
	await hex_grid.load_terrain(terrain_rows, grid_width, grid_height, forest_rows)
	# Charger les unités
	placed_units.clear()
	_clear_all_unit_markers()
	if data.has("units"):
		for unit_info in data["units"]:
			var pos = Vector2i(int(unit_info["pos"][0]), int(unit_info["pos"][1]))
			placed_units[pos] = {"data": unit_info["data"]}
			_create_unit_marker(pos, unit_info["data"])
	_current_file_path = path
	_status_label.text = "Charge : " + path.get_file()
