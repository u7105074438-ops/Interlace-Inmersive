# os_theme.gd — Aspecto deliberadamente obsoleto de StellarOS (§13.3, §13.4, §14.8): paletas por aspecto, biseles, tema y dibujo vectorial.
# PROPIETARIO DE: nada (funciones puras de estilo y dibujo; la caché de fuentes es de UITheme).
# ESCUCHA: nada.
class_name OSTheme
extends RefCounted

## El ordenador MEJORA CON EL RANGO: computer_tier (occupations.json, 1..8) → aspecto
## (balance ordenador.aspecto_por_nivel) y banda artística (ordenador.banda_por_nivel):
##  · retro     «StellarOS 98 Budget Edition»: beige de plástico, escritorio verde azulado,
##              biseles gruesos, líneas de barrido de monitor CRT (the_pit).
##  · classic   «StellarOS 2000 Professional»: gris de oficina, títulos azul corporativo (the_specialists).
##  · luna      «StellarOS XP Executive»: esquinas redondeadas, marino y latón (the_power).
##  · sovereign «StellarOS ∞ Sovereign»: mármol, oro atenuado y cuero negro, sin biseles (the_throne).
##  · contrast  alto contraste (§13.10): negro, blanco y amarillo; se impone a cualquier aspecto.
## El papel pintado toma sus colores de la paleta de la banda (data/art_bands.json).
## Contraste deliberado con el HUD limpio del juego (BUILD_NOTES §8).

const SKIN_RETRO := "retro"
const SKIN_CLASSIC := "classic"
const SKIN_LUNA := "luna"
const SKIN_SOVEREIGN := "sovereign"
const SKIN_CONTRAST := "contrast"
const B_SKINS := "ordenador.aspecto_por_nivel"
const B_BANDS := "ordenador.banda_por_nivel"
const DEFAULT_BAND := "the_pit"
const BAND_KEYS: Array[String] = [
	"floor", "wall", "accent", "light", "shadow", "carpet", "furniture", "outline", "window",
]
const FLAG_KEYS: Array[String] = ["bevel", "radius", "scanlines", "product_key", "edition_key"]
const SKINS: Dictionary = {
	SKIN_RETRO: {
		"face": "#d9d1b8", "light": "#fbf7ea", "shadow": "#8e866d", "dark": "#23251f",
		"text": "#1c1d18", "muted": "#5d5a4c", "title_a": "#0f4c5c", "title_b": "#3a8f8a",
		"title_text": "#ffffff", "title_off": "#9b947c", "field": "#fffdf4", "select": "#0f4c5c",
		"select_text": "#ffffff", "accent": "#c8553d", "good": "#2e7d32", "bad": "#b3261e",
		"warn": "#a86b00", "desk": "#2b7a78", "desk_dark": "#17504e", "paper": "#f6e27a",
		"bevel": true, "radius": 0, "scanlines": true,
		"product_key": "OS_PRODUCT_RETRO", "edition_key": "OS_EDITION_RETRO",
	},
	SKIN_CLASSIC: {
		"face": "#d4d0c8", "light": "#ffffff", "shadow": "#808080", "dark": "#1b2632",
		"text": "#111111", "muted": "#4f5864", "title_a": "#0a246a", "title_b": "#3a6ea5",
		"title_text": "#ffffff", "title_off": "#9aa4b0", "field": "#ffffff", "select": "#0a246a",
		"select_text": "#ffffff", "accent": "#1f6fd1", "good": "#1e7b34", "bad": "#b3261e",
		"warn": "#9a6700", "desk": "#3a5a82", "desk_dark": "#1b2632", "paper": "#f7e98a",
		"bevel": true, "radius": 0, "scanlines": false,
		"product_key": "OS_PRODUCT_CLASSIC", "edition_key": "OS_EDITION_CLASSIC",
	},
	SKIN_LUNA: {
		"face": "#ece9d8", "light": "#ffffff", "shadow": "#aca899", "dark": "#1a120b",
		"text": "#1a120b", "muted": "#5b5446", "title_a": "#1f2d4e", "title_b": "#4a6a9e",
		"title_text": "#fff6dc", "title_off": "#8e9bb3", "field": "#ffffff", "select": "#2f4a7a",
		"select_text": "#ffffff", "accent": "#b8923a", "good": "#2e7d32", "bad": "#a8261e",
		"warn": "#8f6a12", "desk": "#1f2d4e", "desk_dark": "#0e1628", "paper": "#f4e3a1",
		"bevel": false, "radius": 7, "scanlines": false,
		"product_key": "OS_PRODUCT_LUNA", "edition_key": "OS_EDITION_LUNA",
	},
	SKIN_SOVEREIGN: {
		"face": "#f7f5f0", "light": "#fffdf8", "shadow": "#d9d3c6", "dark": "#1c1c1f",
		"text": "#1c1c1f", "muted": "#6e695f", "title_a": "#1c1c1f", "title_b": "#2a2a2e",
		"title_text": "#e8d9ae", "title_off": "#6e695f", "field": "#fffdf8", "select": "#b89b5e",
		"select_text": "#1c1c1f", "accent": "#b89b5e", "good": "#3d7a4f", "bad": "#9e2b25",
		"warn": "#8a6d2f", "desk": "#e8e5de", "desk_dark": "#cbc4b4", "paper": "#fbf6e6",
		"bevel": false, "radius": 12, "scanlines": false,
		"product_key": "OS_PRODUCT_SOVEREIGN", "edition_key": "OS_EDITION_SOVEREIGN",
	},
	SKIN_CONTRAST: {
		"face": "#000000", "light": "#ffffff", "shadow": "#ffffff", "dark": "#ffffff",
		"text": "#ffffff", "muted": "#e6e6e6", "title_a": "#000000", "title_b": "#000000",
		"title_text": "#ffe600", "title_off": "#b0b0b0", "field": "#000000", "select": "#ffe600",
		"select_text": "#000000", "accent": "#ffe600", "good": "#3dff8a", "bad": "#ff5c5c",
		"warn": "#ffcc00", "desk": "#000000", "desk_dark": "#000000", "paper": "#000000",
		"bevel": false, "radius": 0, "scanlines": false,
		"product_key": "OS_PRODUCT_RETRO", "edition_key": "OS_EDITION_CONTRAST",
	},
}
## Proporciones tipográficas respecto al tamaño base de UITheme (tamaño de texto del jugador).
const RATIO_BODY := 0.9
const RATIO_SMALL := 0.74
const RATIO_TITLE := 1.0
const RATIO_BIG := 1.5
const RATIO_HUGE := 2.4
const RATIO_MONO := 0.82
## Grosor de un escalón de bisel respecto al tamaño base (2 px a 24 px).
const BEVEL_PER_BASE := 0.085
const V_TITLE := "OSTitle"
const V_HEADING := "OSHeading"
const V_SMALL := "OSSmall"
const V_BIG := "OSBig"
const V_HUGE := "OSHuge"
const V_MONO := "OSMono"
const V_MUTED := "OSMuted"
const V_ON_DARK := "OSOnDark"
const V_SUNKEN := "OSSunken"
const V_RAISED := "OSRaised"
const V_ROW := "OSRow"
const V_ROW_SELECTED := "OSRowSelected"
const V_PRIMARY := "OSPrimary"
const V_DANGER := "OSDanger"
const V_FLAT := "OSFlat"
const V_TASK := "OSTaskButton"


## Caja de estilo biselada (botones, ventanas y campos al estilo de 1998).
class BevelBox extends StyleBox:
	var face: Color = Color.WHITE
	var light: Color = Color.WHITE
	var hilite: Color = Color.WHITE
	var shadow: Color = Color.GRAY
	var dark: Color = Color.BLACK
	var sunken: bool = false
	var width: float = 2.0
	var draw_face: bool = true

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		if draw_face:
			RenderingServer.canvas_item_add_rect(to_canvas_item, rect, face)
		var tl_out: Color = shadow if sunken else hilite
		var br_out: Color = hilite if sunken else dark
		var tl_in: Color = dark if sunken else light
		var br_in: Color = light if sunken else shadow
		_edge(to_canvas_item, rect, tl_out, br_out)
		_edge(to_canvas_item, rect.grow(-width), tl_in, br_in)

	func _edge(ci: RID, r: Rect2, tl: Color, br: Color) -> void:
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, width)), tl)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(width, r.size.y)), tl)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - width, r.size.x, width), br)
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.end.x - width, r.position.y, width, r.size.y), br)


# ─── Aspecto por nivel del equipo ─────────────────────────────────

## Número de niveles de equipo definidos en balance (8).
static func tier_count() -> int:
	return maxi(UITheme.tune_array(B_SKINS).size(), 1)


static func clamp_tier(tier: int) -> int:
	return clampi(tier, 1, tier_count())


static func skin_for_tier(tier: int) -> String:
	var skins: Array = UITheme.tune_array(B_SKINS)
	if skins.is_empty():
		return SKIN_RETRO
	var skin: String = str(skins[clamp_tier(tier) - 1])
	return skin if SKINS.has(skin) else SKIN_RETRO


static func band_for_tier(tier: int) -> String:
	var bands: Array = UITheme.tune_array(B_BANDS)
	return str(bands[clamp_tier(tier) - 1]) if not bands.is_empty() else DEFAULT_BAND


## Valor de un array *_por_nivel de balance para el nivel (0 si falta).
static func per_tier(path: String, tier: int) -> float:
	var values: Array = UITheme.tune_array(path)
	if values.is_empty():
		return 0.0
	var v: Variant = values[clampi(tier - 1, 0, values.size() - 1)]
	return float(v) if (v is float or v is int) else 0.0


## Paleta completa: colores del aspecto + banderas + colores de la banda ("band_<clave>").
## Con alto contraste (UITheme) se impone el aspecto contrast.
static func palette_for_tier(tier: int) -> Dictionary:
	var skin: String = SKIN_CONTRAST if UITheme.current_high_contrast else skin_for_tier(tier)
	var pal: Dictionary = palette(skin, band_for_tier(tier))
	pal["tier"] = clamp_tier(tier)
	return pal


static func palette(skin_id: String, band_id: String) -> Dictionary:
	var src: Dictionary = SKINS.get(skin_id, SKINS[SKIN_RETRO])
	var pal: Dictionary = {"skin": skin_id, "band": band_id}
	for key: String in src:
		pal[key] = src[key] if FLAG_KEYS.has(key) else Color(str(src[key]))
	var band_pal: Dictionary = _band_palette(band_id)
	for key: String in BAND_KEYS:
		pal["band_" + key] = Color(str(band_pal.get(key, src.get("desk", "#808080"))))
	return pal


static func _band_palette(band_id: String) -> Dictionary:
	var band: Dictionary = Database.get_art_band(band_id)
	var pal: Variant = band.get("palette", {})
	return pal if pal is Dictionary else {}


static func col(pal: Dictionary, key: String) -> Color:
	var v: Variant = pal.get(key)
	return v if v is Color else Color.MAGENTA


static func bevel_width(base: int) -> float:
	return maxf(1.0, roundf(float(base) * BEVEL_PER_BASE))


# ─── Tema ─────────────────────────────────────────────────────────

## Tema de Godot para todo el ordenador. `base` = tamaño base de texto de UITheme.
static func build(pal: Dictionary, base: int) -> Theme:
	var t: Theme = Theme.new()
	t.default_font = UITheme.font(UITheme.FONT_REGULAR)
	t.default_font_size = roundi(base * RATIO_BODY)
	_labels(t, pal, base)
	_buttons(t, pal, base)
	_fields(t, pal, base)
	_panels(t, pal, base)
	_scrollbars(t, pal, base)
	_tabs(t, pal, base)
	return t


static func _labels(t: Theme, pal: Dictionary, base: int) -> void:
	t.set_color("font_color", "Label", col(pal, "text"))
	var specs: Array = [
		[V_TITLE, UITheme.FONT_BOLD, RATIO_TITLE, "text"],
		[V_HEADING, UITheme.FONT_SEMIBOLD, RATIO_BODY, "text"],
		[V_SMALL, UITheme.FONT_REGULAR, RATIO_SMALL, "text"],
		[V_MUTED, UITheme.FONT_REGULAR, RATIO_SMALL, "muted"],
		[V_BIG, UITheme.FONT_BOLD, RATIO_BIG, "text"],
		[V_HUGE, UITheme.FONT_BOLD, RATIO_HUGE, "text"],
		[V_MONO, UITheme.FONT_MONO, RATIO_MONO, "text"],
		[V_ON_DARK, UITheme.FONT_SEMIBOLD, RATIO_BODY, "title_text"],
	]
	for spec: Array in specs:
		var v: String = spec[0]
		t.set_type_variation(v, "Label")
		t.set_font("font", v, UITheme.font(str(spec[1])))
		t.set_font_size("font_size", v, roundi(base * float(spec[2])))
		t.set_color("font_color", v, col(pal, str(spec[3])))


static func _buttons(t: Theme, pal: Dictionary, base: int) -> void:
	var pad: Vector2 = Vector2(base * 0.6, base * 0.28)
	_button_type(t, "Button", pal, box(pal, "raised", base, pad), box(pal, "hover", base, pad),
			box(pal, "pressed", base, pad), col(pal, "text"))
	t.set_font("font", "Button", UITheme.font(UITheme.FONT_SEMIBOLD))
	t.set_font_size("font_size", "Button", roundi(base * RATIO_BODY))
	t.set_stylebox("disabled", "Button", box(pal, "disabled", base, pad))
	t.set_color("font_disabled_color", "Button", col(pal, "shadow") if pal.get("bevel") \
			else col(pal, "muted"))
	t.set_stylebox("focus", "Button", box(pal, "focus", base, pad))
	_variant(t, V_PRIMARY, _tinted(pal, col(pal, "select"), col(pal, "select_text")), base, pad)
	var danger_text: Color = Color.WHITE if pal.get("skin") != SKIN_CONTRAST else Color.BLACK
	_variant(t, V_DANGER, _tinted(pal, col(pal, "bad"), danger_text), base, pad)
	var flat: StyleBoxEmpty = StyleBoxEmpty.new()
	t.set_type_variation(V_FLAT, "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, V_FLAT, flat)
	t.set_color("font_color", V_FLAT, col(pal, "select"))
	t.set_color("font_hover_color", V_FLAT, col(pal, "accent"))
	_variant(t, V_TASK, pal, base, Vector2(base * 0.45, base * 0.2))


## Copia de la paleta con otra cara (botones primario/peligro). En los aspectos planos la luz
## iguala a la cara para que el relleno no se desvaiga.
static func _tinted(pal: Dictionary, face: Color, text: Color) -> Dictionary:
	var out: Dictionary = pal.duplicate()
	out["face"] = face
	out["text"] = text
	if not pal.get("bevel", false):
		out["light"] = face
	return out


static func _variant(t: Theme, v: String, pal: Dictionary, base: int, pad: Vector2) -> void:
	t.set_type_variation(v, "Button")
	_button_type(t, v, pal, box(pal, "raised", base, pad), box(pal, "hover", base, pad),
			box(pal, "pressed", base, pad), col(pal, "text"))


static func _button_type(t: Theme, type_name: String, pal: Dictionary, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, text: Color) -> void:
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, hover)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("hover_pressed", type_name, pressed)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color"]:
		t.set_color(state, type_name, text)
	t.set_color("icon_normal_color", type_name, col(pal, "text"))


static func _fields(t: Theme, pal: Dictionary, base: int) -> void:
	var pad: Vector2 = Vector2(base * 0.4, base * 0.3)
	for type_name: String in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type_name, box(pal, "field", base, pad))
		t.set_stylebox("focus", type_name, box(pal, "field", base, pad))
		t.set_stylebox("read_only", type_name, box(pal, "field", base, pad))
		t.set_color("font_color", type_name, col(pal, "text"))
		t.set_color("font_readonly_color", type_name, col(pal, "text"))
		t.set_color("caret_color", type_name, col(pal, "text"))
		t.set_color("selection_color", type_name, Color(col(pal, "select"), 0.45))
		t.set_color("font_placeholder_color", type_name, col(pal, "muted"))
		t.set_font_size("font_size", type_name, roundi(base * RATIO_BODY))
	t.set_type_variation("OSPaperEdit", "TextEdit")
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	empty.content_margin_left = base * 2.2
	empty.content_margin_top = base * 0.1
	for state: String in ["normal", "focus", "read_only"]:
		t.set_stylebox(state, "OSPaperEdit", empty)
	t.set_color("font_color", "OSPaperEdit", Color("#1d2a57") if pal.get("skin") != SKIN_CONTRAST \
			else Color.WHITE)
	t.set_constant("line_spacing", "OSPaperEdit", roundi(base * 0.42))


static func _panels(t: Theme, pal: Dictionary, base: int) -> void:
	var pad: Vector2 = Vector2(base * 0.5, base * 0.4)
	t.set_stylebox("panel", "PanelContainer", box(pal, "window", base, pad))
	var specs: Dictionary = {V_SUNKEN: "field", V_RAISED: "window", V_ROW: "row",
			V_ROW_SELECTED: "row_selected"}
	for v: String in specs:
		t.set_type_variation(v, "PanelContainer")
		var row_pad: Vector2 = Vector2(base * 0.45, base * 0.3) if v.begins_with("OSRow") else pad
		t.set_stylebox("panel", v, box(pal, str(specs[v]), base, row_pad))
	t.set_constant("separation", "HBoxContainer", roundi(base * 0.4))
	t.set_constant("separation", "VBoxContainer", roundi(base * 0.3))
	t.set_color("font_color", "TooltipLabel", col(pal, "text"))
	t.set_stylebox("panel", "TooltipPanel", box(pal, "tooltip", base, pad))


static func _scrollbars(t: Theme, pal: Dictionary, base: int) -> void:
	var w: float = base * 0.7
	for type_name: String in ["VScrollBar", "HScrollBar"]:
		var track: StyleBoxFlat = StyleBoxFlat.new()
		track.bg_color = col(pal, "face").lerp(col(pal, "light"), 0.5)
		track.content_margin_left = w * 0.5
		track.content_margin_right = w * 0.5
		track.content_margin_top = w * 0.5
		track.content_margin_bottom = w * 0.5
		t.set_stylebox("scroll", type_name, track)
		var grab: StyleBox = box(pal, "raised", base, Vector2(w * 0.5, w * 0.5))
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			t.set_stylebox(state, type_name, grab)


static func _tabs(t: Theme, pal: Dictionary, base: int) -> void:
	var pad: Vector2 = Vector2(base * 0.6, base * 0.25)
	t.set_stylebox("tab_selected", "TabBar", box(pal, "tab_on", base, pad))
	t.set_stylebox("tab_unselected", "TabBar", box(pal, "tab_off", base, pad))
	t.set_stylebox("tab_hovered", "TabBar", box(pal, "tab_off", base, pad))
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", col(pal, "text"))
	t.set_color("font_unselected_color", "TabBar", col(pal, "muted"))
	t.set_color("font_hovered_color", "TabBar", col(pal, "text"))
	t.set_font("font", "TabBar", UITheme.font(UITheme.FONT_SEMIBOLD))
	t.set_font_size("font_size", "TabBar", roundi(base * RATIO_BODY))


# ─── Cajas de estilo ──────────────────────────────────────────────

## kind: raised, hover, pressed, disabled, focus, field, window, row, row_selected, tab_on,
## tab_off, tooltip. Biselada en los aspectos retro/classic; plana y redondeada en el resto.
static func box(pal: Dictionary, kind: String, base: int, pad: Vector2) -> StyleBox:
	var sb: StyleBox = _bevel_box(pal, kind, base) if pal.get("bevel", false) \
			else _flat_box(pal, kind, base)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb


static func _bevel_box(pal: Dictionary, kind: String, base: int) -> StyleBox:
	if kind in ["row", "focus"]:
		return _flat_box(pal, kind, base)
	var b: BevelBox = BevelBox.new()
	b.width = bevel_width(base)
	b.face = col(pal, "face")
	b.light = col(pal, "face").lerp(col(pal, "light"), 0.55)
	b.hilite = col(pal, "light")
	b.shadow = col(pal, "shadow")
	b.dark = col(pal, "dark")
	match kind:
		"hover":
			b.face = col(pal, "face").lerp(col(pal, "light"), 0.25)
		"pressed", "field", "tab_off":
			b.sunken = kind != "tab_off"
			b.face = col(pal, "field") if kind == "field" else col(pal, "face").darkened(0.06)
		"row_selected":
			b.face = col(pal, "select").lerp(col(pal, "field"), 0.78)
			b.sunken = true
		"tooltip":
			b.face = col(pal, "paper")
	return b


static func _flat_box(pal: Dictionary, kind: String, base: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var radius: int = int(pal.get("radius", 0))
	var contrast: bool = pal.get("skin") == SKIN_CONTRAST
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(maxi(1, roundi(bevel_width(base) * (1.5 if contrast else 0.5))))
	sb.border_color = col(pal, "shadow").darkened(0.15)
	sb.bg_color = col(pal, "face").lerp(col(pal, "light"), 0.6)
	sb.anti_aliasing = radius > 0
	_flat_kind(sb, pal, kind, contrast)
	return sb


static func _flat_kind(sb: StyleBoxFlat, pal: Dictionary, kind: String, contrast: bool) -> void:
	match kind:
		"hover":
			sb.bg_color = col(pal, "face").lerp(col(pal, "light"), 0.6).lightened(0.08)
			sb.border_color = col(pal, "accent")
		"pressed":
			sb.bg_color = col(pal, "face").darkened(0.08)
		"disabled":
			sb.bg_color = col(pal, "face")
			sb.border_color = col(pal, "shadow")
		"focus":
			sb.draw_center = false
			sb.border_color = col(pal, "accent") if not contrast else col(pal, "select")
		"field":
			sb.bg_color = col(pal, "field")
			sb.border_color = col(pal, "shadow").darkened(0.25)
		"window", "tab_on":
			sb.bg_color = col(pal, "face")
		"row":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0, 0, 0, 0)
		"row_selected":
			sb.bg_color = col(pal, "select").lerp(col(pal, "field"), 0.72 if not contrast else 0.0)
			sb.border_color = col(pal, "select")
		"tab_off":
			sb.bg_color = col(pal, "face").darkened(0.05)
		"tooltip":
			sb.bg_color = col(pal, "paper")


# ─── Dibujo: marcos, barras de título, papel pintado ──────────────

## Rectángulo biselado dibujado a mano (controles propios).
static func draw_bevel(ci: CanvasItem, r: Rect2, pal: Dictionary, sunken: bool, base: int) -> void:
	if not pal.get("bevel", false):
		draw_panel(ci, r, pal, col(pal, "field") if sunken else col(pal, "face"))
		return
	var b: BevelBox = _bevel_box(pal, "field" if sunken else "raised", base) as BevelBox
	b.draw(ci.get_canvas_item(), r)


## Panel plano con borde (aspectos sin bisel), esquinas según el aspecto.
static func draw_panel(ci: CanvasItem, r: Rect2, pal: Dictionary, fill: Color) -> void:
	var radius: float = float(pal.get("radius", 0))
	var pts: PackedVector2Array = UITheme.rounded_rect_points(r, radius) if radius > 0.0 \
			else PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
					Vector2(r.position.x, r.end.y)])
	ci.draw_colored_polygon(pts, fill)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col(pal, "shadow").darkened(0.2), 1.5, true)


## Degradado horizontal (barras de título, papel pintado).
static func draw_hgradient(ci: CanvasItem, r: Rect2, a: Color, b: Color) -> void:
	var pts: PackedVector2Array = [r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]
	ci.draw_polygon(pts, PackedColorArray([a, b, b, a]))


static func draw_vgradient(ci: CanvasItem, r: Rect2, a: Color, b: Color) -> void:
	var pts: PackedVector2Array = [r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]
	ci.draw_polygon(pts, PackedColorArray([a, a, b, b]))


static func draw_title_bar(ci: CanvasItem, r: Rect2, pal: Dictionary, active: bool) -> void:
	var a: Color = col(pal, "title_a") if active else col(pal, "title_off")
	var b: Color = col(pal, "title_b") if active else col(pal, "title_off").lightened(0.2)
	var radius: float = float(pal.get("radius", 0))
	if radius <= 0.0:
		draw_hgradient(ci, r, a, b)
		return
	var pts: PackedVector2Array = top_rounded_points(r, radius)
	var colors: PackedColorArray = PackedColorArray()
	for p: Vector2 in pts:
		colors.append(a.lerp(b, clampf((p.x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)))
	ci.draw_polygon(pts, colors)
	if pal.get("skin") == SKIN_SOVEREIGN or pal.get("skin") == SKIN_LUNA:
		ci.draw_line(Vector2(r.position.x + radius, r.end.y), Vector2(r.end.x - radius, r.end.y),
				col(pal, "accent"), 2.0)


## Papel pintado del escritorio según el aspecto, con la paleta de la banda.
static func draw_wallpaper(ci: CanvasItem, r: Rect2, pal: Dictionary) -> void:
	match str(pal.get("skin", SKIN_RETRO)):
		SKIN_CLASSIC:
			_wall_classic(ci, r, pal)
		SKIN_LUNA:
			_wall_luna(ci, r, pal)
		SKIN_SOVEREIGN:
			_wall_sovereign(ci, r, pal)
		SKIN_CONTRAST:
			ci.draw_rect(r, Color.BLACK)
		_:
			_wall_retro(ci, r, pal)


static func _wall_retro(ci: CanvasItem, r: Rect2, pal: Dictionary) -> void:
	ci.draw_rect(r, col(pal, "desk"))
	var step: float = r.size.y / 9.0
	var tile: Color = Color(col(pal, "band_light"), 0.07)
	for i: int in range(-10, 24):
		var x: float = r.position.x + i * step * 1.6
		ci.draw_line(Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y), tile, step * 0.35)
	var c: Vector2 = r.get_center() + Vector2(r.size.x * 0.08, -r.size.y * 0.04)
	var rad: float = r.size.y * 0.2
	draw_logo(ci, c, rad, Color(col(pal, "band_light"), 0.22), Color(col(pal, "desk_dark"), 0.6))
	_wall_caption(ci, c + Vector2(0, rad * 1.55), rad, pal, "OS_WALL_SLOGAN_RETRO")


static func _wall_classic(ci: CanvasItem, r: Rect2, pal: Dictionary) -> void:
	draw_vgradient(ci, r, col(pal, "band_accent").darkened(0.25), col(pal, "band_carpet").darkened(0.35))
	var c: Vector2 = r.get_center() + Vector2(r.size.x * 0.08, -r.size.y * 0.05)
	var rad: float = r.size.y * 0.19
	for i: int in 5:
		ci.draw_arc(c, rad * (1.6 + i * 0.55), 0.0, TAU, 96, Color(1, 1, 1, 0.05), 2.0, true)
	draw_logo(ci, c, rad, Color(col(pal, "band_light"), 0.3), Color(col(pal, "band_outline"), 0.5))
	_wall_caption(ci, c + Vector2(0, rad * 1.55), rad, pal, "OS_WALL_SLOGAN_CLASSIC")


static func _wall_luna(ci: CanvasItem, r: Rect2, pal: Dictionary) -> void:
	var horizon: float = r.position.y + r.size.y * 0.66
	draw_vgradient(ci, Rect2(r.position, Vector2(r.size.x, horizon - r.position.y)),
			col(pal, "band_carpet").darkened(0.3), col(pal, "band_window"))
	var sun: Vector2 = Vector2(r.position.x + r.size.x * 0.7, horizon - r.size.y * 0.06)
	ci.draw_circle(sun, r.size.y * 0.11, Color(col(pal, "band_accent"), 0.9))
	ci.draw_circle(sun, r.size.y * 0.16, Color(col(pal, "band_light"), 0.15))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("skyline")
	var x: float = r.position.x
	while x < r.end.x:
		var w: float = r.size.x * rng.randf_range(0.03, 0.07)
		var h: float = r.size.y * rng.randf_range(0.08, 0.36)
		ci.draw_rect(Rect2(x, horizon - h, w * 0.94, h), col(pal, "band_shadow").lerp(col(pal, "band_carpet"), 0.3))
		x += w
	draw_vgradient(ci, Rect2(r.position.x, horizon, r.size.x, r.end.y - horizon),
			col(pal, "band_floor"), col(pal, "band_shadow"))
	ci.draw_line(Vector2(r.position.x, horizon), Vector2(r.end.x, horizon), col(pal, "band_accent"), 3.0)


static func _wall_sovereign(ci: CanvasItem, r: Rect2, pal: Dictionary) -> void:
	draw_vgradient(ci, r, col(pal, "band_wall"), col(pal, "band_floor"))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("marble")
	for i: int in 14:
		var p: Vector2 = r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		var pts: PackedVector2Array = [p]
		for _s: int in 8:
			p += Vector2(rng.randf_range(20.0, 90.0), rng.randf_range(-40.0, 40.0))
			pts.append(p)
		var vein: Color = col(pal, "band_accent") if i % 4 == 0 else col(pal, "band_shadow")
		ci.draw_polyline(pts, Color(vein, 0.18 if i % 4 else 0.35), 1.5 + (i % 3), true)
	var c: Vector2 = r.get_center() + Vector2(r.size.x * 0.08, -r.size.y * 0.04)
	draw_logo(ci, c, r.size.y * 0.12, Color(col(pal, "band_accent"), 0.35), Color(col(pal, "band_accent"), 0.7))
	_wall_caption(ci, c + Vector2(0, r.size.y * 0.2), r.size.y * 0.12, pal, "OS_WALL_SLOGAN_SOVEREIGN")


static func _wall_caption(ci: CanvasItem, pos: Vector2, rad: float, pal: Dictionary, key: String) -> void:
	var f: Font = UITheme.font(UITheme.FONT_BOLD)
	var size: int = maxi(12, roundi(rad * 0.22))
	var text: String = String(TranslationServer.translate(key))
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ink: Color = col(pal, "band_accent") if pal.get("skin") == SKIN_SOVEREIGN \
			else Color(col(pal, "band_light"), 0.45)
	ci.draw_string(f, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


## Líneas de barrido de monitor CRT y viñeta (solo el aspecto retro).
static func draw_scanlines(ci: CanvasItem, r: Rect2, base: int) -> void:
	var gap: float = maxf(3.0, roundf(base * 0.16))
	var y: float = r.position.y
	var line: Color = Color(0, 0, 0, 0.07)
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line, 1.0)
		y += gap
	var edge: float = r.size.y * 0.06
	draw_vgradient(ci, Rect2(r.position, Vector2(r.size.x, edge)), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0))
	draw_vgradient(ci, Rect2(r.position.x, r.end.y - edge, r.size.x, edge), Color(0, 0, 0, 0), Color(0, 0, 0, 0.2))


## Logotipo de Stellar Sell: estrella de cinco puntas con la estela de una zapatilla.
static func draw_logo(ci: CanvasItem, c: Vector2, r: float, fill: Color, ink: Color) -> void:
	var swoosh: PackedVector2Array = PackedVector2Array()
	for i: int in 25:
		var t: float = float(i) / 24.0
		swoosh.append(c + Vector2(-r * 1.25 + t * r * 2.5, r * 0.55 - sin(t * PI) * r * 0.35 + t * r * 0.25))
	for i: int in range(24, -1, -1):
		var t: float = float(i) / 24.0
		swoosh.append(c + Vector2(-r * 1.25 + t * r * 2.5, r * 0.7 - sin(t * PI) * r * 0.2 + t * r * 0.1))
	ci.draw_colored_polygon(swoosh, fill)
	var star: PackedVector2Array = star_points(c - Vector2(0, r * 0.12), r * 0.8, r * 0.34)
	ci.draw_colored_polygon(star, fill)
	var closed: PackedVector2Array = star.duplicate()
	closed.append(star[0])
	ci.draw_polyline(closed, ink, maxf(1.5, r * 0.035), true)


static func star_points(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


# ─── Iconos de aplicación y de archivo ────────────────────────────

## Icono vectorial plano con contorno dentro de `r`. Ids: mail, notebook, personnel, assist, portal,
## files, market, not_found, trash, hourglass, lock, idea, doc, report, personal, warning, user,
## start, snail, drop, shoe, check, cross, folder, star.
static func draw_icon(ci: CanvasItem, icon: String, r: Rect2, pal: Dictionary) -> void:
	var ink: Color = Color("#1a1a1a") if pal.get("skin") != SKIN_CONTRAST else Color.WHITE
	var w: float = maxf(1.5, r.size.x * 0.055)
	if _icons_apps(ci, icon, r, ink, w, pal):
		return
	if _icons_files(ci, icon, r, ink, w, pal):
		return
	_icons_misc(ci, icon, r, ink, w, pal)


static func _icons_apps(ci: CanvasItem, icon: String, r: Rect2, ink: Color, w: float, pal: Dictionary) -> bool:
	match icon:
		"mail":
			_icon_mail(ci, r, ink, w)
		"notebook":
			_icon_notebook(ci, r, ink, w)
		"personnel":
			_icon_personnel(ci, r, ink, w)
		"assist":
			_icon_assist(ci, r, ink, w)
		"portal":
			_icon_portal(ci, r, ink, w)
		"files", "folder":
			_icon_folder(ci, r, ink, w)
		"market":
			_icon_market(ci, r, ink, w)
		"not_found":
			_icon_not_found(ci, r, ink, w, pal)
		_:
			return false
	return true


static func _icons_files(ci: CanvasItem, icon: String, r: Rect2, ink: Color, w: float, pal: Dictionary) -> bool:
	match icon:
		"doc":
			_icon_page(ci, r, ink, w, Color("#fbfaf4"))
			_page_lines(ci, r, ink, 4)
		"report":
			_icon_page(ci, r, ink, w, Color("#fbfaf4"))
			_icon_bars(ci, r, ink, w)
		"personal":
			_icon_page(ci, r, ink, w, Color("#fdf1f4"))
			_icon_heart(ci, _sub(r, 0.3, 0.4, 0.4, 0.35), Color("#e05a74"), ink, w)
		"idea":
			_icon_bulb(ci, r, ink, w)
		"trash":
			_icon_trash(ci, r, ink, w)
		"lock":
			_icon_lock(ci, r, ink, w)
		_:
			return false
	return true


static func _icons_misc(ci: CanvasItem, icon: String, r: Rect2, ink: Color, w: float, pal: Dictionary) -> void:
	match icon:
		"hourglass":
			draw_hourglass(ci, r, ink, 0.5)
		"warning":
			_icon_warning(ci, r, ink, w)
		"user":
			_icon_user(ci, r, ink, w, col(pal, "select"))
		"start", "star":
			var star: PackedVector2Array = star_points(r.get_center(), r.size.x * 0.46, r.size.x * 0.2)
			_shape(ci, star, Color("#f5c542"), ink, w)
		"snail":
			_icon_snail(ci, r, ink, w)
		"drop":
			_icon_drop(ci, r, ink, w)
		"shoe":
			_icon_shoe(ci, r, ink, w)
		"check":
			ci.draw_polyline(_pts(r, [[0.18, 0.55], [0.42, 0.78], [0.84, 0.24]]), col(pal, "good"), w * 2.2, true)
		"cross":
			ci.draw_line(_p(r, 0.22, 0.22), _p(r, 0.78, 0.78), col(pal, "bad"), w * 2.2, true)
			ci.draw_line(_p(r, 0.78, 0.22), _p(r, 0.22, 0.78), col(pal, "bad"), w * 2.2, true)
		_:
			_icon_page(ci, r, ink, w, Color("#fbfaf4"))


static func _icon_mail(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var body: Rect2 = _sub(r, 0.06, 0.2, 0.88, 0.62)
	_shape(ci, _rect_pts(body), Color("#f4f1e6"), ink, w)
	ci.draw_polyline(_pts(r, [[0.06, 0.2], [0.5, 0.56], [0.94, 0.2]]), ink, w, true)
	ci.draw_line(_p(r, 0.06, 0.82), _p(r, 0.4, 0.5), Color(ink, 0.5), w * 0.7, true)
	ci.draw_line(_p(r, 0.94, 0.82), _p(r, 0.6, 0.5), Color(ink, 0.5), w * 0.7, true)
	for i: int in 6:
		var x: float = 0.1 + i * 0.14
		ci.draw_line(_p(r, x, 0.78), _p(r, x + 0.06, 0.78), Color("#c8553d") if i % 2 == 0 else Color("#2f6db5"), w * 1.4)
	ci.draw_circle(_p(r, 0.5, 0.56), r.size.x * 0.08, Color("#c8553d"))


static func _icon_notebook(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var page: Rect2 = _sub(r, 0.14, 0.12, 0.66, 0.8)
	_shape(ci, _rect_pts(page), Color("#f6e27a"), ink, w)
	for i: int in 4:
		var y: float = 0.36 + i * 0.13
		ci.draw_line(_p(r, 0.2, y), _p(r, 0.74, y), Color("#6f8fc9"), w * 0.7)
	ci.draw_line(_p(r, 0.28, 0.2), _p(r, 0.28, 0.9), Color("#d9534f"), w * 0.7)
	for i: int in 4:
		ci.draw_arc(_p(r, 0.24 + i * 0.15, 0.12), r.size.x * 0.045, PI, TAU, 8, ink, w, true)
	var pencil: PackedVector2Array = _pts(r, [[0.62, 0.86], [0.92, 0.3], [0.99, 0.35], [0.69, 0.91]])
	_shape(ci, pencil, Color("#f2a33a"), ink, w * 0.8)
	_shape(ci, _pts(r, [[0.62, 0.86], [0.69, 0.91], [0.6, 0.97]]), Color("#f3d9b1"), ink, w * 0.6)


static func _icon_personnel(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var folder: Rect2 = _sub(r, 0.06, 0.2, 0.88, 0.7)
	_shape(ci, _pts(r, [[0.06, 0.2], [0.36, 0.2], [0.42, 0.12], [0.62, 0.12], [0.62, 0.2]]), Color("#caa55a"), ink, w)
	_shape(ci, _rect_pts(folder), Color("#e3c07a"), ink, w)
	var card: Rect2 = _sub(r, 0.16, 0.3, 0.68, 0.5)
	_shape(ci, _rect_pts(card), Color("#fbfaf4"), ink, w * 0.8)
	var photo: Rect2 = _sub(r, 0.22, 0.36, 0.22, 0.34)
	ci.draw_rect(photo, Color("#9fc3d6"))
	ci.draw_circle(_p(r, 0.33, 0.47), r.size.x * 0.055, Color("#e8b98f"))
	ci.draw_rect(_sub(r, 0.26, 0.56, 0.14, 0.14), Color("#3b4a6b"))
	for i: int in 3:
		ci.draw_line(_p(r, 0.5, 0.42 + i * 0.1), _p(r, 0.78, 0.42 + i * 0.1), Color(ink, 0.6), w * 0.8)


static func _icon_assist(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	ci.draw_line(_p(r, 0.5, 0.22), _p(r, 0.5, 0.1), ink, w)
	_shape(ci, star_points(_p(r, 0.5, 0.08), r.size.x * 0.09, r.size.x * 0.04), Color("#f5c542"), ink, w * 0.6)
	var head: Rect2 = _sub(r, 0.14, 0.22, 0.72, 0.6)
	_shape(ci, UITheme.rounded_rect_points(head, r.size.x * 0.14), Color("#7fd1c7"), ink, w)
	var visor: Rect2 = _sub(r, 0.24, 0.34, 0.52, 0.24)
	_shape(ci, UITheme.rounded_rect_points(visor, r.size.x * 0.08), Color("#16323a"), ink, w * 0.6)
	ci.draw_circle(_p(r, 0.38, 0.46), r.size.x * 0.05, Color("#8ff5ff"))
	ci.draw_circle(_p(r, 0.62, 0.46), r.size.x * 0.05, Color("#8ff5ff"))
	ci.draw_arc(_p(r, 0.5, 0.64), r.size.x * 0.12, 0.2, PI - 0.2, 12, ink, w, true)
	_shape(ci, star_points(_p(r, 0.9, 0.3), r.size.x * 0.09, r.size.x * 0.035), Color("#fff3a6"), ink, w * 0.5)
	_shape(ci, star_points(_p(r, 0.1, 0.84), r.size.x * 0.07, r.size.x * 0.03), Color("#fff3a6"), ink, w * 0.5)


static func _icon_portal(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	ci.draw_polyline(_pts(r, [[0.5, 0.34], [0.5, 0.46], [0.16, 0.46], [0.16, 0.6]]), ink, w, true)
	ci.draw_line(_p(r, 0.5, 0.46), _p(r, 0.5, 0.6), ink, w)
	ci.draw_polyline(_pts(r, [[0.5, 0.46], [0.84, 0.46], [0.84, 0.6]]), ink, w, true)
	_shape(ci, _rect_pts(_sub(r, 0.32, 0.1, 0.36, 0.24)), Color("#f5c542"), ink, w)
	_shape(ci, _rect_pts(_sub(r, 0.02, 0.6, 0.28, 0.22)), Color("#9fc3d6"), ink, w)
	_shape(ci, _rect_pts(_sub(r, 0.36, 0.6, 0.28, 0.22)), Color("#9fc3d6"), ink, w)
	var vacant: Rect2 = _sub(r, 0.7, 0.6, 0.28, 0.22)
	ci.draw_rect(vacant, Color("#fff4f2"))
	ci.draw_rect(vacant, Color("#c8553d"), false, w)
	ci.draw_string(UITheme.font(UITheme.FONT_BOLD), vacant.position + Vector2(vacant.size.x * 0.34, vacant.size.y * 0.82),
			"?", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(vacant.size.y * 0.9)), Color("#c8553d"))


static func _icon_folder(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	_shape(ci, _pts(r, [[0.06, 0.22], [0.38, 0.22], [0.46, 0.3], [0.94, 0.3], [0.94, 0.84], [0.06, 0.84]]),
			Color("#d9a441"), ink, w)
	_shape(ci, _rect_pts(_sub(r, 0.16, 0.26, 0.62, 0.4)), Color("#fbfaf4"), ink, w * 0.7)
	_shape(ci, _pts(r, [[0.06, 0.4], [0.94, 0.4], [0.9, 0.84], [0.1, 0.84]]), Color("#f0c360"), ink, w)


static func _icon_market(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var panel: Rect2 = _sub(r, 0.06, 0.14, 0.88, 0.72)
	_shape(ci, _rect_pts(panel), Color("#10202b"), ink, w)
	for i: int in 4:
		ci.draw_rect(_sub(r, 0.16 + i * 0.18, 0.62 - i * 0.08, 0.1, 0.18 + i * 0.08), Color("#2f6db5"))
	ci.draw_polyline(_pts(r, [[0.12, 0.66], [0.32, 0.5], [0.46, 0.58], [0.66, 0.34], [0.86, 0.22]]),
			Color("#5fd38d"), w * 1.6, true)
	_shape(ci, _pts(r, [[0.8, 0.18], [0.92, 0.18], [0.9, 0.3]]), Color("#5fd38d"), Color("#5fd38d"), w * 0.5)


static func _icon_not_found(ci: CanvasItem, r: Rect2, ink: Color, w: float, pal: Dictionary) -> void:
	_shape(ci, _pts(r, [[0.14, 0.08], [0.7, 0.08], [0.86, 0.24], [0.86, 0.5], [0.72, 0.58], [0.84, 0.7],
			[0.86, 0.92], [0.14, 0.92]]), Color("#fbfaf4"), ink, w)
	var f: Font = UITheme.font(UITheme.FONT_BOLD)
	ci.draw_string(f, _p(r, 0.2, 0.52), "404", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(r.size.y * 0.24)),
			col(pal, "bad"))
	ci.draw_line(_p(r, 0.24, 0.7), _p(r, 0.62, 0.7), Color(ink, 0.5), w)
	ci.draw_line(_p(r, 0.24, 0.8), _p(r, 0.54, 0.8), Color(ink, 0.5), w)


static func _icon_page(ci: CanvasItem, r: Rect2, ink: Color, w: float, fill: Color) -> void:
	_shape(ci, _pts(r, [[0.18, 0.06], [0.64, 0.06], [0.84, 0.26], [0.84, 0.94], [0.18, 0.94]]), fill, ink, w)
	ci.draw_polyline(_pts(r, [[0.64, 0.06], [0.64, 0.26], [0.84, 0.26]]), ink, w, true)


static func _page_lines(ci: CanvasItem, r: Rect2, ink: Color, count: int) -> void:
	for i: int in count:
		var y: float = 0.4 + i * 0.13
		ci.draw_line(_p(r, 0.28, y), _p(r, 0.74 - (i % 2) * 0.12, y), Color(ink, 0.45), maxf(1.0, r.size.x * 0.04))


static func _icon_bars(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var heights: Array[float] = [0.18, 0.32, 0.24, 0.42]
	for i: int in heights.size():
		var h: float = heights[i]
		ci.draw_rect(_sub(r, 0.26 + i * 0.13, 0.86 - h, 0.09, h), Color("#2f6db5") if i != 3 else Color("#5fb36b"))
	ci.draw_line(_p(r, 0.24, 0.86), _p(r, 0.8, 0.86), ink, w * 0.7)


static func _icon_heart(ci: CanvasItem, r: Rect2, fill: Color, ink: Color, w: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 24:
		var t: float = TAU * float(i) / 24.0
		var x: float = 16.0 * pow(sin(t), 3)
		var y: float = -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(r.get_center() + Vector2(x, y) * r.size.x / 34.0)
	_shape(ci, pts, fill, ink, w * 0.7)


static func _icon_bulb(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	for i: int in 5:
		var a: float = -PI * 0.5 + (i - 2) * 0.55
		ci.draw_line(_p(r, 0.5, 0.38) + Vector2(cos(a), sin(a)) * r.size.x * 0.36,
				_p(r, 0.5, 0.38) + Vector2(cos(a), sin(a)) * r.size.x * 0.46, Color("#f5c542"), w * 1.2, true)
	var glass: PackedVector2Array = UITheme.ellipse_points(_p(r, 0.5, 0.4), r.size.x * 0.27, r.size.y * 0.27, 24)
	_shape(ci, glass, Color("#ffe98a"), ink, w)
	_shape(ci, _rect_pts(_sub(r, 0.38, 0.64, 0.24, 0.2)), Color("#9aa4b0"), ink, w)
	ci.draw_line(_p(r, 0.38, 0.72), _p(r, 0.62, 0.72), ink, w * 0.7)


static func _icon_trash(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	_shape(ci, _pts(r, [[0.22, 0.26], [0.78, 0.26], [0.72, 0.92], [0.28, 0.92]]), Color("#c9d3d6"), ink, w)
	_shape(ci, _rect_pts(_sub(r, 0.16, 0.16, 0.68, 0.1)), Color("#aeb9bd"), ink, w)
	for i: int in 3:
		ci.draw_line(_p(r, 0.36 + i * 0.14, 0.34), _p(r, 0.37 + i * 0.13, 0.84), Color(ink, 0.5), w * 0.7)


static func _icon_lock(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	ci.draw_arc(_p(r, 0.5, 0.42), r.size.x * 0.2, PI, TAU, 16, ink, w * 1.8, true)
	_shape(ci, _rect_pts(_sub(r, 0.22, 0.42, 0.56, 0.46)), Color("#f5c542"), ink, w)
	ci.draw_circle(_p(r, 0.5, 0.6), r.size.x * 0.06, ink)


static func _icon_warning(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	_shape(ci, _pts(r, [[0.5, 0.08], [0.94, 0.88], [0.06, 0.88]]), Color("#ffd21f"), ink, w)
	ci.draw_line(_p(r, 0.5, 0.36), _p(r, 0.5, 0.64), ink, w * 1.8)
	ci.draw_circle(_p(r, 0.5, 0.76), w * 1.1, ink)


static func _icon_user(ci: CanvasItem, r: Rect2, ink: Color, w: float, fill: Color) -> void:
	_shape(ci, UITheme.ellipse_points(_p(r, 0.5, 0.92), r.size.x * 0.36, r.size.y * 0.3, 20), fill, ink, w)
	_shape(ci, UITheme.ellipse_points(_p(r, 0.5, 0.38), r.size.x * 0.19, r.size.y * 0.21, 18), Color("#e8b98f"), ink, w)


static func _icon_snail(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	_shape(ci, _pts(r, [[0.08, 0.84], [0.9, 0.84], [0.96, 0.66], [0.84, 0.6], [0.8, 0.74], [0.08, 0.76]]),
			Color("#b9e07a"), ink, w)
	ci.draw_line(_p(r, 0.88, 0.62), _p(r, 0.84, 0.44), ink, w)
	ci.draw_line(_p(r, 0.93, 0.64), _p(r, 0.98, 0.46), ink, w)
	var shell: PackedVector2Array = UITheme.ellipse_points(_p(r, 0.46, 0.56), r.size.x * 0.28, r.size.y * 0.26, 24)
	_shape(ci, shell, Color("#d9a441"), ink, w)
	var spiral: PackedVector2Array = PackedVector2Array()
	for i: int in 30:
		var t: float = float(i) / 29.0
		var a: float = t * TAU * 1.6
		spiral.append(_p(r, 0.46, 0.56) + Vector2(cos(a), sin(a)) * r.size.x * 0.22 * (1.0 - t))
	ci.draw_polyline(spiral, ink, w * 0.7, true)


static func _icon_drop(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array([_p(r, 0.5, 0.06)])
	for i: int in 17:
		var a: float = -0.35 + (PI + 0.7) * float(i) / 16.0
		pts.append(_p(r, 0.5, 0.62) + Vector2(cos(a), sin(a)) * r.size.x * 0.3)
	pts.reverse()
	_shape(ci, pts, Color("#5fb3e8"), ink, w)
	ci.draw_arc(_p(r, 0.5, 0.62), r.size.x * 0.18, PI * 0.6, PI * 0.95, 8, Color(1, 1, 1, 0.8), w, true)


static func _icon_shoe(ci: CanvasItem, r: Rect2, ink: Color, w: float) -> void:
	var sole: PackedVector2Array = _pts(r, [[0.04, 0.7], [0.96, 0.7], [0.96, 0.84], [0.04, 0.84]])
	var upper: PackedVector2Array = _pts(r, [[0.06, 0.7], [0.1, 0.4], [0.3, 0.38], [0.44, 0.52],
			[0.7, 0.56], [0.92, 0.62], [0.96, 0.7]])
	_shape(ci, upper, Color("#f4f1e6"), ink, w)
	_shape(ci, sole, Color("#c8553d"), ink, w)
	ci.draw_polyline(_pts(r, [[0.2, 0.62], [0.5, 0.64], [0.8, 0.6]]), Color("#2f6db5"), w * 1.6, true)
	for i: int in 3:
		ci.draw_line(_p(r, 0.3 + i * 0.06, 0.44 + i * 0.03), _p(r, 0.36 + i * 0.06, 0.48 + i * 0.03), ink, w * 0.7)
	_shape(ci, star_points(_p(r, 0.2, 0.2), r.size.x * 0.1, r.size.x * 0.04), Color("#f5c542"), ink, w * 0.6)


## Reloj de arena de «espere, por favor»; `t` 0-1 = arena caída.
static func draw_hourglass(ci: CanvasItem, r: Rect2, ink: Color, t: float) -> void:
	var w: float = maxf(1.5, r.size.x * 0.06)
	var sand: Color = Color("#e0b04a")
	var glass: Color = Color(1, 1, 1, 0.85)
	var top: PackedVector2Array = _pts(r, [[0.22, 0.12], [0.78, 0.12], [0.52, 0.5], [0.48, 0.5]])
	var bottom: PackedVector2Array = _pts(r, [[0.48, 0.5], [0.52, 0.5], [0.78, 0.88], [0.22, 0.88]])
	_shape(ci, top, glass, ink, w)
	_shape(ci, bottom, glass, ink, w)
	var k: float = clampf(t, 0.0, 1.0)
	var top_level: float = 0.18 + 0.3 * k
	ci.draw_colored_polygon(_pts(r, [[0.22 + 0.26 * (top_level - 0.12) / 0.38, top_level],
			[0.78 - 0.26 * (top_level - 0.12) / 0.38, top_level], [0.5, 0.49]]), sand)
	var pile: float = 0.88 - 0.3 * k
	ci.draw_colored_polygon(_pts(r, [[0.26, 0.86], [0.74, 0.86], [0.5, pile]]), sand)
	ci.draw_line(_p(r, 0.14, 0.1), _p(r, 0.86, 0.1), ink, w * 1.6)
	ci.draw_line(_p(r, 0.14, 0.9), _p(r, 0.86, 0.9), ink, w * 1.6)


# ─── Utilidades geométricas ───────────────────────────────────────

## Rectángulo con solo las esquinas superiores redondeadas (barras de título).
static func top_rounded_points(r: Rect2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var steps: int = 6
	for i: int in steps + 1:
		var a: float = PI + PI * 0.5 * float(i) / float(steps)
		pts.append(r.position + Vector2(rad, rad) + Vector2(cos(a), sin(a)) * rad)
	for i: int in steps + 1:
		var a: float = PI * 1.5 + PI * 0.5 * float(i) / float(steps)
		pts.append(Vector2(r.end.x - rad, r.position.y + rad) + Vector2(cos(a), sin(a)) * rad)
	pts.append(r.end)
	pts.append(Vector2(r.position.x, r.end.y))
	return pts


static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, ink: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, ink, w, true)


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(r.size.x * x, r.size.y * y)


static func _pts(r: Rect2, coords: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for c: Array in coords:
		out.append(_p(r, float(c[0]), float(c[1])))
	return out


static func _sub(r: Rect2, x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_p(r, x, y), Vector2(r.size.x * w, r.size.y * h))


static func _rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
