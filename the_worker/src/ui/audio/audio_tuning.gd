# audio_tuning.gd — Lectura de ajustes de audio (balance.json) y de datos de bandas/salas para el sonido.
# PROPIETARIO DE: cachés de solo lectura de balance.json, art_bands.json y del índice de salas de respaldo.
# ESCUCHA: nada.
class_name AudioTuning
extends RefCounted

## Primero pregunta a Database (autoload); si aún no ha cargado (menú principal, tests con stub),
## lee el mismo archivo de datos. Nunca inventa valores: una ruta ausente avisa y devuelve 0/vacío.
## Solo debe llamarse desde el hilo principal (los hilos de render reciben un Dictionary ya resuelto).

const BALANCE_FILE := "res://data/balance.json"
const BANDS_FILE := "res://data/art_bands.json"
const ROOMS_DIR := "res://data/rooms/"
const ROOM_SUFFIX_SEPARATOR := "@"
const NO_ARRANGEMENT := "none"

static var _balance: Dictionary = {}
static var _bands: Array = []
static var _room_index: Dictionary = {}
static var _warned: Dictionary = {}


## Valor de balance por ruta con puntos ("audio.muzak.nivel_db"); null si no existe.
static func value(path: String) -> Variant:
	var db: Node = autoload("Database")
	if db != null and db.has_method("get_balance"):
		var v: Variant = db.call("get_balance", path)
		if v != null:
			return v
	return _walk(_file_balance(), path)


static func num(path: String) -> float:
	var v: Variant = value(path)
	if v is float or v is int:
		return float(v)
	_warn_missing(path)
	return 0.0


static func integer(path: String) -> int:
	return int(round(num(path)))


static func dict(path: String) -> Dictionary:
	var v: Variant = value(path)
	if v is Dictionary:
		return v
	_warn_missing(path)
	return {}


static func list(path: String) -> Array:
	var v: Variant = value(path)
	if v is Array:
		return v
	_warn_missing(path)
	return []


## Rango [min, max] guardado como lista de dos números.
static func range_of(path: String) -> Vector2:
	var a: Array = list(path)
	if a.size() < 2:
		return Vector2.ZERO
	return Vector2(float(a[0]), float(a[1]))


## Píxeles por "metro" del manual (BUILD_NOTES §3).
static func px_per_metre() -> float:
	return num("mundo.px_por_unidad")


## Banda de arte (art_bands.json) que contiene la planta; {} si ninguna.
@warning_ignore("shadowed_global_identifier")
static func band_for_floor(floor: int) -> Dictionary:
	for band: Dictionary in _all_bands():
		for f: Variant in band.get("floors", []):
			if int(f) == floor:
				return band
	return {}


static func band_by_id(band_id: String) -> Dictionary:
	for band: Dictionary in _all_bands():
		if str(band.get("id", "")) == band_id:
			return band
	return {}


static func all_bands() -> Array:
	return _all_bands().duplicate()


## Arreglo del hilo musical de la planta ("none" en fábrica y exterior).
@warning_ignore("shadowed_global_identifier")
static func arrangement_for_floor(floor: int) -> String:
	var band: Dictionary = band_for_floor(floor)
	return str(band.get("muzak_arrangement", NO_ARRANGEMENT))


## {ambient_sound, ambient_noise_level, acoustic_mask, art_band, floor} de una sala; {} si no existe.
static func room_info(room_id: String) -> Dictionary:
	var base_id: String = room_id.get_slice(ROOM_SUFFIX_SEPARATOR, 0)
	var db: Node = autoload("Database")
	if db != null and db.has_method("get_room"):
		var room: Object = db.call("get_room", base_id)
		if room is RoomData:
			return _info_from_room(room as RoomData)
	return _file_rooms().get(base_id, {})


static func _info_from_room(room: RoomData) -> Dictionary:
	return {
		"ambient_sound": room.ambient_sound,
		"ambient_noise_level": room.ambient_noise_level,
		"acoustic_mask": bool(room.extra.get("acoustic_mask", false)),
		"art_band": room.art_band,
		"floor": room.floor,
	}


static func _all_bands() -> Array:
	if _bands.is_empty():
		var parsed: Variant = _parse_file(BANDS_FILE)
		if parsed is Dictionary:
			_bands = (parsed as Dictionary).get("bands", [])
	return _bands


static func _file_balance() -> Dictionary:
	if _balance.is_empty():
		var parsed: Variant = _parse_file(BALANCE_FILE)
		if parsed is Dictionary:
			_balance = parsed
	return _balance


static func _file_rooms() -> Dictionary:
	if not _room_index.is_empty():
		return _room_index
	for file_name: String in DirAccess.get_files_at(ROOMS_DIR):
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = _parse_file(ROOMS_DIR + file_name)
		if parsed is Dictionary:
			_index_rooms((parsed as Dictionary).get("rooms", []))
	return _room_index


static func _index_rooms(rooms: Array) -> void:
	for entry: Variant in rooms:
		if not entry is Dictionary:
			continue
		var d: Dictionary = entry
		var level: Variant = d.get("ambient_noise_level", 0.0)
		_room_index[str(d.get("id", ""))] = {
			"ambient_sound": str(d.get("ambient_sound", "")),
			"ambient_noise_level": float(level) if level != null else 0.0,
			"acoustic_mask": bool(d.get("acoustic_mask", false)),
			"art_band": str(d.get("art_band", "")),
			"floor": int(d.get("floor", 0)) if d.get("floor") != null else 0,
		}


static func _parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _walk(root: Dictionary, path: String) -> Variant:
	var node: Variant = root
	for key: String in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = (node as Dictionary)[key]
	return node


## Autoload por nombre (null si no existe o no hay árbol). Solo hilo principal.
static func autoload(autoload_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(autoload_name))


static func _warn_missing(path: String) -> void:
	if _warned.has(path):
		return
	_warned[path] = true
	push_warning("AudioTuning: balance path '%s' missing or of the wrong type" % path)
