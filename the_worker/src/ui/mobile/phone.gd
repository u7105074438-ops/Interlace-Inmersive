# phone.gd — Móvil (§13.5): superposición con CONTACTOS, CHAT y LLAMADA, soborno por deslizador, modo silencio y exposición.
# PROPIETARIO DE: la vista abierta del móvil (pestaña, panel de soborno, vibración) y los superiores que ya lo han visto en esta apertura; su Service (hijo de UIRoot) guarda la bandeja de mensajes de la sesión (transitoria, no se guarda en disco).
# ESCUCHA: phone_message_received, money_changed, player_caught_redhanded, game_over (y el Service: phone_message_received, run_started, run_loaded).
class_name PhoneOverlay
extends Control

## UIRoot.open_phone(context) lo instancia, llama a setup(context) y lo abre con
## open_modal(…, false): el reloj NO se pausa y el mundo sigue (superposición, §13.5).
## context (opcional): {tab: "contacts"|"chat"|"call", npc_id: String, action: "chat"|"call"|"deal"}.
## DECISIONES (contrato para el resto de constructores):
##  · Exposición (al abrir y cada movil.intervalo_vigilancia_segundos): superiores a la vista =
##    personajes de escalón mayor que el del jugador a percepcion.cono_distancia_base celdas (nodos
##    del grupo "npcs" con npc_id; si el nodo tiene can_see_player() se respeta) o, sin nodos de NPC
##    en la escena, quienes comparten la sala del jugador (NPCDirector). Cada uno emite
##    player_seen_partially(npc_id, movil.certeza_superior_ve_movil, sala) — BeliefNet crea la
##    creencia de percepción parcial —, como mucho una vez cada movil.enfriamiento_superior_segundos.
##  · Oyentes de una llamada = personajes a movil.radio_escucha_llamada celdas (× factor_escucha_sala_
##    abierta fuera de las salas safe_for_calls: baños y escaleras de servicio) o, sin nodos, quienes
##    comparten la sala. Van en ctx.listeners de Bribery.offer(…, "phone_call"): "bribe_attempt:overheard".
##  · Chat: todo trato escrito pasa por Bribery.offer(…, "mobile_chat") → registro chat_log permanente.
##  · Silencio: AudioDirector.set_phone_silenced() (o el ajuste phone_silenced de SaveSystem). La
##    vibración sonora y su ruido los emite AudioDirector; aquí solo la sacudida visual.
##  · No hay campos de texto: el móvil no bloquea el movimiento por sí mismo (ver REQUESTS: UIRoot).
##  · Si pillan al jugador (player_caught_redhanded) o acaba la partida, el móvil se cierra.

signal close_requested

const GROUP := "phone_overlay"
const SERVICE_GROUP := "phone_service"
const TAB_CONTACTS := "contacts"
const TAB_CHAT := "chat"
const TAB_CALL := "call"
const TABS: Array[String] = [TAB_CONTACTS, TAB_CHAT, TAB_CALL]
const TAB_ICONS: Dictionary = {TAB_CONTACTS: "person", TAB_CHAT: "talk", TAB_CALL: "phone"}
const TAB_KEYS: Dictionary = {TAB_CONTACTS: "PHONE_TAB_CONTACTS", TAB_CHAT: "PHONE_TAB_CHAT",
		TAB_CALL: "PHONE_TAB_CALL"}
const ACTION_CHAT := "chat"
const ACTION_CALL := "call"
const ACTION_DEAL := "deal"
const CTX_TAB := "tab"
const CTX_NPC := "npc_id"
const CTX_ACTION := "action"
const SETTING_SILENCED := "phone_silenced"
const ROOM_SAFE_KEY := "safe_for_calls"
const EXPO_SUPERIORS := "superiors"
const EXPO_LISTENERS := "listeners"
const EXPO_SAFE := "safe"

const B_HEARING := "movil.radio_escucha_llamada"
const B_OPEN_FACTOR := "movil.factor_escucha_sala_abierta"
const B_SIGHT := "percepcion.cono_distancia_base"
const B_CERTAINTY := "movil.certeza_superior_ve_movil"
const B_COOLDOWN := "movil.enfriamiento_superior_segundos"
const B_WATCH := "movil.intervalo_vigilancia_segundos"
const B_SHAKE_S := "movil.vibracion_segundos"
const B_SHAKE_PX := "movil.vibracion_amplitud"
const B_SHAKE_HZ := "movil.vibracion_hz"
const B_OPEN_S := "movil.animacion_apertura_segundos"
const B_INBOX_MAX := "movil.max_mensajes_bandeja"
const B_CELL := "mundo.px_por_unidad"

## Maquetación (píxeles del lienzo base y proporciones de dibujo; no son ajustes de juego).
const DEVICE_ASPECT := 0.5
const DEVICE_HEIGHT_EMS := 34.0
const MARGIN_RIGHT := 44.0
const MARGIN_TOP := 118.0
const MARGIN_BOTTOM := 28.0
const SCREEN_PAD := 12
const OPEN_EASE := 0.4
const SLIDE_FRACTION := 0.35
const EPS := 0.0001
const HANGUP_ANGLE := 2.356
const SIGNAL_BARS := 4
const UNDERGROUND_BARS := 1


# ─── Piezas de interfaz compartidas por las pestañas ───────────────

## Glifo vectorial (los de UITheme más los propios del móvil: bell, bell_off, back, server, hangup).
class Glyph extends Control:
	var glyph: String = "info"
	var color_name: String = "paper"
	var tint: Color = Color(0, 0, 0, 0)
	var ems: float = 1.0

	func _init(p_glyph: String = "info", p_color_name: String = "paper", p_ems: float = 1.0) -> void:
		glyph = p_glyph
		color_name = p_color_name
		ems = p_ems
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			var side: float = float(get_theme_constant("icon", UITheme.HUD_TYPE)) * ems
			custom_minimum_size = Vector2(side, side)

	func set_glyph(p_glyph: String, p_tint: Color = Color(0, 0, 0, 0)) -> void:
		glyph = p_glyph
		tint = p_tint
		queue_redraw()

	func _draw() -> void:
		var col: Color = tint if tint.a > 0.0 else get_theme_color(color_name, UITheme.HUD_TYPE)
		var side: float = minf(size.x, size.y)
		var r: Rect2 = Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		PhoneOverlay.draw_glyph(self, glyph, r, col, maxf(side * 0.09, 1.5))


## Botón con glifo a la izquierda del texto (el hueco del glifo se reserva con espacios).
class IconButton extends Button:
	var glyph: String = ""
	var glyph_tint: Color = Color(0, 0, 0, 0)
	var _label: String = ""

	func _init(p_text: String, p_glyph: String, p_variation: String = "") -> void:
		glyph = p_glyph
		theme_type_variation = p_variation
		focus_mode = Control.FOCUS_NONE
		set_label(p_text)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			set_label(_label)

	func set_label(p_text: String) -> void:
		_label = p_text
		if glyph.is_empty() or not is_inside_tree():
			text = p_text
			return
		var font: Font = get_theme_font("font")
		var fs: int = get_theme_font_size("font_size")
		var space: float = maxf(font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 1.0)
		var pad: int = ceili(fs * 1.35 / space)
		text = " ".repeat(pad) + p_text if not p_text.is_empty() else " ".repeat(pad)
		queue_redraw()

	func get_label() -> String:
		return _label

	func _draw() -> void:
		if glyph.is_empty():
			return
		var font: Font = get_theme_font("font")
		var fs: int = get_theme_font_size("font_size")
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var side: float = fs * 1.05
		var x: float = (size.x - width) * 0.5
		if _label.is_empty():
			x = (size.x - side) * 0.5
		var col: Color = glyph_tint if glyph_tint.a > 0.0 else get_theme_color(
				"font_disabled_color" if disabled else "font_color")
		PhoneOverlay.draw_glyph(self, glyph, Rect2(x, (size.y - side) * 0.5, side, side), col,
				maxf(side * 0.09, 1.5))


## Foto de un personaje (busto de PERSONNEL con el fondo de la banda de su escalón).
class Portrait extends Control:
	var app: Dictionary = {}
	var frame: Color = CharacterStyle.OUTLINE
	var ems: float = 2.0

	func _init(p_ems: float = 2.0) -> void:
		ems = p_ems
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			var side: float = float(get_theme_constant("base", UITheme.HUD_TYPE)) * ems
			custom_minimum_size = Vector2(side, side)

	func set_npc(npc: NPCRuntime) -> void:
		app = CharacterPainter.appearance_for_npc(npc) if npc != null else {}
		queue_redraw()

	func _draw() -> void:
		var side: float = minf(size.x, size.y)
		var r: Rect2 = Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		if app.is_empty():
			draw_rect(r, UITheme.color("slot"))
			UITheme.draw_icon(self, "person", r.grow(-side * 0.18), UITheme.color("faint"), side * 0.05)
		else:
			CharacterPainter.draw_portrait(self, app, r)
		draw_rect(r, frame, false, 2.0)


## Pestaña de la barra inferior: glifo, rótulo, indicador de pestaña activa y globo de no leídos.
class TabButton extends Control:
	signal pressed
	var glyph: String = ""
	var caption: String = ""
	var active: bool = false
	var badge: int = 0
	var accent: Color = Color.WHITE

	func _init(p_glyph: String, p_caption: String) -> void:
		glyph = p_glyph
		caption = p_caption
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			var base: float = float(get_theme_constant("base", UITheme.HUD_TYPE))
			custom_minimum_size = Vector2(base * 3.0, base * 2.9)

	func _gui_input(event: InputEvent) -> void:
		if UITheme.is_primary_press(event):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		var base: float = float(get_theme_constant("base", UITheme.HUD_TYPE))
		var col: Color = accent if active else UITheme.color("muted")
		if active:
			draw_rect(Rect2(size.x * 0.22, 0.0, size.x * 0.56, 3.0), accent)
		var side: float = base * 1.15
		var icon_r: Rect2 = Rect2((size.x - side) * 0.5, base * 0.45, side, side)
		PhoneOverlay.draw_glyph(self, glyph, icon_r, col, maxf(side * 0.09, 1.5))
		var font: Font = get_theme_font("font", UITheme.V_CAPTION)
		var fs: int = get_theme_font_size("font_size", UITheme.V_CAPTION)
		var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - width) * 0.5, base * 2.45), caption,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if badge > 0:
			PhoneOverlay.draw_badge(self, icon_r.position + Vector2(side, 0.0), badge, base)


## El terminal dibujado por código: carcasa según el escalón del jugador, bisel, pantalla y cristal.
class Device extends Control:
	const CORNER := 0.13
	const TOP_BEZEL := 0.058
	const BOTTOM_BEZEL := 0.052
	const SIDE_BEZEL := 0.045
	var body: Color = Color("#d3c7a4")
	var trim: Color = Color(0, 0, 0, 0)
	var cracked: bool = false
	var home_button: bool = false
	var buzz: float = 0.0
	var screen: MarginContainer
	var glass: Control

	func _init() -> void:
		name = "Device"
		mouse_filter = Control.MOUSE_FILTER_STOP
		screen = MarginContainer.new()
		screen.name = "Screen"
		add_child(screen)
		glass = Control.new()
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glass)
		glass.draw.connect(_draw_glass)
		resized.connect(_fit_screen)

	func screen_rect() -> Rect2:
		var side: float = size.x * SIDE_BEZEL
		var top: float = size.y * TOP_BEZEL
		var bottom: float = size.y * BOTTOM_BEZEL
		return Rect2(Vector2(side, top), size - Vector2(side * 2.0, top + bottom))

	func _fit_screen() -> void:
		var r: Rect2 = screen_rect()
		screen.position = r.position
		screen.size = r.size
		glass.position = r.position
		glass.size = r.size

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var radius: float = size.x * CORNER
		PhoneOverlay.fill_round(self, r.grow(2.0).translated(Vector2(7, 11)), radius, Color(0, 0, 0, 0.32))
		_draw_side_keys(radius)
		PhoneOverlay.fill_round(self, r, radius, body)
		PhoneOverlay.line_round(self, r.grow(-6.0), radius - 6.0, Color(body.lightened(0.28), 0.55), 1.5)
		if trim.a > 0.0:
			PhoneOverlay.line_round(self, r.grow(-2.5), radius - 2.5, trim, 2.0)
		PhoneOverlay.line_round(self, r, radius, CharacterStyle.OUTLINE, 3.0)
		var sr: Rect2 = screen_rect()
		PhoneOverlay.fill_round(self, sr, radius * 0.45, UITheme.color("ink"))
		PhoneOverlay.line_round(self, sr, radius * 0.45, CharacterStyle.OUTLINE, 2.0)
		_draw_bezel_details(sr)
		if buzz > 0.0:
			_draw_buzz(r)

	func _draw_side_keys(radius: float) -> void:
		var key: Color = body.darkened(0.22)
		var y0: float = radius * 1.4
		for rect: Rect2 in [Rect2(-4.0, y0, 7.0, size.y * 0.07), Rect2(-4.0, y0 + size.y * 0.09, 7.0,
				size.y * 0.07), Rect2(size.x - 3.0, y0 + size.y * 0.04, 7.0, size.y * 0.1)]:
			PhoneOverlay.fill_round(self, rect, 3.0, key)
			PhoneOverlay.line_round(self, rect, 3.0, CharacterStyle.OUTLINE, 2.0)

	func _draw_bezel_details(sr: Rect2) -> void:
		var ink: Color = body.darkened(0.55)
		var slit: Rect2 = Rect2(size.x * 0.41, sr.position.y * 0.38, size.x * 0.18, maxf(sr.position.y * 0.2, 3.0))
		PhoneOverlay.fill_round(self, slit, slit.size.y * 0.5, ink)
		draw_circle(Vector2(size.x * 0.66, slit.get_center().y), slit.size.y * 0.75, ink)
		if home_button:
			var c: Vector2 = Vector2(size.x * 0.5, sr.end.y + (size.y - sr.end.y) * 0.5)
			var rad: float = (size.y - sr.end.y) * 0.3
			draw_circle(c, rad, body.darkened(0.08))
			draw_arc(c, rad, 0.0, TAU, 24, ink, 2.0, true)

	func _draw_buzz(r: Rect2) -> void:
		var col: Color = Color(UITheme.color("paper"), 0.85 * buzz)
		for i: int in 3:
			var gap: float = 9.0 + i * 8.0
			var y: float = r.size.y * (0.28 + 0.2 * i)
			draw_arc(Vector2(-gap, y), 10.0, PI * 0.65, PI * 1.35, 8, col, 3.0, true)
			draw_arc(Vector2(r.size.x + gap, y), 10.0, -PI * 0.35, PI * 0.35, 8, col, 3.0, true)

	func _draw_glass() -> void:
		var s: Vector2 = glass.size
		var glare: PackedVector2Array = PackedVector2Array([Vector2(s.x * 0.55, 0.0), Vector2(s.x, 0.0),
				Vector2(s.x, s.y * 0.2), Vector2(s.x * 0.35, s.y * 0.62)])
		glass.draw_colored_polygon(glare, Color(1, 1, 1, 0.025))
		if not cracked:
			return
		var o: Vector2 = Vector2(s.x * 0.86, s.y * 0.07)
		var col: Color = Color(1, 1, 1, 0.42)
		for tip: Vector2 in [Vector2(-0.3, 0.1), Vector2(-0.12, 0.2), Vector2(0.1, 0.13), Vector2(-0.2, -0.05)]:
			var mid: Vector2 = o + Vector2(tip.x * s.x * 0.5, tip.y * s.y * 0.5) + Vector2(4, -3)
			glass.draw_polyline(PackedVector2Array([o, mid, o + Vector2(tip.x * s.x, tip.y * s.y)]), col, 1.2, true)


## Bandeja de mensajes de la sesión (transitoria): el móvil puede cerrarse y abrirse sin perderlos.
## PlayerState, si algún día expone get_phone_messages(), manda sobre esta copia (ver REQUESTS).
class Service extends Node:
	var inbox: Array[Dictionary] = []

	func _ready() -> void:
		add_to_group(PhoneOverlay.SERVICE_GROUP)
		EventBus.phone_message_received.connect(_on_message)
		EventBus.run_started.connect(_on_reset)
		EventBus.run_loaded.connect(_on_reset)

	func _on_reset(_value: int) -> void:
		inbox.clear()

	func _on_message(from_id: String, text_key: String, is_chat: bool) -> void:
		inbox.append({"from_id": from_id, "text_key": text_key, "is_chat": is_chat,
				"day": GameClock.get_day(), "time": GameClock.get_time_string(), "read": false})
		while inbox.size() > maxi(PhoneOverlay.tune_i(PhoneOverlay.B_INBOX_MAX), 1):
			inbox.pop_front()
		if PhoneOverlay.is_open(get_tree()) or PhoneOverlay.is_phone_silenced(get_tree()):
			return
		var ui: UIRoot = UIRoot.find(get_tree())
		if ui != null:
			ui.get_toasts().push(UITheme.trf("PHONE_TOAST_MESSAGE", [PhoneOverlay.npc_name(from_id)]),
					ToastStack.KIND_INFO, "phone")

	func messages_from(npc_id: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for entry: Dictionary in inbox:
			if str(entry["from_id"]) == npc_id:
				out.append(entry)
		return out

	func unread_count(npc_id: String = "") -> int:
		var total: int = 0
		for entry: Dictionary in inbox:
			if not bool(entry["read"]) and (npc_id.is_empty() or str(entry["from_id"]) == npc_id):
				total += 1
		return total

	func mark_read(npc_id: String) -> void:
		for entry: Dictionary in inbox:
			if str(entry["from_id"]) == npc_id:
				entry["read"] = true

	## Remitentes, del más reciente al más antiguo.
	func thread_ids() -> Array[String]:
		var out: Array[String] = []
		for i: int in range(inbox.size() - 1, -1, -1):
			var from_id: String = str(inbox[i]["from_id"])
			if not out.has(from_id):
				out.append(from_id)
		return out


var _context: Dictionary = {}
var _device: Device
var _pages: Control
var _contacts: PhoneContactsTab
var _chat: PhoneChatTab
var _call: PhoneCallTab
var _bribe: BribePanel
var _tab_buttons: Dictionary = {}
var _time_label: Label
var _carrier_label: Label
var _signal: Glyph
var _silent_button: IconButton
var _expo_panel: PanelContainer
var _expo_glyph: Glyph
var _expo_label: Label
var _service: Service = null
var _tab: String = TAB_CONTACTS
var _exposure: Dictionary = {EXPO_SUPERIORS: [], EXPO_LISTENERS: [], EXPO_SAFE: false}
var _seen_by: Dictionary = {}
var _clock: float = 0.0
var _watch_left: float = 0.0
var _shake_left: float = 0.0
var _open_t: float = 0.0
var _rest: Vector2 = Vector2.ZERO
var _silenced: bool = false


func _init() -> void:
	name = "Phone"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_device = Device.new()
	add_child(_device)
	_build_screen()


## UIRoot lo llama antes de añadirlo al árbol.
func setup(context: Dictionary) -> void:
	_context = context.duplicate()


func _ready() -> void:
	add_to_group(GROUP)
	_service = ensure_service(get_tree())
	_chat.service = _service
	_silenced = is_phone_silenced(get_tree())
	_silent_button.glyph = "bell_off" if _silenced else "bell"
	_style_device()
	_connect_signals()
	_layout.call_deferred()
	show_tab(str(_context.get(CTX_TAB, TAB_CONTACTS)))
	_apply_context()
	refresh_exposure()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		if _device != null and is_inside_tree():
			_layout()


func _process(delta: float) -> void:
	_clock += delta
	_open_t += delta
	_shake_left = maxf(_shake_left - delta, 0.0)
	_watch_left -= delta
	if _watch_left <= 0.0:
		_watch_left = tune(B_WATCH)
		refresh_exposure()
	_time_label.text = GameClock.get_time_string()
	_device.buzz = clampf(_shake_left / maxf(tune(B_SHAKE_S), EPS), 0.0, 1.0)
	_device.position = _rest + _offset()
	modulate.a = clampf(_open_t / maxf(tune(B_OPEN_S), EPS), 0.0, 1.0)
	_device.queue_redraw()


# ─── Construcción ──────────────────────────────────────────────────

func _build_screen() -> void:
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_device.screen.add_theme_constant_override(side, SCREEN_PAD)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_device.screen.add_child(column)
	column.add_child(_build_status_bar())
	column.add_child(_build_exposure())
	_pages = Control.new()
	_pages.name = "Pages"
	_pages.clip_contents = true
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_pages)
	_contacts = PhoneContactsTab.new()
	_chat = PhoneChatTab.new()
	_call = PhoneCallTab.new()
	_bribe = BribePanel.new()
	for page: Control in [_contacts, _chat, _call, _bribe]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pages.add_child(page)
	_bribe.visible = false
	column.add_child(_build_tab_bar())


func _build_status_bar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	_time_label = label(GameClock.get_time_string(), UITheme.V_STRONG)
	bar.add_child(_time_label)
	_carrier_label = label(tr("PHONE_CARRIER"), UITheme.V_CAPTION)
	_carrier_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_carrier_label.clip_text = true
	bar.add_child(_carrier_label)
	_silent_button = IconButton.new("", "bell", UITheme.V_FLAT)
	_silent_button.tooltip_text = tr("PHONE_SILENT_TOGGLE")
	_silent_button.pressed.connect(func() -> void: set_silenced(not _silenced))
	bar.add_child(_silent_button)
	_signal = Glyph.new("signal", "paper", 1.1)
	bar.add_child(_signal)
	return bar


func _build_exposure() -> Control:
	_expo_panel = PanelContainer.new()
	var row: HBoxContainer = HBoxContainer.new()
	_expo_panel.add_child(row)
	_expo_glyph = Glyph.new("eye", "paper", 0.9)
	row.add_child(_expo_glyph)
	_expo_label = label("", UITheme.V_SMALL, true)
	_expo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_expo_label)
	return _expo_panel


func _build_tab_bar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	for tab: String in TABS:
		var button: TabButton = TabButton.new(str(TAB_ICONS[tab]), tr(str(TAB_KEYS[tab])))
		button.pressed.connect(show_tab.bind(tab))
		bar.add_child(button)
		_tab_buttons[tab] = button
	return bar


func _connect_signals() -> void:
	EventBus.phone_message_received.connect(_on_phone_message)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.player_caught_redhanded.connect(_on_caught)
	EventBus.game_over.connect(_on_game_over)
	_contacts.action_chosen.connect(_on_contact_action)
	_chat.deal_requested.connect(open_bribe.bind(Bribery.CHANNEL_MOBILE_CHAT))
	_chat.blackmail_requested.connect(_open_blackmail)
	_chat.thread_changed.connect(func(_npc_id: String) -> void: _refresh_badges())
	_call.deal_requested.connect(open_bribe.bind(Bribery.CHANNEL_PHONE_CALL))
	_bribe.close_requested.connect(close_bribe)
	_bribe.offer_resolved.connect(_on_offer_resolved)
	_bribe.ctx_provider = offer_context


## Carcasa según el escalón (banda de su foto, art_bands.json) y acento de la banda de la planta.
func _style_device() -> void:
	var tier: int = clampi(PlayerState.get_tier(), 1, CharacterStyle.PORTRAIT_BANDS.size() - 1)
	var band: String = CharacterStyle.PORTRAIT_BANDS[tier]
	var premium: bool = band == "the_power" or band == "the_throne"
	var key: String = "carpet" if band == "the_specialists" or band == "the_power" else "furniture"
	_device.body = CharacterStyle.band_color(band, key, Color("#d3c7a4"))
	_device.trim = CharacterStyle.band_color(band, "accent", Color.TRANSPARENT) if premium \
			else Color.TRANSPARENT
	_device.cracked = band == "the_pit"
	_device.home_button = band == "the_pit"
	var accent: Color = accent_color()
	for tab: String in _tab_buttons:
		(_tab_buttons[tab] as TabButton).accent = accent
	_signal.set_glyph("signal_low" if PlayerState.get_floor() < 0 else "signal")


func _layout() -> void:
	var base: float = float(get_theme_constant("base", UITheme.HUD_TYPE))
	if base <= 0.0:
		base = float(UITheme.base_font_size(UITheme.current_text_size))
	var h: float = minf(size.y - MARGIN_TOP - MARGIN_BOTTOM, base * DEVICE_HEIGHT_EMS)
	var w: float = h * DEVICE_ASPECT
	_rest = Vector2(size.x - MARGIN_RIGHT - w, size.y - MARGIN_BOTTOM - h)
	_device.size = Vector2(w, h)
	_device.position = _rest + _offset()


func _offset() -> Vector2:
	var t: float = clampf(_open_t / maxf(tune(B_OPEN_S), EPS), 0.0, 1.0)
	var slide: float = (1.0 - ease(t, OPEN_EASE)) * _device.size.y * SLIDE_FRACTION
	var shake: float = 0.0
	if _shake_left > 0.0:
		shake = sin(_shake_left * tune(B_SHAKE_HZ) * TAU) * tune(B_SHAKE_PX)
	return Vector2(shake, slide)


# ─── API pública ───────────────────────────────────────────────────

func request_close() -> void:
	if _bribe.visible:
		close_bribe()
		return
	close_requested.emit()


func show_tab(tab: String) -> void:
	if not TABS.has(tab):
		tab = TAB_CONTACTS
	_tab = tab
	close_bribe()
	_contacts.visible = tab == TAB_CONTACTS
	_chat.visible = tab == TAB_CHAT
	_call.visible = tab == TAB_CALL
	for key: String in _tab_buttons:
		var button: TabButton = _tab_buttons[key]
		button.active = key == tab
		button.queue_redraw()
	match tab:
		TAB_CONTACTS:
			_contacts.refresh()
		TAB_CHAT:
			_chat.refresh()
		TAB_CALL:
			_call.refresh()
	_refresh_badges()


func get_tab() -> String:
	return _tab


func open_chat(npc_id: String) -> void:
	show_tab(TAB_CHAT)
	_chat.open_thread(npc_id)
	_refresh_badges()


func open_call(npc_id: String) -> bool:
	show_tab(TAB_CALL)
	var answered: bool = _call.start_call(npc_id)
	_call.set_exposure(_exposure)
	return answered


## Panel de soborno sobre la pestaña: contacto → favor → cantidad (canal chat o llamada).
func open_bribe(npc_id: String, channel: String) -> void:
	_bribe.setup_for(npc_id, channel)
	_bribe.set_exposure(_exposure)
	_bribe.visible = true
	for page: Control in [_contacts, _chat, _call]:
		page.visible = false


func close_bribe() -> void:
	if _bribe == null or not _bribe.visible:
		return
	_bribe.visible = false
	_contacts.visible = _tab == TAB_CONTACTS
	_chat.visible = _tab == TAB_CHAT
	_call.visible = _tab == TAB_CALL


func is_bribe_open() -> bool:
	return _bribe.visible


func get_bribe_panel() -> BribePanel:
	return _bribe


func get_contacts_tab() -> PhoneContactsTab:
	return _contacts


func get_chat_tab() -> PhoneChatTab:
	return _chat


func get_call_tab() -> PhoneCallTab:
	return _call


func get_exposure() -> Dictionary:
	return _exposure.duplicate(true)


func is_silenced() -> bool:
	return _silenced


func set_silenced(on: bool) -> void:
	_silenced = on
	set_phone_silenced(get_tree(), on)
	_silent_button.glyph = "bell_off" if on else "bell"
	_silent_button.queue_redraw()
	if on:
		_shake_left = 0.0


func is_vibrating() -> bool:
	return _shake_left > 0.0


## Contexto que el panel de soborno pasa a Bribery.offer: sala del jugador y, en llamada, oyentes.
func offer_context(channel: String) -> Dictionary:
	var ctx: Dictionary = {"room_id": PlayerState.get_room()}
	if channel == Bribery.CHANNEL_PHONE_CALL:
		ctx["listeners"] = listeners_in_range(get_tree())
	return ctx


## Recalcula quién ve y quién oye al jugador; los superiores que lo ven con el móvil lo apuntan.
func refresh_exposure() -> Dictionary:
	var tree: SceneTree = get_tree()
	var superiors: Array[String] = superiors_in_sight(tree)
	_exposure = {EXPO_SUPERIORS: superiors, EXPO_LISTENERS: listeners_in_range(tree),
			EXPO_SAFE: is_call_safe_room(PlayerState.get_room())}
	_report_superiors(superiors)
	_show_exposure()
	_call.set_exposure(_exposure)
	_bribe.set_exposure(_exposure)
	return get_exposure()


# ─── Comportamiento ────────────────────────────────────────────────

func _apply_context() -> void:
	var npc_id: String = str(_context.get(CTX_NPC, ""))
	if npc_id.is_empty():
		return
	match str(_context.get(CTX_ACTION, "")):
		ACTION_CHAT:
			open_chat(npc_id)
		ACTION_CALL:
			open_call(npc_id)
		ACTION_DEAL:
			open_bribe(npc_id, Bribery.CHANNEL_MOBILE_CHAT)


func _report_superiors(superiors: Array[String]) -> void:
	var cooldown: float = tune(B_COOLDOWN)
	for npc_id: String in superiors:
		if _seen_by.has(npc_id) and _clock - float(_seen_by[npc_id]) < cooldown:
			continue
		_seen_by[npc_id] = _clock
		EventBus.player_seen_partially.emit(npc_id, tune(B_CERTAINTY), PlayerState.get_room())


func _show_exposure() -> void:
	var superiors: Array = _exposure[EXPO_SUPERIORS]
	var listeners: Array = _exposure[EXPO_LISTENERS]
	var tone: String = "gain"
	var glyph: String = "lock"
	var text: String = tr("PHONE_EXPO_PRIVATE") if bool(_exposure[EXPO_SAFE]) else tr("PHONE_EXPO_ALONE")
	if not superiors.is_empty():
		tone = "danger"
		glyph = "eye"
		text = UITheme.trf("PHONE_EXPO_SUPERIOR", [npc_name(str(superiors[0]))]) if superiors.size() == 1 \
				else UITheme.trf("PHONE_EXPO_SUPERIORS", [superiors.size()])
	elif not listeners.is_empty():
		tone = "warn"
		glyph = "ear"
		text = UITheme.trf("PHONE_EXPO_LISTENERS", [listeners.size()])
	var col: Color = UITheme.color(tone)
	_expo_panel.add_theme_stylebox_override("panel", box(Color(col.darkened(0.55), 0.95), col, 8, 10.0, 5.0, 2))
	_expo_glyph.set_glyph(glyph, col.lightened(0.25))
	_expo_label.text = text


func _refresh_badges() -> void:
	var button: TabButton = _tab_buttons.get(TAB_CHAT) as TabButton
	if button == null:
		return
	button.badge = _chat.unread_total()
	button.queue_redraw()


func _on_contact_action(npc_id: String, action: String) -> void:
	match action:
		ACTION_CHAT:
			open_chat(npc_id)
		ACTION_CALL:
			open_call(npc_id)
		ACTION_DEAL:
			open_bribe(npc_id, Bribery.CHANNEL_MOBILE_CHAT)


func _on_offer_resolved(result: Dictionary) -> void:
	if str(result.get("channel", "")) == Bribery.CHANNEL_MOBILE_CHAT:
		_chat.note_offer(result)
	else:
		_call.note_offer(result)
	_contacts.refresh()


func _open_blackmail(npc_id: String) -> void:
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui != null:
		BlackmailDialog.open_for(ui, npc_id)


func _on_phone_message(from_id: String, _text_key: String, _is_chat: bool) -> void:
	if not _silenced:
		_shake_left = tune(B_SHAKE_S)
	_chat.on_message_arrived.call_deferred(from_id)
	_refresh_badges.call_deferred()


func _on_money_changed(_old_value: int, _new_value: int, _reason: String) -> void:
	if _bribe.visible:
		_bribe.refresh_funds()


func _on_caught(_npc_id: String, _crime_type: String, _witnesses: int) -> void:
	close_requested.emit()


func _on_game_over(_cause: String, _ending_id: String, _snapshot: Dictionary) -> void:
	close_requested.emit()


# ─── Exposición (estático, comprobable sin escena) ─────────────────

static func tune(path: String) -> float:
	return Database.get_balance_float(path)


static func tune_i(path: String) -> int:
	return Database.get_balance_int(path)


static func cell_px() -> float:
	return maxf(tune(B_CELL), 1.0)


static func is_open(tree: SceneTree) -> bool:
	return tree != null and tree.get_first_node_in_group(GROUP) != null


## Personajes cerca del jugador: nodos del grupo "npcs" a radius_cells celdas (con la vista del nodo
## si need_sight y el nodo sabe decirla) o, sin nodos de NPC, los que comparten su sala.
static func npcs_within(tree: SceneTree, radius_cells: float, need_sight: bool) -> Array[String]:
	if tree == null:
		return npcs_in_player_room()
	var player: Node2D = tree.get_first_node_in_group("player") as Node2D
	var nodes: Array[Node] = tree.get_nodes_in_group("npcs")
	if player == null or nodes.is_empty():
		return npcs_in_player_room()
	var out: Array[String] = []
	var reach: float = radius_cells * cell_px()
	for node: Node in nodes:
		var body: Node2D = node as Node2D
		var raw_id: Variant = node.get("npc_id")
		if body == null or raw_id == null or str(raw_id).is_empty():
			continue
		if body.global_position.distance_to(player.global_position) > reach:
			continue
		if need_sight and node.has_method("can_see_player") and not bool(node.call("can_see_player")):
			continue
		if NPCDirector.is_active(str(raw_id)):
			out.append(str(raw_id))
	return out


static func npcs_in_player_room() -> Array[String]:
	var out: Array[String] = []
	var room: String = PlayerState.get_room()
	if room.is_empty():
		return out
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.current_room == room:
			out.append(npc.id)
	return out


## Personajes de escalón superior al del jugador que lo ven (usar el móvil delante levanta sospecha).
static func superiors_in_sight(tree: SceneTree) -> Array[String]:
	var out: Array[String] = []
	var player_tier: int = PlayerState.get_tier()
	for npc_id: String in npcs_within(tree, tune(B_SIGHT), true):
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		if npc != null and npc.tier > player_tier:
			out.append(npc_id)
	return out


## Quién oiría una llamada ahora (§13.5: fuera de baños y escaleras de servicio se oye más lejos).
static func listeners_in_range(tree: SceneTree) -> Array[String]:
	return npcs_within(tree, hearing_radius(PlayerState.get_room()), false)


static func hearing_radius(room_id: String) -> float:
	var radius: float = tune(B_HEARING)
	return radius if is_call_safe_room(room_id) else radius * tune(B_OPEN_FACTOR)


static func is_call_safe_room(room_id: String) -> bool:
	var room: RoomData = Database.get_room(room_id) if not room_id.is_empty() else null
	if room == null and room_id.contains("@"):
		room = Database.get_room(room_id.substr(0, room_id.find("@")))
	return room != null and bool(room.extra.get(ROOM_SAFE_KEY, false))


# ─── Silencio y servicio ───────────────────────────────────────────

static func is_phone_silenced(tree: SceneTree) -> bool:
	var audio: AudioDirector = AudioDirector.find(tree)
	if audio != null:
		return audio.is_phone_silenced()
	var value: Variant = SaveSystem.get_setting(SETTING_SILENCED)
	return value is bool and value


static func set_phone_silenced(tree: SceneTree, on: bool) -> void:
	var audio: AudioDirector = AudioDirector.find(tree)
	if audio != null:
		audio.set_phone_silenced(on)
	else:
		SaveSystem.set_setting(SETTING_SILENCED, on)


## Instala (una vez) la bandeja de la sesión como hijo de host (UIRoot). Lo llama game_root al
## montar la interfaz; el móvil también lo hace al abrirse si nadie lo instaló.
static func install(host: Node) -> Service:
	var found: Service = find_service(host.get_tree()) if host != null and host.is_inside_tree() else null
	if found != null or host == null:
		return found
	var service: Service = Service.new()
	service.name = "PhoneService"
	host.add_child(service)
	return service


static func find_service(tree: SceneTree) -> Service:
	return tree.get_first_node_in_group(SERVICE_GROUP) as Service if tree != null else null


static func ensure_service(tree: SceneTree) -> Service:
	var found: Service = find_service(tree)
	if found != null:
		return found
	var ui: UIRoot = UIRoot.find(tree)
	return install(ui if ui != null else tree.root)


# ─── Textos de personajes ──────────────────────────────────────────

static func npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.name.is_empty():
		return npc.name
	var named: NPCData = Database.get_named_npc(npc_id)
	return named.name if named != null else tr_static("PHONE_UNKNOWN_NUMBER")


## Puesto visible: ocupación jugable o rol de nominado; "" si no hay.
static func job_text(npc: NPCRuntime) -> String:
	if npc == null:
		return ""
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	if occupation != null:
		return tr_static(occupation.name_key)
	var named: NPCData = Database.get_named_npc(npc.id)
	if named != null:
		var role_key: String = str(Database.get_role(str(named.extra.get("role", ""))).get("name_key", ""))
		if not role_key.is_empty():
			return tr_static(role_key)
	return ""


static func tr_static(key: String) -> String:
	return String(TranslationServer.translate(key))


static func accent_color() -> Color:
	return UITheme.band_accent_for_floor(PlayerState.get_floor())


# ─── Construcción y dibujo compartidos ─────────────────────────────

static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func box(bg: Color, border: Color, radius: int, pad_h: float, pad_v: float,
		border_w: int = 0) -> StyleBoxFlat:
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
	return sb


static func card(bg: Color, border: Color, radius: int = 10, pad_h: float = 12.0,
		pad_v: float = 9.0) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(bg, border, radius, pad_h, pad_v, 2 if border.a > 0.0 else 0))
	return panel


static func scroll_list() -> Dictionary:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return {"scroll": scroll, "list": list}


static func clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func fill_round(c: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
	c.draw_colored_polygon(UITheme.rounded_rect_points(r, maxf(radius, 0.0)), col)


static func line_round(c: CanvasItem, r: Rect2, radius: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = UITheme.rounded_rect_points(r, maxf(radius, 0.0))
	pts.append(pts[0])
	c.draw_polyline(pts, col, width, true)


## Globo rojo con número (no leídos).
static func draw_badge(c: CanvasItem, center: Vector2, count: int, base: float) -> void:
	var radius: float = base * 0.48
	c.draw_circle(center, radius + 2.0, CharacterStyle.OUTLINE)
	c.draw_circle(center, radius, UITheme.color("danger"))
	var font: Font = UITheme.font(UITheme.FONT_BOLD)
	var fs: int = roundi(base * 0.62)
	var text: String = str(count)
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, center + Vector2(-width * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			fs, UITheme.color("paper"))


static func draw_glyph(c: CanvasItem, glyph: String, r: Rect2, col: Color, w: float) -> void:
	match glyph:
		"bell":
			_glyph_bell(c, r, col, w, false)
		"bell_off":
			_glyph_bell(c, r, col, w, true)
		"back":
			c.draw_polyline(_unit_points(r, [0.62, 0.18, 0.3, 0.5, 0.62, 0.82]), col, w * 1.4, true)
		"server":
			_glyph_server(c, r, col, w)
		"hangup":
			c.draw_set_transform(r.get_center(), HANGUP_ANGLE, Vector2.ONE)
			UITheme.draw_icon(c, "phone", Rect2(-r.size * 0.5, r.size), col, w)
			c.draw_set_transform(Vector2.ZERO)
		"signal", "signal_low":
			_glyph_signal(c, r, col, SIGNAL_BARS if glyph == "signal" else UNDERGROUND_BARS)
		"exclaim":
			_glyph_exclaim(c, r, col)
		_:
			UITheme.draw_icon(c, glyph, r, col, w)


static func _unit(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func _unit_points(r: Rect2, coords: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, coords.size() - 1, 2):
		out.append(_unit(r, float(coords[i]), float(coords[i + 1])))
	return out


static func _glyph_bell(c: CanvasItem, r: Rect2, col: Color, w: float, slashed: bool) -> void:
	var outline: PackedVector2Array = _unit_points(r, [0.18, 0.74, 0.27, 0.62, 0.27, 0.45])
	var center: Vector2 = _unit(r, 0.5, 0.45)
	var radius: float = r.size.x * 0.23
	for i: int in 11:
		var a: float = PI + PI * float(i) / 10.0
		outline.append(center + Vector2(cos(a), sin(a)) * radius)
	outline.append_array(_unit_points(r, [0.73, 0.62, 0.82, 0.74, 0.18, 0.74]))
	c.draw_polyline(outline, col, w, true)
	c.draw_circle(_unit(r, 0.5, 0.84), r.size.x * 0.075, col)
	c.draw_circle(_unit(r, 0.5, 0.17), r.size.x * 0.05, col)
	if slashed:
		c.draw_line(_unit(r, 0.12, 0.1), _unit(r, 0.88, 0.92), col, w * 1.3, true)


static func _glyph_server(c: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	for y: float in [0.14, 0.54]:
		var rack: Rect2 = Rect2(_unit(r, 0.14, y), Vector2(r.size.x * 0.72, r.size.y * 0.32))
		line_round(c, rack, r.size.x * 0.06, col, w)
		c.draw_circle(rack.position + Vector2(rack.size.x * 0.2, rack.size.y * 0.5), r.size.x * 0.055, col)
		c.draw_line(rack.position + Vector2(rack.size.x * 0.45, rack.size.y * 0.5),
				rack.position + Vector2(rack.size.x * 0.82, rack.size.y * 0.5), col, w, true)


static func _glyph_signal(c: CanvasItem, r: Rect2, col: Color, lit: int) -> void:
	var bar_w: float = r.size.x / (SIGNAL_BARS * 1.6)
	for i: int in SIGNAL_BARS:
		var h: float = r.size.y * (0.3 + 0.2 * i)
		var bar: Rect2 = Rect2(r.position.x + i * bar_w * 1.6, r.end.y - h - r.size.y * 0.1, bar_w, h)
		c.draw_rect(bar, col if i < lit else Color(col, 0.28))


static func _glyph_exclaim(c: CanvasItem, r: Rect2, col: Color) -> void:
	var w: float = r.size.x * 0.16
	c.draw_line(_unit(r, 0.5, 0.16), _unit(r, 0.5, 0.6), col, w, true)
	c.draw_circle(_unit(r, 0.5, 0.8), w * 0.62, col)
