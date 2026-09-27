# idea_presentation.gd — La escena de la sala Aurora (§11.2): mérito, choque de credibilidad y consecuencias.
# PROPIETARIO DE: nada (librería estática: el estado de ideas y reuniones vive en IdeaPool).
# ESCUCHA: nada.
class_name IdeaPresentation
extends RefCounted

## Manual §11.2, §10.4, PASO 24; BUILD_NOTES §2, §12-§13.
## · Funciones puras: presentation_factor, compute_merit, accuser_credibility, player_credibility,
##   classify, resolve_contest. IdeaPool (autoload) las usa para resolver y registrar.
## · Contexto del choque (build_context): lecturas de solo consulta a PlayerState, NPCDirector e
##   IdeaPool. Claves: player_reputation, player_suspicion, allies, accuser_reputation, believers,
##   attendees. Cualquier clave puede forzarse con `overrides` (escenas guionizadas, tests, F1).
## · "Manos" (BUILD_NOTES §2): summon_attendees, seat_attendee, release_attendees, prepare*,
##   present_player_idea y apply_consequences mueven personajes y aplican los efectos sobre otros
##   sistemas.
## CONTRATO DE LA ESCENA AURORA (src/ui/aurora_scene.gd, World):
##  1. Al oír aurora_meeting_started → summon_attendees(): lleva a aurora_room a los convocados
##     DISPONIBLES (no a quien otro sistema haya enviado a otra sala en esta franja) y marca la
##     reunión como física: desde ese momento está presente quien NPCDirector sitúa en la sala.
##  2. El jugador presenta SIEMPRE con present_player_idea(idea_id): abre la presentación en
##     IdeaPool (stage_presentation), la resuelve con IdeaPool.present() (§19.11) y aplica el mérito
##     y las consecuencias. Llamar IdeaPool.present() sin abrirla no gasta la idea
##     (status "not_staged").
##  3. Al cerrar, release_attendees(IdeaPool.get_meeting_invitees()).
## DECISIONES:
##  · creyentes de «la idea era suya» = personajes de Idea.known_by distintos del propietario y del
##    jugador (quienes conocen la idea saben de quién es; IdeaPool.share_idea los añade).
##  · aliado presente = asistente (≠ acusador) con afecto ≥ ideas.afecto_minimo_aliado o que debe un
##    favor al jugador (ledger.debt > 0).
##  · reputación de un personaje = NPCDirector.get_npc_reputation (también 0: un acusador
##    desacreditado no recupera nada); ideas.reputacion_npc_por_defecto solo para ids sin personaje.
##  · empate «ambos +10 de sospecha»: la sospecha es la del jugador y deriva de BeliefNet, así que se
##    levanta un acta de la reunión (registro board_minutes, §7.6) sobre el jugador con el peso que
##    aporta exactamente ideas.sospecha_empate puntos (BeliefNet.weight_for_suspicion_points con la
##    certeza 1 y la credibilidad por defecto de un registro). Los personajes no tienen medidor de
##    sospecha (§7.2): la parte del acusador queda como acta de la reunión a su nombre (registro
##    documental, affects_suspicion = false), material para investigaciones e incriminaciones.
##  · victoria: el usurpador pierde 15 de reputación vía NPCDirector.modify_npc_reputation.
##  · derrota: la creencia «roba ideas» se guarda con certeza EXACTA ideas.certeza_creencia_roba_ideas
##    (0,85) en cada presente: la cifra explícita de §11.2 prevalece sobre la rebaja genérica por
##    reputación de §7.10 (se crea y, si BeliefNet la rebajó, se refuerza hasta 0,85).
##  · preparación con A.S.S.I.S.T.: misma lotería 60/25/15 de §10.4 (RNG de IdeaPool); excelente
##    da el mérito menor; fallo evidente lo detecta un personaje con Perspicacia > 60 en la sala
##    del jugador (reputación y anotación, como en DutySystem). El factor sigue siendo 0,8.
##  · el agravio "idea_stolen" del propietario (§7.9) lo pone NPCDirector al oír idea_acquired.

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
const MERIT_SOURCE := "idea_presented"
const REASON_CONTEST_LOST := "aurora_contest_lost"
const REASON_FALSE_ACCUSATION := "aurora_false_accusation"
const ASSIST_TASK := "idea_presentation"
const NOTE_CATEGORY := "ideas"
const NOTE_PRESENTED := "NOTE_IDEA_PRESENTED"
const NOTE_BY_RESULT: Dictionary = {
	RESULT_WIN: "NOTE_IDEA_CONTEST_WIN", RESULT_TIE: "NOTE_IDEA_CONTEST_TIE",
	RESULT_LOSS: "NOTE_IDEA_CONTEST_LOSS",
}
## Escala de los medidores de reputación (0–100, §7.2/§7.10): rango, no ajuste.
const METER_SCALE := 100.0
## Un registro nace con certeza 1 (§7.6).
const RECORD_CERTAINTY := 1.0

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
const B_REAL_PREP_MINUTES := "ideas.minutos_preparacion_real"


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


## Reputación de un personaje (BUILD_NOTES §13: NPCDirector.get_npc_reputation, 0 incluido); solo
## un id sin personaje usa ideas.reputacion_npc_por_defecto.
static func npc_reputation(npc_id: String) -> float:
	if NPCDirector.get_npc(npc_id) != null:
		return NPCDirector.get_npc_reputation(npc_id)
	return Database.get_balance_float(B_NPC_REPUTATION)


# ─── Manos: preparación ───────────────────────────────────────

## "real" consume ideas.minutos_preparacion_real de reloj; "assist" sortea A.S.S.I.S.T. (§10.4).
static func prepare(idea_id: String, preparation: String) -> bool:
	return bool(prepare_detailed(idea_id, preparation)["ok"])


## Como prepare(); devuelve {ok, preparation, minutes} y, con A.S.S.I.S.T., el detalle de
## apply_assist_preparation.
static func prepare_detailed(idea_id: String, preparation: String) -> Dictionary:
	var result: Dictionary = {"ok": IdeaPool.set_preparation(idea_id, preparation),
			"preparation": preparation, "minutes": 0.0}
	if result["ok"] and preparation == PREP_ASSIST:
		return apply_assist_preparation(idea_id, IdeaPool.roll_assist_outcome())
	if result["ok"] and preparation == PREP_REAL:
		result["minutes"] = Database.get_balance_float(B_REAL_PREP_MINUTES)
		GameClock.advance_minutes(float(result["minutes"]))
	return result


## Preparación con A.S.S.I.S.T. con un resultado dado (prepare lo sortea). Excelente: mérito menor;
## fallo evidente: detección por un personaje perspicaz en la sala del jugador. Todo uso emite
## assist_used (rastro digital, DutySystem.get_assist_log).
static func apply_assist_preparation(idea_id: String, outcome: String) -> Dictionary:
	var result: Dictionary = {"ok": IdeaPool.set_preparation(idea_id, PREP_ASSIST),
			"preparation": PREP_ASSIST, "minutes": 0.0, "outcome": outcome, "merit": 0,
			"detected_by": "", "reputation_delta": 0.0, "annotated": false}
	if not result["ok"]:
		return result
	if outcome == DutySystem.ASSIST_EXCELLENT:
		result["merit"] = Database.get_balance_int(DutySystem.B_ASSIST_MERIT)
		Company.register_merit(DutySystem.MERIT_SOURCE_ASSIST, int(result["merit"]))
	elif outcome == DutySystem.ASSIST_FAILURE:
		var room: String = PlayerState.get_room()
		var witness: NPCRuntime = DutySystem.perceptive_witness(NPCDirector.get_npcs_in_room(room))
		result.merge(DutySystem.expose_evident_failure(witness, room), true)
	EventBus.assist_used.emit(ASSIST_TASK, outcome)
	return result


# ─── Manos: asistentes ────────────────────────────────────────

## Lleva a aurora_room, durante la franja en curso, a los convocados disponibles (quien tiene otra
## sala forzada para la franja se queda fuera) y marca la reunión como física. Devuelve cuántos.
static func summon_attendees() -> int:
	if not IdeaPool.is_meeting_open():
		return 0
	var moved: int = 0
	for npc_id: String in IdeaPool.get_meeting_invitees():
		if _move_to_room(npc_id):
			moved += 1
	IdeaPool.mark_meeting_staged()
	return moved


## Convoca a un personaje concreto y, si está disponible, lo sienta en la sala.
static func seat_attendee(npc_id: String) -> bool:
	return IdeaPool.add_meeting_attendee(npc_id) and _move_to_room(npc_id)


static func release_attendees(attendees: Array[String]) -> void:
	var band: String = GameClock.get_current_band()
	for npc_id: String in attendees:
		NPCDirector.override_routine(npc_id, band, "")


static func _move_to_room(npc_id: String) -> bool:
	if not IdeaPool.is_available_for_meeting(npc_id):
		return false
	NPCDirector.override_routine(npc_id, GameClock.get_current_band(), AURORA_ROOM)
	return true


# ─── Manos: presentación y consecuencias ──────────────────────

## Punto de entrada de la escena Aurora. Devuelve el resultado de IdeaPool.present() más "effects"
## (efectos aplicados a otros sistemas). Si la escena aún no convocó a nadie, convoca primero.
static func present_player_idea(idea_id: String, overrides: Dictionary = {}) -> Dictionary:
	if IdeaPool.is_meeting_open() and not IdeaPool.is_meeting_staged():
		summon_attendees()
	IdeaPool.stage_presentation(idea_id, overrides)
	var result: Dictionary = IdeaPool.present(idea_id)
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
	match str(result.get("contest_result", "")):
		RESULT_WIN:
			_punish_usurper(accuser, effects)
		RESULT_TIE:
			_record_tie(accuser, effects)
		RESULT_LOSS:
			_punish_player(result, effects)
	return effects


## Peso de registro que aporta exactamente `points` puntos de sospecha (BeliefNet: certeza 1 y
## credibilidad por defecto del archivo que sostiene los registros).
static func suspicion_record_weight(points: float) -> float:
	return BeliefNet.weight_for_suspicion_points(points, RECORD_CERTAINTY)


static func _punish_usurper(accuser: String, effects: Array[Dictionary]) -> void:
	var delta: float = Database.get_balance_float(B_ACCUSER_REPUTATION)
	var applied: bool = NPCDirector.get_npc(accuser) != null
	var before: float = npc_reputation(accuser)
	if applied:
		NPCDirector.modify_npc_reputation(accuser, delta, REASON_FALSE_ACCUSATION)
	effects.append({"kind": "npc_reputation", "npc_id": accuser, "delta": delta,
			"applied": applied, "before": before, "after": npc_reputation(accuser)})


static func _record_tie(accuser: String, effects: Array[Dictionary]) -> void:
	var points: float = Database.get_balance_float(B_TIE_SUSPICION)
	var weight: float = suspicion_record_weight(points)
	for subject: String in [PLAYER_ID, accuser]:
		var record_id: String = BeliefNet.create_record(RECORD_MINUTES, subject, weight,
				AURORA_ROOM)
		effects.append({"kind": "suspicion_record", "subject": subject, "points": points,
				"weight": weight, "record_id": record_id,
				"affects_suspicion": subject == PLAYER_ID})


static func _punish_player(result: Dictionary, effects: Array[Dictionary]) -> void:
	var delta: float = Database.get_balance_float(B_LOSS_REPUTATION)
	PlayerState.modify_reputation(delta, REASON_CONTEST_LOST)
	effects.append({"kind": "player_reputation", "delta": delta})
	var certainty: float = Database.get_balance_float(B_STEALS_CERTAINTY)
	for holder: String in _witnesses(result):
		var belief_id: String = _hold_steals_ideas(holder, certainty)
		effects.append({"kind": "belief", "holder": holder, "fact": FACT_STEALS_IDEAS,
				"certainty": certainty, "belief_id": belief_id})


## Crea (o refuerza) la creencia «roba ideas» de `holder` y la deja con certeza ≥ `certainty`.
static func _hold_steals_ideas(holder: String, certainty: float) -> String:
	var belief_id: String = BeliefNet.create_belief(holder, PLAYER_ID, FACT_STEALS_IDEAS,
			certainty, BELIEF_SOURCE_DIRECT, AURORA_ROOM)
	var belief: Belief = BeliefNet.get_belief(belief_id)
	if belief != null and belief.certainty < certainty:
		BeliefNet.reinforce_belief(belief_id, certainty - belief.certainty)
	return belief_id


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
