# room_data.gd — Registro tipado de una sala (manual §27, §22, BUILD_NOTES §3).
# PROPIETARIO DE: nada (dato estático de solo lectura cargado por Database).
# ESCUCHA: nada.
class_name RoomData
extends RefCounted

## Claves obligatorias (§27): id, name_key, floor, clearance_required, art_band, kit, size.
## Posiciones y tamaños en celdas (1 celda = 1 "metro" del manual). Una dimensión 0 en `size`
## significa "la decide FloorLayout" (p. ej. pasillos con full_floor_width).
## Normalizaciones:
##  - furniture:     [{type, pos: Vector2i, rotation: float (grados), owner?, ...}]
##  - hiding_spots:  [{id, type, pos: Vector2i, ...}]
##  - interactables: [{id, type, pos: Vector2i, ...resto tal cual (contains, owner...)}]
##  - camera_positions: admite [x, y] o {id?, pos, rotation?}; siempre se normaliza a
##    {id: String, pos: Vector2i, rotation: float}; id por defecto "<sala>_cam_<i>".
##  - illegitimate_entries: Array libre; si un elemento es diccionario con "pos", pasa a Vector2i.
##  - occupants_by_band: {franja: int}, franjas de Validate.TIME_BANDS.
##  - floors: [min, max] solo en salas transversales (floor = TRANSVERSAL_FLOOR, §22.15).

const MIN_CLEARANCE := 0
const MAX_CLEARANCE := 7
const TRANSVERSAL_FLOOR := -99
const CAMERA_ID_FORMAT := "%s_cam_%d"
const FURNITURE_REQUIRED: Array[String] = ["type", "pos"]
const SPOT_REQUIRED: Array[String] = ["id", "type", "pos"]
const KNOWN_KEYS: Array[String] = [
	"id", "name_key", "floor", "wing", "clearance_required", "special_access", "art_band",
	"kit", "ambient_sound", "ambient_noise_level", "has_cameras", "camera_positions", "size",
	"furniture", "hiding_spots", "interactables", "illegitimate_entries", "connects_to",
	"occupants_by_band", "floors",
]

var id: String = ""
var name_key: String = ""
@warning_ignore("shadowed_global_identifier")
var floor: int = 0
var wing: String = ""
var clearance_required: int = MIN_CLEARANCE
var special_access: Array[String] = []
var art_band: String = ""
var kit: String = ""
var ambient_sound: String = ""
var ambient_noise_level: float = 0.0
var has_cameras: bool = false
var camera_positions: Array[Dictionary] = []
var size: Vector2i = Vector2i.ONE
var furniture: Array[Dictionary] = []
var hiding_spots: Array[Dictionary] = []
var interactables: Array[Dictionary] = []
var illegitimate_entries: Array = []
var connects_to: Array[String] = []
var occupants_by_band: Dictionary = {}
## [min, max] para salas transversales; vacío en salas normales.
var floors: Array[int] = []
var extra: Dictionary = {}


static func from_dict(d: Dictionary, source: String) -> RoomData:
	var r: RoomData = RoomData.new()
	r._read_identity(d, source)
	r._read_contents(d, source)
	r.extra = Validate.extra_keys(d, KNOWN_KEYS)
	return r


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out.merge({
		"id": id, "name_key": name_key, "floor": floor, "wing": wing,
		"clearance_required": clearance_required, "special_access": special_access.duplicate(),
		"art_band": art_band, "kit": kit, "ambient_sound": ambient_sound,
		"ambient_noise_level": ambient_noise_level, "has_cameras": has_cameras,
		"camera_positions": _export_entries(camera_positions), "size": [size.x, size.y],
		"furniture": _export_entries(furniture), "hiding_spots": _export_entries(hiding_spots),
		"interactables": _export_entries(interactables),
		"illegitimate_entries": _export_list(illegitimate_entries),
		"connects_to": connects_to.duplicate(), "occupants_by_band": occupants_by_band.duplicate(),
	}, true)
	if is_transversal():
		out["floors"] = floors.duplicate()
	return out


func is_transversal() -> bool:
	return not floors.is_empty()


## true si la sala existe en la planta `f` (sala normal: su planta; transversal: su intervalo).
func spans_floor(f: int) -> bool:
	if is_transversal():
		return f >= floors[0] and f <= floors[1]
	return f == floor


func get_occupants(band: String) -> int:
	return int(occupants_by_band.get(band, 0))


func _read_identity(d: Dictionary, source: String) -> void:
	id = Validate.require_id(d, "id", source)
	name_key = Validate.require_string(d, "name_key", source)
	floor = Validate.require_int(d, "floor", source)
	clearance_required = Validate.require_int_range(d, "clearance_required", MIN_CLEARANCE,
			MAX_CLEARANCE, source)
	art_band = Validate.require_string(d, "art_band", source)
	kit = Validate.require_string(d, "kit", source)
	size = _read_size(d, source)
	wing = Validate.optional_string(d, "wing", "", source)
	special_access = Validate.optional_string_array(d, "special_access", source)
	ambient_sound = Validate.optional_string(d, "ambient_sound", "", source)
	ambient_noise_level = Validate.optional_float(d, "ambient_noise_level", 0.0, source)
	has_cameras = Validate.optional_bool(d, "has_cameras", false, source)
	connects_to = Validate.optional_string_array(d, "connects_to", source)
	floors = _read_floors(d, source)


func _read_contents(d: Dictionary, source: String) -> void:
	furniture = _parse_entries(d, "furniture", FURNITURE_REQUIRED, source)
	hiding_spots = _parse_entries(d, "hiding_spots", SPOT_REQUIRED, source)
	interactables = _parse_entries(d, "interactables", SPOT_REQUIRED, source)
	camera_positions = _parse_cameras(d, source)
	illegitimate_entries = _parse_free_list(d, "illegitimate_entries", source)
	occupants_by_band = _parse_occupants(d, source)


static func _read_size(d: Dictionary, source: String) -> Vector2i:
	var before: int = Validate.errors.size()
	var value: Vector2i = Validate.require_vector2i(d, "size", source)
	if Validate.errors.size() > before:
		return Vector2i.ONE
	if value.x < 0 or value.y < 0:
		Validate.report(source, "size", Validate.PROBLEM_RANGE, "[ancho, alto] >= 0",
				Validate.describe(d["size"]))
		return Vector2i.ONE
	return value


static func _read_floors(d: Dictionary, source: String) -> Array[int]:
	var out: Array[int] = []
	if not d.has("floors") or d["floors"] == null:
		return out
	var before: int = Validate.errors.size()
	var pair: Vector2i = Validate.optional_vector2i(d, "floors", Vector2i.ZERO, source)
	if Validate.errors.size() > before:
		return out
	if pair.x > pair.y:
		Validate.report(source, "floors", Validate.PROBLEM_FORMAT, "[min, max] con min <= max",
				Validate.describe(d["floors"]))
		return out
	out.append(pair.x)
	out.append(pair.y)
	return out


static func _parse_entries(d: Dictionary, key: String, required: Array[String],
		source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = Validate.optional_dict_array(d, key, source)
	var with_rotation: bool = key == "furniture"
	for i: int in raw.size():
		Validate.enter("%s[%d]" % [key, i])
		out.append(_parse_entry(raw[i], required, with_rotation, source))
		Validate.leave()
	return out


static func _parse_entry(raw: Dictionary, required: Array[String], with_rotation: bool,
		source: String) -> Dictionary:
	var entry: Dictionary = raw.duplicate(true)
	for key: String in required:
		if key == "pos":
			entry["pos"] = Validate.require_vector2i(raw, "pos", source)
		else:
			entry[key] = Validate.require_string(raw, key, source)
	if raw.has("pos") and not required.has("pos"):
		entry["pos"] = Validate.optional_vector2i(raw, "pos", Vector2i.ZERO, source)
	if with_rotation or raw.has("rotation"):
		entry["rotation"] = Validate.optional_float(raw, "rotation", 0.0, source)
	return entry


func _parse_cameras(d: Dictionary, source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array = Validate.optional_array(d, "camera_positions", [], source)
	for i: int in raw.size():
		Validate.enter("camera_positions[%d]" % i)
		var cam: Dictionary = {"id": CAMERA_ID_FORMAT % [id, i], "pos": Vector2i.ZERO,
				"rotation": 0.0}
		if raw[i] is Dictionary:
			var src_cam: Dictionary = Validate.strip_comments(raw[i])
			cam.merge(src_cam, true)
			cam["id"] = Validate.optional_string(src_cam, "id", cam["id"], source)
			cam["pos"] = Validate.require_vector2i(src_cam, "pos", source)
			cam["rotation"] = Validate.optional_float(src_cam, "rotation", 0.0, source)
		else:
			cam["pos"] = Validate.as_vector2i(raw[i], "pos", Vector2i.ZERO, source)
		out.append(cam)
		Validate.leave()
	return out


static func _parse_free_list(d: Dictionary, key: String, source: String) -> Array:
	var out: Array = []
	var raw: Array = Validate.optional_array(d, key, [], source)
	for i: int in raw.size():
		if raw[i] is Dictionary and raw[i].has("pos"):
			Validate.enter("%s[%d]" % [key, i])
			var entry: Dictionary = Validate.strip_comments(raw[i])
			entry["pos"] = Validate.as_vector2i(entry["pos"], "pos", Vector2i.ZERO, source)
			out.append(entry)
			Validate.leave()
		else:
			out.append(raw[i])
	return out


static func _parse_occupants(d: Dictionary, source: String) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = Validate.optional_dict(d, "occupants_by_band", {}, source)
	Validate.enter("occupants_by_band")
	for key: Variant in Validate.strip_comments(raw):
		var band: String = str(key)
		Validate.check_enum(band, band, Validate.TIME_BANDS, band, source)
		out[band] = Validate.check_int_min(Validate.as_int(raw[key], band, 0, source), band, 0,
				source)
	Validate.leave()
	return out


## Convierte Vector2i/Vector2 de las entradas a [x, y] para JSON.
static func _export_entries(entries: Array[Dictionary]) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(_export_value(entry))
	return out


static func _export_list(entries: Array) -> Array:
	var out: Array = []
	for entry: Variant in entries:
		out.append(_export_value(entry))
	return out


static func _export_value(value: Variant) -> Variant:
	if value is Vector2i or value is Vector2:
		return [value.x, value.y]
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			out[key] = _export_value(value[key])
		return out
	if value is Array:
		return _export_list(value)
	return value
