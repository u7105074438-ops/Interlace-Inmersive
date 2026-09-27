# app_base.gd — Base de las aplicaciones de StellarOS: contexto de sesión, barra de estado, esperas del equipo y piezas de interfaz retro.
# PROPIETARIO DE: nada (las aplicaciones muestran y mandan sobre el estado de los sistemas; no guardan estado de juego).
# ESCUCHA: nada.
class_name OSApp
extends Control

## CONTRATO DE APLICACIÓN (también para personnel_app.gd, portal_app.gd y market_app.gd, de otro
## constructor: pueden extender OSApp o ser cualquier Control; todo es opcional):
##  · setup(context: Dictionary) — context = {shell: StellarOS, app_id, session ("own"|"guest"),
##    npc_id ("" en sesión propia), tier (computer_tier 1..8), palette (OSTheme.palette_for_tier),
##    base (tamaño base de texto, px), extra (el contexto con que se abrió el ordenador)}.
##  · get_title_key() -> String — título de la ventana (si falta: nombre de la aplicación).
##  · señal status_posted(text: String) — texto para la barra de estado de la ventana.
##  · señal close_requested() — StellarOS cierra la ventana de la aplicación.
##  · on_closing() — antes de cerrar (guardar lo pendiente, p. ej. el cuaderno).
##  · refresh() — volver a leer los sistemas (StellarOS la llama al traer la ventana al frente).
## El tema (OSTheme) lo hereda del escritorio; los colores de dibujo propio salen de `pal`.

signal status_posted(text: String)
signal close_requested()

const SESSION_OWN := "own"
const SESSION_GUEST := "guest"
const PLAYER_ID := "player"

var shell: StellarOS = null
var context: Dictionary = {}
var pal: Dictionary = {}
var base: int = 24
var app_id: String = ""


## Fila clicable de una lista (correo, archivos, cuaderno, menú de inicio): icono, título, subtítulo y etiqueta.
class OSRow extends PanelContainer:
	signal pressed()
	var _icon: OSIcon
	var _title: Label
	var _sub: Label
	var _tag: Label
	var _selected: bool = false

	func _init(p: Dictionary, base_px: int, icon_id: String, title: String, sub: String = "", tag: String = "") -> void:
		theme_type_variation = OSTheme.V_ROW
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var h: HBoxContainer = HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		_icon = OSIcon.new(p, icon_id, base_px * 1.6)
		h.add_child(_icon)
		var col: VBoxContainer = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 0)
		h.add_child(col)
		_title = OSApp.make_label(title, OSTheme.V_HEADING, false, true)
		col.add_child(_title)
		_sub = OSApp.make_label(sub, OSTheme.V_MUTED, false, true)
		_sub.visible = not sub.is_empty()
		col.add_child(_sub)
		_tag = OSApp.make_label(tag, OSTheme.V_SMALL)
		_tag.visible = not tag.is_empty()
		h.add_child(_tag)

	func set_selected(on: bool) -> void:
		_selected = on
		theme_type_variation = OSTheme.V_ROW_SELECTED if on else OSTheme.V_ROW

	func is_selected() -> bool:
		return _selected

	func set_texts(title: String, sub: String, tag: String) -> void:
		_title.text = title
		_sub.text = sub
		_sub.visible = not sub.is_empty()
		_tag.text = tag
		_tag.visible = not tag.is_empty()

	func set_tag_color(c: Color) -> void:
		_tag.add_theme_color_override("font_color", c)

	func set_title_variation(v: String) -> void:
		_title.theme_type_variation = v

	func set_icon(icon_id: String) -> void:
		_icon.icon_id = icon_id
		_icon.queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if UITheme.is_primary_press(event) or event.is_action_pressed("ui_accept"):
			accept_event()
			pressed.emit()


## Icono vectorial de OSTheme a tamaño fijo.
class OSIcon extends Control:
	var icon_id: String = ""
	var pal: Dictionary = {}
	var dimmed: bool = false

	func _init(p: Dictionary, id: String, side: float) -> void:
		pal = p
		icon_id = id
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var side: float = minf(size.x, size.y)
		var r: Rect2 = Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		OSTheme.draw_icon(self, icon_id, r, pal)
		if dimmed:
			draw_rect(r, Color(OSTheme.col(pal, "face"), 0.55))


# ─── Ciclo de vida ────────────────────────────────────────────────

func setup(ctx: Dictionary) -> void:
	context = ctx
	shell = ctx.get("shell") as StellarOS
	pal = ctx.get("palette", {}) as Dictionary
	base = int(ctx.get("base", base))
	app_id = str(ctx.get("app_id", ""))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()


## Sobrescribir: construye la interfaz (tras setup, con paleta y tamaño base ya conocidos).
func build() -> void:
	pass


## Sobrescribir: vuelve a leer los sistemas.
func refresh() -> void:
	pass


## Sobrescribir: antes de cerrar la ventana.
func on_closing() -> void:
	pass


func get_title_key() -> String:
	return ""


func is_guest() -> bool:
	return str(context.get("session", SESSION_OWN)) == SESSION_GUEST


func get_npc_id() -> String:
	return str(context.get("npc_id", ""))


func get_tier() -> int:
	return int(context.get("tier", 1))


func post_status(text: String) -> void:
	status_posted.emit(text)


## Espera del equipo lento (reloj de arena), proporcional a ordenador.retardo_ventana_segundos_por_nivel.
func wait_lag(factor: float = 1.0) -> void:
	if shell != null:
		await shell.wait_lag(factor)


## DutySystem de la partida (grupo "duty_system"; el escritorio garantiza uno mientras está abierto).
func duty_system() -> DutySystem:
	if shell != null:
		return shell.get_duty_system()
	return get_tree().get_first_node_in_group(DutySystem.GROUP) as DutySystem if is_inside_tree() else null


func c(key: String) -> Color:
	return OSTheme.col(pal, key)


# ─── Piezas de interfaz ───────────────────────────────────────────

static func make_label(text: String, variation: String = "", wrap: bool = false, ellipsis: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1
	if ellipsis:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func make_button(text: String, on_press: Callable, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


func make_panel(variation: String) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.theme_type_variation = variation
	return p


func make_row(icon_id: String, title: String, sub: String = "", tag: String = "") -> OSRow:
	return OSRow.new(pal, base, icon_id, title, sub, tag)


func make_icon(icon_id: String, side_ratio: float) -> OSIcon:
	return OSIcon.new(pal, icon_id, base * side_ratio)


## Lista desplazable: devuelve el ScrollContainer (su hijo único es un VBoxContainer: get_child(0)).
func make_scroll_list() -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", roundi(base * 0.12))
	scroll.add_child(list)
	return scroll


## Pastilla de color con texto (resultado de A.S.S.I.S.T., estado de un deber...).
func make_badge(text: String, fill: Color) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(roundi(base * 0.25) if int(pal.get("radius", 0)) > 0 else 0)
	sb.content_margin_left = base * 0.5
	sb.content_margin_right = base * 0.5
	sb.content_margin_top = base * 0.12
	sb.content_margin_bottom = base * 0.12
	sb.set_border_width_all(maxi(1, roundi(OSTheme.bevel_width(base))))
	sb.border_color = fill.darkened(0.35)
	p.add_theme_stylebox_override("panel", sb)
	var l: Label = make_label(text, OSTheme.V_HEADING)
	l.add_theme_color_override("font_color", UITheme.readable_on(fill) if fill.get_luminance() < 0.55 \
			else Color("#12151a"))
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


## Rótulo de sección en versalitas (cabeceras de columnas).
func make_section(text: String) -> Label:
	var l: Label = make_label(text.to_upper(), OSTheme.V_SMALL)
	l.add_theme_font_override("font", UITheme.spaced(UITheme.font(UITheme.FONT_BOLD)))
	l.add_theme_color_override("font_color", c("muted"))
	return l


func spacer(expand: bool = true) -> Control:
	var s: Control = Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


static func clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


## tr() con argumentos (UITheme.trf).
static func t(key: String, args: Array = []) -> String:
	return UITheme.trf(key, args)


## Nombre visible de un personaje (NPCDirector, nominados, o su id).
static func npc_name(npc_id: String) -> String:
	if npc_id.is_empty():
		return ""
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.name.is_empty():
		return npc.name
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.name if named != null else npc_id
