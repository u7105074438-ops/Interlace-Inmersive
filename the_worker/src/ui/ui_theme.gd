# ui_theme.gd — Tema compartido de la interfaz: paleta, tipografía, ajustes y kit de dibujo vectorial.
# PROPIETARIO DE: el tema vigente (tamaño de texto y alto contraste activos) y la caché de fuentes.
# ESCUCHA: nada.
class_name UITheme
extends RefCounted

## Uso: root_control.theme = UITheme.build(text_size, high_contrast)   (manual §13.10, BUILD_NOTES §8)
##  · text_size 0 pequeño · 1 medio · 2 grande (tamaños base en balance interfaz.texto_base_por_nivel).
##  · high_contrast: fondos opacos, contornos gruesos, colores saturados (también para los
##    indicadores de detección: UITheme.palette(UITheme.current_high_contrast)).
##  · Colores del HUD en el tipo de tema "HUD": get_theme_color("rep", UITheme.HUD_TYPE).
##  · Constantes del tipo "HUD": icon, bar_w, bar_h, slot, gap, outline, radius (escalan con el texto).
##  · Variaciones de tipo: ver V_* (Label/PanelContainer/Button).
##  · Iconos vectoriales: UITheme.draw_icon(canvas, "eye", rect, color, width) y UITheme.IconView.

const FONT_DIR := "res://assets/fonts/"
const FONT_REGULAR := FONT_DIR + "Inter-Regular.ttf"
const FONT_SEMIBOLD := FONT_DIR + "Inter-SemiBold.ttf"
const FONT_BOLD := FONT_DIR + "Inter-ExtraBold.ttf"
const FONT_MONO := FONT_DIR + "JetBrainsMono-Medium.ttf"
const BALANCE_FILE := "res://data/balance.json"
const ART_BANDS_FILE := "res://data/art_bands.json"
const DEFAULT_BAND := "the_pit"

const TEXT_SMALL := 0
const TEXT_MEDIUM := 1
const TEXT_LARGE := 2
const HUD_TYPE := "HUD"

const V_CLOCK := "HudClock"
const V_NUMBER := "HudNumber"
const V_TITLE := "HudTitle"
const V_HEADING := "HudHeading"
const V_CAPTION := "HudCaption"
const V_SMALL := "HudSmall"
const V_STRONG := "HudStrong"
const V_MONO := "MonoLabel"
const V_PANEL := "HudPanel"
const V_PILL := "HudPill"
const V_DANGER_PILL := "HudDangerPill"
const V_MODAL := "ModalPanel"
const V_CARD := "CardPanel"
const V_KEYCAP := "KeyCap"
const V_TOAST := "ToastPanel"
const V_SUBTITLE := "SubtitlePanel"
const V_PRIMARY := "PrimaryButton"
const V_DANGER := "DangerButton"
const V_FLAT := "FlatButton"

## Proporciones tipográficas respecto al tamaño base (diseño, no balance).
const RATIO_CLOCK := 2.1
const RATIO_NUMBER := 1.55
const RATIO_TITLE := 1.45
const RATIO_HEADING := 1.12
const RATIO_CAPTION := 0.78
const RATIO_SMALL := 0.84
const RATIO_MONO := 0.72
const RATIO_ICON := 1.15
const RATIO_BAR_W := 11.0
const RATIO_BAR_H := 0.5
const RATIO_SLOT := 4.4
const RATIO_GAP := 0.5
## Acento de banda sobre paneles oscuros: brillo mínimo (HSV), realce de saturación y luminancia mínima.
const ACCENT_MIN_VALUE := 0.82
const ACCENT_SATURATION_BOOST := 1.35
const ACCENT_MIN_LUMINANCE := 0.55
## Inclinación de la cursiva sintética (subtítulos de ambiente).
const ITALIC_SKEW := 0.2

## Tamaño de texto y contraste vigentes (los fija build(); otras piezas pueden consultarlos).
static var current_text_size: int = TEXT_MEDIUM
static var current_high_contrast: bool = false
## Modo táctil activo: el tamaño base se multiplica por interfaz.escala_texto_tactil (pantalla móvil).
static var touch_scale_active: bool = false
static var _fonts: Dictionary = {}
static var _json_cache: Dictionary = {}

const PALETTE_NORMAL: Dictionary = {
	"ink": Color("#12151a"), "panel": Color(0.07, 0.08, 0.10, 0.84), "line": Color("#39414d"),
	"paper": Color("#f4f1ea"), "muted": Color("#a3abb6"), "faint": Color("#5f6874"),
	"rep": Color("#3f8cff"), "rep_track": Color("#1a2b47"), "sus": Color("#ff4d4d"),
	"sus_track": Color("#3d1a1d"), "gain": Color("#5fd38d"), "loss": Color("#ff7b6b"),
	"warn": Color("#ffb23e"), "hazard": Color("#ffd21f"), "hazard_ink": Color("#17181a"),
	"danger": Color("#ff3b3b"), "focus": Color("#ffe28a"), "slot": Color("#1d232b"),
	"slot_hot": Color("#3a1d1b"), "det_progress": Color("#ffd23f"),
	"det_partial": Color("#ff8a1f"), "det_flagrant": Color("#ff2e2e"),
	"shadow": Color(0.0, 0.0, 0.0, 0.38), "accent": Color("#8fa77a"), "dim": Color(0.02, 0.03, 0.05, 0.62),
	"button": Color("#232a33"), "button_hover": Color("#2d3641"),
}
const PALETTE_CONTRAST: Dictionary = {
	"ink": Color("#000000"), "panel": Color(0.0, 0.0, 0.0, 0.96), "line": Color("#ffffff"),
	"paper": Color("#ffffff"), "muted": Color("#e6e6e6"), "faint": Color("#b0b0b0"),
	"rep": Color("#49a6ff"), "rep_track": Color("#0b1f3a"), "sus": Color("#ff2b2b"),
	"sus_track": Color("#3a0b0b"), "gain": Color("#3dff8a"), "loss": Color("#ff5c5c"),
	"warn": Color("#ffcc00"), "hazard": Color("#ffe600"), "hazard_ink": Color("#000000"),
	"danger": Color("#ff1f1f"), "focus": Color("#ffff00"), "slot": Color("#101010"),
	"slot_hot": Color("#4a0f0f"), "det_progress": Color("#ffff00"),
	"det_partial": Color("#ff9900"), "det_flagrant": Color("#ff0000"),
	"shadow": Color(0.0, 0.0, 0.0, 0.6), "accent": Color("#ffffff"), "dim": Color(0.0, 0.0, 0.0, 0.78),
	"button": Color("#111111"), "button_hover": Color("#2a2a2a"),
}


# ─── Construcción del tema ─────────────────────────────────────────

static func build(text_size: int, high_contrast: bool) -> Theme:
	current_text_size = clampi(text_size, TEXT_SMALL, TEXT_LARGE)
	current_high_contrast = high_contrast
	var pal: Dictionary = palette(high_contrast)
	var base: int = base_font_size(current_text_size)
	var t: Theme = Theme.new()
	_apply_fonts(t, base)
	_apply_hud_type(t, pal, base, high_contrast)
	_apply_label_colors(t, pal)
	_apply_panels(t, pal, high_contrast)
	_apply_buttons(t, pal, base, high_contrast)
	_apply_misc(t, pal, base)
	return t


static func palette(high_contrast: bool) -> Dictionary:
	return PALETTE_CONTRAST if high_contrast else PALETTE_NORMAL


## Color de la paleta vigente (alto contraste o normal).
static func color(color_name: String) -> Color:
	return palette(current_high_contrast).get(color_name, Color.MAGENTA)


static func base_font_size(text_size: int) -> int:
	var sizes: Array = tune_array("interfaz.texto_base_por_nivel")
	if sizes.is_empty():
		return ThemeDB.fallback_font_size
	var base: float = float(sizes[clampi(text_size, 0, sizes.size() - 1)])
	if touch_scale_active:
		base *= maxf(tune("interfaz.escala_texto_tactil"), 1.0)
	return roundi(base)


## Nivel de texto por defecto: grande en móvil (crítico en pantalla reducida, §13.10).
static func default_text_size() -> int:
	if OS.has_feature("mobile"):
		return tune_int("interfaz.texto_nivel_por_defecto_movil")
	return tune_int("interfaz.texto_nivel_por_defecto_pc")


static func _apply_fonts(t: Theme, base: int) -> void:
	var regular: Font = font(FONT_REGULAR)
	var semibold: Font = font(FONT_SEMIBOLD)
	var bold: Font = font(FONT_BOLD)
	t.default_font = regular
	t.default_font_size = base
	_label_variation(t, V_CLOCK, tabular(bold), roundi(base * RATIO_CLOCK))
	_label_variation(t, V_NUMBER, tabular(bold), roundi(base * RATIO_NUMBER))
	_label_variation(t, V_TITLE, bold, roundi(base * RATIO_TITLE))
	_label_variation(t, V_HEADING, semibold, roundi(base * RATIO_HEADING))
	_label_variation(t, V_CAPTION, spaced(semibold), roundi(base * RATIO_CAPTION))
	_label_variation(t, V_SMALL, regular, roundi(base * RATIO_SMALL))
	_label_variation(t, V_STRONG, semibold, base)
	_label_variation(t, V_MONO, font(FONT_MONO), roundi(base * RATIO_MONO))
	for button_type: String in ["Button", V_PRIMARY, V_DANGER, V_FLAT]:
		t.set_font("font", button_type, semibold)
		t.set_font_size("font_size", button_type, base)
	t.set_font("normal_font", "RichTextLabel", regular)
	t.set_font("bold_font", "RichTextLabel", semibold)
	t.set_font("mono_font", "RichTextLabel", font(FONT_MONO))
	t.set_font_size("normal_font_size", "RichTextLabel", roundi(base * RATIO_MONO))
	t.set_font_size("bold_font_size", "RichTextLabel", roundi(base * RATIO_MONO))
	t.set_font_size("mono_font_size", "RichTextLabel", roundi(base * RATIO_MONO))


static func _label_variation(t: Theme, variation: String, f: Font, size: int) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font("font", variation, f)
	t.set_font_size("font_size", variation, size)


static func _apply_hud_type(t: Theme, pal: Dictionary, base: int, high_contrast: bool) -> void:
	for key: String in pal:
		t.set_color(key, HUD_TYPE, pal[key])
	t.set_constant("icon", HUD_TYPE, roundi(base * RATIO_ICON))
	t.set_constant("bar_w", HUD_TYPE, roundi(base * RATIO_BAR_W))
	t.set_constant("bar_h", HUD_TYPE, maxi(roundi(base * RATIO_BAR_H), 8))
	t.set_constant("slot", HUD_TYPE, roundi(base * RATIO_SLOT))
	t.set_constant("gap", HUD_TYPE, roundi(base * RATIO_GAP))
	t.set_constant("outline", HUD_TYPE, 3 if high_contrast else 2)
	t.set_constant("radius", HUD_TYPE, 10)
	t.set_constant("base", HUD_TYPE, base)


static func _apply_label_colors(t: Theme, pal: Dictionary) -> void:
	t.set_color("font_color", "Label", pal["paper"])
	t.set_color("font_color", V_CAPTION, pal["muted"])
	t.set_color("font_color", V_SMALL, pal["muted"])
	t.set_color("font_color", V_MONO, pal["paper"])
	t.set_color("default_color", "RichTextLabel", pal["paper"])


static func _apply_panels(t: Theme, pal: Dictionary, high_contrast: bool) -> void:
	var border: int = 3 if high_contrast else 2
	var line: Color = pal["line"]
	t.set_type_variation(V_PANEL, "PanelContainer")
	t.set_stylebox("panel", V_PANEL, _box(pal["panel"], line, border, 12, 18, 12, pal["shadow"]))
	t.set_stylebox("panel", "PanelContainer", _box(pal["panel"], line, border, 12, 18, 12, pal["shadow"]))
	t.set_type_variation(V_PILL, "PanelContainer")
	t.set_stylebox("panel", V_PILL, _box(pal["panel"], line, border, 22, 16, 7, pal["shadow"]))
	t.set_type_variation(V_DANGER_PILL, "PanelContainer")
	var danger_bg: Color = Color(pal["danger"]).darkened(0.35)
	t.set_stylebox("panel", V_DANGER_PILL, _box(danger_bg, pal["paper"], border, 22, 16, 7, pal["shadow"]))
	t.set_type_variation(V_MODAL, "PanelContainer")
	var modal_bg: Color = Color(pal["ink"])
	t.set_stylebox("panel", V_MODAL, _box(modal_bg, line, border, 16, 30, 26, pal["shadow"], 24))
	t.set_type_variation(V_CARD, "PanelContainer")
	t.set_stylebox("panel", V_CARD, _box(pal["slot"], line, border - 1, 10, 16, 12, Color.TRANSPARENT))
	t.set_type_variation(V_KEYCAP, "PanelContainer")
	var cap: StyleBoxFlat = _box(pal["paper"], pal["muted"], 0, 6, 9, 2, Color.TRANSPARENT)
	cap.border_width_bottom = 4
	t.set_stylebox("panel", V_KEYCAP, cap)
	t.set_type_variation(V_TOAST, "PanelContainer")
	t.set_stylebox("panel", V_TOAST, _box(pal["panel"], line, border, 12, 16, 10, pal["shadow"]))
	t.set_type_variation(V_SUBTITLE, "PanelContainer")
	var sub_bg: Color = Color(pal["ink"], 0.9 if high_contrast else 0.72)
	t.set_stylebox("panel", V_SUBTITLE, _box(sub_bg, Color.TRANSPARENT, 0, 8, 14, 5, Color.TRANSPARENT))


static func _apply_buttons(t: Theme, pal: Dictionary, base: int, high_contrast: bool) -> void:
	var border: int = 3 if high_contrast else 2
	var pad_h: float = base * 0.8
	var pad_v: float = base * 0.38
	_button_styles(t, "Button", pal["button"], pal["button_hover"], pal["line"], pal, border, pad_h, pad_v)
	var accent: Color = Color("#2f6fe0") if not high_contrast else Color("#0050ff")
	t.set_type_variation(V_PRIMARY, "Button")
	_button_styles(t, V_PRIMARY, accent, accent.lightened(0.12), accent.lightened(0.3), pal, border, pad_h, pad_v)
	t.set_type_variation(V_DANGER, "Button")
	var red: Color = Color(pal["danger"]).darkened(0.25)
	_button_styles(t, V_DANGER, red, red.lightened(0.12), red.lightened(0.35), pal, border, pad_h, pad_v)
	t.set_type_variation(V_FLAT, "Button")
	var clear: Color = Color(pal["ink"], 0.0)
	_button_styles(t, V_FLAT, clear, pal["button_hover"], clear, pal, 0, pad_h * 0.5, pad_v * 0.5)
	for button_type: String in ["Button", V_PRIMARY, V_DANGER, V_FLAT]:
		t.set_color("font_color", button_type, pal["paper"])
		t.set_color("font_hover_color", button_type, pal["paper"])
		t.set_color("font_pressed_color", button_type, pal["paper"])
		t.set_color("font_focus_color", button_type, pal["paper"])
		t.set_color("font_disabled_color", button_type, pal["faint"])
		t.set_constant("h_separation", button_type, roundi(base * 0.4))


static func _button_styles(t: Theme, type_name: String, bg: Color, hover: Color, border_color: Color,
		pal: Dictionary, border: int, pad_h: float, pad_v: float) -> void:
	t.set_stylebox("normal", type_name, _box(bg, border_color, border, 9, pad_h, pad_v, Color.TRANSPARENT))
	t.set_stylebox("hover", type_name, _box(hover, pal["paper"], border, 9, pad_h, pad_v, Color.TRANSPARENT))
	t.set_stylebox("pressed", type_name, _box(bg.darkened(0.2), pal["paper"], border, 9, pad_h, pad_v,
			Color.TRANSPARENT))
	# Desactivado siempre neutro (gris): un botón peligroso apagado no debe seguir pareciendo rojo.
	var disabled_bg: Color = Color(pal["button"], 0.5) if bg.a > 0.0 else bg
	var disabled_line: Color = Color(pal["faint"], 0.5) if border > 0 else border_color
	t.set_stylebox("disabled", type_name, _box(disabled_bg, disabled_line, border, 9, pad_h, pad_v,
			Color.TRANSPARENT))
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, pal["focus"], 3, 10, pad_h, pad_v, Color.TRANSPARENT)
	focus.draw_center = false
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("focus", type_name, focus)


static func _apply_misc(t: Theme, pal: Dictionary, base: int) -> void:
	var grab: StyleBoxFlat = _box(pal["faint"], Color.TRANSPARENT, 0, 6, 0, 0, Color.TRANSPARENT)
	var track: StyleBoxFlat = _box(Color(pal["ink"], 0.4), Color.TRANSPARENT, 0, 6, 0, 0, Color.TRANSPARENT)
	for bar_type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", bar_type, grab)
		t.set_stylebox("grabber_highlight", bar_type, grab)
		t.set_stylebox("grabber_pressed", bar_type, grab)
		t.set_stylebox("scroll", bar_type, track)
	t.set_stylebox("panel", "TooltipPanel", _box(pal["ink"], pal["line"], 2, 8, 12, 8, pal["shadow"]))
	t.set_color("font_color", "TooltipLabel", pal["paper"])
	t.set_font_size("font_size", "TooltipLabel", roundi(base * RATIO_SMALL))
	t.set_constant("separation", "VBoxContainer", roundi(base * 0.35))
	t.set_constant("separation", "HBoxContainer", roundi(base * 0.45))
	t.set_constant("h_separation", "GridContainer", roundi(base * 0.5))
	t.set_constant("v_separation", "GridContainer", roundi(base * 0.5))


static func _box(bg: Color, border: Color, border_w: int, radius: int, pad_h: float, pad_v: float,
		shadow: Color, shadow_size: int = 8) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	if shadow.a > 0.0:
		sb.shadow_color = shadow
		sb.shadow_size = shadow_size
		sb.shadow_offset = Vector2(0, 3)
	return sb


# ─── Ajuste de tamaño de controles anclados ───────────────────────

## Ajusta los offsets de un control anclado a su tamaño mínimo respetando su dirección de
## crecimiento (los Control crecen solos pero nunca encogen: esto lo corrige).
static func fit_to_min(ctrl: Control) -> void:
	if not is_instance_valid(ctrl):
		return
	var m: Vector2 = ctrl.get_combined_minimum_size()
	match ctrl.grow_horizontal:
		Control.GROW_DIRECTION_BEGIN:
			ctrl.offset_left = ctrl.offset_right - m.x
		Control.GROW_DIRECTION_END:
			ctrl.offset_right = ctrl.offset_left + m.x
		_:
			var cx: float = (ctrl.offset_left + ctrl.offset_right) * 0.5
			ctrl.offset_left = cx - m.x * 0.5
			ctrl.offset_right = cx + m.x * 0.5
	match ctrl.grow_vertical:
		Control.GROW_DIRECTION_BEGIN:
			ctrl.offset_top = ctrl.offset_bottom - m.y
		Control.GROW_DIRECTION_END:
			ctrl.offset_bottom = ctrl.offset_top + m.y
		_:
			var cy: float = (ctrl.offset_top + ctrl.offset_bottom) * 0.5
			ctrl.offset_top = cy - m.y * 0.5
			ctrl.offset_bottom = cy + m.y * 0.5


## Mantiene el control ajustado a su tamaño mínimo cada vez que este cambie.
static func keep_fitted(ctrl: Control) -> void:
	var refit: Callable = _deferred_fit.bind(ctrl)
	if not ctrl.minimum_size_changed.is_connected(refit):
		ctrl.minimum_size_changed.connect(refit)
	_deferred_fit(ctrl)


static func _deferred_fit(ctrl: Control) -> void:
	fit_to_min.call_deferred(ctrl)


## Centra un control en la pantalla y lo mantiene centrado y ajustado (ventanas modales).
static func center_fitted(ctrl: Control) -> void:
	ctrl.set_anchors_preset(Control.PRESET_CENTER)
	ctrl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl.grow_vertical = Control.GROW_DIRECTION_BOTH
	ctrl.offset_left = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_bottom = 0.0
	keep_fitted(ctrl)


# ─── Fuentes ───────────────────────────────────────────────────────

## Fuente del directorio assets/fonts (OFL); si falta, la del motor.
static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[path] = f
	return f


## Variante con cifras tabulares (el reloj y el dinero no bailan al cambiar).
static func tabular(base_font: Font) -> Font:
	var fv: FontVariation = FontVariation.new()
	fv.base_font = base_font
	var ts: TextServer = TextServerManager.get_primary_interface()
	fv.opentype_features = {ts.name_to_tag("tnum"): 1}
	return fv


## Variante con espaciado entre letras (rótulos en versalitas).
static func spaced(base_font: Font) -> Font:
	var fv: FontVariation = FontVariation.new()
	fv.base_font = base_font
	fv.spacing_glyph = 1
	return fv


## Variante cursiva sintética (inclinación de los glifos): distingue por forma, no solo por color.
static func italic(base_font: Font) -> Font:
	var key: String = "italic:%d" % base_font.get_instance_id()
	if _fonts.has(key):
		return _fonts[key]
	var fv: FontVariation = FontVariation.new()
	fv.base_font = base_font
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(ITALIC_SKEW, 1.0), Vector2.ZERO)
	_fonts[key] = fv
	return fv


## Pulsación principal (clic izquierdo o toque) sin duplicados: con la emulación de ratón desde
## el táctil activa (ajuste del proyecto), un toque llega también como clic emulado y solo cuenta este.
static func is_primary_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed and not touch_emulates_mouse()
	var mb: InputEventMouseButton = event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT


static func touch_emulates_mouse() -> bool:
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))


# ─── Ajustes (balance.json, sección interfaz) ──────────────────────

## Valor numérico de balance. Usa Database si está cargado; si no, lee balance.json (solo lectura).
static func tune(path: String) -> float:
	var v: Variant = tune_value(path)
	if v is float or v is int:
		return float(v)
	return 0.0


static func tune_int(path: String) -> int:
	return roundi(tune(path))


static func tune_array(path: String) -> Array:
	var v: Variant = tune_value(path)
	return v if v is Array else []


static func tune_value(path: String) -> Variant:
	var db: Node = _autoload("Database")
	if db != null:
		var v: Variant = db.call("get_balance", path)
		if v != null:
			return v
	return _lookup(_json_file(BALANCE_FILE), path)


static func _lookup(root: Dictionary, path: String) -> Variant:
	var node: Variant = root
	for key: String in path.split("."):
		if not (node is Dictionary and (node as Dictionary).has(key)):
			return null
		node = (node as Dictionary)[key]
	return node


static func _json_file(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Dictionary = parsed if parsed is Dictionary else {}
	_json_cache[path] = out
	return out


static func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))


# ─── Paletas de banda (art_bands.json) ─────────────────────────────

## Paleta {floor, wall, accent, ...} de la banda artística de una planta.
static func band_palette_for_floor(floor_number: int) -> Dictionary:
	var band: Dictionary = band_for_floor(floor_number)
	var pal: Variant = band.get("palette", {})
	return pal if pal is Dictionary else {}


static func band_id_for_floor(floor_number: int) -> String:
	return str(band_for_floor(floor_number).get("id", DEFAULT_BAND))


## Registro de art_bands.json de la banda que contiene la planta (Database si está cargado).
static func band_for_floor(floor_number: int) -> Dictionary:
	var db: Node = _autoload("Database")
	if db != null and db.has_method("get_art_band_for_floor"):
		var band: Variant = db.call("get_art_band_for_floor", floor_number)
		if band is Dictionary and not (band as Dictionary).is_empty():
			return band
	for entry: Variant in _json_file(ART_BANDS_FILE).get("bands", []):
		if entry is Dictionary and _floors_contain((entry as Dictionary).get("floors", []), floor_number):
			return entry
	return {}


static func _floors_contain(floors: Variant, floor_number: int) -> bool:
	if not floors is Array:
		return false
	for f: Variant in floors:
		if (f is int or f is float) and int(f) == floor_number:
			return true
	return false


## Acento de la banda, aclarado si hace falta para leerse sobre un panel oscuro.
static func band_accent_for_floor(floor_number: int) -> Color:
	var pal: Dictionary = band_palette_for_floor(floor_number)
	if current_high_contrast or not pal.has("accent"):
		return color("accent")
	var src: Color = Color(str(pal["accent"]))
	var c: Color = Color.from_hsv(src.h, clampf(src.s * ACCENT_SATURATION_BOOST, 0.0, 1.0),
			maxf(src.v, ACCENT_MIN_VALUE))
	while c.get_luminance() < ACCENT_MIN_LUMINANCE:
		c = c.lightened(0.12)
	return c


## Color de texto legible (tinta o papel) sobre un fondo dado.
static func readable_on(bg: Color) -> Color:
	return color("ink") if bg.get_luminance() > 0.55 else color("paper")


# ─── Formato ───────────────────────────────────────────────────────

## "€1,240" / "1.240 €" según el idioma (claves UI_MONEY_FMT y UI_THOUSANDS_SEP).
static func format_money(amount: int) -> String:
	var digits: String = str(absi(amount))
	var sep: String = String(TranslationServer.translate("UI_THOUSANDS_SEP"))
	var grouped: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			grouped = sep + grouped
		grouped = digits[i] + grouped
		count += 1
	var text: String = String(TranslationServer.translate("UI_MONEY_FMT")) % grouped
	return ("-" + text) if amount < 0 else text


static func format_signed_money(amount: int) -> String:
	return ("+" if amount >= 0 else "") + format_money(amount)


static func format_hour(hour: int, minute: int = 0) -> String:
	return "%02d:%02d" % [hour, minute]


## Traduce una clave con argumentos opcionales (Array → operador %).
static func trf(key: String, args: Array = []) -> String:
	var text: String = String(TranslationServer.translate(key))
	if args.is_empty() or not "%" in text:
		return text
	return text % args


# ─── Iconos por contexto ───────────────────────────────────────────

## Tipo de interactivo (datos de sala, tránsitos de FloorLayout, HidingSpot) → glifo del botón de acción.
const INTERACT_ICONS: Dictionary = {
	"door": "door", "exit": "door", "bus_stop": "door", "turnstile": "card", "card_reader": "card",
	"elevator": "elevator", "freight": "elevator", "elevator_panel": "elevator", "freight_panel": "elevator",
	"stairs": "stairs", "service_stairs": "stairs", "stairs_door": "stairs", "service_stairs_door": "stairs",
	"vent_hatch": "hide", "hiding_spot": "hide", "hide": "hide", "smoking_spot": "talk",
	"computer": "computer", "npc_computer": "computer", "monitor_console": "camera",
	"training_screen": "computer", "backup_unit": "computer",
	"talk": "talk", "npc": "talk", "police_desk": "talk", "interrogation_table": "talk",
	"board_table": "talk", "aurora_podium": "talk", "results_stage": "talk",
	"bed": "sleep", "sleep": "sleep", "lock": "lock", "lock_old": "lock", "safe": "safe",
	"drawer": "take", "desk": "take", "pickup": "take", "take": "take", "carrier_bay": "take",
	"trash": "trash", "trash_dock": "trash", "trash_chute": "trash", "eavesdrop_point": "ear",
	"phone": "phone", "map": "map", "shop": "cash", "shop_counter": "cash", "vending": "food",
	"food_fridge": "food", "kitchen_food": "food", "lunch_counter": "food", "coffee_machine_use": "food",
	"copier": "document", "copier_memory": "document", "archive_files": "document",
	"personnel_files": "document", "design_archive": "document", "delivery_notes": "document",
	"mail_sorting": "document", "notary_desk": "document", "forgery_station": "supplies",
	"supply_shelf": "supplies", "cleaning_supplies": "supplies", "cleaning_cart": "supplies",
	"product_shelf": "product", "demo_table": "product", "uniform_locker": "uniform",
	"tool_rack": "tool", "repair_bench": "tool", "machine_controls": "tool", "mold_station": "tool",
	"car_sabotage": "tool", "electrical_breaker": "tool", "alarm_panel": "tool",
	"chemical_station": "hazard", "roof_ledge": "hazard", "medical_cabinet": "plus",
}
## Reglas por sufijo para tipos no listados (p. ej. "payroll_terminal" → ordenador).
const INTERACT_SUFFIX_ICONS: Dictionary = {
	"_terminal": "computer", "_console": "computer", "_safe": "safe", "_files": "document",
	"_door": "door", "_locker": "uniform", "_shelf": "supplies", "_panel": "tool",
}
const ITEM_ID_ICONS: Dictionary = {
	"phone": "phone", "phone_highend": "phone", "laptop_highend": "computer",
	"office_equipment": "computer", "footage_copy": "camera", "watch_luxury": "clock",
	"lockpick": "key", "master_keys": "key", "guard_keys": "key", "security_master_key": "key",
	"balaclava": "hide", "wallet": "cash", "company_cash": "cash", "cash_envelope": "cash",
}
const ITEM_KIND_ICONS: Dictionary = {
	"key": "key", "tool": "tool", "card": "card", "food": "food", "supplies": "supplies",
	"clothing": "clothing", "uniform": "uniform", "cash": "cash", "product": "product",
	"material": "material", "valuable": "valuable", "document": "document",
	"personal": "personal", "post_tool": "tool",
}


static func icon_for_interact_type(interact_type: String) -> String:
	if INTERACT_ICONS.has(interact_type):
		return str(INTERACT_ICONS[interact_type])
	for suffix: String in INTERACT_SUFFIX_ICONS:
		if interact_type.ends_with(suffix):
			return str(INTERACT_SUFFIX_ICONS[suffix])
	return "target"


static func icon_for_item_kind(kind: String) -> String:
	return str(ITEM_KIND_ICONS.get(kind, "document"))


## Icono de un objeto: primero por id (ITEM_ID_ICONS), después por tipo ("kind" del catálogo).
static func icon_for_item(item_id: String, kind: String) -> String:
	if ITEM_ID_ICONS.has(item_id):
		return str(ITEM_ID_ICONS[item_id])
	return icon_for_item_kind(kind)


# ─── Dibujo vectorial de iconos (trazo plano, extremos redondeados) ─

## Dibuja el icono `icon` dentro de `r`. Nombres: ver _icons_* (desconocido → "target").
static func draw_icon(c: CanvasItem, icon: String, r: Rect2, col: Color, w: float) -> void:
	if _icons_hud(c, icon, r, col, w):
		return
	if _icons_actions(c, icon, r, col, w):
		return
	if _icons_items(c, icon, r, col, w):
		return
	if _icons_misc(c, icon, r, col, w):
		return
	_icon_target(c, r, col, w)


static func _icons_hud(c: CanvasItem, icon: String, r: Rect2, col: Color, w: float) -> bool:
	match icon:
		"clock": _icon_clock(c, r, col, w)
		"coin": _icon_coin(c, r, col, w)
		"shield": _icon_shield(c, r, col, w)
		"eye": _icon_eye(c, r, col, w, false)
		"camera": _icon_camera(c, r, col, w)
		"no_entry": _icon_no_entry(c, r, col, w)
		"check": _poly(c, r, [0.18, 0.52, 0.42, 0.76, 0.84, 0.26], col, w * 1.3)
		"cross": _icon_cross(c, r, col, w * 1.2)
		"box": _rrect(c, r, Rect2(0.16, 0.16, 0.68, 0.68), col, w, 0.12)
		"clipboard": _icon_clipboard(c, r, col, w)
		"star": _icon_star(c, r, col)
		"hazard": _icon_hazard(c, r, col, w)
		"info": _icon_info(c, r, col, w)
		_:
			return false
	return true


static func _icons_actions(c: CanvasItem, icon: String, r: Rect2, col: Color, w: float) -> bool:
	match icon:
		"target": _icon_target(c, r, col, w)
		"take": _icon_take(c, r, col, w)
		"talk": _icon_talk(c, r, col, w)
		"door": _icon_door(c, r, col, w)
		"hide": _icon_eye(c, r, col, w, true)
		"computer": _icon_computer(c, r, col, w)
		"phone": _icon_phone(c, r, col, w)
		"map": _icon_map(c, r, col, w)
		"bag": _icon_bag(c, r, col, w)
		"elevator": _icon_elevator(c, r, col, w)
		"stairs": _poly(c, r, [0.1, 0.86, 0.34, 0.86, 0.34, 0.64, 0.58, 0.64, 0.58, 0.42, 0.82, 0.42, 0.82, 0.18], col, w)
		"sleep": _icon_sleep(c, r, col, w)
		"lock": _icon_lock(c, r, col, w)
		"trash": _icon_trash(c, r, col, w)
		"safe": _icon_safe(c, r, col, w)
		"ear": _icon_ear(c, r, col, w)
		_:
			return false
	return true


static func _icons_items(c: CanvasItem, icon: String, r: Rect2, col: Color, w: float) -> bool:
	match icon:
		"key": _icon_key(c, r, col, w)
		"tool": _icon_tool(c, r, col, w)
		"card": _icon_card(c, r, col, w)
		"food": _icon_food(c, r, col, w)
		"supplies": _icon_pencil(c, r, col, w)
		"clothing": _icon_shirt(c, r, col, w, false)
		"uniform": _icon_shirt(c, r, col, w, true)
		"cash": _icon_cash(c, r, col, w)
		"product": _icon_shoe(c, r, col, w)
		"material": _icon_roll(c, r, col, w)
		"valuable": _icon_gem(c, r, col, w)
		"document": _icon_document(c, r, col, w)
		"personal": _icon_person(c, r, col, w)
		_:
			return false
	return true


static func _icons_misc(c: CanvasItem, icon: String, r: Rect2, col: Color, w: float) -> bool:
	match icon:
		"sneak": _icon_sneak(c, r, col, w)
		"crouch": _icon_crouch(c, r, col, w)
		"sprint": _icon_chevrons(c, r, col, w, false)
		"chevron_down": _poly(c, r, [0.24, 0.38, 0.5, 0.64, 0.76, 0.38], col, w)
		"chevron_up": _poly(c, r, [0.24, 0.62, 0.5, 0.36, 0.76, 0.62], col, w)
		"arrow": _fill(c, r, [0.92, 0.5, 0.26, 0.16, 0.4, 0.5, 0.26, 0.84], col)
		"speaker": _icon_speaker(c, r, col, w)
		"moon": _icon_moon(c, r, col)
		"plus": _icon_plus(c, r, col, w)
		"bug": _icon_bug(c, r, col, w)
		_:
			return false
	return true


## Punto (x, y) en coordenadas unitarias del rectángulo.
static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func _pts(r: Rect2, coords: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, coords.size() - 1, 2):
		out.append(_p(r, float(coords[i]), float(coords[i + 1])))
	return out


static func _poly(c: CanvasItem, r: Rect2, coords: Array, col: Color, w: float, closed: bool = false) -> void:
	var pts: PackedVector2Array = _pts(r, coords)
	if closed and pts.size() > 0:
		pts.append(pts[0])
	c.draw_polyline(pts, col, w, true)


static func _fill(c: CanvasItem, r: Rect2, coords: Array, col: Color) -> void:
	c.draw_colored_polygon(_pts(r, coords), col)


static func _line(c: CanvasItem, r: Rect2, x1: float, y1: float, x2: float, y2: float, col: Color, w: float) -> void:
	c.draw_line(_p(r, x1, y1), _p(r, x2, y2), col, w, true)


static func _ring(c: CanvasItem, r: Rect2, x: float, y: float, radius: float, col: Color, w: float) -> void:
	c.draw_arc(_p(r, x, y), radius * r.size.x, 0.0, TAU, 40, col, w, true)


static func _dot(c: CanvasItem, r: Rect2, x: float, y: float, radius: float, col: Color) -> void:
	c.draw_circle(_p(r, x, y), radius * r.size.x, col, true, -1.0, true)


static func _rrect(c: CanvasItem, r: Rect2, unit: Rect2, col: Color, w: float, radius: float) -> void:
	var rect: Rect2 = Rect2(_p(r, unit.position.x, unit.position.y), unit.size * r.size)
	var pts: PackedVector2Array = rounded_rect_points(rect, radius * r.size.x)
	pts.append(pts[0])
	c.draw_polyline(pts, col, w, true)


## Contorno de un rectángulo redondeado como polígono (útil para recortar y rellenar).
static func rounded_rect_points(rect: Rect2, radius: float, segments: int = 6) -> PackedVector2Array:
	var rad: float = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var out: PackedVector2Array = PackedVector2Array()
	var corners: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - rad, rad), rect.end - Vector2(rad, rad),
		rect.position + Vector2(rad, rect.size.y - rad), rect.position + Vector2(rad, rad),
	]
	for k: int in corners.size():
		var start_angle: float = -PI * 0.5 + k * PI * 0.5
		for s: int in segments + 1:
			var a: float = start_angle + (PI * 0.5) * float(s) / segments
			var point: Vector2 = corners[k] + Vector2(cos(a), sin(a)) * rad
			if out.is_empty() or not out[out.size() - 1].is_equal_approx(point):
				out.append(point)
	if out.size() > 1 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out


## Puntos de una elipse (para huellas, gemas, etc.).
static func ellipse_points(center: Vector2, rx: float, ry: float, segments: int = 20) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for s: int in segments:
		var a: float = TAU * float(s) / segments
		out.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _icon_clock(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.5, 0.42, col, w)
	_line(c, r, 0.5, 0.5, 0.5, 0.24, col, w)
	_line(c, r, 0.5, 0.5, 0.68, 0.6, col, w)


static func _icon_coin(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.5, 0.42, col, w)
	c.draw_arc(_p(r, 0.56, 0.5), 0.2 * r.size.x, deg_to_rad(40.0), deg_to_rad(320.0), 24, col, w, true)
	_line(c, r, 0.26, 0.44, 0.52, 0.44, col, w * 0.8)
	_line(c, r, 0.26, 0.56, 0.52, 0.56, col, w * 0.8)


static func _icon_shield(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var coords: Array = [0.5, 0.06, 0.86, 0.2, 0.82, 0.56, 0.5, 0.92, 0.18, 0.56, 0.14, 0.2]
	_fill(c, r, coords, Color(col, col.a * 0.28))
	_poly(c, r, coords, col, w, true)
	_poly(c, r, [0.34, 0.48, 0.46, 0.6, 0.68, 0.36], col, w)


static func _icon_eye(c: CanvasItem, r: Rect2, col: Color, w: float, slashed: bool) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for s: int in 13:
		var t: float = float(s) / 12.0
		pts.append(_p(r, 0.06 + 0.88 * t, 0.5 - 0.34 * sin(PI * t)))
	for s: int in range(11, 0, -1):
		var t: float = float(s) / 12.0
		pts.append(_p(r, 0.06 + 0.88 * t, 0.5 + 0.34 * sin(PI * t)))
	pts.append(pts[0])
	c.draw_polyline(pts, col, w, true)
	_dot(c, r, 0.5, 0.5, 0.14, col)
	if slashed:
		_line(c, r, 0.14, 0.88, 0.86, 0.12, col, w)


static func _icon_camera(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.06, 0.28, 0.6, 0.46), col, w, 0.08)
	_fill(c, r, [0.66, 0.44, 0.94, 0.3, 0.94, 0.72, 0.66, 0.58], col)
	_dot(c, r, 0.24, 0.44, 0.06, col)


static func _icon_no_entry(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.5, 0.42, col, w)
	_line(c, r, 0.28, 0.5, 0.72, 0.5, col, w * 1.8)


static func _icon_cross(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_line(c, r, 0.24, 0.24, 0.76, 0.76, col, w)
	_line(c, r, 0.76, 0.24, 0.24, 0.76, col, w)


static func _icon_clipboard(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.18, 0.14, 0.64, 0.8), col, w, 0.08)
	_fill(c, r, [0.36, 0.06, 0.64, 0.06, 0.64, 0.22, 0.36, 0.22], col)
	for y: float in [0.42, 0.58, 0.74]:
		_line(c, r, 0.32, y, 0.68, y, col, w * 0.8)


static func _icon_star(c: CanvasItem, r: Rect2, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for k: int in 10:
		var radius: float = 0.46 if k % 2 == 0 else 0.2
		var a: float = -PI * 0.5 + k * PI / 5.0
		pts.append(_p(r, 0.5 + cos(a) * radius, 0.54 + sin(a) * radius))
	c.draw_colored_polygon(pts, col)


static func _icon_hazard(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.5, 0.08, 0.94, 0.88, 0.06, 0.88], col, w, true)
	_line(c, r, 0.5, 0.36, 0.5, 0.62, col, w * 1.2)
	_dot(c, r, 0.5, 0.75, 0.06, col)


## Distintivo de peligro relleno (triángulo amarillo con signo de admiración en tinta).
static func draw_hazard_badge(c: CanvasItem, r: Rect2, fill: Color, ink: Color) -> void:
	_fill(c, r, [0.5, 0.04, 0.97, 0.9, 0.03, 0.9], ink)
	_fill(c, r, [0.5, 0.16, 0.86, 0.83, 0.14, 0.83], fill)
	_line(c, r, 0.5, 0.38, 0.5, 0.6, ink, maxf(r.size.x * 0.1, 1.5))
	_dot(c, r, 0.5, 0.71, 0.055, ink)


static func _icon_info(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.5, 0.42, col, w)
	_dot(c, r, 0.5, 0.3, 0.06, col)
	_line(c, r, 0.5, 0.44, 0.5, 0.72, col, w * 1.2)


static func _icon_target(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.5, 0.38, col, w)
	_dot(c, r, 0.5, 0.5, 0.13, col)


static func _icon_take(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_line(c, r, 0.5, 0.1, 0.5, 0.6, col, w)
	_poly(c, r, [0.3, 0.42, 0.5, 0.62, 0.7, 0.42], col, w)
	_poly(c, r, [0.12, 0.62, 0.12, 0.88, 0.88, 0.88, 0.88, 0.62], col, w)


static func _icon_talk(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.08, 0.12, 0.84, 0.56), col, w, 0.14)
	_poly(c, r, [0.3, 0.68, 0.24, 0.9, 0.48, 0.68], col, w)
	for x: float in [0.32, 0.5, 0.68]:
		_dot(c, r, x, 0.4, 0.05, col)


static func _icon_door(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.22, 0.06, 0.56, 0.88), col, w, 0.04)
	_dot(c, r, 0.64, 0.52, 0.06, col)
	_line(c, r, 0.08, 0.94, 0.92, 0.94, col, w)


static func _icon_computer(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.06, 0.12, 0.88, 0.58), col, w, 0.06)
	_line(c, r, 0.5, 0.7, 0.5, 0.84, col, w)
	_line(c, r, 0.28, 0.88, 0.72, 0.88, col, w)


static func _icon_phone(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.26, 0.05, 0.48, 0.9), col, w, 0.1)
	_dot(c, r, 0.5, 0.82, 0.05, col)
	_line(c, r, 0.42, 0.13, 0.58, 0.13, col, w * 0.8)


static func _icon_map(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var coords: Array = [0.06, 0.2, 0.36, 0.1, 0.64, 0.2, 0.94, 0.1, 0.94, 0.8, 0.64, 0.9, 0.36, 0.8, 0.06, 0.9]
	_poly(c, r, coords, col, w, true)
	_line(c, r, 0.36, 0.1, 0.36, 0.8, col, w * 0.8)
	_line(c, r, 0.64, 0.2, 0.64, 0.9, col, w * 0.8)


static func _icon_bag(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.14, 0.36, 0.86, 0.36, 0.92, 0.92, 0.08, 0.92], col, w, true)
	c.draw_arc(_p(r, 0.5, 0.36), 0.2 * r.size.x, PI, TAU, 20, col, w, true)
	_line(c, r, 0.3, 0.56, 0.7, 0.56, col, w * 0.8)


static func _icon_elevator(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.14, 0.06, 0.72, 0.88), col, w, 0.08)
	_fill(c, r, [0.5, 0.18, 0.68, 0.42, 0.32, 0.42], col)
	_fill(c, r, [0.32, 0.58, 0.68, 0.58, 0.5, 0.82], col)


static func _icon_sleep(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.1, 0.46, 0.5, 0.46, 0.1, 0.88, 0.5, 0.88], col, w)
	_poly(c, r, [0.58, 0.12, 0.88, 0.12, 0.58, 0.4, 0.88, 0.4], col, w * 0.8)


static func _icon_lock(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.2, 0.44, 0.6, 0.48), col, w, 0.08)
	c.draw_arc(_p(r, 0.5, 0.44), 0.19 * r.size.x, PI, TAU, 20, col, w, true)
	_line(c, r, 0.31, 0.44, 0.31, 0.46, col, w)
	_dot(c, r, 0.5, 0.64, 0.06, col)
	_line(c, r, 0.5, 0.66, 0.5, 0.78, col, w)


static func _icon_trash(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_line(c, r, 0.12, 0.24, 0.88, 0.24, col, w)
	_poly(c, r, [0.38, 0.24, 0.38, 0.1, 0.62, 0.1, 0.62, 0.24], col, w)
	_poly(c, r, [0.22, 0.3, 0.78, 0.3, 0.72, 0.92, 0.28, 0.92], col, w, true)
	_line(c, r, 0.42, 0.42, 0.42, 0.8, col, w * 0.7)
	_line(c, r, 0.58, 0.42, 0.58, 0.8, col, w * 0.7)


static func _icon_key(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.28, 0.5, 0.17, col, w)
	_line(c, r, 0.45, 0.5, 0.92, 0.5, col, w)
	_line(c, r, 0.76, 0.5, 0.76, 0.68, col, w)
	_line(c, r, 0.88, 0.5, 0.88, 0.63, col, w)


static func _icon_tool(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_line(c, r, 0.16, 0.84, 0.54, 0.46, col, w * 2.0)
	c.draw_arc(_p(r, 0.66, 0.34), 0.2 * r.size.x, deg_to_rad(80.0), deg_to_rad(370.0), 24, col, w * 1.6, true)


static func _icon_card(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.06, 0.2, 0.88, 0.6), col, w, 0.08)
	_fill(c, r, [0.06, 0.34, 0.94, 0.34, 0.94, 0.44, 0.06, 0.44], col)
	_fill(c, r, [0.16, 0.56, 0.36, 0.56, 0.36, 0.68, 0.16, 0.68], col)


static func _icon_food(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.16, 0.34, 0.72, 0.34, 0.66, 0.88, 0.22, 0.88], col, w, true)
	c.draw_arc(_p(r, 0.72, 0.56), 0.13 * r.size.x, -PI * 0.5, PI * 0.5, 16, col, w, true)
	_line(c, r, 0.36, 0.1, 0.36, 0.24, col, w * 0.8)
	_line(c, r, 0.52, 0.08, 0.52, 0.24, col, w * 0.8)


static func _icon_pencil(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.22, 0.78, 0.7, 0.3, 0.82, 0.42, 0.34, 0.9], col, w, true)
	_fill(c, r, [0.22, 0.78, 0.34, 0.9, 0.12, 0.96], col)
	_line(c, r, 0.62, 0.38, 0.74, 0.5, col, w * 0.8)


static func _icon_shirt(c: CanvasItem, r: Rect2, col: Color, w: float, badge: bool) -> void:
	var coords: Array = [0.32, 0.12, 0.42, 0.2, 0.58, 0.2, 0.68, 0.12, 0.94, 0.32, 0.82, 0.48,
			0.72, 0.42, 0.72, 0.92, 0.28, 0.92, 0.28, 0.42, 0.18, 0.48, 0.06, 0.32]
	_poly(c, r, coords, col, w, true)
	if badge:
		_icon_star(c, Rect2(_p(r, 0.46, 0.4), r.size * 0.22), col)


static func _icon_cash(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.04, 0.22, 0.92, 0.56), col, w, 0.06)
	_ring(c, r, 0.5, 0.5, 0.14, col, w)
	_dot(c, r, 0.17, 0.5, 0.05, col)
	_dot(c, r, 0.83, 0.5, 0.05, col)


static func _icon_shoe(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var coords: Array = [0.08, 0.3, 0.3, 0.3, 0.42, 0.5, 0.64, 0.56, 0.88, 0.62, 0.94, 0.74,
			0.94, 0.82, 0.08, 0.82]
	_fill(c, r, coords, Color(col, col.a * 0.25))
	_poly(c, r, coords, col, w, true)
	_line(c, r, 0.08, 0.72, 0.94, 0.72, col, w * 0.8)
	_line(c, r, 0.34, 0.46, 0.44, 0.4, col, w * 0.7)


static func _icon_roll(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.34, 0.5, 0.28, col, w)
	_ring(c, r, 0.34, 0.5, 0.09, col, w)
	_poly(c, r, [0.34, 0.22, 0.9, 0.22, 0.9, 0.78, 0.34, 0.78], col, w)


static func _icon_gem(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var coords: Array = [0.28, 0.14, 0.72, 0.14, 0.92, 0.38, 0.5, 0.9, 0.08, 0.38]
	_fill(c, r, coords, Color(col, col.a * 0.25))
	_poly(c, r, coords, col, w, true)
	_line(c, r, 0.08, 0.38, 0.92, 0.38, col, w * 0.8)
	_poly(c, r, [0.36, 0.38, 0.5, 0.9, 0.64, 0.38], col, w * 0.7)


static func _icon_document(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_poly(c, r, [0.18, 0.06, 0.62, 0.06, 0.82, 0.26, 0.82, 0.94, 0.18, 0.94], col, w, true)
	_poly(c, r, [0.62, 0.06, 0.62, 0.26, 0.82, 0.26], col, w * 0.8)
	for y: float in [0.46, 0.6, 0.74]:
		_line(c, r, 0.3, y, 0.7, y, col, w * 0.7)


static func _icon_person(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_ring(c, r, 0.5, 0.3, 0.17, col, w)
	c.draw_arc(_p(r, 0.5, 0.94), 0.34 * r.size.x, PI, TAU, 24, col, w, true)


## Huellas de pies descalzos (planta + dedos), una adelantada: sigilo.
static func _icon_sneak(c: CanvasItem, r: Rect2, col: Color, _w: float) -> void:
	_footprint(c, r, Vector2(0.31, 0.68), col)
	_footprint(c, r, Vector2(0.69, 0.3), col)


static func _footprint(c: CanvasItem, r: Rect2, at: Vector2, col: Color) -> void:
	c.draw_colored_polygon(ellipse_points(_p(r, at.x, at.y + 0.05), 0.125 * r.size.x, 0.18 * r.size.y), col)
	var toes: Array[Vector3] = [Vector3(-0.09, -0.19, 0.05), Vector3(-0.025, -0.215, 0.043),
			Vector3(0.035, -0.205, 0.037), Vector3(0.085, -0.175, 0.031)]
	for toe: Vector3 in toes:
		_dot(c, r, at.x + toe.x, at.y + toe.y, toe.z, col)


## Figura agachada: espalda doblada y rodillas flexionadas sobre una línea de suelo.
static func _icon_crouch(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	var s: float = w * 1.25
	_dot(c, r, 0.34, 0.3, 0.1, col)
	_poly(c, r, [0.42, 0.42, 0.62, 0.52, 0.66, 0.62], col, s)
	_poly(c, r, [0.66, 0.62, 0.42, 0.7, 0.5, 0.86], col, s)
	_poly(c, r, [0.66, 0.62, 0.8, 0.74, 0.76, 0.86], col, s)
	_line(c, r, 0.47, 0.46, 0.36, 0.64, col, s)
	_line(c, r, 0.12, 0.93, 0.88, 0.93, col, w)


## Caja fuerte: cuerpo, rueda de combinación y bisagras.
static func _icon_safe(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_rrect(c, r, Rect2(0.1, 0.1, 0.8, 0.74), col, w, 0.08)
	_ring(c, r, 0.5, 0.47, 0.19, col, w)
	_dot(c, r, 0.5, 0.47, 0.05, col)
	_line(c, r, 0.5, 0.28, 0.5, 0.36, col, w * 0.8)
	_line(c, r, 0.2, 0.84, 0.2, 0.94, col, w)
	_line(c, r, 0.8, 0.84, 0.8, 0.94, col, w)


## Oreja (puntos de escucha).
static func _icon_ear(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	c.draw_arc(_p(r, 0.52, 0.4), 0.3 * r.size.x, PI * 0.95, TAU + PI * 0.3, 28, col, w, true)
	_poly(c, r, [0.78, 0.55, 0.62, 0.72, 0.58, 0.88, 0.42, 0.92, 0.34, 0.84], col, w)
	c.draw_arc(_p(r, 0.52, 0.42), 0.12 * r.size.x, PI, TAU + PI * 0.25, 16, col, w * 0.8, true)
	_line(c, r, 0.4, 0.42, 0.46, 0.6, col, w * 0.8)


static func _icon_chevrons(c: CanvasItem, r: Rect2, col: Color, w: float, down: bool) -> void:
	if down:
		_poly(c, r, [0.2, 0.28, 0.5, 0.52, 0.8, 0.28], col, w)
		_poly(c, r, [0.2, 0.52, 0.5, 0.76, 0.8, 0.52], col, w)
	else:
		_poly(c, r, [0.2, 0.2, 0.46, 0.5, 0.2, 0.8], col, w)
		_poly(c, r, [0.52, 0.2, 0.78, 0.5, 0.52, 0.8], col, w)


static func _icon_speaker(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_fill(c, r, [0.08, 0.38, 0.28, 0.38, 0.5, 0.16, 0.5, 0.84, 0.28, 0.62, 0.08, 0.62], col)
	c.draw_arc(_p(r, 0.5, 0.5), 0.2 * r.size.x, -PI * 0.3, PI * 0.3, 12, col, w, true)
	c.draw_arc(_p(r, 0.5, 0.5), 0.36 * r.size.x, -PI * 0.3, PI * 0.3, 16, col, w, true)


static func _icon_moon(c: CanvasItem, r: Rect2, col: Color) -> void:
	var outer: PackedVector2Array = ellipse_points(_p(r, 0.46, 0.54), 0.4 * r.size.x, 0.4 * r.size.y, 32)
	var bite: PackedVector2Array = ellipse_points(_p(r, 0.66, 0.38), 0.32 * r.size.x, 0.32 * r.size.y, 32)
	for piece: PackedVector2Array in Geometry2D.clip_polygons(outer, bite):
		if piece.size() >= 3:
			c.draw_colored_polygon(piece, col)


static func _icon_plus(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	_line(c, r, 0.5, 0.18, 0.5, 0.82, col, w)
	_line(c, r, 0.18, 0.5, 0.82, 0.5, col, w)


static func _icon_bug(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	c.draw_colored_polygon(ellipse_points(_p(r, 0.5, 0.58), 0.22 * r.size.x, 0.3 * r.size.y), col)
	_dot(c, r, 0.5, 0.22, 0.12, col)
	for y: float in [0.46, 0.62, 0.78]:
		_line(c, r, 0.12, y, 0.88, y, col, w * 0.7)


# ─── Widgets compartidos ───────────────────────────────────────────

## Icono vectorial como Control. Color: tint (si alfa > 0) o el color de tema `color_name`.
class IconView extends Control:
	var icon: String = "target"
	var color_name: String = "paper"
	var tint: Color = Color(0, 0, 0, 0)
	var angle: float = 0.0
	var icon_scale: float = 1.0

	func _init(p_icon: String = "target", p_color_name: String = "paper", p_scale: float = 1.0) -> void:
		icon = p_icon
		color_name = p_color_name
		icon_scale = p_scale
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			var s: float = get_theme_constant("icon", UITheme.HUD_TYPE) * icon_scale
			custom_minimum_size = Vector2(s, s)
			queue_redraw()

	func set_icon(p_icon: String) -> void:
		if icon != p_icon:
			icon = p_icon
			queue_redraw()

	func set_color_name(p_name: String) -> void:
		color_name = p_name
		queue_redraw()

	func set_tint(p_tint: Color) -> void:
		tint = p_tint
		queue_redraw()

	func set_angle(p_angle: float) -> void:
		angle = p_angle
		queue_redraw()

	func _draw() -> void:
		var col: Color = tint if tint.a > 0.0 else get_theme_color(color_name, UITheme.HUD_TYPE)
		var side: float = minf(size.x, size.y)
		var w: float = maxf(side * 0.09, 1.5)
		draw_set_transform(size * 0.5, angle, Vector2.ONE)
		UITheme.draw_icon(self, icon, Rect2(Vector2.ONE * -side * 0.5, Vector2(side, side)), col, w)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Barra de medidor redondeada con marcas de cuartos. `striped` añade rayado (forma además de color).
class MeterBar extends Control:
	var value: float = 0.0
	var max_value: float = 100.0
	var color_name: String = "rep"
	var track_name: String = "rep_track"
	var striped: bool = false
	var width_factor: float = 1.0

	func _init(p_color: String = "rep", p_track: String = "rep_track", p_striped: bool = false) -> void:
		color_name = p_color
		track_name = p_track
		striped = p_striped
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
			var w: float = get_theme_constant("bar_w", UITheme.HUD_TYPE) * width_factor
			custom_minimum_size = Vector2(w, get_theme_constant("bar_h", UITheme.HUD_TYPE))
			queue_redraw()

	func set_value(v: float) -> void:
		value = clampf(v, 0.0, max_value)
		queue_redraw()

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var radius: float = size.y * 0.5
		var col: Color = get_theme_color(color_name, UITheme.HUD_TYPE)
		draw_colored_polygon(UITheme.rounded_rect_points(r, radius), get_theme_color(track_name, UITheme.HUD_TYPE))
		var ratio: float = 0.0 if max_value <= 0.0 else value / max_value
		if ratio > 0.0:
			var fill: PackedVector2Array = UITheme.rounded_rect_points(
					Rect2(r.position, Vector2(maxf(size.x * ratio, size.y), size.y)), radius)
			draw_colored_polygon(fill, col)
			if striped:
				UITheme.draw_stripes(self, fill, Rect2(r.position, Vector2(size.x * ratio, size.y)),
						Color(0, 0, 0, 0.35), size.y * 0.9)
		for q: float in [0.25, 0.5, 0.75]:
			var x: float = size.x * q
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), Color(get_theme_color("ink", UITheme.HUD_TYPE), 0.55), 2.0)
		var outline: PackedVector2Array = UITheme.rounded_rect_points(r, radius)
		outline.append(outline[0])
		draw_polyline(outline, Color(col, 0.55), 1.5, true)


## Etiqueta que puede tacharse (deberes cumplidos §13.1).
class StrikeLabel extends Label:
	var struck: bool = false
	var strike_color_name: String = "muted"

	func set_struck(on: bool, p_color_name: String = "muted") -> void:
		struck = on
		strike_color_name = p_color_name
		queue_redraw()

	func _draw() -> void:
		if not struck or text.is_empty():
			return
		var f: Font = get_theme_font("font")
		var fs: int = get_theme_font_size("font_size")
		var width: float = minf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x)
		var y: float = size.y * 0.54
		var col: Color = get_theme_color(strike_color_name, UITheme.HUD_TYPE)
		draw_line(Vector2(-2, y), Vector2(width + 2, y), col, maxf(fs * 0.09, 2.0), true)


## Rayas diagonales recortadas a un polígono (textura de peligro / rayado de medidor).
static func draw_stripes(c: CanvasItem, clip: PackedVector2Array, bounds: Rect2, col: Color, period: float) -> void:
	var step: float = maxf(period, 4.0)
	var x: float = bounds.position.x - bounds.size.y
	while x < bounds.end.x:
		var band: PackedVector2Array = PackedVector2Array([
			Vector2(x, bounds.end.y), Vector2(x + step * 0.5, bounds.end.y),
			Vector2(x + step * 0.5 + bounds.size.y, bounds.position.y), Vector2(x + bounds.size.y, bounds.position.y),
		])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, clip):
			c.draw_colored_polygon(piece, col)
		x += step
