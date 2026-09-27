# news_case.gd — Cuerpo de test_news: capa compartida §7.11 (sentimiento + efecto social del mismo evento), enterrar, decaimiento, oyentes (un hecho, un titular), eventos §9.12 (sostenidos, resueltos, mitigados, amplificados) y bucle insider §9.8 con sus contramedidas.
# PROPIETARIO DE: nada.
# ESCUCHA: news_published, news_buried, crime_committed, insider_pattern_detected (solo para comprobarlas).
extends TestCase

const EPS := 0.0001
const COMMS := "npc_bree_nash"
const RIVAL := "npc_rival_x"
const INSIDER_HEADLINE := "NEWS_INSIDER_SCANDAL"
const PRAISE := "NEWS_FABRICATED_PRAISE"
const SMEAR := "NEWS_FABRICATED_SCANDAL"
# §9.8: coeficientes de la fórmula de detección y umbral de market.json.
const COEF_OPS := 0.05
const COEF_VOLUME := 0.10
const COEF_SUSPICION := 0.20
const COEF_AUDITOR := 0.30
const VOLUME_THRESHOLD := 5000.0
const PATTERN_THRESHOLD := 2.0
const BIG_VOLUME := 50000
const MAX_OPS := 60
const FREQUENCY_RUNS := 300
const FREQUENCY_TOLERANCE := 0.1
const RESURFACE_ITEMS := 30
const RESURFACE_DAYS := 60
const R25_OCCUPATION := "comms_director"
const R28_OCCUPATION := "cfo"
const R30_OCCUPATION := "board_investor"
const AUDITOR_OCCUPATION := "chief_auditor"
const TANIA := "inv_tania_brekke"
const FRAUD_HEADLINE := "NEWS_FRAUD_UNCOVERED"
const INVESTIGATION_HEADLINE := "NEWS_INVESTIGATION_OPENED"
const VIRAL := "viral_moment"
const LEATHER := "leather_price_rise"
const LAWSUIT := "customer_lawsuit"
const RECESSION := "general_recession"
const PROXY_FAVOUR := "lend_access"
const PROXY_FACT := "caught_redhanded:insider_trade"

var _published: Array = []
var _buried: Array = []
var _crimes: Array = []
var _detections: Array[int] = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	EventBus.news_published.connect(
			func(id: String, s: float, sc: bool) -> void: _published.append([id, s, sc]))
	EventBus.news_buried.connect(func(id: String, by: String) -> void: _buried.append([id, by]))
	EventBus.crime_committed.connect(
			func(t: String, _r: String, d: Dictionary) -> void: _crimes.append([t, d]))
	EventBus.insider_pattern_detected.connect(func(n: int) -> void: _detections.append(n))
	_test_shared_layer_and_bury()
	await _check_suspicion_decays_with_press()
	_test_decay_and_consolidation()
	_test_resurfacing()
	_test_fabricate()
	await _test_listeners()
	_test_market_events()
	_test_event_control()
	_test_scheduled_publication()
	_test_insider_formula()
	await _test_insider_detection_is_news()
	_test_insider_countermeasures()
	_test_proxy_countermeasure()
	_test_trade_direction()
	_test_upcoming_news_by_rank()
	_test_save_load()


func _test_shared_layer_and_bury() -> void:
	new_run(DEFAULT_SEED, false)
	var sentiment0: float = NewsFeed.get_sentiment_contribution()
	var social0: float = NewsFeed.get_suspicion_contribution()
	var market0: float = Market.get_sentiment()
	_published.clear()
	var id: String = NewsFeed.publish_about(INSIDER_HEADLINE, -0.2, true, NewsFeedSystem.SUBJECT_PLAYER)
	check(_published.size() == 1 and _published[0] == [id, -0.2, true],
			"one event → one news_published(id, −0.2, scandal) heard by both brains")
	check_near(NewsFeed.get_sentiment_contribution(), sentiment0 - 0.2, EPS, "economic effect: sentiment −0.2")
	check_near(Market.get_sentiment() - Market.get_investor_sentiment(),
			NewsFeed.get_sentiment_contribution(), EPS, "Market reads the same news sentiment")
	check(Market.get_sentiment() <= market0 - 0.2 + EPS,
			"market sentiment drops at least by the scandal (investors may panic on top)")
	var player_weight: float = Database.get_balance_float("noticias.sospecha_escandalo_jugador")
	check_near(NewsFeed.get_suspicion_contribution(), social0 + player_weight, EPS,
			"social effect of the same event: +%.0f suspicion weight on the player" % player_weight)
	check_eq(NewsFeed.get_scandal_count(1), 1, "one scandal today")
	check_eq(NewsFeed.get_headline_key(id), INSIDER_HEADLINE, "get_headline_key(news id) gives the strings.csv key")
	var positive: String = NewsFeed.publish(PRAISE, 0.05, false)
	check(not NewsFeed.bury(positive, COMMS), "good news is not buried")
	_buried.clear()
	check(NewsFeed.bury(id, COMMS), "the Comms Director buries the scandal")
	check(_buried.size() == 1 and _buried[0] == [id, COMMS], "news_buried(id, by_whom) emitted")
	check_near(NewsFeed.get_sentiment_contribution(), sentiment0 + 0.05, EPS,
			"burying removes the negative sentiment (market brain)")
	check_near(NewsFeed.get_suspicion_contribution(), social0, EPS,
			"burying removes the suspicion weight (social brain)")
	check_eq(NewsFeed.get_scandal_count(1), 0, "a buried scandal no longer counts")
	check(not NewsFeed.bury(id, COMMS) and not NewsFeed.bury("news_missing", COMMS),
			"cannot bury twice or bury a missing item")
	_check_suspicion_end_to_end()
	var company_id: String = NewsFeed.publish("NEWS_INVESTIGATION_OPENED", -0.1, true)
	check_near(NewsFeed.get_suspicion_contribution(), social0
			+ Database.get_balance_float("noticias.sospecha_escandalo_general"), EPS,
			"a company scandal raises general vigilance")
	check(NewsFeed.get_active_news().any(func(n: Dictionary) -> bool: return n["id"] == company_id),
			"the company scandal is active news")


## PASO 35 "Verificación": el MISMO escándalo sube la sospecha del jugador (BeliefNet → caché de
## PlayerState, suspicion_changed) y hunde la cotización; enterrarlo baja las dos (§7.11).
func _check_suspicion_end_to_end() -> void:
	var factor: float = Database.get_balance_float("creencias.factor_peso_social_noticias")
	var weight: float = Database.get_balance_float("noticias.sospecha_escandalo_jugador")
	var before: float = BeliefNet.calculate_player_suspicion()
	var market_before: float = Market.get_sentiment()
	var changes: Array = []
	var on_change: Callable = func(o: float, n: float) -> void: changes.append([o, n])
	EventBus.suspicion_changed.connect(on_change)
	var id: String = NewsFeed.publish_about(INSIDER_HEADLINE, -0.2, true, NewsFeedSystem.SUBJECT_PLAYER)
	var with_scandal: float = BeliefNet.calculate_player_suspicion()
	check_near(with_scandal, before + weight * factor, EPS,
			"end to end: the scandal adds its social weight to the player's suspicion (%.1f → %.1f)"
			% [before, with_scandal])
	check_near(PlayerState.get_suspicion(), with_scandal, EPS,
			"end to end: PlayerState's cached suspicion follows at once (news_published)")
	check(changes.size() == 1 and is_equal_approx(float(changes[0][1]), with_scandal),
			"end to end: suspicion_changed announces the rise")
	check(Market.get_sentiment() <= market_before - 0.2 + EPS,
			"end to end: the same event depresses the market sentiment")
	var news_rows: Array = BeliefNet.get_suspicion_breakdown().filter(func(e: Dictionary) -> bool:
		return e["belief_id"] == BeliefNetSystem.NEWS_ENTRY_ID)
	check(news_rows.size() == 1 and is_equal_approx(float(news_rows[0]["contribution"]), weight * factor),
			"the press is one synthetic entry of the suspicion breakdown")
	NewsFeed.bury(id, COMMS)
	check_near(BeliefNet.calculate_player_suspicion(), before, EPS,
			"end to end: burying the scandal gives the suspicion back")
	check_near(PlayerState.get_suspicion(), before, EPS, "…and the cache follows (news_buried)")
	check(Market.get_sentiment() >= market_before - EPS, "…while the market sentiment recovers too")
	EventBus.suspicion_changed.disconnect(on_change)


## El peso social decae con la prensa: tras day_advanced la caché lo recoge (recálculo diferido,
## porque NewsFeed decae al oír day_advanced DESPUÉS que BeliefNet). La jornada nueva puede traer
## más prensa (p. ej. la campaña activista que el escándalo provoca): la caché la suma también.
func _check_suspicion_decays_with_press() -> void:
	new_run(DEFAULT_SEED, false)
	var social_decay: float = Database.get_balance_float("noticias.decaimiento_sospecha_diario")
	var factor: float = Database.get_balance_float("creencias.factor_peso_social_noticias")
	var weight: float = Database.get_balance_float("noticias.sospecha_escandalo_jugador")
	var id: String = NewsFeed.publish_about(INSIDER_HEADLINE, -0.2, true, NewsFeedSystem.SUBJECT_PLAYER)
	EventBus.day_advanced.emit(GameClock.get_day() + 1)
	await get_tree().process_frame
	check_near(float(NewsFeed.get_news(id)["suspicion"]), weight * social_decay, EPS,
			"the scandal's social weight decays overnight")
	var expected: float = NewsFeed.get_suspicion_contribution() * factor
	check_near(PlayerState.get_suspicion(), expected, EPS,
			"after the day change the cached suspicion equals the live press weight (%.2f)" % expected)


func _test_decay_and_consolidation() -> void:
	new_run(DEFAULT_SEED, false)
	var decay: float = Database.get_balance_float("noticias.decaimiento_sentimiento_diario")
	var social_decay: float = Database.get_balance_float("noticias.decaimiento_sospecha_diario")
	var id: String = NewsFeed.publish("NEWS_BODY_FOUND", -0.2, true)
	var general: float = Database.get_balance_float("noticias.sospecha_escandalo_general")
	NewsFeed.apply_daily_decay()
	check_near(float(NewsFeed.get_news(id)["sentiment"]), -0.2 * decay, EPS, "sentiment decays daily")
	check_near(float(NewsFeed.get_news(id)["suspicion"]), general * social_decay, EPS,
			"the social weight decays daily")
	var multiple: float = Market.get_valuation_multiple()
	for _d: int in Database.get_balance_int("noticias.dias_consolidacion") - 1:
		NewsFeed.apply_daily_decay()
	check(bool(NewsFeed.get_news(id)["consolidated"]), "an unburied scandal consolidates")
	check(not NewsFeed.bury(id, COMMS), "a consolidated scandal can no longer be buried")
	check_eq(NewsFeed.get_settled_scandal_count(), 1, "one permanent scandal")
	check_near(multiple - Market.get_valuation_multiple(),
			Database.get_balance_float("mercado.penalizacion_multiplo_escandalo"), EPS,
			"an unburied scandal permanently reduces the valuation multiple")
	var buried: String = NewsFeed.publish("NEWS_BODY_FOUND", -0.2, true)
	NewsFeed.bury(buried, COMMS)
	for _d: int in Database.get_balance_int("noticias.dias_consolidacion"):
		NewsFeed.apply_daily_decay()
	check_eq(NewsFeed.get_settled_scandal_count(), 1, "a buried scandal never becomes permanent")


func _test_resurfacing() -> void:
	new_run(DEFAULT_SEED, false)
	for i: int in RESURFACE_ITEMS:
		NewsFeed.bury(NewsFeed.publish("NEWS_BODY_FOUND", -0.1, true), COMMS)
	for _d: int in RESURFACE_DAYS:
		NewsFeed.apply_daily_decay()
	var window: int = Database.get_balance_int("noticias.dias_ventana_reaparicion")
	var resurfaced: int = 0
	var within_window: bool = true
	for item: Dictionary in NewsFeed.get_all_news():
		if item["source"] == NewsFeedSystem.SOURCE_RESURFACED:
			resurfaced += 1
			within_window = within_window and int(item["age"]) >= RESURFACE_DAYS - window
	check(resurfaced > 0 and resurfaced < RESURFACE_ITEMS,
			"buried press can resurface through outside channels (%d of %d)" % [resurfaced, RESURFACE_ITEMS])
	check(within_window, "only during the first %d days after burial" % window)


func _test_fabricate() -> void:
	new_run(DEFAULT_SEED, false)
	var before: float = NewsFeed.get_sentiment_contribution()
	var praise: String = NewsFeed.fabricate(NewsFeedSystem.SUBJECT_COMPANY, PRAISE)
	check_near(NewsFeed.get_sentiment_contribution() - before,
			Database.get_balance_float("noticias.sentimiento_fabricado_favorable"), EPS,
			"fabricated praise lifts market sentiment")
	check(not bool(NewsFeed.get_news(praise)["is_scandal"]), "praise is not a scandal")
	_crimes.clear()
	var social: float = NewsFeed.get_suspicion_contribution()
	var smear: String = NewsFeed.fabricate(RIVAL, SMEAR)
	check(bool(NewsFeed.get_news(smear)["is_scandal"]) and NewsFeed.get_news(smear)["subject"] == RIVAL,
			"a fabricated scandal targets the rival")
	check_near(NewsFeed.get_suspicion_about(RIVAL),
			Database.get_balance_float("noticias.sospecha_fabricado_objetivo"), EPS,
			"the smear puts social weight on the rival")
	check_near(NewsFeed.get_suspicion_contribution(), social, EPS, "…and none on the player")
	check(_crimes.size() == 1 and _crimes[0][0] == "framing" and _crimes[0][1]["target"] == RIVAL,
			"fabricating a scandal is framing (crime_committed)")
	check_eq(NewsFeed.fabricate("", SMEAR), "", "no target → nothing fabricated")


func _test_listeners() -> void:
	new_run(DEFAULT_SEED, false)
	EventBus.body_discovered.emit("body_test", "dead_archive")
	check_eq(_count_headline("NEWS_BODY_FOUND"), 1, "body_discovered → one body-found scandal")
	check_near(_sentiment_of("NEWS_BODY_FOUND"),
			Database.get_balance_float("noticias.sentimiento_cuerpo_hallado"), EPS,
			"body found: sentiment from balance")
	var generic: int = _count_headline(INVESTIGATION_HEADLINE)
	EventBus.investigation_opened.emit("case_t1", "object_missing", 2)
	EventBus.investigation_opened.emit("case_t2", "power_cut", 4)
	EventBus.investigation_opened.emit("case_t3", "body_found", 5)
	EventBus.investigation_opened.emit("case_t4", "fraud_at_month_close", 5)
	check_eq(_count_headline(INVESTIGATION_HEADLINE), generic,
			"non-public incidents below maximum severity, the body case and fraud cases are not press")
	EventBus.investigation_opened.emit("case_t5", "object_missing", 5)
	check_eq(_count_headline(INVESTIGATION_HEADLINE) - generic, 1,
			"a maximum-severity investigation is public news, published at once")
	check(NewsFeed.is_press_worthy("body_found", 1) == false
			and not NewsFeed.is_press_worthy("power_cut", 4), "is_public_news from investigations.json")
	_test_strike_listeners()
	await _test_one_fraud_headline()


## Un hecho, un titular: auditoría con fraude + cambio de jornada en el mismo fotograma (Security
## abre su caso de fraude ese día o, por la regla de descanso, otro: nunca es un segundo titular).
func _test_one_fraud_headline() -> void:
	new_run(DEFAULT_SEED, false)
	var tania: int = Market.get_investor_confidence(TANIA)
	EventBus.audit_triggered.emit(false)
	check_eq(_count_headline(FRAUD_HEADLINE), 0, "a clean audit is not news")
	EventBus.audit_triggered.emit(true)
	check_eq(Market.get_investor_confidence(TANIA), tania - 25, "the fraud costs Tania 25")
	GameClock.advance_to_next_day()
	await wait_frames(3)
	GameClock.advance_to_next_day()
	await wait_frames(3)
	check_eq(_count_headline(FRAUD_HEADLINE), 1,
			"a discovered falsification is ONE fraud scandal, even across day changes")
	check_eq(_count_source(NewsFeedSystem.SOURCE_INVESTIGATION), 0,
			"its investigation never becomes a second public scandal")


func _test_strike_listeners() -> void:
	EventBus.strike_started.emit()
	check_eq(_count_headline("NEWS_EVENT_STRIKE"), 1, "strike_started → negative strike headline")
	check_near(NewsFeed.get_event_multiplier("production_multiplier"), 0.0, EPS,
			"strike: production stopped")
	check_near(NewsFeed.get_event_addition("risk_factor_add"), 0.5, EPS, "strike: risk +0.5")
	EventBus.strike_resolved.emit("test")
	check_near(NewsFeed.get_event_multiplier("production_multiplier"), 1.0, EPS,
			"strike_resolved ends the strike event")


func _test_market_events() -> void:
	var first: Array = _rolled_for_seed(DEFAULT_SEED)
	var again: Array = _rolled_for_seed(DEFAULT_SEED)
	check_eq(first, again, "market events are rolled with the seeded RNG (reproducible)")
	var counts: Dictionary = {}
	for run_seed: int in range(1, FREQUENCY_RUNS + 1):
		for item: Array in _rolled_for_seed(run_seed):
			counts[item[0]] = int(counts.get(item[0], 0)) + 1
	var all_ok: bool = true
	for ev: Dictionary in Database.get_market_events():
		var freq: float = float(counts.get(ev["id"], 0)) / FREQUENCY_RUNS
		var ok: bool = absf(freq - float(ev["probability_per_quarter"])) <= FREQUENCY_TOLERANCE
		all_ok = all_ok and ok
		if not ok:
			print("  event %s: frequency %.3f vs %.3f" % [ev["id"], freq, ev["probability_per_quarter"]])
	check(all_ok, "each event appears with its probability_per_quarter (±0.1 over 300 quarters)")
	check_eq(int(counts.get("strike", 0)), 0, "the strike is never rolled (discontent triggers it)")


## §9.12: viralización sostenida dos semanas; cuero hasta el cambio de proveedor; demanda mitigada
## por Dirección Jurídica; amplificación por el Director de Comunicación.
func _test_event_control() -> void:
	new_run(DEFAULT_SEED, false)
	var day: int = NewsFeed.get_current_day()
	for event_id: String in [VIRAL, LEATHER, LAWSUIT, RECESSION]:
		check(NewsFeed.schedule_market_event(event_id, day + 1), "%s scheduled for tomorrow" % event_id)
	NewsFeed.advance_day(day + 1)
	var viral: Dictionary = _find_headline("NEWS_EVENT_VIRAL")
	var recession: Dictionary = _find_headline("NEWS_EVENT_RECESSION")
	NewsFeed.apply_daily_decay()
	check_near(float(NewsFeed.get_news(viral["id"])["sentiment"]), float(viral["sentiment"])
			* Database.get_balance_float("noticias.decaimiento_sentimiento_evento_sostenido"), EPS,
			"viral moment: its sentiment is sustained while the event lasts")
	check_near(float(NewsFeed.get_news(recession["id"])["sentiment"]), float(recession["sentiment"])
			* Database.get_balance_float("noticias.decaimiento_sentimiento_diario"), EPS,
			"a one-off headline decays at the normal rate")
	check(not NewsFeed.resolve_market_event(LEATHER, "wrong_cause"), "leather rise ends only on its cause")
	check(NewsFeed.resolve_market_event(LEATHER, "supplier_change")
			and is_equal_approx(NewsFeed.get_event_multiplier("costs_multiplier"), 1.0),
			"changing supplier ends the leather rise")
	check(not NewsFeed.resolve_market_event(RECESSION, "any"), "a recession cannot be wished away")
	check(not NewsFeed.mitigate_market_event(LAWSUIT, "comms_director"), "only its mitigator helps")
	var risk: float = NewsFeed.get_event_addition("risk_factor_add")
	check(NewsFeed.mitigate_market_event(LAWSUIT, "legal_director"), "Legal mitigates the lawsuit")
	check_near(NewsFeed.get_event_addition("risk_factor_add"),
			risk * Database.get_balance_float("noticias.factor_mitigacion_evento"), EPS,
			"mitigation halves the lawsuit's risk")
	check(not NewsFeed.mitigate_market_event(LAWSUIT, "legal_director"), "only once")
	var live: float = float(NewsFeed.get_news(viral["id"])["sentiment"])
	check(NewsFeed.amplify_market_event(VIRAL, "comms_director"), "Comms amplifies the viral moment")
	check_near(float(NewsFeed.get_news(viral["id"])["sentiment"]),
			live * Database.get_balance_float("noticias.factor_amplificacion_evento"), EPS,
			"amplified sentiment ×1.5")


func _test_scheduled_publication() -> void:
	new_run(DEFAULT_SEED, false)
	NewsFeed.schedule_news("NEWS_EVENT_VIRAL", NewsFeed.get_current_day() + 2, 0.15, false, 1, 25)
	var visible_now: bool = _scheduled_has("NEWS_EVENT_VIRAL", 3)
	NewsFeed.advance_day(NewsFeed.get_current_day() + 1)
	check(not visible_now and _scheduled_has("NEWS_EVENT_VIRAL", 3),
			"scheduled news becomes knowable only within its own lead time")
	var trend: Dictionary = {}
	for item: Dictionary in NewsFeed.get_all_scheduled_news():
		check(int(item["lead_days"]) >= 1 and int(item["lead_days"]) <= 3, "lead time 1-3 days")
		if item["event_id"] == "footwear_trend_shift":
			trend = item
	var until: int = NewsFeed.get_current_day() + Database.get_balance_int("tiempo.jornadas_por_trimestre")
	while NewsFeed.get_current_day() < until:
		NewsFeed.advance_day(NewsFeed.get_current_day() + 1)
	check(NewsFeed.get_all_scheduled_news().is_empty(), "all scheduled news published by quarter end")
	check_eq(_count_headline("NEWS_EVENT_VIRAL"), 1, "custom scheduled news published on its day")
	if not trend.is_empty():
		var multiplier: float = float(trend["effects"]["revenue_multiplier"])
		check(multiplier >= 0.85 and multiplier <= 1.15, "trend shift revenue ×[0.85, 1.15]")
		check_near(NewsFeed.get_event_multiplier("revenue_multiplier"), multiplier, EPS,
				"published event is active with its rolled effect")


func _test_insider_formula() -> void:
	check_near(Database.get_balance_float("mercado.umbral_patron_insider"), PATTERN_THRESHOLD, EPS,
			"insider threshold 2.0")
	check_near(Market.compute_insider_score(4, 10000.0, 50.0, 80.0),
			COEF_OPS * 4 + COEF_VOLUME * 2.0 + COEF_SUSPICION * 0.5 + COEF_AUDITOR * 0.8, EPS,
			"score = 0.05·n + 0.10·vol/5000 + 0.20·susp/100 + 0.30·auditor/100 (= 0.74)")
	check_near(Market.compute_insider_score(10, VOLUME_THRESHOLD, 100.0, 100.0), 1.1, EPS,
			"10 ops at threshold volume, max suspicion and auditor → 1.1")


func _test_insider_detection_is_news() -> void:
	new_run(DEFAULT_SEED, false)
	_crimes.clear()
	_detections.clear()
	var ops: int = 0
	var formula_ok: bool = true
	while _detections.is_empty() and ops < MAX_OPS:
		Market.register_insider_operation(BIG_VOLUME)
		ops += 1
		if _detections.is_empty():
			var expected: float = _score(ops)
			formula_ok = formula_ok and absf(Market.get_insider_pattern_score() - expected) < EPS \
					and expected <= PATTERN_THRESHOLD
	check(formula_ok, "the accumulated pattern score follows the detection formula")
	check(_detections.size() == 1 and _detections[0] == ops,
			"crossing the threshold emits insider_pattern_detected(%d) once" % ops)
	check(_score(ops) > PATTERN_THRESHOLD, "detection happens only above the threshold")
	check_eq(_crimes.filter(func(c: Array) -> bool: return c[0] == "insider_trade").size(), ops,
			"every insider operation is a crime_committed(insider_trade)")
	await wait_frames(2)
	var item: Dictionary = _find_headline(INSIDER_HEADLINE)
	check(not item.is_empty() and bool(item["is_scandal"]) and item["subject"] == "player",
			"the detected pattern is a public scandal about the player")
	var sentiment: float = NewsFeed.get_sentiment_contribution()
	var social: float = NewsFeed.get_suspicion_contribution()
	check(float(item.get("sentiment", 0.0)) < 0.0 and float(item.get("suspicion", 0.0)) > 0.0,
			"the same scandal depresses the price AND raises suspicion")
	NewsFeed.bury(str(item.get("id", "")), COMMS)
	check(NewsFeed.get_sentiment_contribution() > sentiment and NewsFeed.get_suspicion_contribution() < social,
			"burying the insider scandal helps both brains")
	check_eq(Market.get_insider_operations_count(), 0, "the pattern restarts after detection")


func _test_insider_countermeasures() -> void:
	new_run(DEFAULT_SEED, false)
	Market.register_insider_operation(BIG_VOLUME)
	check_eq(Market.get_insider_operations_count(), 1, "one operation in the window")
	for _d: int in Database.get_balance_int("mercado.ventana_patron_insider_jornadas"):
		Market.advance_day(Market.get_current_day() + 1)
	check_eq(Market.get_insider_operations_count(), 0, "spacing operations: old ones leave the window")
	PlayerState.set_occupation(AUDITOR_OCCUPATION, "test")
	Market.register_insider_operation(BIG_VOLUME)
	check(Market.get_insider_operations_count() == 0 and Market.get_insider_pattern_score() == 0.0,
			"as Chief Auditor the player's pattern is never detected")


## §9.8 "operar mediante terceros sobornados, que pasan a ser testigos con registro".
func _test_proxy_countermeasure() -> void:
	new_run(DEFAULT_SEED, true)
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	PlayerState.add_money(100000, "test")
	var proxy: String = _bribable_npc()
	check(not proxy.is_empty() and not MarketTrading.buy_via_proxy(proxy, 10),
			"an employee who was not bribed cannot front the trades")
	var bribe: Dictionary = MarketTrading.recruit_proxy(proxy, 5000, "phone_call", {"roll": 0.0})
	check(bool(bribe.get("accepted", false)) and Market.is_proxy(proxy),
			"a bribe (favour '%s') recruits the proxy" % PROXY_FAVOUR)
	NewsFeed.schedule_news(PRAISE, NewsFeed.get_current_day() + 2, 0.05, false, 3, 25)
	_crimes.clear()
	check(MarketTrading.buy_via_proxy(proxy, 100), "the proxy buys on the player's inside knowledge")
	check_eq(Market.get_insider_operations_count(), 0, "the player's own pattern does not grow")
	check_eq(Market.get_proxy_operations().size(), 1, "the operation is on record under the proxy")
	var crime: Array = _crimes.filter(func(c: Array) -> bool: return c[0] == "insider_trade")
	check(crime.size() == 1 and crime[0][1].get("proxy", "") == proxy
			and crime[0][1].get("subject", "") == proxy,
			"still a crime, but the accounting trail points at the proxy")
	var witness: bool = BeliefNet.get_beliefs_about("player").any(
			func(b: Belief) -> bool: return b.holder == proxy and b.fact == PROXY_FACT)
	check(witness, "the proxy becomes a witness who knows about the player")


## Solo es privilegiada la operación que va en el sentido de la noticia conocida.
func _test_trade_direction() -> void:
	new_run(DEFAULT_SEED, false)
	_push_market_events_away()
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	PlayerState.add_money(400000, "test")
	var day: int = NewsFeed.get_current_day()
	NewsFeed.schedule_news(PRAISE, day + 2, 0.05, false, 3, 25)
	check_eq(Market.get_upcoming_news_directions(3), [1] as Array[int], "known good news: direction +1")
	_crimes.clear()
	MarketTrading.buy(100)
	check_eq(_insider_crimes(), 1, "buying ahead of good news is insider trading")
	MarketTrading.sell(50)
	check_eq(_insider_crimes(), 1, "selling against the good news is not")
	NewsFeed.schedule_news(SMEAR, day + 1, -0.05, false, 3, 25)
	MarketTrading.sell(10)
	check_eq(_insider_crimes(), 2, "selling ahead of bad news is insider trading")
	PlayerState.set_occupation(R30_OCCUPATION, "test")
	check(MarketTrading.buy_board_stake() and _insider_crimes() == 3,
			"an informed purchase of the board stake counts too")


func _insider_crimes() -> int:
	return _crimes.filter(func(c: Array) -> bool: return c[0] == "insider_trade").size()


## Aparta los eventos sorteados del trimestre para que ninguno sea "noticia conocida" en la prueba.
func _push_market_events_away() -> void:
	var far: int = NewsFeed.get_current_day() + Database.get_balance_int("tiempo.jornadas_por_trimestre")
	for item: Dictionary in NewsFeed.get_all_scheduled_news():
		NewsFeed.schedule_market_event(str(item["event_id"]), far)


func _bribable_npc() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.alive and npc.get_trait("greed") >= 50 and npc.get_trait("courage") < 60 \
				and npc.get_trait("loyalty") < 70:
			return npc.id
	return ""


func _test_upcoming_news_by_rank() -> void:
	new_run(DEFAULT_SEED, false)
	var day: int = NewsFeed.get_current_day()
	NewsFeed.schedule_news(PRAISE, day + 2, 0.05, false, 3, 25)
	NewsFeed.schedule_news(SMEAR, day + 2, -0.05, false, 1, 25)
	check(Market.get_upcoming_news(3).is_empty(), "R1 knows nothing in advance")
	PlayerState.set_occupation(R25_OCCUPATION, "test")
	var upcoming: Array[String] = Market.get_upcoming_news(3)
	check(upcoming.has(PRAISE), "R25 knows the news two days ahead")
	check(not upcoming.has(SMEAR), "…but only within that item's lead time (1 day)")
	check(not Market.get_upcoming_news(1).has(PRAISE), "days_ahead limits the horizon")
	check(Market.is_trade_informed(), "trading now would be an insider operation")
	while Market.get_current_day() < Market.get_presentation_day() - 2:
		Market.advance_day(Market.get_current_day() + 1)
	var preview: Array[String] = ["NEWS_RESULTS_BEAT", "NEWS_RESULTS_MISS", "NEWS_RESULTS_INLINE"]
	check(not Market.get_upcoming_news(3).any(func(h: String) -> bool: return preview.has(h)),
			"R25 does not see the quarterly results in advance")
	PlayerState.set_occupation(R28_OCCUPATION, "test")
	check(Market.get_upcoming_news(3).any(func(h: String) -> bool: return preview.has(h)),
			"R28 insider information: the results direction before the presentation")


func _test_save_load() -> void:
	new_run(DEFAULT_SEED, false)
	NewsFeed.publish("NEWS_BODY_FOUND", -0.2, true)
	NewsFeed.bury(NewsFeed.publish("NEWS_INVESTIGATION_OPENED", -0.1, true), COMMS)
	NewsFeed.apply_daily_decay()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(NewsFeed.save_state(), "", true, true))
	var news_before: Array[Dictionary] = NewsFeed.get_all_news()
	var rolled_before: Array[String] = NewsFeed.roll_quarter_events(3)
	NewsFeed.load_state(saved)
	check_eq(NewsFeed.get_all_news(), news_before, "news restored exactly after load")
	check_eq(NewsFeed.roll_quarter_events(3), rolled_before, "RNG state restored (same future rolls)")
	check_near(NewsFeed.get_sentiment_contribution(), -0.2 * Database.get_balance_float(
			"noticias.decaimiento_sentimiento_diario"), EPS, "sentiment restored")
	Market.modify_investor_confidence("inv_margaret_ash", -30, "test")
	check_eq(NewsFeed.publish_campaign_news().size(), 1, "the activist campaign is announced once")
	saved = JSON.parse_string(JSON.stringify(NewsFeed.save_state(), "", true, true))
	NewsFeed.reset_for_new_run()
	NewsFeed.load_state(saved)
	check(NewsFeed.publish_campaign_news().is_empty(), "announced campaigns survive a save/load")


func _score(ops: int) -> float:
	return COEF_OPS * ops + COEF_VOLUME * BIG_VOLUME / VOLUME_THRESHOLD \
			+ COEF_SUSPICION * PlayerState.get_suspicion() / 100.0 \
			+ COEF_AUDITOR * Market.get_chief_auditor_perception() / 100.0


func _rolled_for_seed(run_seed: int) -> Array:
	GameClock.set_run_seed(run_seed)
	NewsFeed.reset_for_new_run()
	var out: Array = []
	for item: Dictionary in NewsFeed.get_all_scheduled_news():
		out.append([item["event_id"], item["day"]])
	return out


func _scheduled_has(headline_id: String, days_ahead: int) -> bool:
	return NewsFeed.get_scheduled_news(days_ahead).any(
			func(item: Dictionary) -> bool: return item["headline_id"] == headline_id)


func _count_source(source: String) -> int:
	return NewsFeed.get_all_news().filter(
			func(item: Dictionary) -> bool: return item["source"] == source).size()


func _count_headline(headline_id: String) -> int:
	return NewsFeed.get_all_news().filter(
			func(item: Dictionary) -> bool: return item["headline_id"] == headline_id).size()


func _sentiment_of(headline_id: String) -> float:
	return float(_find_headline(headline_id).get("initial_sentiment", 0.0))


func _find_headline(headline_id: String) -> Dictionary:
	for item: Dictionary in NewsFeed.get_all_news():
		if item["headline_id"] == headline_id:
			return item
	return {}
