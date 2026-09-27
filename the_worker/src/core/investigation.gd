# investigation.gd — Estado de una investigación de cinco fases (manual §12.3, §12.4, §12.6).
# PROPIETARIO DE: nada (estructura de datos; las investigaciones pertenecen a Security).
# ESCUCHA: nada.
class_name Investigation
extends RefCounted

## evidence: [{type, weight, certainty (0–1, por defecto 1), points_to, record_id}]
## suspects: ids ordenados por peso (lista corta de fase 3).
## status: "active" | "cold" | "closed". frozen_until_day: congelada mientras día < este valor.

const MIN_PHASE := 1
const MAX_PHASE := 5
const STATUS_ACTIVE := "active"
const STATUS_COLD := "cold"
const STATUS_CLOSED := "closed"
const STATUSES: Array[String] = [STATUS_ACTIVE, STATUS_COLD, STATUS_CLOSED]
const FULL_CERTAINTY := 1.0

var id: String = ""
var incident_type: String = ""
var severity: int = 0
var location: String = ""
var phase: int = MIN_PHASE
var opened_day: int = 0
## Jornada en que comenzó la fase actual.
var phase_day: int = 0
var evidence: Array[Dictionary] = []
var suspects: Array[String] = []
var status: String = STATUS_ACTIVE
var verdict: String = ""
var culprit: String = ""
var frozen_until_day: int = 0
var searched_rooms: Array[String] = []


static func from_dict(d: Dictionary, source: String) -> Investigation:
	var inv: Investigation = Investigation.new()
	inv.id = Validate.require_string(d, "id", source)
	inv.incident_type = Validate.require_string(d, "incident_type", source)
	inv.severity = Validate.require_int_min(d, "severity", 0, source)
	inv.location = Validate.require_string(d, "location", source)
	inv.phase = Validate.require_int_range(d, "phase", MIN_PHASE, MAX_PHASE, source)
	inv.opened_day = Validate.require_int(d, "opened_day", source)
	inv.phase_day = Validate.optional_int(d, "phase_day", inv.opened_day, source)
	inv.evidence = _parse_evidence(d, source)
	inv.suspects = Validate.optional_string_array(d, "suspects", source)
	inv.status = Validate.optional_enum(d, "status", STATUSES, STATUS_ACTIVE, source)
	inv.verdict = Validate.optional_string(d, "verdict", "", source)
	inv.culprit = Validate.optional_string(d, "culprit", "", source)
	inv.frozen_until_day = Validate.optional_int(d, "frozen_until_day", 0, source)
	inv.searched_rooms = Validate.optional_string_array(d, "searched_rooms", source)
	return inv


func to_dict() -> Dictionary:
	return {
		"id": id, "incident_type": incident_type, "severity": severity, "location": location,
		"phase": phase, "opened_day": opened_day, "phase_day": phase_day,
		"evidence": evidence.duplicate(true), "suspects": suspects.duplicate(),
		"status": status, "verdict": verdict, "culprit": culprit,
		"frozen_until_day": frozen_until_day, "searched_rooms": searched_rooms.duplicate(),
	}


static func make_evidence(evidence_type: String, p_weight: float, p_certainty: float,
		points_to: String, record_id: String) -> Dictionary:
	return {"type": evidence_type, "weight": p_weight, "certainty": p_certainty,
			"points_to": points_to, "record_id": record_id}


func add_evidence(evidence_type: String, p_weight: float, p_certainty: float,
		points_to: String, record_id: String) -> void:
	evidence.append(make_evidence(evidence_type, p_weight, p_certainty, points_to, record_id))


## Σ (peso_pieza × certeza_pieza) de las piezas que apuntan a `subject` (§12.3, fase 3).
func weight_against(subject: String) -> float:
	var total: float = 0.0
	for piece: Dictionary in evidence:
		if piece.get("points_to", "") == subject:
			total += float(piece.get("weight", 0.0)) * float(piece.get("certainty", FULL_CERTAINTY))
	return total


func is_active() -> bool:
	return status == STATUS_ACTIVE


func is_frozen(day: int) -> bool:
	return day < frozen_until_day


static func _parse_evidence(d: Dictionary, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = Validate.optional_dict_array(d, "evidence", source)
	for i: int in raw.size():
		Validate.enter("evidence[%d]" % i)
		var piece: Dictionary = raw[i]
		out.append(make_evidence(
				Validate.require_string(piece, "type", source),
				Validate.require_float(piece, "weight", source),
				Validate.optional_float(piece, "certainty", FULL_CERTAINTY, source),
				Validate.optional_string(piece, "points_to", "", source),
				Validate.optional_string(piece, "record_id", "", source)))
		Validate.leave()
	return out
