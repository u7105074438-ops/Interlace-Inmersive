# npc_runtime.gd — Estado vivo de un personaje durante una partida (NPCDirector, manual §19.5).
# PROPIETARIO DE: nada (estructura de datos; el estado de los personajes pertenece a NPCDirector).
# ESCUCHA: nada.
class_name NPCRuntime
extends RefCounted

## No especificada por el manual: estructura común acordada para NPCDirector y sus consumidores.
## blackmail_material: Array libre; en sus entradas diccionario, FREE_INT_KEYS vuelven a int.
## ledger (§7.9): {affection: int -100..100, fear: int 0..100, debt: int (+ te debe, - le debes),
##                 grievances: [{type, severity, day}], favours: [{type, magnitude, day}]}
## lod (§20.1): 0 completo, 1 medio, 2 estadístico.
## mood: escala propia de NPCDirector; 0.0 = neutro.
## current_room puede llevar sufijo de planta en salas transversales ("corridors_low@3").

const LOD_FULL := 0
const LOD_MEDIUM := 1
const LOD_STATISTICAL := 2
const NO_DESK := Vector2i(-1, -1)
const STATE_IDLE := "idle"
const GRIEVANCE_INT_KEYS: Array[String] = ["severity", "day"]
const FAVOUR_INT_KEYS: Array[String] = ["magnitude", "day"]
## Claves enteras que se restauran como int en entradas libres (blackmail_material).
const FREE_INT_KEYS: Array[String] = ["day", "severity", "magnitude", "amount"]

var id: String = ""
var name: String = ""
var archetype: String = ""
var traits: Dictionary = Validate.default_traits()
var occupation_id: String = ""
var department: String = ""
var tier: int = 1
var home_room: String = ""
var desk_position: Vector2i = NO_DESK
var current_room: String = ""
@warning_ignore("shadowed_global_identifier")
var floor: int = 0
var position: Vector2 = Vector2.ZERO
var state: String = STATE_IDLE
var mood: float = 0.0
var merit: int = 0
var is_slacker: bool = false
var alive: bool = true
var removed_cause: String = ""
var lod: int = LOD_STATISTICAL
var routine_template: String = ""
var routine_overrides: Array[Dictionary] = []
var gatherings: Array[String] = []
var portrait_seed: int = 0
var is_named: bool = false
var weakness_key: String = ""
var danger_key: String = ""
var unique_accessory: String = ""
var ledger: Dictionary = new_ledger()
var blackmail_material: Array = []
## Sustituciones puntuales de la rutina: {franja: sala}.
var schedule_override: Dictionary = {}
var home_address: String = ""


static func new_ledger() -> Dictionary:
	return {"affection": 0, "fear": 0, "debt": 0, "grievances": [], "favours": []}


## Estado inicial de un personaje nominado. tier, department y floor los completa NPCDirector.
static func from_named(n: NPCData) -> NPCRuntime:
	var r: NPCRuntime = NPCRuntime.new()
	r.id = n.id
	r.name = n.name
	r.archetype = n.archetype
	r.traits = n.traits.duplicate()
	r.occupation_id = n.occupation
	r.home_room = n.home_room
	r.current_room = n.home_room
	r.desk_position = n.desk_position
	r.routine_template = n.routine_template
	r.routine_overrides = n.routine_overrides.duplicate(true)
	r.gatherings = n.gatherings.duplicate()
	r.portrait_seed = n.portrait_seed
	r.is_named = true
	r.weakness_key = n.weakness_key
	r.danger_key = n.danger_key
	r.unique_accessory = n.unique_accessory
	r.is_slacker = n.is_slacker
	return r


static func from_dict(d: Dictionary, source: String) -> NPCRuntime:
	var r: NPCRuntime = NPCRuntime.new()
	r._read_identity(d, source)
	r._read_state(d, source)
	r._read_social(d, source)
	return r


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "archetype": archetype, "traits": traits.duplicate(),
		"occupation_id": occupation_id, "department": department, "tier": tier,
		"home_room": home_room, "desk_position": [desk_position.x, desk_position.y],
		"current_room": current_room, "floor": floor, "position": [position.x, position.y],
		"state": state, "mood": mood, "merit": merit, "is_slacker": is_slacker, "alive": alive,
		"removed_cause": removed_cause, "lod": lod, "routine_template": routine_template,
		"routine_overrides": routine_overrides.duplicate(true),
		"gatherings": gatherings.duplicate(),
		"portrait_seed": portrait_seed, "is_named": is_named, "weakness_key": weakness_key,
		"danger_key": danger_key, "unique_accessory": unique_accessory,
		"ledger": ledger.duplicate(true), "blackmail_material": blackmail_material.duplicate(true),
		"schedule_override": schedule_override.duplicate(true), "home_address": home_address,
	}


func get_trait(trait_name: String) -> int:
	return int(traits.get(trait_name, Validate.TRAIT_MIN))


func _read_identity(d: Dictionary, source: String) -> void:
	id = Validate.require_string(d, "id", source)
	name = Validate.require_string(d, "name", source)
	archetype = Validate.optional_string(d, "archetype", "", source)
	traits = Validate.optional_traits(d, "traits", source)
	occupation_id = Validate.optional_string(d, "occupation_id", "", source)
	department = Validate.optional_string(d, "department", "", source)
	tier = Validate.optional_int(d, "tier", 1, source)
	home_room = Validate.optional_string(d, "home_room", "", source)
	desk_position = Validate.optional_vector2i(d, "desk_position", NO_DESK, source)
	is_named = Validate.optional_bool(d, "is_named", false, source)
	portrait_seed = Validate.optional_int(d, "portrait_seed", 0, source)
	weakness_key = Validate.optional_string(d, "weakness_key", "", source)
	danger_key = Validate.optional_string(d, "danger_key", "", source)
	unique_accessory = Validate.optional_string(d, "unique_accessory", "", source)
	home_address = Validate.optional_string(d, "home_address", "", source)


func _read_state(d: Dictionary, source: String) -> void:
	current_room = Validate.optional_string(d, "current_room", home_room, source)
	floor = Validate.optional_int(d, "floor", 0, source)
	position = Validate.optional_vector2(d, "position", Vector2.ZERO, source)
	state = Validate.optional_string(d, "state", STATE_IDLE, source)
	mood = Validate.optional_float(d, "mood", 0.0, source)
	merit = Validate.optional_int(d, "merit", 0, source)
	is_slacker = Validate.optional_bool(d, "is_slacker", false, source)
	alive = Validate.optional_bool(d, "alive", true, source)
	removed_cause = Validate.optional_string(d, "removed_cause", "", source)
	lod = Validate.check_int_range(Validate.optional_int(d, "lod", LOD_STATISTICAL, source),
			"lod", LOD_FULL, LOD_STATISTICAL, source)
	routine_template = Validate.optional_string(d, "routine_template", "", source)
	routine_overrides = NPCData.parse_routine_overrides(d, source)
	schedule_override = Validate.optional_dict(d, "schedule_override", {}, source).duplicate(true)


func _read_social(d: Dictionary, source: String) -> void:
	gatherings = Validate.optional_string_array(d, "gatherings", source)
	blackmail_material = _parse_free_entries(
			Validate.optional_array(d, "blackmail_material", [], source))
	ledger = _parse_ledger(Validate.optional_dict(d, "ledger", {}, source), source)


static func _parse_ledger(raw: Dictionary, source: String) -> Dictionary:
	var out: Dictionary = new_ledger()
	Validate.enter("ledger")
	out["affection"] = Validate.optional_int(raw, "affection", 0, source)
	out["fear"] = Validate.optional_int(raw, "fear", 0, source)
	out["debt"] = Validate.optional_int(raw, "debt", 0, source)
	out["grievances"] = _parse_entries(raw, "grievances", GRIEVANCE_INT_KEYS, source)
	out["favours"] = _parse_entries(raw, "favours", FAVOUR_INT_KEYS, source)
	Validate.leave()
	return out


static func _parse_entries(raw: Dictionary, key: String, int_keys: Array[String],
		source: String) -> Array:
	var out: Array = []
	var entries: Array[Dictionary] = Validate.optional_dict_array(raw, key, source)
	for i: int in entries.size():
		Validate.enter("%s[%d]" % [key, i])
		var entry: Dictionary = entries[i].duplicate(true)
		for int_key: String in int_keys:
			if entry.has(int_key):
				entry[int_key] = Validate.optional_int(entries[i], int_key, 0, source)
		out.append(entry)
		Validate.leave()
	return out


static func _parse_free_entries(raw: Array) -> Array:
	var out: Array = []
	for element: Variant in raw:
		if element is Dictionary:
			var entry: Dictionary = Validate.strip_comments(element).duplicate(true)
			for key: String in FREE_INT_KEYS:
				var value: Variant = entry.get(key)
				if value is float and is_finite(value) and value == floorf(value):
					entry[key] = int(value)
			out.append(entry)
		else:
			out.append(element)
	return out
