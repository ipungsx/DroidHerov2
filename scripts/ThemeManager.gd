extends Node

signal theme_changed(theme_id: String)

const THEMES: Dictionary = {
	"neon_cyber": {
		"name": "NEON CYBERPUNK",
		"subtitle": "Electric Cyan & Magenta Laser Arena",
		"bg_top": Color(0.03, 0.02, 0.09),
		"bg_bottom": Color(0.08, 0.02, 0.16),
		"panel": Color(0.07, 0.06, 0.16, 0.88),
		"panel_alt": Color(0.11, 0.09, 0.24, 0.92),
		"border": Color(0.0, 0.92, 1.0, 0.85),
		"accent": Color(0.0, 0.94, 1.0),
		"accent_2": Color(1.0, 0.16, 0.75),
		"accent_3": Color(0.62, 0.25, 1.0),
		"text": Color(0.95, 0.98, 1.0),
		"text_dim": Color(0.62, 0.72, 0.88),
		"highway": Color(0.05, 0.04, 0.12, 0.92),
		"highway_edge": Color(0.0, 0.94, 1.0),
		"star_power": Color(0.0, 0.98, 1.0),
		"spotlights": [
			Color(0.0, 0.95, 1.0),
			Color(1.0, 0.15, 0.78),
			Color(0.55, 0.22, 1.0),
			Color(0.1, 1.0, 0.65)
		]
	},
	"inferno_rock": {
		"name": "INFERNO STADIUM",
		"subtitle": "Pyrotechnic Crimson & Molten Gold",
		"bg_top": Color(0.09, 0.02, 0.02),
		"bg_bottom": Color(0.19, 0.04, 0.01),
		"panel": Color(0.15, 0.05, 0.05, 0.88),
		"panel_alt": Color(0.22, 0.08, 0.06, 0.92),
		"border": Color(1.0, 0.55, 0.08, 0.88),
		"accent": Color(1.0, 0.62, 0.05),
		"accent_2": Color(1.0, 0.18, 0.12),
		"accent_3": Color(1.0, 0.85, 0.22),
		"text": Color(1.0, 0.97, 0.93),
		"text_dim": Color(0.86, 0.68, 0.58),
		"highway": Color(0.10, 0.03, 0.03, 0.92),
		"highway_edge": Color(1.0, 0.52, 0.08),
		"star_power": Color(1.0, 0.84, 0.18),
		"spotlights": [
			Color(1.0, 0.22, 0.06),
			Color(1.0, 0.65, 0.05),
			Color(1.0, 0.88, 0.22),
			Color(0.95, 0.12, 0.32)
		]
	},
	"emerald_matrix": {
		"name": "EMERALD OVERDRIVE",
		"subtitle": "Toxic Lime & Acid Cyber Stage",
		"bg_top": Color(0.01, 0.07, 0.04),
		"bg_bottom": Color(0.02, 0.14, 0.08),
		"panel": Color(0.04, 0.13, 0.09, 0.88),
		"panel_alt": Color(0.06, 0.19, 0.13, 0.92),
		"border": Color(0.12, 1.0, 0.52, 0.88),
		"accent": Color(0.15, 1.0, 0.52),
		"accent_2": Color(0.75, 1.0, 0.12),
		"accent_3": Color(0.0, 0.88, 0.82),
		"text": Color(0.93, 1.0, 0.96),
		"text_dim": Color(0.58, 0.84, 0.70),
		"highway": Color(0.02, 0.09, 0.06, 0.92),
		"highway_edge": Color(0.15, 1.0, 0.52),
		"star_power": Color(0.68, 1.0, 0.18),
		"spotlights": [
			Color(0.12, 1.0, 0.48),
			Color(0.78, 1.0, 0.12),
			Color(0.0, 0.92, 0.82),
			Color(0.32, 1.0, 0.28)
		]
	},
	"royal_gold": {
		"name": "ROYAL GOLD VIP",
		"subtitle": "Velvet Violet & Champagne Gold",
		"bg_top": Color(0.06, 0.03, 0.11),
		"bg_bottom": Color(0.13, 0.06, 0.18),
		"panel": Color(0.11, 0.07, 0.18, 0.88),
		"panel_alt": Color(0.17, 0.11, 0.26, 0.92),
		"border": Color(1.0, 0.82, 0.28, 0.90),
		"accent": Color(1.0, 0.82, 0.28),
		"accent_2": Color(0.76, 0.36, 1.0),
		"accent_3": Color(1.0, 0.94, 0.65),
		"text": Color(1.0, 0.98, 0.92),
		"text_dim": Color(0.78, 0.72, 0.88),
		"highway": Color(0.07, 0.04, 0.12, 0.92),
		"highway_edge": Color(1.0, 0.82, 0.28),
		"star_power": Color(1.0, 0.92, 0.42),
		"spotlights": [
			Color(1.0, 0.82, 0.28),
			Color(0.76, 0.34, 1.0),
			Color(1.0, 0.95, 0.68),
			Color(0.95, 0.45, 0.78)
		]
	},
	"synthwave_sunset": {
		"name": "SYNTHWAVE SUNSET",
		"subtitle": "80s Outrun Horizon & Laser Grid",
		"bg_top": Color(0.07, 0.02, 0.15),
		"bg_bottom": Color(0.24, 0.04, 0.18),
		"panel": Color(0.12, 0.05, 0.20, 0.88),
		"panel_alt": Color(0.19, 0.07, 0.28, 0.92),
		"border": Color(1.0, 0.28, 0.65, 0.90),
		"accent": Color(1.0, 0.30, 0.66),
		"accent_2": Color(1.0, 0.68, 0.14),
		"accent_3": Color(0.12, 0.88, 1.0),
		"text": Color(1.0, 0.96, 0.99),
		"text_dim": Color(0.84, 0.66, 0.84),
		"highway": Color(0.08, 0.02, 0.14, 0.92),
		"highway_edge": Color(1.0, 0.30, 0.66),
		"star_power": Color(0.18, 0.92, 1.0),
		"spotlights": [
			Color(1.0, 0.25, 0.62),
			Color(1.0, 0.65, 0.12),
			Color(0.12, 0.88, 1.0),
			Color(0.72, 0.20, 1.0)
		]
	}
}

const LANE_COLORS: Array[Color] = [
	Color(0.05, 0.98, 0.45), # Green
	Color(1.00, 0.18, 0.32), # Red
	Color(1.00, 0.88, 0.12), # Yellow
	Color(0.12, 0.65, 1.00), # Blue
	Color(1.00, 0.52, 0.08)  # Orange
]

const LANE_NAMES: Array[String] = ["GREEN", "RED", "YELLOW", "BLUE", "ORANGE"]

var current_theme_id: String = "neon_cyber"
var font_display: FontFile
var font_body: FontFile
var font_semi: FontFile

func _ready() -> void:
	if ResourceLoader.exists("res://assets/fonts/Orbitron.ttf"):
		font_display = load("res://assets/fonts/Orbitron.ttf")
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-Bold.ttf"):
		font_body = load("res://assets/fonts/Rajdhani-Bold.ttf")
	if ResourceLoader.exists("res://assets/fonts/Rajdhani-SemiBold.ttf"):
		font_semi = load("res://assets/fonts/Rajdhani-SemiBold.ttf")

func get_theme_data(id: String = "") -> Dictionary:
	var key := id if id != "" else current_theme_id
	if THEMES.has(key):
		return THEMES[key]
	return THEMES["neon_cyber"]

func set_theme(id: String) -> void:
	if THEMES.has(id) and current_theme_id != id:
		current_theme_id = id
		GameState.settings["theme"] = id
		GameState.save_data()
		theme_changed.emit(id)

func make_card_style(bg: Color, border_col: Color, radius: int = 20, border_w: int = 2, glow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	if glow_size > 0:
		sb.shadow_color = Color(border_col.r, border_col.g, border_col.b, 0.34)
		sb.shadow_size = glow_size
	return sb

func style_button(btn: Button, primary: bool = false, custom_col: Color = Color(0, 0, 0, 0)) -> void:
	var t := get_theme_data()
	var col: Color = custom_col if custom_col.a > 0.01 else (t["accent"] if primary else t["border"])
	var bg_norm: Color = Color(col.r * 0.26, col.g * 0.26, col.b * 0.34, 0.96) if primary else t["panel_alt"]
	var bg_hover: Color = Color(col.r * 0.38, col.g * 0.38, col.b * 0.46, 0.98)
	var bg_press: Color = Color(col.r * 0.56, col.g * 0.56, col.b * 0.64, 1.0)
	btn.add_theme_stylebox_override("normal", make_card_style(bg_norm, col, 18, 2, 10 if primary else 0))
	btn.add_theme_stylebox_override("hover", make_card_style(bg_hover, col.lightened(0.25), 18, 2, 14))
	btn.add_theme_stylebox_override("pressed", make_card_style(bg_press, Color.WHITE, 18, 3, 18))
	btn.add_theme_stylebox_override("focus", make_card_style(bg_hover, col.lightened(0.25), 18, 2, 12))
	btn.add_theme_stylebox_override("disabled", make_card_style(Color(0.1, 0.1, 0.12, 0.5), Color(0.3, 0.3, 0.35, 0.4), 18, 1, 0))
	btn.add_theme_color_override("font_color", t["text"])
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	if font_body:
		btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 28)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
