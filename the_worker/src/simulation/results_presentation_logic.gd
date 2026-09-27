# results_presentation_logic.gd — Las tres fases de la presentación trimestral de resultados (§9.5) que conduce la UI, con sus manipulaciones (soborno y chantaje de inversores, A.S.S.I.S.T.).
# PROPIETARIO DE: el estado de UNA presentación en curso (fase, cifras elegidas, preparación, resultado de A.S.S.I.S.T., resultado); nada global.
# ESCUCHA: nada.
class_name ResultsPresentation
extends RefCounted

## Uso (la UI de la sala de resultados, al recibir results_presentation_due):
##   var p := ResultsPresentation.new(quarter)
##   Antes o durante: ResultsPresentation.bribe_investor(id, importe, canal) (pregunta favorable,
##          solo inversores sobornables) / blackmail_investor(id, material) (chantajeables; el
##          activista coaccionado se dirige con Market.direct_activist). Aliados = los que acepten.
##   Fase 1 PREPARACIÓN: get_quarter_real_figures() / get_quarter_reported_figures();
##          keep_real_figures() o report_inflated_figures(0.15) (→ Company.set_reported_figures:
##          si diverge, Company enciende la mecha de auditoría); confirm_figures().
##   Fase 2 PRESENTACIÓN: select_preparation("none"|"assist"|"stolen_coo_report"|"real_work");
##          get_quality_preview(); present() (solo el día de resultados: Market.can_present_results).
##          "assist" sortea §10.4 (60/25/15): emite assist_used; el fallo evidente deja la
##          preparación en 0 y, si algún inversor tiene perspicacia > umbral, cuesta reputación y
##          una anotación en el expediente.
##   Fase 3 REACCIÓN: get_reaction_rows(), get_summary(); finish().
## Es "manos" del juego (BUILD_NOTES §2): puede llamar a APIs mutadoras de los autoloads.

enum Phase { PREPARATION, PRESENTATION, REACTION, FINISHED }

const LEVEL_NONE := "none"
const LEVEL_ASSIST := "assist"
const LEVEL_STOLEN_REPORT := "stolen_coo_report"
const LEVEL_REAL_WORK := "real_work"
const TRACKING_AXIS := "sweat"
const TRACKING_SOURCE := "presentation_prepared"
const PHASE_NAME_KEYS: Array[String] = [
	"PRES_PHASE_PREPARATION", "PRES_PHASE_PRESENTATION", "PRES_PHASE_REACTION",
	"PRES_PHASE_FINISHED",
]
const PLAYER_ID := "player"
const OFFICE_ROOM_KEY := "office_room"

# A.S.S.I.S.T. (§10.4): mismos resultados y ajustes que DutySystem.
const ASSIST_ACCEPTABLE := "acceptable"
const ASSIST_EXCELLENT := "excellent"
const ASSIST_FAILURE := "evident_failure"
const ASSIST_TASK_TYPE := "results_presentation"
const ASSIST_SALT := "results_presentation_assist"
const MERIT_SOURCE_ASSIST := "assist_excellent"
const REASON_ASSIST_DETECTED := "assist_evident_failure"
const RECORD_FILE_NOTE := "stamped_document"
const TRAIT_PERCEPTION := "perception"

var quarter: int = 0
var phase: Phase = Phase.PREPARATION
var _preparation_id: String = LEVEL_NONE
var _inflation: float = 0.0
var _assist_outcome: String = ""
var _assist_detected_by: Array[String] = []
var _confidence_before: Dictionary = {}
var _result: Dictionary = {}


func _init(quarter_number: int = 0) -> void:
	quarter = quarter_number


func get_phase_name_key() -> String:
	return PHASE_NAME_KEYS[int(phase)]


# ─── Manipulación de la sala (§9.5, §9.6) ─────────────────────────────

## Soborna a un inversor para que formule una pregunta favorable. Bribery con un sustituto del
## inversor (su referencia diaria de investors.json en lugar de salario); Market lo marca aliado
## al oír bribe_result. Insobornable → {ok: false, outcome: "invalid"} sin señales.
static func bribe_investor(investor_id: String, amount: int, channel_id: String,
		ctx: Dictionary = {}) -> Dictionary:
	if not Market.is_investor_bribable(investor_id):
		return {"ok": false, "outcome": Bribery.OUTCOME_INVALID, "amount": amount,
				"text_key": Bribery.OUTCOME_TEXT_KEYS[Bribery.OUTCOME_INVALID]}
	var context: Dictionary = ctx.duplicate()
	context["daily_wage"] = Market.get_investor_bribe_reference(investor_id)
	return Bribery.offer(investor_proxy(investor_id), amount,
			Market.get_favourable_question_favour(), channel_id, context)


## Precio justo (§8.2, con dificultad y sospecha) de la pregunta favorable; 0 si es insobornable.
static func investor_bribe_price(investor_id: String) -> int:
	if not Market.is_investor_bribable(investor_id):
		return 0
	return Bribery.fair_price(investor_proxy(investor_id), Market.get_favourable_question_favour(),
			{"daily_wage": Market.get_investor_bribe_reference(investor_id)})


## Chantaje con material (`leverage`) a un inversor chantajeable: queda coaccionado este trimestre
## (aliado en la sala; al activista se le puede dirigir con Market.direct_activist).
static func blackmail_investor(investor_id: String, leverage: String) -> bool:
	if leverage.is_empty() or not Market.is_investor_blackmailable(investor_id):
		return false
	EventBus.blackmail_initiated.emit(investor_id, investor_id, leverage)
	return Market.is_investor_coerced(investor_id)


## Personaje sustituto con los rasgos del inversor (para Bribery; no entra en NPCDirector).
static func investor_proxy(investor_id: String) -> NPCRuntime:
	var inv: InvestorData = Market.get_investor(investor_id)
	var npc: NPCRuntime = NPCRuntime.new()
	if inv == null:
		npc.alive = false
		return npc
	npc.id = inv.id
	npc.name = inv.name
	npc.traits = inv.traits.duplicate()
	npc.current_room = str(inv.extra.get(OFFICE_ROOM_KEY, ""))
	return npc


# ─── Fase 1: preparación ──────────────────────────────────────────────

## Fundamentales reales de la compañía (por jornada).
func get_real_figures() -> Dictionary:
	return Company.get_fundamentals()


## Cifras que se comunicarán al mercado (las reales si no hay otras), por jornada.
func get_reported_figures() -> Dictionary:
	var reported: Dictionary = Company.get_reported_figures()
	return get_real_figures() if reported.is_empty() else reported


## Totales del trimestre (acumulado + proyección) que se juzgarán: reales y reportados.
func get_quarter_real_figures() -> Dictionary:
	return Market.get_quarter_real_figures(true)


func get_quarter_reported_figures() -> Dictionary:
	return Market.get_quarter_reported_figures(true)


func get_inflation() -> float:
	return _inflation


## Cifras reales + inflado de ingresos (beneficio = ingresos inflados − costes reales).
static func inflate_figures(real: Dictionary, inflation: float) -> Dictionary:
	var out: Dictionary = real.duplicate()
	var revenue: float = float(real.get("revenue", 0.0)) * (1.0 + inflation)
	out["revenue"] = revenue
	out["profit"] = revenue - float(real.get("costs", 0.0))
	return out


## Comunica las cifras reales. Devuelve true si Company las acepta como reportadas.
func keep_real_figures() -> bool:
	return report_inflated_figures(0.0)


## Inflar mejora la reacción inmediata a cambio de la mecha de auditoría (§9.2, §9.5).
## Company decide si el cargo del jugador está autorizado; devuelve si se aceptaron.
func report_inflated_figures(inflation: float) -> bool:
	if phase != Phase.PREPARATION:
		return false
	var cap: float = Database.get_balance_float("mercado.inflado_maximo_reportado")
	var figures: Dictionary = inflate_figures(get_real_figures(), clampf(inflation, 0.0, cap))
	Company.set_reported_figures(figures)
	var accepted: bool = _same_figures(Company.get_reported_figures(), figures)
	if accepted:
		_inflation = clampf(inflation, 0.0, cap)
	return accepted


func confirm_figures() -> void:
	if phase == Phase.PREPARATION:
		phase = Phase.PRESENTATION


# ─── Fase 2: la presentación ──────────────────────────────────────────

## {id: nivel} de market.json: none 0,0 · assist 0,5 · stolen_coo_report 0,8 · real_work 1,0.
func get_preparation_levels() -> Dictionary:
	return Market.get_preparation_levels()


func select_preparation(level_id: String) -> bool:
	if phase != Phase.PRESENTATION or not get_preparation_levels().has(level_id):
		return false
	_preparation_id = level_id
	return true


func get_preparation_id() -> String:
	return _preparation_id


func get_preparation_value() -> float:
	return float(get_preparation_levels().get(_preparation_id, 0.0))


## Aliados en sala: inversores sobornados (pregunta favorable) o chantajeados este trimestre.
func get_allies_present() -> int:
	return Market.get_investor_allies().size()


func get_quality_preview() -> float:
	return Market.compute_presentation_quality(get_preparation_value(), get_allies_present())


## Fija el resultado de A.S.S.I.S.T. antes de presentar (depuración y pruebas).
func force_assist_outcome(outcome: String) -> void:
	_assist_outcome = outcome


func get_assist_outcome() -> String:
	return _assist_outcome


## Ejecuta la presentación (Market calcula calidad y reacción) y pasa a la fase de reacción.
## {} si no se puede presentar hoy (Market.can_present_results) o la fase no es la 2.
func present() -> Dictionary:
	if phase != Phase.PRESENTATION or not Market.can_present_results():
		return {}
	_confidence_before.clear()
	for inv: InvestorData in Market.get_investors():
		_confidence_before[inv.id] = Market.get_investor_confidence(inv.id)
	var preparation: float = get_preparation_value()
	if _preparation_id == LEVEL_ASSIST:
		preparation = _apply_assist()
	_result = Market.conduct_quarterly_presentation(preparation, get_allies_present())
	_result["assist_outcome"] = _assist_outcome
	_result["assist_detected_by"] = _assist_detected_by.duplicate()
	if _preparation_id == LEVEL_REAL_WORK:
		EventBus.tracking_event_recorded.emit(TRACKING_AXIS,
				Database.get_balance_int("seguimiento.sudor_por_presentacion_preparada"),
				TRACKING_SOURCE)
	phase = Phase.REACTION
	return _result.duplicate(true)


## §10.4 (lotería 60/25/15 de deberes.assist_prob_*), determinista por partida y trimestre.
static func roll_assist_outcome(roll: float) -> String:
	var w_ok: float = Database.get_balance_float("deberes.assist_prob_aceptable")
	var w_excellent: float = Database.get_balance_float("deberes.assist_prob_excelente")
	var w_failure: float = Database.get_balance_float("deberes.assist_prob_desastre")
	var point: float = clampf(roll, 0.0, 1.0) * (w_ok + w_excellent + w_failure)
	if point < w_failure:
		return ASSIST_FAILURE
	if point < w_failure + w_excellent:
		return ASSIST_EXCELLENT
	return ASSIST_ACCEPTABLE


func assist_roll() -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([GameClock.get_run_seed(), quarter, ASSIST_SALT])
	return rng.randf()


## Inversores que detectan un fallo evidente (perspicacia > deberes.assist_umbral_deteccion_perspicacia).
static func assist_detectors() -> Array[String]:
	var out: Array[String] = []
	var threshold: int = Database.get_balance_int("deberes.assist_umbral_deteccion_perspicacia")
	for inv: InvestorData in Market.get_investors():
		if inv.get_trait(TRAIT_PERCEPTION) > threshold:
			out.append(inv.id)
	return out


# ─── Fase 3: reacción ─────────────────────────────────────────────────

## Una fila por inversor: {investor_id, name, strategy, before, after, delta}.
func get_reaction_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for inv: InvestorData in Market.get_investors():
		var before: int = int(_confidence_before.get(inv.id, Market.get_investor_confidence(inv.id)))
		var after: int = Market.get_investor_confidence(inv.id)
		rows.append({"investor_id": inv.id, "name": inv.name, "strategy": inv.strategy,
				"before": before, "after": after, "delta": after - before})
	return rows


## Resultado de Market + objetivo trimestral y si se cumple.
func get_summary() -> Dictionary:
	var summary: Dictionary = _result.duplicate(true)
	summary["quarter"] = quarter
	summary["preparation_id"] = _preparation_id
	summary["allies_present"] = get_allies_present()
	summary["inflation"] = _inflation
	summary["target"] = Market.get_quarterly_target()
	summary["meeting_target"] = Market.is_meeting_target()
	return summary


func finish() -> void:
	if phase == Phase.REACTION:
		phase = Phase.FINISHED


# ─── Privado ──────────────────────────────────────────────────────────

## Aplica el resultado de A.S.S.I.S.T. y devuelve la preparación efectiva (0 si fallo evidente).
func _apply_assist() -> float:
	if _assist_outcome.is_empty():
		_assist_outcome = roll_assist_outcome(assist_roll())
	EventBus.assist_used.emit(ASSIST_TASK_TYPE, _assist_outcome)
	if _assist_outcome == ASSIST_EXCELLENT:
		Company.register_merit(MERIT_SOURCE_ASSIST,
				Database.get_balance_int("deberes.assist_merito_excelente"))
	if _assist_outcome != ASSIST_FAILURE:
		return get_preparation_value()
	_assist_detected_by = assist_detectors()
	if not _assist_detected_by.is_empty():
		PlayerState.modify_reputation(
				Database.get_balance_float("deberes.assist_penalizacion_reputacion_detectado"),
				REASON_ASSIST_DETECTED)
		BeliefNet.create_record(RECORD_FILE_NOTE, PLAYER_ID,
				Database.get_balance_float("deberes.assist_peso_anotacion_expediente"),
				Market.get_presentation_room())
	return float(get_preparation_levels().get(LEVEL_NONE, 0.0))


static func _same_figures(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["revenue", "profit"]:
		if not is_equal_approx(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			return false
	return not a.is_empty()
