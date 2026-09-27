# blackmail_dialog.gd — Exigencia de chantaje (§12.2, §8.2): quién te chantajea, qué pide, hasta cuándo, y pagar, negarse o decidir después.
# PROPIETARIO DE: la vista de una exigencia abierta (acción armada a la espera de confirmación y resultado mostrado); el Binder guarda la cola de exigencias que esperan a que se cierre una flagrancia.
# ESCUCHA: blackmail_demanded (el Binder), money_changed, game_over.
class_name BlackmailDialog
extends PanelContainer

## Integración: game_root llama una vez a BlackmailDialog.install(ui_root). Con cada
## blackmail_demanded el Binder abre este diálogo (UIRoot.open_modal(…, true): pausa el reloj como
## cualquier diálogo); si hay una flagrancia abierta espera a que se cierre. El chat del móvil también
## lo abre (BlackmailDialog.open_for(ui, npc_id)) mientras la exigencia siga abierta.
## Pagar = Blackmail.pay(npc, ctx) y negarse = Blackmail.refuse(npc, ctx), cada uno con confirmación
## explícita (§13.7). «Decidir después» cierra sin responder: pasado chantaje.plazo_respuesta_dias,
## Blackmail lo cuenta como negativa. Pagar dinero se deshabilita si no llega el capital.

signal closed

const STATE_DECIDING := "deciding"
const STATE_CONFIRM := "confirm"
const STATE_RESULT := "result"
const ACTION_PAY := "pay"
const ACTION_REFUSE := "refuse"
const WIDTH_EMS := 25.0
const FAILED_KEY := "BLACKMAILUI_FAILED_%s"
const DEMAND_KEYS: Dictionary = {
	Blackmail.DEMAND_MONEY: "BLACKMAILUI_WANTS_MONEY",
	Blackmail.DEMAND_PROMOTION: "BLACKMAILUI_WANTS_PROMOTION",
	Blackmail.DEMAND_FAVOUR: "BLACKMAILUI_WANTS_FAVOUR",
}
const DEMAND_GLYPHS: Dictionary = {
	Blackmail.DEMAND_MONEY: "cash", Blackmail.DEMAND_PROMOTION: "star", Blackmail.DEMAND_FAVOUR: "talk",
}


## Abre un diálogo por exigencia; espera si hay una ventana de flagrancia encima.
class Binder extends Node:
	var ui: UIRoot
	var pending: Array[String] = []

	func _init(p_ui: UIRoot) -> void:
		name = "BlackmailDialogBinder"
		ui = p_ui

	func _ready() -> void:
		EventBus.blackmail_demanded.connect(_on_demanded)

	func _on_demanded(npc_id: String, _demand_type: String, _amount: int) -> void:
		if not pending.has(npc_id):
			pending.append(npc_id)
		_flush.call_deferred()

	func _process(_delta: float) -> void:
		if not pending.is_empty():
			_flush()

	func _flush() -> void:
		if not is_instance_valid(ui) or pending.is_empty() or ui.get_top_modal() is CaughtWindow:
			return
		var npc_id: String = pending.pop_front()
		BlackmailDialog.open_for(ui, npc_id)


var npc_resolver: Callable = Callable()
var wallet: Bribery.Wallet = null
var _npc_id: String = ""
var _demand: Dictionary = {}
var _state: String = STATE_DECIDING
var _armed: String = ""
var _result: Dictionary = {}
var _photo: PhoneOverlay.Portrait
var _kicker: Label
var _kicker_glyph: PhoneOverlay.Glyph
var _who: Label
var _job: Label
var _message: Label
var _demand_glyph: PhoneOverlay.Glyph
var _demand_value: Label
var _demand_cost: Label
var _deadline: Label
var _pay_button: PhoneOverlay.IconButton
var _refuse_button: PhoneOverlay.IconButton
var _later_button: PhoneOverlay.IconButton
var _choice_row: HBoxContainer
var _confirm_box: VBoxContainer
var _confirm_label: Label
var _confirm_button: PhoneOverlay.IconButton
var _result_label: Label
var _close_button: PhoneOverlay.IconButton


func _init() -> void:
	name = "BlackmailDialog"
	theme_type_variation = UITheme.V_MODAL
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_message())
	column.add_child(_build_demand())
	column.add_child(_build_choices())
	column.add_child(_build_confirm())
	_result_label = PhoneOverlay.label("", UITheme.V_HEADING, true)
	column.add_child(_result_label)
	_close_button = PhoneOverlay.IconButton.new(tr("BLACKMAILUI_CLOSE"), "")
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(_close_button)


func _build_header() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	var kicker: HBoxContainer = HBoxContainer.new()
	column.add_child(kicker)
	_kicker_glyph = PhoneOverlay.Glyph.new("phone", "muted", 0.8)
	kicker.add_child(_kicker_glyph)
	_kicker = PhoneOverlay.label(tr("BLACKMAILUI_KICKER").to_upper(), UITheme.V_CAPTION)
	kicker.add_child(_kicker)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_photo = PhoneOverlay.Portrait.new(3.4)
	row.add_child(_photo)
	var text: VBoxContainer = VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_who = PhoneOverlay.label("", UITheme.V_TITLE)
	text.add_child(_who)
	_job = PhoneOverlay.label("", UITheme.V_SMALL)
	text.add_child(_job)
	return column


func _build_message() -> Control:
	var bubble: PanelContainer = PhoneOverlay.card(UITheme.color("slot"), UITheme.color("line"), 14, 16.0, 12.0)
	_message = PhoneOverlay.label("", "", true)
	_message.add_theme_font_override("font", UITheme.italic(UITheme.font(UITheme.FONT_REGULAR)))
	bubble.add_child(_message)
	return bubble


func _build_demand() -> Control:
	var danger: Color = UITheme.color("danger")
	var panel: PanelContainer = PhoneOverlay.card(Color(danger.darkened(0.72), 0.95), danger.darkened(0.1), 12,
			16.0, 10.0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(PhoneOverlay.label(tr("BLACKMAILUI_THEY_WANT").to_upper(), UITheme.V_CAPTION))
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_demand_glyph = PhoneOverlay.Glyph.new("cash", "hazard", 1.6)
	row.add_child(_demand_glyph)
	_demand_value = PhoneOverlay.label("", UITheme.V_NUMBER, true)
	_demand_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_demand_value)
	_demand_cost = PhoneOverlay.label("", UITheme.V_SMALL, true)
	column.add_child(_demand_cost)
	_deadline = PhoneOverlay.label("", UITheme.V_SMALL, true)
	_deadline.add_theme_color_override("font_color", UITheme.color("warn"))
	column.add_child(_deadline)
	return panel


func _build_choices() -> Control:
	_choice_row = HBoxContainer.new()
	_pay_button = PhoneOverlay.IconButton.new("", "cash", UITheme.V_PRIMARY)
	_refuse_button = PhoneOverlay.IconButton.new(tr("BLACKMAILUI_REFUSE"), "cross", UITheme.V_DANGER)
	_later_button = PhoneOverlay.IconButton.new(tr("BLACKMAILUI_LATER"), "clock")
	for button: PhoneOverlay.IconButton in [_pay_button, _refuse_button, _later_button]:
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choice_row.add_child(button)
	_pay_button.pressed.connect(func() -> void: press_pay())
	_refuse_button.pressed.connect(func() -> void: press_refuse())
	_later_button.pressed.connect(later)
	return _choice_row


func _build_confirm() -> Control:
	_confirm_box = VBoxContainer.new()
	_confirm_label = PhoneOverlay.label("", UITheme.V_STRONG, true)
	_confirm_box.add_child(_confirm_label)
	var row: HBoxContainer = HBoxContainer.new()
	_confirm_box.add_child(row)
	var back: PhoneOverlay.IconButton = PhoneOverlay.IconButton.new(tr("CAUGHTUI_BACK"), "back")
	back.focus_mode = Control.FOCUS_ALL
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(back_out)
	row.add_child(back)
	_confirm_button = PhoneOverlay.IconButton.new("", "check", UITheme.V_DANGER)
	_confirm_button.focus_mode = Control.FOCUS_ALL
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(func() -> void: confirm())
	row.add_child(_confirm_button)
	return _confirm_box


# ─── Apertura ──────────────────────────────────────────────────────

static func install(ui: UIRoot) -> Node:
	if ui == null:
		return null
	for child: Node in ui.get_children():
		if child is Binder:
			return child
	var binder: Binder = Binder.new(ui)
	ui.add_child(binder)
	return binder


## Abre el diálogo de la exigencia abierta del personaje (no hace nada si ya no hay exigencia).
static func open_for(ui: UIRoot, npc_id: String) -> BlackmailDialog:
	var dialog: BlackmailDialog = BlackmailDialog.new()
	dialog.setup({"npc_id": npc_id})
	if dialog.get_demand().is_empty():
		dialog.free()
		return null
	ui.open_modal(dialog, true)
	return dialog


## context: {npc_id}. La exigencia se lee de Blackmail.get_open_demand() del personaje.
func setup(context: Dictionary) -> void:
	_npc_id = str(context.get("npc_id", ""))
	var npc: NPCRuntime = _npc()
	_demand = Blackmail.get_open_demand(npc).duplicate() if npc != null else {}
	_photo.set_npc(npc)
	_who.text = PhoneOverlay.npc_name(_npc_id)
	_job.text = PhoneOverlay.job_text(npc)
	_show_demand()
	_set_state(STATE_DECIDING)


func _ready() -> void:
	UITheme.center_fitted(self)
	custom_minimum_size.x = PhoneOverlay.base_size(self) * WIDTH_EMS
	EventBus.money_changed.connect(func(_o: int, _n: int, _r: String) -> void: _refresh_pay())
	EventBus.game_over.connect(func(_c: String, _e: String, _s: Dictionary) -> void: closed.emit())
	_later_button.grab_focus.call_deferred()


## Esc = decidir después.
func request_close() -> void:
	if _state == STATE_CONFIRM:
		back_out()
	else:
		later()


# ─── API ───────────────────────────────────────────────────────────

func get_demand() -> Dictionary:
	return _demand.duplicate()


func get_state() -> String:
	return _state


func get_result() -> Dictionary:
	return _result.duplicate(true)


func is_pay_enabled() -> bool:
	if _demand.is_empty():
		return false
	if str(_demand.get("demand_type", "")) != Blackmail.DEMAND_MONEY:
		return true
	return _can_afford(int(_demand.get("amount", 0)))


func press_pay() -> bool:
	if _state != STATE_DECIDING or not is_pay_enabled():
		return false
	_arm(ACTION_PAY)
	return true


func press_refuse() -> bool:
	if _state != STATE_DECIDING or _demand.is_empty():
		return false
	_arm(ACTION_REFUSE)
	return true


func back_out() -> void:
	if _state == STATE_CONFIRM:
		_set_state(STATE_DECIDING)


func later() -> void:
	if _state != STATE_CONFIRM:
		closed.emit()


## Ejecuta lo armado (Blackmail.pay / Blackmail.refuse). {} si no había nada armado.
func confirm() -> Dictionary:
	if _state != STATE_CONFIRM:
		return {}
	var ctx: Dictionary = {"room_id": PlayerState.get_room()}
	if wallet != null:
		ctx["wallet"] = wallet
	var npc: NPCRuntime = _npc()
	_result = Blackmail.pay(npc, ctx) if _armed == ACTION_PAY else Blackmail.refuse(npc, ctx)
	if not bool(_result.get("ok", false)):
		_confirm_label.text = tr(FAILED_KEY % str(_result.get("reason", Blackmail.REASON_NO_DEMAND)).to_upper())
		return _result
	_result_label.text = tr(str(_result.get("text_key", "")))
	var tone: String = "gain" if _armed == ACTION_PAY else "danger"
	_result_label.add_theme_color_override("font_color", UITheme.color(tone).lightened(0.2))
	_set_state(STATE_RESULT)
	_close_button.grab_focus.call_deferred()
	return _result


# ─── Interno ───────────────────────────────────────────────────────

func _npc() -> NPCRuntime:
	var npc: NPCRuntime = null
	if npc_resolver.is_valid():
		npc = npc_resolver.call(_npc_id) as NPCRuntime
	return npc if npc != null else NPCDirector.get_npc(_npc_id)


func _can_afford(amount: int) -> bool:
	return wallet.can_afford(amount) if wallet != null else PlayerState.can_afford(amount)


func _show_demand() -> void:
	var demand_type: String = str(_demand.get("demand_type", Blackmail.DEMAND_MONEY))
	var face: bool = str(_demand.get("kind", "")) == Blackmail.KIND_ASKED_MONEY
	var keys: Dictionary = Blackmail.FACE_KEYS if face else Blackmail.PHONE_KEYS
	_kicker.text = tr("BLACKMAILUI_KICKER_FACE" if face else "BLACKMAILUI_KICKER").to_upper()
	_kicker_glyph.set_glyph("person" if face else "phone")
	_message.text = UITheme.trf("BLACKMAILUI_QUOTE", [tr(str(keys.get(demand_type, "")))])
	_demand_glyph.set_glyph(str(DEMAND_GLYPHS.get(demand_type, "cash")))
	var amount: String = UITheme.format_money(int(_demand.get("amount", 0)))
	var money: bool = demand_type == Blackmail.DEMAND_MONEY
	_demand_value.text = amount if money else tr(str(DEMAND_KEYS[demand_type]))
	_demand_value.theme_type_variation = UITheme.V_NUMBER if money else UITheme.V_HEADING
	_pay_button.glyph = "cash" if money else "check"
	var cost_key: String = str(Blackmail.REPUTATION_COST_KEYS.get(demand_type, ""))
	_demand_cost.visible = not cost_key.is_empty()
	if _demand_cost.visible:
		_demand_cost.text = UITheme.trf("BLACKMAILUI_REPUTATION_COST", [roundi(PhoneOverlay.tune(cost_key))])
	var days: int = int(_demand.get("deadline_day", 0)) - GameClock.get_day()
	_deadline.text = UITheme.trf("BLACKMAILUI_DEADLINE", [int(_demand.get("deadline_day", 0)), maxi(days, 0)])
	_refresh_pay()


func _refresh_pay() -> void:
	var money: bool = str(_demand.get("demand_type", "")) == Blackmail.DEMAND_MONEY
	var amount: String = UITheme.format_money(int(_demand.get("amount", 0)))
	_pay_button.set_label(UITheme.trf("BLACKMAILUI_PAY_MONEY", [amount]) if money else tr("BLACKMAILUI_COMPLY"))
	_pay_button.disabled = not is_pay_enabled()
	_pay_button.tooltip_text = tr(Bribery.OUTCOME_TEXT_KEYS[Bribery.OUTCOME_NO_FUNDS]) if _pay_button.disabled else ""


func _arm(action: String) -> void:
	_armed = action
	var who: String = PhoneOverlay.npc_name(_npc_id)
	_confirm_label.text = UITheme.trf("BLACKMAILUI_CONFIRM_PAY" if action == ACTION_PAY
			else "BLACKMAILUI_CONFIRM_REFUSE", [who])
	_confirm_button.set_label(tr("BLACKMAILUI_YES_PAY") if action == ACTION_PAY else tr("BLACKMAILUI_YES_REFUSE"))
	_set_state(STATE_CONFIRM)
	_confirm_button.grab_focus.call_deferred()


func _set_state(state: String) -> void:
	_state = state
	if state != STATE_CONFIRM:
		_armed = "" if state == STATE_DECIDING else _armed
	_choice_row.visible = state == STATE_DECIDING
	_confirm_box.visible = state == STATE_CONFIRM
	_result_label.visible = state == STATE_RESULT
	_close_button.visible = state == STATE_RESULT
