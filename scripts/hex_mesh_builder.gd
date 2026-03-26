# HexMeshBuilder.gd
# Helper statique pour générer des prismes hexagonaux (flat-top) en 3D.
# Chaque hex = top face (polygone hex texturé) + 6 faces latérales (murs).
class_name HexMeshBuilder

# Génère un prisme hexagonal flat-top.
# hex_size : rayon de l'hexagone (distance centre → sommet) en unités 3D
# top_height : hauteur du dessus du prisme (Y)
# base_height : hauteur du bas du prisme (Y)
# top_color : couleur/tint de la surface supérieure
# wall_color : couleur de base des murs (sera assombrie par face)
static func build_hex_prism(hex_size: float, top_height: float, base_height: float, top_color: Color, wall_color: Color) -> ArrayMesh:
	var mesh = ArrayMesh.new()

	# Sommets du hexagone flat-top (dans le plan XZ)
	var hex_pts: Array[Vector2] = []
	for i in range(6):
		var angle = deg_to_rad(60.0 * i)
		hex_pts.append(Vector2(hex_size * cos(angle), hex_size * sin(angle)))

	# --- Top face (triangle fan depuis le centre) ---
	_add_top_face(mesh, hex_pts, top_height, top_color)

	# --- Contour hex (liseré gris foncé sur la face top) ---
	_add_hex_outline(mesh, hex_pts, top_height)

	# --- 6 faces latérales (quads) ---
	var wall_factors = [0.5, 0.55, 0.65, 0.5, 0.55, 0.65]
	for i in range(6):
		var i2 = (i + 1) % 6
		var factor = wall_factors[i]
		var wc = Color(wall_color.r * factor, wall_color.g * factor, wall_color.b * factor, 1.0)
		_add_wall_face(mesh, hex_pts[i], hex_pts[i2], top_height, base_height, wc)

	return mesh

# Top face : 6 triangles formant l'hexagone
static func _add_top_face(mesh: ArrayMesh, hex_pts: Array[Vector2], y: float, color: Color) -> void:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var uvs = PackedVector2Array()

	var center = Vector3(0, y, 0)

	for i in range(6):
		var i2 = (i + 1) % 6
		var v0 = center
		var v1 = Vector3(hex_pts[i].x, y, hex_pts[i].y)
		var v2 = Vector3(hex_pts[i2].x, y, hex_pts[i2].y)

		vertices.append(v0)
		vertices.append(v1)
		vertices.append(v2)

		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

		colors.append(Color.WHITE)
		colors.append(Color.WHITE)
		colors.append(Color.WHITE)

		# UVs basés sur la position XZ (pour le tiling de texture)
		uvs.append(Vector2(0.5, 0.5))
		uvs.append(Vector2(hex_pts[i].x / (2.0) + 0.5, hex_pts[i].y / (2.0) + 0.5))
		uvs.append(Vector2(hex_pts[i2].x / (2.0) + 0.5, hex_pts[i2].y / (2.0) + 0.5))

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

# Contour hexagonal : 6 segments de lignes fines sur la face top
static func _add_hex_outline(mesh: ArrayMesh, hex_pts: Array[Vector2], y: float) -> void:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var outline_color = Color(0.2, 0.2, 0.2, 0.4)
	var lift = y + 0.01  # Juste au-dessus de la surface pour éviter le z-fighting

	for i in range(6):
		var i2 = (i + 1) % 6
		vertices.append(Vector3(hex_pts[i].x, lift, hex_pts[i].y))
		vertices.append(Vector3(hex_pts[i2].x, lift, hex_pts[i2].y))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		colors.append(outline_color)
		colors.append(outline_color)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

# Wall face : un quad (2 triangles)
static func _add_wall_face(mesh: ArrayMesh, p0: Vector2, p1: Vector2, top_y: float, bottom_y: float, color: Color) -> void:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()

	var tl = Vector3(p0.x, top_y, p0.y)
	var tr = Vector3(p1.x, top_y, p1.y)
	var bl = Vector3(p0.x, bottom_y, p0.y)
	var br = Vector3(p1.x, bottom_y, p1.y)

	# Normale vers l'extérieur (cross product)
	var edge = tr - tl
	var down = bl - tl
	var normal = edge.cross(down).normalized()

	# Triangle 1
	vertices.append(tl)
	vertices.append(bl)
	vertices.append(tr)
	# Triangle 2
	vertices.append(tr)
	vertices.append(bl)
	vertices.append(br)

	for _i in range(6):
		normals.append(normal)
		colors.append(color)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

# Génère un anneau hexagonal (pour les highlights d'unités)
# inner_size : rayon intérieur, outer_size : rayon extérieur
static func build_hex_ring(inner_size: float, outer_size: float, y_offset: float, color: Color) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()

	for i in range(6):
		var i2 = (i + 1) % 6
		var angle0 = deg_to_rad(60.0 * i)
		var angle1 = deg_to_rad(60.0 * i2)

		var inner0 = Vector3(inner_size * cos(angle0), y_offset, inner_size * sin(angle0))
		var outer0 = Vector3(outer_size * cos(angle0), y_offset, outer_size * sin(angle0))
		var inner1 = Vector3(inner_size * cos(angle1), y_offset, inner_size * sin(angle1))
		var outer1 = Vector3(outer_size * cos(angle1), y_offset, outer_size * sin(angle1))

		# Quad = 2 triangles
		vertices.append(inner0)
		vertices.append(outer0)
		vertices.append(inner1)

		vertices.append(inner1)
		vertices.append(outer0)
		vertices.append(outer1)

		for _j in range(6):
			normals.append(Vector3.UP)
			colors.append(color)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# Génère un prisme englobant pour l'île flottante sous la grille
# Forme simple : bounding box étendue vers le bas avec côtés en pente
static func build_island_mesh(hex_cells: Array, hex_size: float, get_height_func: Callable, elevation_unit: float) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	if hex_cells.is_empty():
		return mesh

	# Trouver le bounding box XZ de toutes les cellules
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for cell in hex_cells:
		var x = hex_size * 1.5 * cell.x
		var z = hex_size * sqrt(3.0) * (cell.y + 0.5 * (cell.x % 2))
		min_x = min(min_x, x - hex_size)
		max_x = max(max_x, x + hex_size)
		min_z = min(min_z, z - hex_size)
		max_z = max(max_z, z + hex_size)

	# L'île commence juste sous la base des hex et descend
	var top_y: float = -1.0 * elevation_unit  # Sous la base des hex
	var bottom_y: float = top_y - elevation_unit * 5.0
	var shrink: float = hex_size * 2.0  # Shrink au fond pour la pente

	var vertices = PackedVector3Array()
	var normals_arr = PackedVector3Array()
	var colors = PackedColorArray()
	var rock_color = Color(0.35, 0.25, 0.18)
	var rock_dark = Color(0.25, 0.18, 0.12)
	var rock_bottom = Color(0.18, 0.12, 0.08)

	# Coins du haut (au niveau top_y, taille complète)
	var ttl = Vector3(min_x, top_y, min_z)
	var ttr = Vector3(max_x, top_y, min_z)
	var tbl = Vector3(min_x, top_y, max_z)
	var tbr = Vector3(max_x, top_y, max_z)

	# Coins du bas (shrinkés pour la pente)
	var btl = Vector3(min_x + shrink, bottom_y, min_z + shrink)
	var btr = Vector3(max_x - shrink, bottom_y, min_z + shrink)
	var bbl = Vector3(min_x + shrink, bottom_y, max_z - shrink)
	var bbr = Vector3(max_x - shrink, bottom_y, max_z - shrink)

	# Bottom face (visible d'en bas)
	_add_quad(vertices, normals_arr, colors, btl, bbl, bbr, btr, rock_bottom, -Vector3.UP)

	# Front face (Z+) — visible de face
	_add_quad(vertices, normals_arr, colors, tbr, tbl, bbl, bbr, rock_color, Vector3.BACK)
	# Back face (Z-)
	_add_quad(vertices, normals_arr, colors, ttl, ttr, btr, btl, rock_color, Vector3.FORWARD)
	# Left face (X-)
	_add_quad(vertices, normals_arr, colors, tbl, ttl, btl, bbl, rock_dark, Vector3.LEFT)
	# Right face (X+)
	_add_quad(vertices, normals_arr, colors, ttr, tbr, bbr, btr, rock_dark, Vector3.RIGHT)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals_arr
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _add_quad(vertices: PackedVector3Array, normals_arr: PackedVector3Array, colors: PackedColorArray, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, color: Color, normal: Vector3) -> void:
	vertices.append(v0)
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v0)
	vertices.append(v2)
	vertices.append(v3)
	for _i in range(6):
		normals_arr.append(normal)
		colors.append(color)
