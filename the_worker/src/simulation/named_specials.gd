# named_specials.gd — Reglas únicas de personajes con nombre (§8.3, npcs_named.json "special"): la contabilidad de favores de Iggy Robbins, el aliado permanente (Alvin Pyne), la vigilancia del chat legible por IT (§7.7) y el CEO al que nadie comunica información veraz (Harlan Voss).
# PROPIETARIO DE: nada (estático; el estado vive en banderas named.* de PlayerState, la deuda en NPCDirector, las creencias en BeliefNet).
# ESCUCHA: favour_added, investigation_opened, day_advanced (una sola conexión por proceso, hook()).
class_name NamedSpecials
extends RefCounted

## · keeps_favour_ledger (Iggy): no acepta dinero; concede favores a crédito (la deuda del registro
##   baja de 0: el jugador le debe) hasta especiales_nombrados.credito_max_favores. Reclama el cobro
##   en el momento más inoportuno: al abrirse una investigación contra el jugador. Si en
##   especiales_nombrados.dias_plazo_cobro jornadas la deuda no vuelve a 0 (favores al personaje:
##   ceder méritos, favores ofrecidos), denuncia al jugador ante el superior y cancela la cuenta.
## · ally_if_protected (Alvin): un favor mientras está amenazado (sospechoso de una investigación
##   abierta o sujeto de una creencia negativa ajena) lo vuelve aliado permanente: afecto máximo y
##   no denuncia jamás (NPCDirector.is_report_suppressed).
## · monitors_gathering (Alvin, "chat_3b"): cada salto del chat legible por IT sobre el jugador le
##   deja la misma creencia (la conserva; como cobarde, silencia por temor).
## · receives_no_truthful_info (Voss): ignora lo que el jugador le cuenta en persona y ningún rumor
##   veraz le llega; los rumores plantados por el jugador sí le llegan por intermediarios, sin merma.

const SPECIAL_LEDGER := "keeps_favour_ledger"
const SPECIAL_ALLY := "ally_if_protected"
const SPECIAL_MONITORS := "monitors_gathering"
const SPECIAL_NO_TRUTH := "receives_no_truthful_info"
const FLAG_ALLY := "named.ally."
const FLAG_CLAIM := "named.claim."
const PLAYER := "player"
const B_CREDIT := "especiales_nombrados.credito_max_favores"
const B_DEADLINE := "especiales_nombrados.dias_plazo_cobro"
const B_AFFECTION := "especiales_nombrados.afecto_aliado"
const REPORT_TYPE := "superior"
const GRIEVANCE := "unpaid_favours"
const NO_CLAIM := -1

static var _hooked: bool = false
static var _specials: Dictionary = {}


static func hook() -> void:
	if _hooked or Engine.is_editor_hint():
		return
	_hooked = true
	EventBus.favour_added.connect(_on_favour_added)
	EventBus.investigation_opened.connect(_on_investigation_opened)
	EventBus.day_advanced.connect(_on_day_advanced)


static func special(npc_id: String) -> Dictionary:
	if not _specials.has(npc_id):
		var raw: Variant = NPCDirector.get_profile(npc_id).get("special", {})
		_specials[npc_id] = raw if raw is Dictionary else {}
	return _specials[npc_id]


static func has_special(npc_id: String, key: String) -> bool:
	var value: Variant = special(npc_id).get(key, false)
	return not str(value).is_empty() if value is String else bool(value)


# ─── Iggy: contabilidad de favores ────────────────────────────

## Deuda a la que puede llegar el jugador con él (0 = no concede a crédito).
static func credit_limit(npc_id: String) -> int:
	return maxi(Database.get_balance_int(B_CREDIT), 0) if has_special(npc_id, SPECIAL_LEDGER) else 0


## ¿Concede un favor de `cost` a crédito aunque no te deba lo bastante?
static func grants_on_credit(npc_id: String, cost: int) -> bool:
	return credit_limit(npc_id) > 0 and NPCDirector.get_debt(npc_id) - cost >= -credit_limit(npc_id)


static func claim_deadline(npc_id: String) -> int:
	return int(PlayerState.get_flag(FLAG_CLAIM + npc_id, NO_CLAIM))


static func _on_investigation_opened(_case_id: String, _type: String, _severity: int) -> void:
	for npc_id: String in _ledger_keepers():
		if NPCDirector.get_debt(npc_id) < 0 and claim_deadline(npc_id) == NO_CLAIM:
			PlayerState.set_flag(FLAG_CLAIM + npc_id,
					GameClock.get_day() + maxi(Database.get_balance_int(B_DEADLINE), 1))
			EventBus.phone_message_received.emit(npc_id, "NAMED_MSG_CLAIM", false)


static func _on_day_advanced(day: int) -> void:
	for npc_id: String in _ledger_keepers():
		var deadline: int = claim_deadline(npc_id)
		if deadline == NO_CLAIM:
			continue
		var debt: int = NPCDirector.get_debt(npc_id)
		if debt >= 0 or not NPCDirector.is_active(npc_id):
			PlayerState.set_flag(FLAG_CLAIM + npc_id, NO_CLAIM)
		elif day >= deadline:
			PlayerState.set_flag(FLAG_CLAIM + npc_id, NO_CLAIM)
			NPCDirector.add_debt(npc_id, -debt)
			NPCDirector.add_grievance(npc_id, GRIEVANCE, 1)
			EventBus.phone_message_received.emit(npc_id, "NAMED_MSG_CLAIM_REPORTED", false)
			EventBus.npc_reported_player.emit(npc_id, REPORT_TYPE, 0.0,
					NPCDirector.get_current_location(npc_id))


static func _ledger_keepers() -> Array[String]:
	var out: Array[String] = []
	for npc_id: String in _named_ids():
		if has_special(npc_id, SPECIAL_LEDGER) and NPCDirector.get_npc(npc_id) != null:
			out.append(npc_id)
	return out


# ─── Alvin: aliado permanente ─────────────────────────────────

static func is_permanent_ally(npc_id: String) -> bool:
	return bool(PlayerState.get_flag(FLAG_ALLY + npc_id, false))


static func is_under_threat(npc_id: String) -> bool:
	for inv: Investigation in Security.get_active_investigations():
		if inv.suspects.has(npc_id):
			return true
	for b: Belief in BeliefNet.get_beliefs_about(npc_id):
		if b.holder != npc_id and BeliefNet.is_negative_fact(b.fact):
			return true
	return false


static func _on_favour_added(npc_id: String, _type: String, _magnitude: int) -> void:
	if not has_special(npc_id, SPECIAL_ALLY) or is_permanent_ally(npc_id) or not is_under_threat(npc_id):
		return
	PlayerState.set_flag(FLAG_ALLY + npc_id, true)
	NPCDirector.add_affection(npc_id, Database.get_balance_int(B_AFFECTION))
	EventBus.phone_message_received.emit(npc_id, "NAMED_MSG_ALLY", false)


# ─── Alvin: el chat legible por IT ────────────────────────────

## SocialGraph: salto registrado en un corrillo legible por IT.
static func on_chat_logged(gathering_id: String, subject: String, fact: String, certainty: float) -> void:
	if subject != PLAYER:
		return
	for npc_id: String in _named_ids():
		if str(special(npc_id).get(SPECIAL_MONITORS, "")) == gathering_id and NPCDirector.is_active(npc_id):
			BeliefNet.create_belief(npc_id, subject, fact, certainty, Belief.SOURCE_RUMOR, "")


# ─── Voss: nadie le comunica información veraz ────────────────

## BeliefNet: ¿llega este rumor a `holder`? `planted` = hecho plantado por el jugador.
static func accepts_rumour(holder: String, from_player: bool, planted: bool) -> bool:
	if not has_special(holder, SPECIAL_NO_TRUTH):
		return true
	return planted and not from_player


static func full_transfer(holder: String) -> bool:
	return has_special(holder, SPECIAL_NO_TRUTH)


static func _named_ids() -> Array[String]:
	var out: Array[String] = []
	for npc: NPCData in Database.get_all_named_npcs():
		out.append(npc.id)
	return out
