# market.gd — Cotización (§9.3), calendario (§9.4), inversores (§9.6-9.7), presentación (§9.5), cartera (§9.11) e información privilegiada (§9.8).
# PROPIETARIO DE: cotización, histórico, sentimiento inversor propio, confianza de cada inversor, racha de trimestres malos, cartera del jugador y patrón insider (§19.9).
# ESCUCHA: hour_passed, day_advanced, quarter_closed, news_published, audit_triggered
class_name MarketSystem
extends Node

## DECISIONES (BUILD_NOTES §6/§13; ver también el informe del constructor):
## - La fórmula DIARIA de §9.3 se aplica en N pasos horarios de 1/N, N = hora_fin_jornada −
##   hora_inicio_jornada (11). Un paso por `hour_passed` de hora de mercado (hora ∈ (inicio, fin]);
##   al llegar `day_advanced` se completan los pasos que falten, de modo que cada jornada aplica
##   exactamente un paso diario completo aunque se salten horas. Nunca por fotograma.
## - β·sentimiento se aplica como β × sentimiento × P (sentimiento adimensional, acotado a
##   ±mercado.sentimiento_max); el ruido ∈ [−ruido_diario_max, +ruido_diario_max] × P se sortea
##   una vez por jornada con el RNG del sistema; momentum = media de la variación diaria (en €)
##   de los últimos `dias_momentum` cierres.
## - Sentimiento = NewsFeed.get_sentiment_contribution() + sentimiento inversor propio (reacción
##   de la presentación y de las pérdidas de confianza), que decae a diario.
## - V usa los fundamentales REALES de Company (valores POR JORNADA; beneficio anual =
##   profit × jornadas del año fiscal). Si Company aún no da cifras, usa market.json
##   starting_fundamentals. La presentación usa las cifras REPORTADAS (§9.5: inflar mejora la
##   reacción; el inversor de valor solo es engañado por la contabilidad falsificada).
## - Market es el ÚNICO emisor de `quarter_reported` (al cerrar cada trimestre, tras la reacción
##   y la actualización de la racha). La degradación R28+ NO la ejecuta Market: expone
##   get_bad_quarters_streak() / is_board_pressure_triggered() y quien escuche quarter_reported
##   (Company / capa mundo) actúa.
## - El dinero del jugador es de PlayerState: comprar/vender/paquete/dividendos solo comprueban
##   can_afford() y emiten la señal EXT `portfolio_cash_settled(amount, reason)` (pendiente de
##   declarar en EventBus; ver informe) para que PlayerState ajuste el capital.
## - Una operación de bolsa del jugador cuenta como operación con información privilegiada si en
##   ese momento get_upcoming_news() no está vacío. register_insider_operation() emite
##   crime_committed("insider_trade") (quien llame no debe emitirlo otra vez).

const PLAYER_ID := "player"
const RNG_SALT := "market"
## Punto medio de la escala [0, 1] de resultados: 0,5 = "según lo esperado" (estructural).
const OUTCOME_NEUTRAL := 0.5
## Escala 0-100 de reputación, sospecha y perspicacia (estructural).
const PERCENT_SCALE := 100.0

const FACTOR_ABOVE := "results_above_expected"
const FACTOR_BELOW := "results_below_expected"
const FACTOR_PRESS := "favourable_press"
const FACTOR_LOUNGE := "lounge_personal_contact"
const FACTOR_TIP := "insider_tip_to_hunter"
const FACTOR_SCANDAL := "public_scandal"
const FACTOR_FRAUD := "falsification_discovered"
const REASON_TREND := "price_trend"

const STRATEGY_MOMENTUM := "momentum"
const STRATEGY_ACTIVIST := "activist"
const BEHAVIOUR_CAMPAIGN := "campaign_against_management"

const CRIME_INSIDER := "insider_trade"
const CASH_SIGNAL := &"portfolio_cash_settled"
const CASH_REASON_BUY := "shares_bought"
const CASH_REASON_SELL := "shares_sold"
const CASH_REASON_STAKE := "board_stake_bought"
const CASH_REASON_DIVIDENDS := "dividends"

const HEADLINE_RESULTS_BEAT := "NEWS_RESULTS_BEAT"
const HEADLINE_RESULTS_MISS := "NEWS_RESULTS_MISS"
const HEADLINE_RESULTS_INLINE := "NEWS_RESULTS_INLINE"

const PERIOD_DAILY := "daily"
const PERIOD_WEEKLY := "weekly"
const PERIOD_MONTHLY := "monthly"
const PERIOD_QUARTERLY := "quarterly"
const PERIOD_ANNUAL := "annual"

# ─── Datos estáticos (caché de Database; no se guardan) ───────────────
var _cfg: Dictionary = {}
var _strategies: Dictionary = {}
var _investors: Array[InvestorData] = []
var _starting_fundamentals: Dictionary = {}

# ─── Estado propio (se guarda) ─────────────────────────────────────────
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _today: int = 0
var _price: float = 0.0
var _history: Array[float] = []
var _steps_today: int = 0
var _noise_today: float = 0.0
var _own_sentiment: float = 0.0
var _fraud_multiple_penalty: float = 0.0
var _confidence: Dictionary = {}
var _last_reason: Dictionary = {}
var _credibility_lost: bool = false
var _activist_targets: Dictionary = {}
var _bad_quarters_streak: int = 0
var _presented_quarter: int = 0
var _due_emitted_quarter: int = 0
var _expected_quarter_profit: float = 0.0
var _last_presentation: Dictionary = {}
var _player_shares: int = 0
var _stake_shares: int = 0
var _invested: float = 0.0
var _dividends_paid: int = 0
var _insider_ops: Array[Dictionary] = []
var _insider_detections: int = 0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.quarter_closed.connect(_on_quarter_closed)
	EventBus.news_published.connect(_on_news_published)
	EventBus.audit_triggered.connect(_on_audit_triggered)


func reset_for_new_run() -> void:
	_load_static_data()
	_rng.seed = GameClock.get_run_seed() ^ RNG_SALT.hash()
	_today = GameClock.get_day()
	_price = _bf("mercado.precio_inicial")
	_history = [_price]
	_steps_today = 0
	_own_sentiment = 0.0
	_fraud_multiple_penalty = 0.0
	_roll_daily_noise()
	_reset_investors()
	_reset_quarter_state()
	_reset_portfolio()


# ═══ Cotización ═══════════════════════════════════════════════════════

func get_price() -> float:
	return _price


## V = (beneficio anual esperado × múltiplo) ÷ número de acciones (§9.3).
func get_intrinsic_value() -> float:
	var annual: float = float(_fundamentals().get("profit", 0.0)) * float(_days_per_year())
	var value: float = annual * get_valuation_multiple() / float(_share_count())
	return maxf(value, _bf("mercado.precio_minimo"))


## Múltiplo vigente: fórmula §9.3 × eventos de mercado activos − penalizaciones permanentes.
func get_valuation_multiple() -> float:
	var f: Dictionary = _fundamentals()
	var multiple: float = compute_multiple(float(f.get("growth_expectation", 0.0)),
			float(f.get("risk_factor", 0.0)))
	multiple *= NewsFeed.get_event_multiplier("multiple_multiplier")
	multiple -= get_permanent_multiple_penalty()
	return maxf(multiple, _bf("mercado.multiplo_minimo"))


## múltiplo = base + 0,8 × crecimiento − 1,2 × riesgo (coeficientes de balance.mercado).
func compute_multiple(growth: float, risk: float) -> float:
	return _bf("mercado.multiplo_base") + _bf("mercado.mod_multiplo_crecimiento") * growth \
			+ _bf("mercado.mod_multiplo_riesgo") * risk


## Escándalos consolidados sin enterrar (§9.10) + falsificaciones descubiertas.
func get_permanent_multiple_penalty() -> float:
	return _fraud_multiple_penalty + float(NewsFeed.get_settled_scandal_count()) \
			* _bf("mercado.penalizacion_multiplo_escandalo")


## Paso DIARIO completo de §9.3: α(V−P) + β·s·P + γ·momentum + ruido·P.
func compute_daily_delta(price: float, value: float, sentiment: float, momentum: float,
		noise_fraction: float) -> float:
	return _bf("mercado.alpha_gravedad") * (value - price) \
			+ _bf("mercado.beta_sentimiento") * sentiment * price \
			+ _bf("mercado.gamma_momentum") * momentum + noise_fraction * price


## Últimos `days` cierres diarios (el más reciente al final; no incluye la cotización en curso).
func get_price_history(days: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(maxi(_history.size() - days, 0), _history.size()):
		out.append(_history[i])
	return out


## Media de la variación diaria (€) de los últimos `dias_momentum` cierres.
func get_momentum() -> float:
	var count: int = mini(_bi("mercado.dias_momentum"), _history.size() - 1)
	if count <= 0:
		return 0.0
	return (_history[_history.size() - 1] - _history[_history.size() - 1 - count]) / float(count)


func get_sentiment() -> float:
	var cap: float = _bf("mercado.sentimiento_max")
	return clampf(NewsFeed.get_sentiment_contribution() + _own_sentiment, -cap, cap)


## Componente de sentimiento generado por los propios inversores (presentación, desbandadas).
func get_investor_sentiment() -> float:
	return _own_sentiment


## Aplica 1/N del paso diario. Como mucho N pasos por jornada; el resto se ignora.
func tick_hourly() -> void:
	var steps: int = get_steps_per_day()
	if _steps_today >= steps:
		return
	var delta: float = compute_daily_delta(_price, get_intrinsic_value(), get_sentiment(),
			get_momentum(), _noise_today)
	_price = maxf(_price + delta / float(steps), _bf("mercado.precio_minimo"))
	_steps_today += 1
	EventBus.stock_price_updated.emit(_price, _percent_change(_last_close(), _price))


func get_steps_per_day() -> int:
	return maxi(_bi("tiempo.hora_fin_jornada") - _bi("tiempo.hora_inicio_jornada"), 1)


func get_steps_done_today() -> int:
	return _steps_today


## Fracción de ruido de la jornada en curso (sorteada al abrir la jornada).
func get_noise_today() -> float:
	return _noise_today


func get_current_day() -> int:
	return _today


## Cierra la jornada de mercado (completa los pasos pendientes) y abre `day_number`.
func advance_day(day_number: int) -> void:
	if day_number <= _today:
		return
	while _steps_today < get_steps_per_day():
		tick_hourly()
	_push_close(_price)
	_apply_trend_drift()
	_own_sentiment *= _bf("mercado.decaimiento_sentimiento_inversor")
	_today = day_number
	_steps_today = 0
	_prune_insider_ops()
	_roll_daily_noise()


# ═══ Calendario (§9.4) ════════════════════════════════════════════════

## Eventos de calendario desde hoy hasta hoy + days_ahead: [{day, id, name_key, periodicity}].
func get_calendar(days_ahead: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offset: int in range(0, days_ahead + 1):
		var day: int = _today + offset
		for entry: Variant in _cfg_array("calendar.events"):
			var ev: Dictionary = entry as Dictionary
			if _calendar_event_on(str(ev.get("periodicity", "")), day):
				out.append({"day": day, "id": str(ev.get("id", "")),
						"name_key": str(ev.get("name_key", "")),
						"periodicity": str(ev.get("periodicity", ""))})
	return out


## Jornada absoluta de la presentación trimestral del trimestre en curso.
func get_presentation_day() -> int:
	var quarter: int = quarter_of(_today)
	return (quarter - 1) * _days_per_quarter() + _cfg_int("calendar.results_presentation.day_of_quarter")


@warning_ignore("integer_division")
func quarter_of(day_number: int) -> int:
	return maxi(day_number - 1, 0) / _days_per_quarter() + 1


func day_in_quarter(day_number: int) -> int:
	return maxi(day_number - 1, 0) % _days_per_quarter() + 1


# ═══ Inversores (§9.6, §9.7) ══════════════════════════════════════════

func get_investors() -> Array[InvestorData]:
	return _investors.duplicate()


func get_investor_confidence(investor_id: String) -> int:
	return int(_confidence.get(investor_id, 0))


func modify_investor_confidence(investor_id: String, delta: int, reason: String) -> void:
	if not _confidence.has(investor_id) or delta == 0:
		return
	var applied: int = delta
	if _credibility_lost and delta > 0:
		applied = floori(float(delta) * _bf("mercado.factor_credibilidad_perdida"))
	var old_value: int = int(_confidence[investor_id])
	var new_value: int = clampi(old_value + applied, InvestorData.MIN_CONFIDENCE,
			InvestorData.MAX_CONFIDENCE)
	if new_value == old_value:
		return
	_confidence[investor_id] = new_value
	_last_reason[investor_id] = reason
	EventBus.investor_confidence_changed.emit(investor_id, old_value, new_value)
	_check_confidence_loss(investor_id, old_value, new_value)


## Motivo del último cambio de confianza (id de factor de §9.7) para la UI.
func get_last_confidence_reason(investor_id: String) -> String:
	return str(_last_reason.get(investor_id, ""))


## Σ(confianza_i × capital_i) ÷ Σ capital_i (§9.7).
func get_aggregate_confidence() -> float:
	var weighted: float = 0.0
	var capital: float = 0.0
	for inv: InvestorData in _investors:
		weighted += float(get_investor_confidence(inv.id)) * float(inv.capital)
		capital += float(inv.capital)
	return weighted / capital if capital > 0.0 else 0.0


func get_quarterly_target() -> float:
	return get_target_for_quarter(quarter_of(_today))


func get_target_for_quarter(quarter_number: int) -> float:
	var targets: Array = _cfg_array("quarterly_confidence_targets")
	var index: int = quarter_number - 1
	if index >= 0 and index < targets.size():
		return float(targets[index])
	return _cfg_float("target_after_last_quarter")


func is_meeting_target() -> bool:
	return get_aggregate_confidence() >= get_quarterly_target()


## DECISIÓN: trimestres consecutivos bajo objetivo mientras el jugador es R28+ (§9.4).
func get_bad_quarters_streak() -> int:
	return _bad_quarters_streak


## true si la racha alcanza mercado.trimestres_malos_para_degradar: degradación o expulsión.
func is_board_pressure_triggered() -> bool:
	return _bad_quarters_streak >= _bi("mercado.trimestres_malos_para_degradar")


## Delta de la tabla §9.7 (market.json confidence_factors). severity ∈ [0,1] va del efecto
## leve (+8, −10, −15…) al severo (+15, −20, −30…). Los factores escalares ignoran severity.
func get_factor_delta(factor_id: String, severity: float) -> int:
	var raw: Variant = _cfg_value("confidence_factors." + factor_id)
	if raw is Array and (raw as Array).size() == 2:
		var low: float = float(raw[0])
		var high: float = float(raw[1])
		var mild: float = high if high <= 0.0 else low
		var severe: float = low if high <= 0.0 else high
		return roundi(lerpf(mild, severe, clampf(severity, 0.0, 1.0)))
	if raw is float or raw is int:
		return roundi(float(raw))
	return 0


## Aplica un factor de §9.7 a los inversores indicados. Devuelve {investor_id: delta aplicado}.
func apply_confidence_factor(factor_id: String, severity: float,
		investor_ids: Array[String]) -> Dictionary:
	var delta: int = get_factor_delta(factor_id, severity)
	var changes: Dictionary = {}
	for investor_id: String in investor_ids:
		var before: int = get_investor_confidence(investor_id)
		modify_investor_confidence(investor_id, delta, factor_id)
		changes[investor_id] = get_investor_confidence(investor_id) - before
	return changes


## Contacto personal en el lounge (+5). El gasto de representación lo cobra quien llama.
func record_lounge_contact(investor_id: String) -> int:
	if not _confidence.has(investor_id):
		return 0
	var ids: Array[String] = [investor_id]
	return int(apply_confidence_factor(FACTOR_LOUNGE, 1.0, ids).get(investor_id, 0))


## Soplo privilegiado: +12 solo al cazador de información. Cada soplo es una prueba:
## emite crime_committed("insider_trade"). Devuelve el delta aplicado.
func give_insider_tip(investor_id: String) -> int:
	var inv: InvestorData = _investor(investor_id)
	if inv == null or _strategy_float(inv, "weight_tips") <= 0.0:
		return 0
	var ids: Array[String] = [investor_id]
	var delta: int = int(apply_confidence_factor(FACTOR_TIP, 1.0, ids).get(investor_id, 0))
	EventBus.crime_committed.emit(CRIME_INSIDER, "", {"tip_to": investor_id})
	return delta


## Dirige al inversor activista contra un objetivo (rival o jugador). Solo estrategia activista.
func direct_activist(investor_id: String, target: String) -> bool:
	var inv: InvestorData = _investor(investor_id)
	if inv == null or inv.strategy != STRATEGY_ACTIVIST:
		return false
	_activist_targets[investor_id] = target
	return true


func get_activist_target(investor_id: String) -> String:
	return str(_activist_targets.get(investor_id, ""))


# ═══ Presentación de resultados (§9.5) ════════════════════════════════

## Niveles de preparación de market.json: {none: 0.0, assist: 0.5, stolen_coo_report: 0.8, real_work: 1.0}.
func get_preparation_levels() -> Dictionary:
	return _cfg_dict("presentation.preparation_levels")


func get_allies_ratio(allies_present: int) -> float:
	if _investors.is_empty():
		return 0.0
	return clampf(float(allies_present) / float(_investors.size()), 0.0, 1.0)


## calidad = 0,4 × preparación + 0,3 × reputación/100 + 0,3 × proporción de aliados.
func compute_presentation_quality(preparation: float, allies_present: int) -> float:
	return _presentation_quality(preparation, allies_present, PlayerState.get_reputation())


## Puntuación [0,1] de las cifras reportadas frente a lo esperado (0,5 = en línea).
func get_figures_score() -> float:
	return figures_score_for(_reported_quarter_profit(), _expected_quarter_profit)


func figures_score_for(reported_profit: float, expected_profit: float) -> float:
	var surprise: float = (reported_profit - expected_profit) / maxf(absf(expected_profit), 1.0)
	return clampf(OUTCOME_NEUTRAL + surprise * OUTCOME_NEUTRAL
			/ _bf("mercado.presentacion_rango_sorpresa"), 0.0, 1.0)


func get_expected_quarter_profit() -> float:
	return _expected_quarter_profit


## Devuelve { quality, confidence_changes, sentiment_delta } (+ outcome, figures_score,
## aggregate_before, aggregate_after). La calidad pesa el 60 % y las cifras el 40 %.
func conduct_quarterly_presentation(preparation: float, allies_present: int) -> Dictionary:
	var result: Dictionary = _run_presentation(
			compute_presentation_quality(preparation, allies_present))
	_presented_quarter = quarter_of(_today)
	return result


func get_last_presentation() -> Dictionary:
	return _last_presentation.duplicate(true)


# ═══ Cartera del jugador (§9.11) ══════════════════════════════════════

func get_player_shares() -> int:
	return _player_shares


func can_trade() -> bool:
	return PlayerState.get_rank() >= _cfg_int("shares.player_trading_min_rank")


func buy_shares(quantity: int) -> bool:
	if quantity <= 0 or not can_trade():
		return false
	var cost: int = ceili(_price * float(quantity))
	if not PlayerState.can_afford(cost):
		return false
	var informed: bool = is_trade_informed()
	_player_shares += quantity
	_invested += float(cost)
	_settle_cash(-cost, CASH_REASON_BUY)
	if informed:
		register_insider_operation(cost)
	return true


func sell_shares(quantity: int) -> bool:
	if quantity <= 0 or quantity > _player_shares or not can_trade():
		return false
	var proceeds: int = floori(_price * float(quantity))
	var informed: bool = is_trade_informed()
	_invested -= _invested * float(quantity) / float(_player_shares)
	_player_shares -= quantity
	if _player_shares < _stake_shares:
		_stake_shares = 0
	_settle_cash(proceeds, CASH_REASON_SELL)
	if informed:
		register_insider_operation(proceeds)
	return true


## R30: paquete accionarial por economia.precio_paquete_accionarial; concede voto en el consejo.
func buy_board_stake() -> bool:
	if has_board_stake() or PlayerState.get_rank() < _cfg_int("shares.share_package_min_rank"):
		return false
	var cost: int = _bi("economia.precio_paquete_accionarial")
	if not PlayerState.can_afford(cost):
		return false
	var quantity: int = floori(float(cost) / _price)
	_player_shares += quantity
	_stake_shares = quantity
	_invested += float(cost)
	_settle_cash(-cost, CASH_REASON_STAKE)
	return true


func has_board_stake() -> bool:
	return _stake_shares > 0


func get_portfolio_value() -> float:
	return float(_player_shares) * _price


## Coste medio acumulado de la cartera (para la UI: plusvalía = valor − invertido).
func get_invested_capital() -> float:
	return _invested


## Dividendo anual previsto de la cartera: acciones × beneficio anual × payout ÷ acciones totales.
## Se cobra en la junta anual (§9.4).
func get_dividend_income() -> int:
	var annual: float = float(_fundamentals().get("profit", 0.0)) * float(_days_per_year())
	var per_share: float = annual * _cfg_float("shares.dividend_payout_ratio") / float(_share_count())
	return maxi(floori(per_share * float(_player_shares)), 0)


func get_dividends_paid() -> int:
	return _dividends_paid


func get_board_votes() -> int:
	var votes: int = floori(float(_player_shares) / float(maxi(_cfg_int("shares.shares_per_board_vote"), 1)))
	if has_board_stake():
		votes = maxi(votes, _bi("mercado.votos_minimos_paquete"))
	return votes


# ═══ Información privilegiada (§9.8) ══════════════════════════════════

## Registra una operación con información privilegiada (volumen en €). Emite crime_committed.
## Contramedidas: menos volumen, espaciar (ventana de jornadas), enterrar la noticia, ser Auditor Jefe.
func register_insider_operation(volume: int) -> void:
	EventBus.crime_committed.emit(CRIME_INSIDER, "", {"volume": volume})
	if _insider_detection_disabled():
		return
	_insider_ops.append({"day": _today, "volume": maxi(volume, 0)})
	if get_insider_pattern_score() > _bf("mercado.umbral_patron_insider"):
		var count: int = _insider_ops.size()
		_insider_ops.clear()
		_insider_detections += 1
		EventBus.insider_pattern_detected.emit(count)


func get_insider_pattern_score() -> float:
	if _insider_ops.is_empty() or _insider_detection_disabled():
		return 0.0
	var total: float = 0.0
	for op: Dictionary in _insider_ops:
		total += float(op["volume"])
	return compute_insider_score(_insider_ops.size(), total / float(_insider_ops.size()),
			PlayerState.get_suspicion(), get_chief_auditor_perception())


## 0,05 × n + 0,10 × (volumen medio ÷ umbral) + 0,20 × sospecha/100 + 0,30 × perspicacia/100.
func compute_insider_score(operations: int, average_volume: float, suspicion: float,
		auditor_perception: float) -> float:
	var threshold: float = maxf(_cfg_float("insider_detection.volume_threshold"), 1.0)
	return _cfg_float("insider_detection.coef_operations") * float(operations) \
			+ _cfg_float("insider_detection.coef_volume") * (average_volume / threshold) \
			+ _cfg_float("insider_detection.coef_suspicion") * (suspicion / PERCENT_SCALE) \
			+ _cfg_float("insider_detection.coef_auditor_perception") \
			* (auditor_perception / PERCENT_SCALE)


func get_insider_operations_count() -> int:
	return _insider_ops.size()


func get_insider_detections() -> int:
	return _insider_detections


## Perspicacia del ocupante de Auditoría Jefe (0 si vacante o si es el jugador).
func get_chief_auditor_perception() -> float:
	var auditor: String = _cfg_string("insider_detection.auditor_occupation")
	if _player_occupation_id() == auditor:
		return 0.0
	var holder: String = Company.get_seat_holder(auditor)
	if holder.is_empty() or holder == PLAYER_ID:
		return 0.0
	return float(NPCDirector.get_trait(holder, "perception"))


## Solo R25+: titulares programados que el jugador ya conoce (antelación 1-3 jornadas).
## R28+ ve además el sentido de los resultados del trimestre antes de la presentación.
func get_upcoming_news(days_ahead: int) -> Array[String]:
	var out: Array[String] = []
	var rank: int = PlayerState.get_rank()
	if rank < _cfg_int("insider_detection.upcoming_news_min_rank"):
		return out
	for item: Dictionary in NewsFeed.get_scheduled_news(days_ahead):
		if rank >= int(item.get("min_rank", 0)):
			out.append(str(item.get("headline_id", "")))
	if rank >= _cfg_int("shares.insider_information_min_rank"):
		_append_results_preview(out, days_ahead)
	return out


## true si operar ahora sería operar con información privilegiada.
func is_trade_informed() -> bool:
	return not get_upcoming_news(_cfg_int("insider_detection.news_lead_days_max")).is_empty()


# ═══ Persistencia ═════════════════════════════════════════════════════

func save_state() -> Dictionary:
	return {
		"today": _today, "price": _price, "history": _history.duplicate(),
		"steps_today": _steps_today, "noise_today": _noise_today,
		"own_sentiment": _own_sentiment, "fraud_penalty": _fraud_multiple_penalty,
		"confidence": _confidence.duplicate(), "last_reason": _last_reason.duplicate(),
		"credibility_lost": _credibility_lost, "activist_targets": _activist_targets.duplicate(),
		"bad_streak": _bad_quarters_streak, "presented_quarter": _presented_quarter,
		"due_emitted_quarter": _due_emitted_quarter,
		"expected_profit": _expected_quarter_profit,
		"last_presentation": _last_presentation.duplicate(true),
		"shares": _player_shares, "stake_shares": _stake_shares, "invested": _invested,
		"dividends_paid": _dividends_paid, "insider_ops": _insider_ops.duplicate(true),
		"insider_detections": _insider_detections,
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	_load_static_data()
	_today = int(data.get("today", 0))
	_price = float(data.get("price", _bf("mercado.precio_inicial")))
	_history.clear()
	for value: Variant in data.get("history", []):
		_history.append(float(value))
	_steps_today = int(data.get("steps_today", 0))
	_noise_today = float(data.get("noise_today", 0.0))
	_own_sentiment = float(data.get("own_sentiment", 0.0))
	_fraud_multiple_penalty = float(data.get("fraud_penalty", 0.0))
	_load_investor_state(data)
	_load_quarter_state(data)
	_load_portfolio_state(data)
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()


# ═══ Privado: datos ═══════════════════════════════════════════════════

func _load_static_data() -> void:
	_cfg = Database.get_market_params()
	_investors = Database.get_all_investors()
	_strategies.clear()
	for inv: InvestorData in _investors:
		if not _strategies.has(inv.strategy):
			_strategies[inv.strategy] = Database.get_investor_strategy(inv.strategy)
	_starting_fundamentals = _build_starting_fundamentals()


func _build_starting_fundamentals() -> Dictionary:
	var sf: Dictionary = _cfg_dict("starting_fundamentals")
	var costs: float = 0.0
	var cost_items: Variant = sf.get("costs_per_day", {})
	if cost_items is Dictionary:
		for key: Variant in (cost_items as Dictionary).keys():
			if not str(key).begins_with("_"):
				costs += float((cost_items as Dictionary)[key])
	var revenue: float = float(sf.get("revenue_per_day", 0.0))
	return {"revenue": revenue, "costs": costs, "profit": revenue - costs,
			"growth_expectation": float(sf.get("growth_expectation", 0.0)),
			"risk_factor": float(sf.get("risk_factor", 0.0))}


func _cfg_value(path: String) -> Variant:
	var node: Variant = _cfg
	for key: String in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = (node as Dictionary)[key]
	return node


func _cfg_float(path: String) -> float:
	var v: Variant = _cfg_value(path)
	return float(v) if v is float or v is int else 0.0


func _cfg_int(path: String) -> int:
	var v: Variant = _cfg_value(path)
	return int(v) if v is float or v is int else 0


func _cfg_string(path: String) -> String:
	var v: Variant = _cfg_value(path)
	return str(v) if v != null else ""


func _cfg_bool(path: String) -> bool:
	var v: Variant = _cfg_value(path)
	return v is bool and v


func _cfg_array(path: String) -> Array:
	var v: Variant = _cfg_value(path)
	return v as Array if v is Array else []


func _cfg_dict(path: String) -> Dictionary:
	var v: Variant = _cfg_value(path)
	return v as Dictionary if v is Dictionary else {}


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _days_per_quarter() -> int:
	return maxi(_bi("tiempo.jornadas_por_trimestre"), 1)


func _days_per_year() -> int:
	return _days_per_quarter() * maxi(_cfg_int("calendar.quarters_per_year"), 1)


func _share_count() -> int:
	return maxi(_cfg_int("shares.share_count"), 1)


## Fundamentales reales de Company (por jornada); los de partida si Company aún no da cifras.
func _fundamentals() -> Dictionary:
	var f: Dictionary = Company.get_fundamentals()
	return _starting_fundamentals if _is_blank_figures(f) else f


func _is_blank_figures(f: Dictionary) -> bool:
	return is_zero_approx(float(f.get("revenue", 0.0))) and is_zero_approx(float(f.get("costs", 0.0)))


func _reported_figures() -> Dictionary:
	var reported: Dictionary = Company.get_reported_figures()
	return _fundamentals() if _is_blank_figures(reported) else reported


func _reported_quarter_profit() -> float:
	return float(_reported_figures().get("profit", 0.0)) * float(_days_per_quarter())


func _player_occupation_id() -> String:
	var occupation: OccupationData = PlayerState.get_occupation()
	return occupation.id if occupation != null else ""


# ═══ Privado: cotización ══════════════════════════════════════════════

func _roll_daily_noise() -> void:
	var amplitude: float = _bf("mercado.ruido_diario_max")
	_noise_today = _rng.randf_range(-amplitude, amplitude)


func _last_close() -> float:
	return _history[_history.size() - 1] if not _history.is_empty() else _price


func _percent_change(from_value: float, to_value: float) -> float:
	if is_zero_approx(from_value):
		return 0.0
	return (to_value - from_value) / from_value * PERCENT_SCALE


func _push_close(value: float) -> void:
	_history.append(value)
	var keep: int = maxi(_bi("mercado.dias_historico"), _bi("mercado.dias_momentum") + 1)
	while _history.size() > keep:
		_history.remove_at(0)


## Estrategia momentum: sigue la tendencia reciente (§9.6).
func _apply_trend_drift() -> void:
	var trend: float = get_momentum() / maxf(_price, _bf("mercado.precio_minimo"))
	if absf(trend) < _bf("mercado.momentum_umbral_tendencia"):
		return
	var step: int = _bi("mercado.momentum_paso_confianza") * (1 if trend > 0.0 else -1)
	for inv: InvestorData in _investors:
		if inv.strategy == STRATEGY_MOMENTUM:
			modify_investor_confidence(inv.id, step, REASON_TREND)


func _on_hour_passed(hour: int, day_number: int) -> void:
	if hour > _bi("tiempo.hora_inicio_jornada") and hour <= _bi("tiempo.hora_fin_jornada"):
		tick_hourly()
	_check_presentation_due(hour, day_number)


func _on_day_advanced(day_number: int) -> void:
	advance_day(day_number)


func _check_presentation_due(hour: int, day_number: int) -> void:
	var quarter: int = quarter_of(day_number)
	if quarter == _due_emitted_quarter:
		return
	if hour != _cfg_int("calendar.results_presentation.hour"):
		return
	if day_in_quarter(day_number) != _cfg_int("calendar.results_presentation.day_of_quarter"):
		return
	_due_emitted_quarter = quarter
	EventBus.results_presentation_due.emit(quarter)


func _calendar_event_on(periodicity: String, day_number: int) -> bool:
	match periodicity:
		PERIOD_DAILY:
			return true
		PERIOD_WEEKLY:
			return day_number > 0 and day_number % maxi(_bi("tiempo.jornadas_por_semana"), 1) == 0
		PERIOD_MONTHLY:
			return day_number > 0 and day_number % maxi(_bi("tiempo.jornadas_por_mes"), 1) == 0
		PERIOD_QUARTERLY:
			return day_in_quarter(day_number) == _cfg_int("calendar.results_presentation.day_of_quarter")
		PERIOD_ANNUAL:
			return day_number > 0 and day_number % _days_per_year() == 0
	return false


# ═══ Privado: inversores ══════════════════════════════════════════════

func _reset_investors() -> void:
	_confidence.clear()
	_last_reason.clear()
	_activist_targets.clear()
	_credibility_lost = false
	for inv: InvestorData in _investors:
		_confidence[inv.id] = inv.initial_confidence


func _investor(investor_id: String) -> InvestorData:
	for inv: InvestorData in _investors:
		if inv.id == investor_id:
			return inv
	return null


func _all_investor_ids() -> Array[String]:
	var ids: Array[String] = []
	for inv: InvestorData in _investors:
		ids.append(inv.id)
	return ids


func _strategy_float(inv: InvestorData, key: String) -> float:
	var strategy: Dictionary = _strategies.get(inv.strategy, {})
	return float(strategy.get(key, 0.0))


## Atención no fundamental de la estrategia (sentimiento + dirección + soplos).
func _soft_weight(inv: InvestorData) -> float:
	return _strategy_float(inv, "weight_sentiment") + _strategy_float(inv, "weight_management") \
			+ _strategy_float(inv, "weight_tips")


## Quién reacciona a prensa (§9.6): valor ignora el sentimiento; momentum y cazador leen titulares;
## el activista reacciona a escándalos (dirección); el pasivo solo a desastres (≥ reaction_threshold).
func _reacts_to_press(inv: InvestorData, magnitude: float, is_scandal: bool) -> bool:
	var threshold: float = _strategy_float(inv, "reaction_threshold")
	if threshold > 0.0:
		return is_scandal and magnitude >= threshold
	if _strategy_float(inv, "weight_sentiment") >= _bf("mercado.umbral_reaccion_prensa"):
		return true
	return is_scandal and _strategy_float(inv, "weight_management") > 0.0


func _on_news_published(headline_id: String, sentiment_delta: float, is_scandal: bool) -> void:
	var item: Dictionary = NewsFeed.get_news(headline_id)
	var subject: String = str(item.get("subject", NewsFeedSystem.SUBJECT_COMPANY))
	if str(item.get("source", "")) == NewsFeedSystem.SOURCE_AUDIT:
		return
	if is_scandal and not NewsFeedSystem.is_corporate_subject(subject):
		return
	if not is_scandal and sentiment_delta <= 0.0:
		return
	var magnitude: float = absf(sentiment_delta)
	var reactors: Array[String] = []
	for inv: InvestorData in _investors:
		if _reacts_to_press(inv, magnitude, is_scandal):
			reactors.append(inv.id)
	var severity: float = clampf(magnitude / _bf("mercado.sentimiento_referencia_prensa"), 0.0, 1.0)
	apply_confidence_factor(FACTOR_SCANDAL if is_scandal else FACTOR_PRESS, severity, reactors)


## Falsificación descubierta: −25 a −40 a todos, pérdida permanente de credibilidad y del múltiplo.
func _on_audit_triggered(discrepancy_found: bool) -> void:
	if not discrepancy_found:
		return
	apply_confidence_factor(FACTOR_FRAUD, _figures_divergence_severity(), _all_investor_ids())
	if _cfg_bool("confidence_factors.falsification_permanent_credibility_loss"):
		_credibility_lost = true
	_fraud_multiple_penalty += _bf("mercado.penalizacion_multiplo_fraude")


func _figures_divergence_severity() -> float:
	var real: float = float(_fundamentals().get("profit", 0.0))
	var reported: float = float(_reported_figures().get("profit", 0.0))
	var divergence: float = absf(reported - real) / maxf(absf(real), 1.0)
	return clampf(divergence / _bf("mercado.presentacion_rango_sorpresa"), 0.0, 1.0)


func is_credibility_lost() -> bool:
	return _credibility_lost


## Al cruzar a la baja umbral_perdida_confianza, el inversor ejecuta su on_confidence_loss:
## impulso de sentimiento (× social_reach) y, el activista, campaña contra la dirección.
func _check_confidence_loss(investor_id: String, old_value: int, new_value: int) -> void:
	var threshold: int = _bi("mercado.umbral_perdida_confianza")
	if old_value < threshold or new_value >= threshold:
		return
	var inv: InvestorData = _investor(investor_id)
	if inv == null or inv.on_confidence_loss.is_empty():
		return
	var reach: float = float(inv.extra.get("social_reach", 1.0))
	var impulse: float = _bf("mercado.impulsos_perdida_confianza." + inv.on_confidence_loss)
	_add_own_sentiment(impulse * reach)
	if inv.on_confidence_loss == BEHAVIOUR_CAMPAIGN and get_activist_target(investor_id).is_empty():
		_activist_targets[investor_id] = PLAYER_ID


func _add_own_sentiment(delta: float) -> void:
	var cap: float = _bf("mercado.sentimiento_max")
	_own_sentiment = clampf(_own_sentiment + delta, -cap, cap)


func _load_investor_state(data: Dictionary) -> void:
	_reset_investors()
	var saved: Variant = data.get("confidence", {})
	if saved is Dictionary:
		for key: Variant in (saved as Dictionary).keys():
			if _confidence.has(str(key)):
				_confidence[str(key)] = int((saved as Dictionary)[key])
	_last_reason = (data.get("last_reason", {}) as Dictionary).duplicate()
	_activist_targets = (data.get("activist_targets", {}) as Dictionary).duplicate()
	_credibility_lost = bool(data.get("credibility_lost", false))


# ═══ Privado: presentación y trimestre ════════════════════════════════

func _reset_quarter_state() -> void:
	_bad_quarters_streak = 0
	_presented_quarter = 0
	_due_emitted_quarter = 0
	_last_presentation = {}
	_expected_quarter_profit = float(_fundamentals().get("profit", 0.0)) * float(_days_per_quarter())


func _presentation_quality(preparation: float, allies_present: int, reputation: float) -> float:
	return _cfg_float("presentation.weight_preparation") * clampf(preparation, 0.0, 1.0) \
			+ _cfg_float("presentation.weight_reputation") \
			* clampf(reputation / PERCENT_SCALE, 0.0, 1.0) \
			+ _cfg_float("presentation.weight_allies") * get_allies_ratio(allies_present)


## Fase de reacción: cada inversor pondera calidad (60 %) y cifras (40 %) según su estrategia.
func _run_presentation(quality: float) -> Dictionary:
	var figures: float = get_figures_score()
	var before: float = get_aggregate_confidence()
	var changes: Dictionary = {}
	for inv: InvestorData in _investors:
		var delta: int = _outcome_delta(inv, _perceived_outcome(inv, quality, figures))
		var old_value: int = get_investor_confidence(inv.id)
		modify_investor_confidence(inv.id, delta, FACTOR_ABOVE if delta > 0 else FACTOR_BELOW)
		changes[inv.id] = get_investor_confidence(inv.id) - old_value
	var sentiment_delta: float = _sentiment_from_changes(changes)
	_add_own_sentiment(sentiment_delta)
	_expected_quarter_profit = _reported_quarter_profit()
	_last_presentation = {
		"quality": quality, "confidence_changes": changes, "sentiment_delta": sentiment_delta,
		"outcome": _bf("mercado.peso_presentacion_calidad") * quality
				+ _bf("mercado.peso_presentacion_cifras") * figures,
		"figures_score": figures, "aggregate_before": before,
		"aggregate_after": get_aggregate_confidence(), "quarter": quarter_of(_today),
	}
	return _last_presentation.duplicate(true)


## Resultado percibido por un inversor: (wq·s·calidad + wf·f·cifras) ÷ (wq·s + wf·f), con
## wq/wf = 0,6/0,4 y s/f = atención no fundamental/fundamental de su estrategia.
func _perceived_outcome(inv: InvestorData, quality: float, figures: float) -> float:
	var wq: float = _bf("mercado.peso_presentacion_calidad") * _soft_weight(inv)
	var wf: float = _bf("mercado.peso_presentacion_cifras") * _strategy_float(inv, "weight_fundamentals")
	if wq + wf <= 0.0:
		return figures
	return (wq * quality + wf * figures) / (wq + wf)


func _outcome_delta(inv: InvestorData, perceived: float) -> int:
	var deviation: float = perceived - OUTCOME_NEUTRAL
	var magnitude: float = absf(deviation)
	var threshold: float = _strategy_float(inv, "reaction_threshold")
	var band: float = _bf("mercado.presentacion_banda_neutra")
	if (threshold > 0.0 and magnitude < threshold) or magnitude <= band:
		return 0
	var severity: float = (magnitude - band) / (OUTCOME_NEUTRAL - band)
	return get_factor_delta(FACTOR_ABOVE if deviation > 0.0 else FACTOR_BELOW, severity)


## Δsentimiento = Σ Δconfianza_i × voz_i ÷ 100 × sentimiento_por_confianza;
## voz_i = capital_i/Σcapital + (social_reach_i − 1) × peso_alcance_social.
func _sentiment_from_changes(changes: Dictionary) -> float:
	var capital: float = 0.0
	for inv: InvestorData in _investors:
		capital += float(inv.capital)
	if capital <= 0.0:
		return 0.0
	var total: float = 0.0
	for inv: InvestorData in _investors:
		var voice: float = float(inv.capital) / capital \
				+ (float(inv.extra.get("social_reach", 1.0)) - 1.0) * _bf("mercado.peso_alcance_social")
		total += float(changes.get(inv.id, 0)) * voice
	return total / PERCENT_SCALE * _bf("mercado.sentimiento_por_confianza")


func _on_quarter_closed(quarter_number: int) -> void:
	if _presented_quarter != quarter_number:
		_run_presentation(_presentation_quality(_bf("mercado.preparacion_presentador_npc"),
				_bi("mercado.aliados_presentador_npc"), _bf("mercado.reputacion_presentador_npc")))
		_presented_quarter = quarter_number
	_update_bad_quarter_streak(quarter_number)
	if quarter_number % maxi(_cfg_int("calendar.quarters_per_year"), 1) == 0:
		_pay_dividends()
	EventBus.quarter_reported.emit(_fundamentals().duplicate(), _reported_figures().duplicate())


func _update_bad_quarter_streak(quarter_number: int) -> void:
	if PlayerState.get_rank() < _cfg_int("board_pressure.applies_from_rank"):
		_bad_quarters_streak = 0
	elif get_aggregate_confidence() >= get_target_for_quarter(quarter_number):
		_bad_quarters_streak = 0
	else:
		_bad_quarters_streak += 1


func _append_results_preview(out: Array[String], days_ahead: int) -> void:
	var days_left: int = get_presentation_day() - _today
	var horizon: int = mini(days_ahead, _cfg_int("insider_detection.news_lead_days_max"))
	if days_left < 0 or days_left > horizon or _presented_quarter == quarter_of(_today):
		return
	var deviation: float = get_figures_score() - OUTCOME_NEUTRAL
	if absf(deviation) <= _bf("mercado.presentacion_banda_neutra"):
		out.append(HEADLINE_RESULTS_INLINE)
	else:
		out.append(HEADLINE_RESULTS_BEAT if deviation > 0.0 else HEADLINE_RESULTS_MISS)


func _load_quarter_state(data: Dictionary) -> void:
	_bad_quarters_streak = int(data.get("bad_streak", 0))
	_presented_quarter = int(data.get("presented_quarter", 0))
	_due_emitted_quarter = int(data.get("due_emitted_quarter", 0))
	_expected_quarter_profit = float(data.get("expected_profit", 0.0))
	var last: Variant = data.get("last_presentation", {})
	_last_presentation = (last as Dictionary).duplicate(true) if last is Dictionary else {}


# ═══ Privado: cartera e insider ═══════════════════════════════════════

func _reset_portfolio() -> void:
	_player_shares = 0
	_stake_shares = 0
	_invested = 0.0
	_dividends_paid = 0
	_insider_ops.clear()
	_insider_detections = 0


func _pay_dividends() -> void:
	var amount: int = get_dividend_income()
	if amount <= 0:
		return
	_dividends_paid += amount
	_settle_cash(amount, CASH_REASON_DIVIDENDS)


## El capital es de PlayerState: se comunica el movimiento por la señal EXT (si existe).
func _settle_cash(amount: int, reason: String) -> void:
	if amount != 0 and EventBus.has_signal(CASH_SIGNAL):
		EventBus.emit_signal(CASH_SIGNAL, amount, reason)


func _insider_detection_disabled() -> bool:
	return _cfg_bool("insider_detection.zero_if_player_is_auditor") \
			and _player_occupation_id() == _cfg_string("insider_detection.auditor_occupation")


## Espaciar las operaciones es una contramedida: solo cuentan las de la ventana de jornadas.
func _prune_insider_ops() -> void:
	var window: int = _bi("mercado.ventana_patron_insider_jornadas")
	var kept: Array[Dictionary] = []
	for op: Dictionary in _insider_ops:
		if _today - int(op["day"]) < window:
			kept.append(op)
	_insider_ops = kept


func _load_portfolio_state(data: Dictionary) -> void:
	_player_shares = int(data.get("shares", 0))
	_stake_shares = int(data.get("stake_shares", 0))
	_invested = float(data.get("invested", 0.0))
	_dividends_paid = int(data.get("dividends_paid", 0))
	_insider_detections = int(data.get("insider_detections", 0))
	_insider_ops.clear()
	for entry: Variant in data.get("insider_ops", []):
		if entry is Dictionary:
			_insider_ops.append({"day": int((entry as Dictionary).get("day", 0)),
					"volume": int((entry as Dictionary).get("volume", 0))})
