# Unit3D.gd
# Représente une unité sur la grille 3D (joueur ou ennemi).
# Sprite3D billboard, animations, combat.
class_name Unit3D
extends Node3D

# --- Constantes couleur ---
const COLOR_ACTIVE = Color(1.0, 0.9, 0.1, 0.85)
const COLOR_STATS = Color(0.2, 0.9, 0.9, 0.6)
const COLOR_ACTED_MODULATE = Color(0.6, 0.6, 0.6, 1.0)

# --- Stats ---
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
var spells: Array[SpellData] = []

# --- État en jeu ---
var grid_pos: Vector2i = Vector2i(0, 0)
var has_acted: bool = false
var has_moved: bool = false
var is_defending: bool = false
var _hex_grid: Node3D = null

# Direction logique (mise à jour au move/attack)
var facing_world_dir: Vector3 = Vector3(1, 0, 0)

# --- Références aux nœuds enfants ---
@onready var body: Sprite3D = $Body
@onready var highlight_mesh: MeshInstance3D = $HighlightMesh
@onready var name_label: Label3D = $NameLabel

# --- Référence caméra (pour le flip billboard) ---
var _camera_pivot: Node3D = null

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
var _base_flip_h: bool = false
var _sprite_scale_factor: float = 1.0
const FRAME_DURATION: float = 0.12
const ATTACK_FRAME_DURATION: float = 0.10

# Animation one-shot
var _playing_oneshot: bool = false
var _oneshot_frame_duration: float = ATTACK_FRAME_DURATION

# Taille du sprite en unités 3D
const SPRITE_TARGET_SIZE: float = 2

func setup(data: UnitData, p_grid_pos: Vector2i, hex_grid: Node3D, p_team: String = "player", overrides: Dictionary = {}) -> void:
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
	if team == "enemy" and data.enemy_avatar_texture:
		avatar_texture = data.enemy_avatar_texture
	grid_pos = p_grid_pos
	_hex_grid = hex_grid
	position = hex_grid.get_cell_world_position(p_grid_pos)

	# Stocker les textures
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
	spells = data.spells.duplicate()

	_apply_overrides(overrides)
	if team == "enemy":
		_remap_sprites_for_team()
	_base_flip_h = team == "enemy"
	_setup_body()
	_setup_highlight()
	_setup_label()
	if _idle_texture:
		_start_idle_animation()

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
			"spells":
				spells.clear()
				for spell_name in overrides[key]:
					var spell = load("res://data/spells/" + spell_name + ".tres")
					if spell:
						spells.append(spell)

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
		var new_path = path.replace("Blue Units", "Black Units")
		var remapped = load(new_path)
		if remapped:
			return remapped
	return tex

func _setup_body() -> void:
	if body == null:
		return
	body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body.transparent = true
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	if _idle_texture:
		body.texture = _idle_texture
		_frame_count = _idle_hframes
		body.hframes = _frame_count
		body.frame = 0
		var tex_size = _idle_texture.get_size()
		var frame_width = tex_size.x / _frame_count
		var frame_height = tex_size.y
		var ps = SPRITE_TARGET_SIZE / max(frame_width, frame_height) * _sprite_scale_factor
		body.pixel_size = ps
		body.flip_h = _base_flip_h
		# centered=true, on positionne le sprite pour que les pieds
		# soient au niveau du sol hex. Factor 0.35 au lieu de 0.5
		# pour compenser le padding transparent sous les pieds.
		body.centered = true
		var base_height = frame_height * (SPRITE_TARGET_SIZE / max(frame_width, frame_height))
		body.position = Vector3(0, base_height * 0.20, 0)

func _setup_highlight() -> void:
	if highlight_mesh == null:
		return
	highlight_mesh.mesh = null  # Pas de highlight par défaut

func _setup_label() -> void:
	if name_label == null:
		return
	name_label.text = ""
	name_label.visible = false
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 32
	name_label.pixel_size = 0.01
	name_label.position.y = SPRITE_TARGET_SIZE + 0.2
	name_label.no_depth_test = true

func _start_idle_animation() -> void:
	_frame_timer = randf_range(0.0, FRAME_DURATION * _frame_count)
	_current_frame = randi_range(0, _frame_count - 1)
	body.frame = _current_frame

func _switch_sprite(texture: Texture2D, hframes: int) -> void:
	if texture == null or body == null:
		return
	body.texture = texture
	body.hframes = hframes
	_frame_count = hframes
	_current_frame = 0
	_frame_timer = 0.0
	body.frame = 0
	var tex_size = texture.get_size()
	var frame_width = tex_size.x / hframes
	var frame_height = tex_size.y
	var ps = SPRITE_TARGET_SIZE / max(frame_width, frame_height) * _sprite_scale_factor
	body.pixel_size = ps
	body.centered = true
	var base_height = frame_height * (SPRITE_TARGET_SIZE / max(frame_width, frame_height))
	body.position = Vector3(0, base_height * 0.20, 0)

func _switch_to_idle() -> void:
	_playing_oneshot = false
	_switch_sprite(_idle_texture, _idle_hframes)

func _switch_to_run() -> void:
	if _run_texture:
		_switch_sprite(_run_texture, _run_hframes)

func _process(delta: float) -> void:
	# Animation frames
	if _frame_count > 1 and body != null:
		var duration = _oneshot_frame_duration if _playing_oneshot else FRAME_DURATION
		_frame_timer += delta
		if _frame_timer >= duration:
			_frame_timer -= duration
			_current_frame = (_current_frame + 1) % _frame_count
			body.frame = _current_frame

	# Billboard : le sprite regarde toujours la caméra
	_update_sprite_facing()

func _update_sprite_facing() -> void:
	if body == null or _camera_pivot == null:
		return
	var camera = _camera_pivot.get_node_or_null("CameraArm/Camera3D") as Camera3D
	if camera == null:
		return
	# Flip basé sur la direction logique vs la droite de la caméra
	var cam_right = camera.global_transform.basis.x
	cam_right.y = 0
	if cam_right.length_squared() < 0.001:
		return
	cam_right = cam_right.normalized()
	var dot = cam_right.dot(facing_world_dir)
	if _base_flip_h:
		body.flip_h = dot >= 0
	else:
		body.flip_h = dot < 0

# --- Combat ---

func play_attack_anim(target_pos: Vector3 = Vector3.ZERO) -> void:
	# Orienter vers la cible
	if target_pos != Vector3.ZERO:
		var dir = target_pos - position
		dir.y = 0
		if dir.length_squared() > 0.001:
			facing_world_dir = dir.normalized()

	if _attack_texture == null:
		var tween = create_tween()
		var base_y = body.position.y
		tween.tween_property(body, "position:y", base_y + 0.1, 0.08)
		tween.tween_property(body, "position:y", base_y, 0.08)
		await tween.finished
		return
	_switch_sprite(_attack_texture, _attack_hframes)
	_playing_oneshot = true
	_oneshot_frame_duration = ATTACK_FRAME_DURATION
	var anim_duration = ATTACK_FRAME_DURATION * _attack_hframes
	# Projectile à mi-animation
	if _projectile_texture and target_pos != Vector3.ZERO:
		get_tree().create_timer(anim_duration * 0.4).timeout.connect(
			func(): _fire_projectile_3d(target_pos), CONNECT_ONE_SHOT
		)
	await get_tree().create_timer(anim_duration).timeout
	_switch_to_idle()

func play_cast_anim() -> void:
	if _cast_texture == null:
		var tween = create_tween()
		var base_y = body.position.y
		tween.tween_property(body, "position:y", base_y + 0.15, 0.1)
		tween.tween_property(body, "position:y", base_y, 0.1)
		await tween.finished
		return
	_switch_sprite(_cast_texture, _cast_hframes)
	_playing_oneshot = true
	_oneshot_frame_duration = ATTACK_FRAME_DURATION
	var anim_duration = ATTACK_FRAME_DURATION * _cast_hframes
	await get_tree().create_timer(anim_duration).timeout
	_switch_to_idle()

func heal(amount: int) -> void:
	hp = min(hp + amount, max_hp)
	_spawn_floating_text("+" + str(amount), Color(0.2, 0.9, 0.2))
	# Flash vert
	body.modulate = Color(0.5, 2.0, 0.5, 1.0)
	var tween = create_tween()
	tween.tween_property(body, "modulate", Color(1, 1, 1, 1), 0.3)
	await tween.finished

func take_damage(amount: int) -> void:
	hp -= amount
	_spawn_floating_text("-" + str(amount), Color(1.0, 0.2, 0.2))
	# Flash + shake
	body.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var base_pos = body.position
	var tween = create_tween()
	tween.tween_property(body, "position:x", base_pos.x + 0.1, 0.03)
	tween.tween_property(body, "position:x", base_pos.x - 0.1, 0.03)
	tween.tween_property(body, "position:x", base_pos.x + 0.08, 0.03)
	tween.tween_property(body, "position:x", base_pos.x - 0.06, 0.03)
	tween.tween_property(body, "position:x", base_pos.x, 0.03)
	tween.parallel().tween_property(body, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.05)
	tween.tween_property(body, "modulate", Color(1, 1, 1, 1), 0.2)
	await tween.finished
	if hp <= 0:
		queue_free()

func _spawn_floating_text(text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.position = Vector3(0, SPRITE_TARGET_SIZE + 0.2, 0)
	add_child(label)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(label.queue_free)

func _fire_projectile_3d(target_pos: Vector3) -> void:
	var projectile = Sprite3D.new()
	projectile.texture = _projectile_texture
	projectile.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	projectile.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	projectile.pixel_size = 0.015
	var start = position + Vector3(0, 0.8, 0)
	var target = target_pos + Vector3(0, 0.8, 0)
	projectile.position = start
	get_parent().get_parent().add_child(projectile)
	var dist = start.distance_to(target)
	var arc_height = clampf(dist * 0.4, 0.8, 2.5)
	var duration = clampf(dist / 6.0, 0.3, 0.7)
	var elapsed = 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var pos = start.lerp(target, t)
		pos.y += arc_height * 4.0 * t * (1.0 - t)
		projectile.position = pos
		await get_tree().process_frame
	projectile.queue_free()

# --- Mouvement ---

func move_along_path(path_cells: Array[Vector2i], start_cell: Vector2i = Vector2i(-1, -1)) -> void:
	if path_cells.is_empty():
		return
	_switch_to_run()
	var current_cell = start_cell if start_cell != Vector2i(-1, -1) else grid_pos
	for cell in path_cells:
		var target_pos = _hex_grid.get_cell_world_position(cell)
		# Orienter dans la direction du mouvement
		var dir = target_pos - position
		dir.y = 0
		if dir.length_squared() > 0.001:
			facing_world_dir = dir.normalized()
		var h_from = _hex_grid.get_height_at(current_cell)
		var h_to = _hex_grid.get_height_at(cell)
		var h_diff = h_to - h_from
		if h_diff != 0:
			await _move_with_jump(target_pos, h_diff)
		else:
			var dist = position.distance_to(target_pos)
			var duration = clampf(dist / 4.0, 0.08, 0.25)
			var tween = create_tween()
			tween.tween_property(self, "position", target_pos, duration)\
				.set_trans(Tween.TRANS_LINEAR)
			await tween.finished
		current_cell = cell
	_switch_to_idle()

func _move_with_jump(target_pos: Vector3, h_diff: int) -> void:
	var start_pos = position
	var dist = start_pos.distance_to(target_pos)
	var duration = clampf(dist / 3.0, 0.15, 0.35)
	var arc_height: float
	if h_diff > 0:
		arc_height = 0.3 + abs(h_diff) * 0.25
	else:
		arc_height = 0.15 + abs(h_diff) * 0.12
	var elapsed = 0.0
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t = clampf(elapsed / duration, 0.0, 1.0)
		var pos = start_pos.lerp(target_pos, t)
		pos.y += arc_height * 4.0 * t * (1.0 - t)
		position = pos
		await get_tree().process_frame
	position = target_pos

func move_to(target_pos: Vector3) -> void:
	_switch_to_run()
	var dir = target_pos - position
	dir.y = 0
	if dir.length_squared() > 0.001:
		facing_world_dir = dir.normalized()
	var dist = position.distance_to(target_pos)
	var duration = clampf(dist / 3.0, 0.4, 1.2)
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_switch_to_idle()

# --- Highlight ---

func set_highlight(state: String) -> void:
	match state:
		"active":
			body.modulate = Color(1, 1, 1, 1)
			_set_highlight_ring(COLOR_ACTIVE)
		"stats":
			body.modulate = Color(1, 1, 1, 1)
			_set_highlight_ring(COLOR_STATS)
		"acted":
			body.modulate = COLOR_ACTED_MODULATE
			_clear_highlight_ring()
		_:
			body.modulate = Color(1, 1, 1, 1)
			_clear_highlight_ring()

func _set_highlight_ring(color: Color) -> void:
	if highlight_mesh == null:
		return
	highlight_mesh.mesh = HexMeshBuilder.build_hex_ring(0.4, 0.55, 0.02, color)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	highlight_mesh.material_override = mat

func _clear_highlight_ring() -> void:
	if highlight_mesh == null:
		return
	highlight_mesh.mesh = null

# --- Combat helpers (copiés de unit.gd) ---

static func calc_damage(atk: int, target_unit: Unit3D, height_diff: int = 0, terrain_def_bonus: int = 0) -> int:
	var attack_power = atk + max(0, height_diff)
	var defense_power = target_unit.get_effective_defense() + terrain_def_bonus + max(0, -height_diff)
	return max(1, attack_power - defense_power)

func get_effective_defense() -> int:
	return defense + (1 if is_defending else 0)

func can_attack_from(from: Vector2i, target_pos: Vector2i, hex_grid: Node3D) -> bool:
	var dist = hex_grid.hex_distance(from, target_pos)
	return dist >= min_attack_range and dist <= attack_range and hex_grid.has_line_of_sight(from, target_pos)

func can_cast_spell_on(spell: SpellData, from: Vector2i, target_pos: Vector2i, p_hex_grid: Node3D) -> bool:
	var dist = p_hex_grid.hex_distance(from, target_pos)
	if dist < spell.min_spell_range or dist > spell.spell_range:
		return false
	if spell.needs_los and not p_hex_grid.has_line_of_sight(from, target_pos):
		return false
	return true

static func build_attack_log(attacker_name: String, target_name: String, damage: int, height_diff: int, terrain_def: int) -> String:
	var text = attacker_name + " attaque " + target_name + " (-" + str(damage) + " HP)"
	if height_diff > 0:
		text += " [hauteur +" + str(height_diff) + " ATK]"
	elif height_diff < 0:
		text += " [hauteur +" + str(-height_diff) + " DEF]"
	if terrain_def > 0:
		text += " [terrain +" + str(terrain_def) + " DEF]"
	return text

func activate_defend() -> void:
	is_defending = true
	if _guard_texture:
		_switch_sprite(_guard_texture, _guard_hframes)

func reset_for_new_round() -> void:
	has_acted = false
	has_moved = false
	if is_defending:
		is_defending = false
		_switch_to_idle()
	body.modulate = Color(1, 1, 1, 1)
	set_highlight("")
