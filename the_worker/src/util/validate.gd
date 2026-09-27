# validate.gd — Lectura tipada y validada de registros de datos (JSON) con errores legibles.
# PROPIETARIO DE: la lista estática de errores de validación (Validate.errors).
# ESCUCHA: nada.
class_name Validate
extends RefCounted

## Uso (manual PASO 3, BUILD_NOTES §4):
##   var src := Validate.entry("occupations.json", i)        # "occupations.json → entrada 3"
##   var rank := Validate.require_int_range(d, "rank", 0, 33, src)
## Ninguna función falla: ante un problema anota en `errors` una línea con el formato exacto
##   "ARCHIVO → entrada N → campo 'clave': PROBLEMA (esperado X, recibido Y)"
## y devuelve un valor por defecto. N es el índice en el array JSON, empezando en 0.
## Para registros anidados, `enter("furniture[2]")` / `leave()` prefijan la clave mostrada:
##   campo 'furniture[2].pos'.
## Los números JSON llegan como float: require_int acepta floats enteros (3.0 → 3).
## Las claves que empiezan por "_" son comentarios y se ignoran.

const TRAIT_NAMES: Array[String] = [
	"ambition", "loyalty", "greed", "courage", "perception", "sociability",
]
const TRAIT_MIN := 0
const TRAIT_MAX := 100
const TIME_BANDS: Array[String] = [
	"arrival", "work_morning", "lunch", "work_afternoon", "exit", "night",
]

const ENTRY_FORMAT := "%s → entrada %d"
const ERROR_FORMAT := "%s → campo '%s': %s (esperado %s, recibido %s)"
const MAX_REPR_LENGTH := 60

const PROBLEM_MISSING := "clave ausente"
const PROBLEM_NULL := "valor nulo"
const PROBLEM_TYPE := "tipo incorrecto"
const PROBLEM_NOT_INTEGER := "número no entero"
const PROBLEM_RANGE := "fuera de rango"
const PROBLEM_MIN := "por debajo del mínimo"
const PROBLEM_ENUM := "valor no permitido"
const PROBLEM_FORMAT := "formato incorrecto"
const PROBLEM_ID := "identificador no válido"
const PROBLEM_UNKNOWN_KEY := "clave desconocida"
const RECEIVED_NOTHING := "nada"
const EXPECTED_ID := "identificador snake_case"
const EXPECTED_PAIR := "[x, y]"
const EXPECTED_INT_PAIR := "[x, y] enteros"
const ID_PATTERN := "^[a-z0-9_]+(@-?[0-9]+)?$"

static var errors: Array[String] = []
static var _path: Array[String] = []
static var _id_regex: RegEx = null


# ─── Gestión de errores ───────────────────────────────────────

static func clear_errors() -> void:
	errors.clear()
	_path.clear()


static func has_errors() -> bool:
	return not errors.is_empty()


## Copia de los errores acumulados y vacía la lista.
static func take_errors() -> Array[String]:
	var out: Array[String] = errors.duplicate()
	clear_errors()
	return out


## "ARCHIVO → entrada N": contexto que se pasa como `source`.
static func entry(file: String, index: int) -> String:
	return ENTRY_FORMAT % [file, index]


static func enter(segment: String) -> void:
	_path.append(segment)


static func leave() -> void:
	if not _path.is_empty():
		_path.pop_back()


## Anota un error con el formato exacto. Público para comprobaciones propias de cada clase.
static func report(source: String, key: String, problem: String, expected: String,
		received: String) -> void:
	errors.append(ERROR_FORMAT % [source, _display_key(key), problem, expected, received])


## Descripción breve de un valor recibido: `String "abc"`, `float 2.5`, `Array [1]`...
static func describe(value: Variant) -> String:
	if value == null:
		return "null"
	var text: String
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			text = "\"%s\"" % value
		TYPE_ARRAY, TYPE_DICTIONARY:
			text = JSON.stringify(value)
		_:
			text = str(value)
	if text.length() > MAX_REPR_LENGTH:
		text = text.left(MAX_REPR_LENGTH) + "…"
	return "%s %s" % [type_string(typeof(value)), text]


static func is_valid_id(value: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_PATTERN)
	return _id_regex.search(value) != null


## Claves no reconocidas (ni comentarios "_") de `d`, para conservarlas en `extra`.
static func extra_keys(d: Dictionary, known: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in d:
		var k: String = str(key)
		if k.begins_with("_") or known.has(k):
			continue
		out[k] = d[key]
	return out


## Copia de `d` sin las claves de comentario ("_...").
static func strip_comments(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in d:
		if not str(key).begins_with("_"):
			out[key] = d[key]
	return out


# ─── Obligatorios ─────────────────────────────────────────────

static func require_string(d: Dictionary, key: String, source: String) -> String:
	if not _present(d, key, "String", source):
		return ""
	return as_string(d[key], key, "", source)


## Extra: cadena no vacía en snake_case (admite sufijo de planta "@3").
static func require_id(d: Dictionary, key: String, source: String) -> String:
	var before: int = errors.size()
	var value: String = require_string(d, key, source)
	if errors.size() == before and not is_valid_id(value):
		report(source, key, PROBLEM_ID, EXPECTED_ID, describe(value))
	return value


static func require_int(d: Dictionary, key: String, source: String) -> int:
	if not _present(d, key, "int", source):
		return 0
	return as_int(d[key], key, 0, source)


static func require_int_range(d: Dictionary, key: String, min_value: int, max_value: int,
		source: String) -> int:
	var before: int = errors.size()
	var value: int = require_int(d, key, source)
	if errors.size() > before:
		return min_value
	return check_int_range(value, key, min_value, max_value, source)


static func require_int_min(d: Dictionary, key: String, min_value: int, source: String) -> int:
	var before: int = errors.size()
	var value: int = require_int(d, key, source)
	if errors.size() > before:
		return min_value
	return check_int_min(value, key, min_value, source)


static func require_float(d: Dictionary, key: String, source: String) -> float:
	if not _present(d, key, "float", source):
		return 0.0
	return as_float(d[key], key, 0.0, source)


static func require_float_range(d: Dictionary, key: String, min_value: float, max_value: float,
		source: String) -> float:
	var before: int = errors.size()
	var value: float = require_float(d, key, source)
	if errors.size() > before:
		return min_value
	return check_float_range(value, key, min_value, max_value, source)


static func require_bool(d: Dictionary, key: String, source: String) -> bool:
	if not _present(d, key, "bool", source):
		return false
	return as_bool(d[key], key, false, source)


static func require_array(d: Dictionary, key: String, source: String) -> Array:
	if not _present(d, key, "Array", source):
		return []
	return as_array(d[key], key, [], source)


static func require_dict(d: Dictionary, key: String, source: String) -> Dictionary:
	if not _present(d, key, "Dictionary", source):
		return {}
	return as_dict(d[key], key, {}, source)


static func require_vector2(d: Dictionary, key: String, source: String) -> Vector2:
	if not _present(d, key, EXPECTED_PAIR, source):
		return Vector2.ZERO
	return as_vector2(d[key], key, Vector2.ZERO, source)


## Extra: par de enteros [x, y] → Vector2i (celdas de sala, posiciones de mesa).
static func require_vector2i(d: Dictionary, key: String, source: String) -> Vector2i:
	if not _present(d, key, EXPECTED_INT_PAIR, source):
		return Vector2i.ZERO
	return as_vector2i(d[key], key, Vector2i.ZERO, source)


## Extra: cadena perteneciente a `allowed`. Ante fallo devuelve allowed[0].
static func require_enum(d: Dictionary, key: String, allowed: Array[String],
		source: String) -> String:
	var fallback: String = allowed[0] if not allowed.is_empty() else ""
	var before: int = errors.size()
	var value: String = require_string(d, key, source)
	if errors.size() > before:
		return fallback
	return check_enum(value, key, allowed, fallback, source)


## Extra: Array cuyos elementos son todos String → Array[String].
static func require_string_array(d: Dictionary, key: String, source: String) -> Array[String]:
	var before: int = errors.size()
	var raw: Array = require_array(d, key, source)
	if errors.size() > before:
		return []
	return as_string_array(raw, key, source)


## Extra: Array cuyos elementos son todos Dictionary → Array[Dictionary] (sin comentarios).
static func require_dict_array(d: Dictionary, key: String, source: String) -> Array[Dictionary]:
	var before: int = errors.size()
	var raw: Array = require_array(d, key, source)
	if errors.size() > before:
		return []
	return as_dict_array(raw, key, source)


## Extra: diccionario con los seis rasgos (§7.4) como enteros 0–100.
static func require_traits(d: Dictionary, key: String, source: String) -> Dictionary:
	var before: int = errors.size()
	var raw: Dictionary = require_dict(d, key, source)
	if errors.size() > before:
		return default_traits()
	return as_traits(raw, key, source)


# ─── Opcionales (ausente o null → valor por defecto, sin error) ─

static func optional_string(d: Dictionary, key: String, default_value: String,
		source: String) -> String:
	if not _given(d, key):
		return default_value
	return as_string(d[key], key, default_value, source)


static func optional_int(d: Dictionary, key: String, default_value: int, source: String) -> int:
	if not _given(d, key):
		return default_value
	return as_int(d[key], key, default_value, source)


static func optional_float(d: Dictionary, key: String, default_value: float,
		source: String) -> float:
	if not _given(d, key):
		return default_value
	return as_float(d[key], key, default_value, source)


static func optional_array(d: Dictionary, key: String, default_value: Array,
		source: String) -> Array:
	if not _given(d, key):
		return default_value
	return as_array(d[key], key, default_value, source)


static func optional_dict(d: Dictionary, key: String, default_value: Dictionary,
		source: String) -> Dictionary:
	if not _given(d, key):
		return default_value
	return as_dict(d[key], key, default_value, source)


## Extra.
static func optional_bool(d: Dictionary, key: String, default_value: bool, source: String) -> bool:
	if not _given(d, key):
		return default_value
	return as_bool(d[key], key, default_value, source)


## Extra.
static func optional_vector2(d: Dictionary, key: String, default_value: Vector2,
		source: String) -> Vector2:
	if not _given(d, key):
		return default_value
	return as_vector2(d[key], key, default_value, source)


## Extra.
static func optional_vector2i(d: Dictionary, key: String, default_value: Vector2i,
		source: String) -> Vector2i:
	if not _given(d, key):
		return default_value
	return as_vector2i(d[key], key, default_value, source)


## Extra.
static func optional_enum(d: Dictionary, key: String, allowed: Array[String],
		default_value: String, source: String) -> String:
	if not _given(d, key):
		return default_value
	var before: int = errors.size()
	var value: String = as_string(d[key], key, default_value, source)
	if errors.size() > before:
		return default_value
	return check_enum(value, key, allowed, default_value, source)


## Extra: ausente → Array[String] vacío.
static func optional_string_array(d: Dictionary, key: String, source: String) -> Array[String]:
	if not _given(d, key):
		return []
	return as_string_array(as_array(d[key], key, [], source), key, source)


## Extra: ausente → Array[Dictionary] vacío.
static func optional_dict_array(d: Dictionary, key: String, source: String) -> Array[Dictionary]:
	if not _given(d, key):
		return []
	return as_dict_array(as_array(d[key], key, [], source), key, source)


## Extra: rasgos opcionales; ausentes → todos a 0.
static func optional_traits(d: Dictionary, key: String, source: String) -> Dictionary:
	if not _given(d, key):
		return default_traits()
	return as_traits(as_dict(d[key], key, {}, source), key, source)


# ─── Conversores de valor (sin búsqueda de clave) ─────────────

static func as_string(value: Variant, key: String, fallback: String, source: String) -> String:
	if value is String or value is StringName:
		return str(value)
	report(source, key, PROBLEM_TYPE, "String", describe(value))
	return fallback


static func as_int(value: Variant, key: String, fallback: int, source: String) -> int:
	if value is int:
		return value
	if value is float:
		var f: float = value
		if is_finite(f) and f == floorf(f):
			return int(f)
		report(source, key, PROBLEM_NOT_INTEGER, "int", describe(value))
		return fallback
	report(source, key, PROBLEM_TYPE, "int", describe(value))
	return fallback


static func as_float(value: Variant, key: String, fallback: float, source: String) -> float:
	if value is float or value is int:
		return float(value)
	report(source, key, PROBLEM_TYPE, "float", describe(value))
	return fallback


static func as_bool(value: Variant, key: String, fallback: bool, source: String) -> bool:
	if value is bool:
		return value
	report(source, key, PROBLEM_TYPE, "bool", describe(value))
	return fallback


static func as_array(value: Variant, key: String, fallback: Array, source: String) -> Array:
	if value is Array:
		return value
	report(source, key, PROBLEM_TYPE, "Array", describe(value))
	return fallback


static func as_dict(value: Variant, key: String, fallback: Dictionary,
		source: String) -> Dictionary:
	if value is Dictionary:
		return value
	report(source, key, PROBLEM_TYPE, "Dictionary", describe(value))
	return fallback


static func as_vector2(value: Variant, key: String, fallback: Vector2, source: String) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and _is_number_pair(value):
		return Vector2(float(value[0]), float(value[1]))
	report(source, key, PROBLEM_FORMAT, EXPECTED_PAIR, describe(value))
	return fallback


static func as_vector2i(value: Variant, key: String, fallback: Vector2i,
		source: String) -> Vector2i:
	if value is Vector2i:
		return value
	var pair: Vector2 = Vector2.INF
	if value is Vector2:
		pair = value
	elif value is Array and _is_number_pair(value):
		pair = Vector2(float(value[0]), float(value[1]))
	if pair.is_finite() and pair == pair.floor():
		return Vector2i(pair)
	report(source, key, PROBLEM_FORMAT, EXPECTED_INT_PAIR, describe(value))
	return fallback


static func as_string_array(raw: Array, key: String, source: String) -> Array[String]:
	var out: Array[String] = []
	for i: int in raw.size():
		var element: Variant = raw[i]
		if element is String or element is StringName:
			out.append(str(element))
		else:
			report(source, "%s[%d]" % [key, i], PROBLEM_TYPE, "String", describe(element))
	return out


static func as_dict_array(raw: Array, key: String, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in raw.size():
		var element: Variant = raw[i]
		if element is Dictionary:
			out.append(strip_comments(element))
		else:
			report(source, "%s[%d]" % [key, i], PROBLEM_TYPE, "Dictionary", describe(element))
	return out


static func as_traits(raw: Dictionary, key: String, source: String) -> Dictionary:
	var out: Dictionary = {}
	enter(key)
	for trait_name: String in TRAIT_NAMES:
		out[trait_name] = require_int_range(raw, trait_name, TRAIT_MIN, TRAIT_MAX, source)
	for unknown: Variant in extra_keys(raw, TRAIT_NAMES):
		report(source, str(unknown), PROBLEM_UNKNOWN_KEY, "uno de %s" % str(TRAIT_NAMES),
				describe(raw[unknown]))
	leave()
	return out


static func default_traits() -> Dictionary:
	var out: Dictionary = {}
	for trait_name: String in TRAIT_NAMES:
		out[trait_name] = TRAIT_MIN
	return out


# ─── Comprobaciones de límites sobre valores ya leídos ────────

static func check_int_range(value: int, key: String, min_value: int, max_value: int,
		source: String) -> int:
	if value < min_value or value > max_value:
		report(source, key, PROBLEM_RANGE, "int %d..%d" % [min_value, max_value], describe(value))
		return clampi(value, min_value, max_value)
	return value


static func check_int_min(value: int, key: String, min_value: int, source: String) -> int:
	if value < min_value:
		report(source, key, PROBLEM_MIN, "int >= %d" % min_value, describe(value))
		return min_value
	return value


static func check_float_range(value: float, key: String, min_value: float, max_value: float,
		source: String) -> float:
	if value < min_value or value > max_value:
		report(source, key, PROBLEM_RANGE, "float %s..%s" % [str(min_value), str(max_value)],
				describe(value))
		return clampf(value, min_value, max_value)
	return value


static func check_enum(value: String, key: String, allowed: Array[String], fallback: String,
		source: String) -> String:
	if allowed.has(value):
		return value
	report(source, key, PROBLEM_ENUM, "uno de %s" % str(allowed), describe(value))
	return fallback


# ─── Internos ─────────────────────────────────────────────────

static func _present(d: Dictionary, key: String, expected: String, source: String) -> bool:
	if not d.has(key):
		report(source, key, PROBLEM_MISSING, expected, RECEIVED_NOTHING)
		return false
	if d[key] == null:
		report(source, key, PROBLEM_NULL, expected, "null")
		return false
	return true


static func _given(d: Dictionary, key: String) -> bool:
	return d.has(key) and d[key] != null


static func _is_number_pair(value: Array) -> bool:
	if value.size() != 2:
		return false
	for element: Variant in value:
		if not (element is int or element is float):
			return false
	return true


static func _display_key(key: String) -> String:
	if _path.is_empty():
		return key
	if key.is_empty():
		return ".".join(PackedStringArray(_path))
	return "%s.%s" % [".".join(PackedStringArray(_path)), key]
