# investor_data.gd — Registro tipado de un inversor (manual §32.4, §24.4, §9.6).
# PROPIETARIO DE: nada (dato estático de solo lectura cargado por Database).
# ESCUCHA: nada.
class_name InvestorData
extends RefCounted

## Obligatorias: id, name, strategy, capital, initial_confidence (0–100), traits.
## Opcionales: bribable, blackmailable, reacts_to, on_confidence_loss.
## Las estrategias (`strategies` del archivo) son de nivel de archivo: las lee Database.

const MIN_CONFIDENCE := 0
const MAX_CONFIDENCE := 100
const KNOWN_KEYS: Array[String] = [
	"id", "name", "strategy", "capital", "initial_confidence", "bribable", "blackmailable",
	"traits", "reacts_to", "on_confidence_loss",
]

var id: String = ""
var name: String = ""
var strategy: String = ""
var capital: int = 0
var initial_confidence: int = MIN_CONFIDENCE
var bribable: bool = false
var blackmailable: bool = false
var traits: Dictionary = Validate.default_traits()
var reacts_to: Array[String] = []
var on_confidence_loss: String = ""
var extra: Dictionary = {}


static func from_dict(d: Dictionary, source: String) -> InvestorData:
	var v: InvestorData = InvestorData.new()
	v.id = Validate.require_id(d, "id", source)
	v.name = Validate.require_string(d, "name", source)
	v.strategy = Validate.require_string(d, "strategy", source)
	v.capital = Validate.require_int_min(d, "capital", 0, source)
	v.initial_confidence = Validate.require_int_range(d, "initial_confidence", MIN_CONFIDENCE,
			MAX_CONFIDENCE, source)
	v.traits = Validate.require_traits(d, "traits", source)
	v.bribable = Validate.optional_bool(d, "bribable", false, source)
	v.blackmailable = Validate.optional_bool(d, "blackmailable", false, source)
	v.reacts_to = Validate.optional_string_array(d, "reacts_to", source)
	v.on_confidence_loss = Validate.optional_string(d, "on_confidence_loss", "", source)
	v.extra = Validate.extra_keys(d, KNOWN_KEYS)
	return v


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out.merge({
		"id": id, "name": name, "strategy": strategy, "capital": capital,
		"initial_confidence": initial_confidence, "bribable": bribable,
		"blackmailable": blackmailable, "traits": traits.duplicate(),
		"reacts_to": reacts_to.duplicate(), "on_confidence_loss": on_confidence_loss,
	}, true)
	return out


func get_trait(trait_name: String) -> int:
	return int(traits.get(trait_name, Validate.TRAIT_MIN))
