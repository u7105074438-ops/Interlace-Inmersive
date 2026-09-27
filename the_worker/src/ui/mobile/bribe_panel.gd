# bribe_panel.gd — Interfaz de soborno del móvil (§13.5, §8.2): contacto → favor → cantidad con deslizador; precio estimado solo con expediente N5.
# PROPIETARIO DE: la oferta que se está preparando (favor, cantidad, confirmación armada) y la ficha de contraoferta en pie de esta negociación (estado de vista).
# ESCUCHA: nada (PhoneOverlay le avisa de money_changed y de la exposición).
class_name BribePanel
extends PanelContainer

## Flujo: setup_for(npc_id, canal) → select_favour()/step_favour() → set_amount() → request_offer()
## (arma la confirmación, §13.7: nada irreversible con una pulsación) → confirm_offer(), que llama a
## Bribery.offer(npc, cantidad, favor, canal, ctx). ctx = ctx_provider.call(canal) (PhoneOverlay:
## sala y, en llamada, oyentes) + la ficha de contraoferta si el personaje pidió más + wallet (pruebas).
## Precio estimado (Bribery.estimated_price) visible solo si PlayerState.get_personnel_file_level() >=
## movil.nivel_expediente_precio_estimado; por debajo, el jugador opera a ciegas (sin cifra ni marca).
## El deslizador va de movil.soborno_paso al capital disponible, en pasos de movil.soborno_paso.

signal offer_resolved(result: Dictionary)
signal close_requested

const STATE_EDIT := "edit"
const STATE_CONFIRM := "confirm"
const STATE_RESULT := "result"
const B_STEP := "movil.soborno_paso"
const B_START := "movil.soborno_fraccion_inicial"
const B_FILE_LEVEL := "movil.nivel_expediente_precio_estimado"
const SLIDER_CURVE := 2.0
const OUTCOME_TONES: Dictionary = {
	Bribery.OUTCOME_ACCEPTED: "gain", Bribery.OUTCOME_COUNTEROFFER: "warn",
	Bribery.OUTCOME_DENOUNCED: "danger", Bribery.OUTCOME_SILENCE: "warn",
	Bribery.OUTCOME_NEUTRAL: "loss",
}
const OUTCOME_GLYPHS: Dictionary = {
	Bribery.OUTCOME_ACCEPTED: "check", Bribery.OUTCOME_COUNTEROFFER: "coin",
	Bribery.OUTCOME_DENOUNCED: "hazard", Bribery.OUTCOME_SILENCE: "eye",
}


## Deslizador de cantidad dibujado por código: pista, relleno, marca del precio estimado y pomo.
class AmountSlider extends Range:
	var estimate: int = -1
	var accent: Color = Color.WHITE
	var _dragging: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		value_changed.connect(func(_v: float) -> void: queue_redraw())
		changed.connect(queue_redraw)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			custom_minimum_size.y = PhoneOverlay.base_size(self) * 2.0

	func _gui_input(event: InputEvent) -> void:
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
		return max_value > min_value

	func _knob_radius() -> float:
		return size.y * 0.3

	## Escala cuadrática: más precisión en las cantidades bajas aunque el capital sea grande.
	func _x_for(amount: float) -> float:
		var pad: float = _knob_radius() + 2.0
		var span: float = maxf(max_value - min_value, 1.0)
		var t: float = pow(clampf((amount - min_value) / span, 0.0, 1.0), 1.0 / BribePanel.SLIDER_CURVE)
		return pad + (size.x - pad * 2.0) * t

	func _set_from(x: float) -> void:
		var pad: float = _knob_radius() + 2.0
		var t: float = clampf((x - pad) / maxf(size.x - pad * 2.0, 1.0), 0.0, 1.0)
		value = min_value + pow(t, BribePanel.SLIDER_CURVE) * (max_value - min_value)

	func _draw() -> void:
		var mid: float = size.y * 0.58
		var track_h: float = size.y * 0.2
		var left: float = _x_for(min_value)
		var right: float = _x_for(max_value)
		var knob: float = _x_for(value)
		var track: Rect2 = Rect2(left, mid - track_h * 0.5, right - left, track_h)
		PhoneOverlay.fill_round(self, track.grow(2.0), track_h, CharacterStyle.OUTLINE)
		PhoneOverlay.fill_round(self, track, track_h * 0.5, UITheme.color("slot"))
		PhoneOverlay.fill_round(self, Rect2(track.position, Vector2(knob - left, track_h)), track_h * 0.5,
				accent if editable() else UITheme.color("faint"))
		if estimate >= 0:
			_draw_estimate(mid - track_h, float(estimate) > max_value)
		var radius: float = _knob_radius()
		draw_circle(Vector2(knob, mid), radius + 2.5, CharacterStyle.OUTLINE)
		draw_circle(Vector2(knob, mid), radius, UITheme.color("paper"))
		draw_circle(Vector2(knob, mid), radius * 0.42, accent if editable() else UITheme.color("faint"))

	func _draw_estimate(top: float, beyond: bool) -> void:
		var x: float = _x_for(float(estimate))
		var col: Color = UITheme.color("loss" if beyond else "hazard")
		var s: float = size.y * 0.16
		var tip: Vector2 = Vector2(x, top - 2.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s, -s * 1.4), tip + Vector2(s, -s * 1.4)]), col)
		draw_line(Vector2(x, top), Vector2(x, size.y * 0.58 + size.y * 0.14), col, 2.0, true)


var npc_resolver: Callable = Callable()
var wallet: Bribery.Wallet = null
var ctx_provider: Callable = Callable()
var _npc_id: String = ""
var _channel: String = Bribery.CHANNEL_MOBILE_CHAT
var _favours: Array[Dictionary] = []
var _favour_index: int = 0
var _state: String = STATE_EDIT
var _counter: Dictionary = {}
var _last: Dictionary = {}
var _exposure: Dictionary = {}
var _portrait: PhoneOverlay.Portrait
var _title: Label
var _channel_glyph: PhoneOverlay.Glyph
var _channel_label: Label
var _favour_label: Label
var _favour_count: Label
var _amount_label: Label
var _funds_label: Label
var _slider: AmountSlider
var _estimate_glyph: PhoneOverlay.Glyph
var _estimate_label: Label
var _risk_glyph: PhoneOverlay.Glyph
var _risk_label: Label
var _send_button: PhoneOverlay.IconButton
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _result_card: PanelContainer
var _result_glyph: PhoneOverlay.Glyph
var _result_label: Label
var _counter_button: PhoneOverlay.IconButton


func _init() -> void:
	name = "BribePanel"
	add_theme_stylebox_override("panel", PhoneOverlay.box(UITheme.color("ink"), Color(0, 0, 0, 0), 0, 0.0, 0.0))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	column.add_child(_build_header())
	var parts: Dictionary = PhoneOverlay.scroll_list()
	var body: VBoxContainer = parts["list"]
	body.add_theme_constant_override("separation", 7)
	column.add_child(parts["scroll"])
	body.add_child(_caption("PHONE_BRIBE_FAVOUR_CAPTION"))
	body.add_child(_build_favour_stepper())
	body.add_child(_caption("PHONE_BRIBE_AMOUNT_CAPTION"))
	body.add_child(_build_amount())
	body.add_child(_build_info_line(true))
	body.add_child(_build_info_line(false))
	column.add_child(_build_actions())


func _build_header() -> Control:
	var head: HBoxContainer = HBoxContainer.new()
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "back", UITheme.V_FLAT)
	back.tooltip_text = tr("PHONE_BACK")
	back.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(back)
	_portrait = PhoneOverlay.Portrait.new(2.0)
	head.add_child(_portrait)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	_title = PhoneOverlay.label("", UITheme.V_STRONG, true)
	text.add_child(_title)
	var channel: HBoxContainer = HBoxContainer.new()
	text.add_child(channel)
	_channel_glyph = PhoneOverlay.Glyph.new("talk", "muted", 0.75)
	channel.add_child(_channel_glyph)
	_channel_label = PhoneOverlay.label("", UITheme.V_CAPTION)
	channel.add_child(_channel_label)
	return head


func _caption(key: String) -> Label:
	return PhoneOverlay.label(tr(key).to_upper(), UITheme.V_CAPTION)


func _build_favour_stepper() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var prev: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "back")
	prev.pressed.connect(step_favour.bind(-1))
	row.add_child(prev)
	var card: PanelContainer = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 8, 10.0, 6.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(card)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	card.add_child(text)
	_favour_label = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_favour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_favour_label)
	_favour_count = PhoneOverlay.label("", UITheme.V_CAPTION)
	_favour_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(_favour_count)
	var next: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("", "arrow")
	next.pressed.connect(step_favour.bind(1))
	row.add_child(next)
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
	var slide_row: HBoxContainer = HBoxContainer.new()
	column.add_child(slide_row)
	var minus: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("−", "", UITheme.V_FLAT)
	minus.pressed.connect(func() -> void: nudge(-1))
	slide_row.add_child(minus)
	_slider = AmountSlider.new()
	_slider.value_changed.connect(func(_v: float) -> void: _refresh_amount())
	slide_row.add_child(_slider)
	var plus: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new("+", "", UITheme.V_FLAT)
	plus.pressed.connect(func() -> void: nudge(1))
	slide_row.add_child(plus)
	return column


func _build_info_line(estimate: bool) -> Control:
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


func _build_actions() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	_send_button = PhoneOverlay.IconButton.new("", "coin", UITheme.V_PRIMARY)
	_send_button.pressed.connect(func() -> void: request_offer())
	column.add_child(_send_button)
	_confirm_box = VBoxContainer.new()
	column.add_child(_confirm_box)
	_confirm_label = PhoneOverlay.label("", UITheme.V_SMALL, true)
	_confirm_box.add_child(_confirm_label)
	var row: HBoxContainer = HBoxContainer.new()
	_confirm_box.add_child(row)
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BACK"), "")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(cancel_confirm)
	row.add_child(back)
	var confirm: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BRIBE_CONFIRM"), "check",
			UITheme.V_DANGER)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void: confirm_offer())
	row.add_child(confirm)
	column.add_child(_build_result())
	return column


func _build_result() -> Control:
	_result_card = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 10, 12.0, 9.0)
	var column: VBoxContainer = VBoxContainer.new()
	_result_card.add_child(column)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_result_glyph = PhoneOverlay.Glyph.new("info", "paper", 1.2)
	_result_glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_result_glyph)
	_result_label = PhoneOverlay.label("", "", true)
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_result_label)
	_counter_button = PhoneOverlay.IconButton.new("", "coin", UITheme.V_PRIMARY)
	_counter_button.pressed.connect(accept_counteroffer)
	column.add_child(_counter_button)
	var done: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("PHONE_BRIBE_DONE"), "")
	done.pressed.connect(func() -> void: close_requested.emit())
	column.add_child(done)
	return _result_card


# ─── API ───────────────────────────────────────────────────────────

func setup_for(npc_id: String, channel: String) -> void:
	_npc_id = npc_id
	_channel = channel
	_counter = {}
	_last = {}
	_favours = Database.get_all_bribe_favours()
	_favour_index = 0
	var npc: NPCRuntime = _npc()
	_portrait.set_npc(npc)
	_title.text = UITheme.trf("PHONE_BRIBE_TITLE", [PhoneOverlay.npc_name(npc_id)])
	var call: bool = channel == Bribery.CHANNEL_PHONE_CALL
	_channel_glyph.set_glyph("phone" if call else "talk")
	_channel_label.text = tr("PHONE_BRIBE_VIA_CALL" if call else "PHONE_BRIBE_VIA_CHAT").to_upper()
	_slider.accent = PhoneOverlay.accent_color()
	refresh_funds()
	_reset_amount()
	_set_state(STATE_EDIT)


func get_npc_id() -> String:
	return _npc_id


func get_channel() -> String:
	return _channel


func get_favour() -> String:
	return str(_favours[_favour_index]["id"]) if _favour_index < _favours.size() else ""


func select_favour(favour_id: String) -> bool:
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
	return roundi(_slider.value) if _slider.editable() else 0


func set_amount(amount: int) -> void:
	_slider.value = amount
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
	var result: Dictionary = Bribery.offer(_npc(), get_amount(), get_favour(), _channel, ctx)
	_last = result
	var countered: bool = str(result.get("outcome", "")) == Bribery.OUTCOME_COUNTEROFFER
	_counter = (result.get("counteroffer", {}) as Dictionary).duplicate() if countered else {}
	_set_state(STATE_RESULT)
	_show_result(result)
	offer_resolved.emit(result)
	return result


## Contraoferta: pone la cantidad pedida y arma la confirmación (sigue haciendo falta confirmar).
func accept_counteroffer() -> bool:
	if _counter.is_empty():
		return false
	refresh_funds()
	_set_state(STATE_EDIT)
	set_amount(int(_counter.get(Bribery.TOKEN_ASKED, 0)))
	return request_offer()


func refresh_funds() -> void:
	var step: int = _step()
	var money: int = _money()
	_slider.min_value = step
	_slider.step = step
	_slider.max_value = maxi(money - money % step, step)
	_funds_label.text = UITheme.trf("PHONE_BRIBE_FUNDS", [UITheme.format_money(money)])
	_refresh_amount()


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


func _reset_amount() -> void:
	var estimate: int = get_estimate()
	var step: int = _step()
	var start: int = estimate if estimate > 0 else roundi(_money() * PhoneOverlay.tune(B_START))
	set_amount(clampi(start - start % step, step, int(_slider.max_value)))


func _on_favour_changed() -> void:
	if shows_estimate():
		_reset_amount()
	_refresh()


func _set_state(state: String) -> void:
	_state = state
	_send_button.visible = state == STATE_EDIT
	_confirm_box.visible = state == STATE_CONFIRM
	_result_card.visible = state == STATE_RESULT
	_refresh()


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
	var amount: int = get_amount()
	var text: String = UITheme.format_money(amount)
	_amount_label.text = text
	_send_button.set_label(UITheme.trf("PHONE_BRIBE_SEND", [text]))
	_send_button.disabled = not can_offer()
	_confirm_label.text = UITheme.trf("PHONE_BRIBE_CONFIRM_BODY", [text, PhoneOverlay.npc_name(_npc_id),
			_favour_label.text])


func _refresh_estimate() -> void:
	var estimate: int = get_estimate()
	_slider.estimate = estimate
	_slider.queue_redraw()
	if estimate >= 0:
		_estimate_glyph.set_glyph("document", UITheme.color("hazard"))
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_ESTIMATE", [UITheme.format_money(estimate)])
		_estimate_label.add_theme_color_override("font_color", UITheme.color("hazard"))
	else:
		_estimate_glyph.set_glyph("lock", UITheme.color("muted"))
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_BLIND", [PhoneOverlay.tune_i(B_FILE_LEVEL)])
		_estimate_label.add_theme_color_override("font_color", UITheme.color("muted"))
	if not _counter.is_empty():
		_estimate_label.text = UITheme.trf("PHONE_BRIBE_ASKED",
				[UITheme.format_money(int(_counter.get(Bribery.TOKEN_ASKED, 0)))])


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
	var tone: String = str(OUTCOME_TONES.get(outcome, "loss"))
	var col: Color = UITheme.color(tone)
	_result_card.add_theme_stylebox_override("panel", PhoneOverlay.box(Color(col.darkened(0.7), 0.95), col,
			10, 12.0, 9.0, 2))
	_result_glyph.set_glyph(str(OUTCOME_GLYPHS.get(outcome, "cross")), col)
	var text: String = tr(str(result.get("text_key", "")))
	var insult: String = str(result.get("insult_text_key", ""))
	if not insult.is_empty() and insult != str(result.get("text_key", "")):
		text += "\n" + tr(insult)
	_result_label.text = text
	_counter_button.visible = not _counter.is_empty()
	if not _counter.is_empty():
		_counter_button.set_label(UITheme.trf("PHONE_BRIBE_PAY_ASKED",
				[UITheme.format_money(int(_counter.get(Bribery.TOKEN_ASKED, 0)))]))
	_refresh_estimate()
