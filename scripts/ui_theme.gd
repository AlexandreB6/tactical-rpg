# Autoload — construit et applique le thème UI global avec les assets Tiny Swords
extends Node

const UI_PATH = "res://assets/Tiny Swords/UI Elements/UI Elements/"

func _ready() -> void:
	var theme = _build_theme()
	ThemeDB.project_theme = theme

func _build_theme() -> Theme:
	var theme = Theme.new()
	# --- Couleurs Label ---
	theme.set_color("font_color", "Label", Color(0.95, 0.9, 0.8))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	# --- Boutons (BigBlue NineSlice) ---
	var btn_n = _nine_slice(UI_PATH + "Buttons/BigBlueButton_Regular.png", 107, 107, 107, 107)
	var btn_p = _nine_slice(UI_PATH + "Buttons/BigBlueButton_Pressed.png", 107, 107, 107, 107)
	var btn_h = _nine_slice(UI_PATH + "Buttons/BigBlueButton_Regular.png", 107, 107, 107, 107)
	btn_h.modulate_color = Color(1.15, 1.15, 1.15)
	var btn_d = _nine_slice(UI_PATH + "Buttons/BigBlueButton_Regular.png", 107, 107, 107, 107)
	btn_d.modulate_color = Color(0.5, 0.5, 0.5, 0.7)
	var btn_f = _nine_slice(UI_PATH + "Buttons/BigBlueButton_Regular.png", 107, 107, 107, 107)
	theme.set_stylebox("normal", "Button", btn_n)
	theme.set_stylebox("pressed", "Button", btn_p)
	theme.set_stylebox("hover", "Button", btn_h)
	theme.set_stylebox("disabled", "Button", btn_d)
	theme.set_stylebox("focus", "Button", btn_f)
	theme.set_color("font_color", "Button", Color(1, 1, 1))
	theme.set_color("font_pressed_color", "Button", Color(0.9, 0.9, 0.85))
	theme.set_color("font_hover_color", "Button", Color(1, 1, 0.9))
	theme.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.6))
	theme.set_color("font_shadow_color", "Button", Color(0, 0, 0, 0.8))
	theme.set_constant("shadow_offset_x", "Button", 1)
	theme.set_constant("shadow_offset_y", "Button", 1)
	# --- PanelContainer : WoodTable ---
	var panel_box = _nine_slice(UI_PATH + "Wood Table/WoodTable.png", 150, 150, 150, 150)
	theme.set_stylebox("panel", "PanelContainer", panel_box)
	# --- LineEdit ---
	var le = _nine_slice(UI_PATH + "Papers/RegularPaper.png", 107, 107, 107, 107)
	le.content_margin_left = 8
	le.content_margin_right = 8
	le.content_margin_top = 4
	le.content_margin_bottom = 4
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", le)
	theme.set_color("font_color", "LineEdit", Color(0.15, 0.12, 0.1))
	theme.set_color("caret_color", "LineEdit", Color(0.2, 0.15, 0.1))
	# --- ItemList (menu principal) ---
	var il = _nine_slice(UI_PATH + "Papers/RegularPaper.png", 107, 107, 107, 107)
	theme.set_stylebox("panel", "ItemList", il)
	theme.set_color("font_color", "ItemList", Color(0.15, 0.12, 0.1))
	theme.set_color("font_selected_color", "ItemList", Color(0.1, 0.05, 0.0))
	var sel = StyleBoxFlat.new()
	sel.bg_color = Color(0.85, 0.75, 0.55, 0.5)
	for prop in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		sel.set(prop, 4)
	theme.set_stylebox("selected", "ItemList", sel)
	theme.set_stylebox("selected_focus", "ItemList", sel)
	# --- ScrollContainer : transparent ---
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return theme

func _nine_slice(path: String, left: int, top: int, right: int, bottom: int) -> StyleBoxTexture:
	var tex = load(path) as Texture2D
	var s = StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = left
	s.texture_margin_top = top
	s.texture_margin_right = right
	s.texture_margin_bottom = bottom
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s
