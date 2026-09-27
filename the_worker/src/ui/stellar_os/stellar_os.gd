# stellar_os.gd — StellarOS (§13.3, §15.1, PASO 22/25): escritorio a pantalla completa, arranque por nivel del equipo, barra de tareas, ventanas de aplicación, anuncios internos y sesión de invitado por intrusión.
# PROPIETARIO DE: la sesión de escritorio abierta (aplicación en primer plano, anuncios visibles, progreso del arranque), la ralentización del reloj cuando nadie más la gestiona y, si la partida no aporta uno, un DutySystem de respaldo mientras está abierto.
# ESCUCHA: nada (lee GameClock, PlayerState, NPCDirector y Database; las aplicaciones escuchan lo suyo).
class_name StellarOS
extends Control

## Uso normal: UIRoot.open_computer(context) instancia este script, llama a setup(context) y lo
## abre como modal de clase "computer" (UIRoot aplica tiempo.velocidad_en_ordenador = 0.4 y lo
## restaura al cerrar; Esc → request_close(), C → cierre). Fuera de UIRoot (pruebas, escenarios)
## el propio escritorio ralentiza el reloj, atiende Esc/C y se libera al apagarse.
## context: {session: "own"|"guest", npc_id, tier (forzar computer_tier), app (abrir al arrancar),
##           instant (sin esperas ni anuncios: QA), computer_id, room_id, contains: Array (documentos
##           del ordenador ajeno, de data/rooms: interactables npc_computer)}.
## Intrusión (enrutador de interacciones): StellarOS.open_intrusion(npc_id, {computer_id, room_id,
## contains}) → sesión de INVITADO: solo FILES, con el aspecto del equipo del dueño.
## DECISIONES:
##  · El equipo mejora con el rango (computer_tier de occupations.json): nivel 1 = arranque de
##    ordenador.arranque_segundos_por_nivel[0] s con BIOS y anuncios internos, ventanas que abren
##    con reloj de arena (ordenador.retardo_ventana_segundos_por_nivel), anuncios emergentes cada
##    ordenador.anuncio_emergente_segundos_por_nivel s; nivel 8 = instantáneo y sin anuncios.
##    Las esperas son segundos REALES: el reloj de juego sigue corriendo (al 40 %), así que un
##    equipo lento cuesta minutos de jornada (§15.1: el reloj nunca se detiene).
##  · Una sola aplicación en primer plano (legible en móvil); cambiar de icono cierra la anterior.
##  · PERSONNEL, PORTAL y MARKET son de otro constructor: se cargan si su archivo existe; si no,
##    ventana «404: aplicación no desplegada». MARKET solo aparece si la ocupación la desbloquea
##    (occupations.json unlocks_apps contiene "MARKET", desde R25).
##  · Deberes: se usa el DutySystem de la partida (grupo "duty_system"); si no hay ninguno (pruebas,
##    escenarios) se crea uno de respaldo hijo del escritorio, que vive mientras está abierto.

signal booted()
signal app_opened(app_id: String)
signal app_closed(app_id: String)
signal close_requested()

const SESSION_OWN := "own"
const SESSION_GUEST := "guest"
const APP_MAIL := "mail"
const APP_NOTEBOOK := "notebook"
const APP_PERSONNEL := "personnel"
const APP_ASSIST := "assist"
const APP_PORTAL := "portal"
const APP_FILES := "files"
const APP_MARKET := "market"
const APP_ORDER: Array[String] = [APP_MAIL, APP_NOTEBOOK, APP_PERSONNEL, APP_ASSIST, APP_PORTAL,
		APP_FILES, APP_MARKET]
const APP_DIR := "res://src/ui/stellar_os/"
const APP_SCRIPTS: Dictionary = {
	APP_MAIL: "mail_app.gd", APP_NOTEBOOK: "notebook_app.gd", APP_PERSONNEL: "personnel_app.gd",
	APP_ASSIST: "assist_app.gd", APP_PORTAL: "portal_app.gd", APP_FILES: "files_app.gd",
	APP_MARKET: "market_app.gd",
}
const APP_NAME_FORMAT := "OS_APP_%s"
const MARKET_UNLOCK := "MARKET"
const GUEST_APPS: Array[String] = [APP_FILES]
const META_KIND := "ui_kind"
const KIND_COMPUTER := "computer"
const B_BOOT := "ordenador.arranque_segundos_por_nivel"
const B_BOOT_TIPS := "ordenador.anuncios_arranque_por_nivel"
const B_LAG := "ordenador.retardo_ventana_segundos_por_nivel"
const B_AD_INTERVAL := "ordenador.anuncio_emergente_segundos_por_nivel"
const B_AD_MAX := "ordenador.anuncio_emergente_max_simultaneos"
const B_GUEST_LOGIN := "ordenador.intrusion_inicio_sesion_segundos"
const B_CLOCK_SPEED := "tiempo.velocidad_en_ordenador"
const B_BALLOON := "interfaz.toast_segundos"
## Contenido (no ajustes): anuncios OS_AD_<n>_* y consejos de arranque OS_BOOT_TIP_<n>.
const AD_ICONS: Array[String] = ["drop", "star", "user", "shoe", "portal", "idea", "warning", "hourglass"]
const BOOT_TIP_COUNT := 6
const BIOS_LINES := 5
const BIOS_FRACTION := 0.38
const PERCENT := 100.0
const RNG_SALT := "stellar_os"

var _context: Dictionary = {}
var _session: String = SESSION_OWN
var _npc_id: String = ""
var _tier: int = 1
var _pal: Dictionary = {}
var _base: int = 24
var _instant: bool = false
var _managed: bool = false
var _booted: bool = false
var _boot_elapsed: float = 0.0
var _boot_duration: float = 0.0
var _ad_timer: float = 0.0
var _ads: Array[Control] = []
var _ad_serial: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _window: OSWindow = null
var _app: Control = null
var _app_id: String = ""
var _opening: bool = false
var _clock_owned: bool = false
var _speed_before: float = 1.0
var _fallback_duties: DutySystem = null
var _icons: Dictionary = {}
var _window_layer: Control
var _ad_layer: Control
var _taskbar: Taskbar
var _start_menu: StartMenu
var _busy: BusyOverlay
var _boot: BootScreen
var _balloon: PanelContainer
var _balloon_label: Label
var _balloon_left: float = 0.0


# ─── Piezas del escritorio (clases internas) ───────────────────────

## Papel pintado (y franja de invitado) según el aspecto y la banda.
class Wallpaper extends Control:
	var pal: Dictionary = {}

	func _init(p: Dictionary) -> void:
		pal = p
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		OSTheme.draw_wallpaper(self, Rect2(Vector2.ZERO, size), pal)


## Líneas de barrido del monitor CRT sobre todo el escritorio (aspecto retro).
class Scanlines extends Control:
	var base: int = 24

	func _init(base_px: int) -> void:
		base = base_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		OSTheme.draw_scanlines(self, Rect2(Vector2.ZERO, size), base)


## Icono del escritorio: dibujo vectorial + rótulo; un toque lo abre.
class DesktopIcon extends Control:
	signal activated(app_id: String)
	var pal: Dictionary = {}
	var base: int = 24
	var app_id: String = ""
	var icon_id: String = ""
	var caption: String = ""
	var locked: bool = false
	var badge: int = 0
	var _hover: bool = false

	func _init(p: Dictionary, base_px: int, id: String, text: String) -> void:
		pal = p
		base = base_px
		app_id = id
		icon_id = id
		caption = text
		custom_minimum_size = Vector2(base * 5.0, base * 4.4)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_ALL
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if UITheme.is_primary_press(event) or event.is_action_pressed("ui_accept"):
			accept_event()
			activated.emit(app_id)

	func _draw() -> void:
		var side: float = base * 2.5
		var icon_rect: Rect2 = Rect2(Vector2((size.x - side) * 0.5, base * 0.35), Vector2(side, side))
		if _hover or has_focus():
			draw_rect(Rect2(Vector2.ZERO, size).grow(-base * 0.1), Color(OSTheme.col(pal, "select"), 0.35))
		OSTheme.draw_icon(self, icon_id, icon_rect, pal)
		if locked:
			draw_rect(icon_rect, Color(OSTheme.col(pal, "desk"), 0.45))
			OSTheme.draw_icon(self, "lock", Rect2(icon_rect.end - Vector2(side, side) * 0.45, Vector2(side, side) * 0.5), pal)
		if badge > 0:
			_draw_badge(icon_rect)
		_draw_caption(icon_rect.end.y + base * 0.2)

	func _draw_badge(icon_rect: Rect2) -> void:
		var c: Vector2 = Vector2(icon_rect.end.x - base * 0.1, icon_rect.position.y + base * 0.2)
		draw_circle(c, base * 0.55, OSTheme.col(pal, "bad"))
		draw_arc(c, base * 0.55, 0.0, TAU, 20, Color.WHITE, 2.0, true)
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(base * 0.62)
		var txt: String = str(badge)
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

	func _draw_caption(y: float) -> void:
		var f: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var fs: int = roundi(base * 0.72)
		var dark_text: bool = pal.get("skin") == OSTheme.SKIN_SOVEREIGN
		var ink: Color = OSTheme.col(pal, "dark") if dark_text else Color.WHITE
		var pos: Vector2 = Vector2(0, y + fs)
		if not dark_text:
			draw_string(f, pos + Vector2(1.5, 1.5), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(0, 0, 0, 0.75))
		draw_string(f, pos, caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, ink)


## Ventana de aplicación: marco biselado, barra de título, cuerpo y barra de estado.
class OSWindow extends Control:
	signal close_pressed()
	signal minimise_pressed()
	var pal: Dictionary = {}
	var base: int = 24
	var icon_id: String = ""
	var body: MarginContainer
	var _title: Label
	var _status_left: Label
	var _status_right: Label
	var _status_bar: HBoxContainer
	var _close: Button
	var _min: Button

	func _init(p: Dictionary, base_px: int, icon: String, title_text: String) -> void:
		pal = p
		base = base_px
		icon_id = icon
		mouse_filter = Control.MOUSE_FILTER_STOP
		_title = OSApp.make_label(title_text, OSTheme.V_ON_DARK, false, true)
		add_child(_title)
		_min = _title_button("_", minimise_pressed)
		_close = _title_button("×", close_pressed)
		body = MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			body.add_theme_constant_override("margin_" + side, roundi(base * 0.4))
		add_child(body)
		_build_status()

	func _title_button(glyph: String, sig: Signal) -> Button:
		var b: Button = Button.new()
		b.text = glyph
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", roundi(base * 0.8))
		b.pressed.connect(func() -> void: sig.emit())
		add_child(b)
		return b

	func _build_status() -> void:
		_status_bar = HBoxContainer.new()
		add_child(_status_bar)
		for i: int in 2:
			var cell: PanelContainer = PanelContainer.new()
			cell.theme_type_variation = OSTheme.V_SUNKEN
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if i == 0 else Control.SIZE_SHRINK_END
			var l: Label = OSApp.make_label("", OSTheme.V_SMALL, false, i == 0)
			cell.add_child(l)
			_status_bar.add_child(cell)
			if i == 0:
				_status_left = l
			else:
				_status_right = l

	func set_title(text: String) -> void:
		_title.text = text

	func set_status(text: String) -> void:
		_status_left.text = text

	func set_status_right(text: String) -> void:
		_status_right.text = text

	func get_status() -> String:
		return _status_left.text

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_layout()

	func title_height() -> float:
		return base * 1.6

	func frame_width() -> float:
		return OSTheme.bevel_width(base) * 3.0

	func _layout() -> void:
		var fw: float = frame_width()
		var th: float = title_height()
		var bs: float = th - fw * 1.5
		_close.position = Vector2(size.x - fw - bs - base * 0.2, fw + (th - bs) * 0.25)
		_close.size = Vector2(bs, bs)
		_min.position = _close.position - Vector2(bs + base * 0.15, 0)
		_min.size = Vector2(bs, bs)
		_title.position = Vector2(fw + th, fw)
		_title.size = Vector2(maxf(_min.position.x - _title.position.x - base * 0.3, 0.0), th)
		_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var status_h: float = base * 1.55
		_status_bar.position = Vector2(fw, size.y - fw - status_h)
		_status_bar.size = Vector2(size.x - fw * 2.0, status_h)
		body.position = Vector2(fw, fw + th)
		body.size = Vector2(size.x - fw * 2.0, size.y - th - status_h - fw * 2.0)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		OSTheme.draw_bevel(self, r, pal, false, base)
		var fw: float = frame_width()
		var bar: Rect2 = Rect2(Vector2(fw, fw), Vector2(size.x - fw * 2.0, title_height()))
		OSTheme.draw_title_bar(self, bar, pal, true)
		var side: float = bar.size.y * 0.72
		OSTheme.draw_icon(self, icon_id, Rect2(bar.position + Vector2(base * 0.25, (bar.size.y - side) * 0.5),
				Vector2(side, side)), pal)


## Barra de tareas: botón de inicio, aplicación abierta y bandeja (reloj de juego y velocidad).
class Taskbar extends PanelContainer:
	signal start_pressed()
	signal task_pressed()
	var pal: Dictionary = {}
	var base: int = 24
	var _start: Button
	var _task: Button
	var _speed: Label
	var _clock: Label
	var _day: Label
	var _tray: PanelContainer

	func _init(p: Dictionary, base_px: int, guest: bool) -> void:
		pal = p
		base = base_px
		theme_type_variation = OSTheme.V_RAISED
		var h: HBoxContainer = HBoxContainer.new()
		add_child(h)
		_start = Button.new()
		_start.text = OSApp.t("OS_GUEST_START") if guest else OSApp.t("OS_START")
		_start.theme_type_variation = OSTheme.V_DANGER if guest else OSTheme.V_PRIMARY
		_start.add_theme_font_override("font", UITheme.font(UITheme.FONT_BOLD))
		_start.pressed.connect(func() -> void: start_pressed.emit())
		h.add_child(_start)
		_task = Button.new()
		_task.theme_type_variation = OSTheme.V_TASK
		_task.visible = false
		_task.custom_minimum_size.x = base * 9.0
		_task.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_task.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_task.pressed.connect(func() -> void: task_pressed.emit())
		h.add_child(_task)
		var gap: Control = Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(gap)
		h.add_child(_build_tray())

	func _build_tray() -> PanelContainer:
		_tray = PanelContainer.new()
		_tray.theme_type_variation = OSTheme.V_SUNKEN
		var h: HBoxContainer = HBoxContainer.new()
		_tray.add_child(h)
		h.add_child(OSApp.OSIcon.new(pal, "snail", base * 1.2))
		_speed = OSApp.make_label("", OSTheme.V_SMALL)
		h.add_child(_speed)
		_day = OSApp.make_label("", OSTheme.V_SMALL)
		h.add_child(_day)
		_clock = OSApp.make_label("", OSTheme.V_HEADING)
		_clock.add_theme_font_override("font", UITheme.tabular(UITheme.font(UITheme.FONT_BOLD)))
		h.add_child(_clock)
		_tray.tooltip_text = OSApp.t("OS_TRAY_SPEED_TIP")
		return _tray

	func update_clock() -> void:
		var clock_text: String = UITheme.format_hour(GameClock.get_hour(), GameClock.get_minute())
		if _clock.text != clock_text:
			_clock.text = clock_text
			_day.text = OSApp.t("OS_TRAY_DAY", [GameClock.get_day()])
			_speed.text = OSApp.t("OS_TRAY_SPEED", [roundi(GameClock.get_speed_multiplier() * StellarOS.PERCENT)])

	func set_task(text: String) -> void:
		_task.text = text
		_task.visible = not text.is_empty()

	func set_task_down(down: bool) -> void:
		_task.toggle_mode = true
		_task.set_pressed_no_signal(down)

	func get_clock_text() -> String:
		return _clock.text

	func get_start_button() -> Button:
		return _start

	func get_tray_rect() -> Rect2:
		return _tray.get_global_rect()


## Menú de inicio: franja lateral con el nombre del producto y las aplicaciones disponibles.
class StartMenu extends PanelContainer:
	signal app_chosen(app_id: String)
	signal shutdown_chosen()
	var pal: Dictionary = {}
	var base: int = 24
	var _banner: Control

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		theme_type_variation = OSTheme.V_RAISED
		var h: HBoxContainer = HBoxContainer.new()
		add_child(h)
		_banner = Control.new()
		_banner.custom_minimum_size = Vector2(base * 1.8, 0)
		_banner.draw.connect(_draw_banner)
		h.add_child(_banner)
		var col: VBoxContainer = VBoxContainer.new()
		col.name = "Items"
		col.custom_minimum_size.x = base * 12.0
		h.add_child(col)

	func fill(apps: Array[String], locked: Array[String]) -> void:
		var col: VBoxContainer = find_child("Items", true, false) as VBoxContainer
		OSApp.clear_children(col)
		for app_id: String in apps:
			var row: OSApp.OSRow = OSApp.OSRow.new(pal, base, app_id, OSApp.t(StellarOS.app_name_key(app_id)))
			if locked.has(app_id):
				row.set_icon("lock")
			row.pressed.connect(func() -> void: app_chosen.emit(app_id))
			col.add_child(row)
		col.add_child(HSeparator.new())
		var off: OSApp.OSRow = OSApp.OSRow.new(pal, base, "cross", OSApp.t("OS_SHUT_DOWN"))
		off.pressed.connect(func() -> void: shutdown_chosen.emit())
		col.add_child(off)

	func _draw_banner() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, _banner.size)
		OSTheme.draw_vgradient(_banner, r, OSTheme.col(pal, "title_b"), OSTheme.col(pal, "title_a"))
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(base * 1.1)
		_banner.draw_set_transform(Vector2(r.size.x * 0.5 + fs * 0.36, r.size.y - base * 0.5), -PI * 0.5, Vector2.ONE)
		_banner.draw_string(f, Vector2.ZERO, OSApp.t(str(pal.get("product_key", ""))), HORIZONTAL_ALIGNMENT_LEFT,
				-1, fs, OSTheme.col(pal, "title_text"))
		_banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Reloj de arena del equipo lento: bloquea los clics y anima la apertura de ventanas.
class BusyOverlay extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var _from: Rect2 = Rect2()
	var _to: Rect2 = Rect2()
	var _duration: float = 0.0
	var _elapsed: float = 0.0
	var _count: int = 0

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_BUSY
		visible = false
		set_process(false)

	func set_zoom(from_rect: Rect2, to_rect: Rect2) -> void:
		_from = from_rect
		_to = to_rect

	func begin(seconds: float) -> void:
		_count += 1
		_duration = maxf(seconds, 0.01)
		_elapsed = 0.0
		visible = true
		set_process(true)

	func end() -> void:
		_count = maxi(_count - 1, 0)
		if _count == 0:
			visible = false
			set_process(false)
			_from = Rect2()
			_to = Rect2()

	func is_busy() -> bool:
		return _count > 0

	func _process(delta: float) -> void:
		_elapsed += delta
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
		if _to.has_area():
			for i: int in 4:
				var k: float = clampf(t - i * 0.08, 0.0, 1.0)
				var r: Rect2 = Rect2(_from.position.lerp(_to.position, k), _from.size.lerp(_to.size, k))
				draw_rect(r, Color(OSTheme.col(pal, "dark"), 0.8 - i * 0.15), false, 2.0)
		var target: Rect2 = _to if _to.has_area() else Rect2(Vector2.ZERO, size)
		var side: float = base * 3.2
		var hg: Rect2 = Rect2(target.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
		OSTheme.draw_panel(self, hg.grow(base * 0.6), pal, Color(OSTheme.col(pal, "face"), 0.92))
		OSTheme.draw_hourglass(self, hg, OSTheme.col(pal, "dark"), fmod(_elapsed * 0.9, 1.0))


## Pantalla de arranque: BIOS (aspectos biselados), presentación con anuncios internos, o inicio de
## sesión de invitado (intrusión) con la foto del dueño del equipo.
class BootScreen extends Control:
	var pal: Dictionary = {}
	var base: int = 24
	var progress: float = 0.0
	var tips: int = 0
	var guest_name: String = ""
	var guest_appearance: Dictionary = {}
	var tip_offset: int = 0

	func _init(p: Dictionary, base_px: int) -> void:
		pal = p
		base = base_px
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_BUSY

	func set_progress(value: float) -> void:
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

	func in_bios() -> bool:
		return guest_name.is_empty() and bool(pal.get("bevel", false)) and progress < StellarOS.BIOS_FRACTION

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		if not guest_name.is_empty():
			_draw_login(r)
		elif in_bios():
			_draw_bios(r)
		else:
			_draw_splash(r)

	func _draw_bios(r: Rect2) -> void:
		draw_rect(r, Color("#050505"))
		var f: Font = UITheme.font(UITheme.FONT_MONO)
		var fs: int = roundi(base * 0.9)
		var shown: int = floori(progress / StellarOS.BIOS_FRACTION * float(StellarOS.BIOS_LINES + 1))
		for i: int in mini(shown, StellarOS.BIOS_LINES):
			var line: String = OSApp.t("OS_BIOS_%d" % (i + 1))
			draw_string(f, Vector2(base * 2.0, base * 3.0 + i * fs * 1.6), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color("#c8c8c8") if i > 0 else Color("#f5c542"))
		if fmod(progress * 40.0, 2.0) < 1.0:
			draw_rect(Rect2(base * 2.0, base * 3.0 + mini(shown, StellarOS.BIOS_LINES) * fs * 1.6 - fs * 0.8,
					fs * 0.6, fs * 0.15), Color("#c8c8c8"))
		OSTheme.draw_logo(self, Vector2(r.size.x - base * 6.0, base * 4.5), base * 2.2, Color("#f5c542"), Color("#2e7d32"))

	func _draw_splash(r: Rect2) -> void:
		OSTheme.draw_vgradient(self, r, OSTheme.col(pal, "desk_dark"), OSTheme.col(pal, "desk"))
		var c: Vector2 = r.get_center() - Vector2(0, r.size.y * 0.12)
		OSTheme.draw_logo(self, c - Vector2(r.size.x * 0.17, 0), base * 3.4, Color(OSTheme.col(pal, "band_light"), 0.9),
				OSTheme.col(pal, "dark"))
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		var ink: Color = OSTheme.col(pal, "dark") if pal.get("skin") == OSTheme.SKIN_SOVEREIGN else Color.WHITE
		draw_string(f, c + Vector2(-r.size.x * 0.06, base * 0.6), OSApp.t(str(pal.get("product_key", ""))),
				HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(base * 3.2), ink)
		draw_string(UITheme.font(UITheme.FONT_SEMIBOLD), c + Vector2(-r.size.x * 0.06, base * 2.1),
				OSApp.t(str(pal.get("edition_key", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(base * 1.0), Color(ink, 0.85))
		_draw_bar(Rect2(c.x - r.size.x * 0.2, c.y + base * 4.0, r.size.x * 0.4, base * 1.2))
		if tips > 0:
			_draw_tip(Rect2(c.x - r.size.x * 0.24, c.y + base * 6.6, r.size.x * 0.48, base * 4.2))

	func _draw_bar(bar: Rect2) -> void:
		OSTheme.draw_bevel(self, bar, pal, true, base)
		var inner: Rect2 = bar.grow(-OSTheme.bevel_width(base) * 2.5)
		if not pal.get("bevel", false):
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * progress, inner.size.y)), OSTheme.col(pal, "accent"))
			return
		var block: float = inner.size.y * 0.8
		var count: int = floori(inner.size.x * progress / (block + 3.0))
		for i: int in count:
			draw_rect(Rect2(inner.position + Vector2(i * (block + 3.0), 0), Vector2(block, inner.size.y)),
					OSTheme.col(pal, "select"))

	func _draw_tip(card: Rect2) -> void:
		OSTheme.draw_panel(self, card, pal, OSTheme.col(pal, "paper"))
		OSTheme.draw_icon(self, "idea", Rect2(card.position + Vector2(base * 0.5, base * 0.6), Vector2(base * 2.6, base * 2.6)), pal)
		var index: int = (tip_offset + mini(floori(progress * tips), tips - 1)) % StellarOS.BOOT_TIP_COUNT + 1
		var f: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		var fs: int = roundi(base * 0.95)
		draw_string(UITheme.font(UITheme.FONT_BOLD), card.position + Vector2(base * 3.6, base * 1.2),
				OSApp.t("OS_BOOT_TIP_HEADER"), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(base * 0.7), OSTheme.col(pal, "accent"))
		draw_multiline_string(f, card.position + Vector2(base * 3.6, base * 2.3), OSApp.t("OS_BOOT_TIP_%d" % index),
				HORIZONTAL_ALIGNMENT_LEFT, card.size.x - base * 4.2, fs, 3, Color("#1c1d18"))

	func _draw_login(r: Rect2) -> void:
		OSTheme.draw_vgradient(self, r, OSTheme.col(pal, "desk_dark"), OSTheme.col(pal, "desk"))
		var card: Rect2 = Rect2(r.get_center() - Vector2(base * 12.0, base * 7.0), Vector2(base * 24.0, base * 14.0))
		OSTheme.draw_bevel(self, card, pal, false, base)
		var title: Rect2 = Rect2(card.position + Vector2(4, 4), Vector2(card.size.x - 8, base * 1.6))
		OSTheme.draw_title_bar(self, title, pal, true)
		var f: Font = UITheme.font(UITheme.FONT_BOLD)
		draw_string(f, title.position + Vector2(base * 0.5, base * 1.1), OSApp.t("OS_GUEST_LOGIN_TITLE"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(base * 0.85), OSTheme.col(pal, "title_text"))
		var photo: Rect2 = Rect2(card.position + Vector2(base * 1.2, base * 2.8), Vector2(base * 7.0, base * 7.0))
		_draw_photo(photo)
		var x: float = photo.end.x + base * 1.0
		var ink: Color = OSTheme.col(pal, "text")
		draw_string(f, Vector2(x, photo.position.y + base * 1.2), guest_name, HORIZONTAL_ALIGNMENT_LEFT, card.end.x - x - base,
				roundi(base * 1.2), ink)
		draw_string(UITheme.font(UITheme.FONT_MONO), Vector2(x, photo.position.y + base * 3.2),
				OSApp.t("OS_GUEST_PASSWORD") + "•".repeat(floori(progress * 9.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(base * 0.9), ink)
		draw_multiline_string(UITheme.font(UITheme.FONT_REGULAR), Vector2(x, photo.position.y + base * 5.0),
				OSApp.t("OS_GUEST_LOGIN_HINT"), HORIZONTAL_ALIGNMENT_LEFT, card.end.x - x - base, roundi(base * 0.75), 3,
				OSTheme.col(pal, "muted"))
		_draw_bar(Rect2(card.position.x + base * 1.2, card.end.y - base * 2.4, card.size.x - base * 2.4, base * 1.0))

	func _draw_photo(photo: Rect2) -> void:
		OSTheme.draw_bevel(self, photo.grow(4), pal, true, base)
		if guest_appearance.is_empty():
			OSTheme.draw_icon(self, "user", photo, pal)
			return
		CharacterPainter.draw_portrait(self, guest_appearance, photo)


## Anuncio interno emergente (§13.3: «publicidad interna» del equipo de R1).
class AdPopup extends Control:
	signal dismissed()
	var pal: Dictionary = {}
	var base: int = 24
	var index: int = 1
	var icon_id: String = "star"

	func _init(p: Dictionary, base_px: int, ad_index: int, icon: String) -> void:
		pal = p
		base = base_px
		index = ad_index
		icon_id = icon
		size = Vector2(base * 20.0, base * 10.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var title: Label = OSApp.make_label(OSApp.t("OS_AD_WINDOW_TITLE"), OSTheme.V_ON_DARK, false, true)
		title.position = Vector2(base * 0.5, base * 0.2)
		title.size = Vector2(size.x - base * 3.0, base * 1.3)
		add_child(title)
		var close: Button = Button.new()
		close.text = "×"
		close.position = Vector2(size.x - base * 1.6, base * 0.25)
		close.size = Vector2(base * 1.2, base * 1.2)
		close.pressed.connect(func() -> void: dismissed.emit())
		add_child(close)
		_build_body()

	func _build_body() -> void:
		var head: Label = OSApp.make_label(OSApp.t("OS_AD_%d_TITLE" % index), OSTheme.V_TITLE, true)
		head.position = Vector2(base * 5.2, base * 2.2)
		head.size = Vector2(size.x - base * 6.0, base * 1.5)
		head.add_theme_color_override("font_color", OSTheme.col(pal, "accent"))
		add_child(head)
		var body: Label = OSApp.make_label(OSApp.t("OS_AD_%d_BODY" % index), OSTheme.V_SMALL, true)
		body.position = Vector2(base * 5.2, base * 3.9)
		body.size = Vector2(size.x - base * 6.0, base * 3.4)
		add_child(body)
		var ok: Button = Button.new()
		ok.text = OSApp.t("OS_AD_%d_BUTTON" % index)
		ok.theme_type_variation = OSTheme.V_PRIMARY
		ok.pressed.connect(func() -> void: dismissed.emit())
		add_child(ok)
		ok.position = Vector2(base * 5.2, size.y - base * 2.3)
		ok.size = Vector2(size.x - base * 6.0, base * 1.7)

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0, 0, 0, 0.3))
		OSTheme.draw_bevel(self, r, pal, false, base)
		OSTheme.draw_title_bar(self, Rect2(Vector2(4, 4), Vector2(size.x - 8, base * 1.7)), pal, true)
		var art: Rect2 = Rect2(Vector2(base * 0.8, base * 2.6), Vector2(base * 3.8, base * 3.8))
		draw_circle(art.get_center(), art.size.x * 0.55, Color(OSTheme.col(pal, "paper"), 0.9))
		OSTheme.draw_icon(self, icon_id, art, pal)


## Contenido de una aplicación sin desplegar (PERSONNEL/PORTAL/MARKET mientras no existan).
class NotDeployedApp extends OSApp:
	func build() -> void:
		var center: CenterContainer = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var col: VBoxContainer = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		center.add_child(col)
		var art: OSApp.OSIcon = make_icon("not_found", 7.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(art)
		var head: Label = make_label(t("OS_404_TITLE"), OSTheme.V_BIG)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var ticket: int = absi(hash(app_id)) % 90000 + 10000
		var body: Label = make_label(t("OS_404_BODY", [t(StellarOS.app_name_key(app_id)), ticket]), "", true)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.custom_minimum_size.x = base * 26.0
		col.add_child(body)
		var ok: Button = make_button(t("OS_404_OK"), func() -> void: close_requested.emit(), OSTheme.V_PRIMARY)
		ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ok)

	func get_title_key() -> String:
		return "OS_404_WINDOW"


# ─── Ciclo de vida ────────────────────────────────────────────────

func _init() -> void:
	name = "StellarOS"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Contexto del ordenador (ver cabecera). UIRoot lo llama antes de añadirlo al árbol.
func setup(context: Dictionary) -> void:
	_context = context.duplicate(true)
	_npc_id = str(_context.get("npc_id", ""))
	var guest: bool = str(_context.get("session", "")) == SESSION_GUEST or not _npc_id.is_empty()
	_session = SESSION_GUEST if guest else SESSION_OWN
	_instant = bool(_context.get("instant", false))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_managed = str(get_meta(META_KIND, "")) == KIND_COMPUTER
	_tier = _resolve_tier()
	_base = UITheme.base_font_size(UITheme.current_text_size)
	_pal = OSTheme.palette_for_tier(_tier)
	theme = OSTheme.build(_pal, _base)
	_rng.seed = hash("%d:%s:%d" % [GameClock.get_run_seed(), RNG_SALT, GameClock.get_day()])
	_build_desktop()
	_take_clock()
	_start_boot()


func _exit_tree() -> void:
	_release_clock()


func _process(delta: float) -> void:
	if not _booted:
		_advance_boot(delta)
		return
	_taskbar.update_clock()
	_tick_ads(delta)
	_tick_balloon(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _window_layer != null:
		_layout_desktop()


## Fuera de UIRoot el escritorio atiende Esc (cerrar lo de arriba) y C (apagar).
func _unhandled_input(event: InputEvent) -> void:
	if _managed or not event.is_pressed() or event.is_echo():
		return
	if _action(event, "pause_menu") or _action(event, "ui_cancel"):
		request_close()
	elif _action(event, "computer"):
		shut_down()
	else:
		return
	get_viewport().set_input_as_handled()


func _action(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


# ─── API pública ──────────────────────────────────────────────────

## Intrusión en el ordenador de un personaje (enrutador de interacciones): sesión de invitado con
## FILES. context opcional: {computer_id, room_id, contains}. Devuelve el escritorio abierto (o null).
static func open_intrusion(npc_id: String, context: Dictionary = {}) -> Control:
	var ctx: Dictionary = context.duplicate(true)
	ctx["session"] = SESSION_GUEST
	ctx["npc_id"] = npc_id
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ui: UIRoot = UIRoot.find(tree)
	if ui != null:
		ui.open_computer(ctx)
		var top: Control = ui.get_top_modal()
		return top if top is StellarOS else null
	var os: StellarOS = StellarOS.new()
	os.setup(ctx)
	tree.root.add_child(os)
	return os


static func app_name_key(app_id: String) -> String:
	return APP_NAME_FORMAT % app_id.to_upper()


static func tier_for_player() -> int:
	var occ: OccupationData = PlayerState.get_occupation()
	return OSTheme.clamp_tier(occ.computer_tier if occ != null and occ.computer_tier > 0 else 1)


## Equipo del dueño del ordenador intervenido: el de su ocupación (o su escalón).
static func tier_for_npc(npc_id: String) -> int:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return 1
	var occ: OccupationData = Database.get_occupation(npc.occupation_id)
	if occ != null and occ.computer_tier > 0:
		return OSTheme.clamp_tier(occ.computer_tier)
	return OSTheme.clamp_tier(npc.tier)


static func boot_seconds_for_tier(tier: int) -> float:
	return maxf(OSTheme.per_tier(B_BOOT, tier), 0.0)


static func window_lag_for_tier(tier: int) -> float:
	return maxf(OSTheme.per_tier(B_LAG, tier), 0.0)


func get_tier() -> int:
	return _tier


func get_session() -> String:
	return _session


func is_guest() -> bool:
	return _session == SESSION_GUEST


func get_intrusion_npc() -> String:
	return _npc_id


func get_context() -> Dictionary:
	return _context.duplicate(true)


func get_palette() -> Dictionary:
	return _pal


func get_base_size() -> int:
	return _base


func is_booted() -> bool:
	return _booted


func get_boot_duration() -> float:
	return _boot_duration


func get_window_lag() -> float:
	return 0.0 if _instant else window_lag_for_tier(_tier)


func is_busy() -> bool:
	return _busy != null and _busy.is_busy()


func skip_boot() -> void:
	if not _booted:
		_finish_boot()


## Espera del equipo lento: reloj de arena y clics bloqueados durante retardo × factor segundos reales.
func wait_lag(factor: float = 1.0) -> void:
	var seconds: float = get_window_lag() * factor
	if seconds <= 0.0 or not is_inside_tree():
		return
	_busy.begin(seconds)
	var timer: Timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()
	_busy.end()


## DutySystem de la partida; si no existe, uno de respaldo que vive con el escritorio.
func get_duty_system() -> DutySystem:
	if is_instance_valid(_fallback_duties):
		return _fallback_duties
	var found: DutySystem = get_tree().get_first_node_in_group(DutySystem.GROUP) as DutySystem \
			if is_inside_tree() else null
	if found != null:
		return found
	_fallback_duties = DutySystem.new()
	_fallback_duties.name = "FallbackDutySystem"
	add_child(_fallback_duties)
	return _fallback_duties


## Aplicaciones que muestra el escritorio (MARKET solo si la ocupación la desbloquea).
func get_desktop_apps() -> Array[String]:
	var out: Array[String] = []
	for app_id: String in APP_ORDER:
		if app_id != APP_MARKET or _market_unlocked():
			out.append(app_id)
	return out


func is_app_available(app_id: String) -> bool:
	if not get_desktop_apps().has(app_id):
		return false
	return not is_guest() or GUEST_APPS.has(app_id)


func get_open_app() -> Control:
	return _app if is_instance_valid(_app) else null


func get_open_app_id() -> String:
	return _app_id


func get_window_status() -> String:
	return _window.get_status() if _window != null else ""


func get_taskbar_clock() -> String:
	return _taskbar.get_clock_text()


func get_ads() -> Array[Control]:
	var out: Array[Control] = []
	for ad: Control in _ads:
		if is_instance_valid(ad):
			out.append(ad)
	return out


## Abre una aplicación (espera del equipo incluida). Devuelve su Control o null. Usar con await.
func open_app(app_id: String) -> Control:
	if not _booted or _opening:
		return null
	if not is_app_available(app_id):
		notify(t("OS_ACCESS_DENIED", [t(app_name_key(app_id))]) if is_guest() else t("OS_APP_UNKNOWN"))
		return null
	_close_start_menu()
	if _app_id == app_id and _window != null:
		_show_window(true)
		return _app
	close_app()
	_opening = true
	_busy.set_zoom(_icon_rect(app_id), _window_rect())
	await wait_lag(1.0)
	_opening = false
	return _mount_app(app_id)


## Cierra la aplicación en primer plano (le deja guardar lo pendiente).
func close_app() -> void:
	if _window == null:
		return
	if is_instance_valid(_app) and _app.has_method("on_closing"):
		_app.call("on_closing")
	var closed_id: String = _app_id
	_window.queue_free()
	_window = null
	_app = null
	_app_id = ""
	_taskbar.set_task("")
	app_closed.emit(closed_id)


## Esc: cierra el menú de inicio, luego la aplicación y, en el escritorio vacío, apaga.
func request_close() -> void:
	if _start_menu.visible:
		_close_start_menu()
	elif _window != null:
		close_app()
	else:
		shut_down()


func shut_down() -> void:
	close_app()
	close_requested.emit()
	if not _managed:
		queue_free()


## UIRoot la llama al cerrar el modal: la aplicación guarda lo pendiente.
func cancel() -> void:
	close_app()


## Barra de estado de la ventana abierta (o globo de la bandeja en el escritorio).
func post_status(text: String) -> void:
	if _window != null:
		_window.set_status(text)
	else:
		notify(text)


## Globo de aviso junto a la bandeja (estilo del sistema).
func notify(text: String) -> void:
	_balloon_label.text = text
	_balloon.visible = true
	_balloon_left = UITheme.tune(B_BALLOON)
	_balloon.reset_size()
	var tray: Rect2 = _taskbar.get_tray_rect()
	var local: Vector2 = tray.position - get_global_rect().position
	_balloon.position = Vector2(size.x - _balloon.size.x - _base * 0.4, local.y - _balloon.size.y - _base * 0.3)


func get_balloon_text() -> String:
	return _balloon_label.text if _balloon.visible else ""


## Anuncio interno emergente (índice 1..AD_ICONS.size(); −1 = al azar). Devuelve el anuncio.
func spawn_ad(index: int = -1) -> Control:
	var count: int = AD_ICONS.size()
	var i: int = index if index >= 1 and index <= count else (_ad_serial + _rng.randi_range(0, count - 1)) % count + 1
	_ad_serial += 1
	var ad: AdPopup = AdPopup.new(_pal, _base, i, AD_ICONS[i - 1])
	_ad_layer.add_child(ad)
	var area: Rect2 = _window_rect()
	var span: Vector2 = (area.size - ad.size).max(Vector2.ZERO)
	ad.position = area.position + Vector2(_rng.randf() * span.x, _rng.randf() * span.y)
	ad.dismissed.connect(_dismiss_ad.bind(ad))
	_ads.append(ad)
	return ad


# ─── Construcción ─────────────────────────────────────────────────

func _resolve_tier() -> int:
	if _context.has("tier"):
		return OSTheme.clamp_tier(int(_context["tier"]))
	return tier_for_npc(_npc_id) if is_guest() else tier_for_player()


func _build_desktop() -> void:
	add_child(Wallpaper.new(_pal))
	_build_icons()
	if is_guest():
		add_child(_guest_banner())
	_window_layer = _layer("Windows", Control.MOUSE_FILTER_IGNORE)
	_ad_layer = _layer("Ads", Control.MOUSE_FILTER_IGNORE)
	_taskbar = Taskbar.new(_pal, _base, is_guest())
	_taskbar.start_pressed.connect(_toggle_start_menu)
	_taskbar.task_pressed.connect(_on_task_pressed)
	add_child(_taskbar)
	_start_menu = StartMenu.new(_pal, _base)
	_start_menu.visible = false
	_start_menu.app_chosen.connect(func(app_id: String) -> void: open_app(app_id))
	_start_menu.shutdown_chosen.connect(shut_down)
	add_child(_start_menu)
	_build_balloon()
	_busy = BusyOverlay.new(_pal, _base)
	add_child(_busy)
	_boot = BootScreen.new(_pal, _base)
	add_child(_boot)
	if bool(_pal.get("scanlines", false)):
		add_child(Scanlines.new(_base))
	_layout_desktop()


func _layer(layer_name: String, filter: Control.MouseFilter) -> Control:
	var layer: Control = Control.new()
	layer.name = layer_name
	layer.mouse_filter = filter
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer


func _build_icons() -> void:
	var locked: Array[String] = []
	for app_id: String in get_desktop_apps():
		var icon: DesktopIcon = DesktopIcon.new(_pal, _base, app_id, t(app_name_key(app_id)))
		icon.locked = not is_app_available(app_id)
		if icon.locked:
			locked.append(app_id)
		if app_id == APP_MAIL and not is_guest():
			icon.badge = MailApp.pending_count(get_duty_system())
		icon.activated.connect(func(id: String) -> void: open_app(id))
		add_child(icon)
		_icons[app_id] = icon


func _guest_banner() -> PanelContainer:
	var banner: PanelContainer = PanelContainer.new()
	banner.name = "GuestBanner"
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = OSTheme.col(_pal, "bad")
	sb.content_margin_left = _base * 0.8
	sb.content_margin_right = _base * 0.8
	sb.content_margin_top = _base * 0.25
	sb.content_margin_bottom = _base * 0.25
	banner.add_theme_stylebox_override("panel", sb)
	var l: Label = OSApp.make_label(t("OS_GUEST_BANNER", [OSApp.npc_name(_npc_id)]), OSTheme.V_HEADING)
	l.add_theme_color_override("font_color", Color.WHITE)
	banner.add_child(l)
	return banner


func _build_balloon() -> void:
	_balloon = PanelContainer.new()
	_balloon.name = "Balloon"
	_balloon.add_theme_stylebox_override("panel", OSTheme.box(_pal, "tooltip", _base, Vector2(_base * 0.6, _base * 0.4)))
	_balloon_label = OSApp.make_label("", "", true)
	_balloon_label.custom_minimum_size.x = _base * 16.0
	_balloon.add_child(_balloon_label)
	_balloon.visible = false
	_balloon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_balloon)


func _layout_desktop() -> void:
	var tb_h: float = _base * 2.3
	_taskbar.position = Vector2(0, size.y - tb_h)
	_taskbar.size = Vector2(size.x, tb_h)
	var margin: float = _base * 0.6
	var cell: Vector2 = Vector2(_base * 5.0, _base * 4.4)
	var rows: int = maxi(floori((size.y - tb_h - margin * 2.0) / cell.y), 1)
	var i: int = 0
	for app_id: String in get_desktop_apps():
		var icon: DesktopIcon = _icons[app_id]
		icon.position = Vector2(margin + floorf(float(i) / float(rows)) * cell.x, margin + (i % rows) * cell.y)
		icon.size = cell
		i += 1
	var guest_banner: Control = get_node_or_null("GuestBanner") as Control
	if guest_banner != null:
		guest_banner.reset_size()
		guest_banner.position = Vector2((size.x - guest_banner.size.x) * 0.5, 0)
	if _window != null:
		var r: Rect2 = _window_rect()
		_window.position = r.position
		_window.size = r.size
	_start_menu.reset_size()
	_start_menu.position = Vector2(0, size.y - tb_h - _start_menu.size.y)


## Área de las ventanas: a la derecha de la columna de iconos, sobre la barra de tareas.
func _window_rect() -> Rect2:
	var tb_h: float = _base * 2.3
	var margin: float = _base * 0.6
	var cell: Vector2 = Vector2(_base * 5.0, _base * 4.4)
	var rows: int = maxi(floori((size.y - tb_h - margin * 2.0) / cell.y), 1)
	var cols: int = ceili(float(get_desktop_apps().size()) / float(rows))
	var left: float = margin * 2.0 + cols * cell.x
	var top: float = margin + (_base * 1.8 if is_guest() else 0.0)
	return Rect2(left, top, maxf(size.x - left - margin, _base * 10.0), maxf(size.y - tb_h - top - margin, _base * 10.0))


func _icon_rect(app_id: String) -> Rect2:
	var icon: DesktopIcon = _icons.get(app_id) as DesktopIcon
	return Rect2(icon.position, icon.size) if icon != null else Rect2()


# ─── Arranque ─────────────────────────────────────────────────────

func _start_boot() -> void:
	if _instant:
		_boot_duration = 0.0
	elif is_guest():
		_boot_duration = maxf(UITheme.tune(B_GUEST_LOGIN), 0.0)
	else:
		_boot_duration = boot_seconds_for_tier(_tier)
	_boot.tips = roundi(OSTheme.per_tier(B_BOOT_TIPS, _tier))
	_boot.tip_offset = _rng.randi_range(0, BOOT_TIP_COUNT - 1)
	if is_guest():
		_boot.guest_name = OSApp.npc_name(_npc_id)
		var npc: NPCRuntime = NPCDirector.get_npc(_npc_id)
		_boot.guest_appearance = CharacterPainter.appearance_for_npc(npc) if npc != null else {}
	if _boot_duration <= 0.0:
		_finish_boot()


func _advance_boot(delta: float) -> void:
	_boot_elapsed += delta
	_boot.set_progress(_boot_elapsed / maxf(_boot_duration, 0.001))
	if _boot_elapsed >= _boot_duration:
		_finish_boot()


func _finish_boot() -> void:
	_booted = true
	_boot.visible = false
	_taskbar.update_clock()
	booted.emit()
	var first_app: String = APP_FILES if is_guest() else str(_context.get("app", ""))
	if not first_app.is_empty():
		open_app(first_app)


# ─── Ventanas ─────────────────────────────────────────────────────

func _mount_app(app_id: String) -> Control:
	var app: Control = _instantiate_app(app_id)
	var title_key: String = str(app.call("get_title_key")) if app.has_method("get_title_key") else ""
	var title: String = t(title_key if not title_key.is_empty() else app_name_key(app_id))
	_window = OSWindow.new(_pal, _base, app_id if APP_SCRIPTS.has(app_id) else "not_found", title)
	_window.close_pressed.connect(close_app)
	_window.minimise_pressed.connect(func() -> void: _show_window(false))
	_window_layer.add_child(_window)
	var r: Rect2 = _window_rect()
	_window.position = r.position
	_window.size = r.size
	_window.body.add_child(app)
	_window.set_status(t("OS_STATUS_READY"))
	_window.set_status_right(_session_caption())
	if app.has_signal("status_posted"):
		app.connect("status_posted", _window.set_status)
	if app.has_signal("close_requested"):
		app.connect("close_requested", close_app)
	_app = app
	_app_id = app_id
	_taskbar.set_task(title)
	_taskbar.set_task_down(true)
	app_opened.emit(app_id)
	return app


func _instantiate_app(app_id: String) -> Control:
	var path: String = APP_DIR + str(APP_SCRIPTS.get(app_id, ""))
	var node: Control = null
	if APP_SCRIPTS.has(app_id) and ResourceLoader.exists(path):
		var script: GDScript = load(path) as GDScript
		if script != null and script.can_instantiate():
			var obj: Object = script.new()
			node = obj as Control
			if node == null and obj is Node:
				node = Control.new()
				node.add_child(obj as Node)
	if node == null:
		node = NotDeployedApp.new()
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if node.has_method("setup"):
		node.call("setup", _app_context(app_id))
	return node


func _app_context(app_id: String) -> Dictionary:
	return {
		"shell": self, "app_id": app_id, "session": _session, "npc_id": _npc_id, "tier": _tier,
		"palette": _pal, "base": _base, "extra": _context.duplicate(true),
	}


func _session_caption() -> String:
	if is_guest():
		return t("OS_SESSION_GUEST", [OSApp.npc_name(_npc_id)])
	var player: String = PlayerState.get_player_name()
	return t("OS_SESSION_OWN", [player if not player.is_empty() else t("OS_SESSION_ANON")])


func _show_window(show: bool) -> void:
	if _window == null:
		return
	_window.visible = show
	_taskbar.set_task_down(show)
	if show and is_instance_valid(_app) and _app.has_method("refresh"):
		_app.call("refresh")


func _on_task_pressed() -> void:
	if _window != null:
		_show_window(not _window.visible)


func _toggle_start_menu() -> void:
	if _start_menu.visible:
		_close_start_menu()
		return
	var locked: Array[String] = []
	for app_id: String in get_desktop_apps():
		if not is_app_available(app_id):
			locked.append(app_id)
	_start_menu.fill(get_desktop_apps(), locked)
	_start_menu.visible = true
	_layout_desktop()


func _close_start_menu() -> void:
	_start_menu.visible = false


# ─── Anuncios y avisos ────────────────────────────────────────────

func _tick_ads(delta: float) -> void:
	var interval: float = OSTheme.per_tier(B_AD_INTERVAL, _tier)
	if interval <= 0.0 or is_guest() or _instant or is_busy():
		return
	_ad_timer += delta
	if _ad_timer < interval:
		return
	_ad_timer = 0.0
	if get_ads().size() < UITheme.tune_int(B_AD_MAX):
		spawn_ad()


func _dismiss_ad(ad: Control) -> void:
	_ads.erase(ad)
	if is_instance_valid(ad):
		ad.queue_free()


func _tick_balloon(delta: float) -> void:
	if not _balloon.visible:
		return
	_balloon_left -= delta
	if _balloon_left <= 0.0:
		_balloon.visible = false


# ─── Reloj (§15.1) ────────────────────────────────────────────────

## Dentro del ordenador el reloj va al 40 % y nunca se pausa. Con UIRoot lo gestiona ella.
func _take_clock() -> void:
	if _managed or _clock_owned:
		return
	_clock_owned = true
	_speed_before = GameClock.get_speed_multiplier()
	GameClock.set_speed_multiplier(UITheme.tune(B_CLOCK_SPEED))


func _release_clock() -> void:
	if not _clock_owned:
		return
	_clock_owned = false
	GameClock.set_speed_multiplier(_speed_before)


func _market_unlocked() -> bool:
	var occ: OccupationData = PlayerState.get_occupation()
	if occ == null:
		return false
	var apps: Variant = occ.extra.get("unlocks_apps", [])
	return apps is Array and (apps as Array).has(MARKET_UNLOCK)


static func t(key: String, args: Array = []) -> String:
	return UITheme.trf(key, args)
