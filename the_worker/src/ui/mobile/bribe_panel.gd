# bribe_panel.gd — Interfaz de soborno del móvil (§13.5, §8.2): contacto → favor → cantidad con deslizador; precio estimado solo con expediente N5.
# PROPIETARIO DE: la oferta que se está preparando (favor, cantidad, confirmación armada, resultado mostrado); las fichas de contraoferta en pie las guarda PhoneOverlay.Service (por personaje y favor).
# ESCUCHA: nada (PhoneOverlay le avisa de money_changed y de la exposición).
class_name BribePanel
extends PanelContainer

## Flujo: setup_for(npc_id, canal) → select_favour()/step_favour() → set_amount() → request_offer()
## (arma la confirmación, §13.7: nada irreversible con una pulsación) → confirm_offer(), que llama a
## Bribery.offer(npc, cantidad, favor, canal, ctx). ctx = ctx_provider.call(canal) (PhoneOverlay:
## sala y, en llamada, oyentes) + la ficha de contraoferta en pie de ese favor + wallet (pruebas).
## Precio estimado (Bribery.estimated_price) visible solo si PlayerState.get_personnel_file_level() >=
## movil.nivel_expediente_precio_estimado; por debajo, el jugador opera a ciegas (sin cifra ni marca).
## Cantidad: la fija el panel (entero exacto); el deslizador la muestra y, al arrastrarlo, va en pasos
## de movil.soborno_paso entre ese paso y el capital. «Ofrecer lo que piden» (contraoferta) solo se
## puede pulsar si llega el dinero y siempre ofrece exactamente lo pedido.
## Maquetación: cabecera, favor y cantidad fijos; líneas de precio/riesgo, confirmación y resultado en
## un cuerpo desplazable; botones abajo, siempre visibles. set_compact(true) aprieta todo (móvil).

signal offer_resolved(result: Dictionary)
signal close_requested

const STATE_EDIT := "edit"
const STATE_CONFIRM := "confirm"
const STATE_RESULT := "result"
const B_STEP := "movil.soborno_paso"
const B_START := "movil.soborno_fraccion_inicial"
const B_FILE_LEVEL := "movil.nivel_expediente_precio_estimado"
const SLIDER_CURVE := 2.0
const PORTRAIT_EMS := 2.0
const PORTRAIT_EMS_COMPACT := 1.5
const SLIDER_EMS := 2.2
const SLIDER_EMS_COMPACT := 1.7
const OUTCOME_TONES: Dictionary = {
	Bribery.OUTCOME_ACCEPTED: "gain", Bribery.OUTCOME_COUNTEROFFER: "warn",
	Bribery.OUTCOME_DENOUNCED: "danger", Bribery.OUTCOME_SILENCE: "warn",
	Bribery.OUTCOME_NEUTRAL: "loss",
}
const OUTCOME_GLYPHS: Dictionary = {
	Bribery.OUTCOME_ACCEPTED: "check", Bribery.OUTCOME_COUNTEROFFER: "coin",
	Bribery.OUTCOME_DENOUNCED: "hazard", Bribery.OUTCOME_SILENCE: "eye",
}


## Deslizador de cantidad dibujado por código: pista, relleno, pomo y, encima, la marca del precio
## estimado (visible aunque el pomo esté justo en ella). Sin paso propio: el arrastre redondea a `snap`.
class AmountSlider extends Range:
	var estimate: int = -1
	var accent: Color = Color.WHITE
	var snap: float = 1.0
	var locked: bool = false
	var ems: float = BribePanel.SLIDER_EMS
	var _dragging: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		step = 0.0
		value_changed.connect(func(_v: float) -> void: queue_redraw())
		changed.connect(queue_redraw)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			set_ems(ems)

	func set_ems(p_ems: float) -> void:
		ems = p_ems
		custom_minimum_size.y = PhoneOverlay.base_size(self) * ems
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if locked:
			return
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null and button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed and editable()
			if _dragging:
				_set_from(button.position.x)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from((event as InputEventMouseMotion).position.x)
			accept_event()

	func editable() -> bool:
		return max_value > min_value and not locked

	func _knob_radius() -> float:
		return size.y * 0.27

	## Escala cuadrática: más precisión en las cantidades bajas aunque el capital sea grande.
	func _x_for(amount: float) -> float:
		var pad: float = _knob_radius() + 2.0
		var span: float = maxf(max_value - min_value, 1.0)
		var t: float = pow(clampf((amount - min_value) / span, 0.0, 1.0), 1.0 / BribePanel.SLIDER_CURVE)
		return pad + (size.x - pad * 2.0) * t

	func _set_from(x: float) -> void:
		var pad: float = _knob_radius() + 2.0
		var t: float = clampf((x - pad) / maxf(size.x - pad * 2.0, 1.0), 0.0, 1.0)
		var raw: float = min_value + pow(t, BribePanel.SLIDER_CURVE) * (max_value - min_value)
		value = minf(min_value + snappedf(raw - min_value, maxf(snap, 1.0)), max_value)

	func _draw() -> void:
		var mid: float = size.y * 0.64
		var track_h: float = size.y * 0.18
		var left: float = _x_for(min_value)
		var right: float = _x_for(max_value)
		var knob: float = _x_for(value)
		var fill: Color = accent if max_value > min_value else UITheme.color("faint")
		var track: Rect2 = Rect2(left, mid - track_h * 0.5, right - left, track_h)
		PhoneOverlay.fill_round(self, track.grow(2.0), track_h, CharacterStyle.OUTLINE)
		PhoneOverlay.fill_round(self, track, track_h * 0.5, UITheme.color("slot"))
		PhoneOverlay.fill_round(self, Rect2(track.position, Vector2(knob - left, track_h)), track_h * 0.5, fill)
		var radius: float = _knob_radius()
		draw_circle(Vector2(knob, mid), radius + 2.5, CharacterStyle.OUTLINE)
		draw_circle(Vector2(knob, mid), radius, UITheme.color("paper"))
		draw_circle(Vector2(knob, mid), radius * 0.42, fill)
		if estimate >= 0:
			_draw_estimate(mid - radius - 3.0, float(estimate) > max_value)

	## Triángulo hacia abajo por encima del pomo, apuntando a la cantidad estimada.
	func _draw_estimate(tip_y: float, beyond: bool) -> void:
		var x: float = _x_for(minf(float(estimate), max_value))
		var col: Color = UITheme.color("loss" if beyond else "hazard")
		var s: float = maxf(tip_y * 0.55, 3.0)
		var tip: Vector2 = Vector2(x, tip_y)
		var pts: PackedVector2Array = PackedVector2Array([tip, tip + Vector2(-s, -s * 1.2), tip + Vector2(s, -s * 1.2)])
		draw_colored_polygon(pts, col)
		pts.append(tip)
		draw_polyline(pts, CharacterStyle.OUTLINE, 1.5, true)


var npc_resolver: Callable = Callable()
var wallet: Bribery.Wallet = null
var ctx_provider: Callable = Callable()
## Almacén de fichas de contraoferta (PhoneOverlay se lo pasa); sin él, un diccionario propio.
var service: PhoneOverlay.Service = null
var _npc_id: String = ""
var _channel: String = Bribery.CHANNEL_MOBILE_CHAT
var _favours: Array[Dictionary] = []
var _favour_index: int = 0
var _amount: int = 0
var _state: String = STATE_EDIT
var _counter: Dictionary = {}
var _local_counters: Dictionary = {}
var _last: Dictionary = {}
var _exposure: Dictionary = {}
var _compact: bool = false
var _syncing: bool = false
var _portrait: PhoneOverlay.Portrait
var _title: Label
var _title_glyph: PhoneOverlay.Glyph
var _channel_row: HBoxContainer
var _channel_glyph: PhoneOverlay.Glyph
var _channel_label: Label
var _favour_caption: Label
var _amount_caption: Label
var _favour_label: Label
var _favour_count: Label
var _stepper: Array[PhoneOverlay.IconButton] = []
var _amount_label: Label
var _funds_label: Label
var _slider_row: HBoxContainer
var _slider: AmountSlider
var _scroll: ScrollContainer
var _estimate_row: HBoxContainer
var _estimate_glyph: PhoneOverlay.Glyph
var _estimate_label: Label
var _risk_row: HBoxContainer
var _risk_glyph: PhoneOverlay.Glyph
var _risk_label: Label
var _confirm_label: Label
var _result_card: PanelContainer
var _result_glyph: PhoneOverlay.Glyph
var _result_label: Label
var _counter_note: Label
var _send_button: PhoneOverlay.IconButton
var _confirm_row: HBoxContainer
var _result_row: HBoxContainer
var _counter_button: PhoneOverlay.IconButton


func _init() -> void:
	name = "BribePanel"
	add_theme_stylebox_override("panel", PhoneOverlay.fill_box(UITheme.color("ink")))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	column.add_child(_build_header())
	_favour_caption = _caption("PHONE_BRIBE_FAVOUR_CAPTION")
	column.add_child(_favour_caption)
	column.add_child(_build_favour_stepper())
	_amount_caption = _caption("PHONE_BRIBE_AMOUNT_CAPTION")
	column.add_child(_amount_caption)
	column.add_child(_build_amount())
	var parts: Dictionary = PhoneOverlay.scroll_list()
	_scroll = parts["scroll"]
	var body: VBoxContainer = parts["list"]
	body.add_theme_constant_override("separation", 6)
	column.add_child(_scroll)
	_estimate_row = _build_info_line(true)
	body.add_child(_estimate_row)
	_risk_row = _build_info_line(false)
	body.add_child(_risk_row)
	_confirm_label = PhoneOverlay.label("", UITheme.V_SMALL, true)
	body.add_child(_confirm_label)
	body.add_child(_build_result())
	column.add_child(_build_actions())


func _build_header() -> Control:
	var head: HBoxContainer = HBoxContainer.new()
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "back", UITheme.V_FLAT)
	back.tooltip_text = tr("PHONE_BACK")
	back.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(back)
	_portrait = PhoneOverlay.Portrait.new(PORTRAIT_EMS)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_portrait)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(text)
	var title_row: HBoxContainer = HBoxContainer.new()
	text.add_child(title_row)
	_title_glyph = PhoneOverlay.Glyph.new("talk", "muted", 0.8)
	_title_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title_glyph.visible = false
	title_row.add_child(_title_glyph)
	_title = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_channel_row = HBoxContainer.new()
	text.add_child(_channel_row)
	_channel_glyph = PhoneOverlay.Glyph.new("talk", "muted", 0.75)
	_channel_row.add_child(_channel_glyph)
	_channel_label = PhoneOverlay.label("", UITheme.V_CAPTION)
	_channel_row.add_child(_channel_label)
	return head


func _caption(key: String) -> Label:
	return PhoneOverlay.label(tr(key).to_upper(), UITheme.V_CAPTION)


func _build_favour_stepper() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var prev: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "back")
	prev.tooltip_text = tr("PHONE_BACK")
	prev.pressed.connect(step_favour.bind(-1))
	row.add_child(prev)
	var card: PanelContainer = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 8, 10.0, 4.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(text)
	_favour_label = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_favour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_favour_label)
	_favour_count = PhoneOverlay.label("", UITheme.V_CAPTION)
	_favour_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_favour_count)
	var next: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "forward")
	next.pressed.connect(step_favour.bind(1))
	row.add_child(next)
	_stepper = [prev, next]
	return row


func _build_amount() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var line: HBoxContainer = HBoxContainer.new()
	column.add_child(line)
	_amount_label = PhoneOverlay.label("", UITheme.V_NUMBER)
	_amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_amount_label)
	_funds_label = PhoneOverlay.label("", UITheme.V_SMALL)
	_funds_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_funds_label)
	_slider_row = HBoxContainer.new()
	column.add_child(_slider_row)
	var minus: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("−", "", UITheme.V_FLAT)
	minus.pressed.connect(func() -> void: nudge(-1))
	_slider_row.add_child(minus)
	_slider = AmountSlider.new()
	_slider.value_changed.connect(_on_slider_moved)
	_slider_row.add_child(_slider)
	var plus: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("+", "", UITheme.V_FLAT)
	plus.pressed.connect(func() -> void: nudge(1))
	_slider_row.add_child(plus)
	return column


func _build_info_line(estimate: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var glyph: PhoneOverlay.Glyph = PhoneOverlay.Glyph.new("lock", "muted", 0.9)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(glyph)
	var text: Label = PhoneOverlay.label("", UITheme.V_SMALL, true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if estimate:
		_estimate_glyph = glyph
		_estimate_label = text
	else:
		_risk_glyph = glyph
		_risk_label = text
	return row


func _build_result() -> Control:
	_result_card = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 10, 12.0, 9.0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_result_card.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_result_glyph = PhoneOverlay.Glyph.new("info", "paper", 1.2)
	_result_glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_result_glyph)
	_result_label = PhoneOverlay.label("", "", true)
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_result_label)
	_counter_note = PhoneOverlay.label("", UITheme.V_SMALL, true)
	column.add_child(_counter_note)
	return _result_card


func _build_actions() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	_send_button = PhoneOverlay.IconButton.new("", "coin", UITheme.V_PRIMARY)
	_send_button.pressed.connect(func() -> void: request_offer())
	column.add_child(_send_button)
	_confirm_row = HBoxContainer.new()
	column.add_child(_confirm_row)
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BACK"), "back")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(cancel_confirm)
	_confirm_row.add_child(back)
	var confirm: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BRIBE_CONFIRM"), "check",
			UITheme.V_DANGER)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void: confirm_offer())
	_confirm_row.add_child(confirm)
	_result_row = HBoxContainer.new()
	column.add_child(_result_row)
	_counter_button = PhoneOverlay.IconButton.new("", "coin", UITheme.V_PRIMARY)
	_counter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter_button.pressed.connect(accept_counteroffer)
	_result_row.add_child(_counter_button)
	var done: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BRIBE_DONE"), "")
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func() -> void: close_requested.emit())
	_result_row.add_child(done)
	return column


# ─── API ───────────────────────────────────────────────────────────

## Abre la negociación; si hay una contraoferta en pie con este personaje, arranca en ese favor.
func setup_for(npc_id: String, channel: String) -> void:
	_npc_id = npc_id
	_channel = channel
	_last = {}
	_favours = Database.get_all_bribe_favours()
	_favour_index = 0
	var standing: String = service.counter_favour(npc_id) if service != null else ""
	for i: int in _favours.size():
		if str(_favours[i]["id"]) == standing:
			_favour_index = i
	_counter = _stored_counter(get_favour())
	_portrait.set_npc(_npc())
	_title.text = UITheme.trf("PHONE_BRIBE_TITLE", [PhoneOverlay.npc_name(npc_id)])
	var call: bool = channel == Bribery.CHANNEL_PHONE_CALL
	_channel_glyph.set_glyph("phone" if call else "talk")
	_title_glyph.set_glyph("phone" if call else "talk")
	_channel_label.text = tr("PHONE_BRIBE_VIA_CALL" if call else "PHONE_BRIBE_VIA_CHAT").to_upper()
	_slider.accent = PhoneOverlay.accent_color()
	refresh_funds()
	_reset_amount()
	_set_state(STATE_EDIT)


func set_compact(on: bool) -> void:
	_compact = on
	_portrait.set_ems(PORTRAIT_EMS_COMPACT if on else PORTRAIT_EMS)
	PhoneOverlay.set_single_line(_title, on)
	_title_glyph.visible = on
	_channel_row.visible = not on
	_favour_caption.visible = not on
	_amount_caption.visible = not on
	_favour_count.visible = not on
	_slider.set_ems(SLIDER_EMS_COMPACT if on else SLIDER_EMS)
	if not _npc_id.is_empty():
		_refresh()


func is_compact() -> bool:
	return _compact


func get_npc_id() -> String:
	return _npc_id


func get_channel() -> String:
	return _channel


func get_favour() -> String:
	return str(_favours[_favour_index]["id"]) if _favour_index < _favours.size() else ""


func select_favour(favour_id: String) -> bool:
	if _state != STATE_EDIT:
		return false
	for i: int in _favours.size():
		if str(_favours[i]["id"]) == favour_id:
			_favour_index = i
			_on_favour_changed()
			return true
	return false


func step_favour(delta: int) -> void:
	if _favours.is_empty() or _state != STATE_EDIT:
		return
	_favour_index = posmod(_favour_index + delta, _favours.size())
	_on_favour_changed()


func get_amount() -> int:
	return _amount if _money() >= _step() else 0


## Fija la cantidad exacta (entre el paso y el capital); el deslizador solo la muestra.
func set_amount(amount: int) -> void:
	_amount = clampi(amount, _step(), maxi(_money(), _step()))
	_slider.set_value_no_signal(_amount)
	_slider.queue_redraw()
	_refresh_amount()


func nudge(steps: int) -> void:
	if _state == STATE_EDIT:
		set_amount(get_amount() + steps * _step())


## Con expediente N5 o superior se muestra el precio estimado (§13.4, §13.5).
static func estimate_visible() -> bool:
	return PlayerState.get_personnel_file_level() >= PhoneOverlay.tune_i(B_FILE_LEVEL)


func shows_estimate() -> bool:
	return estimate_visible()


## Precio estimado del favor elegido; -1 si el jugador opera a ciegas.
func get_estimate() -> int:
	var npc: NPCRuntime = _npc()
	if not shows_estimate() or npc == null or get_favour().is_empty():
		return -1
	return Bribery.estimated_price(npc, get_favour())


## Texto de la línea del precio (estimación N5, «a ciegas» o precio pedido).
func get_estimate_text() -> String:
	return _estimate_label.text


func get_state() -> String:
	return _state


func is_confirm_armed() -> bool:
	return _state == STATE_CONFIRM


func get_last_result() -> Dictionary:
	return _last.duplicate(true)


func get_counteroffer() -> Dictionary:
	return _counter.duplicate()


## Lo que pide la contraoferta en pie del favor elegido (0 si no hay).
func asked_price() -> int:
	return int(_counter.get(Bribery.TOKEN_ASKED, 0)) if not _counter.is_empty() else 0


## «Ofrecer lo que piden» solo si hay contraoferta y el capital llega a lo pedido.
func can_pay_asked() -> bool:
	var asked: int = asked_price()
	return asked > 0 and asked <= _money()


func can_offer() -> bool:
	var npc: NPCRuntime = _npc()
	var amount: int = get_amount()
	return npc != null and PhoneContactsTab.will_answer(npc) and amount >= _step() and amount <= _money() \
			and not get_favour().is_empty()


## Primer paso (arma la confirmación). Devuelve si quedó armada.
func request_offer() -> bool:
	if _state != STATE_EDIT or not can_offer():
		return false
	_set_state(STATE_CONFIRM)
	return true


func cancel_confirm() -> void:
	if _state == STATE_CONFIRM:
		_set_state(STATE_EDIT)


## Segundo paso: ejecuta la oferta armada. {} si no había confirmación armada.
func confirm_offer() -> Dictionary:
	if _state != STATE_CONFIRM:
		return {}
	var ctx: Dictionary = {}
	if ctx_provider.is_valid():
		ctx = ctx_provider.call(_channel)
	if not _counter.is_empty():
		ctx[Bribery.CTX_COUNTEROFFER] = _counter
	if wallet != null:
		ctx["wallet"] = wallet
	var favour: String = get_favour()
	var result: Dictionary = Bribery.offer(_npc(), get_amount(), favour, _channel, ctx)
	_last = result
	if bool(result.get("ok", false)):
		var countered: bool = str(result.get("outcome", "")) == Bribery.OUTCOME_COUNTEROFFER
		_counter = (result.get("counteroffer", {}) as Dictionary).duplicate() if countered else {}
		_store_counter(favour, _counter)
	_set_state(STATE_RESULT)
	_show_result(result)
	offer_resolved.emit(result)
	return result


## Contraoferta: pone exactamente la cantidad pedida y arma la confirmación (sigue haciendo falta
## confirmar). false si no hay contraoferta o no llega el dinero: nunca ofrece menos de lo pedido.
func accept_counteroffer() -> bool:
	if not can_pay_asked():
		return false
	var asked: int = asked_price()
	_set_state(STATE_EDIT)
	set_amount(asked)
	if get_amount() != asked:
		return false
	return request_offer()


func refresh_funds() -> void:
	var money: int = _money()
	_syncing = true
	_slider.snap = _step()
	_slider.min_value = _step()
	_slider.max_value = maxi(money, _step())
	_syncing = false
	_funds_label.text = UITheme.trf("PHONE_BRIBE_FUNDS", [UITheme.format_money(money)])
	if _amount > 0:
		set_amount(_amount)
	if _state == STATE_RESULT:
		_refresh_counter_offer()


func set_exposure(exposure: Dictionary) -> void:
	_exposure = exposure
	if _channel == Bribery.CHANNEL_PHONE_CALL:
		_refresh_risk()


# ─── Interno ───────────────────────────────────────────────────────

func _npc() -> NPCRuntime:
	var npc: NPCRuntime = null
	if npc_resolver.is_valid():
		npc = npc_resolver.call(_npc_id) as NPCRuntime
	return npc if npc != null else NPCDirector.get_npc(_npc_id)


func _money() -> int:
	if wallet != null and wallet.has_method("get_money"):
		return int(wallet.call("get_money"))
	return PlayerState.get_money()


func _step() -> int:
	return maxi(PhoneOverlay.tune_i(B_STEP), 1)


func _stored_counter(favour_id: String) -> Dictionary:
	if service != null:
		return service.get_counter(_npc_id, favour_id)
	return (_local_counters.get(_npc_id + "|" + favour_id, {}) as Dictionary).duplicate()


func _store_counter(favour_id: String, token: Dictionary) -> void:
	if service != null:
		service.set_counter(_npc_id, favour_id, token)
	elif token.is_empty():
		_local_counters.erase(_npc_id + "|" + favour_id)
	else:
		_local_counters[_npc_id + "|" + favour_id] = token.duplicate()


## Arranque: lo pedido si hay contraoferta asumible, el estimado con N5 o una fracción del capital.
func _reset_amount() -> void:
	var step: int = _step()
	var start: int = get_estimate()
	if can_pay_asked():
		start = asked_price()
	elif start <= 0:
		start = roundi(_money() * PhoneOverlay.tune(B_START))
		start -= start % step
	set_amount(start)


func _on_slider_moved(value: float) -> void:
	if _syncing:
		return
	_amount = roundi(value)
	_refresh_amount()


func _on_favour_changed() -> void:
	_counter = _stored_counter(get_favour())
	if shows_estimate() or not _counter.is_empty():
		_reset_amount()
	_refresh()


func _set_state(state: String) -> void:
	_state = state
	var edit: bool = state == STATE_EDIT
	_slider_row.visible = edit
	_slider.locked = not edit
	_estimate_row.visible = edit
	_risk_row.visible = state != STATE_RESULT
	_confirm_label.visible = state == STATE_CONFIRM
	_result_card.visible = state == STATE_RESULT
	_send_button.visible = edit
	_confirm_row.visible = state == STATE_CONFIRM
	_result_row.visible = state == STATE_RESULT
	for button: PhoneOverlay.IconButton in _stepper:
		button.disabled = not edit
	_refresh()
	_scroll.scroll_vertical = 0


func _refresh() -> void:
	var favour: Dictionary = _favours[_favour_index] if _favour_index < _favours.size() else {}
	_favour_label.text = tr(str(favour.get("name_key", "")))
	_favour_count.text = "%d / %d" % [_favour_index + 1, _favours.size()]
	_refresh_estimate()
	_refresh_risk()
	_refresh_amount()


func _refresh_amount() -> void:
	if _amount_label == null:
		return
	var text: String = UITheme.format_money(get_amount())
	_amount_label.text = text
	_send_button.set_label(UITheme.trf("PHONE_BRIBE_SEND", [text]))
	_send_button.disabled = not can_offer()
	_confirm_label.text = UITheme.trf("PHONE_BRIBE_CONFIRM_BODY", [text, PhoneOverlay.npc_name(_npc_id),
			_favour_label.text])


func _refresh_estimate() -> void:
	var estimate: int = get_estimate()
	_slider.estimate = estimate
	_slider.queue_redraw()
	var tone: String = "hazard" if estimate >= 0 else "muted"
	_estimate_glyph.set_glyph("document" if estimate >= 0 else "lock", UITheme.color(tone))
	if estimate >= 0:
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_ESTIMATE", [UITheme.format_money(estimate)])
	else:
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_BLIND_SHORT" if _compact else "PHONE_BRIBE_BLIND",
				[PhoneOverlay.tune_i(B_FILE_LEVEL)])
	if not _counter.is_empty():
		tone = "warn"
		_estimate_glyph.set_glyph("coin", UITheme.color(tone))
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_ASKED", [UITheme.format_money(asked_price())])
	_estimate_label.add_theme_color_override("font_color", UITheme.color(tone))


func _refresh_risk() -> void:
	if _risk_label == null:
		return
	if _channel == Bribery.CHANNEL_MOBILE_CHAT:
		_risk_glyph.set_glyph("server", UITheme.color("warn"))
		_risk_label.text = tr("PHONE_BRIBE_RISK_CHAT")
		_risk_label.add_theme_color_override("font_color", UITheme.color("warn"))
		return
	var listeners: Array = _exposure.get(PhoneOverlay.EXPO_LISTENERS, [])
	var tone: String = "gain" if listeners.is_empty() else "danger"
	_risk_glyph.set_glyph("lock" if listeners.is_empty() else "ear", UITheme.color(tone))
	_risk_label.text = tr("PHONE_PRIVACY_NOBODY") if listeners.is_empty() \
			else UITheme.trf("PHONE_PRIVACY_LISTENERS", [listeners.size()])
	_risk_label.add_theme_color_override("font_color", UITheme.color(tone))


func _show_result(result: Dictionary) -> void:
	var outcome: String = str(result.get("outcome", ""))
	var col: Color = UITheme.color(str(OUTCOME_TONES.get(outcome, "loss")))
	_result_card.add_theme_stylebox_override("panel", PhoneOverlay.box(Color(col.darkened(0.7), 0.95), col,
			10, 12.0, 9.0, 2))
	_result_glyph.set_glyph(str(OUTCOME_GLYPHS.get(outcome, "cross")), col)
	var text: String = tr(str(result.get("text_key", "")))
	var insult: String = str(result.get("insult_text_key", ""))
	if not insult.is_empty() and insult != str(result.get("text_key", "")):
		text += "\n" + tr(insult)
	_result_label.text = text
	_refresh_counter_offer()


## Botón «Ofrecer lo que piden»: solo con contraoferta; deshabilitado (y explicado) sin fondos.
func _refresh_counter_offer() -> void:
	var asked: int = asked_price()
	_counter_button.visible = asked > 0
	_counter_note.visible = asked > 0
	if asked <= 0:
		return
	var price: String = UITheme.format_money(asked)
	_counter_button.set_label(UITheme.trf("PHONE_BRIBE_PAY_ASKED", [price]))
	_counter_button.disabled = not can_pay_asked()
	var short: bool = not can_pay_asked()
	_counter_note.text = UITheme.trf("PHONE_BRIBE_COUNTER_NO_FUNDS", [price, UITheme.format_money(_money())]) \
			if short else UITheme.trf("PHONE_BRIBE_ASKED", [price])
	_counter_note.add_theme_color_override("font_color", UITheme.color("loss" if short else "warn"))
