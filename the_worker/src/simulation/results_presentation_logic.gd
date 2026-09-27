# results_presentation_logic.gd — Las tres fases de la presentación trimestral de resultados (§9.5) que conduce la UI.
# PROPIETARIO DE: el estado de UNA presentación en curso (fase, cifras elegidas, preparación, aliados, resultado); nada global.
# ESCUCHA: nada.
class_name ResultsPresentation
extends RefCounted

## Uso (la UI de la sala de resultados, al recibir results_presentation_due):
##   var p := ResultsPresentation.new(quarter)
##   Fase 1 PREPARACIÓN: get_real_figures() / get_reported_figures(); keep_real_figures() o
##          report_inflated_figures(0.15) (→ Company.set_reported_figures: si diverge, Company
##          enciende la mecha de auditoría); confirm_figures().
##   Fase 2 PRESENTACIÓN: select_preparation("none"|"assist"|"stolen_coo_report"|"real_work"),
##          set_allies_present(n) / add_ally(); get_quality_preview(); present().
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

var quarter: int = 0
var phase: Phase = Phase.PREPARATION
var _preparation_id: String = LEVEL_NONE
var _allies_present: int = 0
var _inflation: float = 0.0
var _confidence_before: Dictionary = {}
var _result: Dictionary = {}


func _init(quarter_number: int = 0) -> void:
	quarter = quarter_number


func get_phase_name_key() -> String:
	return PHASE_NAME_KEYS[int(phase)]


# ─── Fase 1: preparación ──────────────────────────────────────────────

## Fundamentales reales de la compañía (por jornada).
func get_real_figures() -> Dictionary:
	return Company.get_fundamentals()


## Cifras que se comunicarán al mercado (las reales si no hay otras).
func get_reported_figures() -> Dictionary:
	var reported: Dictionary = Company.get_reported_figures()
	return get_real_figures() if reported.is_empty() else reported


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


## Aliados en sala (inversores sobornados con pregunta favorable, colegas aliados).
func set_allies_present(count: int) -> void:
	_allies_present = maxi(count, 0)


func add_ally() -> void:
	_allies_present += 1


func get_allies_present() -> int:
	return _allies_present


func get_quality_preview() -> float:
	return Market.compute_presentation_quality(get_preparation_value(), _allies_present)


## Ejecuta la presentación (Market calcula calidad y reacción). Pasa a la fase de reacción.
func present() -> Dictionary:
	if phase != Phase.PRESENTATION:
		return {}
	_confidence_before.clear()
	for inv: InvestorData in Market.get_investors():
		_confidence_before[inv.id] = Market.get_investor_confidence(inv.id)
	_result = Market.conduct_quarterly_presentation(get_preparation_value(), _allies_present)
	if _preparation_id == LEVEL_REAL_WORK:
		EventBus.tracking_event_recorded.emit(TRACKING_AXIS,
				Database.get_balance_int("seguimiento.sudor_por_presentacion_preparada"),
				TRACKING_SOURCE)
	phase = Phase.REACTION
	return _result.duplicate(true)


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
	summary["allies_present"] = _allies_present
	summary["inflation"] = _inflation
	summary["target"] = Market.get_quarterly_target()
	summary["meeting_target"] = Market.is_meeting_target()
	return summary


func finish() -> void:
	if phase == Phase.REACTION:
		phase = Phase.FINISHED


static func _same_figures(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["revenue", "profit"]:
		if not is_equal_approx(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			return false
	return not a.is_empty()
