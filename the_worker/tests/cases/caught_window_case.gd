# caught_window_case.gd — Cuerpo de test_caught_window: testigos que vetan la eliminación (también por código), confirmación, contraoferta, fondos, inacción, integración con UIRoot y chantaje.
# PROPIETARIO DE: nada.
# ESCUCHA: npc_removed, crime_committed, npc_reported_player, bribe_offered, npc_decided (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const CRIME := "drawer_forced"
const WATCHED: Array[String] = ["npc_removed", "crime_committed", "npc_reported_player", "bribe_offered",
		"npc_decided", "blackmail_demanded"]
const VICTIM := "npc_nate_brackley"
const MANAGED_BLACKMAILER := "npc_frank_rudd"

var _log: Fixtures.SignalLog = null
var _npcs: Dictionary = {}
var _handler: CaughtHandler = null
var _wallet: Fixtures.FakeWallet = null


func run_case() -> void:
	check(new_run(), "Database loaded the data files")
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_setup_handler()
	await _check_witnesses_block_elimination()
	await _check_elimination_without_witnesses()
	await _check_counteroffer()
	await _check_no_funds()
	await _check_timeout_inaction()
	await _check_with_ui_root()
	await _check_blackmail_dialog()
	await _check_blackmail_binder()
	_log.stop()
	_handler.queue_free()
	await wait_frames(2)


func _npc(archetype: String) -> NPCRuntime:
	var npc_id: String = "test_" + archetype
	if not _npcs.has(npc_id):
		_npcs[npc_id] = Fixtures.synthetic(npc_id, archetype)
	return _npcs[npc_id]


func _setup_handler() -> void:
	_handler = CaughtHandler.new()
	_handler.npc_resolver = func(npc_id: String) -> NPCRuntime: return _npcs.get(npc_id)
	_handler.roll_source = func() -> float: return 0.0
	_wallet = Fixtures.FakeWallet.new(50000)
	_handler.wallet = _wallet
	add_child(_handler)
	_handler.set_process(false)


func _open_window(npc_id: String, witnesses: int) -> CaughtWindow:
	_log.clear()
	EventBus.player_caught_redhanded.emit(npc_id, CRIME, witnesses)
	var window: CaughtWindow = CaughtWindow.new()
	window.attach(_handler, npc_id, _handler.get_options())
	add_child(window)
	await wait_frames(2)
	return window


func _close(window: CaughtWindow) -> void:
	if _handler.is_window_open():
		_handler.resolve_inaction(0.9)
	window.queue_free()
	await wait_frames(1)


## Clic real del ratón en el centro de una tarjeta.
func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
	await wait_frames(2)


func _press_key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)
	await wait_frames(2)


# ─── Eliminación ───────────────────────────────────────────────────

func _check_witnesses_block_elimination() -> void:
	var window: CaughtWindow = await _open_window(_npc("hardliner").id, 2)
	var card: CaughtWindow.OptionCard = window.get_option_card(CaughtWindow.OPTION_ELIMINATE) as CaughtWindow.OptionCard
	check(not window.is_elimination_enabled(), "with witnesses, elimination is disabled")
	check(card.disabled and card.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.focus_mode == Control.FOCUS_NONE,
			"…the button ignores clicks and focus")
	check(card.flagged_red and card.detail.contains(tr("UI_CAUGHT_ELIMINATE_WITNESSES")),
			"…marked red with the 'There are witnesses' warning")
	check(not window.press_elimination() and window.get_armed().is_empty(), "press_elimination() refuses")
	card.pressed.emit()
	await _click(card)
	await _press_key(KEY_2)
	check(window.get_armed().is_empty() and window.get_state() == CaughtWindow.STATE_DECIDING,
			"neither a forced pressed signal, a real click nor key 2 can arm it")
	check(window.confirm().is_empty(), "confirm() with nothing armed does nothing")
	check(_log.count("npc_removed") == 0 and _handler.is_window_open(), "nobody was eliminated")
	check(window.is_bribe_enabled(), "offering money is still possible")
	await _close(window)


func _check_elimination_without_witnesses() -> void:
	var window: CaughtWindow = await _open_window(VICTIM, 0)
	check(window.is_elimination_enabled() and window.is_elimination_clickable(),
			"without witnesses, SILENCE THEM PERMANENTLY is available")
	await _click(window.get_option_card(CaughtWindow.OPTION_ELIMINATE))
	check_eq(window.get_armed(), CaughtWindow.OPTION_ELIMINATE, "a real click arms it")
	check_eq(_log.count("npc_removed"), 0, "one press does nothing irreversible (§13.7)")
	window.back_out()
	check_eq(window.get_state(), CaughtWindow.STATE_DECIDING, "Back disarms it")
	window.press_elimination()
	var result: Dictionary = window.confirm()
	check(bool(result.get("ok", false)), "confirming carries out the elimination through CaughtHandler")
	var crime: Array = _log.last("crime_committed")
	check(not crime.is_empty() and crime[0] == CaughtHandler.CRIME_ELIMINATION, "crime_committed('elimination')")
	check(window.get_state() == CaughtWindow.STATE_RESULT and window.get_outcome() == CaughtHandler.OUTCOME_ELIMINATED,
			"the window shows the outcome")
	check(not NPCDirector.is_alive(VICTIM), "the witness is gone")
	await _close(window)


# ─── Dinero ────────────────────────────────────────────────────────

func _check_counteroffer() -> void:
	var window: CaughtWindow = await _open_window(_npc("bribable").id, 1)
	var original: int = int(window.get_options()["bribe"]["price"])
	window.bribe_ctx = {"roll": 0.99, "counter_roll": 0.5}
	check(window.press_bribe() and window.get_state() == CaughtWindow.STATE_CONFIRM, "OFFER MONEY arms first")
	check_eq(_log.count("bribe_offered"), 0, "…and offers nothing until confirmed")
	var first: Dictionary = window.confirm()
	check_eq(str(first.get("outcome", "")), Bribery.OUTCOME_COUNTEROFFER, "the bribable asks for more")
	var options: Dictionary = window.get_options()
	var asked: int = int(options["bribe"]["price"])
	check(_handler.is_window_open() and window.get_state() == CaughtWindow.STATE_DECIDING,
			"counteroffer: the window stays open for another answer")
	check(bool(options["bribe"]["counteroffer"]) and asked == roundi(original * 1.55),
			"the new asked price is shown")
	var card: CaughtWindow.OptionCard = window.get_option_card(CaughtWindow.OPTION_BRIBE) as CaughtWindow.OptionCard
	check(card.detail.contains(UITheme.format_money(asked)), "the money card shows the counteroffer price")
	var money: int = _wallet.money
	window.press_bribe()
	var second: Dictionary = window.confirm()
	check_eq(str(second.get("outcome", "")), Bribery.OUTCOME_ACCEPTED, "paying what they ask is accepted")
	check_eq(_wallet.money, money - asked, "the counteroffer price was paid")
	check_eq(window.get_state(), CaughtWindow.STATE_RESULT, "the window shows the result")
	await _close(window)


func _check_no_funds() -> void:
	var saved: int = _wallet.money
	_wallet.money = 0
	var window: CaughtWindow = await _open_window(_npc("coward").id, 1)
	var card: CaughtWindow.OptionCard = window.get_option_card(CaughtWindow.OPTION_BRIBE) as CaughtWindow.OptionCard
	check(not window.is_bribe_enabled() and card.disabled, "insufficient funds: OFFER MONEY is disabled")
	check(card.detail.contains(tr("UI_CAUGHT_BRIBE_NO_FUNDS")), "…and says why")
	check(not window.press_bribe(), "…and cannot be armed")
	_wallet.money = saved
	await _close(window)


# ─── Inacción ──────────────────────────────────────────────────────

func _check_timeout_inaction() -> void:
	BeliefNet.reset_for_new_run()
	var window: CaughtWindow = await _open_window(_npc("hardliner").id, 1)
	var start: float = window.get_seconds_left()
	check(start > 0.0, "the inaction countdown is visible")
	await wait_frames(6)
	check(window.get_seconds_left() < start, "…and it runs down")
	var closed: Array[bool] = [false]
	window.closed.connect(func() -> void: closed[0] = true)
	_handler.advance_timer(float(_handler.get_options()["seconds_left"]) + 0.01)
	check(not _handler.is_window_open(), "time out: the handler resolves the inaction")
	check(window.get_state() == CaughtWindow.STATE_RESULT and window.get_outcome() == CaughtHandler.OUTCOME_INACTION,
			"the window shows the inaction outcome")
	check_eq(str(window.get_reaction().get("reaction", "")), CaughtHandler.REACTION_SECURITY,
			"…with the witness's reaction (hardliner goes to Security)")
	check_eq(_log.count("npc_reported_player"), 1, "the NPC acted on timeout")
	await get_tree().create_timer(PhoneOverlay.tune(CaughtWindow.B_RESULT_S) + 0.3).timeout
	check(closed[0], "after showing the reaction the window asks to close")
	window.queue_free()
	await wait_frames(1)


## Con UIRoot: el Binder abre la ventana, guarda el móvil, no pausa el reloj y Esc no la cierra.
func _check_with_ui_root() -> void:
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await wait_frames(2)
	check(CaughtWindow.install(ui, _handler) != null, "CaughtWindow.install(ui_root, caught_handler)")
	ui.open_phone()
	await wait_frames(2)
	EventBus.player_caught_redhanded.emit(_npc("oblivious").id, CRIME, 0)
	await wait_frames(3)
	check(ui.get_top_modal() is CaughtWindow, "decision_window_opened opens the caught window")
	check(not PhoneOverlay.is_open(get_tree()), "…and the phone is put away")
	check(not ui.is_clock_paused_by_ui() and _handler.is_time_slowed(),
			"time slows (CaughtHandler) but the clock is not paused by the UI")
	(ui.get_top_modal() as CaughtWindow).request_close()
	await wait_frames(2)
	check(ui.get_top_modal() is CaughtWindow, "Esc cannot dismiss the flagrancy window")
	_handler.resolve_inaction(0.9)
	await get_tree().create_timer(PhoneOverlay.tune(CaughtWindow.B_RESULT_S) + 0.3).timeout
	check(not ui.has_modal(), "once resolved and shown, the window leaves the modal stack")
	ui.queue_free()
	await wait_frames(2)


# ─── Chantaje ──────────────────────────────────────────────────────

func _demand_from(npc: NPCRuntime, demand_type: String) -> void:
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_WITNESSED, CRIME, GameClock.get_day(),
			demand_type, 0)
	Blackmail.issue_demand(npc, entry, GameClock.get_day())


func _dialog_for(npc: NPCRuntime, money: int) -> BlackmailDialog:
	var dialog: BlackmailDialog = BlackmailDialog.new()
	dialog.npc_resolver = func(npc_id: String) -> NPCRuntime: return _npcs.get(npc_id)
	dialog.wallet = Fixtures.FakeWallet.new(money)
	dialog.setup({"npc_id": npc.id})
	add_child(dialog)
	return dialog


func _check_blackmail_dialog() -> void:
	var payer: NPCRuntime = _npc("burnout")
	_demand_from(payer, Blackmail.DEMAND_MONEY)
	var amount: int = int(Blackmail.get_open_demand(payer)["amount"])
	var dialog: BlackmailDialog = _dialog_for(payer, amount + 1)
	await wait_frames(2)
	check(not dialog.get_demand().is_empty() and dialog.is_pay_enabled(), "the blackmail demand is shown, payable")
	check(dialog.press_pay() and dialog.get_state() == BlackmailDialog.STATE_CONFIRM, "Pay asks for confirmation")
	check_eq((dialog.wallet as Fixtures.FakeWallet).money, amount + 1, "…and has not paid yet")
	var paid: Dictionary = dialog.confirm()
	check(bool(paid.get("ok", false)) and str(paid.get("event", "")) == Blackmail.EVENT_PAID, "Blackmail.pay() runs")
	check_eq((dialog.wallet as Fixtures.FakeWallet).money, 1, "the demanded amount was paid")
	dialog.queue_free()
	var refuser: NPCRuntime = _npc("climber")
	_demand_from(refuser, Blackmail.DEMAND_FAVOUR)
	var broke: BlackmailDialog = _dialog_for(refuser, 0)
	await wait_frames(2)
	check(broke.is_pay_enabled(), "a favour demand can be met without money")
	check(broke.press_refuse(), "Refuse asks for confirmation")
	_log.clear()
	var refused: Dictionary = broke.confirm()
	check(bool(refused.get("ok", false)) and _log.count_for("npc_reported_player", refuser.id) == 1,
			"refusing: Blackmail.refuse() and they talk")
	broke.queue_free()
	var poor: NPCRuntime = _npc("gossip")
	_demand_from(poor, Blackmail.DEMAND_MONEY)
	var no_money: BlackmailDialog = _dialog_for(poor, 0)
	await wait_frames(2)
	check(not no_money.is_pay_enabled() and not no_money.press_pay(), "cannot pay money you do not have")
	no_money.queue_free()


func _check_blackmail_binder() -> void:
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await wait_frames(2)
	check(BlackmailDialog.install(ui) != null, "BlackmailDialog.install(ui_root)")
	var npc: NPCRuntime = NPCDirector.get_npc(MANAGED_BLACKMAILER)
	_demand_from(npc, Blackmail.DEMAND_MONEY)
	await wait_frames(3)
	check(ui.get_top_modal() is BlackmailDialog, "blackmail_demanded opens the pay/refuse dialog")
	(ui.get_top_modal() as BlackmailDialog).request_close()
	await wait_frames(2)
	check(not ui.has_modal() and not Blackmail.get_open_demand(npc).is_empty(),
			"'Decide later' closes it and the demand stays open")
	ui.queue_free()
	await wait_frames(2)
