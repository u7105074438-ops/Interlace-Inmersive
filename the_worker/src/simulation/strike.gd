# strike.gd — Conflicto laboral (§11.7): las cuatro acciones del jugador (agitar, apaciguar, liderar, traicionar) sobre el descontento de Company y sus efectos en reputaciones y registros.
# PROPIETARIO DE: nada (descontento, huelga, agitación, líder y prestigio laboral los guarda Company; la reputación, PlayerState; los registros de los personajes, NPCDirector).
# ESCUCHA: nada.
class_name Strike
extends RefCounted

## Manual §11.7, §9.12 (huelga: ambos cerebros); PASO 41; BUILD_NOTES §2 (manos), §12.
## MANOS DEL MUNDO: conversación con un personaje (agitate), chat o corrillo (plant_rumour), portal
## de dirección (appease_with_concession, appease_by_firing), asamblea (lead; betray cuando el
## líder no comparece). Cada acción devuelve {ok, reason, ...}; get_reason_label_key(reason) da el
## texto; get_status() resume el conflicto para la interfaz.
## DECISIONES:
##  · Agitar (conversación): personaje en plantilla de escalón ≤ descontento.escalon_max_afectado y
##    descontento (ánimo < huelga.animo_max_descontento o algún agravio), una vez cada
##    huelga.jornadas_entre_agitaciones jornadas por personaje; imposible si el jugador traicionó
##    una huelga (nadie le escucha). Efecto: descontento inmediato + impulso diario
##    (Company.add_agitation): el descontento sube más deprisa los días siguientes.
##  · Rumor contra la dirección: SocialGraph.inject_rumour_about(destino, directivo,
##    "<huelga.hecho_rumor>:<directivo>", certeza) (emite crime_committed rumour_planted: SEDA);
##    directivo por defecto = titular de huelga.ocupacion_objetivo_rumor (si no, "company"); más
##    impulso que una conversación.
##  · Apaciguar: concesión salarial (escalón del jugador ≥ huelga.escalon_min_concesion) →
##    Company.apply_labour_event("wage_concession") (−15 y coste en nómina); despido del causante
##    (directivo de escalón > escalon_max_afectado y menor que el del jugador, con escalón ≥
##    escalon_min_despido) → NPCDirector.remove_npc(causante, huelga.causa_despido) y
##    "culprit_dismissed" (−10). Si el descontento vuelve a ≤ 70, Company da la huelga por apaciguada.
##  · Liderar (descontento > umbral): Company.call_strike("player") (estalla si no estaba activa;
##    Company fija el prestigio laboral); PlayerState.modify_reputation(reputacion_direccion_liderar)
##    —la reputación del jugador es la que juzga la dirección—; afecto + afecto_bajos_liderar a cada
##    personaje de escalones bajos y afecto_direccion_liderar a la dirección (escalón ≥
##    empresa.escalon_directivo). Sin favores ni señales por personaje (no llena la agenda).
##  · Traicionar (haberla convocado y no comparecer: exige ser su líder): strike_resolved("betrayed")
##    (Company la termina y marca la traición para siempre; NewsFeed cierra el evento), reputación +
##    reputacion_direccion_traicionar («salvó la compañía»), agravio permanente agravio_traicion a
##    cada personaje de escalones bajos (los agravios no decaen) y afecto a la dirección.
##  · Huelga activa (ambos cerebros): unidades × empresa.factor_unidades_huelga y riesgo
##    (Company), noticia negativa y evento "strike" (NewsFeed al oír strike_started), cotización a la
##    baja (Market: sentimiento y valor intrínseco). Este módulo no los duplica.

const PLAYER_ID := "player"
const RESOLUTION_BETRAYED := "betrayed"
const CAUSE_AGITATION := "agitation"
const CAUSE_TALK := "agitation_talk"
const CAUSE_RUMOUR := "agitation_rumour"
const STANDING_WORKERS := "workers"
const STANDING_MANAGEMENT := "management"
const EVENT_WAGE_CONCESSION := "wage_concession"
const EVENT_CULPRIT_DISMISSED := "culprit_dismissed"
const SUBJECT_COMPANY := "company"
const FACT_FORMAT := "%s:%s"
const NO_DAY := -1

const REASON_UNKNOWN_NPC := "unknown_npc"
const REASON_NOT_LOW_TIER := "not_low_tier"
const REASON_NOT_DISCONTENTED := "not_discontented"
const REASON_COOLDOWN := "cooldown"
const REASON_BETRAYED := "workers_betrayed"
const REASON_NO_AUTHORITY := "no_authority"
const REASON_NOT_MANAGEMENT := "not_management"
const REASON_BELOW_THRESHOLD := "below_threshold"
const REASON_ALREADY_LEADING := "already_leading"
const REASON_NOT_LEADER := "not_leader"
const REASON_RUMOUR_FAILED := "rumour_failed"
const REASON_LABEL_KEYS: Dictionary = {
	REASON_UNKNOWN_NPC: "STRIKE_REASON_UNKNOWN_NPC", REASON_NOT_LOW_TIER: "STRIKE_REASON_NOT_LOW_TIER",
	REASON_NOT_DISCONTENTED: "STRIKE_REASON_NOT_DISCONTENTED",
	REASON_COOLDOWN: "STRIKE_REASON_COOLDOWN", REASON_BETRAYED: "STRIKE_REASON_WORKERS_BETRAYED",
	REASON_NO_AUTHORITY: "STRIKE_REASON_NO_AUTHORITY",
	REASON_NOT_MANAGEMENT: "STRIKE_REASON_NOT_MANAGEMENT",
	REASON_BELOW_THRESHOLD: "STRIKE_REASON_BELOW_THRESHOLD",
	REASON_ALREADY_LEADING: "STRIKE_REASON_ALREADY_LEADING",
	REASON_NOT_LEADER: "STRIKE_REASON_NOT_LEADER", REASON_RUMOUR_FAILED: "STRIKE_REASON_RUMOUR_FAILED",
}
const REPUTATION_LED := "strike_led"
const REPUTATION_BETRAYED := "strike_betrayed"
const NOTE_CATEGORY := "labour"
const NOTE_LED := "NOTE_STRIKE_LED"
const NOTE_BETRAYED := "NOTE_STRIKE_BETRAYED"

const B_MAX_TIER := "descontento.escalon_max_afectado"
const B_EXEC_TIER := "empresa.escalon_directivo"
const B_MOOD_MAX := "huelga.animo_max_descontento"
const B_COOLDOWN := "huelga.jornadas_entre_agitaciones"
const B_TALK_DISCONTENT := "huelga.descontento_por_conversacion"
const B_TALK_AGITATION := "huelga.agitacion_por_conversacion"
const B_RUMOUR_DISCONTENT := "huelga.descontento_por_rumor"
const B_RUMOUR_AGITATION := "huelga.agitacion_por_rumor"
const B_RUMOUR_FACT := "huelga.hecho_rumor"
const B_RUMOUR_CERTAINTY := "huelga.certeza_rumor"
const B_RUMOUR_TARGET := "huelga.ocupacion_objetivo_rumor"
const B_CONCESSION_TIER := "huelga.escalon_min_concesion"
const B_FIRING_TIER := "huelga.escalon_min_despido"
const B_FIRING_CAUSE := "huelga.causa_despido"
const B_LEAD_REPUTATION := "huelga.reputacion_direccion_liderar"
const B_BETRAY_REPUTATION := "huelga.reputacion_direccion_traicionar"
const B_LEAD_LOW_AFFECTION := "huelga.afecto_bajos_liderar"
const B_LEAD_EXEC_AFFECTION := "huelga.afecto_direccion_liderar"
const B_BETRAY_EXEC_AFFECTION := "huelga.afecto_direccion_traicionar"
const B_BETRAY_GRIEVANCE := "huelga.agravio_traicion"
const B_BETRAY_SEVERITY := "huelga.gravedad_agravio_traicion"


# ─── Agitar ───────────────────────────────────────────────────

## Descontento: ánimo por debajo de huelga.animo_max_descontento o algún agravio pendiente.
static func is_discontented(npc_id: String) -> bool:
	return NPCDirector.get_mood(npc_id) < Database.get_balance_float(B_MOOD_MAX) \
			or NPCDirector.get_grievance_total(npc_id) > 0


## {allowed, reason} de una conversación de agitación con ese personaje.
static func can_agitate(npc_id: String) -> Dictionary:
	var reason: String = _low_tier_reason(npc_id)
	if reason.is_empty() and Company.are_workers_betrayed():
		reason = REASON_BETRAYED
	elif reason.is_empty() and not is_discontented(npc_id):
		reason = REASON_NOT_DISCONTENTED
	elif reason.is_empty() and _in_cooldown(npc_id):
		reason = REASON_COOLDOWN
	return {"allowed": reason.is_empty(), "reason": reason}


## Conversación con un descontento: descontento inmediato + impulso diario.
static func agitate(npc_id: String) -> Dictionary:
	var check: Dictionary = can_agitate(npc_id)
	if not bool(check["allowed"]):
		return _failure(str(check["reason"]))
	Company.add_agitation(Database.get_balance_int(B_TALK_AGITATION), npc_id)
	Company.modify_discontent(Database.get_balance_int(B_TALK_DISCONTENT), CAUSE_TALK)
	return _success({"npc_id": npc_id})


## Rumor contra la dirección plantado en un personaje de escalones bajos (manager_id "" = titular
## de huelga.ocupacion_objetivo_rumor, o la compañía).
static func plant_rumour(target_npc: String, manager_id: String = "") -> Dictionary:
	var reason: String = _low_tier_reason(target_npc)
	if not reason.is_empty():
		return _failure(reason)
	var subject: String = manager_id if not manager_id.is_empty() else _default_manager()
	var fact: String = FACT_FORMAT % [str(Database.get_balance(B_RUMOUR_FACT)), subject]
	var rumour_id: String = SocialGraph.inject_rumour_about(target_npc, subject, fact,
			Database.get_balance_float(B_RUMOUR_CERTAINTY))
	if rumour_id.is_empty():
		return _failure(REASON_RUMOUR_FAILED)
	Company.add_agitation(Database.get_balance_int(B_RUMOUR_AGITATION), "")
	Company.modify_discontent(Database.get_balance_int(B_RUMOUR_DISCONTENT), CAUSE_RUMOUR)
	return _success({"rumour_id": rumour_id, "subject": subject})


# ─── Apaciguar ────────────────────────────────────────────────

## Concesión salarial (−15 y coste directo en nómina). Solo desde la dirección.
static func appease_with_concession() -> Dictionary:
	if PlayerState.get_tier() < Database.get_balance_int(B_CONCESSION_TIER):
		return _failure(REASON_NO_AUTHORITY)
	var delta: int = Company.apply_labour_event(EVENT_WAGE_CONCESSION)
	return _success({"delta": delta})


## Despido del causante del malestar (un directivo por debajo del jugador): −10.
static func appease_by_firing(culprit_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(culprit_id)
	if npc == null or not NPCDirector.is_active(culprit_id):
		return _failure(REASON_UNKNOWN_NPC)
	if npc.tier <= Database.get_balance_int(B_MAX_TIER):
		return _failure(REASON_NOT_MANAGEMENT)
	if PlayerState.get_tier() < Database.get_balance_int(B_FIRING_TIER) \
			or npc.tier >= PlayerState.get_tier():
		return _failure(REASON_NO_AUTHORITY)
	NPCDirector.remove_npc(culprit_id, str(Database.get_balance(B_FIRING_CAUSE)))
	var delta: int = Company.apply_labour_event(EVENT_CULPRIT_DISMISSED)
	return _success({"delta": delta, "npc_id": culprit_id})


# ─── Liderar y traicionar ─────────────────────────────────────

## {allowed, reason}: descontento > umbral, sin traición previa y sin liderarla ya.
static func can_lead() -> Dictionary:
	var reason: String = ""
	if Company.are_workers_betrayed():
		reason = REASON_BETRAYED
	elif Company.get_discontent() <= Company.get_strike_threshold():
		reason = REASON_BELOW_THRESHOLD
	elif Company.get_strike_leader() == PLAYER_ID:
		reason = REASON_ALREADY_LEADING
	return {"allowed": reason.is_empty(), "reason": reason}


## Encabeza la huelga: muy alta entre los escalones bajos, muy baja ante la dirección.
static func lead() -> Dictionary:
	var check: Dictionary = can_lead()
	if not bool(check["allowed"]):
		return _failure(str(check["reason"]))
	if not Company.call_strike(PLAYER_ID):
		return _failure(REASON_BELOW_THRESHOLD)
	PlayerState.modify_reputation(Database.get_balance_float(B_LEAD_REPUTATION), REPUTATION_LED)
	_shift_affection(Database.get_balance_int(B_LEAD_LOW_AFFECTION),
			Database.get_balance_int(B_LEAD_EXEC_AFFECTION))
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_LED, [])
	return _success({})


## La convocó y no comparece: la huelga se detiene y los escalones bajos no lo olvidan nunca.
static func betray() -> Dictionary:
	if not Company.is_strike_active() or Company.get_strike_leader() != PLAYER_ID:
		return _failure(REASON_NOT_LEADER)
	EventBus.strike_resolved.emit(RESOLUTION_BETRAYED)
	PlayerState.modify_reputation(Database.get_balance_float(B_BETRAY_REPUTATION),
			REPUTATION_BETRAYED)
	var low_tier: int = Database.get_balance_int(B_MAX_TIER)
	var grievance: String = str(Database.get_balance(B_BETRAY_GRIEVANCE))
	var severity: int = Database.get_balance_int(B_BETRAY_SEVERITY)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.tier <= low_tier:
			NPCDirector.add_grievance(npc.id, grievance, severity)
	_shift_affection(0, Database.get_balance_int(B_BETRAY_EXEC_AFFECTION))
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_BETRAYED, [])
	return _success({})


## Resumen del conflicto para la interfaz y el panel F1.
static func get_status() -> Dictionary:
	return {
		"discontent": Company.get_discontent(), "threshold": Company.get_strike_threshold(),
		"strike_active": Company.is_strike_active(), "leader": Company.get_strike_leader(),
		"agitation": Company.get_agitation(), "workers_betrayed": Company.are_workers_betrayed(),
		"standing_workers": Company.get_labour_standing(STANDING_WORKERS),
		"standing_management": Company.get_labour_standing(STANDING_MANAGEMENT),
		"quota_excessive": Company.is_quota_excessive(),
		"factory_degraded": Company.is_factory_degraded(),
		"mood_delta": Company.get_mood_discontent_delta(),
	}


static func get_reason_label_key(reason: String) -> String:
	return str(REASON_LABEL_KEYS.get(reason, ""))


# ─── Internos ─────────────────────────────────────────────────

## "" si es un personaje en plantilla de escalones bajos; si no, el motivo.
static func _low_tier_reason(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not NPCDirector.is_active(npc_id):
		return REASON_UNKNOWN_NPC
	if npc.tier > Database.get_balance_int(B_MAX_TIER):
		return REASON_NOT_LOW_TIER
	return ""


static func _in_cooldown(npc_id: String) -> bool:
	var last: int = Company.get_last_agitation_day(npc_id)
	return last != NO_DAY \
			and GameClock.get_day() - last < Database.get_balance_int(B_COOLDOWN)


static func _default_manager() -> String:
	var holder: String = Company.get_seat_holder(str(Database.get_balance(B_RUMOUR_TARGET)))
	return SUBJECT_COMPANY if holder.is_empty() or holder == PLAYER_ID else holder


## Afecto a los escalones bajos (≤ descontento.escalon_max_afectado) y a la dirección (≥
## empresa.escalon_directivo); 0 = sin cambio.
static func _shift_affection(low_delta: int, exec_delta: int) -> void:
	var low_tier: int = Database.get_balance_int(B_MAX_TIER)
	var exec_tier: int = Database.get_balance_int(B_EXEC_TIER)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.tier <= low_tier and low_delta != 0:
			NPCDirector.add_affection(npc.id, low_delta)
		elif npc.tier >= exec_tier and exec_delta != 0:
			NPCDirector.add_affection(npc.id, exec_delta)


static func _success(extra: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": true, "reason": "", "discontent": Company.get_discontent(),
			"agitation": Company.get_agitation(), "strike_active": Company.is_strike_active()}
	out.merge(extra)
	return out


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "discontent": Company.get_discontent(),
			"agitation": Company.get_agitation(), "strike_active": Company.is_strike_active()}
