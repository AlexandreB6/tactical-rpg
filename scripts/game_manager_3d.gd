# GameManager3D.gd
# Gère les phases du jeu en 3D : phase joueur puis phase ennemie.
# Adapté de game_manager.gd pour Unit3D et Node3D.
extends Node

enum Phase { PLAYER_PHASE, ENEMY_PHASE }
var current_phase: Phase = Phase.PLAYER_PHASE
var round_count: int = 0

var units_node: Node3D
var hex_grid: Node3D  # HexGrid3D
var end_screen
var combat_log

signal player_phase_started
signal enemy_phase_started

func init(p_units_node: Node3D, p_hex_grid: Node3D, p_end_screen, p_combat_log) -> void:
	units_node = p_units_node
	hex_grid = p_hex_grid
	end_screen = p_end_screen
	combat_log = p_combat_log

# --- Gestion des rounds ---

func start_round() -> void:
	round_count += 1
	combat_log.set_turn(round_count)
	combat_log.add_entry("=== Round " + str(round_count) + " ===")
	_start_player_phase()

func _start_player_phase() -> void:
	current_phase = Phase.PLAYER_PHASE
	for unit in _get_units_by_team("player"):
		unit.reset_for_new_round()
	combat_log.add_entry("--- Phase joueur ---")
	emit_signal("player_phase_started")

func notify_unit_done(unit) -> void:
	unit.has_acted = true
	unit.set_highlight("acted")

func all_players_done() -> bool:
	return _get_units_by_team("player").filter(func(u): return not u.has_acted).is_empty()

func force_end_player_phase() -> void:
	for unit in _get_units_by_team("player"):
		if not unit.has_acted:
			unit.has_acted = true
			unit.set_highlight("acted")
	_start_enemy_phase()

func _start_enemy_phase() -> void:
	current_phase = Phase.ENEMY_PHASE
	combat_log.add_entry("--- Phase ennemie ---")
	emit_signal("enemy_phase_started")
	await _run_all_enemies()
	await get_tree().create_timer(0.3).timeout
	start_round()

func _run_all_enemies() -> void:
	for enemy in _get_units_by_team("enemy"):
		if enemy.is_queued_for_deletion():
			continue
		enemy.set_highlight("active")
		await get_tree().create_timer(0.4).timeout
		await _process_enemy(enemy)
		enemy.set_highlight("")
		await get_tree().create_timer(0.2).timeout
		check_victory()
		if _get_units_by_team("player").is_empty() or _get_units_by_team("enemy").is_empty():
			return

func is_player_phase() -> bool:
	return current_phase == Phase.PLAYER_PHASE

# --- IA ennemie ---

func _process_enemy(enemy: Unit3D) -> void:
	var players = _get_units_by_team("player")
	if players.is_empty():
		return
	var heal_result = await _try_enemy_heal(enemy)
	if heal_result:
		return
	var target: Unit3D = _choose_target(enemy, players)
	if target == null:
		return
	if await _try_enemy_offensive_spell(enemy, target):
		return
	if enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
		await _enemy_attack(enemy, target)
		return
	var best_cell = _find_best_move(enemy, target)
	if best_cell != enemy.grid_pos:
		var blocked = _get_occupied_cells()
		blocked.erase(enemy.grid_pos)
		var start_cell = enemy.grid_pos
		var path = hex_grid.find_path(enemy.grid_pos, best_cell, blocked, enemy.move_range)
		enemy.grid_pos = best_cell
		combat_log.add_entry(enemy.unit_name + " se déplace")
		await enemy.move_along_path(path, start_cell)
	if enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
		await _enemy_attack(enemy, target)

func _choose_target(enemy: Unit3D, players: Array[Unit3D]) -> Unit3D:
	var best: Unit3D = null
	var best_score: float = -INF
	for player in players:
		var dist = hex_grid.hex_distance(enemy.grid_pos, player.grid_pos)
		var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(player.grid_pos)
		var terrain_def = hex_grid.get_terrain_def_bonus(player.grid_pos)
		var damage = Unit3D.calc_damage(enemy.attack, player, height_diff, terrain_def)
		var score: float = 0.0
		if damage >= player.hp:
			score += 100.0
		var missing_hp_ratio = 1.0 - (float(player.hp) / player.max_hp)
		score += missing_hp_ratio * 30.0
		score -= dist * 2.0
		if height_diff > 0:
			score += height_diff * 3.0
		if score > best_score:
			best_score = score
			best = player
	return best

func _enemy_attack(enemy: Unit3D, target: Unit3D) -> void:
	var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(target.grid_pos)
	var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
	var damage = Unit3D.calc_damage(enemy.attack, target, height_diff, terrain_def)
	combat_log.add_entry(Unit3D.build_attack_log(enemy.unit_name, target.unit_name, damage, height_diff, terrain_def))
	await enemy.play_attack_anim(target.position)
	await target.take_damage(damage)
	check_victory()

func _find_best_move(enemy: Unit3D, target: Unit3D) -> Vector2i:
	var best_cell: Vector2i = enemy.grid_pos
	var best_score: float = -INF
	var occupied = _get_occupied_cells()
	occupied.erase(enemy.grid_pos)
	var reachable = hex_grid.get_reachable_cells(enemy.grid_pos, enemy.move_range, occupied)
	for cell in reachable:
		var score: float = 0.0
		var dist_to_target = hex_grid.hex_distance(cell, target.grid_pos)
		if enemy.can_attack_from(cell, target.grid_pos, hex_grid):
			score += 50.0
			var h_diff = hex_grid.get_height_at(cell) - hex_grid.get_height_at(target.grid_pos)
			score += h_diff * 5.0
			if enemy.min_attack_range > 1:
				score += dist_to_target * 2.0
		else:
			score -= dist_to_target * 3.0
		score += hex_grid.get_height_at(cell) * 1.0
		score += hex_grid.get_terrain_def_bonus(cell) * 2.0
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell

# --- IA sorts ---

func _try_enemy_heal(enemy: Unit3D) -> bool:
	for spell in enemy.spells:
		if spell.target_type != SpellData.TargetType.ALLY:
			continue
		var best_target: Unit3D = null
		var worst_ratio: float = 1.0
		for ally in _get_units_by_team("enemy"):
			if ally.is_queued_for_deletion():
				continue
			var ratio = float(ally.hp) / ally.max_hp
			if ratio < 0.7 and ratio < worst_ratio:
				if enemy.can_cast_spell_on(spell, enemy.grid_pos, ally.grid_pos, hex_grid):
					worst_ratio = ratio
					best_target = ally
		if best_target != null:
			await _enemy_cast_spell(enemy, best_target, spell)
			return true
	return false

func _try_enemy_offensive_spell(enemy: Unit3D, target: Unit3D) -> bool:
	for spell in enemy.spells:
		if spell.target_type != SpellData.TargetType.ENEMY:
			continue
		if not enemy.can_cast_spell_on(spell, enemy.grid_pos, target.grid_pos, hex_grid):
			continue
		var spell_damage = max(1, spell.power - target.get_effective_defense())
		var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(target.grid_pos)
		var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
		var phys_damage = Unit3D.calc_damage(enemy.attack, target, height_diff, terrain_def)
		if spell_damage >= phys_damage or not enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
			await _enemy_cast_spell(enemy, target, spell)
			return true
	return false

func _enemy_cast_spell(enemy: Unit3D, target: Unit3D, spell: SpellData) -> void:
	await enemy.play_cast_anim()
	if spell.effect_texture:
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
		units_node.add_child(effect)
		for i in range(spell.effect_hframes):
			effect.frame = i
			await get_tree().create_timer(0.08).timeout
		effect.queue_free()
	if spell.target_type == SpellData.TargetType.ALLY:
		await target.heal(spell.power)
		combat_log.add_entry(enemy.unit_name + " lance " + spell.spell_name + " sur " + target.unit_name + " (+" + str(spell.power) + " HP)")
	else:
		var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
		var damage = max(1, spell.power - target.get_effective_defense() - terrain_def)
		combat_log.add_entry(enemy.unit_name + " lance " + spell.spell_name + " sur " + target.unit_name + " (-" + str(damage) + " HP)")
		await target.take_damage(damage)
		check_victory()

# --- Utilitaires ---

func _get_units_by_team(p_team: String) -> Array[Unit3D]:
	var result: Array[Unit3D] = []
	for unit in units_node.get_children():
		if unit is Unit3D and unit.team == p_team and not unit.is_queued_for_deletion():
			result.append(unit)
	return result

func _get_occupied_cells() -> Dictionary:
	var result = {}
	for unit in units_node.get_children():
		if unit is Unit3D and not unit.is_queued_for_deletion():
			result[unit.grid_pos] = true
	return result

func check_victory() -> void:
	var players = _get_units_by_team("player")
	var enemies = _get_units_by_team("enemy")
	if players.is_empty():
		_clear_all_highlights()
		combat_log.add_entry("=== DÉFAITE ===")
		end_screen.show_end_screen("DÉFAITE !")
	elif enemies.is_empty():
		_clear_all_highlights()
		combat_log.add_entry("=== VICTOIRE ===")
		end_screen.show_end_screen("VICTOIRE !")

func _clear_all_highlights() -> void:
	for unit in units_node.get_children():
		if unit is Unit3D and not unit.is_queued_for_deletion():
			unit.set_highlight("")
