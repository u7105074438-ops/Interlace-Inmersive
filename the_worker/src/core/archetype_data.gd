# archetype_data.gd — Registro tipado de un arquetipo de personaje (manual §28, §24.1, §8.1).
# PROPIETARIO DE: nada (dato estático de solo lectura cargado por Database).
# ESCUCHA: nada.
class_name ArchetypeData
extends RefCounted

## Claves obligatorias: id, name_key, description_key, traits (seis rasgos 0–100),
## visual_tic, caught_reaction. Opcional: propagation_bonus (multiplicador, neutro 1.0).
## `variation_range` es una clave de nivel de archivo: la lee Database, no esta clase.

const NEUTRAL_PROPAGATION := 1.0
const KNOWN_KEYS: Array[String] = [
	"id", "name_key", "description_key", "traits", "visual_tic", "caught_reaction",
	"propagation_bonus",
]

var id: String = ""
var name_key: String = ""
var description_key: String = ""
## {ambition, loyalty, greed, courage, perception, sociability} → int 0–100.
var traits: Dictionary = Validate.default_traits()
var visual_tic: String = ""
var caught_reaction: String = ""
var propagation_bonus: float = NEUTRAL_PROPAGATION
var extra: Dictionary = {}


static func from_dict(d: Dictionary, source: String) -> ArchetypeData:
	var a: ArchetypeData = ArchetypeData.new()
	a.id = Validate.require_id(d, "id", source)
	a.name_key = Validate.require_string(d, "name_key", source)
	a.description_key = Validate.require_string(d, "description_key", source)
	a.traits = Validate.require_traits(d, "traits", source)
	a.visual_tic = Validate.require_string(d, "visual_tic", source)
	a.caught_reaction = Validate.require_string(d, "caught_reaction", source)
	a.propagation_bonus = Validate.optional_float(d, "propagation_bonus", NEUTRAL_PROPAGATION,
			source)
	a.extra = Validate.extra_keys(d, KNOWN_KEYS)
	return a


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out.merge({
		"id": id, "name_key": name_key, "description_key": description_key,
		"traits": traits.duplicate(), "visual_tic": visual_tic,
		"caught_reaction": caught_reaction, "propagation_bonus": propagation_bonus,
	}, true)
	return out


func get_trait(trait_name: String) -> int:
	return int(traits.get(trait_name, Validate.TRAIT_MIN))
