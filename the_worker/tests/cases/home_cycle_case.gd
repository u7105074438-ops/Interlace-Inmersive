# home_cycle_case.gd — Cuerpo de test_home_cycle: gastos diarios (§15.4), salario, compras en supermercado y tienda de ropa, comidas de despensa o compradas, comida robada sin coste, cuándo se puede dormir, secuencia de dormir (resumen → cambio de jornada → guardado → desayuno), tiempo de las comidas, carga (nodo presente y nodo creado después de load_run), jornada sin dormir e inanición (THE GAP).
# PROPIETARIO DE: nada (los nodos HomeCycle y Police que crea viven solo durante el caso; su carpeta de guardado se borra al final).
# ESCUCHA: money_changed, crime_committed, day_summary_ready, day_advanced, game_over, notebook_entry_added (registro durante el caso).
extends TestCase

const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
const STORAGE_FORMAT := "user://test_home_cycle_%d"
const FLAT := "player_flat"
const STREET := "street"
const SUPERMARKET := "supermarket"
const CLOTHES := "clothes_shop"
const KITCHEN := "cafeteria_kitchen"
const PANTRY := "p3_pantry"
const MINUTES_PER_HOUR := 60.0
const WATCHED: Array[String] = ["money_changed", "crime_committed", "day_summary_ready",
		"day_advanced", "game_over", "notebook_entry_added"]

var _dir: String = ""
var _cycle: HomeCycle = null
var _police: Police = null
var _log: Fixtures.SignalLog = null
var _order: Array[String] = []
var _summary_day: int = -1
var _saved_at_summary: bool = true
var _money_after_sleep: int = 0
var _minutes_after_sleep: float = 0.0


func run_case() -> void:
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_cycle = HomeCycle.new()
	add_child(_cycle)
	_police = Police.new()
	add_child(_police)
	_log = Fixtures.SignalLog.new().watch(WATCHED)
	_test_expenses_and_wage()
	_test_shopping()
	_test_meals_and_stolen_food()
	_test_can_sleep()
	_test_sleep_sequence()
	_test_load_repeats_breakfast()
	_test_late_node_repeats_breakfast()
	_test_day_without_sleep()
	_test_starvation()
	_test_debt_and_vouchers()
	_test_mid_day_demotion()
	_log.stop()
	_cleanup()
	_cycle.queue_free()
	_police.queue_free()
	await get_tree().process_frame


## attended: el jugador pasó por el edificio esta jornada (condición del salario, §6.5).
func _fresh(hour: int, attended: bool = true) -> void:
	new_run(DEFAULT_SEED)
	# Saldo de prueba de 120 € (economia.dinero_inicial es 2 €: §6.5, 26 jornadas hasta 210 €).
	PlayerState.add_money(120 - PlayerState.get_money(), "test")
	SaveSystem.reset_for_new_run()
	GameClock.set_time(1, hour, 0)
	_police.reset_for_new_run()
	_cycle.reset_for_new_run()
	if attended:
		EventBus.room_entered.emit("turnstiles", true)
	EventBus.room_entered.emit(FLAT, true)
	_log.clear()


func _advance_to(hour: int) -> void:
	var now: float = GameClock.get_hour() * MINUTES_PER_HOUR + GameClock.get_minute()
	var target: float = hour * MINUTES_PER_HOUR
	GameClock.advance_minutes(fposmod(target - now, 24.0 * MINUTES_PER_HOUR))


func _reasons(signal_args: Array[Array]) -> Array[String]:
	var out: Array[String] = []
	for args: Array in signal_args:
		out.append(str(args[2]))
	return out


func _test_expenses_and_wage() -> void:
	_fresh(18, false)
	check_eq(PlayerState.get_daily_expenses(), 22, "R1 daily expenses: 5 + 10 + 7 = 22 € (§15.4)")
	var money: int = PlayerState.get_money()
	_advance_to(20)
	check_eq(PlayerState.get_money() - money, 0, "absent all day (never entered the building): no wage (§6.5)")
	_fresh(18)
	money = PlayerState.get_money()
	_advance_to(20)
	check_eq(PlayerState.get_money() - money, PlayerState.get_daily_wage(), "wage paid at 19:00 after going to work")
	check(_reasons(_log.all("money_changed")).has("wage"), "money reason 'wage'")
	_advance_to(22)
	check_eq(PlayerState.get_money() - money, PlayerState.get_daily_wage(), "only once per day")


func _test_shopping() -> void:
	_fresh(20)
	var money: int = PlayerState.get_money()
	var before: float = GameClock.get_total_minutes()
	check_eq(_cycle.buy("food_dinner", SUPERMARKET), HomeCycle.OK, "dinner bought at the supermarket")
	check_eq(money - PlayerState.get_money(), 10, "food_dinner costs 10 €")
	check(_reasons(_log.all("money_changed")).has("food"), "money reason 'food'")
	check_eq(PlayerState.get_item_count("food_dinner"), 1, "the food is in the inventory")
	check_eq(GameClock.get_total_minutes() - before, Database.get_balance_float("hogar.minutos_compra"),
			"shopping takes game time")
	check_eq(_cycle.buy("balaclava", SUPERMARKET), HomeCycle.ERR_NOT_SOLD, "no balaclavas at the supermarket")
	money = PlayerState.get_money()
	check_eq(_cycle.buy("balaclava", CLOTHES), HomeCycle.OK, "balaclava bought at the clothes shop")
	check_eq(money - PlayerState.get_money(), Database.get_balance_int("economia.precio_pasamontanas"),
			"balaclava price from economia.precio_pasamontanas (45)")
	check_eq(_cycle.buy("executive_suit", CLOTHES), HomeCycle.ERR_FUNDS, "a 1800 € suit is out of reach")
	var prices: Dictionary = {}
	for row: Dictionary in _cycle.get_shop_items(CLOTHES):
		prices[str(row["item_id"])] = int(row["price"])
	check_eq(int(prices.get("executive_suit", 0)), 1800, "the shop lists the suit at 1800 €")


func _test_meals_and_stolen_food() -> void:
	_fresh(20)
	_cycle.buy("food_dinner", SUPERMARKET)
	var money: int = PlayerState.get_money()
	var before: float = GameClock.get_total_minutes()
	var dinner: Dictionary = _cycle.eat(HomeCycle.MEAL_DINNER)
	check(bool(dinner["eaten"]) and str(dinner["source"]) == HomeCycle.SOURCE_STOCK, "dinner from the fridge")
	check_near(GameClock.get_total_minutes() - before,
			Database.get_balance_float("hogar.minutos_comida.dinner"), 0.001, "dinner takes game time")
	before = GameClock.get_total_minutes()
	_cycle.eat(HomeCycle.MEAL_DINNER)
	check_near(GameClock.get_total_minutes(), before, 0.001, "an already eaten meal takes no time")
	check_eq(PlayerState.get_money(), money, "eating from stock costs nothing")
	check_eq(PlayerState.get_item_count("food_dinner"), 0, "the food was eaten")
	check_eq(int(_cycle.eat(HomeCycle.MEAL_DINNER)["cost"]), 0, "no second dinner")
	_log.clear()
	check_eq(_cycle.steal_food(KITCHEN), HomeCycle.OK, "food taken from the cafeteria kitchen")
	var crime: Array = _log.last("crime_committed")
	check(crime.size() == 3 and str(crime[0]) == "theft_small" and bool(crime[2]["food"])
			and not bool(crime[2]["leaves_record"]), "a small theft that opens no investigation")
	check_eq(_cycle.steal_food(STREET), HomeCycle.ERR_NO_SOURCE, "no food source in the street")
	check_eq(_cycle.get_food_stock(HomeCycle.MEAL_BREAKFAST), 1, "stolen food counts as breakfast stock")
	var breakfast: Dictionary = _cycle.eat(HomeCycle.MEAL_BREAKFAST)
	check(str(breakfast["source"]) == HomeCycle.SOURCE_STOCK and PlayerState.get_money() == money,
			"stolen food removes the meal cost (§22.4)")
	_fresh(20)
	money = PlayerState.get_money()
	var bought: Dictionary = _cycle.eat(HomeCycle.MEAL_DINNER)
	check(str(bought["source"]) == HomeCycle.SOURCE_BOUGHT, "no food at home: the meal is bought")
	check_eq(money - PlayerState.get_money(), _cycle.meal_price(HomeCycle.MEAL_DINNER), "at its price")
	check_eq(_cycle.meal_price(HomeCycle.MEAL_DINNER), 10, "dinner = midpoint of 8-12 €")


func _test_can_sleep() -> void:
	_fresh(14)
	check_eq(_cycle.can_sleep(), HomeCycle.ERR_NOT_NIGHT, "no sleeping at 14:00")
	GameClock.set_time(1, 22, 0)
	check_eq(_cycle.can_sleep(), HomeCycle.OK, "22:00 at home: bed time")
	EventBus.room_entered.emit(STREET, true)
	check_eq(_cycle.can_sleep(), HomeCycle.ERR_NOT_HOME, "only in the player's flat")
	EventBus.room_entered.emit(FLAT, true)
	_police.dispatch(STREET)
	check_eq(_cycle.can_sleep(), HomeCycle.ERR_POLICE, "not with the police on the way")
	_police.reset_for_new_run()
	GameClock.set_time(1, 2, 0)
	check_eq(_cycle.can_sleep(), HomeCycle.OK, "02:00 still counts as the night")
	check_eq(HomeCycle.reason_key(HomeCycle.ERR_NOT_NIGHT), "HOME_ERR_NOT_NIGHT", "reason keys")


func _test_sleep_sequence() -> void:
	_fresh(18)
	_advance_to(22)
	SaveSystem.delete_run()
	_order.clear()
	EventBus.day_summary_ready.connect(_on_summary)
	EventBus.day_advanced.connect(_on_day)
	var result: Dictionary = _cycle.sleep()
	EventBus.day_summary_ready.disconnect(_on_summary)
	EventBus.day_advanced.disconnect(_on_day)
	check(bool(result["ok"]), "the player sleeps")
	check_eq(_order, ["summary", "advanced"] as Array[String], "day_summary_ready BEFORE the day advances")
	check_eq(_summary_day, 1, "the summary is emitted while the closing day is still day 1")
	check(not _saved_at_summary, "nothing is saved before the summary")
	var summary: Dictionary = result["summary"]
	check_eq(int(summary["day"]), 1, "summary.day = closing day")
	check_eq(int(summary["income"]), PlayerState.get_daily_wage(), "summary income = the wage")
	check_eq(int(summary["expenses"]), PlayerState.get_daily_expenses()
			- _cycle.meal_price(HomeCycle.MEAL_BREAKFAST),
			"summary expenses = 22 € minus the breakfast never taken (§4.2: not billed afterwards)")
	check(summary.has("reputation") and summary.has("suspicion_delta") and summary.has("meals"),
			"the summary carries the meters")
	check_eq(GameClock.get_day(), 2, "the day advanced")
	check_eq(GameClock.get_hour(), Database.get_balance_int("tiempo.hora_inicio_jornada"), "woke up at 08:00")
	check(bool(result["saved"]) and SaveSystem.run_exists(), "sleeping saved the run (§12.7)")
	var header: Dictionary = SaveSystem.read_verified(SaveSystem.get_run_path(), "systems")
	check_eq(int(header.get("day", 0)), 2, "the save was written after the day advanced")
	check(bool(result["breakfast"]["eaten"]) and _cycle.has_eaten(HomeCycle.MEAL_BREAKFAST),
			"breakfast the next morning")
	check_eq(int(summary["money"]) - PlayerState.get_money(), _cycle.meal_price(HomeCycle.MEAL_BREAKFAST),
			"breakfast is paid after the save, on the new day")
	_money_after_sleep = PlayerState.get_money()


func _on_summary(summary: Dictionary) -> void:
	_order.append("summary")
	_summary_day = GameClock.get_day()
	_saved_at_summary = SaveSystem.run_exists()
	check_eq(int(summary.get("day", 0)), _summary_day, "summary day matches the clock at emission")


func _on_day(_day: int) -> void:
	_order.append("advanced")


## El guardado es previo al desayuno: al cargar se desayuna otra vez y el dinero cuadra.
func _test_load_repeats_breakfast() -> void:
	_minutes_after_sleep = GameClock.get_total_minutes()
	check(SaveSystem.load_run(), "the run loads")
	GameClock.pause()
	check_eq(GameClock.get_day(), 2, "loaded on day 2")
	check(_cycle.has_eaten(HomeCycle.MEAL_BREAKFAST), "breakfast is repeated after loading")
	check_eq(PlayerState.get_money(), _money_after_sleep, "the money matches the uninterrupted night")
	check_near(GameClock.get_total_minutes(), _minutes_after_sleep, 0.001,
			"and so does the clock (breakfast time included)")


## BUILD_NOTES §2: un HomeCycle creado DESPUÉS de load_run reclama su estado en _ready y repite
## el desayuno igual (no oye run_loaded).
func _test_late_node_repeats_breakfast() -> void:
	remove_child(_cycle)
	_cycle.free()
	check(SaveSystem.load_run(), "the run loads with no HomeCycle in the tree")
	GameClock.pause()
	_cycle = HomeCycle.new()
	add_child(_cycle)
	check(_cycle.has_eaten(HomeCycle.MEAL_BREAKFAST), "the late node repeats breakfast")
	check_eq(PlayerState.get_money(), _money_after_sleep, "money matches the uninterrupted night")
	check_near(GameClock.get_total_minutes(), _minutes_after_sleep, 0.001, "and the clock too")


func _test_day_without_sleep() -> void:
	_fresh(20)
	var money: int = PlayerState.get_money()
	_advance_to(7)
	check_eq(GameClock.get_day(), 2, "the day advanced at 06:00 without sleeping")
	check_eq(PlayerState.get_money() - money, PlayerState.get_daily_wage() - PlayerState.get_daily_expenses()
			+ _cycle.meal_price(HomeCycle.MEAL_BREAKFAST),
			"a day costs rent, status and dinner even without sleeping; an untaken breakfast is not billed")
	_fresh(20)
	_cycle.steal_food(PANTRY)
	_cycle.steal_food(PANTRY)
	money = PlayerState.get_money()
	_advance_to(7)
	var rent: int = Database.get_balance_int("economia.alquiler_diario")
	check_eq(PlayerState.get_money() - money, PlayerState.get_daily_wage() - rent,
			"with stolen food only the rent is paid")
	check_eq(PlayerState.get_item_count("food_basic"), 1,
			"settling eats only the dinner; the other stolen meal stays in the pantry")


func _drain() -> void:
	PlayerState.spend_money(PlayerState.get_money(), "bribe")


func _test_starvation() -> void:
	_fresh(18)
	_advance_to(20)
	_drain()
	_advance_to(7)
	check_eq(_cycle.get_hungry_days(), 1, "a day without food")
	check_eq(_log.count("game_over"), 0, "one hungry day is survivable")
	var warnings: int = 0
	for args: Array in _log.all("notebook_entry_added"):
		if str(args[1]) == HomeCycle.NOTE_HUNGRY:
			warnings += 1
	check_eq(warnings, 1, "the notebook warns about hunger")
	check(_log.all("notebook_entry_added").any(func(a: Array) -> bool:
			return str(a[1]) == HomeCycle.NOTE_RENT_UNPAID), "and about the unpaid rent")
	EventBus.room_entered.emit("turnstiles", true)
	_advance_to(20)
	_advance_to(7)
	check_eq(_cycle.get_hungry_days(), 0, "a fed day resets the count")
	_advance_to(20)
	_drain()
	_advance_to(7)
	var saved: Dictionary = _cycle.save_state()
	var copy: HomeCycle = HomeCycle.new()
	copy.load_state(saved)
	check_eq(copy.get_hungry_days(), 1, "save/load keeps the hungry days")
	copy.free()
	_advance_to(20)
	_drain()
	_advance_to(7)
	var over: Array = _log.last("game_over")
	check(over.size() == 3 and str(over[0]) == "starvation",
			"%d days without food: game_over(starvation)" % Database.get_balance_int("hogar.jornadas_sin_comer_inanicion"))
	check_eq(str(over[1]) if over.size() == 3 else "", "the_gap", "starvation ends as THE GAP")
	check_eq(_cycle.can_sleep(), HomeCycle.ERR_GAME_OVER, "no sleeping after the end")


## §4.4: la renta impagada se arrastra y se cobra antes que la comida; §22 R0: vales de comida.
func _test_mid_day_demotion() -> void:
	_fresh(17)
	var wage: int = PlayerState.get_daily_wage()
	var duty_id: String = str(PlayerState.get_todays_duties()[0]["id"]) \
			if not PlayerState.get_todays_duties().is_empty() else ""
	if not duty_id.is_empty():
		PlayerState.fail_duty(duty_id)
	PlayerState.set_occupation("eternal_intern", "demotion")
	var summary: Dictionary = _cycle.build_day_summary()
	if not duty_id.is_empty():
		check(Array(summary["missed_duties"]).has(duty_id),
				"a duty failed before the demotion stays in the day summary")
	check_eq(Array(summary["occupation_changes"]).size(), 1, "the demotion is in the day summary")
	_advance_to(20)
	check_eq(int(_cycle.build_day_summary()["income"]), wage, "the day is paid at the rank it was worked at")


func _test_debt_and_vouchers() -> void:
	_fresh(18)
	_advance_to(20)
	_drain()
	_advance_to(7)
	var debt: int = _cycle.get_debt()
	check(debt > 0, "unpaid rent becomes arrears")
	PlayerState.add_money(debt, "test")
	EventBus.room_entered.emit("turnstiles", true)
	_advance_to(20)
	_drain()
	PlayerState.add_money(debt + Database.get_balance_int("economia.alquiler_diario"), "test")
	_advance_to(7)
	check_eq(_cycle.get_debt(), 0, "arrears and rent are paid first")
	# Intern from the start of the day (a mid-day change is paid at the rank the day began with).
	_fresh(18, false)
	PlayerState.set_occupation("eternal_intern", "test")
	EventBus.room_entered.emit("turnstiles", true)
	_drain()
	_advance_to(20)
	check_eq(PlayerState.get_money(), 0, "the intern's wage is not cash (§22 R0 vouchers)")
	check_eq(_cycle.get_vouchers(), PlayerState.get_daily_wage(), "it arrives as meal vouchers")
	_advance_to(7)
	check(_cycle.has_eaten(HomeCycle.MEAL_BREAKFAST) or _cycle.get_hungry_days() == 0,
			"vouchers feed the intern")


func _cleanup() -> void:
	SaveSystem.delete_run()
	DirAccess.remove_absolute(_dir)
	SaveSystem.set_storage_dir("")
	SaveSystem.reset_for_new_run()
	check(not DirAccess.dir_exists_absolute(_dir), "the case leaves no files behind")
