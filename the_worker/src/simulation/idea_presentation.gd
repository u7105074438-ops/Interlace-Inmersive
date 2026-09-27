# idea_presentation.gd — La escena de la sala Aurora (§11.2): mérito, choque de credibilidad y consecuencias.
# PROPIETARIO DE: nada (librería estática: el estado de ideas y reuniones vive en IdeaPool).
# ESCUCHA: nada.
class_name IdeaPresentation
extends RefCounted

## Manual §11.2, PASO 24; BUILD_NOTES §12-§13.
## · Funciones puras: presentation_factor, compute_merit, accuser_credibility, player_credibility,
##   classify, resolve_contest. IdeaPool (autoload) las usa para resolver y registrar.
## · Contexto del choque (build_context): lecturas de solo consulta a PlayerState, NPCDirector e
##   IdeaPool. Claves: player_reputation, player_suspicion, allies, accuser_reputation, believers,
##   attendees. Cualquier clave puede forzarse con `overrides` (escenas guionizadas, tests, F1).
## · "Manos" (BUILD_NOTES §2): present_player_idea() y apply_consequences() aplican los efectos
##   sobre otros sistemas. La escena Aurora (src/ui/aurora_scene.gd) llama a present_player_idea().
## DECISIONES:
##  · creyentes de «la idea era suya» = personajes de Idea.known_by distintos del propietario y del
##    jugador (quienes conocen la idea saben de quién es; IdeaPool.share_idea los añade).
##  · aliado presente = asistente (≠ acusador) con afecto ≥ ideas.afecto_minimo_aliado o que debe un
##    favor al jugador (ledger.debt > 0).
##  · empate «ambos +10 de sospecha»: la sospecha deriva de BeliefNet, así que se levanta un acta de
##    la reunión (registro board_minutes, §7.6) sobre cada parte con el peso que equivale a
##    ideas.sospecha_empate puntos en la fórmula de BeliefNet (suspicion_record_weight). Es un
##    registro: no decae y solo desaparece destruyéndolo.
##  · victoria: el usurpador pierde 15 de reputación vía NPCDirector.modify_npc_reputation (si existe).
##  · todo choque deja al propietario un agravio "idea_stolen" (§7.9).

const PREP_NONE := "none"
const PREP_ASSIST := "assist"
const PREP_REAL := "real"
const PREPARATIONS: Array[String] = [PREP_NONE, PREP_ASSIST, PREP_REAL]
const RESULT_WIN := "win"
const RESULT_TIE := "tie"
const RESULT_LOSS := "loss"
const PLAYER_ID := "player"
const AURORA_ROOM := "aurora_room"
const FACT_STEALS_IDEAS := "steals_ideas"
const RECORD_MINUTES := "board_minutes"
const BELIEF_SOURCE_DIRECT := "direct"
const GRIEVANCE_IDEA_STOLEN := "idea_stolen"
const MERIT_SOURCE := "idea_presented"
const REASON_CONTEST_LOST := "aurora_contest_lost"
const REASON_FALSE_ACCUSATION := "aurora_false_accusation"
const ASSIST_TASK := "idea_presentation"
const ASSIST_RESULT := "acceptable"
const NOTE_CATEGORY := "ideas"
const NOTE_PRESENTED := "NOTE_IDEA_PRESENTED"
const NOTE_BY_RESULT: Dictionary = {
	RESULT_WIN: "NOTE_IDEA_CONTEST_WIN", RESULT_TIE: "NOTE_IDEA_CONTEST_TIE",
	RESULT_LOSS: "NOTE_IDEA_CONTEST_LOSS",
}
## Escala de los medidores de reputación y sospecha (0–100, §7.2/§7.10): rango, no ajuste.
const METER_SCALE := 100.0
const NPC_REPUTATION_GETTER := "get_npc_reputation"
const NPC_REPUTATION_SETTER := "modify_npc_reputation"
const CREDIBILITY_GETTER := "get_credibility"
## Portador genérico (no personaje) para la credibilidad de un registro en BeliefNet.
const NON_CHARACTER_HOLDER := ""

const B_FACTOR_NONE := "ideas.factor_presentacion_sin_preparar"
const B_FACTOR_ASSIST := "ideas.factor_presentacion_assist"
const B_FACTOR_REAL := "ideas.factor_presentacion_real"
const B_MERIT_BASE := "ideas.merito_base_reputacion"
const B_MERIT_WEIGHT := "ideas.merito_peso_reputacion"
const B_PER_BELIEVER := "ideas.credibilidad_por_creyente"
const B_PER_ALLY := "ideas.credibilidad_por_aliado"
const B_PER_SUSPICION := "ideas.credibilidad_por_sospecha"
const B_CLASH_THRESHOLD := "ideas.umbral_diferencia_choque"
const B_LOSS_REPUTATION := "ideas.penalizacion_reputacion_derrota_choque"
const B_ACCUSER_REPUTATION := "ideas.penalizacion_reputacion_acusador_fallido"
const B_STEALS_CERTAINTY := "ideas.certeza_creencia_roba_ideas"
const B_TIE_SUSPICION := "ideas.sospecha_empate"
const B_ALLY_AFFECTION := "ideas.afecto_minimo_aliado"
const B_NPC_REPUTATION := "ideas.reputacion_npc_por_defecto"
const B_GRIEVANCE := "ideas.gravedad_agravio_idea_robada"
const B_REAL_PREP_MINUTES := "ideas.minutos_preparacion_real"
const B_SUSPICION_DIVISOR := "creencias.divisor_normalizacion"
const B_RECORD_ORIGIN := "creencias.peso_origen.record"


# ─── Fórmulas puras (§11.2) ───────────────────────────────────

## factor_presentación ∈ {0,6 sin preparación · 0,8 con A.S.S.I.S.T. · 1,0 con preparación real}.
static func presentation_factor(preparation: String) -> float:
	match preparation:
		PREP_ASSIST:
			return Database.get_balance_float(B_FACTOR_ASSIST)
		PREP_REAL:
			return Database.get_balance_float(B_FACTOR_REAL)
		_:
			return Database.get_balance_float(B_FACTOR_NONE)


## mérito = calidad × factor × (0,7 + 0,3 × reputación / 100), redondeado.
static func compute_merit(quality: int, preparation: String, reputation: float) -> int:
	var rep_term: float = Database.get_balance_float(B_MERIT_BASE) \
			+ Database.get_balance_float(B_MERIT_WEIGHT) * reputation / METER_SCALE
	return maxi(roundi(float(quality) * presentation_factor(preparation) * rep_term), 0)


## credibilidad_acusador = reputación_acusador + 20 × creyentes de «la idea era suya».
static func accuser_credibility(accuser_reputation: float, believers: int) -> float:
	return accuser_reputation + Database.get_balance_float(B_PER_BELIEVER) * float(believers)


## credibilidad_jugador = reputación + 15 × aliados presentes − 0,5 × sospecha.
static func player_credibility(reputation: float, allies: int, suspicion: float) -> float:
	return reputation + Database.get_balance_float(B_PER_ALLY) * float(allies) \
			- Database.get_balance_float(B_PER_SUSPICION) * suspicion


## difference = credibilidad_jugador − credibilidad_acusador. > 20 victoria; < −20 derrota;
## en otro caso (|diferencia| ≤ 20) empate.
static func classify(difference: float) -> String:
	var threshold: float = Database.get_balance_float(B_CLASH_THRESHOLD)
	if difference > threshold:
		return RESULT_WIN
	if difference < -threshold:
		return RESULT_LOSS
	return RESULT_TIE


## Devuelve {result, player_credibility, accuser_credibility, difference}.
static func resolve_contest(context: Dictionary) -> Dictionary:
	var player: float = player_credibility(float(context.get("player_reputation", 0.0)),
			int(context.get("allies", 0)), float(context.get("player_suspicion", 0.0)))
	var accuser: float = accuser_credibility(float(context.get("accuser_reputation", 0.0)),
			int(context.get("believers", 0)))
	return {
		"result": classify(player - accuser), "player_credibility": player,
		"accuser_credibility": accuser, "difference": player - accuser,
	}


# ─── Contexto del choque (solo lectura) ───────────────────────

static func build_context(idea: Idea, accuser: String, attendees: Array[String]) -> Dictionary:
	return {
		"player_reputation": PlayerState.get_reputation(),
		"player_suspicion": PlayerState.get_suspicion(),
		"allies": count_allies(attendees, accuser),
		"accuser_reputation": npc_reputation(accuser),
		"believers": count_believers(idea),
		"attendees": attendees.duplicate(),
	}


static func count_believers(idea: Idea) -> int:
	var count: int = 0
	for npc_id: String in idea.known_by:
		if npc_id != idea.owner and npc_id != PLAYER_ID and not IdeaPool.is_owner_gone(npc_id):
			count += 1
	return count


static func count_allies(attendees: Array[String], accuser: String) -> int:
	var count: int = 0
	for npc_id: String in attendees:
		if npc_id != accuser and npc_id != PLAYER_ID and is_ally(npc_id):
			count += 1
	return count


static func is_ally(npc_id: String) -> bool:
	return NPCDirector.get_affection(npc_id) >= Database.get_balance_int(B_ALLY_AFFECTION) \
			or NPCDirector.get_debt(npc_id) > 0


## Reputación de un personaje (BUILD_NOTES §13: NPCDirector.get_npc_reputation); sin dato, la
## de ideas.reputacion_npc_por_defecto.
static func npc_reputation(npc_id: String) -> float:
	if NPCDirector.has_method(NPC_REPUTATION_GETTER):
		var value: float = float(NPCDirector.call(NPC_REPUTATION_GETTER, npc_id))
		if value > 0.0:
			return value
	return Database.get_balance_float(B_NPC_REPUTATION)


# ─── Manos: preparación, presentación y consecuencias ─────────

## "real" consume ideas.minutos_preparacion_real de reloj; "assist" deja rastro (assist_used).
static func prepare(idea_id: String, preparation: String) -> bool:
	if not IdeaPool.set_preparation(idea_id, preparation):
		return false
	if preparation == PREP_REAL:
		GameClock.advance_minutes(Database.get_balance_float(B_REAL_PREP_MINUTES))
	elif preparation == PREP_ASSIST:
		EventBus.assist_used.emit(ASSIST_TASK, ASSIST_RESULT)
	return true


## Punto de entrada de la escena Aurora. Devuelve el resultado de IdeaPool.present_with_context
## más "effects" (lista de efectos aplicados a otros sistemas).
static func present_player_idea(idea_id: String, overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = IdeaPool.present_with_context(idea_id, overrides)
	result["effects"] = apply_consequences(result)
	_write_notebook(result)
	return result


static func apply_consequences(result: Dictionary) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	if str(result.get("status", "")) != IdeaPool.STATUS_OK:
		return effects
	var merit: int = int(result.get("merit", 0))
	if merit > 0:
		Company.register_merit(MERIT_SOURCE, merit)
		effects.append({"kind": "merit", "amount": merit})
	if not bool(result.get("contested", false)):
		return effects
	var accuser: String = str(result.get("accuser", ""))
	_add_grievance(accuser, effects)
	match str(result.get("contest_result", "")):
		RESULT_WIN:
			_punish_usurper(accuser, effects)
		RESULT_TIE:
			_record_tie(accuser, effects)
		RESULT_LOSS:
			_punish_player(result, effects)
	return effects


## Peso de registro que equivale a `points` puntos de sospecha en BeliefNet:
## contribución = certeza(1) × credibilidad × peso × peso_origen.record × 100 / divisor.
static func suspicion_record_weight(points: float) -> float:
	var credibility: float = 1.0
	if BeliefNet.has_method(CREDIBILITY_GETTER):
		credibility = float(BeliefNet.call(CREDIBILITY_GETTER, NON_CHARACTER_HOLDER))
	var divisor: float = _balance_or(B_SUSPICION_DIVISOR, METER_SCALE)
	var origin: float = _balance_or(B_RECORD_ORIGIN, 1.0)
	var per_weight: float = credibility * origin * METER_SCALE / divisor
	return points / per_weight if per_weight > 0.0 else points


static func _add_grievance(accuser: String, effects: Array[Dictionary]) -> void:
	var severity: int = Database.get_balance_int(B_GRIEVANCE)
	NPCDirector.add_grievance(accuser, GRIEVANCE_IDEA_STOLEN, severity)
	effects.append({"kind": "grievance", "npc_id": accuser, "type": GRIEVANCE_IDEA_STOLEN,
			"severity": severity})


static func _punish_usurper(accuser: String, effects: Array[Dictionary]) -> void:
	var delta: float = Database.get_balance_float(B_ACCUSER_REPUTATION)
	var applied: bool = NPCDirector.has_method(NPC_REPUTATION_SETTER)
	if applied:
		NPCDirector.call(NPC_REPUTATION_SETTER, accuser, delta, REASON_FALSE_ACCUSATION)
	effects.append({"kind": "npc_reputation", "npc_id": accuser, "delta": delta,
			"applied": applied})


static func _record_tie(accuser: String, effects: Array[Dictionary]) -> void:
	var points: float = Database.get_balance_float(B_TIE_SUSPICION)
	var weight: float = suspicion_record_weight(points)
	for subject: String in [PLAYER_ID, accuser]:
		var record_id: String = BeliefNet.create_record(RECORD_MINUTES, subject, weight,
				AURORA_ROOM)
		effects.append({"kind": "suspicion_record", "subject": subject, "points": points,
				"weight": weight, "record_id": record_id})


static func _punish_player(result: Dictionary, effects: Array[Dictionary]) -> void:
	var delta: float = Database.get_balance_float(B_LOSS_REPUTATION)
	PlayerState.modify_reputation(delta, REASON_CONTEST_LOST)
	effects.append({"kind": "player_reputation", "delta": delta})
	var certainty: float = Database.get_balance_float(B_STEALS_CERTAINTY)
	for holder: String in _witnesses(result):
		var belief_id: String = BeliefNet.create_belief(holder, PLAYER_ID, FACT_STEALS_IDEAS,
				certainty, BELIEF_SOURCE_DIRECT, AURORA_ROOM)
		effects.append({"kind": "belief", "holder": holder, "fact": FACT_STEALS_IDEAS,
				"certainty": certainty, "belief_id": belief_id})


## Quienes presenciaron la derrota: los asistentes más el acusador, sin repetir.
static func _witnesses(result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var accuser: String = str(result.get("accuser", ""))
	if not accuser.is_empty():
		out.append(accuser)
	for npc_id: Variant in result.get("attendees", []):
		var id: String = str(npc_id)
		if not id.is_empty() and id != PLAYER_ID and not out.has(id):
			out.append(id)
	return out


static func _write_notebook(result: Dictionary) -> void:
	if str(result.get("status", "")) != IdeaPool.STATUS_OK:
		return
	if bool(result.get("contested", false)):
		var key: String = str(NOTE_BY_RESULT.get(str(result.get("contest_result", "")), ""))
		if not key.is_empty():
			var accuser_name: String = IdeaPool.get_npc_display_name(str(result.get("accuser", "")))
			EventBus.notebook_entry_added.emit(NOTE_CATEGORY, key, [accuser_name])
	if int(result.get("merit", 0)) > 0:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_PRESENTED, [int(result["merit"])])


static func _balance_or(path: String, fallback: float) -> float:
	if Database.has_balance(path):
		return Database.get_balance_float(path)
	return fallback
