# World3D.gd
# Scène principale 3D — gère l'initialisation, les inputs et la coordination.
# Adapté de world.gd pour le rendu 3D.
extends Node3D

# --- Références aux nœuds enfants ---
@onready var hex_grid: Node3D = $HexGrid3D
@onready var units_node: Node3D = $Units3D
@onready var game_manager: Node = $GameManager3D
@onready var end_screen: CanvasLayer = $EndScreen
@onready var stats_panel: CanvasLayer = $StatsPanel
@onready var combat_log: CanvasLayer = $CombatLog
@onready var action_bar: CanvasLayer = $ActionBar
@onready var camera_pivot: Node3D = $CameraPivot

# --- Données des unités ---
const Unit3DScene = preload("res://scenes/units/Unit3D.tscn")

@export var level_path: String = "res://data/levels/level_01.json"

# --- Machine d'état ---
enum State { IDLE, ACTION_BAR, SELECTING_MOVE, SELECTING_ATTACK, SELECTING_SPELL_TARGET }
var state: State = State.IDLE

var selected_unit: Unit3D = null
var inspected_unit: Unit3D = null
var pre_move_pos: Vector2i = Vector2i(-1, -1)
var is_animating: bool = false
var _last_cursor: int = DisplayServer.CURSOR_ARROW
var _cursor_move: ImageTexture
var _cursor_attack: ImageTexture
var _cached_reachable: Dictionary = {}
var current_spell: SpellData = null
var _terrain_tooltip: CanvasLayer = null
var _terrain_tooltip_panel: PanelContainer = null
var _terrain_tooltip_label: Label = null
var _end_phase_layer: CanvasLayer = null
var _end_phase_button: Button = null
var _confirm_dialog: ConfirmationDialog = null
var _compass: CanvasLayer = null

func _ready() -> void:
	_create_cursors()
	_create_terrain_tooltip()
	_create_end_phase_button()
	_create_compass()
	if GameState.selected_level_path != "":
		level_path = GameState.selected_level_path
	await _load_level(level_path)
	# Construire l'île flottante après le terrain
	hex_grid.build_floating_island()
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
	# Connecter la rotation caméra pour mettre à jour les sprites
	camera_pivot.camera_rotated.connect(_on_camera_rotated)
	game_manager.start_round()

func _create_compass() -> void:
	var compass_script = load("res://scripts/compass.gd")
	_compass = CanvasLayer.new()
	_compass.set_script(compass_script)
	add_child(_compass)
	_compass.setup(camera_pivot)

func _load_level(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Impossible de charger le niveau : " + path)
		return
	var json = JSON.new()
	json.parse(file.get_as_text())
	var data: Dictionary = json.data
	var terrain_rows: Array = data["terrain"]
	var width: int = data.get("grid_width", 10)
	var height: int = data.get("grid_height", 8)
	var forest_rows: Array = data.get("forest", [])
	await hex_grid.load_terrain(terrain_rows, width, height, forest_rows)
	for unit_info in data["units"]:
		var unit_type: String = unit_info["data"]
		var unit_team: String = ""
		var overrides: Dictionary = {}
		if unit_info.has("team"):
			unit_team = unit_info["team"]
		else:
			if unit_type.begins_with("enemy_"):
				unit_type = unit_type.substr(6)
				unit_team = "enemy"
			else:
				unit_team = "player"
		if unit_info.has("overrides"):
			overrides = unit_info["overrides"]
		var unit_data_path = "res://data/units/" + unit_type + ".tres"
		var unit_data: UnitData = load(unit_data_path)
		var pos = Vector2i(int(unit_info["pos"][0]), int(unit_info["pos"][1]))
		_spawn_unit(unit_data, pos, unit_team, overrides)

func _spawn_unit(data: UnitData, p_grid_pos: Vector2i, p_team: String = "player", overrides: Dictionary = {}) -> void:
	var unit = Unit3DScene.instantiate() as Unit3D
	units_node.add_child(unit)
	unit.setup(data, p_grid_pos, hex_grid, p_team, overrides)
	unit._camera_pivot = camera_pivot

# --- Raycast picking ---

func _raycast_to_hex(mouse_pos: Vector2) -> Vector2i:
	var camera: Camera3D = camera_pivot.camera
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	# Intersect avec le plan Y = hauteur moyenne (pour chaque hauteur)
	# Méthode simple : intersect plan Y pour chaque hauteur possible
	var best_cell = Vector2i(-1, -1)
	var best_dist = INF
	var heights_seen = {}
	for cell in hex_grid.terrain_map:
		var h = hex_grid.TERRAIN_INFO[hex_grid.terrain_map[cell]]["height"]
		heights_seen[h] = true
	for h in heights_seen:
		var plane_y = h * hex_grid.ELEVATION_UNIT + hex_grid.position.y
		# Intersect ray with Y plane
		if abs(dir.y) < 0.001:
			continue
		var t = (plane_y - from.y) / dir.y
		if t < 0:
			continue
		var hit = from + dir * t
		# Convertir en coordonnées hex
		var local_hit = hit - hex_grid.position
		var fq = (2.0 / 3.0 * local_hit.x) / hex_grid.HEX_SIZE
		var fr = (-1.0 / 3.0 * local_hit.x + sqrt(3.0) / 3.0 * local_hit.z) / hex_grid.HEX_SIZE
		var cell = hex_grid._axial_round(fq, fr)
		if hex_grid.is_valid_cell(cell) and hex_grid.get_height_at(cell) == h:
			var center = hex_grid.hex_to_world_local(cell.x, cell.y)
			var dist_xz = Vector2(local_hit.x - center.x, local_hit.z - center.z).length()
			if dist_xz < best_dist and dist_xz < hex_grid.HEX_SIZE * 1.2:
				best_dist = dist_xz
				best_cell = cell
	return best_cell

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
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Certaines unités n'ont pas encore agi.\nPasser au tour ennemi ?"
	_confirm_dialog.ok_button_text = "Confirmer"
	_confirm_dialog.cancel_button_text = "Annuler"
	_confirm_dialog.confirmed.connect(_force_end_phase)
	_end_phase_layer.add_child(_confirm_dialog)
	_end_phase_button.visible = false
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
	await get_tree().process_frame
	var panel_size = _terrain_tooltip_panel.size
	var pos = mouse_pos + Vector2(16, -panel_size.y - 8)
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

# --- Curseur hover ---

func _process(_delta: float) -> void:
	if not game_manager.is_player_phase() or is_animating or selected_unit == null:
		_set_cursor(DisplayServer.CURSOR_ARROW)
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var cell = _raycast_to_hex(mouse_pos)
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

# --- Gestion des inputs ---

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if not game_manager.is_player_phase() or is_animating:
		return
	var mouse_pos = event.position
	var cell = _raycast_to_hex(mouse_pos)
	if not hex_grid.is_valid_cell(cell):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(cell)

func _handle_click(cell: Vector2i) -> void:
	_hide_terrain_tooltip()
	var clicked_unit = _get_unit_at(cell)
	match state:
		State.IDLE:
			_handle_idle_click(clicked_unit)
		State.ACTION_BAR:
			if clicked_unit == selected_unit:
				pass
			elif clicked_unit != null and clicked_unit.team == "player" and not clicked_unit.has_acted:
				await _on_cancel_requested()
				_handle_idle_click(clicked_unit)
			elif clicked_unit != null and clicked_unit.team == "enemy" and not selected_unit.has_acted:
				if _is_in_attack_range(selected_unit, selected_unit.grid_pos, clicked_unit.grid_pos):
					await _execute_attack(selected_unit, clicked_unit)
				elif not selected_unit.has_moved:
					var move_cell = _find_attack_move_cell(selected_unit, clicked_unit)
					if move_cell != Vector2i(-1, -1):
						await _execute_move(selected_unit, move_cell)
						await _execute_attack(selected_unit, clicked_unit)
			elif clicked_unit == null and not selected_unit.has_moved:
				if _cached_reachable.has(cell):
					await _execute_move(selected_unit, cell)
		State.SELECTING_MOVE:
			_handle_move_click(clicked_unit, cell)
		State.SELECTING_ATTACK:
			_handle_attack_click(clicked_unit)
		State.SELECTING_SPELL_TARGET:
			_handle_spell_target_click(clicked_unit, cell)

func _handle_right_click(cell: Vector2i) -> void:
	var unit = _get_unit_at(cell)
	if unit == null:
		_clear_inspection()
		_show_terrain_tooltip(cell)
		return
	_hide_terrain_tooltip()
	_clear_inspection()
	if unit != selected_unit:
		inspected_unit = unit
		unit.set_highlight("stats")
	stats_panel.show_stats(unit, _get_terrain_text(unit.grid_pos))
	if state == State.IDLE:
		_show_inspect_highlights(unit)

func _handle_idle_click(clicked_unit) -> void:
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

func _handle_move_click(clicked_unit, cell: Vector2i) -> void:
	if clicked_unit == selected_unit:
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
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.update_buttons(selected_unit.has_moved, selected_unit.has_acted)
		action_bar.show_bar()

func _handle_attack_click(clicked_unit) -> void:
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

func _handle_spell_target_click(clicked_unit, cell: Vector2i) -> void:
	if clicked_unit == null or current_spell == null:
		_show_selection_highlights(selected_unit)
		state = State.ACTION_BAR
		action_bar.show_bar()
		current_spell = null
		return
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

# --- Actions ---

func _execute_move(unit: Unit3D, cell: Vector2i) -> void:
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

func _execute_attack(attacker: Unit3D, target: Unit3D) -> void:
	_clear_ui_state()
	is_animating = true
	var height_diff = hex_grid.get_height_at(attacker.grid_pos) - hex_grid.get_height_at(target.grid_pos)
	var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
	var result = Unit3D.calc_damage(attacker.attack, target, height_diff, terrain_def, attacker.damage_type)
	combat_log.add_entry(Unit3D.build_attack_log(attacker.unit_name, target.unit_name, result, height_diff, terrain_def, attacker.damage_type, target.armor_type), attacker.unit_name)
	await attacker.play_attack_anim(target.position)
	await target.take_damage(result.damage)
	is_animating = false
	game_manager.check_victory()
	game_manager.notify_unit_done(attacker)

func _execute_spell(caster: Unit3D, target: Unit3D, spell: SpellData) -> void:
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
		var multiplier = Unit3D.DAMAGE_MULTIPLIERS[target.armor_type][spell.damage_type]
		var damage = max(1, int(raw * multiplier))
		var log_text = caster.unit_name + " lance " + spell.spell_name + " sur " + target.unit_name + " → -" + str(damage) + " HP"
		var detail = "  PWR " + str(spell.power) + " vs DEF " + str(def_power)
		if terrain_def > 0:
			detail += " (+" + str(terrain_def) + " terrain)"
		detail += " = " + str(raw) + " × " + str(multiplier)
		detail += " (" + Unit3D.get_damage_type_name(spell.damage_type) + " vs " + Unit3D.get_armor_type_name(target.armor_type) + ")"
		detail += " = " + str(damage)
		combat_log.add_entry(log_text + "\n" + detail, caster.unit_name)
		await target.take_damage(damage)
	is_animating = false
	game_manager.check_victory()
	game_manager.notify_unit_done(caster)

func _play_spell_effect(target: Unit3D, spell: SpellData) -> void:
	if spell.effect_texture == null:
		return
	var effect = Sprite3D.new()
	effect.texture = spell.effect_texture
	effect.hframes = spell.effect_hframes
	effect.frame = 0
	effect.position = target.position + Vector3(0, 0.8, 0)
	effect.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	effect.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	effect.transparent = true
	var tex_size = spell.effect_texture.get_size()
	var frame_width = tex_size.x / spell.effect_hframes
	effect.pixel_size = 1.5 / max(frame_width, tex_size.y)
	add_child(effect)
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
	hex_grid.clear_highlights()
	var highlight_color = hex_grid.HIGHLIGHT_MOVE if current_spell.target_type == SpellData.TargetType.ALLY else hex_grid.HIGHLIGHT_ATTACK
	for unit in units_node.get_children():
		if not unit is Unit3D or unit.is_queued_for_deletion():
			continue
		var valid = false
		if current_spell.target_type == SpellData.TargetType.ALLY and unit.team == selected_unit.team:
			valid = true
		elif current_spell.target_type == SpellData.TargetType.ENEMY and unit.team != selected_unit.team:
			valid = true
		if valid and selected_unit.can_cast_spell_on(current_spell, selected_unit.grid_pos, unit.grid_pos, hex_grid):
			hex_grid.set_cell_color(unit.grid_pos, highlight_color)

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
		var origin_pos = hex_grid.get_cell_world_position(pre_move_pos)
		unit.grid_pos = pre_move_pos
		unit.has_moved = false
		unit.set_highlight("")
		_clear_ui_state()
		unit.position = origin_pos
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

func _on_camera_rotated() -> void:
	# Les sprites se mettent à jour automatiquement via _process
	pass

func _on_stats_panel_closed() -> void:
	_clear_inspection()
	if state == State.ACTION_BAR and selected_unit != null and not selected_unit.is_queued_for_deletion():
		_show_selection_highlights(selected_unit)

# --- Highlights ---

func _show_selection_highlights(unit: Unit3D) -> void:
	hex_grid.clear_highlights()
	var blocked = _get_blocked_cells(unit)
	var moveable: Array[Vector2i] = []
	if not unit.has_moved:
		moveable = hex_grid.get_reachable_cells(unit.grid_pos, unit.move_range, blocked)
		for cell in moveable:
			hex_grid.set_cell_color(cell, hex_grid.HIGHLIGHT_MOVE)
	if not unit.has_acted:
		var sources: Array[Vector2i] = [unit.grid_pos]
		sources.append_array(moveable)
		for enemy in units_node.get_children():
			if not enemy is Unit3D or enemy.is_queued_for_deletion() or enemy.team != "enemy":
				continue
			for source in sources:
				if _is_in_attack_range(unit, source, enemy.grid_pos):
					hex_grid.set_cell_color(enemy.grid_pos, hex_grid.HIGHLIGHT_ATTACK)
					break
		for spell in unit.spells:
			for other in units_node.get_children():
				if not other is Unit3D or other.is_queued_for_deletion():
					continue
				var valid = false
				if spell.target_type == SpellData.TargetType.ALLY and other.team == unit.team:
					valid = true
				elif spell.target_type == SpellData.TargetType.ENEMY and other.team != unit.team:
					valid = true
				if valid and unit.can_cast_spell_on(spell, unit.grid_pos, other.grid_pos, hex_grid):
					var color = hex_grid.HIGHLIGHT_MOVE if spell.target_type == SpellData.TargetType.ALLY else hex_grid.HIGHLIGHT_ATTACK
					hex_grid.set_cell_color(other.grid_pos, color)

func _show_inspect_highlights(unit: Unit3D) -> void:
	hex_grid.clear_highlights()
	var blocked = _get_blocked_cells(unit)
	var moveable = hex_grid.get_reachable_cells(unit.grid_pos, unit.move_range, blocked)
	var move_set = {}
	for cell in moveable:
		move_set[cell] = true
	var attack_cells = {}
	var sources: Array[Vector2i] = [unit.grid_pos]
	sources.append_array(moveable)
	for source in sources:
		for cell in hex_grid.get_cells_in_range(source, unit.attack_range, {}, false):
			if not move_set.has(cell) and cell != unit.grid_pos and _is_in_attack_range(unit, source, cell):
				attack_cells[cell] = true
	for cell: Vector2i in attack_cells:
		hex_grid.set_cell_color(cell, hex_grid.HIGHLIGHT_INSPECT_ATTACK)
	for cell in moveable:
		hex_grid.set_cell_color(cell, hex_grid.HIGHLIGHT_MOVE)

func _highlight_attack_targets(targets: Array) -> void:
	for unit in targets:
		hex_grid.set_cell_color(unit.grid_pos, hex_grid.HIGHLIGHT_ATTACK)

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

func _get_blocked_cells(exclude_unit: Unit3D) -> Dictionary:
	var result = {}
	for unit in units_node.get_children():
		if unit is Unit3D and unit != exclude_unit and not unit.is_queued_for_deletion():
			result[unit.grid_pos] = true
	return result

func _find_attack_move_cell(attacker: Unit3D, target: Unit3D) -> Vector2i:
	var blocked = _get_blocked_cells(attacker)
	var best_cell = Vector2i(-1, -1)
	var best_dist = INF
	for cell in hex_grid.get_reachable_cells(attacker.grid_pos, attacker.move_range, blocked):
		if _is_in_attack_range(attacker, cell, target.grid_pos):
			var d = hex_grid.hex_distance(attacker.grid_pos, cell)
			if d < best_dist:
				best_dist = d
				best_cell = cell
	return best_cell

func _get_units_in_attack_range(attacker: Unit3D) -> Array:
	var result = []
	for unit in units_node.get_children():
		if unit is Unit3D and unit.team == "enemy" and not unit.is_queued_for_deletion():
			if _is_in_attack_range(attacker, attacker.grid_pos, unit.grid_pos):
				result.append(unit)
	return result

func _is_in_attack_range(unit: Unit3D, from: Vector2i, target_pos: Vector2i) -> bool:
	return unit.can_attack_from(from, target_pos, hex_grid)

func _get_unit_at(cell: Vector2i) -> Unit3D:
	for unit in units_node.get_children():
		if unit is Unit3D and unit.grid_pos == cell:
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
