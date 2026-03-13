# HexGrid.gd
# Génère et gère la grille hexagonale (flat-top, offset odd-q).
# Fournit les conversions pixel ↔ coordonnées hex et la gestion du highlight.
extends Node2D

# --- Configuration de la grille ---
const HEX_SIZE = 48        # Rayon d'un hexagone en pixels
const GRID_WIDTH = 10      # Nombre de colonnes
const GRID_HEIGHT = 8      # Nombre de lignes
const ISO_Y_SCALE = 0.55   # Écrasement vertical pour effet isométrique
const ELEVATION_PX = 20    # Pixels par niveau de hauteur
const MIN_HEIGHT: int = -1
const BASE_THICKNESS: int = 1
const WALL_FACTOR_DARK: float = 0.5
const WALL_FACTOR_MEDIUM: float = 0.65
const HIGHLIGHT_MOVE = Color(0.55, 1.0, 0.4)
const HIGHLIGHT_ATTACK = Color(1.0, 0.35, 0.35)
const HIGHLIGHT_INSPECT_ATTACK = Color(1.0, 0.6, 0.3)

# --- Terrain ---
enum Terrain { PLAINS, FOREST, HILL, MOUNTAIN, WATER }

const TERRAIN_INFO = {
	Terrain.PLAINS:   { "name": "Plaine",   "color": Color(0.3, 0.55, 0.3),   "outline": Color(0.1, 0.25, 0.1),   "height": 1, "def_bonus": 0, "passable": true,  "blocks_los": false, "tint": Color.WHITE },
	Terrain.FOREST:   { "name": "Forêt",    "color": Color(0.18, 0.4, 0.18),  "outline": Color(0.07, 0.2, 0.07),  "height": 1, "def_bonus": 1, "passable": false, "blocks_los": true,  "tint": Color(0.85, 0.95, 0.75) },
	Terrain.HILL:     { "name": "Colline",  "color": Color(0.6, 0.5, 0.3),    "outline": Color(0.35, 0.28, 0.15), "height": 2, "def_bonus": 1, "passable": true,  "blocks_los": false, "tint": Color(1.05, 0.88, 0.65) },
	Terrain.MOUNTAIN: { "name": "Montagne", "color": Color(0.55, 0.55, 0.55), "outline": Color(0.3, 0.3, 0.3),   "height": 5, "def_bonus": 0, "passable": false, "blocks_los": true,  "tint": Color(0.7, 0.7, 0.75) },
	Terrain.WATER:    { "name": "Eau",      "color": Color(0.2, 0.35, 0.65),  "outline": Color(0.1, 0.18, 0.35), "height": 0, "def_bonus": 0, "passable": false, "blocks_los": false, "tint": Color.WHITE },
}

const TERRAIN_CHAR = {
	"P": Terrain.PLAINS, "F": Terrain.FOREST, "H": Terrain.HILL,
	"M": Terrain.MOUNTAIN, "W": Terrain.WATER,
}

# Dictionnaire Vector2i → Polygon2D (remplissage de la case)
var cells = {}
# Dictionnaire Vector2i → Terrain
var terrain_map = {}
# Couleur de base par case (pour restaurer après highlight)
var _cell_base_color: Dictionary = {}
# Textures de terrain extraites (Terrain → ImageTexture)
var _terrain_tex: Dictionary = {}
# Marqueurs de croix rouge (cases impassables à portée)
var _cross_markers: Array[Node2D] = []
# Dimensions effectives (peuvent être remplacées par load_level_data)
var grid_width: int = GRID_WIDTH
var grid_height: int = GRID_HEIGHT
# Textures de décoration
var _tree_textures: Array[Texture2D] = []
var _rock_textures: Array[Texture2D] = []
var _bush_textures: Array[Texture2D] = []

# --- Chargement des textures de terrain ---

func _init_terrain_textures() -> void:
	var tilemap1 = load("res://assets/Tiny Swords/Terrain/Tileset/Tilemap_color1.png") as Texture2D
	var tilemap5 = load("res://assets/Tiny Swords/Terrain/Tileset/Tilemap_color5.png") as Texture2D
	var water_tex = load("res://assets/Tiny Swords/Terrain/Tileset/Water Background color.png") as Texture2D
	# Extraire la zone d'herbe intérieure (centre du grand bloc, 128x128)
	_terrain_tex[Terrain.PLAINS] = _extract_tile_region(tilemap1)
	_terrain_tex[Terrain.HILL] = _extract_tile_region(tilemap1)
	_terrain_tex[Terrain.FOREST] = _extract_tile_region(tilemap5)
	_terrain_tex[Terrain.MOUNTAIN] = _extract_tile_region(tilemap5)
	_terrain_tex[Terrain.WATER] = water_tex
	# Décorations
	for i in range(1, 5):
		_tree_textures.append(load("res://assets/Tiny Swords/Terrain/Resources/Wood/Trees/Tree%d.png" % i))
		_rock_textures.append(load("res://assets/Tiny Swords/Terrain/Decorations/Rocks/Rock%d.png" % i))
		_bush_textures.append(load("res://assets/Tiny Swords/Terrain/Decorations/Bushes/Bushe%d.png" % i))

# Extrait une zone d'herbe pure depuis le centre du tilemap (576x384)
# On prend une petite zone bien à l'intérieur du bloc pour éviter les bords feuillus
func _extract_tile_region(tilemap_tex: Texture2D) -> ImageTexture:
	var img = tilemap_tex.get_image()
	# Zone 64x64 au cœur du bloc d'herbe (loin des bords décoratifs)
	var region = Rect2i(80, 44, 64, 64)
	var cropped = img.get_region(region)
	return ImageTexture.create_from_image(cropped)

# Charge le terrain depuis un tableau de chaînes (ex: ["PPFFPP", "PPPFPP", ...])
func load_terrain(terrain_rows: Array, width: int, height: int) -> void:
	grid_width = width
	grid_height = height
	terrain_map.clear()
	_cell_base_color.clear()
	for r in range(grid_height):
		var row: String = terrain_rows[r]
		for q in range(grid_width):
			terrain_map[Vector2i(q, r)] = TERRAIN_CHAR[row[q]]
	# Charger les textures si pas encore fait
	if _terrain_tex.is_empty():
		_init_terrain_textures()
	# Supprime l'ancienne grille visuelle si elle existe
	for child in get_children():
		child.queue_free()
	cells.clear()
	await get_tree().process_frame
	_generate_grid()

# Génère toutes les cases et centre la grille dans la fenêtre
func _generate_grid() -> void:
	# Itérer par r croissant (fond → avant) pour le tri de profondeur
	for r in range(grid_height):
		for q in range(grid_width):
			_create_hex_cell(q, r)
	var grid_w = HEX_SIZE * 1.5 * grid_width
	var grid_h = HEX_SIZE * sqrt(3.0) * grid_height * ISO_Y_SCALE
	position = -Vector2(grid_w, grid_h) / 2.0

# Génère les 6 sommets d'un hexagone flat-top de rayon donné (écrasés en iso)
func _get_hex_vertices(size: float) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60.0 * i)
		pts.append(Vector2(size * cos(angle), size * sin(angle) * ISO_Y_SCALE))
	return pts

# Crée un bloc hexagonal solide (silhouette + 3 murs + surface) à la position (q, r)
func _create_hex_cell(q: int, r: int) -> void:
	var cell = Vector2i(q, r)
	var terrain = terrain_map.get(cell, Terrain.PLAINS)
	var info = TERRAIN_INFO[terrain]
	var h: int = info["height"]
	var pos = hex_to_pixel(q, r) + Vector2(0, -h * ELEVATION_PX)
	var wall_height = (h - MIN_HEIGHT + BASE_THICKNESS) * ELEVATION_PX
	var down = Vector2(0, wall_height)
	var verts = _get_hex_vertices(HEX_SIZE)
	# z_index pairs pour les hex, impairs pour les unités (intercalés)
	var zi = (r * 2 + (q % 2)) * 2
	# 1. Silhouette opaque (8 vertices) — couvre tout le bloc visible
	# Top edge: v3, v4, v5, v0 — Base edge: v0+down, v1+down, v2+down, v3+down
	var silhouette = Polygon2D.new()
	silhouette.polygon = PackedVector2Array([
		verts[3], verts[4], verts[5], verts[0],
		verts[0] + down, verts[1] + down, verts[2] + down, verts[3] + down,
	])
	silhouette.color = info["outline"]
	silhouette.position = pos
	silhouette.z_index = zi
	silhouette.z_as_relative = false
	add_child(silhouette)
	# 2. Mur droit [v0, v1, v1+down, v0+down]
	var wall_right = Polygon2D.new()
	wall_right.polygon = PackedVector2Array([
		verts[0], verts[1], verts[1] + down, verts[0] + down,
	])
	var c_right: Color = info["color"] * WALL_FACTOR_DARK
	c_right.a = 1.0
	wall_right.color = c_right
	wall_right.position = pos
	wall_right.z_index = zi
	wall_right.z_as_relative = false
	add_child(wall_right)
	# 3. Mur avant [v1, v2, v2+down, v1+down]
	var wall_front = Polygon2D.new()
	wall_front.polygon = PackedVector2Array([
		verts[1], verts[2], verts[2] + down, verts[1] + down,
	])
	var c_front: Color = info["color"] * WALL_FACTOR_MEDIUM
	c_front.a = 1.0
	wall_front.color = c_front
	wall_front.position = pos
	wall_front.z_index = zi
	wall_front.z_as_relative = false
	add_child(wall_front)
	# 4. Mur gauche [v2, v3, v2+down, v3+down]
	var wall_left = Polygon2D.new()
	wall_left.polygon = PackedVector2Array([
		verts[2], verts[3], verts[3] + down, verts[2] + down,
	])
	var c_left: Color = info["color"] * WALL_FACTOR_DARK
	c_left.a = 1.0
	wall_left.color = c_left
	wall_left.position = pos
	wall_left.z_index = zi
	wall_left.z_as_relative = false
	add_child(wall_left)
	# 5. Surface top (fill, HEX_SIZE-2) — texturée
	var fill = Polygon2D.new()
	var verts_fill = _get_hex_vertices(HEX_SIZE - 2)
	fill.polygon = verts_fill
	var tex = _terrain_tex.get(terrain)
	if tex:
		fill.texture = tex
		fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# UV en coordonnées monde (sans élévation) pour tiling seamless
		var base_pix = hex_to_pixel(q, r)
		var uvs = PackedVector2Array()
		for v in verts_fill:
			var wv = v + base_pix
			uvs.append(Vector2(wv.x, wv.y / ISO_Y_SCALE))
		fill.uv = uvs
		fill.color = info["tint"]
	else:
		fill.color = info["color"]
	fill.position = pos
	fill.z_index = zi
	fill.z_as_relative = false
	add_child(fill)
	cells[cell] = fill
	_cell_base_color[cell] = fill.color
	# 6. Décorations (arbres, rochers) sur certains terrains
	_add_decoration(cell, terrain, pos, zi)

# Ajoute un sprite décoratif sur certains terrains (arbres, rochers, buissons)
func _add_decoration(cell: Vector2i, terrain: Terrain, pos: Vector2, zi: int) -> void:
	var sprite: Sprite2D = null
	# Seed déterministe par position pour variation reproductible
	var rng = RandomNumberGenerator.new()
	rng.seed = cell.x * 73856093 + cell.y * 19349663
	match terrain:
		Terrain.FOREST:
			if _tree_textures.is_empty():
				return
			# Forêt dense : 3-4 arbres + 2-3 buissons + 1-2 petits arbres
			var tree_count = rng.randi_range(3, 4)
			for i in range(tree_count):
				var tree = Sprite2D.new()
				var tex = _tree_textures[rng.randi_range(0, _tree_textures.size() - 1)]
				tree.texture = tex
				tree.hframes = 8
				tree.frame = rng.randi_range(0, 7)
				var target_h = rng.randf_range(50.0, 80.0)
				var s = target_h / tex.get_height()
				tree.scale = Vector2(s, s)
				var ox = rng.randf_range(-38, 38)
				var oy = rng.randf_range(-18, 14) * ISO_Y_SCALE
				tree.position = pos + Vector2(ox, oy - 26)
				tree.z_index = zi + 1
				tree.z_as_relative = false
				add_child(tree)
			# Buissons pour remplir les trous
			var bush_count = rng.randi_range(2, 3)
			for i in range(bush_count):
				if _bush_textures.is_empty():
					break
				var bush = Sprite2D.new()
				var tex = _bush_textures[rng.randi_range(0, _bush_textures.size() - 1)]
				bush.texture = tex
				bush.hframes = 8
				bush.frame = rng.randi_range(0, 7)
				var target_h = rng.randf_range(18.0, 30.0)
				var s = target_h / tex.get_height()
				bush.scale = Vector2(s, s)
				var ox = rng.randf_range(-34, 34)
				var oy = rng.randf_range(-10, 14) * ISO_Y_SCALE
				bush.position = pos + Vector2(ox, oy)
				bush.z_index = zi + 1
				bush.z_as_relative = false
				add_child(bush)
			# Petits arbres supplémentaires en arrière-plan
			var small_tree_count = rng.randi_range(1, 2)
			for i in range(small_tree_count):
				var tree = Sprite2D.new()
				var tex = _tree_textures[rng.randi_range(0, _tree_textures.size() - 1)]
				tree.texture = tex
				tree.hframes = 8
				tree.frame = rng.randi_range(0, 7)
				var target_h = rng.randf_range(30.0, 45.0)
				var s = target_h / tex.get_height()
				tree.scale = Vector2(s, s)
				var ox = rng.randf_range(-32, 32)
				var oy = rng.randf_range(-14, 10) * ISO_Y_SCALE
				tree.position = pos + Vector2(ox, oy - 14)
				tree.z_index = zi + 1
				tree.z_as_relative = false
				add_child(tree)
			return  # Pas de sprite unique à ajouter
		Terrain.MOUNTAIN:
			if _rock_textures.is_empty():
				return
			# Placer 2-3 rochers
			for i in range(rng.randi_range(2, 3)):
				var rock = Sprite2D.new()
				rock.texture = _rock_textures[rng.randi_range(0, _rock_textures.size() - 1)]
				var s = rng.randf_range(0.5, 0.8)
				rock.scale = Vector2(s, s)
				var ox = rng.randf_range(-18, 18)
				var oy = rng.randf_range(-8, 8) * ISO_Y_SCALE
				rock.position = pos + Vector2(ox, oy - 4)
				rock.z_index = zi + 1
				rock.z_as_relative = false
				add_child(rock)
			return  # Pas de sprite unique à ajouter
		Terrain.HILL:
			if _bush_textures.is_empty():
				return
			# Optionnel : un buisson sur ~50% des collines
			if rng.randf() > 0.5:
				return
			sprite = Sprite2D.new()
			var tex = _bush_textures[rng.randi_range(0, _bush_textures.size() - 1)]
			sprite.texture = tex
			sprite.hframes = 8
			sprite.frame = rng.randi_range(0, 7)
			var target_h = 28.0
			var s = target_h / tex.get_height()
			sprite.scale = Vector2(s, s)
			sprite.position = pos + Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 2))
		_:
			return
	if sprite:
		sprite.z_index = zi + 1
		sprite.z_as_relative = false
		add_child(sprite)

# --- Conversions de coordonnées ---

# Convertit des coordonnées hex (q, r) en position pixel locale (projection iso)
func hex_to_pixel(q: int, r: int) -> Vector2:
	var x = HEX_SIZE * 1.5 * q
	var y = HEX_SIZE * sqrt(3.0) * (r + 0.5 * (q % 2))
	y *= ISO_Y_SCALE
	return Vector2(x, y)

# Retourne la position monde d'une case (avec offset d'élévation)
func get_cell_world_position(cell: Vector2i) -> Vector2:
	var base = hex_to_pixel(cell.x, cell.y) + position
	var h = get_height_at(cell)
	return base + Vector2(0, -h * ELEVATION_PX)

# Convertit une position pixel globale en coordonnées hex (arrondi cubique précis)
# Compense l'élévation visuelle : teste chaque hauteur possible et garde le hex
# dont la surface top est la plus proche du clic (évite de sélectionner un mur)
func pixel_to_hex(pixel_pos: Vector2) -> Vector2i:
	var local_pos = pixel_pos - position
	var best_cell = Vector2i(-1, -1)
	var best_dist = INF
	# Collecter les hauteurs uniques présentes dans la carte
	var heights_seen = {}
	for cell in terrain_map:
		var h = TERRAIN_INFO[terrain_map[cell]]["height"]
		heights_seen[h] = true
	# Pour chaque hauteur possible, tester si le clic correspond à un hex de cette hauteur
	for h in heights_seen:
		# Compenser l'élévation visuelle pour retrouver les coordonnées hex
		var test_pos = Vector2(local_pos.x, local_pos.y + h * ELEVATION_PX)
		test_pos.y /= ISO_Y_SCALE
		# Pixel → axial (flat-top)
		var fq = (2.0 / 3.0 * test_pos.x) / HEX_SIZE
		var fr = (-1.0 / 3.0 * test_pos.x + sqrt(3.0) / 3.0 * test_pos.y) / HEX_SIZE
		# Arrondi cubique
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
		var cell = Vector2i(q, r)
		if is_valid_cell(cell) and get_height_at(cell) == h:
			# Distance entre le clic et le centre de la surface top du hex
			# Préfère le hex dont la surface est la plus proche → évite les murs
			var center = hex_to_pixel(q, r) + Vector2(0, -h * ELEVATION_PX)
			var dist = local_pos.distance_to(center)
			if dist < best_dist:
				best_dist = dist
				best_cell = cell
	# Fallback sans compensation d'élévation (ne devrait pas arriver en jeu)
	if best_cell == Vector2i(-1, -1):
		return _pixel_to_hex_flat(pixel_pos)
	return best_cell

# Version sans compensation d'élévation (fallback)
func _pixel_to_hex_flat(pixel_pos: Vector2) -> Vector2i:
	var local_pos = pixel_pos - position
	local_pos.y /= ISO_Y_SCALE
	var fq = (2.0 / 3.0 * local_pos.x) / HEX_SIZE
	var fr = (-1.0 / 3.0 * local_pos.x + sqrt(3.0) / 3.0 * local_pos.y) / HEX_SIZE
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
	var q = rq
	var r = rr + (rq - (rq & 1)) / 2
	return Vector2i(q, r)

# Retourne true si la case est dans les limites de la grille
func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

# --- Terrain : accesseurs ---

func get_terrain_at(cell: Vector2i) -> Terrain:
	return terrain_map.get(cell, Terrain.PLAINS)

func get_height_at(cell: Vector2i) -> int:
	return TERRAIN_INFO[get_terrain_at(cell)]["height"]

func get_terrain_def_bonus(cell: Vector2i) -> int:
	return TERRAIN_INFO[get_terrain_at(cell)]["def_bonus"]

func get_terrain_name(cell: Vector2i) -> String:
	return TERRAIN_INFO[get_terrain_at(cell)]["name"]

func is_passable(cell: Vector2i) -> bool:
	return TERRAIN_INFO[get_terrain_at(cell)]["passable"]

func blocks_los(cell: Vector2i) -> bool:
	return TERRAIN_INFO[get_terrain_at(cell)]["blocks_los"]

# Vérifie la ligne de vue entre deux cases (les cases intermédiaires bloquantes = pas de LOS)
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var dist = hex_distance(from, to)
	if dist <= 1:
		return true
	var ac = _offset_to_cube(from)
	var bc = _offset_to_cube(to)
	# Parcourir les hex intermédiaires via lerp cubique
	for i in range(1, dist):
		var t = float(i) / float(dist)
		# Lerp en cube float + nudge pour éviter les arêtes exactes
		var fx = ac.x + (bc.x - ac.x) * t + 1e-6
		var fy = ac.y + (bc.y - ac.y) * t + 1e-6
		var fz = ac.z + (bc.z - ac.z) * t - 2e-6
		# Arrondi cubique
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
		# Cube → offset odd-q
		var cq = int(rx)
		var cr = int(rz) + int((int(rx) - (int(rx) & 1)) / 2)
		var cell = Vector2i(cq, cr)
		if is_valid_cell(cell) and blocks_los(cell):
			return false
	return true

# --- Highlight ---

# Retourne toutes les cases dans un rayon donné, en excluant origin, les bloquées et (par défaut) les infranchissables
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

# Retourne les cases réellement atteignables via BFS (respecte le pathfinding)
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

# Surligne les cases accessibles et marque les cases impassables à portée
func highlight_cells(origin: Vector2i, move_range: int, blocked_cells: Dictionary = {}) -> void:
	clear_highlights()
	var reachable = get_reachable_cells(origin, move_range, blocked_cells)
	var reachable_set: Dictionary = {}
	for cell in reachable:
		reachable_set[cell] = true
		cells[cell].color = HIGHLIGHT_MOVE
	# Croix rouges sur les cases impassables ou bloquées dans le rayon
	for q in range(grid_width):
		for r in range(grid_height):
			var cell = Vector2i(q, r)
			if cell == origin or reachable_set.has(cell):
				continue
			if hex_distance(origin, cell) <= move_range:
				if not is_passable(cell) or blocked_cells.has(cell):
					_create_cross_marker(cell)

# Remet toutes les cases à leur couleur de base et supprime les marqueurs
func clear_highlights() -> void:
	for cell: Vector2i in cells:
		cells[cell].color = _cell_base_color.get(cell, Color.WHITE)
	# Supprimer les croix rouges
	for marker in _cross_markers:
		marker.queue_free()
	_cross_markers.clear()

# Crée une croix rouge sur une case impassable (indique qu'on ne peut pas y aller)
func _create_cross_marker(cell: Vector2i) -> void:
	var h = get_height_at(cell)
	var pos = hex_to_pixel(cell.x, cell.y) + Vector2(0, -h * ELEVATION_PX)
	var size = 8.0
	var zi = (cell.y * 2 + (cell.x % 2)) * 2 + 1
	# Deux lignes qui se croisent
	var line1 = Line2D.new()
	line1.points = [
		pos + Vector2(-size, -size * ISO_Y_SCALE),
		pos + Vector2(size, size * ISO_Y_SCALE),
	]
	line1.width = 2.5
	line1.default_color = Color(0.85, 0.15, 0.15, 0.75)
	line1.z_index = zi
	line1.z_as_relative = false
	add_child(line1)
	var line2 = Line2D.new()
	line2.points = [
		pos + Vector2(size, -size * ISO_Y_SCALE),
		pos + Vector2(-size, size * ISO_Y_SCALE),
	]
	line2.width = 2.5
	line2.default_color = Color(0.85, 0.15, 0.15, 0.75)
	line2.z_index = zi
	line2.z_as_relative = false
	add_child(line2)
	_cross_markers.append(line1)
	_cross_markers.append(line2)

# --- Calcul de distance ---

# Retourne la distance en nombre de cases entre deux positions hex
func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var ac = _offset_to_cube(a)
	var bc = _offset_to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2)

# Convertit des coordonnées offset odd-q en coordonnées cubiques
func _offset_to_cube(cell: Vector2i) -> Vector3i:
	var x = cell.x
	var z = cell.y - int((cell.x - (cell.x & 1)) / 2)
	var y = -x - z
	return Vector3i(x, y, z)

# Retourne les 6 voisins d'une case hex (odd-q offset)
func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var q = cell.x
	var r = cell.y
	var parity = q & 1  # 0 = pair, 1 = impair
	var result: Array[Vector2i] = []
	# Directions odd-q offset : [dq, dr_pair, dr_impair]
	var dirs = [
		[Vector2i(+1, -1), Vector2i(+1,  0)],  # droite haut
		[Vector2i(+1,  0), Vector2i(+1, +1)],  # droite bas
		[Vector2i( 0, +1), Vector2i( 0, +1)],  # bas
		[Vector2i(-1,  0), Vector2i(-1, +1)],  # gauche bas
		[Vector2i(-1, -1), Vector2i(-1,  0)],  # gauche haut
		[Vector2i( 0, -1), Vector2i( 0, -1)],  # haut
	]
	for dir in dirs:
		var d: Vector2i = dir[parity]
		var neighbor = Vector2i(q + d.x, r + d.y)
		if is_valid_cell(neighbor):
			result.append(neighbor)
	return result

# A* pathfinding : trouve le chemin le plus court entre deux cases
# blocked = cases occupées (unités, etc.) à éviter
# max_range = portée de déplacement (limite la recherche)
func find_path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}, max_range: int = 99) -> Array[Vector2i]:
	if from == to:
		return []
	# Open set : [f_score, cell]
	var open: Array = []
	open.append([hex_distance(from, to), from])
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0}
	while not open.is_empty():
		# Trouver le nœud avec le plus petit f_score
		var best_idx = 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var current: Vector2i = open[best_idx][1]
		open.remove_at(best_idx)
		if current == to:
			# Reconstruire le chemin
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
