# menu_kit.gd — Utilidades compartidas de menús y cinemáticas: paleta, fuentes, tema y balance.
# PROPIETARIO DE: nada (cachés de solo lectura de balance.json y art_bands.json para la interfaz).
# ESCUCHA: nada.
class_name MenuKit
extends RefCounted

## Los colores salen de data/art_bands.json (paletas por banda) y de balance `menus.*`.
## Los tunables se leen con bal(): Database.get_balance() si Database ya cargó los datos;
## si no (Database aún sin cargar o en stub), se lee balance.json directamente (solo lectura).

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
static var _fonts: Dictionary = {}


# ─── Balance ───────────────────────────────────────────────────

## Valor de balance por ruta con puntos ("menus.apertura.m1_segundos").
static func bal(path: String) -> Variant:
	if Database.has_method("get_balance"):
		var value: Variant = Database.get_balance(path)
		if value != null:
			return value
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
	for band_id: String in _bands:
		var band: Dictionary = _bands[band_id]
		if (band.get("floors", []) as Array).has(floor_number):
			return band
	return _bands.get("the_pit", {})


static func _load_bands() -> void:
	var data: Dictionary = read_json(BANDS_FILE)
	for raw: Variant in data.get("bands", []):
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


## Color semántico de la interfaz (ver SEMANTIC). En alto contraste, fondo/texto/foco duros.
static func color(semantic: String) -> Color:
	if SettingsMenu.get_bool("high_contrast"):
		var hc: Color = _high_contrast(semantic)
		if hc.a > 0.0:
			return hc
	var pair: Array = SEMANTIC.get(semantic, ["exterior", "outline"])
	return band_palette(str(pair[0])).get(str(pair[1]), Color.MAGENTA)


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
	var table: Dictionary = bal_dict("menus.tinte_eje")
	return Color.from_string(str(table.get(axis, table.get("hybrid", ""))), color("gold"))


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


## Variación "TWMenuItem": elementos del menú principal, texto claro sobre la noche.
static func _style_menu_items(theme: Theme) -> void:
	theme.set_type_variation("TWMenuItem", "Button")
	var clear: StyleBoxFlat = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	clear.content_margin_left = 18
	theme.set_stylebox("normal", "TWMenuItem", clear)
	theme.set_stylebox("disabled", "TWMenuItem", clear)
	var lit: StyleBoxFlat = box(color("amber"), color("ink"), OUTLINE, SHADOW)
	lit.content_margin_left = 18
	for state: String in ["hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "TWMenuItem", lit)
	theme.set_color("font_color", "TWMenuItem", color("paper"))
	for key: String in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, "TWMenuItem", color("ink"))
	theme.set_color("font_disabled_color", "TWMenuItem", color("steel"))
	theme.set_color("font_outline_color", "TWMenuItem", color("ink"))
	theme.set_constant("outline_size", "TWMenuItem", 0)
	theme.set_font("font", "TWMenuItem", font("display"))
	theme.set_font_size("font_size", "TWMenuItem", fs(FONT_HEADING))


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


## Marco de memorándum a pantalla casi completa. Devuelve {root, panel, body, back, title, scroll}.
static func memo_frame(title_text: String, kicker_text: String) -> Dictionary:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 96)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	var panel: PanelContainer = PanelContainer.new()
	margin.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var kicker: Label = label(kicker_text.to_upper(), "TWSmall")
	kicker.add_theme_font_override("font", font("bold"))
	kicker.add_theme_color_override("font_color", color("gold").darkened(0.35))
	titles.add_child(kicker)
	var title: Label = label(title_text, "TWHeading")
	titles.add_child(title)
	var back: Button = button(TranslationServer.translate("UI_BACK"))
	back.name = "Back"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	column.add_child(rule(color("ink"), OUTLINE))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	scroll.add_child(body)
	return {"root": margin, "panel": panel, "body": body, "back": back, "title": title, "scroll": scroll}


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


## Llama a un método de AudioDirector si existe (nodo del grupo "audio_director"). Si no hay ninguno
## y `create` es true, instancia uno propio hijo de `host`, solo si implementa `method`.
static func audio_call(host: Node, method: String, args: Array, create: bool = false) -> void:
	if host == null or not host.is_inside_tree():
		return
	var director: Node = host.get_tree().get_first_node_in_group(AUDIO_GROUP)
	if director == null and create:
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
