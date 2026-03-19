# HexGrid3D.gd
# Grille hexagonale 3D (flat-top, offset odd-q).
# Remplace hex_grid.gd : même math hex, rendu avec MeshInstance3D.
extends Node3D

# --- Configuration ---
const HEX_SIZE: float = 1.0         # Rayon d'un hexagone en unités 3D
const ELEVATION_UNIT: float = 0.5   # Unités 3D par niveau de hauteur
const GRID_WIDTH: int = 10
const GRID_HEIGHT: int = 8

const HIGHLIGHT_MOVE = Color(0.55, 1.0, 0.4)
const HIGHLIGHT_ATTACK = Color(1.0, 0.35, 0.35)
const HIGHLIGHT_INSPECT_ATTACK = Color(1.0, 0.6, 0.3)

# --- Terrain ---
enum Terrain { PLAINS, FOREST, HILL, MOUNTAIN, WATER }

const TERRAIN_INFO = {
	Terrain.PLAINS:   { "name": "Plaine",   "color": Color(0.55, 0.65, 0.45),  "height": 1, "def_bonus": 0, "passable": true,  "blocks_los": false },
	Terrain.FOREST:   { "name": "Forêt",    "color": Color(0.4, 0.52, 0.35),   "height": 1, "def_bonus": 1, "passable": false, "blocks_los": true  },
	Terrain.HILL:     { "name": "Colline",  "color": Color(0.6, 0.55, 0.4),    "height": 2, "def_bonus": 1, "passable": true,  "blocks_los": false },
	Terrain.MOUNTAIN: { "name": "Montagne", "color": Color(0.52, 0.52, 0.52),  "height": 5, "def_bonus": 0, "passable": false, "blocks_los": true  },
	Terrain.WATER:    { "name": "Eau",      "color": Color(0.3, 0.45, 0.6),    "height": 0, "def_bonus": 0, "passable": false, "blocks_los": false },
}

const TERRAIN_CHAR = {
	"P": Terrain.PLAINS, "F": Terrain.FOREST, "H": Terrain.HILL,
	"M": Terrain.MOUNTAIN, "W": Terrain.WATER,
}

# --- Données internes ---
var terrain_map: Dictionary = {}        # Vector2i → Terrain
var forest_map: Dictionary = {}         # Vector2i → true
var grid_width: int = GRID_WIDTH
var grid_height: int = GRID_HEIGHT

# Rendu 3D
var _cell_meshes: Dictionary = {}       # Vector2i → MeshInstance3D (hex prism)
var _cell_materials: Dictionary = {}    # Vector2i → StandardMaterial3D (top surface)
var _cell_base_color: Dictionary = {}   # Vector2i → Color (pour restaurer après highlight)
var _cell_bodies: Dictionary = {}       # Vector2i → StaticBody3D (picking)
var _cross_markers: Array[Node3D] = []
var _decoration_nodes: Array[Node3D] = []

# Textures terrain
var _terrain_tex: Dictionary = {}
var _tree_textures: Array[Texture2D] = []
var _rock_textures: Array[Texture2D] = []
var _bush_textures: Array[Texture2D] = []

# Collision layer pour le picking hex
const HEX_COLLISION_LAYER: int = 1

# --- Chargement terrain ---

func _init_terrain_textures() -> void:
	var tilemap1 = load("res://assets/Tiny Swords/Terrain/Tileset/Tilemap_color1.png") as Texture2D
	var tilemap5 = load("res://assets/Tiny Swords/Terrain/Tileset/Tilemap_color5.png") as Texture2D
	var water_tex = load("res://assets/Tiny Swords/Terrain/Tileset/Water Background color.png") as Texture2D
	_terrain_tex[Terrain.PLAINS] = _extract_tile_region(tilemap1)
	_terrain_tex[Terrain.HILL] = _extract_tile_region(tilemap1)
	_terrain_tex[Terrain.FOREST] = _extract_tile_region(tilemap5)
	_terrain_tex[Terrain.MOUNTAIN] = _extract_tile_region(tilemap5)
	_terrain_tex[Terrain.WATER] = water_tex
	for i in range(1, 5):
		_tree_textures.append(load("res://assets/Tiny Swords/Terrain/Resources/Wood/Trees/Tree%d.png" % i))
		_rock_textures.append(load("res://assets/Tiny Swords/Terrain/Decorations/Rocks/Rock%d.png" % i))
		_bush_textures.append(load("res://assets/Tiny Swords/Terrain/Decorations/Bushes/Bushe%d.png" % i))

func _extract_tile_region(tilemap_tex: Texture2D) -> ImageTexture:
	var img = tilemap_tex.get_image()
	var region = Rect2i(80, 44, 64, 64)
	var cropped = img.get_region(region)
	return ImageTexture.create_from_image(cropped)

func load_terrain(terrain_rows: Array, width: int, height: int, forest_rows: Array = []) -> void:
	grid_width = width
	grid_height = height
	terrain_map.clear()
	forest_map.clear()
	_cell_base_color.clear()
	for r in range(grid_height):
		var row: String = terrain_rows[r]
		for q in range(grid_width):
			var ch = row[q]
			if ch == "F":
				terrain_map[Vector2i(q, r)] = Terrain.PLAINS
				forest_map[Vector2i(q, r)] = true
			else:
				terrain_map[Vector2i(q, r)] = TERRAIN_CHAR[ch]
	for r in range(mini(forest_rows.size(), grid_height)):
		var row: String = forest_rows[r]
		for q in range(mini(row.length(), grid_width)):
			if row[q] == "F":
				forest_map[Vector2i(q, r)] = true
	if _terrain_tex.is_empty():
		_init_terrain_textures()
	# Supprimer l'ancienne grille
	for child in get_children():
		child.queue_free()
	_cell_meshes.clear()
	_cell_materials.clear()
	_cell_bodies.clear()
	_cross_markers.clear()
	_decoration_nodes.clear()
	await get_tree().process_frame
	_generate_grid()

func _generate_grid() -> void:
	for r in range(grid_height):
		for q in range(grid_width):
			_create_hex_cell_3d(q, r)
	# Centrer la grille
	var center = _get_grid_center()
	position = -center

func _get_grid_center() -> Vector3:
	var sum = Vector3.ZERO
	var count = 0
	for cell in terrain_map:
		sum += hex_to_world_local(cell.x, cell.y)
		count += 1
	if count > 0:
		sum /= count
	sum.y = 0
	return sum

# --- Création des cellules 3D ---

func _create_hex_cell_3d(q: int, r: int) -> void:
	var cell = Vector2i(q, r)
	var terrain = terrain_map.get(cell, Terrain.PLAINS)
	var info = TERRAIN_INFO[terrain]
	var h: int = info["height"]
	var top_y = h * ELEVATION_UNIT
	var base_y = -1 * ELEVATION_UNIT  # Base sous le sol

	# Couleur de la surface
	var is_forest = forest_map.has(cell)
	var surface_terrain = Terrain.FOREST if is_forest else terrain
	var surface_info = TERRAIN_INFO[surface_terrain]
	var top_color = surface_info["color"]
	var wall_color = info["color"]

	# Position XZ
	var world_pos = hex_to_world_local(q, r)
	world_pos.y = 0  # Le prisme gère sa propre hauteur

	# Construire le mesh
	var prism_mesh = HexMeshBuilder.build_hex_prism(HEX_SIZE, top_y, base_y, top_color, wall_color)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = prism_mesh
	mesh_instance.position = Vector3(world_pos.x, 0, world_pos.z)
	mesh_instance.name = "Hex_%d_%d" % [q, r]

	# Material pour la surface top (surface 0) — permet le highlight
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = top_color
	var tex = _terrain_tex.get(surface_terrain)
	if tex:
		mat.albedo_texture = tex
	mesh_instance.set_surface_override_material(0, mat)
	_cell_materials[cell] = mat
	_cell_base_color[cell] = top_color

	# Material pour le contour hex (surface 1) — lignes unshaded
	var outline_mat = StandardMaterial3D.new()
	outline_mat.vertex_color_use_as_albedo = true
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.set_surface_override_material(1, outline_mat)

	# Materials pour les murs (surfaces 2+) — vertex color
	for si in range(2, prism_mesh.get_surface_count()):
		var wall_mat = StandardMaterial3D.new()
		wall_mat.vertex_color_use_as_albedo = true
		mesh_instance.set_surface_override_material(si, wall_mat)

	add_child(mesh_instance)
	_cell_meshes[cell] = mesh_instance

	# Collision pour le picking (sur la surface top uniquement)
	var body = StaticBody3D.new()
	body.collision_layer = HEX_COLLISION_LAYER
	body.collision_mask = 0
	body.set_meta("hex_cell", cell)

	# Collision shape : box couvrant l'hexagone
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(HEX_SIZE * 1.8, ELEVATION_UNIT * 0.5, HEX_SIZE * 1.6)
	col_shape.shape = box
	col_shape.position = Vector3(0, top_y - ELEVATION_UNIT * 0.25, 0)
	body.add_child(col_shape)
	body.position = Vector3(world_pos.x, 0, world_pos.z)
	add_child(body)
	_cell_bodies[cell] = body

	# Décorations
	if forest_map.has(cell):
		_add_decoration_3d(cell, Terrain.FOREST, Vector3(world_pos.x, top_y, world_pos.z))
	else:
		_add_decoration_3d(cell, terrain, Vector3(world_pos.x, top_y, world_pos.z))

# --- Décorations 3D (Sprite3D billboard) ---

func _add_decoration_3d(cell: Vector2i, terrain: Terrain, pos: Vector3) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = cell.x * 73856093 + cell.y * 19349663

	match terrain:
		Terrain.FOREST:
			if _tree_textures.is_empty():
				return
			var tree_count = rng.randi_range(3, 4)
			for i in range(tree_count):
				var tree = _create_billboard_sprite(_tree_textures[rng.randi_range(0, _tree_textures.size() - 1)], rng.randi_range(0, 7), 8)
				var target_h = rng.randf_range(1.2, 1.8)
				tree.pixel_size = target_h / tree.texture.get_height()
				var ox = rng.randf_range(-0.7, 0.7)
				var oz = rng.randf_range(-0.5, 0.5)
				tree.position = pos + Vector3(ox, target_h * 0.5, oz)
				add_child(tree)
				_decoration_nodes.append(tree)
			# Buissons
			var bush_count = rng.randi_range(2, 3)
			for i in range(bush_count):
				if _bush_textures.is_empty():
					break
				var bush = _create_billboard_sprite(_bush_textures[rng.randi_range(0, _bush_textures.size() - 1)], rng.randi_range(0, 7), 8)
				var target_h = rng.randf_range(0.4, 0.7)
				bush.pixel_size = target_h / bush.texture.get_height()
				var ox = rng.randf_range(-0.6, 0.6)
				var oz = rng.randf_range(-0.4, 0.4)
				bush.position = pos + Vector3(ox, target_h * 0.3, oz)
				add_child(bush)
				_decoration_nodes.append(bush)
			# Petits arbres
			var small_count = rng.randi_range(1, 2)
			for i in range(small_count):
				var tree = _create_billboard_sprite(_tree_textures[rng.randi_range(0, _tree_textures.size() - 1)], rng.randi_range(0, 7), 8)
				var target_h = rng.randf_range(0.7, 1.0)
				tree.pixel_size = target_h / tree.texture.get_height()
				var ox = rng.randf_range(-0.6, 0.6)
				var oz = rng.randf_range(-0.4, 0.4)
				tree.position = pos + Vector3(ox, target_h * 0.5, oz)
				add_child(tree)
				_decoration_nodes.append(tree)
		Terrain.MOUNTAIN:
			if _rock_textures.is_empty():
				return
			for i in range(rng.randi_range(2, 3)):
				var rock = Sprite3D.new()
				rock.texture = _rock_textures[rng.randi_range(0, _rock_textures.size() - 1)]
				rock.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				rock.pixel_size = rng.randf_range(0.008, 0.012)
				var ox = rng.randf_range(-0.3, 0.3)
				var oz = rng.randf_range(-0.2, 0.2)
				rock.position = pos + Vector3(ox, 0.15, oz)
				add_child(rock)
				_decoration_nodes.append(rock)
		Terrain.HILL:
			if _bush_textures.is_empty():
				return
			if rng.randf() > 0.5:
				return
			var bush = _create_billboard_sprite(_bush_textures[rng.randi_range(0, _bush_textures.size() - 1)], rng.randi_range(0, 7), 8)
			var target_h = 0.6
			bush.pixel_size = target_h / bush.texture.get_height()
			bush.position = pos + Vector3(rng.randf_range(-0.15, 0.15), target_h * 0.3, rng.randf_range(-0.1, 0.1))
			add_child(bush)
			_decoration_nodes.append(bush)

func _create_billboard_sprite(tex: Texture2D, frame_idx: int, hframes: int) -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.texture = tex
	sprite.hframes = hframes
	sprite.frame = frame_idx
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	return sprite

# --- Conversions de coordonnées ---

# Hex (q,r) → position monde locale (sans le offset de centrage)
func hex_to_world_local(q: int, r: int) -> Vector3:
	var x = HEX_SIZE * 1.5 * q
	var z = HEX_SIZE * sqrt(3.0) * (r + 0.5 * (q % 2))
	var y = get_height_at(Vector2i(q, r)) * ELEVATION_UNIT
	return Vector3(x, y, z)

# Position monde globale d'une case (incluant le offset de la grille)
func get_cell_world_position(cell: Vector2i) -> Vector3:
	return hex_to_world_local(cell.x, cell.y) + position

# Convertit une position monde globale en coordonnées hex
# Utilise un raycast depuis le dessus pour trouver le bon hex
func world_to_hex(world_pos: Vector3) -> Vector2i:
	var local_pos = world_pos - position
	# Méthode algébrique : trouver le hex le plus proche pour chaque hauteur possible
	var best_cell = Vector2i(-1, -1)
	var best_dist = INF
	var heights_seen = {}
	for cell in terrain_map:
		var h = TERRAIN_INFO[terrain_map[cell]]["height"]
		heights_seen[h] = true
	for h in heights_seen:
		var test_y = h * ELEVATION_UNIT
		# Ignorer si trop loin en Y
		if abs(local_pos.y - test_y) > ELEVATION_UNIT * 3:
			continue
		var test_pos = Vector2(local_pos.x, local_pos.z)
		# Pixel → axial (flat-top)
		var fq = (2.0 / 3.0 * test_pos.x) / HEX_SIZE
		var fr = (-1.0 / 3.0 * test_pos.x + sqrt(3.0) / 3.0 * test_pos.y) / HEX_SIZE
		var cell = _axial_round(fq, fr)
		if is_valid_cell(cell) and get_height_at(cell) == h:
			var center = hex_to_world_local(cell.x, cell.y)
			var dist = Vector2(local_pos.x - center.x, local_pos.z - center.z).length()
			if dist < best_dist:
				best_dist = dist
				best_cell = cell
	if best_cell == Vector2i(-1, -1):
		# Fallback sans filtre de hauteur
		var fq = (2.0 / 3.0 * local_pos.x) / HEX_SIZE
		var fr = (-1.0 / 3.0 * local_pos.x + sqrt(3.0) / 3.0 * local_pos.z) / HEX_SIZE
		best_cell = _axial_round(fq, fr)
	return best_cell

func _axial_round(fq: float, fr: float) -> Vector2i:
	var fs = -fq - fr
	var rq = int(round(fq))
	var rr = int(round(fr))
	var rs = int(round(fs))
	var dq = abs(rq - fq)
	var dr = abs(rr - fr)
	var ds = abs(rs - fs)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	# Axial → offset odd-q
	var q = rq
	var r = rr + (rq - (rq & 1)) / 2
	return Vector2i(q, r)

func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

# --- Terrain accesseurs (copiés de hex_grid.gd) ---

func get_terrain_at(cell: Vector2i) -> Terrain:
	return terrain_map.get(cell, Terrain.PLAINS)

func get_height_at(cell: Vector2i) -> int:
	return TERRAIN_INFO[get_terrain_at(cell)]["height"]

# Alias pour compatibilité (hex_grid.gd utilisait get_height)
func get_height(cell: Vector2i) -> int:
	return get_height_at(cell)

func has_forest(cell: Vector2i) -> bool:
	return forest_map.has(cell)

func get_terrain_def_bonus(cell: Vector2i) -> int:
	var bonus = TERRAIN_INFO[get_terrain_at(cell)]["def_bonus"]
	if has_forest(cell):
		bonus = maxi(bonus, 1)
	return bonus

func get_terrain_name(cell: Vector2i) -> String:
	var base_name = TERRAIN_INFO[get_terrain_at(cell)]["name"]
	if has_forest(cell):
		return "Forêt (" + base_name + ")"
	return base_name

func is_passable(cell: Vector2i) -> bool:
	if has_forest(cell):
		return false
	return TERRAIN_INFO[get_terrain_at(cell)]["passable"]

func blocks_los(cell: Vector2i) -> bool:
	if has_forest(cell):
		return true
	return TERRAIN_INFO[get_terrain_at(cell)]["blocks_los"]

# --- Distance et voisins (copiés de hex_grid.gd) ---

func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _offset_to_cube(a)
	var bc = _offset_to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)

func _offset_to_cube(cell: Vector2i) -> Vector3i:
	var x = cell.x
	var z = cell.y - int((cell.x - (cell.x & 1)) / 2)
	var y = -x - z
	return Vector3i(x, y, z)

func _cube_to_offset(cube: Vector3i) -> Vector2i:
	var q = cube.x
	var r = cube.z + int((cube.x - (cube.x & 1)) / 2)
	return Vector2i(q, r)

func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var q = cell.x
	var r = cell.y
	var parity = q & 1
	var result: Array[Vector2i] = []
	var dirs = [
		[Vector2i(+1, -1), Vector2i(+1,  0)],
		[Vector2i(+1,  0), Vector2i(+1, +1)],
		[Vector2i( 0, +1), Vector2i( 0, +1)],
		[Vector2i(-1,  0), Vector2i(-1, +1)],
		[Vector2i(-1, -1), Vector2i(-1,  0)],
		[Vector2i( 0, -1), Vector2i( 0, -1)],
	]
	for dir in dirs:
		var d: Vector2i = dir[parity]
		var neighbor = Vector2i(q + d.x, r + d.y)
		if is_valid_cell(neighbor):
			result.append(neighbor)
	return result

# --- Ligne de vue (copiée de hex_grid.gd) ---

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var dist = hex_distance(from, to)
	if dist <= 1:
		return true
	var ac = _offset_to_cube(from)
	var bc = _offset_to_cube(to)
	for i in range(1, dist):
		var t = float(i) / float(dist)
		var fx = ac.x + (bc.x - ac.x) * t + 1e-6
		var fy = ac.y + (bc.y - ac.y) * t + 1e-6
		var fz = ac.z + (bc.z - ac.z) * t - 2e-6
		var rx = round(fx)
		var ry = round(fy)
		var rz = round(fz)
		var dx = abs(rx - fx)
		var dy = abs(ry - fy)
		var dz = abs(rz - fz)
		if dx > dy and dx > dz:
			rx = -ry - rz
		elif dy > dz:
			ry = -rx - rz
		else:
			rz = -rx - ry
		var cq = int(rx)
		var cr = int(rz) + int((int(rx) - (int(rx) & 1)) / 2)
		var cell = Vector2i(cq, cr)
		if is_valid_cell(cell) and blocks_los(cell):
			return false
	return true

# --- Pathfinding (copié de hex_grid.gd) ---

func get_cells_in_range(origin: Vector2i, radius: int, blocked: Dictionary = {}, passable_only: bool = true) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(grid_width):
		for r in range(grid_height):
			var cell = Vector2i(q, r)
			if cell == origin or blocked.has(cell):
				continue
			if passable_only and not is_passable(cell):
				continue
			if hex_distance(origin, cell) <= radius:
				result.append(cell)
	return result

func get_reachable_cells(origin: Vector2i, radius: int, blocked: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {origin: 0}
	var queue: Array = [origin]
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_dist: int = visited[current]
		if current_dist >= radius:
			continue
		for neighbor in get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not is_passable(neighbor) or blocked.has(neighbor):
				continue
			visited[neighbor] = current_dist + 1
			queue.append(neighbor)
			result.append(neighbor)
	return result

func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, max_range: int = 99) -> Array[Vector2i]:
	if from == to:
		return []
	var open: Array = []
	open.append([hex_distance(from, to), from])
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0}
	while not open.is_empty():
		var best_idx = 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var current: Vector2i = open[best_idx][1]
		open.remove_at(best_idx)
		if current == to:
			var path: Array[Vector2i] = []
			var node = to
			while node != from:
				path.push_front(node)
				node = came_from[node]
			return path
		for neighbor in get_neighbors(current):
			if not is_passable(neighbor):
				continue
			if blocked.has(neighbor) and neighbor != to:
				continue
			var tentative_g = g_score[current] + 1
			if tentative_g > max_range:
				continue
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				came_from[neighbor] = current
				var f = tentative_g + hex_distance(neighbor, to)
				open.append([f, neighbor])
	return []

# --- Highlight 3D ---

# Change la couleur de la surface top d'un hex
func set_cell_color(cell: Vector2i, color: Color) -> void:
	if not _cell_materials.has(cell):
		return
	var mat: StandardMaterial3D = _cell_materials[cell]
	# Modifier l'albedo_color (multipliée avec la texture)
	mat.albedo_color = color

func highlight_cells(origin: Vector2i, move_range: int, blocked_cells: Dictionary = {}) -> void:
	clear_highlights()
	var reachable = get_reachable_cells(origin, move_range, blocked_cells)
	var reachable_set: Dictionary = {}
	for cell in reachable:
		reachable_set[cell] = true
		set_cell_color(cell, HIGHLIGHT_MOVE)
	for q in range(grid_width):
		for r in range(grid_height):
			var cell = Vector2i(q, r)
			if cell == origin or reachable_set.has(cell):
				continue
			if hex_distance(origin, cell) <= move_range:
				if not is_passable(cell) or blocked_cells.has(cell):
					_create_cross_marker_3d(cell)

func clear_highlights() -> void:
	for cell: Vector2i in _cell_materials:
		_cell_materials[cell].albedo_color = _cell_base_color.get(cell, Color.WHITE)
	for marker in _cross_markers:
		marker.queue_free()
	_cross_markers.clear()

func _create_cross_marker_3d(cell: Vector2i) -> void:
	var pos = hex_to_world_local(cell.x, cell.y) + Vector3(0, 0.05, 0)
	var size = 0.15
	# Deux lignes croisées utilisant des MeshInstance3D (ImmediateMesh)
	var marker = Node3D.new()
	marker.position = pos
	for angle_offset in [0.0, PI / 2.0]:
		var line_mesh = ImmediateMesh.new()
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var dx = cos(angle_offset + PI / 4.0) * size
		var dz = sin(angle_offset + PI / 4.0) * size
		line_mesh.surface_add_vertex(Vector3(-dx, 0, -dz))
		line_mesh.surface_add_vertex(Vector3(dx, 0, dz))
		line_mesh.surface_end()
		var mi = MeshInstance3D.new()
		mi.mesh = line_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.15, 0.15, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		marker.add_child(mi)
	add_child(marker)
	_cross_markers.append(marker)

# --- Île flottante ---

func build_floating_island() -> void:
	var cells_array = terrain_map.keys()
	var get_h = func(cell: Vector2i) -> int: return get_height_at(cell)
	var island_mesh = HexMeshBuilder.build_island_mesh(cells_array, HEX_SIZE, get_h, ELEVATION_UNIT)
	if island_mesh.get_surface_count() == 0:
		return
	var mi = MeshInstance3D.new()
	mi.mesh = island_mesh
	mi.name = "FloatingIsland"
	# Appliquer un material par surface
	for si in range(island_mesh.get_surface_count()):
		var mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(si, mat)
	add_child(mi)

# Accès direct aux cellules pour compatibilité
var cells: Dictionary:
	get:
		return _cell_meshes
