# game_clock_case.gd — Cuerpo de test_game_clock (§21, PASO 5): franjas §5.6, jornada, cierres §15.1, velocidad.
# PROPIETARIO DE: nada.
# ESCUCHA: time_band_changed, day_advanced, hour_passed, week_closed, month_closed, quarter_closed, time_skipped (conexión temporal).
extends TestCase

## Pasos de tiempo real simulados (60 fotogramas por segundo).
const FRAME := 1.0 / 60.0
const EXPECTED_BAND_CHANGES: Array[String] = [
	"work_morning", "lunch", "work_afternoon", "exit", "night", "arrival",
]
const MINUTES_PER_HOUR := 60.0

var _band_news: Array[String] = []
var _band_olds: Array[String] = []
var _days: Array[int] = []
var _day_hours: Array[int] = []
var _hours: Array[int] = []
var _skips: Array = []
## Registro ordenado de cierres y cambios de jornada: "week:1@5", "month:1@20", "day:21".
var _events: Array[String] = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded and a new run was created")
	_connect_bus()
	_test_initial_state()
	_test_full_day_awake()
	_test_after_midnight()
	_test_real_time_rates()
	_test_speed_multipliers()
	_test_sleep()
	_test_advance_to_band()
	_test_period_closures()
	_test_save_load()
	_disconnect_bus()


# ─── Escenarios ────────────────────────────────────────────────

func _test_initial_state() -> void:
	check_eq(GameClock.get_day(), 1, "a new run starts on day 1")
	check_eq(GameClock.get_time_string(), "08:00", "a new run starts at 08:00 (arrival)")
	check_eq(GameClock.get_current_band(), "arrival", "initial band is arrival")
	check(GameClock.is_working_hours(), "08:00 is within working hours")
	check_near(GameClock.hours_until_closing(), 11.0, 0.001, "11 hours until the 19:00 closing")
	check_eq([GameClock.get_week(), GameClock.get_month(), GameClock.get_quarter()], [1, 1, 1],
			"day 1 is week 1, month 1, quarter 1")
	check(GameClock.is_paused(), "the clock stays paused after reset until the world resumes it")
	GameClock._process(5.0)
	check_eq(GameClock.get_time_string(), "08:00", "_process does nothing while paused")
	GameClock.resume()
	GameClock._process(0.9)
	check_near(GameClock.get_day_minutes(), 481.0, 0.001,
			"resumed: 0.9 real s in arrival (0.9 real min per game hour) = 1 game minute")
	GameClock.pause()
	GameClock.advance_minutes(329.0)
	check_eq(GameClock.get_time_string(), "13:30", "advance_minutes steps game time exactly")
	check_near(GameClock.hours_until_closing(), 5.5, 0.001, "13:30 -> 5.5 hours until closing")


func _test_full_day_awake() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	var elapsed: float = 0.0
	var guard: int = 0
	while guard < 100000 and not (GameClock.get_day() == 2
			and GameClock.get_current_band() == "arrival"):
		GameClock.advance_real_seconds(FRAME)
		elapsed += FRAME
		guard += 1
	check_eq(_band_news, EXPECTED_BAND_CHANGES,
			"a full day emits the six bands in order (arrival -> ... -> night -> arrival)")
	check_eq(_band_olds, ["arrival", "work_morning", "lunch", "work_afternoon", "exit", "night"],
			"every time_band_changed old_band is the previous band")
	check_eq(_days, [2], "day_advanced is emitted exactly once in a full day")
	check_eq(_day_hours, [6], "awake all night: the day advances at 06:00")
	check_eq(_hours.size(), 24, "hour_passed fires once per game hour")
	check_eq([_hours.front(), _hours.back()], [9, 8], "hour_passed runs from 09 to 08 next day")
	check_near(elapsed, 540.0 + 13.0 * 30.0, 0.1,
			"real duration: 9 min office + 13 night hours at 0.5 real min each")


func _test_after_midnight() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	GameClock.advance_minutes(17.0 * MINUTES_PER_HOUR)
	check_eq([GameClock.get_day(), GameClock.get_hour()], [1, 1],
			"at 01:00 the game day is still day 1 (the day changes at 06:00 or on sleep)")
	check_eq(GameClock.get_current_band(), "night", "01:00 is night")
	check(not GameClock.is_working_hours(), "01:00 is outside working hours")
	check_near(GameClock.hours_until_closing(), 0.0, 0.001, "no hours until closing after 19:00")
	GameClock.advance_minutes(4.0 * MINUTES_PER_HOUR + 59.0)
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [1, "05:59"],
			"05:59 still belongs to day 1")
	GameClock.advance_minutes(1.0)
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [2, "06:00"],
			"the day advances at 06:00 when the player stays awake")
	check_eq(_days, [2], "only one day_advanced")


func _test_real_time_rates() -> void:
	var office: float = 0.0
	for band: String in ["arrival", "work_morning", "lunch", "work_afternoon", "exit"]:
		var hours: int = _band_hours(band)
		office += hours * Database.get_balance_float("tiempo.minutos_reales_por_hora_por_franja." + band)
	check_near(office, 9.0, 0.001, "balance: the office day 8:00-19:00 lasts 9 real minutes")
	var night: float = Database.get_balance_float("tiempo.minutos_reales_por_hora_por_franja.night")
	check_near(office + 4.0 * night, Database.get_balance_float("tiempo.minutos_reales_por_jornada"),
			0.001, "office + evening until 23:00 = minutos_reales_por_jornada (11)")
	new_run(DEFAULT_SEED, false)
	GameClock.advance_real_seconds(540.0)
	check_near(GameClock.get_day_minutes(), 19.0 * MINUTES_PER_HOUR, 0.01,
			"540 real seconds (one call crossing every band) take 08:00 to 19:00")
	check_eq(GameClock.get_time_string(), "19:00", "time string after the office day")
	GameClock.advance_real_seconds(120.0)
	check_eq(GameClock.get_time_string(), "23:00", "the evening 19:00-23:00 takes 2 real minutes")


func _test_speed_multipliers() -> void:
	new_run(DEFAULT_SEED, false)
	GameClock.advance_minutes(MINUTES_PER_HOUR)
	var computer: float = Database.get_balance_float("tiempo.velocidad_en_ordenador")
	check_near(computer, 0.4, 0.0001, "balance: computer speed is 0.4")
	GameClock.set_speed_multiplier(computer)
	GameClock.advance_real_seconds(60.0)
	check_near(GameClock.get_day_minutes(), 570.0, 0.01,
			"in the computer 60 real s advance 30 game minutes instead of 75")
	GameClock.set_speed_multiplier(0.0)
	check(GameClock.get_effective_speed() > 0.0, "a zero multiplier is clamped: never stops")
	var before: float = GameClock.get_day_minutes()
	GameClock.advance_real_seconds(10.0)
	check(GameClock.get_day_minutes() > before, "time still advances at the minimum multiplier")
	GameClock.set_speed_multiplier(computer)
	GameClock.set_accessibility_speed(0.5)
	check_near(GameClock.get_effective_speed(), 0.2, 0.0001,
			"accessibility speed multiplies with the computer speed")
	before = GameClock.get_day_minutes()
	GameClock.advance_real_seconds(60.0)
	check_near(GameClock.get_day_minutes() - before, 15.0, 0.01, "effective 0.2 -> 15 game min")
	GameClock.set_accessibility_speed(100.0)
	check_near(GameClock.get_accessibility_speed(),
			Database.get_balance_float("tiempo.velocidad_accesibilidad_max"), 0.0001,
			"accessibility speed is clamped to the balance maximum")
	GameClock.set_accessibility_speed(1.0)
	GameClock.set_speed_multiplier(1.0)


func _test_sleep() -> void:
	new_run(DEFAULT_SEED, false)
	GameClock.advance_minutes(15.0 * MINUTES_PER_HOUR)
	_clear()
	GameClock.advance_to_next_day()
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [2, "08:00"],
			"sleeping at 23:00 wakes up on day 2 at 08:00")
	check_eq(GameClock.get_current_band(), "arrival", "waking up in the arrival band")
	check_eq(_days, [2], "sleeping emits day_advanced once")
	check_eq(_skips, [[23, 8]], "sleeping emits time_skipped(23, 8)")
	check_eq(_hours.size(), 9, "the skipped night hours still emit hour_passed (00..08)")
	check_eq(_band_news, ["arrival"], "sleeping emits night -> arrival")
	GameClock.advance_minutes(23.0 * MINUTES_PER_HOUR)
	_clear()
	GameClock.advance_to_next_day()
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [3, "08:00"],
			"awake until 07:00 (day already advanced at 06:00): sleep reaches 08:00 same day")
	check(_days.is_empty(), "no second day_advanced for the same day")


func _test_advance_to_band() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	GameClock.set_observer_check(func() -> bool: return true)
	check(not GameClock.advance_to_band("lunch"), "time skip fails when observers are near")
	check_eq(GameClock.get_time_string(), "08:00", "a failed skip does not move time")
	check(_skips.is_empty(), "a failed skip emits nothing")
	GameClock.set_observer_check(func() -> bool: return false)
	check(GameClock.advance_to_band("lunch"), "time skip succeeds without observers")
	check_eq([GameClock.get_time_string(), GameClock.get_current_band()], ["13:00", "lunch"],
			"skip lands at the start of the lunch band")
	check_eq(_skips, [[8, 13]], "time_skipped(8, 13)")
	check_eq(_band_news, ["work_morning", "lunch"], "skipping still emits the crossed bands")
	check_eq(_hours, [9, 10, 11, 12, 13], "skipping still emits every hour")
	check(not GameClock.advance_to_band("lunch"), "cannot skip to the current band")
	check(not GameClock.advance_to_band("coffee_break"), "cannot skip to an unknown band")
	check(GameClock.advance_to_band("arrival"), "skip to arrival from lunch")
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [2, "08:00"],
			"skipping to arrival crosses the night into day 2")
	check_eq(_days, [2], "one day_advanced while skipping through the night")
	GameClock.set_observer_check(Callable())


func _test_period_closures() -> void:
	new_run(DEFAULT_SEED, false)
	_clear()
	for _i: int in 50:
		GameClock.advance_to_next_day()
	check_eq(_days.size(), 50, "50 sleeps = 50 day_advanced")
	check_eq([_days.front(), _days.back()], [2, 51], "days 2..51")
	var weeks: Array[String] = _events_with_prefix("week:")
	check_eq(weeks, ["week:1@5", "week:2@10", "week:3@15", "week:4@20", "week:5@25",
			"week:6@30", "week:7@35", "week:8@40", "week:9@45", "week:10@50"],
			"week_closed every 5 days (jornadas_por_semana)")
	check_eq(_events_with_prefix("month:"), ["month:1@20", "month:2@40"],
			"month_closed every 20 days (jornadas_por_mes)")
	check_eq(_events_with_prefix("quarter:"), ["quarter:1@25", "quarter:2@50"],
			"quarter_closed every 25 days (jornadas_por_trimestre)")
	var at: int = _events.find("month:1@20")
	check(at > 0 and _events.slice(at - 1, at + 2) == ["week:4@20", "month:1@20", "day:21"],
			"closures of day 20 are emitted before day_advanced(21)")
	check_eq([GameClock.get_week(), GameClock.get_month(), GameClock.get_quarter()], [11, 3, 3],
			"day 51 is week 11, month 3, quarter 3")
	check_eq(GameClock.days_since(1), 50, "days_since(1) on day 51")


func _test_save_load() -> void:
	new_run(DEFAULT_SEED, false)
	GameClock.set_run_seed(777)
	GameClock.advance_to_next_day()
	GameClock.advance_minutes(333.5)
	var parsed: Variant = JSON.parse_string(JSON.stringify(GameClock.save_state()))
	check(parsed is Dictionary, "clock state survives a JSON round trip")
	GameClock.advance_minutes(2000.0)
	GameClock.set_run_seed(1)
	GameClock.resume()
	GameClock.load_state(parsed)
	check_eq([GameClock.get_day(), GameClock.get_time_string()], [2, "13:33"],
			"load_state restores day and time")
	check_near(GameClock.get_day_minutes(), 813.5, 0.0001, "load_state restores minute fractions")
	check_eq(GameClock.get_current_band(), "lunch", "load_state recomputes the band")
	check_eq(GameClock.get_run_seed(), 777, "load_state restores the run seed")
	check(GameClock.is_paused(), "load_state leaves the clock paused")
	GameClock.set_run_seed(DEFAULT_SEED)


# ─── Registro de señales ───────────────────────────────────────

func _connect_bus() -> void:
	EventBus.time_band_changed.connect(_on_band)
	EventBus.day_advanced.connect(_on_day)
	EventBus.hour_passed.connect(_on_hour)
	EventBus.week_closed.connect(_on_week)
	EventBus.month_closed.connect(_on_month)
	EventBus.quarter_closed.connect(_on_quarter)
	EventBus.time_skipped.connect(_on_skip)


func _disconnect_bus() -> void:
	EventBus.time_band_changed.disconnect(_on_band)
	EventBus.day_advanced.disconnect(_on_day)
	EventBus.hour_passed.disconnect(_on_hour)
	EventBus.week_closed.disconnect(_on_week)
	EventBus.month_closed.disconnect(_on_month)
	EventBus.quarter_closed.disconnect(_on_quarter)
	EventBus.time_skipped.disconnect(_on_skip)


func _clear() -> void:
	_band_news.clear()
	_band_olds.clear()
	_days.clear()
	_day_hours.clear()
	_hours.clear()
	_skips.clear()
	_events.clear()


func _on_band(old_band: String, new_band: String) -> void:
	_band_olds.append(old_band)
	_band_news.append(new_band)


func _on_day(day_number: int) -> void:
	_days.append(day_number)
	_day_hours.append(GameClock.get_hour())
	_events.append("day:%d" % day_number)


func _on_hour(hour: int, _day_number: int) -> void:
	_hours.append(hour)


func _on_week(week_number: int) -> void:
	_events.append("week:%d@%d" % [week_number, GameClock.get_day()])


func _on_month(month_number: int) -> void:
	_events.append("month:%d@%d" % [month_number, GameClock.get_day()])


func _on_quarter(quarter_number: int) -> void:
	_events.append("quarter:%d@%d" % [quarter_number, GameClock.get_day()])


func _on_skip(from_hour: int, to_hour: int) -> void:
	_skips.append([from_hour, to_hour])


func _events_with_prefix(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for event: String in _events:
		if event.begins_with(prefix):
			out.append(event)
	return out


func _band_hours(band: String) -> int:
	var order: Array[String] = GameClock.get_band_order()
	var next_band: String = order[order.find(band) + 1]
	return GameClock.get_band_start_hour(next_band) - GameClock.get_band_start_hour(band)
