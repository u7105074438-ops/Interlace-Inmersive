# investigation.gd — Motor de investigaciones: reglas puras de las cinco fases (§12.3, §12.4, §12.6).
# PROPIETARIO DE: nada (funciones puras sobre objetos Investigation; el estado pertenece a Security).
# ESCUCHA: nada.
class_name InvestigationEngine
extends RefCounted

## Security reúne los datos del mundo (creencias, grabaciones, registros de tarjeta, escondites,
## cuerpos) y delega aquí el cálculo: qué piezas produce cada procedimiento de la fase 2, el peso
## de cada sospechoso (fase 3), la lista corta y el veredicto (fase 5). Nada de lo que hay aquí
## lee autoloads ni guarda estado: todos los números llegan como parámetros (datos de
## balance.json e investigations.json leídos por el dueño).
## Pieza de evidencia = Investigation.make_evidence(): {type, weight, certainty, points_to, record_id}.

const SUBJECT_PLAYER := "player"
## Sujetos sin identidad: grabación con uniforme ("uniform:<id>", §5.3) o cuerpo sin autor.
const SUBJECT_UNIFORM_PREFIX := "uniform:"
const SUBJECT_UNKNOWN := "unknown"
const ROOM_INSTANCE_SEPARATOR := "@"
const FACT_SEPARATOR := ":"

const PHASE_INCIDENT := 1
const PHASE_COLLECTION := 2
const PHASE_SHORTLIST := 3
const PHASE_INTERROGATION := 4
const PHASE_VERDICT := 5

## Veredictos que viajan en investigation_resolved (fase 5, §12.3).
const VERDICT_COLD := "cold"
const VERDICT_OTHER := "other_guilty"
const VERDICT_PLAYER_MINOR := "player_minor"
const VERDICT_PLAYER_MAJOR := "player_major"
const VERDICTS: Array[String] = [
	VERDICT_COLD, VERDICT_OTHER, VERDICT_PLAYER_MINOR, VERDICT_PLAYER_MAJOR,
]
## Id del veredicto en investigations.json → verdicts[].id.
const VERDICT_DATA_IDS: Dictionary = {
	VERDICT_COLD: "cold", VERDICT_OTHER: "other_guilty",
	VERDICT_PLAYER_MINOR: "player_guilty_minor", VERDICT_PLAYER_MAJOR: "player_guilty_major",
}

## Procedimientos de la fase 2 (investigations.json evidence_collection.procedures).
const PROC_WITNESSES := "interrogate_witnesses"
const PROC_FOOTAGE := "review_footage"
const PROC_SEARCH := "search_rooms"

## Tipos de pieza (investigations.json evidence_types[].id).
const EV_DIRECT_WITNESS := "direct_witness"
const EV_PARTIAL_WITNESS := "partial_witness"
const EV_FOOTAGE := "camera_footage"
const EV_CARD_LOG := "card_log"
const EV_ITEM := "compromising_item"
const EV_RUMOUR := "unsourced_rumour"
const EV_BODY := "body_found"
## Registros de BeliefNet → tipo de pieza. Grabaciones, tarjetas y cuerpos no pasan por aquí:
## Security los examina desde sus propios registros (procedimientos 2 y 3).
const RECORD_TO_EVIDENCE: Dictionary = {
	"accounting_entry": "accounting_trail", "stamped_document": "forged_document",
}
const RECORDS_HANDLED_BY_SECURITY: Array[String] = ["footage", "card_log", "body_found"]
## Incidentes y registros sin entrada en investigations.json → clave de texto.
const EXTRA_NAME_KEYS: Dictionary = {
	"missing_person": "INCIDENT_MISSING_PERSON", "signed_expulsion": "EVIDENCE_SIGNED_EXPULSION",
	"board_minutes": "EVIDENCE_BOARD_MINUTES",
}
## Hecho de percepción parcial en BeliefNet ("seen_partially[:detalle]").
const FACT_SEEN_PARTIALLY := "seen_partially"

## Incrementos de la fórmula del sospechoso (§12.3 fase 3).
const FLAG_ACCESS := "access"
const FLAG_MOTIVE := "motive"
const FLAG_LAST := "last_to_leave"
const FLAGS: Array[String] = [FLAG_ACCESS, FLAG_MOTIVE, FLAG_LAST]

## Objetivos del registro físico de salas.
const TARGET_ITEM := "item"
const TARGET_BODY := "body"
const OWN_DESK_SPOT := "player_desk"


# ─── Utilidades de datos ──────────────────────────────────────

## Valor en una ruta con puntos ("interrogation.tone.apology_if_reputation_above").
static func dig(data: Dictionary, path: String, fallback: Variant = null) -> Variant:
	var node: Variant = data
	for key: String in path.split("."):
		if not (node is Dictionary) or not (node as Dictionary).has(key):
			return fallback
		node = (node as Dictionary)[key]
	return node


## Entrada de una lista de registros con "id" ({} si no está).
static func find_by_id(entries: Array, id: String) -> Dictionary:
	for entry: Variant in entries:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == id:
			return entry
	return {}


## Id base de una sala transversal ("cleaning_closet_low@3" → "cleaning_closet_low").
static func base_room(room_id: String) -> String:
	return room_id.get_slice(ROOM_INSTANCE_SEPARATOR, 0)


## true si el sujeto identifica a alguien (no vacío, no un uniforme, no "unknown").
static func is_identified(subject: String) -> bool:
	return not subject.is_empty() and subject != SUBJECT_UNKNOWN \
			and not subject.begins_with(SUBJECT_UNIFORM_PREFIX)


## Clave de texto de un tipo de pieza o de incidente (evidence_types / incident_triggers).
static func evidence_name_key(params: Dictionary, evidence_type: String) -> String:
	for list_key: String in ["evidence_types", "incident_triggers"]:
		var entry: Dictionary = find_by_id(params.get(list_key, []), evidence_type)
		if not entry.is_empty():
			return str(entry.get("name_key", ""))
	return str(EXTRA_NAME_KEYS.get(evidence_type, ""))


# ─── Fase 1: incidente ────────────────────────────────────────

## Umbral de cualquier fase modulado por la sospecha del jugador: base + mod × sospecha (§12.4).
## Con base 3,0, mod −0,03 y sospecha 80 → 0,6. Nunca negativo.
static func modulated_threshold(base: float, mod_per_point: float, suspicion: float) -> float:
	return maxf(0.0, base + mod_per_point * suspicion)


## Regla de respiro (§15.3): true si ya pasaron `min_days` desde la última apertura o cierre.
static func rest_satisfied(today: int, last_case_day: int, min_days: int) -> bool:
	return today - last_case_day >= min_days


## Gravedad efectiva: la pedida (1-5) o, si no es válida, la del disparador.
static func effective_severity(requested: int, trigger: Dictionary, max_severity: int) -> int:
	if requested >= 1:
		return mini(requested, max_severity)
	return clampi(int(trigger.get("default_severity", 1)), 1, max_severity)


# ─── Fase 2: recogida de evidencia ────────────────────────────

## Jornadas de recogida según la gravedad (2-10, phase_durations.evidence_collection_by_severity).
static func collection_days(severity: int, by_severity: Dictionary, min_days: int,
		max_days: int) -> int:
	return clampi(int(by_severity.get(str(severity), max_days)), min_days, max_days)


## Jornada (contada desde el inicio de la fase 2) en que se ejecuta el procedimiento `index`
## de `count`: se reparten a lo largo de la recogida y el último cae en su última jornada.
static func procedure_due_day(index: int, count: int, total_days: int) -> int:
	return ceili(float((index + 1) * total_days) / float(maxi(count, 1)))


## Una creencia es pertinente si se formó en la ventana del incidente y en su ubicación.
static func is_belief_relevant(b: Belief, location: String, from_day: int, to_day: int) -> bool:
	if b.timestamp < from_day or b.timestamp > to_day:
		return false
	return b.location.is_empty() or base_room(b.location) == base_room(location)


## Pieza de testigo a partir de una creencia del grafo (procedimiento 1, §12.4):
## rumor → rumor sin fuente; percepción parcial o certeza baja → testigo parcial; resto →
## testigo directo. Los registros usan su propio peso. {} si no aporta nada.
static func piece_from_belief(b: Belief, weights: Dictionary, direct_min_certainty: float) -> Dictionary:
	if b.is_record:
		return _piece_from_record(b)
	var kind: String = EV_DIRECT_WITNESS
	if b.source == Belief.SOURCE_RUMOR:
		kind = EV_RUMOUR
	elif b.fact.get_slice(FACT_SEPARATOR, 0) == FACT_SEEN_PARTIALLY \
			or b.certainty < direct_min_certainty:
		kind = EV_PARTIAL_WITNESS
	return Investigation.make_evidence(kind, float(weights.get(kind, 0.0)), b.certainty,
			b.subject, b.id)


static func _piece_from_record(b: Belief) -> Dictionary:
	if RECORDS_HANDLED_BY_SECURITY.has(b.record_type) or b.weight <= 0.0:
		return {}
	var kind: String = str(RECORD_TO_EVIDENCE.get(b.record_type, b.record_type))
	return Investigation.make_evidence(kind, b.weight, b.certainty, b.subject, b.id)


## Grabación o registro de tarjeta dentro de la zona y franja revisadas (procedimiento 2).
## hour < 0 → se revisa la jornada entera.
static func is_record_relevant(entry: Dictionary, location: String, day: int, hour: int,
		window_hours: int) -> bool:
	if base_room(str(entry.get("room_id", ""))) != base_room(location):
		return false
	if int(entry.get("day", -1)) != day:
		return false
	return hour < 0 or absi(int(entry.get("hour", hour)) - hour) <= window_hours


## Plan del registro físico (procedimiento 3): la sala del incidente primero y después el orden
## de room_search.order filtrado por gravedad. forgotten_corridor (never_searched) y trash_dock
## (irrelevant) no se registran jamás. → [{room, spot, find_chance}]
static func search_plan(location: String, severity: int, room_search: Dictionary,
		incident_chance: float) -> Array[Dictionary]:
	var skip: Array = []
	skip.append_array(room_search.get("never_searched", []))
	skip.append_array(room_search.get("irrelevant", []))
	var order: Array = room_search.get("order", [])
	var loc: String = base_room(location)
	var plan: Array[Dictionary] = []
	if bool(room_search.get("search_incident_room_first", true)) and not loc.is_empty() \
			and not skip.has(loc):
		var own: Dictionary = _order_entry(order, loc)
		plan.append({"room": loc, "spot": str(own.get("spot", "")),
				"find_chance": float(own.get("find_chance", incident_chance))})
	for entry: Variant in order:
		var room: String = str((entry as Dictionary).get("room", ""))
		if room == loc or skip.has(room) or int(entry.get("min_severity", 0)) > severity:
			continue
		plan.append({"room": room, "spot": str(entry.get("spot", "")),
				"find_chance": float(entry.get("find_chance", 0.0))})
	return plan


static func _order_entry(order: Array, room: String) -> Dictionary:
	for entry: Variant in order:
		if entry is Dictionary and str((entry as Dictionary).get("room", "")) == room:
			return entry
	return {}


## Recorre el plan en orden. Cada objetivo {kind, id, room_id, spot_id, hidden} situado en una
## sala del plan aflora si está mal oculto (hidden = false) o si la tirada < find_chance.
## Devuelve los hallados (con "plan_spot" del paso) en orden de registro. rng es del dueño.
static func run_search(plan: Array[Dictionary], targets: Array[Dictionary],
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for step: Dictionary in plan:
		for target: Dictionary in targets:
			if base_room(str(target.get("room_id", ""))) != str(step["room"]):
				continue
			if not bool(target.get("hidden", true)) or rng.randf() < float(step["find_chance"]):
				var hit: Dictionary = target.duplicate()
				hit["plan_spot"] = step.get("spot", "")
				found.append(hit)
	return found


## Salas registradas por el plan (para Investigation.searched_rooms).
static func plan_rooms(plan: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for step: Dictionary in plan:
		out.append(str(step["room"]))
	return out


# ─── Fase 3: lista corta ──────────────────────────────────────

## peso = Σ (peso_pieza × certeza_pieza) + 2,0 acceso + 1,5 móvil + 3,5 último en salir.
## flags: {access, motive, last_to_leave: bool}; bonuses: mismos nombres → incremento.
static func suspect_weight(inv: Investigation, subject: String, flags: Dictionary,
		bonuses: Dictionary) -> float:
	var total: float = inv.weight_against(subject)
	for flag: String in FLAGS:
		if bool(flags.get(flag, false)):
			total += float(bonuses.get(flag, 0.0))
	return total


## Candidatos: todo sujeto identificado al que apunta alguna pieza, más los extra (último en
## salir, beneficiarios...). Sin duplicados y en orden de aparición.
static func candidates(inv: Investigation, extra: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for piece: Dictionary in inv.evidence:
		var subject: String = str(piece.get("points_to", ""))
		if is_identified(subject) and not out.has(subject):
			out.append(subject)
	for subject: String in extra:
		if is_identified(subject) and not out.has(subject):
			out.append(subject)
	return out


## Sujetos por peso descendente; empate → orden alfabético (determinista).
static func rank(weights: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in weights:
		ids.append(str(key))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var wa: float = float(weights[a])
		var wb: float = float(weights[b])
		if not is_equal_approx(wa, wb):
			return wa > wb
		return a < b)
	return ids


## Lista corta de 1 a `max_count` sospechosos: los que alcanzan su umbral (el del jugador va
## modulado por su sospecha), ordenados por peso. Vacía si nadie lo alcanza.
static func form_shortlist(weights: Dictionary, player_threshold: float, npc_threshold: float,
		max_count: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in rank(weights):
		var limit: float = player_threshold if id == SUBJECT_PLAYER else npc_threshold
		var weight: float = float(weights[id])
		if weight > 0.0 and weight >= limit and out.size() < max_count:
			out.append(id)
	return out


# ─── Fase 5: veredicto ────────────────────────────────────────

## §12.3: máximo < 7,0 → frío; encabeza otro con ≥ 7,0 → otro culpable; encabeza el jugador:
## 7,0–10,0 → leve; > 10,0 → grave. Decide el primero de la lista por peso actual.
## → {verdict, culprit, weight}
static func decide_verdict(weights: Dictionary, shortlist: Array[String], minor: float,
		major: float) -> Dictionary:
	var ranked: Array[String] = []
	var subset: Dictionary = {}
	for id: String in shortlist:
		subset[id] = float(weights.get(id, 0.0))
	ranked = rank(subset)
	if ranked.is_empty() or float(subset[ranked[0]]) < minor:
		return {"verdict": VERDICT_COLD, "culprit": "", "weight": _top_weight(subset, ranked)}
	var top: String = ranked[0]
	var weight: float = float(subset[top])
	if top != SUBJECT_PLAYER:
		return {"verdict": VERDICT_OTHER, "culprit": top, "weight": weight}
	var verdict: String = VERDICT_PLAYER_MAJOR if weight > major else VERDICT_PLAYER_MINOR
	return {"verdict": verdict, "culprit": SUBJECT_PLAYER, "weight": weight}


static func _top_weight(subset: Dictionary, ranked: Array[String]) -> float:
	return 0.0 if ranked.is_empty() else float(subset[ranked[0]])


# ─── Manipulación de piezas ───────────────────────────────────

## Índice de la pieza con ese record_id (-1 si no está).
static func find_piece(inv: Investigation, record_id: String) -> int:
	for i: int in inv.evidence.size():
		if str(inv.evidence[i].get("record_id", "")) == record_id:
			return i
	return -1


static func has_piece(inv: Investigation, record_id: String) -> bool:
	return find_piece(inv, record_id) >= 0


## Piezas que apuntan a `subject`, en orden de incorporación (el interrogatorio las presenta así).
static func pieces_against(inv: Investigation, subject: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for piece: Dictionary in inv.evidence:
		if str(piece.get("points_to", "")) == subject:
			out.append(piece)
	return out


## Σ peso × certeza de todas las piezas (identificadas o no).
static func total_weight(inv: Investigation) -> float:
	var total: float = 0.0
	for piece: Dictionary in inv.evidence:
		total += float(piece.get("weight", 0.0)) * float(
				piece.get("certainty", Investigation.FULL_CERTAINTY))
	return total


# ─── Casos fríos (§12.6) ──────────────────────────────────────

## Probabilidad de que un testigo silencioso hable: proporcional al agravio acumulado desde el
## archivo (suma de gravedades × por_punto), con tope.
static func silent_witness_chance(severity_sum: int, per_point: float, max_chance: float) -> float:
	return clampf(float(severity_sum) * per_point, 0.0, max_chance)


# ─── Informe del caso (epílogo THE FILE, §12.9) ───────────────

## Expediente: datos del caso, piezas en orden cronológico (piece_days del meta) y personas.
static func build_report(inv: Investigation, meta: Dictionary) -> Dictionary:
	var days: Dictionary = meta.get("piece_days", {})
	var pieces: Array[Dictionary] = []
	for i: int in inv.evidence.size():
		var piece: Dictionary = inv.evidence[i].duplicate()
		piece["day"] = int(days.get(str(piece.get("record_id", "")), inv.opened_day))
		piece["order"] = i
		pieces.append(piece)
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["day"]) != int(b["day"]):
			return int(a["day"]) < int(b["day"])
		return int(a["order"]) < int(b["order"]))
	return {
		"case_id": inv.id, "incident_type": inv.incident_type, "severity": inv.severity,
		"location": inv.location, "opened_day": inv.opened_day, "status": inv.status,
		"phase": inv.phase, "verdict": inv.verdict, "culprit": inv.culprit,
		"investigator": str(meta.get("interrogator", "")), "evidence": pieces,
		"evidence_count": pieces.size(), "suspects": inv.suspects.duplicate(),
		"scapegoats": (meta.get("framed", []) as Array).duplicate(),
		"culprit_innocent": bool(meta.get("culprit_innocent", false)),
		"resolved_day": int(meta.get("resolved_day", -1)),
	}
