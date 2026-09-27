# muzak_library.gd — Biblioteca de pistas del hilo musical compartida por todos los AudioDirector del proceso.
# PROPIETARIO DE: la caché LRU de pistas renderizadas, la pieza pedida por cada director y el render en curso.
# ESCUCHA: nada (los AudioDirector llaman a request() / poll() / release()).
class_name MuzakLibrary
extends RefCounted

## Render en dos fases en WorkerThreadPool (fase 1: acompañamiento + melodía limpia; fase 2:
## variantes desafinada/atonal), un trabajo a la vez. **Nadie espera nunca a un render sin terminar**
## (BUILD_NOTES §6): si el director que lo pidió desaparece, el trabajo termina solo y el siguiente
## poll() de cualquier director lo recoge (wait_for_task_completion de una tarea ya completada es
## inmediato). La caché es del proceso: menú → partida → menú no vuelve a renderizar nada.
## Solo hilo principal (render_config() lee balance).

const KEY_SEPARATOR := "|"
const TASK_NAME := "muzak_render"

static var _stems: Dictionary = {}
static var _order: Array[String] = []
static var _requests: Dictionary = {}
static var _request_order: Array[int] = []
static var _job: Dictionary = {}
static var _cache_size: int = 1


static func key_for(piece: String, arrangement: String) -> String:
	return piece + KEY_SEPARATOR + arrangement


static func piece_of(key: String) -> String:
	return key.get_slice(KEY_SEPARATOR, 0)


## Máximo de piezas guardadas (audio.muzak.cache_piezas); nunca se expulsa una pieza pedida.
static func configure(cache_size: int) -> void:
	_cache_size = maxi(1, cache_size)


## `owner` (p. ej. get_instance_id()) quiere `key`; sustituye su petición anterior.
static func request(owner: int, key: String) -> void:
	_requests[owner] = key
	_request_order.erase(owner)
	_request_order.append(owner)
	if _stems.has(key):
		_touch(key)
	poll()


## El dueño ya no quiere nada (salida del árbol). No espera al render en curso.
static func release(owner: int) -> void:
	_requests.erase(owner)
	_request_order.erase(owner)


## Pistas disponibles para `key` ({} si aún no hay ninguna fase lista).
static func get_stems(key: String) -> Dictionary:
	return _stems.get(key, {})


## True si la pieza tiene todas sus variantes (o no se degrada).
static func is_complete(key: String) -> bool:
	return _stems.has(key) and stems_complete(_stems[key])


static func stems_complete(stems: Dictionary) -> bool:
	return not bool(stems.get("degradable", false)) \
			or (stems.get("mel", []) as Array).size() >= MuzakSynth.VARIANT_COUNT


static func is_rendering() -> bool:
	return not _job.is_empty()


## True si un render sigue ejecutándose en su hilo (aún no terminado).
static func render_in_flight() -> bool:
	return not _job.is_empty() and not WorkerThreadPool.is_task_completed(int(_job["id"]))


static func cached_keys() -> Array[String]:
	return _order.duplicate()


## Recoge el trabajo terminado (sin esperar si no lo está) y arranca el siguiente pendiente.
static func poll() -> void:
	if not _job.is_empty():
		if not WorkerThreadPool.is_task_completed(int(_job["id"])):
			return
		WorkerThreadPool.wait_for_task_completion(int(_job["id"]))
		var stems: Dictionary = (_job["holder"] as Array)[0]
		var key: String = str(_job["key"])
		_job = {}
		if not stems.is_empty():
			_store(key, stems)
	_start_next()


## La petición más reciente sin completar va primero; luego las de otros directores vivos.
static func _start_next() -> void:
	for i: int in range(_request_order.size() - 1, -1, -1):
		var key: String = str(_requests.get(_request_order[i], ""))
		if not key.is_empty() and not is_complete(key):
			_start_job(key)
			return


static func _start_job(key: String) -> void:
	var piece: String = piece_of(key)
	var arrangement: String = key.get_slice(KEY_SEPARATOR, 1)
	var cfg: Dictionary = MuzakSynth.render_config(piece)
	var base: Dictionary = _stems.get(key, {})
	var holder: Array = [{}]
	var task: Callable
	if base.is_empty():
		task = func() -> void: holder[0] = MuzakSynth.render_piece(piece, arrangement, cfg, 1)
	else:
		task = func() -> void: holder[0] = MuzakSynth.add_variants(base, cfg)
	_job = {"id": WorkerThreadPool.add_task(task, false, TASK_NAME), "key": key, "holder": holder}


static func _store(key: String, stems: Dictionary) -> void:
	_stems[key] = stems
	_touch(key)
	var wanted: Array = _requests.values()
	var i: int = 0
	while _order.size() > _cache_size and i < _order.size():
		var candidate: String = _order[i]
		if wanted.has(candidate):
			i += 1
			continue
		_order.remove_at(i)
		_stems.erase(candidate)


static func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)
