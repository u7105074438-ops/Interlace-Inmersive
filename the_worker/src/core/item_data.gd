# item_data.gd — Un objeto de inventario, ordinario o comprometedor (manual §11.3).
# PROPIETARIO DE: nada (estructura de datos; el inventario pertenece a PlayerState).
# ESCUCHA: nada.
class_name ItemData
extends RefCounted

## Obligatorias: id, name_key, category ("ordinary" | "compromising").
## Opcionales: value (int), stack (int >= 1), extra (Dictionary). Las claves desconocidas del
## registro también se guardan en `extra`.
## Un objeto comprometedor hallado en un registro corporal es evidencia de peso definitivo (§12.4).

const CATEGORY_ORDINARY := "ordinary"
const CATEGORY_COMPROMISING := "compromising"
const CATEGORIES: Array[String] = [CATEGORY_ORDINARY, CATEGORY_COMPROMISING]
const MIN_STACK := 1
const KNOWN_KEYS: Array[String] = ["id", "name_key", "category", "value", "stack", "extra"]

var id: String = ""
var name_key: String = ""
var category: String = CATEGORY_ORDINARY
var value: int = 0
var stack: int = MIN_STACK
var extra: Dictionary = {}


static func make(p_id: String, p_name_key: String, p_category: String) -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = p_id
	item.name_key = p_name_key
	item.category = p_category
	return item


static func from_dict(d: Dictionary, source: String) -> ItemData:
	var item: ItemData = ItemData.new()
	item.id = Validate.require_id(d, "id", source)
	item.name_key = Validate.require_string(d, "name_key", source)
	item.category = Validate.require_enum(d, "category", CATEGORIES, source)
	item.value = Validate.optional_int(d, "value", 0, source)
	item.stack = Validate.check_int_min(Validate.optional_int(d, "stack", MIN_STACK, source),
			"stack", MIN_STACK, source)
	item.extra = Validate.optional_dict(d, "extra", {}, source).duplicate(true)
	item.extra.merge(Validate.extra_keys(d, KNOWN_KEYS), true)
	return item


func to_dict() -> Dictionary:
	return {
		"id": id, "name_key": name_key, "category": category, "value": value,
		"stack": stack, "extra": extra.duplicate(true),
	}


func is_compromising() -> bool:
	return category == CATEGORY_COMPROMISING
