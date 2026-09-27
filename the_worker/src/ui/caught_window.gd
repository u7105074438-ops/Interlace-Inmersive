# caught_window.gd — Ventana de flagrancia (§12.2, PASO 19): tiempo ralentizado, OFRECER DINERO o SILENCIARLO PARA SIEMPRE, cuenta atrás de la inacción y contraoferta.
# PROPIETARIO DE: la vista de la ventana abierta (opciones mostradas, opción armada a la espera de confirmación, segundos que se muestran, resultado que se enseña al cerrar).
# ESCUCHA: CaughtHandler.decision_window_opened/_updated/_closed (el Binder), npc_decided, money_changed, game_over.
class_name CaughtWindow
extends Control

## Integración: game_root llama una vez a CaughtWindow.install(ui_root, caught_handler). El Binder
## abre una CaughtWindow en UIRoot.open_modal(ventana, false) con cada decision_window_opened (sin
## pausar: CaughtHandler ya ralentiza el reloj, flagrancia.multiplicador_tiempo) y cierra el móvil.
## DECISIONES:
##  · Las opciones salen de CaughtHandler.get_options(); la ventana nunca decide precios ni testigos.
##  · SILENCIARLO PARA SIEMPRE con testigos: botón deshabilitado, sin foco, que ignora el ratón,
##    marcado en rojo con el aviso UI_CAUGHT_ELIMINATE_WITNESSES; press_elimination()/confirm()
##    vuelven a leer las opciones y lo rechazan, y CaughtHandler.choose_elimination() también.
##  · Toda opción pide confirmación explícita (§13.7): press_*() arma, confirm() ejecuta.
##  · La cuenta atrás es la del CaughtHandler (seconds_left); al agotarse, el handler resuelve la
##    inacción y la ventana muestra la reacción (npc_decided) durante interfaz.flagrancia_resultado_segundos.
##  · Esc no la cierra (request_close no hace nada): solo el handler cierra la ventana.
##  · Teclado: 1 = dinero, 2 = eliminación (la misma tecla otra vez confirma; el foco queda en
##    «Volver»), Retroceso = volver.

signal closed

const OPTION_BRIBE := "bribe"
const OPTION_ELIMINATE := "eliminate"
const STATE_DECIDING := "deciding"
const STATE_CONFIRM := "confirm"
const STATE_RESULT := "result"
const B_RESULT_S := "interfaz.flagrancia_resultado_segundos"
const B_PULSE_HZ := "interfaz.flagrancia_pulso_hz"
const B_WARN_S := "interfaz.flagrancia_aviso_segundos"
const B_DIM := "interfaz.flagrancia_ralentizacion_visual"
const CRIME_KEY := "CAUGHTUI_CRIME_%s"
const CRIME_GENERIC := "CAUGHTUI_CRIME_GENERIC"
const REACTION_KEY := "CAUGHTUI_REACTION_%s"
const OUTCOME_KEY := "CAUGHTUI_OUTCOME_%s"
const CARD_WIDTH_EMS := 16.0
const PORTRAIT_EMS := 7.0
const DIAL_EMS := 6.0
const VIGNETTE_FRACTION := 0.2
const HATCH_STEP := 18.0
const REACTING_OUTCOMES: Array[String] = [CaughtHandler.OUTCOME_INACTION, Bribery.OUTCOME_NEUTRAL]
const OUTCOME_TONES: Dictionary = {
	Bribery.OUTCOME_ACCEPTED: "gain", Bribery.OUTCOME_DENOUNCED: "danger",
	CaughtHandler.OUTCOME_ELIMINATED: "danger", CaughtHandler.OUTCOME_VOID: "muted",
}


## Conecta las señales del CaughtHandler y abre una ventana por flagrancia.
class Binder extends Node:
	var handler: CaughtHandler
	var ui: UIRoot

	func _init(p_ui: UIRoot, p_handler: CaughtHandler) -> void:
		name = "CaughtWindowBinder"
		ui = p_ui
		handler = p_handler
		handler.decision_window_opened.connect(_on_opened)

	func _on_opened(npc_id: String, options: Dictionary) -> void:
		if not is_instance_valid(ui) or not ui.is_inside_tree():
			return
		var phone: Control = ui.get_top_modal()
		if phone is PhoneOverlay:
			ui.close_modal_control(phone)
		var window: CaughtWindow = CaughtWindow.new()
		window.attach(handler, npc_id, options)
		window.set_meta(UIRoot.META_DIM, false)
		ui.open_modal(window, false)


## Anillo de cuenta atrás con los segundos en el centro.
class Dial extends Control:
	var fraction: float = 1.0
	var seconds: int = 0
	var urgent: bool = false
	var pulse: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			var side: float = PhoneOverlay.base_size(self) * CaughtWindow.DIAL_EMS
			custom_minimum_size = Vector2(side, side)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.46
		if r <= 1.0:
			return
		var col: Color = UITheme.color("danger" if urgent else "hazard")
		draw_circle(c, r + 3.0, CharacterStyle.OUTLINE)
		draw_circle(c, r, UITheme.color("ink"))
		draw_arc(c, r * 0.8, 0.0, TAU, 48, Color(col, 0.18), r * 0.22, true)
		if fraction > 0.0:
			draw_arc(c, r * 0.8, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, col, r * 0.22, true)
		var font: Font = UITheme.tabular(UITheme.font(UITheme.FONT_BOLD))
		var fs: int = roundi(r * (0.78 + 0.1 * pulse))
		var text: String = str(seconds)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				UITheme.color("paper"))


## Tarjeta de opción (botón alto dibujado): icono, título, detalle; roja y rayada si está vetada.
## Su alto mínimo se calcula con el texto envuelto (nunca recorta el aviso ni el precio).
class OptionCard extends Button:
	const TITLE_RATIO := 1.05
	const DETAIL_RATIO := 0.86
	const TITLE_LINES := 2
	const DETAIL_LINES := 5
	var glyph: String = "coin"
	var title: String = ""
	var detail: String = ""
	var tone: String = "hazard"
	var flagged_red: bool = false
	var armed: bool = false
	var hotkey: String = ""
	var pulse: float = 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flat = true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
			refresh_size()

	func set_texts(p_title: String, p_detail: String) -> void:
		title = p_title
		detail = p_detail
		refresh_size()
		queue_redraw()

	func refresh_size() -> void:
		var base: float = PhoneOverlay.base_size(self)
		var m: Dictionary = _metrics(base, maxf(size.x, base * CaughtWindow.CARD_WIDTH_EMS))
		var h: float = base * 1.8 + float(m["title_h"]) + base * 0.3 + float(m["detail_h"])
		var wanted: Vector2 = Vector2(base * CaughtWindow.CARD_WIDTH_EMS, ceilf(maxf(h, base * 5.0)))
		if not wanted.is_equal_approx(custom_minimum_size):
			custom_minimum_size = wanted

	func _metrics(base: float, width: float) -> Dictionary:
		var side: float = base * 2.0
		var x: float = base * 0.9 + side + base * 0.7
		var title_w: float = maxf(width - x - base * 2.6, base * 4.0)
		var detail_w: float = maxf(width - x - base * 0.9, base * 4.0)
		var fs_t: int = roundi(base * TITLE_RATIO)
		var fs_d: int = roundi(base * DETAIL_RATIO)
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var regular: Font = UITheme.font(UITheme.FONT_REGULAR)
		return {"side": side, "x": x, "title_w": title_w, "detail_w": detail_w, "fs_t": fs_t, "fs_d": fs_d,
				"title_h": bold.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, title_w, fs_t,
						TITLE_LINES).y,
				"detail_h": regular.get_multiline_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, detail_w, fs_d,
						DETAIL_LINES).y}

	func _draw() -> void:
		var base: float = PhoneOverlay.base_size(self)
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var col: Color = UITheme.color("danger") if flagged_red else UITheme.color(tone)
		PhoneOverlay.fill_round(self, Rect2(r.position + Vector2(0, 5), r.size), 14.0, Color(0, 0, 0, 0.35))
		PhoneOverlay.fill_round(self, r, 14.0, _background(col))
		if flagged_red:
			_draw_hatch(r, col)
		var border: Color = col if (not disabled or flagged_red) else UITheme.color("faint")
		PhoneOverlay.line_round(self, r, 14.0, CharacterStyle.OUTLINE, 5.0)
		PhoneOverlay.line_round(self, r.grow(-3.0), 11.0, border.lightened(0.15 * pulse if armed else 0.0),
				4.0 if armed else 2.5)
		_draw_text(base, col)

	func _background(col: Color) -> Color:
		if flagged_red:
			return col.darkened(0.72)
		if disabled:
			return UITheme.color("slot").darkened(0.2)
		var hover: bool = is_hovered() or armed
		return col.darkened(0.62 if hover else 0.74)

	func _draw_hatch(r: Rect2, col: Color) -> void:
		var h: float = r.size.y
		var x: float = -h
		while x < r.size.x:
			var a: Vector2 = Vector2(x, h)
			var b: Vector2 = Vector2(x + h, 0.0)
			if a.x < 0.0:
				a = Vector2(0.0, h + x)
			if b.x > r.size.x:
				b = Vector2(r.size.x, h - (r.size.x - x))
			draw_line(a, b, Color(col, 0.16), 7.0, true)
			x += CaughtWindow.HATCH_STEP

	func _draw_text(base: float, col: Color) -> void:
		var ink: Color = UITheme.color("faint") if disabled and not flagged_red else UITheme.color("paper")
		var accent: Color = col.lightened(0.3) if not disabled or flagged_red else ink
		var m: Dictionary = _metrics(base, size.x)
		var side: float = float(m["side"])
		var icon_r: Rect2 = Rect2(base * 0.9, base * 0.9, side, side)
		PhoneOverlay.draw_glyph(self, "lock" if flagged_red else glyph, icon_r, accent, maxf(side * 0.08, 2.0))
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var regular: Font = UITheme.font(UITheme.FONT_REGULAR)
		var fs_t: int = int(m["fs_t"])
		var fs_d: int = int(m["fs_d"])
		var x: float = float(m["x"])
		var top: float = base * 0.9
		draw_multiline_string(bold, Vector2(x, top + bold.get_ascent(fs_t)), title, HORIZONTAL_ALIGNMENT_LEFT,
				float(m["title_w"]), fs_t, TITLE_LINES, ink)
		var detail_top: float = top + float(m["title_h"]) + base * 0.3
		draw_multiline_string(regular, Vector2(x, detail_top + regular.get_ascent(fs_d)), detail,
				HORIZONTAL_ALIGNMENT_LEFT, float(m["detail_w"]), fs_d, DETAIL_LINES, accent if flagged_red else ink)
		if not hotkey.is_empty():
			_draw_hotkey(base)

	func _draw_hotkey(base: float) -> void:
		var cap: Rect2 = Rect2(size.x - base * 2.2, base * 0.8, base * 1.4, base * 1.4)
		PhoneOverlay.fill_round(self, cap, 6.0, UITheme.color("paper") if not disabled else UITheme.color("faint"))
		var bold: Font = UITheme.font(UITheme.FONT_BOLD)
		var fs: int = roundi(base * 0.9)
		var w: float = bold.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(bold, cap.get_center() + Vector2(-w * 0.5, fs * 0.36), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1,
				fs, UITheme.color("ink"))


var handler: CaughtHandler = null
## Contexto extra para CaughtHandler.choose_bribe (herramientas y pruebas: tiradas fijas).
var bribe_ctx: Dictionary = {}
var _npc_id: String = ""
var _options: Dictionary = {}
var _seconds_left: float = 0.0
var _deadline: float = 1.0
var _state: String = STATE_DECIDING
var _armed: String = ""
var _outcome: String = ""
var _reaction: Dictionary = {}
var _result_left: float = 0.0
var _clock: float = 0.0
var _card: PanelContainer
var _badge: PhoneOverlay.Glyph
var _title: Label
var _subtitle: Label
var _photo: PhoneOverlay.Portrait
var _name_label: Label
var _job_label: Label
var _dial: Dial
var _inaction_label: Label
var _witness_label: Label
var _bribe_card: OptionCard
var _elim_card: OptionCard
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _confirm_button: PhoneOverlay.IconButton
var _back_button: PhoneOverlay.IconButton
var _result_panel: PanelContainer
var _result_label: Label
var _notice: Label


func _init() -> void:
	name = "CaughtWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", PhoneOverlay.box(UITheme.color("ink"),
			UITheme.color("danger"), 18, 30.0, 24.0, 3))
	add_child(_card)
	UITheme.center_fitted(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_card.add_child(column)
	column.add_child(_build_title())
	column.add_child(_build_face())
	column.add_child(_build_options())
	_notice = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_color_override("font_color", UITheme.color("loss"))
	_notice.visible = false
	column.add_child(_notice)
	column.add_child(_build_confirm())
	column.add_child(_build_result())


func _build_title() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_badge = PhoneOverlay.Glyph.new("flagrant", "danger", 2.4)
	row.add_child(_badge)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	_title = PhoneOverlay.label(tr("UI_CAUGHT_TITLE").to_upper(), UITheme.V_TITLE)
	_title.add_theme_color_override("font_color", UITheme.color("danger").lightened(0.2))
	text.add_child(_title)
	_subtitle = PhoneOverlay.label("", UITheme.V_STRONG)
	text.add_child(_subtitle)
	return row


func _build_face() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_photo = PhoneOverlay.Portrait.new(PORTRAIT_EMS)
	_photo.frame = UITheme.color("danger")
	row.add_child(_photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_name_label = PhoneOverlay.label("", UITheme.V_TITLE)
	text.add_child(_name_label)
	_job_label = PhoneOverlay.label("", UITheme.V_SMALL)
	text.add_child(_job_label)
	_inaction_label = PhoneOverlay.label("", "", true)
	text.add_child(_inaction_label)
	_witness_label = PhoneOverlay.label("", UITheme.V_STRONG, true)
	text.add_child(_witness_label)
	_dial = Dial.new()
	row.add_child(_dial)
	return row


func _build_options() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_bribe_card = OptionCard.new()
	_bribe_card.glyph = "cash"
	_bribe_card.hotkey = "1"
	_bribe_card.pressed.connect(func() -> void: press_bribe())
	row.add_child(_bribe_card)
	_elim_card = OptionCard.new()
	_elim_card.glyph = "hazard"
	_elim_card.tone = "danger"
	_elim_card.hotkey = "2"
	_elim_card.pressed.connect(func() -> void: press_elimination())
	row.add_child(_elim_card)
	return row


func _build_confirm() -> Control:
	_confirm_box = VBoxContainer.new()
	_confirm_label = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_box.add_child(_confirm_label)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_box.add_child(row)
	_back_button = PhoneOverlay.IconButton.new(tr("CAUGHTUI_BACK"), "back")
	_back_button.focus_mode = Control.FOCUS_ALL
	_back_button.pressed.connect(back_out)
	row.add_child(_back_button)
	_confirm_button = PhoneOverlay.IconButton.new("", "check", UITheme.V_DANGER)
	_confirm_button.focus_mode = Control.FOCUS_ALL
	_confirm_button.pressed.connect(func() -> void: confirm())
	row.add_child(_confirm_button)
	_confirm_box.visible = false
	return _confirm_box


func _build_result() -> Control:
	_result_panel = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 12, 18.0, 12.0)
	_result_label = PhoneOverlay.label("", UITheme.V_HEADING, true)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)
	_result_panel.visible = false
	return _result_panel


static func install(ui: UIRoot, caught_handler: CaughtHandler) -> Node:
	if ui == null or caught_handler == null:
		return null
	for child: Node in caught_handler.get_children():
		if child is Binder:
			return child
	var binder: Binder = Binder.new(ui, caught_handler)
	caught_handler.add_child(binder)
	return binder


# ─── Ciclo ─────────────────────────────────────────────────────────

func attach(p_handler: CaughtHandler, npc_id: String, options: Dictionary) -> void:
	handler = p_handler
	_npc_id = npc_id
	handler.decision_window_updated.connect(_on_updated)
	handler.decision_window_closed.connect(_on_closed)
	_apply_options(options)


func _ready() -> void:
	EventBus.npc_decided.connect(_on_npc_decided)
	EventBus.money_changed.connect(_on_money_changed)


func _process(delta: float) -> void:
	_clock += delta
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * PhoneOverlay.tune(B_PULSE_HZ))
	if _state == STATE_RESULT:
		_result_left -= delta
		if _result_left <= 0.0:
			set_process(false)
			closed.emit()
		return
	_seconds_left = maxf(_seconds_left - delta, 0.0)
	_dial.fraction = clampf(_seconds_left / maxf(_deadline, 0.001), 0.0, 1.0)
	_dial.seconds = ceili(_seconds_left)
	_dial.urgent = _seconds_left <= PhoneOverlay.tune(B_WARN_S)
	_dial.pulse = pulse if _dial.urgent else 0.0
	_dial.queue_redraw()
	for card: OptionCard in [_bribe_card, _elim_card]:
		card.pulse = pulse
		card.queue_redraw()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UITheme.color("ink"), PhoneOverlay.tune(B_DIM)))
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * PhoneOverlay.tune(B_PULSE_HZ))
	var red: Color = UITheme.color("danger")
	var band: float = minf(size.x, size.y) * VIGNETTE_FRACTION
	var outer: Color = Color(red, 0.3 + 0.2 * pulse)
	var colors: PackedColorArray = PackedColorArray([outer, outer, Color(red, 0.0), Color(red, 0.0)])
	var s: Vector2 = size
	var b: float = band
	var edges: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x - b, b), Vector2(b, b)]),
		PackedVector2Array([Vector2(0, s.y), s, Vector2(s.x - b, s.y - b), Vector2(b, s.y - b)]),
		PackedVector2Array([Vector2.ZERO, Vector2(0, s.y), Vector2(b, s.y - b), Vector2(b, b)]),
		PackedVector2Array([Vector2(s.x, 0), s, Vector2(s.x - b, s.y - b), Vector2(s.x - b, b)]),
	]
	for edge: PackedVector2Array in edges:
		draw_polygon(edge, colors)


## Esc no cierra la flagrancia: solo el CaughtHandler la resuelve (elección o inacción).
func request_close() -> void:
	pass


# ─── Opciones ──────────────────────────────────────────────────────

func get_options() -> Dictionary:
	return _options.duplicate(true)


func get_state() -> String:
	return _state


func get_armed() -> String:
	return _armed


func get_outcome() -> String:
	return _outcome


func get_reaction() -> Dictionary:
	return _reaction.duplicate(true)


func get_seconds_left() -> float:
	return _seconds_left


func is_bribe_enabled() -> bool:
	return bool((_current_options().get(OPTION_BRIBE, {}) as Dictionary).get("enabled", false))


## Lee siempre las opciones vivas del handler: con testigos la eliminación está vetada.
func is_elimination_enabled() -> bool:
	var live: Dictionary = _current_options()
	var eliminate: Dictionary = live.get(OPTION_ELIMINATE, {})
	return bool(eliminate.get("enabled", false)) and int(live.get("witnesses", 0)) == 0


## La tarjeta de una opción (OPTION_BRIBE / OPTION_ELIMINATE).
func get_option_card(option: String) -> Button:
	return _bribe_card if option == OPTION_BRIBE else _elim_card


func is_elimination_clickable() -> bool:
	return not _elim_card.disabled and _elim_card.mouse_filter != Control.MOUSE_FILTER_IGNORE


## Primer paso de OFRECER DINERO (arma la confirmación).
func press_bribe() -> bool:
	if _state == STATE_RESULT or not is_bribe_enabled():
		return false
	_arm(OPTION_BRIBE)
	return true


## Primer paso de SILENCIARLO PARA SIEMPRE: imposible con testigos.
func press_elimination() -> bool:
	if _state == STATE_RESULT or not is_elimination_enabled():
		return false
	_arm(OPTION_ELIMINATE)
	return true


func back_out() -> void:
	if _state == STATE_CONFIRM:
		_armed = ""
		_state = STATE_DECIDING
		_refresh_state()


## Segundo paso: ejecuta lo armado a través del CaughtHandler (que vuelve a validar).
func confirm() -> Dictionary:
	if _state != STATE_CONFIRM or handler == null:
		return {}
	var option: String = _armed
	back_out()
	if option == OPTION_BRIBE and is_bribe_enabled():
		var result: Dictionary = handler.choose_bribe(-1, bribe_ctx)
		if str(result.get("outcome", "")) != Bribery.OUTCOME_COUNTEROFFER:
			_outcome_text_from(result)
		return result
	if option == OPTION_ELIMINATE and is_elimination_enabled():
		return handler.choose_elimination()
	return {}


func _arm(option: String) -> void:
	_armed = option
	_state = STATE_CONFIRM
	var price: String = UITheme.format_money(int((_options.get(OPTION_BRIBE, {}) as Dictionary).get("price", 0)))
	var who: String = str(_options.get("npc_name", ""))
	_confirm_label.text = UITheme.trf("CAUGHTUI_CONFIRM_BRIBE", [price, who]) if option == OPTION_BRIBE \
			else UITheme.trf("CAUGHTUI_CONFIRM_ELIMINATE", [who])
	_confirm_button.set_label(tr("CAUGHTUI_CONFIRM_PAY") if option == OPTION_BRIBE
			else tr("CAUGHTUI_CONFIRM_KILL"))
	_refresh_state()
	_back_button.grab_focus.call_deferred()


func _current_options() -> Dictionary:
	if handler != null and handler.is_window_open():
		var live: Dictionary = handler.get_options()
		if str(live.get("npc_id", "")) == _npc_id:
			return live
	return _options


# ─── Presentación ──────────────────────────────────────────────────

func _apply_options(options: Dictionary) -> void:
	_options = options.duplicate(true)
	_seconds_left = float(options.get("seconds_left", 0.0))
	_deadline = maxf(float(options.get("deadline", _seconds_left)), 0.001)
	var npc: NPCRuntime = NPCDirector.get_npc(_npc_id)
	if npc == null and handler != null and handler.npc_resolver.is_valid():
		npc = handler.npc_resolver.call(_npc_id) as NPCRuntime
	var who: String = str(options.get("npc_name", PhoneOverlay.npc_name(_npc_id)))
	_photo.set_npc(npc)
	_name_label.text = who
	_job_label.text = PhoneOverlay.job_text(npc)
	var crime: String = _translated_or(CRIME_KEY % str(options.get("crime_type", "")).to_upper(), CRIME_GENERIC)
	_subtitle.text = UITheme.trf("CAUGHTUI_SUBTITLE", [who, crime])
	_inaction_label.text = UITheme.trf("CAUGHTUI_INACTION", [who])
	_apply_bribe_card(options.get(OPTION_BRIBE, {}))
	_apply_elim_card(options)
	if _armed == OPTION_ELIMINATE and not is_elimination_enabled():
		back_out()
	_refresh_state()


func _apply_bribe_card(bribe: Dictionary) -> void:
	var enabled: bool = bool(bribe.get("enabled", false))
	var countered: bool = bool(bribe.get("counteroffer", false))
	var price: String = UITheme.format_money(int(bribe.get("price", 0)))
	_bribe_card.tone = "warn" if countered else "hazard"
	var detail: String = UITheme.trf(str(bribe.get("label_key", "UI_CAUGHT_BRIBE")), [price])
	if countered:
		detail += "\n" + tr("CAUGHTUI_COUNTER_HINT")
	elif enabled:
		detail += "\n" + tr("CAUGHTUI_BRIBE_HINT")
	if not enabled:
		detail = tr(str(bribe.get("disabled_reason_key", "UI_CAUGHT_BRIBE_NO_FUNDS"))) + "\n" \
				+ UITheme.trf("CAUGHTUI_PRICE", [price])
	_bribe_card.set_texts(tr("CAUGHTUI_OFFER_MONEY").to_upper(), detail)
	_set_card_enabled(_bribe_card, enabled)


func _apply_elim_card(options: Dictionary) -> void:
	var eliminate: Dictionary = options.get(OPTION_ELIMINATE, {})
	var witnesses: int = int(options.get("witnesses", 0))
	var enabled: bool = bool(eliminate.get("enabled", false)) and witnesses == 0
	_elim_card.flagged_red = bool(eliminate.get("flagged_red", false)) or witnesses > 0
	_elim_card.set_texts(tr("CAUGHTUI_ELIMINATE").to_upper(), tr("CAUGHTUI_ELIMINATE_HINT") if enabled
			else tr(str(eliminate.get("disabled_reason_key", "UI_CAUGHT_ELIMINATE_WITNESSES"))))
	_set_card_enabled(_elim_card, enabled)
	_witness_label.visible = witnesses > 0
	_witness_label.text = UITheme.trf("CAUGHTUI_WITNESSES", [witnesses])
	_witness_label.add_theme_color_override("font_color", UITheme.color("danger").lightened(0.2))


## Deshabilitada = no pulsable de ninguna forma (ni ratón, ni foco, ni tecla).
func _set_card_enabled(card: OptionCard, enabled: bool) -> void:
	card.disabled = not enabled
	card.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_FORBIDDEN
	card.queue_redraw()


func _refresh_state() -> void:
	_bribe_card.armed = _armed == OPTION_BRIBE
	_elim_card.armed = _armed == OPTION_ELIMINATE
	_confirm_box.visible = _state == STATE_CONFIRM
	_result_panel.visible = _state == STATE_RESULT
	for card: OptionCard in [_bribe_card, _elim_card]:
		card.queue_redraw()


## Oferta rechazada sin efectos (fondos, precio): se avisa y la ventana sigue abierta.
func _outcome_text_from(result: Dictionary) -> void:
	var key: String = str(result.get("text_key", ""))
	_notice.visible = not key.is_empty() and not bool(result.get("ok", true))
	_notice.text = tr(key) if _notice.visible else ""


func _show_result(text: String, tone: String) -> void:
	_state = STATE_RESULT
	_armed = ""
	var col: Color = UITheme.color(tone)
	_result_panel.add_theme_stylebox_override("panel", PhoneOverlay.box(Color(col.darkened(0.7), 0.95), col,
			12, 18.0, 12.0, 3))
	_result_label.text = text
	_set_card_enabled(_bribe_card, false)
	_set_card_enabled(_elim_card, false)
	_result_left = PhoneOverlay.tune(B_RESULT_S)
	_refresh_state()


# ─── Señales ───────────────────────────────────────────────────────

func _on_updated(npc_id: String, options: Dictionary) -> void:
	if npc_id == _npc_id and _state != STATE_RESULT:
		_apply_options(options)


func _on_closed(npc_id: String, outcome: String) -> void:
	if npc_id != _npc_id or _state == STATE_RESULT:
		return
	_outcome = outcome
	if outcome == CaughtHandler.OUTCOME_GAME_OVER:
		closed.emit()
		return
	var who: String = str(_options.get("npc_name", ""))
	var text: String = UITheme.trf(OUTCOME_KEY % outcome.to_upper(), [who])
	var tone: String = str(OUTCOME_TONES.get(outcome, "warn"))
	if Bribery.OUTCOME_TEXT_KEYS.has(outcome):
		text = tr(str(Bribery.OUTCOME_TEXT_KEYS[outcome]))
	if REACTING_OUTCOMES.has(outcome) and not _reaction.is_empty():
		var key: String = REACTION_KEY % str(_reaction.get("reaction", "")).to_upper()
		var reaction: String = _translated_or(key, OUTCOME_KEY % CaughtHandler.OUTCOME_INACTION.to_upper()) % who
		text = reaction if outcome == CaughtHandler.OUTCOME_INACTION else text + "\n" + reaction
		tone = "danger" if bool(_reaction.get("reported", false)) else tone
	_show_result(text, tone)


## Texto de la clave o, si no existe en strings.csv, el de la clave de reserva.
func _translated_or(key: String, fallback: String) -> String:
	var text: String = tr(key)
	return tr(fallback) if text == key else text


func _on_npc_decided(npc_id: String, _action: String, context: Dictionary) -> void:
	if npc_id == _npc_id and context.has("reaction"):
		_reaction = context.duplicate(true)


func _on_money_changed(_old_value: int, _new_value: int, _reason: String) -> void:
	if _state != STATE_RESULT:
		_apply_options(_current_options())


## Tecla de opción: la primera pulsación arma; la misma tecla otra vez confirma (dos gestos, §13.7).
func _hotkey(option: String) -> void:
	if _state == STATE_CONFIRM and _armed == option:
		confirm()
	elif option == OPTION_BRIBE:
		press_bribe()
	else:
		press_elimination()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var handled: bool = true
	match key.physical_keycode:
		KEY_1:
			_hotkey(OPTION_BRIBE)
		KEY_2:
			_hotkey(OPTION_ELIMINATE)
		KEY_BACKSPACE:
			back_out()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
