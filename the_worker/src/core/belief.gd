# belief.gd — Una creencia o un registro permanente sostenido por alguien (manual §7.2, §7.6).
# PROPIETARIO DE: nada (estructura de datos; el conjunto de creencias pertenece a BeliefNet).
# ESCUCHA: nada.
class_name Belief
extends RefCounted

## Campos exactos de §7.2 más dos opcionales para registros (is_record = true):
## record_type (grabación, registro de tarjeta, asiento contable... §7.6) y weight (§12.4).
## Nota: el segundo parámetro de from_dict es el contexto de validación ("ARCHIVO → entrada N");
## se llama `ctx` porque `source` es aquí un campo de la creencia.

const SOURCE_DIRECT := "direct"
const SOURCE_RUMOR := "rumor"
const SOURCE_RECORD := "record"
const SOURCES: Array[String] = [SOURCE_DIRECT, SOURCE_RUMOR, SOURCE_RECORD]
const MIN_CERTAINTY := 0.0
const MAX_CERTAINTY := 1.0

var id: String = ""
## Quién sostiene la creencia.
var holder: String = ""
## Sobre quién versa.
var subject: String = ""
## Qué afirma.
var fact: String = ""
var evidence_strength: float = 0.0
## "direct" | "rumor" | "record"
var source: String = SOURCE_DIRECT
## 0.0 – 1.0
var certainty: float = MIN_CERTAINTY
var location: String = ""
## Jornada de creación.
var timestamp: int = 0
## Si es permanente (no decae; solo desaparece por destrucción activa).
var is_record: bool = false
var record_type: String = ""
var weight: float = 0.0


static func make(p_id: String, p_holder: String, p_subject: String, p_fact: String,
		p_certainty: float, p_source: String, p_location: String, p_timestamp: int) -> Belief:
	var b: Belief = Belief.new()
	b.id = p_id
	b.holder = p_holder
	b.subject = p_subject
	b.fact = p_fact
	b.certainty = p_certainty
	b.source = p_source
	b.location = p_location
	b.timestamp = p_timestamp
	b.is_record = p_source == SOURCE_RECORD
	return b


static func from_dict(d: Dictionary, ctx: String) -> Belief:
	var b: Belief = Belief.new()
	b.id = Validate.require_string(d, "id", ctx)
	b.holder = Validate.require_string(d, "holder", ctx)
	b.subject = Validate.require_string(d, "subject", ctx)
	b.fact = Validate.require_string(d, "fact", ctx)
	b.evidence_strength = Validate.require_float(d, "evidence_strength", ctx)
	b.source = Validate.require_enum(d, "source", SOURCES, ctx)
	b.certainty = Validate.require_float_range(d, "certainty", MIN_CERTAINTY, MAX_CERTAINTY, ctx)
	b.location = Validate.require_string(d, "location", ctx)
	b.timestamp = Validate.require_int(d, "timestamp", ctx)
	b.is_record = Validate.require_bool(d, "is_record", ctx)
	b.record_type = Validate.optional_string(d, "record_type", "", ctx)
	b.weight = Validate.optional_float(d, "weight", 0.0, ctx)
	return b


func to_dict() -> Dictionary:
	var out: Dictionary = {
		"id": id, "holder": holder, "subject": subject, "fact": fact,
		"evidence_strength": evidence_strength, "source": source, "certainty": certainty,
		"location": location, "timestamp": timestamp, "is_record": is_record,
	}
	if is_record or not record_type.is_empty():
		out["record_type"] = record_type
		out["weight"] = weight
	return out
