# player_state_case.gd — Cuerpo de test_player_state (§21, PASO 6): capital, inventario, deberes, ejes, persistencia.
# PROPIETARIO DE: nada.
# ESCUCHA: money_changed, occupation_changed, clearance_changed, reputation_changed, inventory_changed, duty_assigned, duty_completed, duty_failed, duty_deadline_warned, tracking_event_recorded, disguise_changed (conexión temporal).
extends TestCase

const START_OCCUPATION := "email_worker_3b"
const START_DUTY := "duty_emails_r1"

## señal → Array de llamadas (cada llamada = Array de argumentos).
var _log: Dictionary = {}


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded and a new run was created")
	_connect_bus()
	_test_start_state()
	_test_money()
	_test_expenses()
	_test_occupation_change()
	_test_inventory_capacity()
	_test_inventory_categories()
	_test_duties()
	_test_duty_deadlines()
	_test_failure_ladder()
	_test_multi_duty_days()
	_test_periodic_duties()
	_test_demotion_risk()
	_test_rebuild_during_rollover()
	_test_meters()
	_test_tracking_facade()
	_test_position_and_identity()
	_test_save_load()
	_disconnect_bus()


# ─── Escenarios ────────────────────────────────────────────────

func _test_start_state() -> void:
	check_eq(PlayerState.get_occupation_id(), START_OCCUPATION, "the run starts as email_worker_3b")
	check_eq([PlayerState.get_rank(), PlayerState.get_tier(), PlayerState.get_clearance()],
			[1, 1, 1], "R1, tier 1, clearance 1 (§6.1)")
	check_eq(PlayerState.get_personnel_file_level(), 1, "personnel file level 1")
	check_eq(PlayerState.get_money(), 120, "starting money = economia.dinero_inicial (120 €)")
	check_near(PlayerState.get_reputation(),
			Database.get_balance_float("jugador.reputacion_inicial"), 0.0001, "starting reputation")
	check_eq(_inventory_ids(), ["own_card", "phone"], "starting inventory: own card and phone")
	check_eq(PlayerState.get_free_slots(), 6, "8 slots, 2 used")
	check(not PlayerState.has_hot_items(), "nothing compromising at the start")
	check_eq(_duty_ids(PlayerState.get_pending_duties()), [START_DUTY], "day 1 duty: 8 emails")
	check_eq([PlayerState.get_room(), PlayerState.get_floor()], ["wing_3b", 3],
			"the player starts at the 3B office on floor 3")
	check(PlayerState.has_item("keys_basic") and PlayerState.has_item("stamp"),
			"R1 is issued keys and stamp (occupation tools) without carrying them")
	check(not PlayerState.is_carrying("keys_basic") and PlayerState.is_carrying("phone"),
			"is_carrying is physical possession: issued keys are not carried, the phone is")
	check(not PlayerState.remove_item("keys_basic"),
			"an issued-but-not-carried tool cannot be removed (check is_carrying first)")


func _test_money() -> void:
	_clear()
	PlayerState.add_money(50, "test_income")
	check_eq(PlayerState.get_money(), 170, "add_money adds")
	check_eq(_calls("money_changed"), [[120, 170, "test_income"]],
			"money_changed(old, new, reason)")
	check(not PlayerState.spend_money(1000, "bribe"), "spend_money fails with insufficient funds")
	check_eq(PlayerState.get_money(), 170, "a failed payment leaves money untouched")
	check_eq(_calls("money_changed").size(), 1, "a failed payment emits nothing")
	check(PlayerState.can_afford(170) and not PlayerState.can_afford(171), "can_afford boundary")
	check(PlayerState.spend_money(170, "rent"), "spending exactly all the money works")
	check_eq(PlayerState.get_money(), 0, "money reaches zero")
	check(not PlayerState.spend_money(1, "breakfast"),
			"cannot pay with zero money (starvation risk)")
	PlayerState.add_money(-5, "negative")
	check_eq(PlayerState.get_money(), 0, "add_money ignores negative amounts")


func _test_expenses() -> void:
	new_run(DEFAULT_SEED, false)
	var breakdown: Dictionary = PlayerState.get_daily_expense_breakdown()
	check_eq([breakdown["breakfast"], breakdown["dinner"], breakdown["rent"], breakdown["status"]],
			[5, 10, 7, 0], "R1 daily costs: breakfast 5, dinner 10, rent 7, no status (§15.4)")
	check_eq(PlayerState.get_daily_expenses(), 22, "R1 spends 22 € a day")
	check_eq(PlayerState.get_daily_wage() - PlayerState.get_daily_expenses(), 8,
			"R1 honest margin is 8 € per day (§15.4)")
	var by_tier: Dictionary = {
		"a10_marketing_director": 62, "hr_director": 82, "cfo": 112, "ceo": 142,
	}
	for occupation_id: String in by_tier:
		PlayerState.set_occupation(occupation_id, "test")
		check_eq(PlayerState.get_daily_expenses(), by_tier[occupation_id],
				"tier %d adds its status expense (+40/+60/+90/+120)" % PlayerState.get_tier())


func _test_occupation_change() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	PlayerState.set_occupation("order_filer", "promotion")
	check_eq(_calls("occupation_changed"), [[START_OCCUPATION, "order_filer", "promotion"]],
			"set_occupation emits occupation_changed(old, new, reason)")
	check(_calls("clearance_changed").is_empty(), "same clearance -> no clearance_changed")
	check_eq(_duty_ids(PlayerState.get_todays_duties()), ["duty_orders_r2"],
			"the day's duties are rebuilt for the new occupation")
	check_eq(_calls("duty_assigned"), [["duty_orders_r2", "volume", 18]], "duty_assigned emitted")
	PlayerState.set_occupation("security_guard", "lateral")
	check_eq(_calls("clearance_changed"), [[1, 3]], "clearance_changed(1, 3)")
	check_eq(PlayerState.get_todays_duties().size(), 3, "security guard: three rounds")
	PlayerState.set_occupation("no_such_job", "test")
	check_eq(PlayerState.get_occupation_id(), "security_guard", "unknown occupation ignored")
	_clear()
	EventBus.occupation_changed.emit("security_guard", START_OCCUPATION, "demotion")
	check_eq(PlayerState.get_occupation_id(), START_OCCUPATION,
			"an occupation_changed emitted by another system (Company) is adopted")
	check_eq(_calls("occupation_changed").size(), 1, "PlayerState does not re-emit it")
	check_eq(_calls("clearance_changed"), [[3, 1]], "adopting still emits clearance_changed")


func _test_inventory_capacity() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	check(PlayerState.add_item("food_basic"), "add food")
	check(PlayerState.add_item("food_basic"), "a stackable item shares its slot")
	check_eq(PlayerState.get_free_slots(), 5, "two sandwiches use one slot")
	for item_id: String in ["keys_basic", "stamp", "executive_suit", "stellar_shoes", "balaclava"]:
		check(PlayerState.add_item(item_id), "add %s" % item_id)
	check_eq(PlayerState.get_free_slots(), 0, "8 slots full")
	check(not PlayerState.add_item("lockpick"), "the 9th distinct item does not fit")
	check(not PlayerState.has_item("lockpick"), "the rejected item is not in the inventory")
	check(PlayerState.add_item("food_basic"), "a stackable already carried still fits when full")
	check_eq(PlayerState.get_item_count("food_basic"), 3, "three units in one slot")
	check_eq(_calls("inventory_changed").size(), 8, "inventory_changed only for accepted items")
	check(not PlayerState.add_item("flashlight"), "post tools (kind post_tool) cannot be picked up")
	var cash: int = Database.get_item("cash_small").value
	var money: int = PlayerState.get_money()
	check(PlayerState.add_item("cash_small"), "ordinary cash is accepted even when full")
	check_eq(PlayerState.get_money(), money + cash, "ordinary cash becomes money")
	check(not PlayerState.has_item("cash_small"), "cash does not occupy a slot")
	check(PlayerState.remove_item("food_basic"), "remove one unit")
	check_eq(PlayerState.get_item_count("food_basic"), 2, "stack decremented")
	check(not PlayerState.remove_item("lockpick"), "removing an absent item fails")


func _test_inventory_categories() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.add_item("balaclava")
	check(PlayerState.has_hot_items(), "a balaclava is compromising (§11.3)")
	PlayerState.add_item("product_pair")
	PlayerState.add_item("product_pair")
	check_eq(PlayerState.get_hot_item_count(), 3, "hot units counted: balaclava + 2 pairs")
	PlayerState.add_item("food_premium")
	check_eq(PlayerState.get_hot_item_count(), 3, "food is ordinary")
	PlayerState.remove_item("balaclava")
	check_eq(PlayerState.get_hot_item_count(), 2, "removing the balaclava")
	PlayerState.add_item("unregistered_gadget")
	check_eq(PlayerState.get_hot_item_count(), 3,
			"uncatalogued ids fall back to inventario.categoria_por_defecto (compromising)")
	check(not InventoryRules.is_compromising("food_unregistered"),
			"uncatalogued ids with an ordinary prefix are ordinary")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("cleaner", "lateral")
	PlayerState.add_item("uniform_cleaning")
	check(not PlayerState.has_hot_items(), "the cleaner's own issued uniform is not compromising")
	check_eq(PlayerState.get_inventory().back().category, "ordinary",
			"get_inventory reports issued material as ordinary")
	PlayerState.set_occupation(START_OCCUPATION, "lateral")
	check(PlayerState.has_hot_items(), "a uniform kept after leaving the post is compromising")


func _test_duties() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	PlayerState.complete_duty(START_DUTY, 0.8, "honest")
	check_eq(_calls("duty_completed"), [[START_DUTY, 0.8, "honest"]],
			"duty_completed(id, quality, method)")
	check(PlayerState.get_pending_duties().is_empty(), "no pending duties after completing")
	check_eq(PlayerState.get_duty(START_DUTY)["status"], "completed", "status completed")
	PlayerState.complete_duty(START_DUTY, 1.0, "honest")
	PlayerState.fail_duty(START_DUTY)
	check_eq(_calls("duty_completed").size() + _calls("duty_failed").size(), 1,
			"a finished duty cannot be completed or failed again")
	GameClock.advance_to_next_day()
	check_eq(_duty_ids(PlayerState.get_pending_duties()), [START_DUTY], "day 2 has a fresh duty")
	check_eq(_calls("duty_assigned").back(), [START_DUTY, "volume", 18], "duty_assigned on day 2")
	PlayerState.modify_reputation(50.0, "setup")
	_clear()
	PlayerState.fail_duty(START_DUTY)
	check_eq(_calls("duty_failed"), [[START_DUTY, "warning"]], "first failure: warning")
	check_eq(PlayerState.get_consecutive_failures(), 1, "one consecutive failure")
	check_near(PlayerState.get_reputation(), 42.0, 0.0001,
			"a failed duty costs deberes.penalizacion_reputacion_fallo (-8) reputation")


func _test_duty_deadlines() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	GameClock.advance_minutes(9.0 * 60.0)
	check_eq(_calls("duty_deadline_warned"), [[START_DUTY, 1.0]],
			"one hour before the 18:00 deadline the duty is warned (§15.6)")
	check_eq(PlayerState.get_pending_duties().size(), 1, "still pending at 17:00")
	GameClock.advance_minutes(60.0)
	check_eq(_calls("duty_failed"), [[START_DUTY, "warning"]], "at 18:00 the pending duty fails")
	check_eq(PlayerState.get_duty(START_DUTY)["status"], "failed", "status failed")
	new_run(DEFAULT_SEED, false)
	GameClock.advance_minutes(9.5 * 60.0)
	_clear()
	PlayerState.set_occupation("order_filer", "promotion")
	check_eq(_calls("duty_deadline_warned"), [["duty_orders_r2", 0.5]],
			"a duty assigned at 17:30 (deadline 18:00) is warned at once with 0.5 h left (§15.6)")
	GameClock.advance_minutes(30.0)
	check_eq(_calls("duty_deadline_warned").size(), 1, "the warning is not repeated")
	check_eq(_calls("duty_failed"), [["duty_orders_r2", "warning"]], "…and it fails at 18:00")


func _test_failure_ladder() -> void:
	check_eq([Database.get_balance_int("deberes.fallos_para_aviso"),
			Database.get_balance_int("deberes.fallos_para_descenso"),
			Database.get_balance_int("deberes.fallos_para_expulsion")], [1, 3, 5],
			"balance: warning at 1, demotion at 3, expulsion at 5 failed days")
	new_run(DEFAULT_SEED, false)
	_clear()
	for _day: int in 5:
		PlayerState.fail_duty(START_DUTY)
		GameClock.advance_to_next_day()
	check_eq(_consequences(), ["warning", "warning", "demotion", "warning", "expulsion"],
			"failed days escalate: demotion once when the streak reaches 3 (it survives the"
			+ " demotion, so day 4 is a warning), expulsion at 5 (§4.4 incumplimiento reiterado)")
	PlayerState.complete_duty(START_DUTY, 1.0, "honest")
	GameClock.advance_to_next_day()
	check_eq(PlayerState.get_consecutive_failures(), 0, "a clean day resets the failure streak")
	PlayerState.fail_duty(START_DUTY)
	GameClock.advance_to_next_day()
	PlayerState.fail_duty(START_DUTY)
	PlayerState.set_occupation("senior_accountant", "lateral")
	check_eq(PlayerState.get_consecutive_failures(), 2,
			"the streak of failed days survives an occupation change")
	GameClock.advance_to_next_day()
	check_eq(PlayerState.get_consecutive_failures(), 2,
			"a jornada with no duties (monthly-only post) is neutral")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("eternal_intern", "demotion")
	_clear()
	PlayerState.fail_duty("duty_errands_r0")
	check_eq(_calls("duty_failed"), [["duty_errands_r0", "expulsion"]],
			"failing at R0 means expulsion (fail_penalty expulsion, §4.4)")


## Several duties in one jornada count as ONE failed day, and at most one demotion per day.
func _test_multi_duty_days() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("ceo", "test")
	check_eq(_duty_ids(PlayerState.get_pending_duties()),
			["duty_share_price_target_r33", "duty_crisis_management_r33"],
			"CEO on day 1: the two daily duties (the quarterly board only on quarter-closing days)")
	_clear()
	GameClock.advance_minutes(10.0 * 60.0)
	check_eq(_consequences(), ["warning", "warning"], "CEO misses day 1: two warnings, no demotion")
	check_eq(PlayerState.get_consecutive_failures(), 1, "one failed day, not two failures")
	GameClock.advance_to_next_day()
	_clear()
	GameClock.advance_minutes(10.0 * 60.0)
	check_eq(_consequences(), ["demotion", "warning"],
			"second missed day: demotion_risk streak 2 -> one demotion; the other is a warning")
	check_eq(PlayerState.get_consecutive_failures(), 2, "two failed days")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("security_guard", "test")
	_clear()
	GameClock.advance_minutes(15.0 * 60.0)
	check_eq(_calls("duty_failed"), [["duty_guard_round_morning_r10", "warning"],
			["duty_guard_round_afternoon_r10", "warning"], ["duty_closing_round_r10", "expulsion"]],
			"guard: rounds due 13:00/18:00 warn, the forgotten 22:00 closing round expels (§23.6)")
	check_eq(PlayerState.get_consecutive_failures(), 1, "three failures in one day = one failed day")


## Periodic duties (subtype prefix weekly_/monthly_/quarterly_) are only due on closing days.
func _test_periodic_duties() -> void:
	var r13: Dictionary = Database.get_occupation("senior_accountant").duties[0]
	var r28: Dictionary = Database.get_occupation("cfo").duties[0]
	var r11: Dictionary = Database.get_occupation("junior_shoe_designer").duties[0]
	var r1: Dictionary = Database.get_occupation(START_OCCUPATION).duties[0]
	check_eq([PlayerState.get_duty_frequency(r13), PlayerState.get_duty_frequency(r28),
			PlayerState.get_duty_frequency(r11), PlayerState.get_duty_frequency(r1)],
			["monthly", "quarterly", "weekly", "daily"],
			"frequency inferred from the subtype (monthly_close, quarterly_results, weekly_sketches)")
	check_eq(_days_with_duties("senior_accountant", 21), [20],
			"R13 monthly close: only on day 20 (jornadas_por_mes), not on ordinary days")
	check_eq(_days_with_duties("cfo", 26), [25],
			"R28 quarterly results: only on day 25 (jornadas_por_trimestre)")
	check_eq(_days_with_duties("junior_shoe_designer", 11), [5, 10],
			"R11 weekly sketches: days 5 and 10 (jornadas_por_semana)")
	check_eq(_days_with_duties(START_OCCUPATION, 3), [1, 2, 3], "R1 emails: every day")


## demotion_risk: the same periodic duty failed fallos_para_descenso_riesgo (2) times -> demotion
## ("dos trimestres deficientes suponen degradación", §23.7).
func _test_demotion_risk() -> void:
	check_eq(Database.get_balance_int("deberes.fallos_para_descenso_riesgo"), 2,
			"balance: two deficient periods of a demotion_risk duty")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("cfo", "test")
	_clear()
	_advance_to_day(25)
	check(_calls("duty_failed").is_empty(), "no quarterly failure before day 25")
	GameClock.advance_minutes(10.0 * 60.0)
	_advance_to_day(50)
	GameClock.advance_minutes(10.0 * 60.0)
	check_eq(_calls("duty_failed"), [["duty_quarterly_results_r28", "warning"],
			["duty_quarterly_results_r28", "demotion"]],
			"CFO: first deficient quarter -> warning, second -> demotion")
	check_eq(PlayerState.get_duty_failure_streak("duty_quarterly_results_r28"), 2, "streak 2")
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("b10_director", "test")
	_clear()
	PlayerState.fail_duty("duty_block_sales_r20")
	GameClock.advance_to_next_day()
	PlayerState.complete_duty("duty_block_sales_r20", 1.0, "honest")
	check_eq(PlayerState.get_duty_failure_streak("duty_block_sales_r20"), 0,
			"completing a demotion_risk duty resets its streak")
	GameClock.advance_to_next_day()
	PlayerState.fail_duty("duty_block_sales_r20")
	check_eq(_consequences(), ["warning", "warning"],
			"fail, succeed, fail: not consecutive -> no demotion")


## A listener that demotes synchronously while the day closes (DutySystem -> Company) must not make
## PlayerState rebuild the new day twice.
func _test_rebuild_during_rollover() -> void:
	new_run(DEFAULT_SEED, false)
	GameClock.set_time(1, 5, 30)
	var demote: Callable = func(_id: String, _consequence: String) -> void:
		EventBus.occupation_changed.emit(PlayerState.get_occupation_id(), "order_filer", "demotion")
	EventBus.duty_failed.connect(demote)
	_clear()
	GameClock.advance_minutes(30.0)
	EventBus.duty_failed.disconnect(demote)
	check_eq(_calls("duty_failed"), [[START_DUTY, "warning"]],
			"the duty left pending at the 06:00 rollover fails once")
	check_eq(_calls("duty_assigned"), [["duty_orders_r2", "volume", 18]],
			"day 2's duty of the new occupation is assigned exactly once")
	check_eq(_duty_ids(PlayerState.get_todays_duties()), ["duty_orders_r2"],
			"today's list belongs to the new occupation")


func _test_meters() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	var start: float = PlayerState.get_reputation()
	PlayerState.modify_reputation(30.0, "presentation")
	check_eq(_calls("reputation_changed"), [[start, start + 30.0]], "reputation_changed(old, new)")
	PlayerState.modify_reputation(500.0, "test")
	check_near(PlayerState.get_reputation(), 100.0, 0.0001, "reputation is capped at 100")
	PlayerState.modify_reputation(-500.0, "test")
	check_near(PlayerState.get_reputation(), 0.0, 0.0001, "reputation floor is 0")
	PlayerState._set_suspicion_from_beliefnet(42.5)
	check_near(PlayerState.get_suspicion(), 42.5, 0.0001, "suspicion cache set by BeliefNet")
	EventBus.suspicion_changed.emit(42.5, 61.0)
	check_near(PlayerState.get_suspicion(), 42.5, 0.0001,
			"only BeliefNet's exclusive setter writes the cache: a stray suspicion_changed does not")


func _test_tracking_facade() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	var blood: int = Tracking.get_axis("blood")
	PlayerState.add_tracking("blood", 10)
	check_eq(_calls("tracking_event_recorded"), [["blood", 10, "player_state"]],
			"add_tracking emits tracking_event_recorded(axis, amount, source)")
	check_eq(PlayerState.get_tracking("blood"), blood + 10,
			"Tracking accumulates the event: the blood axis rose by 10 (§12.8)")
	check_eq(PlayerState.get_dominant_axis(), "blood", "blood 10 vs 0 elsewhere: blood dominates")
	PlayerState.add_tracking("gold", 15)
	check_eq([PlayerState.get_tracking("gold"), PlayerState.get_dominant_axis()], [15, "gold"],
			"gold 15 overtakes blood 10 as the dominant axis")
	PlayerState.add_tracking("ruin", 40)
	check_eq([PlayerState.get_tracking("ruin"), PlayerState.get_dominant_axis()], [40, "gold"],
			"ruin accumulates but is not a style axis")
	PlayerState.add_tracking("glitter", 5)
	PlayerState.add_tracking("gold", 0)
	check_eq(_calls("tracking_event_recorded").size(), 3, "unknown axes and zero amounts ignored")
	check_eq(PlayerState.get_tracking("gold"), 15, "…and change nothing")


func _test_position_and_identity() -> void:
	_clear()
	EventBus.room_entered.emit("p3_pantry", true)
	EventBus.room_entered.emit("wing_3b", false)
	check_eq(PlayerState.get_room(), "p3_pantry", "room follows room_entered(room, true) only")
	EventBus.room_exited.emit("p3_pantry", true)
	check_eq(PlayerState.get_room(), "", "room cleared on exit")
	EventBus.floor_changed.emit(3, 5)
	check_eq(PlayerState.get_floor(), 5, "floor follows floor_changed")
	PlayerState.set_disguise("uniform_cleaning")
	PlayerState.set_disguise("uniform_cleaning")
	check_eq(_calls("disguise_changed"), [["uniform_cleaning"]], "disguise_changed once")
	check_eq(PlayerState.get_disguise(), "uniform_cleaning", "get_disguise")
	check(not PlayerState.get_player_name().is_empty(), "a default player name exists")
	PlayerState.set_player_name("  Ana Ruiz ")
	check_eq(PlayerState.get_player_name(), "Ana Ruiz", "the chosen name is kept (trimmed)")


func _test_save_load() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation("order_filer", "promotion")
	PlayerState.add_money(333, "test")
	PlayerState.modify_reputation(12.5, "test")
	PlayerState._set_suspicion_from_beliefnet(17.25)
	PlayerState.add_item("balaclava")
	PlayerState.add_item("foreign_document")
	PlayerState.add_item("foreign_document")
	PlayerState.add_item("food_basic")
	check(PlayerState.stash_item("food_basic", "hide_3b_desk", "wing_3b"), "setup: stash")
	PlayerState.complete_duty("duty_orders_r2", 0.7, "assist")
	GameClock.advance_to_next_day()
	PlayerState.fail_duty("duty_orders_r2")
	PlayerState.set_disguise("uniform_security")
	PlayerState.set_player_name("Ana")
	var snapshot: Dictionary = PlayerState.save_state()
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	new_run(DEFAULT_SEED, false)
	check(_canonical(PlayerState.save_state()) != _canonical(snapshot), "a new run differs")
	PlayerState.load_state(parsed)
	check_eq(_canonical(PlayerState.save_state()), _canonical(snapshot),
			"save -> JSON -> load reproduces the exact state")
	check_eq([PlayerState.get_occupation_id(), PlayerState.get_money()], ["order_filer", 453],
			"occupation and money restored")
	check_eq(PlayerState.get_item_count("foreign_document"), 2, "stacked items restored")
	check_eq(PlayerState.get_hot_item_count(), 3, "hot items restored")
	check(PlayerState.get_stashes().has("hide_3b_desk"), "stashes restored")
	check_eq(PlayerState.get_duty("duty_orders_r2")["status"], "failed", "duties restored")
	check_eq([PlayerState.get_consecutive_failures(),
			PlayerState.get_duty_failure_streak("duty_orders_r2")], [1, 1],
			"failure streaks restored")
	check_eq(PlayerState.get_player_name(), "Ana", "name restored")
	check(PlayerState.retrieve_item("hide_3b_desk", "food_basic"), "restored stash is usable")


# ─── Utilidades ────────────────────────────────────────────────

const LOGGED_SIGNALS: Array[String] = [
	"money_changed", "occupation_changed", "clearance_changed", "reputation_changed",
	"inventory_changed", "duty_assigned", "duty_completed", "duty_failed",
	"duty_deadline_warned", "tracking_event_recorded", "disguise_changed",
]
var _handlers: Dictionary = {}


func _connect_bus() -> void:
	for signal_name: String in LOGGED_SIGNALS:
		var handler: Callable = func(...args: Array) -> void: _record(signal_name, args)
		_handlers[signal_name] = handler
		EventBus.connect(signal_name, handler)


func _disconnect_bus() -> void:
	for signal_name: String in _handlers:
		EventBus.disconnect(signal_name, _handlers[signal_name])


func _record(signal_name: String, args: Array) -> void:
	if not _log.has(signal_name):
		_log[signal_name] = []
	(_log[signal_name] as Array).append(args)


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()


func _consequences() -> Array[String]:
	var out: Array[String] = []
	for call: Array in _calls("duty_failed"):
		out.append(str(call[1]))
	return out


func _advance_to_day(day: int) -> void:
	while GameClock.get_day() < day:
		GameClock.advance_to_next_day()


## Fresh run in `occupation_id`; days 1..last_day on which it had any duty assigned.
func _days_with_duties(occupation_id: String, last_day: int) -> Array[int]:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(occupation_id, "test")
	var days: Array[int] = []
	while GameClock.get_day() <= last_day:
		if not PlayerState.get_todays_duties().is_empty():
			days.append(GameClock.get_day())
		GameClock.advance_to_next_day()
	return days


func _inventory_ids() -> Array[String]:
	var out: Array[String] = []
	for item: ItemData in PlayerState.get_inventory():
		out.append(item.id)
	return out


func _duty_ids(duties: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for duty: Dictionary in duties:
		out.append(str(duty["id"]))
	return out


## JSON canónico (claves ordenadas; números normalizados por el ida y vuelta de JSON).
func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)
