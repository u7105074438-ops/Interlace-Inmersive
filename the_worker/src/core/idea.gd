# idea.gd — Una idea viva del mundo, con propietario y caducidad (manual §11.1, §11.2).
# PROPIETARIO DE: nada (estructura de datos; las ideas pertenecen a IdeaPool).
# ESCUCHA: nada.
class_name Idea
extends RefCounted

## Campos exactos de §11.1 (id, owner, quality, department, freshness, known_by, presented)
## más cuatro opcionales de apoyo: text_key (plantilla de ideas.json), acquired_by (quién la
## posee además del propietario, p. ej. "player"), acquisition_method (vía de §11.1) y
## created_day (jornada de generación).

const MIN_QUALITY := 0
const MAX_QUALITY := 100

var id: String = ""
## Personaje que la generó.
var owner: String = ""
## 20–100 según ideas.json / balance.json.
var quality: int = MIN_QUALITY
var department: String = ""
## Jornadas restantes antes de caducar.
var freshness: int = 0
## Personajes que saben de su existencia.
var known_by: Array[String] = []
var presented: bool = false
var text_key: String = ""
var acquired_by: String = ""
var acquisition_method: String = ""
var created_day: int = 0


static func from_dict(d: Dictionary, source: String) -> Idea:
	var i: Idea = Idea.new()
	i.id = Validate.require_string(d, "id", source)
	i.owner = Validate.require_string(d, "owner", source)
	i.quality = Validate.require_int_range(d, "quality", MIN_QUALITY, MAX_QUALITY, source)
	i.department = Validate.require_string(d, "department", source)
	i.freshness = Validate.require_int(d, "freshness", source)
	i.known_by = Validate.require_string_array(d, "known_by", source)
	i.presented = Validate.require_bool(d, "presented", source)
	i.text_key = Validate.optional_string(d, "text_key", "", source)
	i.acquired_by = Validate.optional_string(d, "acquired_by", "", source)
	i.acquisition_method = Validate.optional_string(d, "acquisition_method", "", source)
	i.created_day = Validate.optional_int(d, "created_day", 0, source)
	return i


func to_dict() -> Dictionary:
	return {
		"id": id, "owner": owner, "quality": quality, "department": department,
		"freshness": freshness, "known_by": known_by.duplicate(), "presented": presented,
		"text_key": text_key, "acquired_by": acquired_by,
		"acquisition_method": acquisition_method, "created_day": created_day,
	}


func is_expired() -> bool:
	return freshness <= 0
