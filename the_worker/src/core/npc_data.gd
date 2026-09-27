# npc_data.gd — Registro tipado de un personaje nominado (manual §29, §24.2).
# PROPIETARIO DE: nada (dato estático de solo lectura cargado por Database).
# ESCUCHA: nada.
class_name NPCData
extends RefCounted

## Obligatorias: id, name, archetype, traits, occupation, home_room. El resto es opcional.
## routine_overrides: [{band (franja), action, time? "HH:MM", location?, duration_minutes? int,
##                      note?, ...}]
## initial_links:     [{to, type, strength 0.0–1.0}]
## `name` es un nombre propio (único texto literal permitido, BUILD_NOTES §5).

const NO_DESK := Vector2i(-1, -1)
const TIME_PATTERN := "^[0-9]{1,2}:[0-9]{2}$"
const EXPECTED_TIME := "\"HH:MM\""
const KNOWN_KEYS: Array[String] = [
	"id", "name", "archetype", "traits", "occupation", "home_room", "desk_position",
	"routine_template", "routine_overrides", "initial_links", "gatherings", "weakness_key",
	"danger_key", "unique_accessory", "portrait_seed", "is_slacker",
]

static var _time_regex: RegEx = null

var id: String = ""
var name: String = ""
var archetype: String = ""
var traits: Dictionary = Validate.default_traits()
var occupation: String = ""
var home_room: String = ""
var desk_position: Vector2i = NO_DESK
var routine_template: String = ""
var routine_overrides: Array[Dictionary] = []
var initial_links: Array[Dictionary] = []
var gatherings: Array[String] = []
var weakness_key: String = ""
var danger_key: String = ""
var unique_accessory: String = ""
var portrait_seed: int = 0
var is_slacker: bool = false
var extra: Dictionary = {}


static func from_dict(d: Dictionary, source: String) -> NPCData:
	var n: NPCData = NPCData.new()
	n._read_identity(d, source)
	n.routine_overrides = parse_routine_overrides(d, source)
	n.initial_links = _parse_links(d, source)
	n.extra = Validate.extra_keys(d, KNOWN_KEYS)
	return n


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out.merge({
		"id": id, "name": name, "archetype": archetype, "traits": traits.duplicate(),
		"occupation": occupation, "home_room": home_room,
		"desk_position": [desk_position.x, desk_position.y],
		"routine_template": routine_template,
		"routine_overrides": routine_overrides.duplicate(true),
		"initial_links": initial_links.duplicate(true), "gatherings": gatherings.duplicate(),
		"weakness_key": weakness_key, "danger_key": danger_key,
		"unique_accessory": unique_accessory, "portrait_seed": portrait_seed,
		"is_slacker": is_slacker,
	}, true)
	return out


func get_trait(trait_name: String) -> int:
	return int(traits.get(trait_name, Validate.TRAIT_MIN))


func _read_identity(d: Dictionary, source: String) -> void:
	id = Validate.require_id(d, "id", source)
	name = Validate.require_string(d, "name", source)
	archetype = Validate.require_string(d, "archetype", source)
	traits = Validate.require_traits(d, "traits", source)
	occupation = Validate.require_string(d, "occupation", source)
	home_room = Validate.require_string(d, "home_room", source)
	desk_position = Validate.optional_vector2i(d, "desk_position", NO_DESK, source)
	routine_template = Validate.optional_string(d, "routine_template", "", source)
	gatherings = Validate.optional_string_array(d, "gatherings", source)
	weakness_key = Validate.optional_string(d, "weakness_key", "", source)
	danger_key = Validate.optional_string(d, "danger_key", "", source)
	unique_accessory = Validate.optional_string(d, "unique_accessory", "", source)
	portrait_seed = Validate.optional_int(d, "portrait_seed", 0, source)
	is_slacker = Validate.optional_bool(d, "is_slacker", false, source)


## Público: NPCRuntime reutiliza la misma normalización al cargar partidas.
static func parse_routine_overrides(d: Dictionary, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = Validate.optional_dict_array(d, "routine_overrides", source)
	for i: int in raw.size():
		Validate.enter("routine_overrides[%d]" % i)
		var o: Dictionary = raw[i].duplicate(true)
		o["band"] = Validate.require_enum(raw[i], "band", Validate.TIME_BANDS, source)
		o["action"] = Validate.require_string(raw[i], "action", source)
		o["location"] = Validate.optional_string(raw[i], "location", "", source)
		if raw[i].has("time"):
			o["time"] = _check_time(raw[i], source)
		if raw[i].has("duration_minutes"):
			o["duration_minutes"] = Validate.optional_int(raw[i], "duration_minutes", 0, source)
		out.append(o)
		Validate.leave()
	return out


static func _check_time(raw: Dictionary, source: String) -> String:
	var value: String = Validate.optional_string(raw, "time", "", source)
	if _time_regex == null:
		_time_regex = RegEx.create_from_string(TIME_PATTERN)
	if _time_regex.search(value) == null:
		Validate.report(source, "time", Validate.PROBLEM_FORMAT, EXPECTED_TIME,
				Validate.describe(raw["time"]))
	return value


static func _parse_links(d: Dictionary, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = Validate.optional_dict_array(d, "initial_links", source)
	for i: int in raw.size():
		Validate.enter("initial_links[%d]" % i)
		var link: Dictionary = raw[i].duplicate(true)
		link["to"] = Validate.require_string(raw[i], "to", source)
		link["type"] = Validate.require_string(raw[i], "type", source)
		link["strength"] = Validate.require_float_range(raw[i], "strength", 0.0, 1.0, source)
		out.append(link)
		Validate.leave()
	return out
