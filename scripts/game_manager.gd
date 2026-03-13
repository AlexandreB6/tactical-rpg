# Gère les phases du jeu : phase joueur puis phase ennemie.
# Phase joueur : chaque unité joueur agit une fois, puis phase ennemie.
# Phase ennemie : tous les ennemis agissent automatiquement, puis nouveau round.
extends Node

# --- Phases ---
enum Phase { PLAYER_PHASE, ENEMY_PHASE }
var current_phase: Phase = Phase.PLAYER_PHASE

# --- État du jeu ---
var round_count: int = 0

# --- Références ---
var units_node: Node2D
var hex_grid: Node2D
var end_screen
var combat_log

# --- Signaux ---
signal player_phase_started
signal enemy_phase_started

# Initialise le GameManager avec les références nécessaires
func init(p_units_node: Node2D, p_hex_grid: Node2D, p_end_screen, p_combat_log) -> void:
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

# Appelé par world.gd après chaque action d'une unité joueur
func notify_unit_done(unit) -> void:
	unit.has_acted = true
	unit.set_highlight("acted")

# Retourne true si toutes les unités joueur ont agi
func all_players_done() -> bool:
	return _get_units_by_team("player").filter(func(u): return not u.has_acted).is_empty()

# Appelé par world.gd pour forcer le passage en phase ennemie
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

func _process_enemy(enemy: Unit) -> void:
	var players = _get_units_by_team("player")
	if players.is_empty():
		return
	# Vérifier si un sort de soin est utile (allié < 70% HP en range)
	var heal_result = await _try_enemy_heal(enemy)
	if heal_result:
		return
	var target: Unit = _choose_target(enemy, players)
	if target == null:
		return
	# Vérifier si un sort offensif est meilleur qu'une attaque physique
	if await _try_enemy_offensive_spell(enemy, target):
		return
	# Déjà à portée → attaque directement
	if enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
		await _enemy_attack(enemy, target)
		return
	# Sinon, se déplace vers la cible
	var best_cell = _find_best_move(enemy, target)
	if best_cell != enemy.grid_pos:
		var blocked = _get_occupied_cells()
		blocked.erase(enemy.grid_pos)
		var start_cell = enemy.grid_pos
		var path = hex_grid.find_path(enemy.grid_pos, best_cell, blocked, enemy.move_range)
		enemy.grid_pos = best_cell
		combat_log.add_entry(enemy.unit_name + " se déplace")
		await enemy.move_along_path(path, start_cell)
	# Attaque si à portée après déplacement
	if enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
		await _enemy_attack(enemy, target)

# Choisit la meilleure cible parmi les joueurs
# Priorité : cible tuable en un coup > cible la plus blessée > cible la plus proche
func _choose_target(enemy: Unit, players: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_score: float = -INF
	for player in players:
		var dist = hex_grid.hex_distance(enemy.grid_pos, player.grid_pos)
		var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(player.grid_pos)
		var terrain_def = hex_grid.get_terrain_def_bonus(player.grid_pos)
		var damage = Unit.calc_damage(enemy.attack, player, height_diff, terrain_def)
		var score: float = 0.0
		# Forte priorité : cible tuable en un coup
		if damage >= player.hp:
			score += 100.0
		# Priorité : cible blessée (ratio HP manquants)
		var missing_hp_ratio = 1.0 - (float(player.hp) / player.max_hp)
		score += missing_hp_ratio * 30.0
		# Préférer les cibles proches (accessibles plus facilement)
		score -= dist * 2.0
		# Bonus léger pour avantage de hauteur
		if height_diff > 0:
			score += height_diff * 3.0
		if score > best_score:
			best_score = score
			best = player
	return best

# Calcule et applique les dégâts d'une attaque ennemie
func _enemy_attack(enemy: Unit, target: Unit) -> void:
	var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(target.grid_pos)
	var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
	var damage = Unit.calc_damage(enemy.attack, target, height_diff, terrain_def)
	combat_log.add_entry(Unit.build_attack_log(enemy.unit_name, target.unit_name, damage, height_diff, terrain_def))
	await enemy.play_attack_anim(target.position)
	await target.take_damage(damage)
	check_victory()

# Trouve la meilleure case de déplacement pour l'ennemi
# Privilégie : cases d'attaque > proximité > avantage de hauteur
func _find_best_move(enemy: Unit, target: Unit) -> Vector2i:
	var best_cell: Vector2i = enemy.grid_pos
	var best_score: float = -INF
	var occupied = _get_occupied_cells()
	occupied.erase(enemy.grid_pos)
	var reachable = hex_grid.get_reachable_cells(enemy.grid_pos, enemy.move_range, occupied)
	for cell in reachable:
		var score: float = 0.0
		var dist_to_target = hex_grid.hex_distance(cell, target.grid_pos)
		# Forte priorité : case permettant d'attaquer la cible
		if enemy.can_attack_from(cell, target.grid_pos, hex_grid):
			score += 50.0
			# Parmi les cases d'attaque, préférer celles avec avantage de hauteur
			var h_diff = hex_grid.get_height_at(cell) - hex_grid.get_height_at(target.grid_pos)
			score += h_diff * 5.0
			# Unités à distance : préférer rester loin (maximiser la distance dans la portée)
			if enemy.min_attack_range > 1:
				score += dist_to_target * 2.0
		else:
			# Se rapprocher de la cible
			score -= dist_to_target * 3.0
		# Léger bonus de hauteur du terrain
		score += hex_grid.get_height_at(cell) * 1.0
		# Bonus défensif du terrain
		score += hex_grid.get_terrain_def_bonus(cell) * 2.0
		if score > best_score:
			best_score = score
			best_cell = cell
	return best_cell

# --- IA sorts ---

# Tente de lancer un sort de soin sur un allié blessé (< 70% HP)
func _try_enemy_heal(enemy: Unit) -> bool:
	for spell in enemy.spells:
		if spell.target_type != SpellData.TargetType.ALLY:
			continue
		var best_target: Unit = null
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

# Tente de lancer un sort offensif si plus efficace que l'attaque physique
func _try_enemy_offensive_spell(enemy: Unit, target: Unit) -> bool:
	for spell in enemy.spells:
		if spell.target_type != SpellData.TargetType.ENEMY:
			continue
		if not enemy.can_cast_spell_on(spell, enemy.grid_pos, target.grid_pos, hex_grid):
			continue
		var spell_damage = max(1, spell.power - target.get_effective_defense())
		var height_diff = hex_grid.get_height_at(enemy.grid_pos) - hex_grid.get_height_at(target.grid_pos)
		var terrain_def = hex_grid.get_terrain_def_bonus(target.grid_pos)
		var phys_damage = Unit.calc_damage(enemy.attack, target, height_diff, terrain_def)
		# Utiliser le sort si dégâts >= attaque physique ou pas à portée physique
		if spell_damage >= phys_damage or not enemy.can_attack_from(enemy.grid_pos, target.grid_pos, hex_grid):
			await _enemy_cast_spell(enemy, target, spell)
			return true
	return false

# Lance un sort ennemi (animation + effet)
func _enemy_cast_spell(enemy: Unit, target: Unit, spell: SpellData) -> void:
	await enemy.play_cast_anim()
	# Jouer l'effet visuel
	if spell.effect_texture:
		var effect = Sprite2D.new()
		effect.texture = spell.effect_texture
		effect.hframes = spell.effect_hframes
		effect.frame = 0
		effect.position = target.position + Vector2(0, -20)
		effect.z_index = 999
		effect.z_as_relative = false
		var tex_size = spell.effect_texture.get_size()
		var frame_width = tex_size.x / spell.effect_hframes
		var scale_factor = 100.0 / max(frame_width, tex_size.y)
		effect.scale = Vector2(scale_factor, scale_factor)
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

# Retourne toutes les unités vivantes d'une équipe
func _get_units_by_team(team: String) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units_node.get_children():
		if unit.team == team and not unit.is_queued_for_deletion():
			result.append(unit)
	return result

# Retourne toutes les cases occupées par des unités
func _get_occupied_cells() -> Dictionary:
	var result = {}
	for unit in units_node.get_children():
		if not unit.is_queued_for_deletion():
			result[unit.grid_pos] = true
	return result

# Vérifie si une équipe est entièrement éliminée
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
		if not unit.is_queued_for_deletion():
			unit.set_highlight("")
