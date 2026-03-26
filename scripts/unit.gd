# Unit.gd
# Représente une unité sur la grille (joueur ou ennemi).
# Gère l'affichage, les stats et les animations.
class_name Unit
extends Node2D

# --- Constantes couleur ---
const COLOR_ACTIVE = Color(1.0, 0.9, 0.1, 0.85)
const COLOR_STATS = Color(0.2, 0.9, 0.9, 0.6)
const COLOR_ACTED_MODULATE = Color(0.6, 0.6, 0.6, 1.0)

# --- Stats (chargées depuis UnitData.tres) ---
var unit_name: String = ""
var max_hp: int = 10
var hp: int = 10
var attack: int = 3
var defense: int = 1
var move_range: int = 3
var attack_range: int = 1
var min_attack_range: int = 1
var team: String = "player"
var description: String = ""
var initiative: int = 5
var avatar_texture: Texture2D = null
var class_type: int = 0  # 0=PHYSICAL, 1=MAGIC
var damage_type: int = 0  # UnitData.DamageType
var armor_type: int = 0   # UnitData.ArmorType
var spells: Array[SpellData] = []

# Table de multiplicateurs : DAMAGE_MULTIPLIERS[armor_type][damage_type]
#                          SLASHING  PIERCING  BLUNT  MAGIC
const DAMAGE_MULTIPLIERS = [
	[1.2, 1.0, 0.8, 1.2],  # NONE   - vulnérable tranchant/magie, résiste contondant
	[0.8, 1.0, 1.0, 1.0],  # LIGHT  - résiste tranchant
	[0.6, 1.2, 1.0, 1.0],  # CHAIN  - résiste tranchant, vulnérable perçant
	[0.5, 0.7, 1.3, 0.8],  # PLATE  - résiste tranchant/perçant, vulnérable contondant
]

# --- État en jeu ---
var grid_pos: Vector2i = Vector2i(0, 0)
var has_acted: bool = false
var has_moved: bool = false
var is_defending: bool = false
var iso_y_scale: float = 1.0
var _hex_grid: Node2D = null

# --- Références aux nœuds enfants ---
@onready var body: Sprite2D = $Body
@onready var name_label: Label = $NameLabel
@onready var highlight: Polygon2D = $Highlight
@onready var shield_label: Label = $ShieldLabel


# --- Animation ---
var _idle_texture: Texture2D = null
var _idle_hframes: int = 1
var _run_texture: Texture2D = null
var _run_hframes: int = 1
var _attack_texture: Texture2D = null
var _attack_hframes: int = 1
var _guard_texture: Texture2D = null
var _guard_hframes: int = 1
var _cast_texture: Texture2D = null
var _cast_hframes: int = 1
var _projectile_texture: Texture2D = null
var _frame_count: int = 1
var _frame_timer: float = 0.0
var _current_frame: int = 0
var _flip_x: float = 1.0
var _sprite_scale_factor: float = 1.0
const FRAME_DURATION: float = 0.12
const ATTACK_FRAME_DURATION: float = 0.10

# Animation one-shot (attaque)
var _playing_oneshot: bool = false
var _oneshot_frame_duration: float = ATTACK_FRAME_DURATION

# Initialise l'unité depuis ses données et la positionne sur la grille
func setup(data: UnitData, p_grid_pos: Vector2i, hex_grid: Node2D, p_team: String = "player", overrides: Dictionary = {}) -> void:
	unit_name = data.unit_name
	max_hp = data.hp
	hp = data.hp
	attack = data.attack
	defense = data.defense
	move_range = data.move_range
	attack_range = data.attack_range
	min_attack_range = data.min_attack_range
	initiative = data.initiative
	team = p_team
	description = data.description
	avatar_texture = data.avatar_texture
	# Avatar ennemi si disponible
	if team == "enemy" and data.enemy_avatar_texture:
		avatar_texture = data.enemy_avatar_texture
	grid_pos = p_grid_pos
	_hex_grid = hex_grid
	iso_y_scale = hex_grid.ISO_Y_SCALE
	position = hex_grid.get_cell_world_position(p_grid_pos)
	_update_z_index()
	# Éléments UI toujours au-dessus des hex (z_index global élevé)
	for ui_node in [name_label, shield_label]:
		ui_node.z_index = 1000
		ui_node.z_as_relative = false
	# Stocker les textures d'animation
	_idle_texture = data.sprite_texture
	_idle_hframes = data.sprite_hframes
	_run_texture = data.sprite_run_texture
	_run_hframes = data.sprite_run_hframes
	_attack_texture = data.sprite_attack_texture
	_attack_hframes = data.sprite_attack_hframes
	_guard_texture = data.sprite_guard_texture
	_guard_hframes = data.sprite_guard_hframes
	_cast_texture = data.sprite_cast_texture
	_cast_hframes = data.sprite_cast_hframes
	_projectile_texture = data.projectile_texture
	_sprite_scale_factor = data.sprite_scale_factor
	class_type = data.class_type
	damage_type = data.damage_type
	armor_type = data.armor_type
	spells = data.spells.duplicate()
	# Appliquer les overrides
	_apply_overrides(overrides)
	# Remapper les sprites pour l'équipe ennemie
	if team == "enemy":
		_remap_sprites_for_team()
	_setup_body(data)
	name_label.visible = false
	if _idle_texture:
		_start_idle_animation()

# Applique les overrides de stats depuis le JSON
func _apply_overrides(overrides: Dictionary) -> void:
	for key in overrides:
		match key:
			"hp":
				hp = overrides[key]
				max_hp = overrides[key]
			"attack":
				attack = overrides[key]
			"defense":
				defense = overrides[key]
			"move_range":
				move_range = overrides[key]
			"initiative":
				initiative = overrides[key]
			"attack_range":
				attack_range = overrides[key]
			"min_attack_range":
				min_attack_range = overrides[key]
			"unit_name":
				unit_name = overrides[key]
			"damage_type":
				damage_type = overrides[key]
			"armor_type":
				armor_type = overrides[key]
			"spells":
				spells.clear()
				for spell_name in overrides[key]:
					var spell = load("res://data/spells/" + spell_name + ".tres")
					if spell:
						spells.append(spell)

# Remplace "Blue Units" par "Red Units" dans les chemins de textures
func _remap_sprites_for_team() -> void:
	_idle_texture = _remap_texture(_idle_texture)
	_run_texture = _remap_texture(_run_texture)
	_attack_texture = _remap_texture(_attack_texture)
	_guard_texture = _remap_texture(_guard_texture)
	_cast_texture = _remap_texture(_cast_texture)
	_projectile_texture = _remap_texture(_projectile_texture)

func _remap_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var path = tex.resource_path
	if "Blue Units" in path:
		var new_path = path.replace("Blue Units", "Red Units")
		var remapped = load(new_path)
		if remapped:
			return remapped
	return tex

# Configure le visuel du pion : sprite si disponible, sinon cercle coloré
func _setup_body(data: UnitData) -> void:
	if _idle_texture:
		body.texture = _idle_texture
		_frame_count = _idle_hframes
		body.hframes = _frame_count
		body.frame = 0
		var tex_size = _idle_texture.get_size()
		var frame_width = tex_size.x / _frame_count
		var frame_height = tex_size.y
		var target_size = 110.0
		var scale_factor = target_size / max(frame_width, frame_height) * _sprite_scale_factor
		_flip_x = -1.0 if team == "enemy" else 1.0
		body.scale = Vector2(scale_factor * _flip_x, scale_factor)
		body.position.y = -20.0
	else:
		body.texture = null
		var fallback_color = Color(0.9, 0.2, 0.2) if team == "enemy" else Color(0.2, 0.4, 0.9)
		_draw_body_fallback(fallback_color)

# Fallback : dessine un cercle coloré quand il n'y a pas de sprite
func _draw_body_fallback(color: Color) -> void:
	var size = 40
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0
	for x in range(size):
		for y in range(size):
			if Vector2(x, y).distance_to(center) <= radius:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex = ImageTexture.create_from_image(img)
	body.texture = tex

# Lance l'animation idle
func _start_idle_animation() -> void:
	_frame_timer = randf_range(0.0, FRAME_DURATION * _frame_count)
	_current_frame = randi_range(0, _frame_count - 1)
	body.frame = _current_frame

# Switch le sprite sheet actif
func _switch_sprite(texture: Texture2D, hframes: int) -> void:
	if texture == null:
		return
	body.texture = texture
	body.hframes = hframes
	_frame_count = hframes
	_current_frame = 0
	_frame_timer = 0.0
	body.frame = 0
	# Recalculer le scale pour la nouvelle texture
	var tex_size = texture.get_size()
	var frame_width = tex_size.x / hframes
	var frame_height = tex_size.y
	var target_size = 110.0
	var scale_factor = target_size / max(frame_width, frame_height) * _sprite_scale_factor
	body.scale = Vector2(scale_factor * _flip_x, scale_factor)

func _switch_to_idle() -> void:
	_playing_oneshot = false
	_switch_sprite(_idle_texture, _idle_hframes)

func _switch_to_run() -> void:
	if _run_texture:
		_switch_sprite(_run_texture, _run_hframes)

func _process(delta: float) -> void:
	if _frame_count <= 1:
		return
	var duration = _oneshot_frame_duration if _playing_oneshot else FRAME_DURATION
	_frame_timer += delta
	if _frame_timer >= duration:
		_frame_timer -= duration
		_current_frame = (_current_frame + 1) % _frame_count
		body.frame = _current_frame

# Joue l'animation d'attaque une fois puis revient à idle
# target_pos : position monde de la cible (pour le projectile)
func play_attack_anim(target_pos: Vector2 = Vector2.ZERO) -> void:
	if _attack_texture == null:
		var tween = create_tween()
		tween.tween_property(body, "position:y", body.position.y - 6.0, 0.08)
		tween.tween_property(body, "position:y", -20.0, 0.08)
		await tween.finished
		return
	_switch_sprite(_attack_texture, _attack_hframes)
	_playing_oneshot = true
	_oneshot_frame_duration = ATTACK_FRAME_DURATION
	var anim_duration = ATTACK_FRAME_DURATION * _attack_hframes
	# Lancer le projectile à mi-animation (moment du tir)
	if _projectile_texture and target_pos != Vector2.ZERO:
		get_tree().create_timer(anim_duration * 0.4).timeout.connect(
			func(): _fire_projectile(target_pos), CONNECT_ONE_SHOT
		)
	await get_tree().create_timer(anim_duration).timeout
	_switch_to_idle()

# Joue l'animation de cast (sort) une fois puis revient à idle
func play_cast_anim() -> void:
	if _cast_texture == null:
		# Fallback : petit bounce
		var tween = create_tween()
		tween.tween_property(body, "position:y", body.position.y - 8.0, 0.1)
		tween.tween_property(body, "position:y", -20.0, 0.1)
		await tween.finished
		return
	_switch_sprite(_cast_texture, _cast_hframes)
	_playing_oneshot = true
	_oneshot_frame_duration = ATTACK_FRAME_DURATION
	var anim_duration = ATTACK_FRAME_DURATION * _cast_hframes
	await get_tree().create_timer(anim_duration).timeout
	_switch_to_idle()

# Restaure des HP (plafonné à max_hp) avec un flash vert
func heal(amount: int) -> void:
	hp = min(hp + amount, max_hp)
	_spawn_floating_text("+" + str(amount), Color(0.2, 0.9, 0.2))
	# Flash vert (soin)
	body.modulate = Color(0.5, 2.0, 0.5, 1.0)
	var tween = create_tween()
	tween.tween_property(body, "modulate", Color(1, 1, 1, 1), 0.3)
	await tween.finished

# Vérifie si un sort peut être lancé depuis from vers target_pos
func can_cast_spell_on(spell: SpellData, from: Vector2i, target_pos: Vector2i, p_hex_grid: Node2D) -> bool:
	var dist = p_hex_grid.hex_distance(from, target_pos)
	if dist < spell.min_spell_range or dist > spell.spell_range:
		return false
	if spell.needs_los and not p_hex_grid.has_line_of_sight(from, target_pos):
		return false
	return true

# Crée un projectile qui vole en cloche vers la cible
func _fire_projectile(target_pos: Vector2) -> void:
	var projectile = Sprite2D.new()
	projectile.texture = _projectile_texture
	projectile.scale = Vector2(0.5, 0.5)
	projectile.z_index = 100
	var start = position + Vector2(0, -20)
	var target = target_pos + Vector2(0, -20)
	projectile.position = start
	get_parent().get_parent().add_child(projectile)
	# Arc en cloche : interpolation manuelle position + rotation
	var dist = start.distance_to(target)
	var arc_height = clampf(dist * 0.5, 40.0, 120.0)
	var duration = clampf(dist / 300.0, 0.3, 0.7)
	var elapsed = 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t = clampf(elapsed / duration, 0.0, 1.0)
		# Position linéaire + arc parabolique en Y
		var pos = start.lerp(target, t)
		pos.y -= arc_height * 4.0 * t * (1.0 - t)
		projectile.position = pos
		# Rotation = tangente de la trajectoire
		var dt = 0.01
		var t2 = clampf(t + dt, 0.0, 1.0)
		var next_pos = start.lerp(target, t2)
		next_pos.y -= arc_height * 4.0 * t2 * (1.0 - t2)
		var tangent = next_pos - pos
		projectile.rotation = tangent.angle()
		if abs(tangent.angle()) > PI / 2.0:
			projectile.flip_v = true
		else:
			projectile.flip_v = false
		await get_tree().process_frame
	projectile.queue_free()

# Affiche un texte flottant qui monte et disparaît (dégâts ou soin)
func _spawn_floating_text(text: String, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-20, -50)
	label.z_index = 1000
	label.z_as_relative = false
	add_child(label)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(label.queue_free)

# Applique des dégâts à l'unité et la supprime si ses HP tombent à 0
func take_damage(amount: int) -> void:
	hp -= amount
	_spawn_floating_text("-" + str(amount), Color(1.0, 0.2, 0.2))
	# Flash blanc (impact) + shake
	body.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var base_pos = body.position
	var tween = create_tween()
	# Shake rapide (3 secousses)
	tween.tween_property(body, "position", base_pos + Vector2(5, -2), 0.03)
	tween.tween_property(body, "position", base_pos + Vector2(-5, 3), 0.03)
	tween.tween_property(body, "position", base_pos + Vector2(4, -1), 0.03)
	tween.tween_property(body, "position", base_pos + Vector2(-3, 2), 0.03)
	tween.tween_property(body, "position", base_pos, 0.03)
	# Flash blanc → rouge → normal
	tween.parallel().tween_property(body, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.05)
	tween.tween_property(body, "modulate", Color(1, 1, 1, 1), 0.2)
	await tween.finished
	if hp <= 0:
		queue_free()


# Calcule le z_index de l'unité d'après sa position sur la grille
# Impair = entre les couches hex (pairs) pour une occlusion correcte
# Met à jour le z_index global de l'unité (impair, intercalé avec les hex pairs)
func _update_z_index() -> void:
	z_index = (grid_pos.y * 2 + (grid_pos.x % 2)) * 2 + 1
	z_as_relative = false

# Anime le déplacement le long d'un chemin hex, case par case
# start_cell : case de départ (grid_pos est déjà mis à jour avant l'appel)
func move_along_path(path_cells: Array[Vector2i], start_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if path_cells.is_empty():
		return
	_switch_to_run()
	# Z-index élevé pendant le mouvement pour ne pas passer derrière les tuiles
	z_index = 999
	var current_cell = start_cell if start_cell != Vector2i(-1, -1) else grid_pos
	for cell in path_cells:
		var target_pos = _hex_grid.get_cell_world_position(cell)
		var h_from = _hex_grid.get_height_at(current_cell)
		var h_to = _hex_grid.get_height_at(cell)
		var h_diff = h_to - h_from
		if h_diff != 0:
			await _move_with_jump(target_pos, h_diff)
		else:
			var dist = position.distance_to(target_pos)
			var duration = clampf(dist / 200.0, 0.08, 0.25)
			var tween = create_tween()
			tween.tween_property(self, "position", target_pos, duration)\
				.set_trans(Tween.TRANS_LINEAR)
			await tween.finished
		current_cell = cell
	# Restaurer le z_index correct une fois arrivé
	_update_z_index()
	_switch_to_idle()

# Anime un saut parabolique entre deux cases de hauteurs différentes
func _move_with_jump(target_pos: Vector2, h_diff: int) -> void:
	var start_pos = position
	var dist = start_pos.distance_to(target_pos)
	var duration = clampf(dist / 160.0, 0.15, 0.35)
	# Arc plus haut en montée, plus léger en descente
	var arc_height: float
	if h_diff > 0:
		arc_height = 12.0 + abs(h_diff) * 10.0
	else:
		arc_height = 6.0 + abs(h_diff) * 5.0
	var elapsed = 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var pos = start_pos.lerp(target_pos, t)
		# Arc parabolique vers le haut
		pos.y -= arc_height * 4.0 * t * (1.0 - t)
		position = pos
		await get_tree().process_frame
	position = target_pos

# Fallback : déplacement direct (pour annulation)
func move_to(target_pos: Vector2) -> void:
	_switch_to_run()
	z_index = 999
	var dist = position.distance_to(target_pos)
	var duration = clampf(dist / 150.0, 0.4, 1.2)
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_update_z_index()
	_switch_to_idle()

# Applique un highlight selon l'état : "active", "stats", "acted", ou "" pour effacer
func set_highlight(state: String) -> void:
	match state:
		"active":
			body.modulate = Color(1, 1, 1, 1)
			highlight.polygon = _get_highlight_vertices(28.0)
			highlight.color = COLOR_ACTIVE
		"stats":
			body.modulate = Color(1, 1, 1, 1)
			highlight.polygon = _get_highlight_vertices(28.0)
			highlight.color = COLOR_STATS
		"acted":
			body.modulate = COLOR_ACTED_MODULATE
			highlight.polygon = PackedVector2Array()
		_:
			body.modulate = Color(1, 1, 1, 1)
			highlight.polygon = PackedVector2Array()

static func calc_damage(atk: int, target_unit: Unit, height_diff: int = 0, terrain_def_bonus: int = 0, dmg_type: int = 0) -> Dictionary:
	var attack_power = atk + max(0, height_diff)
	var defense_power = target_unit.get_effective_defense() + terrain_def_bonus + max(0, -height_diff)
	var raw_damage = attack_power - defense_power
	var multiplier = DAMAGE_MULTIPLIERS[target_unit.armor_type][dmg_type]
	var final_damage = max(1, int(raw_damage * multiplier))
	return {
		"damage": final_damage,
		"atk_power": attack_power,
		"def_power": defense_power,
		"raw": raw_damage,
		"multiplier": multiplier,
	}

func get_effective_defense() -> int:
	return defense + (1 if is_defending else 0)

# Vérifie si une position cible est dans la portée d'attaque (min/max + LOS)
func can_attack_from(from: Vector2i, target_pos: Vector2i, hex_grid: Node2D) -> bool:
	var dist = hex_grid.hex_distance(from, target_pos)
	return dist >= min_attack_range and dist <= attack_range and hex_grid.has_line_of_sight(from, target_pos)

# Génère le texte de log pour une attaque
static func get_damage_type_name(dmg_type: int) -> String:
	match dmg_type:
		UnitData.DamageType.SLASHING: return "tranchant"
		UnitData.DamageType.PIERCING: return "perçant"
		UnitData.DamageType.BLUNT: return "contondant"
		UnitData.DamageType.MAGIC: return "magique"
	return ""

static func get_armor_type_name(arm_type: int) -> String:
	match arm_type:
		UnitData.ArmorType.NONE: return "aucune"
		UnitData.ArmorType.LIGHT: return "légère"
		UnitData.ArmorType.CHAIN: return "mailles"
		UnitData.ArmorType.PLATE: return "plate"
	return ""

static func build_attack_log(attacker_name: String, target_name: String, result: Dictionary, height_diff: int, terrain_def: int, dmg_type: int = -1, armor_type: int = -1) -> String:
	var text = attacker_name + " attaque " + target_name + " → -" + str(result.damage) + " HP"
	# Ligne de détail du calcul
	var detail = "  ATK " + str(result.atk_power)
	if height_diff > 0:
		detail += " (+" + str(height_diff) + " hauteur)"
	detail += " vs DEF " + str(result.def_power)
	if height_diff < 0:
		detail += " (+" + str(-height_diff) + " hauteur)"
	if terrain_def > 0:
		detail += " (+" + str(terrain_def) + " terrain)"
	detail += " = " + str(result.raw)
	if dmg_type >= 0 and armor_type >= 0:
		var mult = result.multiplier
		detail += " × " + str(mult)
		detail += " (" + get_damage_type_name(dmg_type) + " vs " + get_armor_type_name(armor_type) + ")"
	detail += " = " + str(result.damage)
	return text + "\n" + detail

func activate_defend() -> void:
	is_defending = true
	if _guard_texture:
		_switch_sprite(_guard_texture, _guard_hframes)

# Réinitialise l'état de l'unité pour un nouveau round
func reset_for_new_round() -> void:
	has_acted = false
	has_moved = false
	if is_defending:
		is_defending = false
		_switch_to_idle()
	shield_label.visible = false
	body.modulate = Color(1, 1, 1, 1)
	set_highlight("")

func _get_highlight_vertices(size: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(16):
		var angle = deg_to_rad(360.0 / 16 * i)
		pts.append(Vector2(size * cos(angle), size * sin(angle) * iso_y_scale))
	return pts
