# Scène principale — gère l'initialisation, les inputs et la coordination
# entre la grille, les unités et le GameManager.
extends Node2D

# --- Références aux nœuds enfants ---
@onready var hex_grid: Node2D = $HexGrid
@onready var units_node: Node2D = $Units
@onready var game_manager: Node = $GameManager
@onready var end_screen: CanvasLayer = $EndScreen
@onready var stats_panel: CanvasLayer = $StatsPanel
@onready var combat_log: CanvasLayer = $CombatLog
@onready var action_bar: CanvasLayer = $ActionBar

# --- Données des unités ---
const UnitScene = preload("res://scenes/units/Unit.tscn")

# Chemin du niveau à charger (modifiable pour charger d'autres niveaux)
@export var level_path: String = "res://data/levels/level_01.json"

# --- Machine d'état ---
enum State { IDLE, ACTION_BAR, SELECTING_MOVE, SELECTING_ATTACK, SELECTING_SPELL_TARGET }
var state: State = State.IDLE

# L'unité sélectionnée pour agir
var selected_unit = null
# L'unité dont on consulte les stats (clic droit)
var inspected_unit = null
# Position avant déplacement (pour undo)
var pre_move_pos: Vector2i = Vector2i(-1, -1)
# Bloque les inputs pendant les animations
var is_animating: bool = false
# Cache du curseur pour éviter les appels répétés
var _last_cursor: int = DisplayServer.CURSOR_ARROW
# Curseurs personnalisés
var _cursor_move: ImageTexture
var _cursor_attack: ImageTexture
# Cache des cases accessibles (BFS) pour l'unité sélectionnée
var _cached_reachable: Dictionary = {}
# Tooltip terrain (clic droit sur case vide)
var current_spell: SpellData = null
var _terrain_tooltip: CanvasLayer = null
var _terrain_tooltip_panel: PanelContainer = null
var _terrain_tooltip_label: Label = null
# Bouton fin de phase + confirmation
var _end_phase_layer: CanvasLayer = null
var _end_phase_button: Button = null
var _confirm_dialog: ConfirmationDialog = null

# --- Initialisation ---
func _ready() -> void:
	_create_cursors()
	_create_terrain_tooltip()
	_create_end_phase_button()
	# Utiliser le niveau sélectionné dans le menu si disponible
	if GameState.selected_level_path != "":
		level_path = GameState.selected_level_path
	await _load_level(level_path)
	game_manager.init(units_node, hex_grid, end_screen, combat_log)
	stats_panel.panel_closed.connect(_on_stats_panel_closed)
	action_bar.move_requested.connect(_on_move_requested)
	action_bar.attack_requested.connect(_on_attack_requested)
	action_bar.end_turn_requested.connect(_on_end_turn_requested)
	action_bar.cancel_requested.connect(_on_cancel_requested)
	action_bar.defend_requested.connect(_on_defend_requested)
	action_bar.spell_requested.connect(_on_spell_requested)
	game_manager.player_phase_started.connect(_on_player_phase_started)
	game_manager.enemy_phase_started.connect(_on_enemy_phase_started)
	game_manager.start_round()

# Charge un niveau depuis un fichier JSON
func _load_level(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Impossible de charger le niveau : " + path)
		return
	var json = JSON.new()
	json.parse(file.get_as_text())
	var data: Dictionary = json.data
	# Terrain
	var terrain_rows: Array = data["terrain"]
	var width: int = data.get("grid_width", 10)
	var height: int = data.get("grid_height", 8)
	var forest_rows: Array = data.get("forest", [])
	await hex_grid.load_terrain(terrain_rows, width, height, forest_rows)
	# Unités
	for unit_info in data["units"]:
		var unit_type: String = unit_info["data"]
		var unit_team: String = ""
		var overrides: Dictionary = {}
		# Lire l'équipe depuis le JSON (nouveau format)
		if unit_info.has("team"):
			unit_team = unit_info["team"]
		else:
			# Rétrocompatibilité : détecter le préfixe "enemy_"
			if unit_type.begins_with("enemy_"):
				unit_type = unit_type.substr(6)  # strip "enemy_"
				unit_team = "enemy"
			else:
				unit_team = "player"
		# Lire les overrides optionnels
		if unit_info.has("overrides"):
			overrides = unit_info["overrides"]
		var unit_data_path = "res://data/units/" + unit_type + ".tres"
		var unit_data: UnitData = load(unit_data_path)
		var pos = Vector2i(int(unit_info["pos"][0]), int(unit_info["pos"][1]))
		_spawn_unit(unit_data, pos, unit_team, overrides)

func _spawn_unit(data: UnitData, p_grid_pos: Vector2i, p_team: String = "player", overrides: Dictionary = {}) -> void:
	var unit = UnitScene.instantiate()
	units_node.add_child(unit)
	unit.setup(data, p_grid_pos, hex_grid, p_team, overrides)

# --- Bouton fin de phase ---

func _create_end_phase_button() -> void:
	_end_phase_layer = CanvasLayer.new()
	_end_phase_layer.layer = 10
	add_child(_end_phase_layer)
	_end_phase_button = Button.new()
	_end_phase_button.text = "Fin de phase"
	_end_phase_button.custom_minimum_size = Vector2(140, 36)
	_end_phase_button.anchor_left = 1.0
	_end_phase_button.anchor_right = 1.0
	_end_phase_button.anchor_top = 0.0
	_end_phase_button.anchor_bottom = 0.0
	_end_phase_button.offset_left = -152
	_end_phase_button.offset_top = 52
	_end_phase_button.offset_right = -12
	_end_phase_button.offset_bottom = 82
	_end_phase_button.pressed.connect(_on_end_phase_pressed)
	_end_phase_layer.add_child(_end_phase_button)
	# Dialog de confirmation
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Certaines unités n'ont pas encore agi.\nPasser au tour ennemi ?"
	_confirm_dialog.ok_button_text = "Confirmer"
	_confirm_dialog.cancel_button_text = "Annuler"
	_confirm_dialog.confirmed.connect(_force_end_phase)
	_end_phase_layer.add_child(_confirm_dialog)
	_end_phase_button.visible = false
	# Bouton retour au menu
	var menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.custom_minimum_size = Vector2(80, 30)
	menu_btn.anchor_left = 1.0
	menu_btn.anchor_right = 1.0
	menu_btn.anchor_top = 0.0
	menu_btn.anchor_bottom = 0.0
	menu_btn.offset_left = -92
	menu_btn.offset_top = 12
	menu_btn.offset_right = -12
	menu_btn.offset_bottom = 48
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	_end_phase_layer.add_child(menu_btn)

func _on_end_phase_pressed() -> void:
	if is_animating or not game_manager.is_player_phase():
		return
	if game_manager.all_players_done():
		_force_end_phase()
	else:
		_confirm_dialog.popup_centered()

func _force_end_phase() -> void:
	# Annuler la sélection en cours
	if selected_unit and not selected_unit.is_queued_for_deletion():
		if selected_unit.has_moved:
			selected_unit.position = hex_grid.get_cell_world_position(pre_move_pos)
			selected_unit.grid_pos = pre_move_pos
			selected_unit.has_moved = false
		selected_unit.set_highlight("")
	_clear_ui_state()
	_end_phase_button.visible = false
	game_manager.force_end_player_phase()

# --- Tooltip terrain ---

func _create_terrain_tooltip() -> void:
	_terrain_tooltip = CanvasLayer.new()
	_terrain_tooltip.layer = 10
	add_child(_terrain_tooltip)
	_terrain_tooltip_panel = PanelContainer.new()
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.1, 0.1, 0.1, 0.85)
	stylebox.border_color = Color(0.6, 0.55, 0.4, 0.9)
	stylebox.set_border_width_all(2)
	stylebox.set_corner_radius_all(4)
	stylebox.set_content_margin_all(8)
	_terrain_tooltip_panel.add_theme_stylebox_override("panel", stylebox)
	_terrain_tooltip_panel.visible = false
	_terrain_tooltip.add_child(_terrain_tooltip_panel)
	_terrain_tooltip_label = Label.new()
	_terrain_tooltip_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_terrain_tooltip_label.add_theme_font_size_override("font_size", 14)
	_terrain_tooltip_panel.add_child(_terrain_tooltip_label)

func _show_terrain_tooltip(cell: Vector2i) -> void:
	var terrain_name = hex_grid.get_terrain_name(cell)
	var def_bonus = hex_grid.get_terrain_def_bonus(cell)
	var height = hex_grid.get_height_at(cell)
	var passable = hex_grid.is_passable(cell)
	var text = terrain_name
	var details: Array[String] = []
	if def_bonus > 0:
		details.append("+" + str(def_bonus) + " DEF")
	if height > 1:
		details.append("+" + str(height - 1) + " ATK")
	if not passable:
		details.append("Infranchissable")
	if hex_grid.blocks_los(cell):
		details.append("Bloque la vue")
	if not details.is_empty():
		text += "\n" + "\n".join(details)
	_terrain_tooltip_label.text = text
	var mouse_pos = get_viewport().get_mouse_position()
	var vp_size = get_viewport().get_visible_rect().size
	# Positionner à droite et au-dessus du curseur
	await get_tree().process_frame
	var panel_size = _terrain_tooltip_panel.size
	var pos = mouse_pos + Vector2(16, -panel_size.y - 8)
	# Empêcher de sortir de l'écran
	if pos.x + panel_size.x > vp_size.x:
		pos.x = mouse_pos.x - panel_size.x - 16
	if pos.y < 0:
		pos.y = mouse_pos.y + 24
	_terrain_tooltip_panel.position = pos
	_terrain_tooltip_panel.visible = true

func _hide_terrain_tooltip() -> void:
	_terrain_tooltip_panel.visible = false

# --- Curseurs personnalisés ---

func _create_cursors() -> void:
	_cursor_attack = _load_icon_as_cursor(preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_05.png"), 32)
	_cursor_move = _load_icon_as_cursor(preload("res://assets/Tiny Swords/UI Elements/UI Elements/Icons/Icon_07.png"), 32)

func _load_icon_as_cursor(texture: Texture2D, target_size: int) -> ImageTexture:
	var img = texture.get_image()
	img.resize(target_size, target_size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

func _make_cursor_image(pixels: Array, main_color: Color) -> ImageTexture:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var outline = Color(0, 0, 0, 0.85)
	# Passe 1 : contour noir
	for p in pixels:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx != 0 or dy != 0:
					_safe_pixel(img, p.x + dx, p.y + dy, outline)
	# Passe 2 : couleur principale
	for p in pixels:
		_safe_pixel(img, p.x, p.y, main_color)
	return ImageTexture.create_from_image(img)

func _get_attack_pixels() -> Array:
	var pixels = []
	var cx = 15
	var cy = 15
	# Lignes du réticule (avec trou au centre)
	for i in range(32):
		if abs(i - cx) > 4:
			pixels.append(Vector2i(i, cy))
			pixels.append(Vector2i(cx, i))
	# Cercle rayon 8
	for deg in range(360):
		var a = deg_to_rad(float(deg))
		pixels.append(Vector2i(cx + int(round(8.0 * cos(a))), cy + int(round(8.0 * sin(a)))))
	# Point central
	pixels.append(Vector2i(cx, cy))
	return pixels

func _get_move_pixels() -> Array:
	var pixels = []
	var cx = 15
	var cy = 15
	# Lignes centrales
	for i in range(6, 26):
		pixels.append(Vector2i(i, cy))
		pixels.append(Vector2i(cx, i))
	# Pointes de flèche (4 directions)
	for s in range(5):
		# Haut
		pixels.append(Vector2i(cx - s, 6 + s))
		pixels.append(Vector2i(cx + s, 6 + s))
		# Bas
		pixels.append(Vector2i(cx - s, 25 - s))
		pixels.append(Vector2i(cx + s, 25 - s))
		# Gauche
		pixels.append(Vector2i(6 + s, cy - s))
		pixels.append(Vector2i(6 + s, cy + s))
		# Droite
		pixels.append(Vector2i(25 - s, cy - s))
		pixels.append(Vector2i(25 - s, cy + s))
	return pixels

func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)

# --- Curseur hover ---

func _set_cursor(shape: int) -> void:
	if shape != _last_cursor:
		_last_cursor = shape
		match shape:
			DisplayServer.CURSOR_CROSS:
				Input.set_custom_mouse_cursor(_cursor_attack, Input.CURSOR_ARROW, Vector2(16, 16))
			DisplayServer.CURSOR_MOVE:
				Input.set_custom_mouse_cursor(_cursor_move, Input.CURSOR_ARROW, Vector2(16, 16))
			_:
				Input.set_custom_mouse_cursor(null)

func _process(_delta: float) -> void:
	if not game_manager.is_player_phase() or is_animating or selected_unit == null:
		_set_cursor(DisplayServer.CURSOR_ARROW)
		return
	var cell = hex_grid.pixel_to_hex(get_global_mouse_position())
	if not hex_grid.is_valid_cell(cell):
		_set_cursor(DisplayServer.CURSOR_ARROW)
		return
	match state:
		State.ACTION_BAR:
			_update_cursor_action_bar(cell)
		State.SELECTING_MOVE:
			_update_cursor_selecting_move(cell)
		State.SELECTING_ATTACK:
			_update_cursor_selecting_attack(cell)
		State.SELECTING_SPELL_TARGET:
			_update_cursor_selecting_spell(cell)
		_:
			_set_cursor(DisplayServer.CURSOR_ARROW)

func _update_cursor_action_bar(cell: Vector2i) -> void:
	var hovered = _get_unit_at(cell)
	if hovered != null and hovered.team == "enemy" and not selected_unit.has_acted:
		if _is_in_attack_range(selected_unit, selected_unit.grid_pos, hovered.grid_pos):
			_set_cursor(DisplayServer.CURSOR_CROSS)
			return
		if not selected_unit.has_moved and _find_attack_move_cell(selected_unit, hovered) != Vector2i(-1, -1):
			_set_cursor(DisplayServer.CURSOR_CROSS)
			return
	if hovered == null and not selected_unit.has_moved:
		if _cached_reachable.has(cell):
			_set_cursor(DisplayServer.CURSOR_MOVE)
			return
	_set_cursor(DisplayServer.CURSOR_ARROW)

func _update_cursor_selecting_move(cell: Vector2i) -> void:
	var hovered = _get_unit_at(cell)
	if hovered == null:
		if _cached_reachable.has(cell):
			_set_cursor(DisplayServer.CURSOR_MOVE)
			return
	_set_cursor(DisplayServer.CURSOR_ARROW)

func _update_cursor_selecting_attack(cell: Vector2i) -> void:
	var hovered = _get_unit_at(cell)
	if hovered != null and hovered.team == "enemy":
		if _is_in_attack_range(selected_unit, selected_unit.grid_pos, hovered.grid_pos):
			_set_cursor(DisplayServer.CURSOR_CROSS)
			return
	_set_cursor(DisplayServer.CURSOR_ARROW)

# --- Gestion des inputs ---
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if not game_manager.is_player_phase() or is_animating:
		return
	var cell = hex_grid.pixel_to_hex(get_global_mouse_position())
	if not hex_grid.is_valid_cell(cell):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(cell)

# Clic gauche
func _handle_click(cell: Vector2i) -> void:
	_hide_terrain_tooltip()
	var clicked_unit = _get_unit_at(cell)
	match state:
		State.IDLE:
			_handle_idle_click(clicked_unit)
		State.ACTION_BAR:
			if clicked_unit == selected_unit:
				pass  # Clic sur soi-même → rien, garder la barre
			elif clicked_unit != null and clicked_unit.team == "player" and not clicked_unit.has_acted:
				# Allié actif → cancel + sélectionner
				await _on_cancel_requested()
				_handle_idle_click(clicked_unit)
			elif clicked_unit != null and clicked_unit.team == "enemy" and not selected_unit.has_acted:
				# Attaque directe si à portée
				if _is_in_attack_range(selected_unit, selected_unit.grid_pos, clicked_unit.grid_pos):
					await _execute_attack(selected_unit, clicked_unit)
				# Déplacement + attaque si pas encore bougé
				elif not selected_unit.has_moved:
					var move_cell = _find_attack_move_cell(selected_unit, clicked_unit)
					if move_cell != Vector2i(-1, -1):
						await _execute_move(selected_unit, move_cell)
						await _execute_attack(selected_unit, clicked_unit)
				# Ennemi hors portée → rien (garder la sélection)
			elif clicked_unit == null and not selected_unit.has_moved:
				# Case vide dans portée → déplacement direct
				if _cached_reachable.has(cell):
					await _execute_move(selected_unit, cell)
		State.SELECTING_MOVE:
			_handle_move_click(clicked_unit, cell)
		State.SELECTING_ATTACK:
			_handle_attack_click(clicked_unit)
		State.SELECTING_SPELL_TARGET:
			_handle_spell_target_click(clicked_unit, cell)

# Clic droit : inspection des stats ou tooltip terrain
func _handle_right_click(cell: Vector2i) -> void:
	var unit = _get_unit_at(cell)
	if unit == null:
		# Case vide → tooltip terrain
		_clear_inspection()
		_show_terrain_tooltip(cell)
		return
	# Unité → panel de stats
	_hide_terrain_tooltip()
	_clear_inspection()
	# Pose le ring cyan seulement si ce n'est pas l'unité sélectionnée
	if unit != selected_unit:
		inspected_unit = unit
		unit.set_highlight("stats")
	stats_panel.show_stats(unit, _get_terrain_text(unit.grid_pos))
	# Highlights de planification uniquement en IDLE (sans sélection active)
	if state == State.IDLE:
		_show_inspect_highlights(unit)

func _handle_idle_click(clicked_unit: Unit) -> void:
	if clicked_unit == null or clicked_unit.team != "player" or clicked_unit.has_acted:
		return
	_clear_inspection()
	selected_unit = clicked_unit
	_update_reachable_cache()
	clicked_unit.set_highlight("active")
	action_bar.setup_for_unit(clicked_unit)
	action_bar.update_buttons(clicked_unit.has_moved, clicked_unit.has_acted)
	action_bar.show_bar()
	stats_panel.show_stats(clicked_unit, _get_terrain_text(clicked_unit.grid_pos))
	state = State.ACTION_BAR
	_show_selection_highlights(clicked_unit)

# Utilisé par le bouton "Déplacer" (mode sélection explicite)
func _handle_move_click(clicked_unit: Unit, cell: Vector2i) -> void:
	if clicked_unit == selected_unit:
		# Clic sur soi-même → retour à la barre
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.update_buttons(selected_unit.has_moved, selected_unit.has_acted)
		action_bar.show_bar()
		return
	if clicked_unit != null and clicked_unit.team == "player" and not clicked_unit.has_acted:
		await _on_cancel_requested()
		_handle_idle_click(clicked_unit)
		return
	if clicked_unit != null:
		return
	if _cached_reachable.has(cell):
		await _execute_move(selected_unit, cell)
	else:
		# Hors portée → retour à la barre d'actions
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.update_buttons(selected_unit.has_moved, selected_unit.has_acted)
		action_bar.show_bar()

# Utilisé par le bouton "Attaquer" (mode sélection explicite)
func _handle_attack_click(clicked_unit: Unit) -> void:
	if clicked_unit == null or clicked_unit.team != "enemy":
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.show_bar()
		return
	if _is_in_attack_range(selected_unit, selected_unit.grid_pos, clicked_unit.grid_pos):
		await _execute_attack(selected_unit, clicked_unit)
	else:
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.show_bar()

# Clic en mode sélection de cible de sort
func _handle_spell_target_click(clicked_unit: Unit, cell: Vector2i) -> void:
	if clicked_unit == null or current_spell == null:
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.show_bar()
		current_spell = null
		return
	# Vérifier que la cible est du bon type
	var valid = false
	if current_spell.target_type == SpellData.TargetType.ALLY and clicked_unit.team == selected_unit.team:
		valid = true
	elif current_spell.target_type == SpellData.TargetType.ENEMY and clicked_unit.team != selected_unit.team:
		valid = true
	if valid and selected_unit.can_cast_spell_on(current_spell, selected_unit.grid_pos, clicked_unit.grid_pos, hex_grid):
		await _execute_spell(selected_unit, clicked_unit, current_spell)
	else:
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.show_bar()
		current_spell = null

func _update_cursor_selecting_spell(cell: Vector2i) -> void:
	if current_spell == null:
		_set_cursor(DisplayServer.CURSOR_ARROW)
		return
	var hovered = _get_unit_at(cell)
	if hovered != null:
		var is_valid_target = false
		if current_spell.target_type == SpellData.TargetType.ALLY and hovered.team == selected_unit.team:
			is_valid_target = true
		elif current_spell.target_type == SpellData.TargetType.ENEMY and hovered.team != selected_unit.team:
			is_valid_target = true
		if is_valid_target and selected_unit.can_cast_spell_on(current_spell, selected_unit.grid_pos, hovered.grid_pos, hex_grid):
			_set_cursor(DisplayServer.CURSOR_CROSS)
			return
	_set_cursor(DisplayServer.CURSOR_ARROW)

# --- Actions ---

func _execute_move(unit: Unit, cell: Vector2i) -> void:
	combat_log.add_entry(unit.unit_name + " se déplace", unit.unit_name)
	pre_move_pos = unit.grid_pos
	var blocked = _get_blocked_cells(unit)
	var start_cell = unit.grid_pos
	var path = hex_grid.find_path(unit.grid_pos, cell, blocked, unit.move_range)
	unit.grid_pos = cell
	hex_grid.clear_highlights()
	action_bar.hide_bar()
	stats_panel.hide()
	selected_unit = null
	state = State.IDLE
	is_animating = true
	await unit.move_along_path(path, start_cell)
	is_animating = false
	unit.has_moved = true
	selected_unit = unit
	state = State.ACTION_BAR
	action_bar.update_buttons(true, unit.has_acted)
	action_bar.show_bar()
	stats_panel.show_stats(unit, _get_terrain_text(unit.grid_pos))
	_show_selection_highlights(unit)

func _execute_attack(attacker: Unit, target: Unit) -> void:
	_clear_ui_state()
	is_animating = true
	var height_diff = hex_grid.get_height_at(attacker.grid_pos) - hex_grid.get_height_at(target.grid_pos)
	var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
	var result = Unit.calc_damage(attacker.attack, target, height_diff, terrain_def, attacker.damage_type)
	combat_log.add_entry(Unit.build_attack_log(attacker.unit_name, target.unit_name, result, height_diff, terrain_def, attacker.damage_type, target.armor_type), attacker.unit_name)
	await attacker.play_attack_anim(target.position)
	await target.take_damage(result.damage)
	is_animating = false
	game_manager.check_victory()
	game_manager.notify_unit_done(attacker)

func _execute_spell(caster: Unit, target: Unit, spell: SpellData) -> void:
	_clear_ui_state()
	current_spell = null
	is_animating = true
	await caster.play_cast_anim()
	await _play_spell_effect(target, spell)
	if spell.target_type == SpellData.TargetType.ALLY:
		await target.heal(spell.power)
		combat_log.add_entry(caster.unit_name + " lance " + spell.spell_name + " sur " + target.unit_name + " → +" + str(spell.power) + " HP", caster.unit_name)
	else:
		var height_diff = hex_grid.get_height_at(caster.grid_pos) - hex_grid.get_height_at(target.grid_pos)
		var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
		var def_power = target.get_effective_defense() + terrain_def
		var raw = spell.power - def_power
		var multiplier = Unit.DAMAGE_MULTIPLIERS[target.armor_type][spell.damage_type]
		var damage = max(1, int(raw * multiplier))
		var log_text = caster.unit_name + " lance " + spell.spell_name + " sur " + target.unit_name + " → -" + str(damage) + " HP"
		var detail = "  PWR " + str(spell.power) + " vs DEF " + str(def_power)
		if terrain_def > 0:
			detail += " (+" + str(terrain_def) + " terrain)"
		detail += " = " + str(raw) + " × " + str(multiplier)
		detail += " (" + Unit.get_damage_type_name(spell.damage_type) + " vs " + Unit.get_armor_type_name(target.armor_type) + ")"
		detail += " = " + str(damage)
		combat_log.add_entry(log_text + "\n" + detail, caster.unit_name)
		await target.take_damage(damage)
	is_animating = false
	game_manager.check_victory()
	game_manager.notify_unit_done(caster)

func _play_spell_effect(target: Unit, spell: SpellData) -> void:
	if spell.effect_texture == null:
		return
	var effect = Sprite2D.new()
	effect.texture = spell.effect_texture
	effect.hframes = spell.effect_hframes
	effect.frame = 0
	effect.position = target.position + Vector2(0, -20)
	effect.z_index = 999
	effect.z_as_relative = false
	# Scale l'effet pour une taille raisonnable
	var tex_size = spell.effect_texture.get_size()
	var frame_width = tex_size.x / spell.effect_hframes
	var scale_factor = 100.0 / max(frame_width, tex_size.y)
	effect.scale = Vector2(scale_factor, scale_factor)
	add_child(effect)
	# Animer les frames
	for i in range(spell.effect_hframes):
		effect.frame = i
		await get_tree().create_timer(0.08).timeout
	effect.queue_free()

# --- Callbacks barre d'actions ---

func _on_move_requested() -> void:
	if selected_unit == null:
		return
	state = State.SELECTING_MOVE
	hex_grid.highlight_cells(selected_unit.grid_pos, selected_unit.move_range, _get_blocked_cells(selected_unit))

func _on_spell_requested(spell_index: int) -> void:
	if selected_unit == null or spell_index >= selected_unit.spells.size():
		return
	current_spell = selected_unit.spells[spell_index]
	state = State.SELECTING_SPELL_TARGET
	# Highlight les cibles valides
	hex_grid.clear_highlights()
	var highlight_color = hex_grid.HIGHLIGHT_MOVE if current_spell.target_type == SpellData.TargetType.ALLY else hex_grid.HIGHLIGHT_ATTACK
	for unit in units_node.get_children():
		if unit.is_queued_for_deletion():
			continue
		var valid = false
		if current_spell.target_type == SpellData.TargetType.ALLY and unit.team == selected_unit.team:
			valid = true
		elif current_spell.target_type == SpellData.TargetType.ENEMY and unit.team != selected_unit.team:
			valid = true
		if valid and selected_unit.can_cast_spell_on(current_spell, selected_unit.grid_pos, unit.grid_pos, hex_grid):
			if hex_grid.cells.has(unit.grid_pos):
				hex_grid.cells[unit.grid_pos].color = highlight_color

func _on_attack_requested() -> void:
	if selected_unit == null:
		return
	var targets = _get_units_in_attack_range(selected_unit)
	if targets.is_empty():
		combat_log.add_entry("Aucune cible à portée.")
		return
	state = State.SELECTING_ATTACK
	_highlight_attack_targets(targets)

func _on_end_turn_requested() -> void:
	if selected_unit == null:
		return
	var unit = selected_unit
	_clear_ui_state()
	combat_log.add_entry(unit.unit_name + " termine son tour sans agir.", unit.unit_name)
	game_manager.notify_unit_done(unit)

func _on_cancel_requested() -> void:
	if selected_unit != null and selected_unit.has_moved:
		var unit = selected_unit
		var origin_pixel = hex_grid.get_cell_world_position(pre_move_pos)
		unit.grid_pos = pre_move_pos
		unit.has_moved = false
		unit.set_highlight("")
		_clear_ui_state()
		# Repositionnement instantané (pas d'animation pour l'annulation)
		unit.position = origin_pixel
		unit._update_z_index()
	else:
		_cancel_selection()

func _on_defend_requested() -> void:
	if selected_unit == null:
		return
	var unit = selected_unit
	_clear_ui_state()
	unit.activate_defend()
	combat_log.add_entry(unit.unit_name + " se défend (+1 DEF)", unit.unit_name)
	game_manager.notify_unit_done(unit)

# --- Callbacks phases ---

func _on_player_phase_started() -> void:
	_clear_ui_state()
	_set_cursor(DisplayServer.CURSOR_ARROW)
	_end_phase_button.visible = true

func _on_enemy_phase_started() -> void:
	if selected_unit and not selected_unit.is_queued_for_deletion():
		selected_unit.set_highlight("")
	_clear_ui_state()
	_set_cursor(DisplayServer.CURSOR_ARROW)
	_end_phase_button.visible = false

# --- Stats panel ---

func _on_stats_panel_closed() -> void:
	_clear_inspection()
	# Restaure les highlights de sélection si une unité est toujours active
	if state == State.ACTION_BAR and selected_unit != null and not selected_unit.is_queued_for_deletion():
		_show_selection_highlights(selected_unit)

# --- Highlights ---

# Zones pour l'unité sélectionnée : vert=mouvement (si pas encore bougé), rouge=ennemis attaquables
func _show_selection_highlights(unit: Unit) -> void:
	hex_grid.clear_highlights()
	var blocked =_get_blocked_cells(unit)
	var moveable: Array[Vector2i] = []
	if not unit.has_moved:
		moveable = hex_grid.get_reachable_cells(unit.grid_pos, unit.move_range, blocked)
		for cell in moveable:
			if hex_grid.cells.has(cell):
				hex_grid.cells[cell].color = hex_grid.HIGHLIGHT_MOVE
	# Ennemis attaquables depuis pos actuelle ou depuis les cases accessibles
	if not unit.has_acted:
		var sources: Array[Vector2i] = [unit.grid_pos]
		sources.append_array(moveable)
		for enemy in units_node.get_children():
			if enemy.is_queued_for_deletion() or enemy.team != "enemy":
				continue
			for source in sources:
				if _is_in_attack_range(unit, source, enemy.grid_pos):
					if hex_grid.cells.has(enemy.grid_pos):
						hex_grid.cells[enemy.grid_pos].color = hex_grid.HIGHLIGHT_ATTACK
					break
		# Cibles de sorts
		for spell in unit.spells:
			for other in units_node.get_children():
				if other.is_queued_for_deletion():
					continue
				var valid = false
				if spell.target_type == SpellData.TargetType.ALLY and other.team == unit.team:
					valid = true
				elif spell.target_type == SpellData.TargetType.ENEMY and other.team != unit.team:
					valid = true
				if valid and unit.can_cast_spell_on(spell, unit.grid_pos, other.grid_pos, hex_grid):
					if hex_grid.cells.has(other.grid_pos):
						var color = hex_grid.HIGHLIGHT_MOVE if spell.target_type == SpellData.TargetType.ALLY else hex_grid.HIGHLIGHT_ATTACK
						hex_grid.cells[other.grid_pos].color = color

# Zones complètes pour planification (clic droit) — ignore has_moved
func _show_inspect_highlights(unit: Unit) -> void:
	hex_grid.clear_highlights()
	var blocked =_get_blocked_cells(unit)
	var moveable =hex_grid.get_reachable_cells(unit.grid_pos, unit.move_range, blocked)
	var move_set ={}
	for cell in moveable:
		move_set[cell] = true
	# Collecter les cases attaquables (Dictionary pour dédupliquer)
	var attack_cells ={}
	var sources: Array[Vector2i] = [unit.grid_pos]
	sources.append_array(moveable)
	for source in sources:
		for cell in hex_grid.get_cells_in_range(source, unit.attack_range, {}, false):
			if not move_set.has(cell) and cell != unit.grid_pos and _is_in_attack_range(unit, source, cell):
				attack_cells[cell] = true
	for cell: Vector2i in attack_cells:
		if hex_grid.cells.has(cell):
			hex_grid.cells[cell].color = hex_grid.HIGHLIGHT_INSPECT_ATTACK
	for cell in moveable:
		if hex_grid.cells.has(cell):
			hex_grid.cells[cell].color = hex_grid.HIGHLIGHT_MOVE

func _highlight_attack_targets(targets: Array) -> void:
	for unit in targets:
		if hex_grid.cells.has(unit.grid_pos):
			hex_grid.cells[unit.grid_pos].color = hex_grid.HIGHLIGHT_ATTACK

# --- Helpers ---

func _clear_inspection() -> void:
	if inspected_unit and not inspected_unit.is_queued_for_deletion():
		if inspected_unit == selected_unit:
			inspected_unit.set_highlight("active")
		elif inspected_unit.has_acted:
			inspected_unit.set_highlight("acted")
		else:
			inspected_unit.set_highlight("")
		if state == State.IDLE:
			hex_grid.clear_highlights()
	inspected_unit = null

func _clear_ui_state() -> void:
	hex_grid.clear_highlights()
	action_bar.hide_bar()
	stats_panel.hide()
	selected_unit = null
	current_spell = null
	_cached_reachable = {}
	state = State.IDLE

func _update_reachable_cache() -> void:
	if selected_unit and not selected_unit.has_moved:
		var blocked = _get_blocked_cells(selected_unit)
		_cached_reachable = {}
		for cell in hex_grid.get_reachable_cells(selected_unit.grid_pos, selected_unit.move_range, blocked):
			_cached_reachable[cell] = true
	else:
		_cached_reachable = {}

func _cancel_selection() -> void:
	if selected_unit and not selected_unit.is_queued_for_deletion():
		if selected_unit.has_acted:
			selected_unit.set_highlight("acted")
		else:
			selected_unit.set_highlight("")
	_clear_ui_state()

func _get_blocked_cells(exclude_unit: Unit) -> Dictionary:
	var result ={}
	for unit in units_node.get_children():
		if unit != exclude_unit and not unit.is_queued_for_deletion():
			result[unit.grid_pos] = true
	return result

# Trouve la case accessible la plus proche depuis laquelle attaquer la cible.
# Retourne Vector2i(-1,-1) si aucune case accessible ne permet d'attaquer.
func _find_attack_move_cell(attacker: Unit, target: Unit) -> Vector2i:
	var blocked =_get_blocked_cells(attacker)
	var best_cell =Vector2i(-1, -1)
	var best_dist =INF
	for cell in hex_grid.get_reachable_cells(attacker.grid_pos, attacker.move_range, blocked):
		if _is_in_attack_range(attacker, cell, target.grid_pos):
			var d =hex_grid.hex_distance(attacker.grid_pos, cell)
			if d < best_dist:
				best_dist = d
				best_cell = cell
	return best_cell

func _get_units_in_attack_range(attacker: Unit) -> Array:
	var result = []
	for unit in units_node.get_children():
		if unit.team == "enemy" and not unit.is_queued_for_deletion():
			if _is_in_attack_range(attacker, attacker.grid_pos, unit.grid_pos):
				result.append(unit)
	return result

# Vérifie si la distance est dans la portée d'attaque (min et max) avec LOS
func _is_in_attack_range(unit: Unit, from: Vector2i, target_pos: Vector2i) -> bool:
	return unit.can_attack_from(from, target_pos, hex_grid)

func _get_unit_at(cell: Vector2i) -> Unit:
	for unit in units_node.get_children():
		if unit.grid_pos == cell:
			return unit
	return null

func _get_terrain_text(cell: Vector2i) -> String:
	var terrain_name = hex_grid.get_terrain_name(cell)
	var def_bonus = hex_grid.get_terrain_def_bonus(cell)
	var height = hex_grid.get_height_at(cell)
	var text = terrain_name
	var bonuses = []
	if height > 1:
		bonuses.append("+" + str(height - 1) + " ATK")
	if def_bonus > 0:
		bonuses.append("+" + str(def_bonus) + " DEF")
	if not bonuses.is_empty():
		text += " (" + ", ".join(bonuses) + ")"
	return text
