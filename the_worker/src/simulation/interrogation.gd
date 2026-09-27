# interrogation.gd — Reglas de la escena de interrogatorio (§12.5) y la sesión que la escena conduce.
# PROPIETARIO DE: el estado de UNA sesión de interrogatorio en curso (la crea la escena de la sala).
# ESCUCHA: nada.
class_name Interrogation
extends RefCounted

## Uso (escena interrogation_room de P15, PASO 29):
##   var s := Interrogation.new(case_id)            # contexto opcional (ver abajo)
##   var intro := s.start()                         # {tone, intro_key, interrogator, pieces}
##   while not s.is_finished():
##       var piece := s.current_piece()             # se presentan de una en una (secuencial)
##       var result := s.answer("deny")             # o "explain", "accuse_other" (+ acusado),
##                                                  #   "silence", "request_lawyer"
##   var end := s.finish()                          # {success, total_weight, verdict}
## Las reglas puras son estáticas (rule_*). La sesión es código "manos" (BUILD_NOTES §2): aplica
## los efectos con la API pública de Security (retirar, duplicar o trasladar piezas, congelar el
## caso) y de NPCDirector (agravio del acusado y de sus aliados), y emite interrogation_answered.
## La subida de sospecha (+5 por silencio, +8 por negación rechazada, datos de
## investigations.json) la aplica BeliefNet al escuchar interrogation_answered; la sesión la
## acumula en get_suspicion_delta() y la descuenta ya dentro de la escena.
## Contexto (todas opcionales; si faltan se leen del juego): reputation, suspicion,
## alibi ({provider, genuine}), has_legal_contact, verification_roll (0-1, sustituye la tirada).

const ANSWER_DENY := "deny"
const ANSWER_EXPLAIN := "explain"
const ANSWER_ACCUSE := "accuse_other"
const ANSWER_SILENCE := "silence"
const ANSWER_LAWYER := "request_lawyer"
const ANSWERS: Array[String] = [
	ANSWER_DENY, ANSWER_EXPLAIN, ANSWER_ACCUSE, ANSWER_SILENCE, ANSWER_LAWYER,
]

const TONE_APOLOGY := "apology"
const TONE_DOOR_SLAM := "door_slam"
const TONE_NEUTRAL := "neutral"

## Resultados (4.º parámetro de interrogation_answered).
const OUTCOME_PIECE_REMOVED := "piece_removed"
const OUTCOME_DENIAL_REJECTED := "denial_rejected"
const OUTCOME_ALIBI_ACCEPTED := "alibi_accepted"
const OUTCOME_ALIBI_FALSE := "alibi_false"
const OUTCOME_PIECE_TRANSFERRED := "piece_transferred"
const OUTCOME_SILENCE := "silence_kept"
const OUTCOME_CASE_FROZEN := "case_frozen"
const OUTCOME_REQUIREMENT_MISSING := "requirement_missing"
const OUTCOME_NO_PIECE := "no_piece"

const OUTCOME_KEY_PREFIX := "INTERROGATION_OUTCOME_"
const B_DENY_DISCOUNT := "seguridad.interrogatorio_sospecha_descuenta_negar"
const B_ALLY_GRIEVANCE := "seguridad.gravedad_agravio_aliados"
const B_ALLY_STRENGTH := "seguridad.fuerza_minima_aliado"
const B_FREEZE_DAYS := "investigaciones.dias_congelacion_por_abogado"
const GRIEVANCE_ACCUSED := "accused_in_interrogation"
const GRIEVANCE_ALLY := "ally_accused"
const SALT := "interrogation"

var case_id: String = ""
var _rules: Dictionary = {}
var _context: Dictionary = {}
## record_id de las piezas presentadas, en orden (instantánea al empezar).
var _queue: Array[String] = []
var _index: int = 0
var _ended: bool = false
var _started: bool = false
var _suspicion_delta: int = 0
var _log: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_case_id: String, context: Dictionary = {}) -> void:
	case_id = p_case_id
	_context = context.duplicate(true)
	_rules = load_rules()
	_rng.seed = hash(SALT + p_case_id) ^ GameClock.get_run_seed()


# ─── Reglas (datos) ───────────────────────────────────────────

## Umbrales y efectos de §12.5 leídos de investigations.json (interrogation) y balance.json.
static func load_rules() -> Dictionary:
	var block: Dictionary = Database.get_investigation_params().get("interrogation", {})
	var answers: Array = block.get("answers", [])
	var deny: Dictionary = InvestigationEngine.find_by_id(answers, ANSWER_DENY)
	var explain: Dictionary = InvestigationEngine.find_by_id(answers, ANSWER_EXPLAIN)
	var accuse: Dictionary = InvestigationEngine.find_by_id(answers, ANSWER_ACCUSE)
	var silence: Dictionary = InvestigationEngine.find_by_id(answers, ANSWER_SILENCE)
	return {
		"deny_reputation_above": float(_dig(deny, "removes_piece_if.reputation_above")),
		"deny_weight_below": float(_dig(deny, "removes_piece_if.piece_weight_below")),
		"deny_fail_suspicion": int(deny.get("on_failure_suspicion_delta", 0)),
		"deny_discount_suspicion": Database.get_balance_float(B_DENY_DISCOUNT),
		"false_alibi_multiplier": float(explain.get("false_alibi_weight_multiplier", 1.0)),
		"alibi_verification_chance": float(explain.get("bought_alibi_verification_chance", 0.0)),
		"accuse_grievance": int(accuse.get("grievance_severity", 0)),
		"ally_grievance": Database.get_balance_int(B_ALLY_GRIEVANCE),
		"ally_min_strength": Database.get_balance_float(B_ALLY_STRENGTH),
		"silence_suspicion": int(silence.get("suspicion_delta_per_use", 0)),
		"freeze_days": Database.get_balance_int(B_FREEZE_DAYS),
		"success_below": float(block.get("success_below_weight", 0.0)),
		"apology_above": float(_dig(block, "tone.apology_if_reputation_above")),
		"door_slam_above": float(_dig(block, "tone.door_slam_if_suspicion_above")),
		"intro_keys": block.get("intro_keys", {}),
		"answer_keys": _answer_keys(answers),
	}


static func _dig(data: Dictionary, path: String) -> float:
	return float(InvestigationEngine.dig(data, path, 0.0))


## Clave de texto del resultado de una respuesta (INTERROGATION_OUTCOME_*).
static func outcome_key(outcome: String) -> String:
	return OUTCOME_KEY_PREFIX + outcome.to_upper()


static func _answer_keys(answers: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in answers:
		if entry is Dictionary:
			out[str(entry.get("id", ""))] = str(entry.get("name_key", ""))
	return out


## Detalle de tono (§12.5): sospecha > 70 → portazo; si no, reputación > 85 → disculpa.
## Con ambas condiciones manda el portazo (la sospecha es lo que abre el caso).
static func opening_tone(reputation: float, suspicion: float, rules: Dictionary) -> String:
	if suspicion > float(rules["door_slam_above"]):
		return TONE_DOOR_SLAM
	if reputation > float(rules["apology_above"]):
		return TONE_APOLOGY
	return TONE_NEUTRAL


## Negar: retira la pieza si reputación > 60 y peso < 2,0 (§12.5), salvo que la sospecha
## descuente los desmentidos (§7.10); si no, sube la sospecha.
static func rule_deny(piece_weight: float, reputation: float, suspicion: float,
		rules: Dictionary) -> Dictionary:
	var believed: bool = reputation > float(rules["deny_reputation_above"]) \
			and piece_weight < float(rules["deny_weight_below"]) \
			and suspicion <= float(rules["deny_discount_suspicion"])
	if believed:
		return _result(OUTCOME_PIECE_REMOVED, {"remove": true})
	return _result(OUTCOME_DENIAL_REJECTED,
			{"suspicion_delta": int(rules["deny_fail_suspicion"])})


## Explicar: exige coartada. Real → retira la pieza. Comprada o prestada → se verifica con la
## probabilidad de datos: si se descubre falsa, el peso de la pieza se duplica.
static func rule_explain(alibi: Dictionary, verification_roll: float,
		rules: Dictionary) -> Dictionary:
	if alibi.is_empty():
		return _result(OUTCOME_REQUIREMENT_MISSING, {"consumes_turn": false})
	if bool(alibi.get("genuine", false)) \
			or verification_roll >= float(rules["alibi_verification_chance"]):
		return _result(OUTCOME_ALIBI_ACCEPTED, {"remove": true})
	return _result(OUTCOME_ALIBI_FALSE,
			{"weight_multiplier": float(rules["false_alibi_multiplier"])})


## Acusar a otro: traslada la pieza al acusado; agravio permanente y hostilidad de sus aliados.
static func rule_accuse(accused: String, rules: Dictionary) -> Dictionary:
	if not InvestigationEngine.is_identified(accused) \
			or accused == InvestigationEngine.SUBJECT_PLAYER:
		return _result(OUTCOME_REQUIREMENT_MISSING, {"consumes_turn": false})
	return _result(OUTCOME_PIECE_TRANSFERRED, {
		"new_subject": accused, "grievance_severity": int(rules["accuse_grievance"])})


## Silencio: el peso no cambia; +5 de sospecha por uso.
static func rule_silence(rules: Dictionary) -> Dictionary:
	return _result(OUTCOME_SILENCE, {"suspicion_delta": int(rules["silence_suspicion"])})


## Asistencia legal: exige contacto en el bufete de P9; congela el caso tres jornadas.
static func rule_lawyer(has_contact: bool, rules: Dictionary) -> Dictionary:
	if not has_contact:
		return _result(OUTCOME_REQUIREMENT_MISSING, {"consumes_turn": false})
	return _result(OUTCOME_CASE_FROZEN, {"freeze_days": int(rules["freeze_days"])})


## Condición de éxito: peso total del caso contra el jugador por debajo de 7,0.
static func is_success(total_weight: float, rules: Dictionary) -> bool:
	return total_weight < float(rules["success_below"])


static func _result(outcome: String, fields: Dictionary) -> Dictionary:
	var out: Dictionary = {"outcome": outcome, "remove": false, "weight_multiplier": 1.0,
			"new_subject": "", "suspicion_delta": 0, "freeze_days": 0, "grievance_severity": 0,
			"consumes_turn": true}
	out.merge(fields, true)
	return out


# ─── Sesión ───────────────────────────────────────────────────

## Abre la escena: fija las piezas a presentar y avisa a Security (fase 4 en curso).
func start() -> Dictionary:
	var inv: Investigation = Security.get_investigation(case_id)
	_started = true
	if inv == null:
		_ended = true
		return {}
	var player: String = InvestigationEngine.SUBJECT_PLAYER
	for piece: Dictionary in InvestigationEngine.pieces_against(inv, player):
		_queue.append(str(piece.get("record_id", "")))
	Security.begin_interrogation(case_id)
	return {"tone": get_opening_tone(), "intro_key": get_opening_key(),
			"interrogator": Security.get_interrogator(case_id), "pieces": _queue.size()}


func get_opening_tone() -> String:
	return opening_tone(_reputation(), _suspicion(), _rules)


func get_opening_key() -> String:
	return str((_rules["intro_keys"] as Dictionary).get(get_opening_tone(), ""))


func get_answer_key(answer_id: String) -> String:
	return str((_rules["answer_keys"] as Dictionary).get(answer_id, ""))


func get_rules() -> Dictionary:
	return _rules.duplicate(true)


## Respuestas utilizables ahora (explicar exige coartada; abogado exige contacto en P9).
func available_answers() -> Array[String]:
	var out: Array[String] = [ANSWER_DENY]
	if not _alibi().is_empty():
		out.append(ANSWER_EXPLAIN)
	out.append_array([ANSWER_ACCUSE, ANSWER_SILENCE])
	if _has_legal_contact():
		out.append(ANSWER_LAWYER)
	return out


## Pieza que el investigador tiene sobre la mesa ({} si ya no quedan).
func current_piece() -> Dictionary:
	var inv: Investigation = Security.get_investigation(case_id)
	while inv != null and not _ended and _index < _queue.size():
		var i: int = InvestigationEngine.find_piece(inv, _queue[_index])
		if i >= 0:
			return inv.evidence[i].duplicate()
		_index += 1
	return {}


func get_current_index() -> int:
	return _index


func get_piece_count() -> int:
	return _queue.size()


func is_finished() -> bool:
	return _ended or current_piece().is_empty()


## Responde a la pieza actual. `accused` solo para "accuse_other". → resultado de rule_*.
func answer(answer_id: String, accused: String = "") -> Dictionary:
	var piece: Dictionary = current_piece()
	if piece.is_empty() or not ANSWERS.has(answer_id):
		return _result(OUTCOME_NO_PIECE, {"consumes_turn": false})
	var result: Dictionary = _resolve(answer_id, piece, accused)
	_apply(result, piece)
	EventBus.interrogation_answered.emit(case_id, _index, answer_id, str(result["outcome"]))
	_log.append({"index": _index, "answer": answer_id, "outcome": result["outcome"],
			"record_id": piece.get("record_id", "")})
	if bool(result["consumes_turn"]):
		_index += 1
	if str(result["outcome"]) == OUTCOME_CASE_FROZEN:
		_ended = true
	return result


## Cierra la escena y devuelve {success, total_weight, verdict} (Security decide la fase 5).
func finish() -> Dictionary:
	_ended = true
	return Security.finish_interrogation(case_id)


func get_suspicion_delta() -> int:
	return _suspicion_delta


func get_log() -> Array[Dictionary]:
	return _log.duplicate(true)


func _resolve(answer_id: String, piece: Dictionary, accused: String) -> Dictionary:
	var weight: float = float(piece.get("weight", 0.0))
	match answer_id:
		ANSWER_DENY:
			return rule_deny(weight, _reputation(), _suspicion(), _rules)
		ANSWER_EXPLAIN:
			return rule_explain(_alibi(), _verification_roll(), _rules)
		ANSWER_ACCUSE:
			return rule_accuse(accused, _rules)
		ANSWER_SILENCE:
			return rule_silence(_rules)
	return rule_lawyer(_has_legal_contact(), _rules)


func _apply(result: Dictionary, piece: Dictionary) -> void:
	var record_id: String = str(piece.get("record_id", ""))
	_suspicion_delta += int(result["suspicion_delta"])
	if bool(result["remove"]):
		Security.remove_evidence(case_id, record_id, str(result["outcome"]))
	elif float(result["weight_multiplier"]) != 1.0:
		Security.scale_evidence(case_id, record_id, float(result["weight_multiplier"]))
	elif not str(result["new_subject"]).is_empty():
		_apply_accusation(record_id, str(result["new_subject"]), int(result["grievance_severity"]))
	elif int(result["freeze_days"]) > 0:
		Security.freeze_case(case_id, int(result["freeze_days"]))


func _apply_accusation(record_id: String, accused: String, severity: int) -> void:
	Security.transfer_evidence(case_id, record_id, accused)
	NPCDirector.add_grievance(accused, GRIEVANCE_ACCUSED, severity)
	for ally: String in SocialGraph.get_neighbours(accused, float(_rules["ally_min_strength"])):
		if ally != InvestigationEngine.SUBJECT_PLAYER:
			NPCDirector.add_grievance(ally, GRIEVANCE_ALLY, int(_rules["ally_grievance"]))


func _reputation() -> float:
	return float(_context.get("reputation", PlayerState.get_reputation()))


## La sospecha de la escena incluye lo que las respuestas ya han sumado.
func _suspicion() -> float:
	return float(_context.get("suspicion", Security.get_known_suspicion())) + _suspicion_delta


func _alibi() -> Dictionary:
	if _context.has("alibi"):
		return _context["alibi"]
	return Security.get_alibi(case_id)


func _has_legal_contact() -> bool:
	return bool(_context.get("has_legal_contact", Security.has_legal_contact()))


func _verification_roll() -> float:
	if _context.has("verification_roll"):
		return float(_context["verification_roll"])
	return _rng.randf()
