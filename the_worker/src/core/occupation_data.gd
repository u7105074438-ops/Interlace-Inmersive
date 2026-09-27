# occupation_data.gd — Registro tipado de una ocupación (manual §26, §23, §6).
# PROPIETARIO DE: nada (dato estático de solo lectura cargado por Database).
# ESCUCHA: nada.
class_name OccupationData
extends RefCounted

## Claves obligatorias (§26): id, name_key, rank, tier, clearance, daily_wage,
## personnel_file_level, duties, promotes_to. El resto es opcional.
## Cada deber de `duties` se normaliza: id y type obligatorios; los campos numéricos
## (amount, time_cost_minutes, assist_time_cost_minutes, deadline_hour) pasan a int;
## el resto de claves (subtype, fail_penalty...) se conserva tal cual.

const MIN_RANK := 0
const MAX_RANK := 33
const MIN_TIER := 1
const MAX_TIER := 8
const MIN_CLEARANCE := 0
const MAX_CLEARANCE := 7
const NO_DESK := Vector2i(-1, -1)
const SILHOUETTE_FORMAT := "tier_%d"
const DUTY_INT_KEYS: Array[String] = [
	"amount", "time_cost_minutes", "assist_time_cost_minutes", "deadline_hour",
]
const KNOWN_KEYS: Array[String] = [
	"id", "name_key", "rank", "tier", "clearance", "daily_wage", "office_room",
	"desk_position", "computer_tier", "personnel_file_level", "duties", "tools",
	"special_access", "opportunities", "risks", "promotes_to", "can_jump_to", "demotes_to",
	"min_reputation", "silhouette",
]

var id: String = ""
var name_key: String = ""
var rank: int = MIN_RANK
var tier: int = MIN_TIER
var clearance: int = MIN_CLEARANCE
var daily_wage: int = 0
var office_room: String = ""
var desk_position: Vector2i = NO_DESK
var computer_tier: int = 0
var personnel_file_level: int = 0
var duties: Array[Dictionary] = []
var tools: Array[String] = []
var special_access: Array[String] = []
var opportunities: Array[String] = []
var risks: Array[String] = []
var promotes_to: Array[String] = []
var can_jump_to: Array[String] = []
var demotes_to: Array[String] = []
var min_reputation: float = 0.0
var silhouette: String = ""
## Claves del JSON no reconocidas (se conservan para no perder datos).
var extra: Dictionary = {}


static func from_dict(d: Dictionary, source: String) -> OccupationData:
	var o: OccupationData = OccupationData.new()
	o._read_identity(d, source)
	o._read_lists(d, source)
	o.duties = _parse_duties(d, source)
	o.extra = Validate.extra_keys(d, KNOWN_KEYS)
	return o


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out.merge({
		"id": id, "name_key": name_key, "rank": rank, "tier": tier, "clearance": clearance,
		"daily_wage": daily_wage, "office_room": office_room,
		"desk_position": [desk_position.x, desk_position.y], "computer_tier": computer_tier,
		"personnel_file_level": personnel_file_level, "duties": duties.duplicate(true),
		"tools": tools.duplicate(), "special_access": special_access.duplicate(),
		"opportunities": opportunities.duplicate(), "risks": risks.duplicate(),
		"promotes_to": promotes_to.duplicate(), "can_jump_to": can_jump_to.duplicate(),
		"demotes_to": demotes_to.duplicate(), "min_reputation": min_reputation,
		"silhouette": silhouette,
	}, true)
	return out


func has_desk() -> bool:
	return desk_position != NO_DESK


func get_duty(duty_id: String) -> Dictionary:
	for duty: Dictionary in duties:
		if duty.get("id", "") == duty_id:
			return duty
	return {}


func _read_identity(d: Dictionary, source: String) -> void:
	id = Validate.require_id(d, "id", source)
	name_key = Validate.require_string(d, "name_key", source)
	rank = Validate.require_int_range(d, "rank", MIN_RANK, MAX_RANK, source)
	tier = Validate.require_int_range(d, "tier", MIN_TIER, MAX_TIER, source)
	clearance = Validate.require_int_range(d, "clearance", MIN_CLEARANCE, MAX_CLEARANCE, source)
	daily_wage = Validate.require_int_min(d, "daily_wage", 0, source)
	personnel_file_level = Validate.require_int_min(d, "personnel_file_level", 0, source)
	office_room = Validate.optional_string(d, "office_room", "", source)
	desk_position = Validate.optional_vector2i(d, "desk_position", NO_DESK, source)
	computer_tier = Validate.optional_int(d, "computer_tier", 0, source)
	min_reputation = Validate.optional_float(d, "min_reputation", 0.0, source)
	silhouette = Validate.optional_string(d, "silhouette", SILHOUETTE_FORMAT % tier, source)


func _read_lists(d: Dictionary, source: String) -> void:
	promotes_to = Validate.require_string_array(d, "promotes_to", source)
	tools = Validate.optional_string_array(d, "tools", source)
	special_access = Validate.optional_string_array(d, "special_access", source)
	opportunities = Validate.optional_string_array(d, "opportunities", source)
	risks = Validate.optional_string_array(d, "risks", source)
	can_jump_to = Validate.optional_string_array(d, "can_jump_to", source)
	demotes_to = Validate.optional_string_array(d, "demotes_to", source)


static func _parse_duties(d: Dictionary, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = Validate.require_dict_array(d, "duties", source)
	for i: int in raw.size():
		Validate.enter("duties[%d]" % i)
		out.append(_parse_duty(raw[i], source))
		Validate.leave()
	return out


static func _parse_duty(raw: Dictionary, source: String) -> Dictionary:
	var duty: Dictionary = raw.duplicate(true)
	duty["id"] = Validate.require_id(raw, "id", source)
	duty["type"] = Validate.require_string(raw, "type", source)
	for key: String in DUTY_INT_KEYS:
		if raw.has(key):
			duty[key] = Validate.optional_int(raw, key, 0, source)
	return duty
