# strike_case.gd — Cuerpo de test_strike: las cuatro acciones del jugador en el conflicto laboral (agitar, apaciguar, liderar, traicionar), el umbral de la huelga, sus reputaciones y los efectos de la huelga activa en ambos cerebros (§11.7, §9.12, PASO 41).
# PROPIETARIO DE: nada.
# ESCUCHA: strike_started, strike_resolved, news_published, crime_committed, grievance_added (solo para comprobarlas).
extends TestCase

const EPS := 0.01
const THRESHOLD := 70
const CONTENT := 0.5
const UPSET := -0.5
const START_REPUTATION := 60.0
const BETRAY_REPUTATION := 40.0
const SIGNALS: Array[String] = [
	"strike_started", "strike_resolved", "news_published", "crime_committed", "grievance_added",
]

var _log: Dictionary = {}


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	_test_status_factors()
	_test_agitation_talk()
	_test_agitation_speeds_up()
	_test_agitation_rumour()
	_test_appeasement()
	_test_threshold_and_lead()
	_test_lead_calls_a_new_strike()
	_test_betrayal()
	_test_active_strike_both_brains()
	_test_save_load()


# ─── Factores y agitar ────────────────────────────────────────

## Los factores de la tabla §11.7 que ya lleva Company, vistos desde el resumen de Strike.
func _test_status_factors() -> void:
	_fresh()
	var status: Dictionary = Strike.get_status()
	check(not bool(status["strike_active"]) and int(status["threshold"]) == THRESHOLD
			and int(status["discontent"]) == _bi("descontento.inicial"), "a calm start")
	check_near(float(status["standing_workers"]), _bf("huelga.prestigio_inicial"), EPS,
			"neutral standing with the workers")
	Company.set_production_quota(_bf("empresa.cuota_razonable_max") + 0.1)
	Company.set_cost_cutting(0.1)
	status = Strike.get_status()
	check(bool(status["quota_excessive"]) and bool(status["factory_degraded"]),
			"an excessive quota and degraded conditions are visible factors")
	var worker: String = _holder("email_worker_3b")
	_set_mood(worker, UPSET)
	Strike.agitate(worker)
	var deltas: Dictionary = _day_deltas()
	check_eq([deltas.get("excessive_quota", 0), deltas.get("degraded_factory", 0),
			deltas.get("agitation", 0)], [_bi("descontento.por_cuota_excesiva_diaria"),
			_bi("descontento.por_condiciones_fabrica"), _bi("huelga.agitacion_por_conversacion")],
			"the day adds the quota, conditions and agitation factors together")


func _test_agitation_talk() -> void:
	_fresh()
	var worker: String = _holder("email_worker_3b")
	_set_mood(worker, CONTENT)
	check_eq(Strike.agitate(worker)["reason"], "not_discontented",
			"a content worker with no grievances will not be stirred")
	_set_mood(worker, UPSET)
	check(Strike.is_discontented(worker), "an unhappy worker is discontented")
	var before: int = Company.get_discontent()
	var result: Dictionary = Strike.agitate(worker)
	check(bool(result["ok"]), "agitating a discontented worker")
	check_eq(Company.get_discontent() - before, _bi("huelga.descontento_por_conversacion"),
			"immediate rise in discontent")
	check_eq(Company.get_agitation(), _bi("huelga.agitacion_por_conversacion"),
			"and a daily agitation impulse")
	check_eq(Strike.agitate(worker)["reason"], "cooldown",
			"the same worker cannot be worked on again")
	check_eq(Strike.agitate(_holder("b10_director"))["reason"], "not_low_tier",
			"directors are not the shop floor")
	check_eq(Strike.agitate("npc_nobody")["reason"], "unknown_npc", "unknown person")
	check_eq(Strike.get_reason_label_key("cooldown"), "STRIKE_REASON_COOLDOWN",
			"reasons have text keys")
	GameClock.advance_to_next_day()
	_set_mood(worker, UPSET)
	check_eq(Strike.can_agitate(worker)["reason"], "cooldown", "a day later: still too soon")
	for i: int in _bi("huelga.jornadas_entre_agitaciones") - 1:
		GameClock.advance_to_next_day()
	_set_mood(worker, UPSET)
	check(bool(Strike.can_agitate(worker)["allowed"]),
			"after the cooldown the worker listens again")


## «Acelera el incremento del descontento»: el impulso se suma cada jornada y decae.
func _test_agitation_speeds_up() -> void:
	_fresh()
	for occupation: String in ["email_worker_3b", "order_filer"]:
		var worker: String = _holder(occupation)
		_set_mood(worker, UPSET)
		Strike.agitate(worker)
	var impulse: int = Company.get_agitation()
	check_eq(impulse, 2 * _bi("huelga.agitacion_por_conversacion"), "two talks, twice the impulse")
	check_eq(_day_delta("agitation"), impulse, "next day: discontent rises by the whole impulse")
	check_eq(Company.get_agitation(), impulse - _bi("huelga.decaimiento_agitacion_diario"),
			"and the impulse decays")
	check_eq(_day_delta("agitation"), impulse - _bi("huelga.decaimiento_agitacion_diario"),
			"the following day it rises a little less")


func _test_agitation_rumour() -> void:
	_fresh()
	var worker: String = _holder("email_worker_3b")
	var before: int = Company.get_discontent()
	var result: Dictionary = Strike.plant_rumour(worker)
	var manager: String = _holder("factory_director")
	check(bool(result["ok"]) and result["subject"] == manager,
			"a rumour against management (the factory director) is planted")
	check(not _crimes("rumour_planted").is_empty(), "crime_committed(rumour_planted)")
	var rumours: Array[Dictionary] = SocialGraph.get_injected_rumours()
	check(not rumours.is_empty() and rumours.back()["fact"] == "management_abuse:%s" % manager
			and rumours.back()["target"] == worker, "SocialGraph carries the rumour")
	check_eq(Company.get_discontent() - before, _bi("huelga.descontento_por_rumor"),
			"discontent rises")
	check_eq(Company.get_agitation(), _bi("huelga.agitacion_por_rumor"),
			"a rumour pushes harder than a talk")
	check_eq(Strike.plant_rumour(_holder("cfo"))["reason"], "not_low_tier",
			"the rumour is planted on the shop floor")


# ─── Apaciguar ────────────────────────────────────────────────

func _test_appeasement() -> void:
	_fresh()
	Company.modify_discontent(40, "test")
	check_eq(Strike.appease_with_concession()["reason"], "no_authority",
			"an email worker cannot grant a pay rise")
	PlayerState.set_occupation("factory_director", "test")
	var payroll: float = float(Company.get_fundamentals()["payroll"])
	var before: int = Company.get_discontent()
	check(bool(Strike.appease_with_concession()["ok"]), "the factory director grants a concession")
	check_eq(Company.get_discontent() - before, _bi("descontento.reduccion_por_concesion"),
			"concession: −15")
	check(float(Company.get_fundamentals()["payroll"]) > payroll, "at a direct economic cost")
	check_eq(Strike.appease_by_firing(_holder("email_worker_3b"))["reason"], "not_management",
			"firing a worker is no appeasement")
	check_eq(Strike.appease_by_firing(_holder("cfo"))["reason"], "no_authority",
			"nobody fires their own superiors")
	var foreman: String = _holder("factory_foreman")
	before = Company.get_discontent()
	check(bool(Strike.appease_by_firing(foreman)["ok"]), "the director fires the foreman")
	check(not NPCDirector.is_active(foreman), "the culprit leaves the company")
	check_eq(Company.get_discontent() - before, _bi("descontento.reduccion_por_despedir_causante"),
			"firing the culprit: −10")


# ─── Liderar y traicionar ─────────────────────────────────────

func _test_threshold_and_lead() -> void:
	_fresh()
	PlayerState.modify_reputation(START_REPUTATION, "test")
	Company.modify_discontent(THRESHOLD - Company.get_discontent(), "test")
	check_eq(Strike.lead()["reason"], "below_threshold", "exactly 70 is not enough to lead")
	check(not Company.is_strike_active(), "no strike at 70")
	Company.modify_discontent(1, "test")
	check(Company.is_strike_active(), "71: the strike breaks out")
	var worker: String = _holder("email_worker_3b")
	var boss: String = _holder("b10_director")
	var worker_affection: int = NPCDirector.get_affection(worker)
	var boss_affection: int = NPCDirector.get_affection(boss)
	check(bool(Strike.lead()["ok"]), "the player leads the strike")
	check_eq(Company.get_strike_leader(), "player", "the player is the leader")
	check_near(PlayerState.get_reputation(), START_REPUTATION
			+ _bf("huelga.reputacion_direccion_liderar"), EPS,
			"reputation with management drops hard")
	check_near(Company.get_labour_standing("workers"), _bf("huelga.prestigio_liderar_trabajadores"),
			EPS, "standing among tiers 1-3: very high")
	check_near(Company.get_labour_standing("management"),
			_bf("huelga.prestigio_liderar_direccion"), EPS, "standing with management: very low")
	check_eq(NPCDirector.get_affection(worker) - worker_affection,
			_bi("huelga.afecto_bajos_liderar"), "the shop floor warms to the player")
	check_eq(NPCDirector.get_affection(boss) - boss_affection,
			_bi("huelga.afecto_direccion_liderar"), "management cools")
	check_eq(Strike.lead()["reason"], "already_leading", "leading twice changes nothing")


## Una huelga terminada por otra vía con el descontento aún por encima: liderarla la convoca.
func _test_lead_calls_a_new_strike() -> void:
	_fresh()
	Company.modify_discontent(THRESHOLD + 5 - Company.get_discontent(), "test")
	EventBus.strike_resolved.emit("negotiated")
	check(not Company.is_strike_active(), "the strike was settled but discontent stays at 75")
	var started: int = _calls("strike_started").size()
	check(bool(Strike.lead()["ok"]) and Company.is_strike_active(), "the player calls a new strike")
	check_eq(_calls("strike_started").size(), started + 1, "strike_started is emitted")


func _test_betrayal() -> void:
	_fresh()
	PlayerState.modify_reputation(BETRAY_REPUTATION, "test")
	Company.modify_discontent(THRESHOLD + 10 - Company.get_discontent(), "test")
	check_eq(Strike.betray()["reason"], "not_leader", "only the one who called it can betray it")
	Strike.lead()
	var worker: String = _holder("email_worker_3b")
	var boss: String = _holder("b10_director")
	var boss_affection: int = NPCDirector.get_affection(boss)
	var reputation: float = PlayerState.get_reputation()
	_clear()
	check(bool(Strike.betray()["ok"]), "the player does not show up")
	check_eq(_calls("strike_resolved"), [["betrayed"]], "strike_resolved(betrayed)")
	check(not Company.is_strike_active(), "the strike stops")
	check_near(PlayerState.get_reputation() - reputation,
			_bf("huelga.reputacion_direccion_traicionar"), EPS,
			"management: the player saved the company")
	check_near(Company.get_labour_standing("management"),
			_bf("huelga.prestigio_traicion_direccion"), EPS, "standing with management: very high")
	check_near(Company.get_labour_standing("workers"),
			_bf("huelga.prestigio_traicion_trabajadores"), EPS, "standing on the floor: destroyed")
	check(_has_grievance(worker, "strike_betrayed"), "every low-tier worker holds a grievance")
	check(not _has_grievance(boss, "strike_betrayed"), "management holds none")
	check_eq(NPCDirector.get_affection(boss) - boss_affection,
			_bi("huelga.afecto_direccion_traicionar"), "management warms to the player")
	_check_betrayal_is_permanent(worker)


func _check_betrayal_is_permanent(worker: String) -> void:
	check(Company.are_workers_betrayed(), "the betrayal is recorded for good")
	Company.modify_discontent(-20, "test")
	Company.modify_discontent(20, "test")
	check(Company.is_strike_active(), "the floor strikes again without the player")
	check_eq(Strike.lead()["reason"], "workers_betrayed", "nobody follows the traitor")
	_set_mood(worker, UPSET)
	check_eq(Strike.agitate(worker)["reason"], "workers_betrayed", "nobody listens to them either")
	check_near(Company.get_labour_standing("workers"),
			_bf("huelga.prestigio_traicion_trabajadores"), EPS, "the standing never recovers")


# ─── Huelga activa: ambos cerebros ────────────────────────────

func _test_active_strike_both_brains() -> void:
	_fresh()
	GameClock.advance_to_next_day()
	var control_price: float = Market.get_price()
	var control_sentiment: float = Market.get_sentiment()
	_fresh()
	var base: Dictionary = Company.get_fundamentals()
	var bad_news: int = NewsFeed.get_negative_news_count()
	Company.modify_discontent(THRESHOLD - Company.get_discontent(), "test")
	check(not bool(Strike.lead()["ok"]), "at 70 there is nothing to lead")
	Company.modify_discontent(1, "test")
	Strike.lead()
	var f: Dictionary = Company.get_fundamentals()
	check_near(float(f["units"]), 0.0, EPS, "production stops at once")
	check(float(f["risk_factor"]) > float(base["risk_factor"]), "the risk factor rises")
	check(NewsFeed.get_negative_news_count() > bad_news, "negative news is published")
	check(_calls("news_published").any(_is_bad_news), "news_published with negative sentiment")
	GameClock.advance_to_next_day()
	check(Market.get_price() < control_price,
			"the share price falls (same seed, no strike: higher)")
	check(Market.get_sentiment() < control_sentiment, "market sentiment is worse")
	EventBus.strike_resolved.emit("negotiated")
	check(float(Company.get_fundamentals()["units"]) > 0.0, "production resumes when it ends")


func _test_save_load() -> void:
	_fresh()
	var worker: String = _holder("email_worker_3b")
	_set_mood(worker, UPSET)
	Strike.agitate(worker)
	Company.modify_discontent(THRESHOLD + 1 - Company.get_discontent(), "test")
	Strike.lead()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(saved)
	check_eq(Company.get_strike_leader(), "player", "the leader survives a JSON save")
	check_eq(Company.get_agitation(), _bi("huelga.agitacion_por_conversacion"), "and the impulse")
	check_eq(Company.get_last_agitation_day(worker), 1, "and the agitation cooldowns")
	check_near(Company.get_labour_standing("workers"), _bf("huelga.prestigio_liderar_trabajadores"),
			EPS, "and the labour standing")
	Strike.betray()
	var again: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(again)
	check(Company.are_workers_betrayed(), "the betrayal survives a save")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


func _holder(occupation_id: String) -> String:
	return Company.get_seat_holders(occupation_id)[0]


func _set_mood(npc_id: String, mood: float) -> void:
	NPCDirector.get_npc(npc_id).mood = mood


## Avanza una jornada y devuelve el cambio de descontento registrado con esa causa.
func _day_delta(cause: String) -> int:
	return int(_day_deltas().get(cause, 0))


## Avanza una jornada y devuelve {causa: cambio} de los factores aplicados ese día.
func _day_deltas() -> Dictionary:
	GameClock.advance_to_next_day()
	var out: Dictionary = {}
	for entry: Dictionary in Company.get_discontent_history():
		if int(entry["day"]) == GameClock.get_day():
			out[entry["cause"]] = int(out.get(entry["cause"], 0)) + int(entry["delta"])
	return out


func _has_grievance(npc_id: String, grievance_type: String) -> bool:
	for entry: Variant in NPCDirector.get_ledger(npc_id).get("grievances", []):
		if entry is Dictionary and (entry as Dictionary).get("type", "") == grievance_type:
			return true
	return false


func _is_bad_news(call: Array) -> bool:
	return float(call[1]) < 0.0


func _crimes(crime_type: String) -> Array:
	var out: Array = []
	for call: Array in _calls("crime_committed"):
		if call[0] == crime_type:
			out.append(call)
	return out


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _connect_bus() -> void:
	for signal_name: String in SIGNALS:
		EventBus.connect(signal_name, _record.bind(signal_name))


func _record(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	if not _log.has(signal_name):
		_log[signal_name] = []
	_log[signal_name].append(args)


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()
