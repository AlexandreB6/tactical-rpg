# Autoload — construit et applique le thème UI global avec les assets Tiny Swords
#
# Styles de boutons disponibles (via theme_type_variation) :
#   "BtnPrimary"   — bleu, pour les actions principales (Jouer, valider…)
#   "BtnGhost"     — transparent, juste l'icône/texte (action bar, fermer…)
#   "BtnDanger"    — rouge, pour les actions destructives (Quitter…)
#
# Usage en code :  button.theme_type_variation = "BtnPrimary"
# Usage en .tscn : propriété theme_type_variation dans l'Inspector
extends Node

const UI_PATH = "res://assets/Tiny Swords/UI Elements/UI Elements/"

var current_theme: Theme

func _ready() -> void:
	current_theme = _build_theme()
	get_tree().root.theme = current_theme
	_set_default_cursor()

func _build_theme() -> Theme:
	var theme = Theme.new()
	# ==================== Label ====================
	theme.set_color("font_color", "Label", Color(0.95, 0.9, 0.8))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)

	# ==================== Button (base, pas de style) ====================
	# Le Button de base est neutre (pas de fond) — on choisit un style via variation
	var empty = StyleBoxEmpty.new()
	empty.content_margin_left = 8
	empty.content_margin_right = 8
	empty.content_margin_top = 4
	empty.content_margin_bottom = 4
	theme.set_stylebox("normal", "Button", empty)
	theme.set_stylebox("pressed", "Button", empty)
	theme.set_stylebox("hover", "Button", empty)
	theme.set_stylebox("disabled", "Button", empty)
	theme.set_stylebox("focus", "Button", empty)
	theme.set_color("font_color", "Button", Color(1, 1, 1))
	theme.set_color("font_pressed_color", "Button", Color(0.9, 0.9, 0.85))
	theme.set_color("font_hover_color", "Button", Color(1, 1, 0.9))
	theme.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.6))
	theme.set_color("font_shadow_color", "Button", Color(0, 0, 0, 0.8))
	theme.set_constant("shadow_offset_x", "Button", 1)
	theme.set_constant("shadow_offset_y", "Button", 1)

	# ==================== BtnPrimary (bleu) ====================
	_register_button_style(theme, "BtnPrimary",
		UI_PATH + "Buttons/SmallBlueSquareButton_Regular.png",
		UI_PATH + "Buttons/SmallBlueSquareButton_Pressed.png")

	# ==================== BtnDanger (rouge) ====================
	_register_button_style(theme, "BtnDanger",
		UI_PATH + "Buttons/SmallRedSquareButton_Regular.png",
		UI_PATH + "Buttons/SmallRedSquareButton_Pressed.png")

	# ==================== BtnGhost (transparent, icônes only) ====================
	theme.add_type("BtnGhost")
	theme.set_type_variation("BtnGhost", "Button")
	var ghost = StyleBoxEmpty.new()
	ghost.content_margin_left = 4
	ghost.content_margin_right = 4
	ghost.content_margin_top = 2
	ghost.content_margin_bottom = 2
	theme.set_stylebox("normal", "BtnGhost", ghost)
	theme.set_stylebox("pressed", "BtnGhost", ghost)
	theme.set_stylebox("focus", "BtnGhost", ghost)
	theme.set_stylebox("disabled", "BtnGhost", ghost)
	var ghost_hover = StyleBoxFlat.new()
	ghost_hover.bg_color = Color(1, 1, 1, 0.1)
	ghost_hover.set_corner_radius_all(4)
	ghost_hover.content_margin_left = 4
	ghost_hover.content_margin_right = 4
	ghost_hover.content_margin_top = 2
	ghost_hover.content_margin_bottom = 2
	theme.set_stylebox("hover", "BtnGhost", ghost_hover)

	# ==================== PanelContainer ====================
	var panel_box = _nine_slice(UI_PATH + "Wood Table/WoodTable_Slots.png", 22, 22, 22, 22)
	theme.set_stylebox("panel", "PanelContainer", panel_box)

	# ==================== LineEdit ====================
	var le = StyleBoxFlat.new()
	le.bg_color = Color(0.92, 0.87, 0.75, 0.95)
	le.set_border_width_all(2)
	le.border_color = Color(0.3, 0.25, 0.2, 0.8)
	le.set_corner_radius_all(4)
	le.content_margin_left = 8
	le.content_margin_right = 8
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", le)
	theme.set_color("font_color", "LineEdit", Color(0.15, 0.12, 0.1))
	theme.set_color("caret_color", "LineEdit", Color(0.2, 0.15, 0.1))

	# ==================== ItemList ====================
	var il = StyleBoxFlat.new()
	il.bg_color = Color(0.92, 0.87, 0.75, 0.95)
	il.set_border_width_all(2)
	il.border_color = Color(0.3, 0.25, 0.2, 0.6)
	il.set_corner_radius_all(4)
	il.content_margin_left = 10
	il.content_margin_right = 10
	il.content_margin_top = 8
	il.content_margin_bottom = 8
	theme.set_stylebox("panel", "ItemList", il)
	theme.set_color("font_color", "ItemList", Color(0.15, 0.12, 0.1))
	theme.set_color("font_selected_color", "ItemList", Color(0.1, 0.05, 0.0))
	var sel = StyleBoxFlat.new()
	sel.bg_color = Color(0.85, 0.75, 0.55, 0.5)
	sel.set_corner_radius_all(4)
	theme.set_stylebox("selected", "ItemList", sel)
	theme.set_stylebox("selected_focus", "ItemList", sel)
	var item_hover = StyleBoxFlat.new()
	item_hover.bg_color = Color(0.85, 0.75, 0.55, 0.25)
	item_hover.set_corner_radius_all(4)
	theme.set_stylebox("hovered", "ItemList", item_hover)
	theme.set_color("font_hovered_color", "ItemList", Color(0.15, 0.12, 0.1))

	# ==================== ScrollContainer ====================
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return theme

# Enregistre un style de bouton NinePatch (normal, pressed, hover, disabled, focus)
func _register_button_style(theme: Theme, type_name: String, regular_path: String, pressed_path: String) -> void:
	theme.add_type(type_name)
	theme.set_type_variation(type_name, "Button")
	var btn_n = _nine_slice(regular_path, 20, 20, 20, 20)
	btn_n.content_margin_top = 4
	btn_n.content_margin_bottom = 12
	var btn_p = _nine_slice(pressed_path, 20, 20, 20, 20)
	btn_p.content_margin_top = 8
	btn_p.content_margin_bottom = 6
	var btn_h = _nine_slice(regular_path, 20, 20, 20, 20)
	btn_h.content_margin_top = 4
	btn_h.content_margin_bottom = 12
	btn_h.modulate_color = Color(1.15, 1.15, 1.15)
	var btn_d = _nine_slice(regular_path, 20, 20, 20, 20)
	btn_d.content_margin_top = 4
	btn_d.content_margin_bottom = 12
	btn_d.modulate_color = Color(0.5, 0.5, 0.5, 0.7)
	var btn_f = _nine_slice(regular_path, 20, 20, 20, 20)
	btn_f.content_margin_top = 4
	btn_f.content_margin_bottom = 12
	theme.set_stylebox("normal", type_name, btn_n)
	theme.set_stylebox("pressed", type_name, btn_p)
	theme.set_stylebox("hover", type_name, btn_h)
	theme.set_stylebox("disabled", type_name, btn_d)
	theme.set_stylebox("focus", type_name, btn_f)

func _set_default_cursor() -> void:
	var cursor_tex = load(UI_PATH + "Cursors/Cursor_02.png") as Texture2D
	if cursor_tex:
		var img = cursor_tex.get_image()
		img.resize(32, 32, Image.INTERPOLATE_NEAREST)
		var resized = ImageTexture.create_from_image(img)
		Input.set_custom_mouse_cursor(resized, Input.CURSOR_ARROW, Vector2(4, 0))

func _nine_slice(path: String, left: int, top: int, right: int, bottom: int) -> StyleBoxTexture:
	var tex = load(path) as Texture2D
	var s = StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = left
	s.texture_margin_top = top
	s.texture_margin_right = right
	s.texture_margin_bottom = bottom
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s
