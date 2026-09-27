# menu_kit.gd — Utilidades compartidas de menús y cinemáticas: paleta, fuentes, tema y balance.
# PROPIETARIO DE: nada (cachés de solo lectura de balance.json y art_bands.json para la interfaz).
# ESCUCHA: nada.
class_name MenuKit
extends RefCounted

## Los colores salen de data/art_bands.json (paletas por banda) y de balance `menus.*`.
## Los tunables se leen con bal(): Database.get_balance() si la ruta existe (Database.has_balance);
## si no (Database en stub o clave añadida después de cargar), balance.json directamente (solo lectura).

const BALANCE_FILE := "res://data/balance.json"
const BANDS_FILE := "res://data/art_bands.json"
const UI_THEME_SCRIPT := "res://src/ui/ui_theme.gd"
const MONO_FONT_NAMES: PackedStringArray = ["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"]
## Tipografías OFL compartidas con UITheme (si faltan, la del motor).
const FONT_REGULAR_FILE := "res://assets/fonts/Inter-Regular.ttf"
const FONT_HEAVY_FILE := "res://assets/fonts/Inter-ExtraBold.ttf"
const FONT_MONO_FILE := "res://assets/fonts/JetBrainsMono-Medium.ttf"

## Tamaños de letra de referencia (px a 1080 de alto) — maquetación, no tunables.
const FONT_SMALL := 24
const FONT_BODY := 30
const FONT_BUTTON := 34
const FONT_HEADING := 52
const FONT_DISPLAY := 84
const FONT_TITLE := 150
const OUTLINE := 4
const SHADOW := 7
const MIN_TOUCH := 64

## Nombre semántico → [banda, clave de paleta] de art_bands.json.
const SEMANTIC: Dictionary = {
	"ink": ["exterior", "outline"], "night": ["exterior", "shadow"], "dusk": ["exterior", "floor"],
	"slate": ["exterior", "wall"], "steel": ["exterior", "furniture"], "amber": ["exterior", "accent"],
	"lamp": ["exterior", "window"], "paper": ["the_throne", "light"], "paper_dim": ["the_throne", "carpet"],
	"marble": ["the_throne", "floor"], "gold": ["the_throne", "accent"], "green": ["the_pit", "accent"],
	"sick": ["the_pit", "light"], "blue": ["the_specialists", "accent"], "navy": ["the_power", "carpet"],
	"orange": ["factory", "accent"], "wood": ["the_power", "furniture"], "guts": ["the_guts", "accent"],
}

static var _balance: Dictionary = {}
static var _bands: Dictionary = {}
static var _floor_bands: Dictionary = {}
static var _fonts: Dictionary = {}
## Cachés de colores resueltos y de escala de texto: se revalidan una vez por fotograma (o al
## cambiar un ajuste, invalidate_cache) para no consultar SaveSystem en cada llamada de dibujo.
static var _color_cache: Dictionary = {}
static var _cache_frame: int = -1
static var _cache_hc: bool = false
static var _cache_scale: float = 1.0


# ─── Balance ───────────────────────────────────────────────────

## Valor de balance por ruta con puntos ("menus.apertura.m1_segundos").
static func bal(path: String) -> Variant:
	if Database.has_method("has_balance") and bool(Database.call("has_balance", path)):
		return Database.get_balance(path)
	return _walk(_balance_data(), path)


static func bal_float(path: String) -> float:
	var value: Variant = bal(path)
	return float(value) if (value is float or value is int) else 0.0


static func bal_int(path: String) -> int:
	var value: Variant = bal(path)
	return int(value) if (value is float or value is int) else 0


static func bal_dict(path: String) -> Dictionary:
	var value: Variant = bal(path)
	return value if value is Dictionary else {}


static func _balance_data() -> Dictionary:
	if _balance.is_empty():
		_balance = read_json(BALANCE_FILE)
	return _balance


static func _walk(data: Dictionary, path: String) -> Variant:
	var node: Variant = data
	for part: String in path.split("."):
		if not (node is Dictionary) or not (node as Dictionary).has(part):
			return null
		node = (node as Dictionary)[part]
	return node


## Lee un JSON de data/ (solo lectura). {} si falta o está mal formado.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


# ─── Paleta ────────────────────────────────────────────────────

## Paleta (clave → Color) de una banda de art_bands.json.
static func band_palette(band_id: String) -> Dictionary:
	if _bands.is_empty():
		_load_bands()
	var band: Dictionary = _bands.get(band_id, {})
	return band.get("colors", {})


## Banda (Dictionary de art_bands.json) a la que pertenece una planta.
static func band_for_floor(floor_number: int) -> Dictionary:
	if _bands.is_empty():
		_load_bands()
	var band: Variant = _floor_bands.get(floor_number)
	return band if band != null else _bands.get("the_pit", {})


static func _load_bands() -> void:
	var list: Array = []
	if Database.has_method("get_all_art_bands"):
		list = Database.call("get_all_art_bands")
	if list.is_empty():
		list = read_json(BANDS_FILE).get("bands", [])
	for raw: Variant in list:
		if not (raw is Dictionary):
			continue
		var band: Dictionary = (raw as Dictionary).duplicate()
		var colors: Dictionary = {}
		var palette: Dictionary = band.get("palette", {})
		for key: String in palette:
			colors[key] = Color.from_string(str(palette[key]), Color.MAGENTA)
		band["colors"] = colors
		var floors: Array = []
		for f: Variant in band.get("floors", []):
			floors.append(int(f))
		band["floors"] = floors
		_bands[str(band.get("id", ""))] = band
		for f: int in floors:
			if not _floor_bands.has(f):
				_floor_bands[f] = band


## Olvida las cachés de color y escala (lo llama SettingsMenu al aplicar un ajuste).
static func invalidate_cache() -> void:
	_cache_frame = -1


## Revalida las cachés como mucho una vez por fotograma.
static func _refresh_cache() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _cache_frame:
		return
	_cache_frame = frame
	var hc: bool = SettingsMenu.get_bool("high_contrast")
	if hc != _cache_hc:
		_color_cache.clear()
	_cache_hc = hc
	_cache_scale = _read_text_scale()


## true con el ajuste de alto contraste activo (§13.10).
static func is_high_contrast() -> bool:
	_refresh_cache()
	return _cache_hc


## Color semántico de la interfaz (ver SEMANTIC). En alto contraste, fondo/texto/foco duros.
static func color(semantic: String) -> Color:
	_refresh_cache()
	var cached: Variant = _color_cache.get(semantic)
	if cached != null:
		return cached
	var resolved: Color = _resolve_color(semantic)
	_color_cache[semantic] = resolved
	return resolved


static func _resolve_color(semantic: String) -> Color:
	if _cache_hc:
		var hc: Color = _high_contrast(semantic)
		if hc.a > 0.0:
			return hc
	var pair: Array = SEMANTIC.get(semantic, ["exterior", "outline"])
	return band_palette(str(pair[0])).get(str(pair[1]), Color.MAGENTA)


## Color de rótulos pequeños (antetítulos, cabeceras de sección) derivado de `base`; en alto
## contraste, tinta pura: los derivados oscurecidos del amarillo de foco no alcanzan AA (§13.10).
static func heading_color(base: Color) -> Color:
	return color("ink") if is_high_contrast() else base


static func _high_contrast(semantic: String) -> Color:
	var table: Dictionary = bal_dict("menus.alto_contraste")
	var key: String = ""
	match semantic:
		"ink", "night", "dusk", "slate":
			key = "fondo"
		"paper", "marble":
			key = "texto"
		"amber", "gold", "lamp":
			key = "foco"
	if key.is_empty():
		return Color(0, 0, 0, 0)
	return Color.from_string(str(table.get(key, "")), Color(0, 0, 0, 0))


## Color de tinte de un eje de seguimiento ("blood", "gold", "silk", "sweat", "hybrid", "defeat").
static func axis_color(axis: String) -> Color:
	var key: String = "axis:" + axis
	var cached: Variant = _color_cache.get(key)
	if cached != null:
		return cached
	var table: Dictionary = bal_dict("menus.tinte_eje")
	var resolved: Color = Color.from_string(str(table.get(axis, table.get("hybrid", ""))), color("gold"))
	_color_cache[key] = resolved
	return resolved


# ─── Fuentes ───────────────────────────────────────────────────

## Fuentes: "body", "bold", "display" (condensada y gruesa, logotipo), "italic", "mono".
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var made: Font = _make_font(kind)
	_fonts[kind] = made
	return made


static func _make_font(kind: String) -> Font:
	if kind == "mono":
		return _mono_font()
	var heavy: bool = kind == "bold" or kind == "display"
	var file_font: Font = _file_font(FONT_HEAVY_FILE if heavy else FONT_REGULAR_FILE)
	var variation: FontVariation = FontVariation.new()
	variation.base_font = file_font if file_font != null else ThemeDB.fallback_font
	match kind:
		"bold":
			if file_font == null:
				variation.variation_embolden = 0.6
		"display":
			variation.variation_embolden = 0.35 if file_font != null else 1.1
			variation.variation_transform = Transform2D(Vector2(0.86, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
			variation.spacing_glyph = -1
		"italic":
			variation.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	return variation


static func _file_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Font


static func _mono_font() -> Font:
	var file_font: Font = _file_font(FONT_MONO_FILE)
	if file_font != null:
		return file_font
	var mono: SystemFont = SystemFont.new()
	mono.font_names = MONO_FONT_NAMES
	mono.fallbacks = [ThemeDB.fallback_font]
	return mono


## Multiplicador del tamaño de texto (§13.10: tres niveles).
static func text_scale() -> float:
	_refresh_cache()
	return _cache_scale


static func _read_text_scale() -> float:
	var levels: Variant = bal("menus.escala_texto")
	var level: int = SettingsMenu.get_int("text_size")
	if levels is Array and not (levels as Array).is_empty():
		return float((levels as Array)[clampi(level, 0, (levels as Array).size() - 1)])
	return 1.0


static func fs(base_size: int) -> int:
	return roundi(base_size * text_scale())


# ─── Tema ──────────────────────────────────────────────────────

## Tema de menús: parte de UITheme (si existe) y aplica el estilo de póster plano con contorno.
static func build_theme() -> Theme:
	var theme: Theme = _base_theme()
	theme.default_font = font("body")
	theme.default_font_size = fs(FONT_BODY)
	_style_buttons(theme)
	_style_menu_items(theme)
	_style_toggles(theme)
	_style_inputs(theme)
	_style_containers(theme)
	_style_labels(theme)
	return theme


static func _base_theme() -> Theme:
	if ResourceLoader.exists(UI_THEME_SCRIPT):
		var script: GDScript = load(UI_THEME_SCRIPT) as GDScript
		if script != null and script.has_method("build"):
			var level: int = SettingsMenu.get_int("text_size")
			var built: Variant = script.call("build", level, SettingsMenu.get_bool("high_contrast"))
			if built is Theme:
				return (built as Theme).duplicate() as Theme
	return Theme.new()


## Caja plana con contorno y sombra dura desplazada (estética de póster corporativo).
static func box(fill: Color, border: Color, border_px: int = OUTLINE, shadow_px: int = SHADOW) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_px)
	sb.set_corner_radius_all(3)
	sb.shadow_color = color("ink")
	sb.shadow_size = 1 if shadow_px > 0 else 0
	sb.shadow_offset = Vector2(shadow_px, shadow_px)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func _style_buttons(theme: Theme) -> void:
	var ink: Color = color("ink")
	theme.set_stylebox("normal", "Button", box(color("paper"), ink))
	theme.set_stylebox("hover", "Button", box(color("amber"), ink))
	var pressed: StyleBoxFlat = box(color("gold"), ink, OUTLINE, 2)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", box(color("paper_dim"), color("steel"), OUTLINE, 0))
	var focus: StyleBoxFlat = box(Color(0, 0, 0, 0), color("amber"), OUTLINE + 2, 0)
	focus.expand_margin_left = 6
	focus.expand_margin_right = 6
	focus.expand_margin_top = 6
	focus.expand_margin_bottom = 6
	theme.set_stylebox("focus", "Button", focus)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color"]:
		theme.set_color(key, "Button", ink)
	theme.set_color("font_disabled_color", "Button", color("steel"))
	theme.set_font("font", "Button", font("bold"))
	theme.set_font_size("font_size", "Button", fs(FONT_BUTTON))


## Variación "TWToggle": opciones seleccionables (controles segmentados, tarjetas de contrato).
static func _style_toggles(theme: Theme) -> void:
	theme.set_type_variation("TWToggle", "Button")
	var ink: Color = color("ink")
	theme.set_stylebox("normal", "TWToggle", box(color("paper"), ink, OUTLINE, 3))
	theme.set_stylebox("hover", "TWToggle", box(color("paper").lerp(color("amber"), 0.3), ink, OUTLINE, 3))
	var on: StyleBoxFlat = box(color("amber"), ink, OUTLINE + 1, SHADOW)
	theme.set_stylebox("pressed", "TWToggle", on)
	theme.set_stylebox("hover_pressed", "TWToggle", on)


## Variación "TWMenuItem": elementos del menú principal, texto claro sobre la noche.
static func _style_menu_items(theme: Theme) -> void:
	theme.set_type_variation("TWMenuItem", "Button")
	var clear: StyleBoxFlat = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	var lit: StyleBoxFlat = box(color("amber"), color("ink"), OUTLINE, SHADOW)
	for sb: StyleBoxFlat in [clear, lit]:
		sb.content_margin_left = 18
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
	theme.set_stylebox("normal", "TWMenuItem", clear)
	theme.set_stylebox("disabled", "TWMenuItem", clear)
	for state: String in ["hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "TWMenuItem", lit)
	theme.set_color("font_color", "TWMenuItem", color("paper"))
	for key: String in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, "TWMenuItem", color("ink"))
	theme.set_color("font_disabled_color", "TWMenuItem", color("steel"))
	theme.set_color("font_outline_color", "TWMenuItem", color("ink"))
	theme.set_constant("outline_size", "TWMenuItem", 0)
	theme.set_font("font", "TWMenuItem", font("display"))
	theme.set_font_size("font_size", "TWMenuItem", fs(FONT_HEADING - 6))


static func _style_inputs(theme: Theme) -> void:
	var ink: Color = color("ink")
	var field: StyleBoxFlat = box(color("paper"), ink, OUTLINE, 0)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), color("amber"), OUTLINE + 2, 0))
	theme.set_color("font_color", "LineEdit", ink)
	theme.set_color("font_placeholder_color", "LineEdit", color("steel"))
	theme.set_color("caret_color", "LineEdit", ink)
	theme.set_font("font", "LineEdit", font("bold"))
	theme.set_font_size("font_size", "LineEdit", fs(FONT_HEADING))
	var track: StyleBoxFlat = box(color("paper_dim"), ink, 3, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", track)
	var fill: StyleBoxFlat = box(color("amber"), ink, 3, 0)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	theme.set_icon("grabber", "HSlider", _knob(color("paper")))
	theme.set_icon("grabber_highlight", "HSlider", _knob(color("amber")))
	theme.set_color("font_color", "CheckButton", ink)
	theme.set_font_size("font_size", "CheckButton", fs(FONT_BODY))


## Pomo de deslizador dibujado por código (círculo con contorno).
static func _knob(fill: Color) -> ImageTexture:
	var size: int = 36
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(size, size) * 0.5
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= size * 0.5 - 0.5:
				img.set_pixel(x, y, color("ink") if d > size * 0.5 - 5.0 else fill)
	return ImageTexture.create_from_image(img)


static func _style_containers(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", box(color("paper"), color("ink"), OUTLINE, SHADOW * 2))
	theme.set_type_variation("TWCard", "PanelContainer")
	theme.set_stylebox("panel", "TWCard", box(color("paper"), color("ink"), OUTLINE, SHADOW))
	var flat: StyleBoxEmpty = StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", flat)
	theme.set_constant("separation", "VBoxContainer", 14)
	theme.set_constant("separation", "HBoxContainer", 14)
	theme.set_constant("h_separation", "GridContainer", 24)
	theme.set_constant("v_separation", "GridContainer", 24)
	_style_scrollbars(theme)


## Barra de desplazamiento visible y táctil: carril claro con contorno y tirador ámbar.
static func _style_scrollbars(theme: Theme) -> void:
	var ink: Color = color("ink")
	var track: StyleBoxFlat = box(color("paper_dim"), ink, 2, 0)
	var grab: StyleBoxFlat = box(color("amber"), ink, 2, 0)
	var grab_hot: StyleBoxFlat = box(color("gold"), ink, 2, 0)
	for sb: StyleBoxFlat in [track, grab, grab_hot]:
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("scroll_focus", "VScrollBar", track)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grab_hot)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grab_hot)


static func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", color("ink"))
	theme.set_type_variation("TWHeading", "Label")
	theme.set_font("font", "TWHeading", font("display"))
	theme.set_font_size("font_size", "TWHeading", fs(FONT_DISPLAY))
	theme.set_type_variation("TWSmall", "Label")
	theme.set_font_size("font_size", "TWSmall", fs(FONT_SMALL))
	theme.set_type_variation("TWLight", "Label")
	theme.set_color("font_color", "TWLight", color("paper"))


# ─── Fábricas de controles ─────────────────────────────────────

## Etiqueta con texto ya traducido. variation: "", "TWHeading", "TWSmall", "TWLight".
static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Botón con texto ya traducido y altura mínima táctil.
static func button(text: String, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, MIN_TOUCH)
	b.focus_mode = Control.FOCUS_ALL
	return b


## Marco de memorándum. Devuelve {root, panel, body, back, title, scroll, area}. El cuerpo va siempre
## en un MenuScroll (barra visible y aviso de «hay más»). compact = panel centrado que se ajusta a
## su contenido y solo desplaza si no cabe; si no, ocupa casi toda la pantalla.
static func memo_frame(title_text: String, kicker_text: String, compact: bool = false) -> Dictionary:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 260 if compact else 96)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36 if compact else 44)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_FILL
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var header: Dictionary = _memo_header(title_text, kicker_text)
	column.add_child(header["row"])
	column.add_child(rule(color("ink"), OUTLINE))
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	var area: MenuScroll = MenuScroll.new()
	area.name = "ScrollArea"
	area.fade_color = color("paper")
	area.set_content(body)
	if compact:
		area.fit_to(margin, panel)
	else:
		area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(area)
	return {"root": margin, "panel": panel, "body": body, "back": header["back"], "title": header["title"],
		"scroll": area.scroll, "area": area}


static func _memo_header(title_text: String, kicker_text: String) -> Dictionary:
	var header: HBoxContainer = HBoxContainer.new()
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var kicker: Label = label(kicker_text.to_upper(), "TWSmall")
	kicker.add_theme_font_override("font", font("bold"))
	kicker.add_theme_color_override("font_color", heading_color(color("gold").darkened(0.35)))
	titles.add_child(kicker)
	var title: Label = label(title_text, "TWHeading", true)
	titles.add_child(title)
	var back: Button = button(TranslationServer.translate("UI_BACK"))
	back.name = "Back"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	return {"row": header, "title": title, "back": back}


## true si una pantalla ya construida (built_locale no vacío) quedó en otro idioma y debe rehacerse.
## La notificación de traducción también llega al entrar en el árbol, antes de _ready().
static func locale_outdated(node: Node, built_locale: String) -> bool:
	return node.is_inside_tree() and not built_locale.is_empty() and built_locale != TranslationServer.get_locale()


## Da el foco al control en el siguiente fotograma, si sigue en el árbol.
static func focus_later(control: Control) -> void:
	var grab: Callable = func() -> void:
		if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
			control.grab_focus()
	grab.call_deferred()


## Línea horizontal plana.
static func rule(c: Color, thickness: int) -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.color = c
	line.custom_minimum_size = Vector2(0, thickness)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Pone una etiqueta en estilo póster: relleno claro, contorno de tinta y sombra dura.
static func poster_text(l: Label, font_kind: String, size: int, fill: Color, shadow: Color) -> void:
	l.add_theme_font_override("font", font(font_kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fill)
	l.add_theme_color_override("font_outline_color", color("ink"))
	l.add_theme_constant_override("outline_size", maxi(4, size / 10))
	l.add_theme_color_override("font_shadow_color", shadow)
	l.add_theme_constant_override("shadow_offset_x", maxi(3, size / 18))
	l.add_theme_constant_override("shadow_offset_y", maxi(3, size / 18))
	l.add_theme_constant_override("shadow_outline_size", maxi(4, size / 10))


## Traducción con relleno de formato seguro ({clave} → valor).
static func trf(key: String, values: Dictionary) -> String:
	return TranslationServer.translate(key).format(values)


const CHARACTER_PAINTER_SCRIPT := "res://src/entities/character_painter.gd"


## Retrato con el pintor de personajes compartido (§14.4) si existe; false si no (usar draw_person).
static func draw_portrait(canvas: CanvasItem, portrait_seed: int, tier: int, rect: Rect2) -> bool:
	if not ResourceLoader.exists(CHARACTER_PAINTER_SCRIPT):
		return false
	var painter: GDScript = load(CHARACTER_PAINTER_SCRIPT) as GDScript
	if painter == null or not painter.has_method("draw_portrait") or not painter.has_method("appearance_from_seed"):
		return false
	var appearance: Variant = painter.call("appearance_from_seed", portrait_seed, tier, false, "")
	if not (appearance is Dictionary):
		return false
	painter.call("draw_portrait", canvas, appearance, rect)
	return true


## Silueta sencilla de persona (cabeza + hombros + cuerpo) con contorno, vista 3/4.
static func draw_person(canvas: CanvasItem, feet: Vector2, height: float, body: Color, head: Color,
		outline: Color, facing_up: bool = false) -> void:
	var w: float = height * 0.36
	var head_r: float = height * 0.15
	var shoulder_y: float = feet.y - height * 0.66
	var torso: PackedVector2Array = [
		Vector2(feet.x - w * 0.5, feet.y), Vector2(feet.x - w * 0.55, shoulder_y + w * 0.18),
		Vector2(feet.x - w * 0.3, shoulder_y), Vector2(feet.x + w * 0.3, shoulder_y),
		Vector2(feet.x + w * 0.55, shoulder_y + w * 0.18), Vector2(feet.x + w * 0.5, feet.y),
	]
	var lw: float = maxf(1.0, height * 0.05)
	canvas.draw_colored_polygon(torso, body)
	canvas.draw_polyline(torso + PackedVector2Array([torso[0]]), outline, lw, true)
	var head_c: Vector2 = Vector2(feet.x, shoulder_y - head_r * (1.25 if facing_up else 1.0))
	canvas.draw_circle(head_c, head_r, head)
	canvas.draw_arc(head_c, head_r, 0.0, TAU, 20, outline, lw, true)


# ─── Audio (guardado: AudioDirector puede no existir aún) ──────

const AUDIO_DIRECTOR_SCRIPT := "res://src/ui/audio/audio_director.gd"
const AUDIO_GROUP := "audio_director"

## false = audio_call nunca crea un AudioDirector propio (pruebas: sin renders de música en hilos).
static var spawn_audio: bool = true


## Llama a un método de AudioDirector si existe (nodo del grupo "audio_director"). Si no hay ninguno
## y `create` es true, instancia uno propio hijo de `host`, solo si implementa `method`.
static func audio_call(host: Node, method: String, args: Array, create: bool = false) -> void:
	if host == null or not host.is_inside_tree():
		return
	var director: Node = host.get_tree().get_first_node_in_group(AUDIO_GROUP)
	if director == null and create and spawn_audio:
		director = _spawn_audio_director(host, method)
	if director != null and director.has_method(method):
		director.callv(method, args)


static func _spawn_audio_director(host: Node, method: String) -> Node:
	if not ResourceLoader.exists(AUDIO_DIRECTOR_SCRIPT):
		return null
	var script: GDScript = load(AUDIO_DIRECTOR_SCRIPT) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var director: Node = script.new() as Node
	if director == null or not director.has_method(method):
		if director != null:
			director.free()
		return null
	director.name = "MenuAudioDirector"
	director.add_to_group(AUDIO_GROUP)
	host.add_child(director)
	return director
