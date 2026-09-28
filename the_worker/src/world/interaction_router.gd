# interaction_router.gd — Despachador de interacciones (BUILD_NOTES §14/§15): elige por interact_type el módulo que la resuelve.
# PROPIETARIO DE: la tabla de módulos descubiertos (tipo → script) y el registro de módulos inyectados por pruebas.
# ESCUCHA: nada (el jugador llama a interact() con la tecla E o el botón contextual).
class_name InteractionRouter
extends RefCounted

## CONTRATO DE MÓDULO (un archivo por familia en res://src/world/interactions/*.gd; ver §15):
##   static func handled_types() -> Array[String]            (obligatoria: interact_type que atiende)
##   static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void
##                                                            (obligatoria; puede usar await)
##   static func is_available(interactable: Interactable, player: Node) -> bool   (opcional: false =
##       el jugador no lo enfoca ni ve la indicación; por defecto true)
##   static func prompt_key(interactable: Interactable) -> String   (opcional: clave de la indicación
##       contextual; "" = la de Interactable.get_prompt_key(), UI_INTERACT_<TIPO>)
## ctx = {game_root: GameRoot|null, ui_root: UIRoot|null, streamer: FloorStreamer|null,
##        room_id: String (sala del interactivo o, si no tiene, la del jugador), floor: int}
## Descubrimiento (una vez por proceso, perezoso): primero los módulos del mundo (BUILTIN_MODULES:
## FloorTravel para los tránsitos, WorldBridges para los objetos soltados), después los archivos de
## MODULE_DIR en orden alfabético (se ignoran los que empiezan por "_"). Un tipo reclamado dos
## veces: gana el primero y se avisa (push_warning). Un tipo sin módulo → _default.gd: indicación
## neutra UI_INTERACT_EXAMINE («Mirar») y aviso educado INTERACT_NOTHING_USEFUL; apaños del bucle
## básico hasta que su módulo exista: "npc" (ficha rápida), "bed" del piso (dormir y guardar),
## "desk" propia (ordenador), "turnstile" (pasar la tarjeta). Quien reclame esos tipos conserva
## ese comportamiento (ver la cabecera de _default.gd).
## Un nodo que no es Interactable pero tiene interact(player) se llama directamente.
## Pruebas: register_module(script) añade/reemplaza módulos en caliente; reset() vuelve a descubrir.

const MODULE_DIR := "res://src/world/interactions/"
const DEFAULT_MODULE := "res://src/world/interactions/_default.gd"
const BUILTIN_MODULES: Array[String] = [
	"res://src/world/floor_travel.gd", "res://src/world/world_bridges.gd",
]
const SCRIPT_EXTENSIONS: Array[String] = [".gd", ".gdc"]
const REMAP_SUFFIX := ".remap"
const PRIVATE_PREFIX := "_"
const M_TYPES := "handled_types"
const M_INTERACT := "interact"
const M_AVAILABLE := "is_available"
const M_PROMPT := "prompt_key"
const NODE_METHOD := "interact"
const WARN_DUPLICATE := "InteractionRouter: '%s' ya lo atiende %s; se ignora %s"
const WARN_INVALID := "InteractionRouter: %s no cumple el contrato de módulo (handled_types/interact)"

static var _modules: Dictionary = {}
## script → {método: bool} (caché de _has_static: la disponibilidad se consulta cada fotograma).
static var _caps: Dictionary = {}
static var _scanned: bool = false
static var _default: Script = null


## Punto de entrada (Player.try_interact → InteractionRouter.interact(foco, jugador)).
static func interact(interactable: Node, player: Node) -> void:
	if interactable == null or not is_instance_valid(interactable):
		return
	var item: Interactable = interactable as Interactable
	if item == null:
		if interactable.has_method(NODE_METHOD):
			interactable.call(NODE_METHOD, player)
		return
	var module: Script = module_for(item.interact_type)
	if module == null:
		return
	module.call(M_INTERACT, item, player, build_context(item, player))


## Disponibilidad según el módulo (además de Interactable.is_available()).
static func is_available_for(interactable: Node, player: Node) -> bool:
	var item: Interactable = interactable as Interactable
	if item == null:
		return true
	var module: Script = module_for(item.interact_type)
	if module == null or not _has_static(module, M_AVAILABLE):
		return true
	return bool(module.call(M_AVAILABLE, item, player))


## Clave de la indicación contextual ("" = la del propio interactivo).
static func prompt_key_for(interactable: Node) -> String:
	var item: Interactable = interactable as Interactable
	if item == null:
		return ""
	var module: Script = module_for(item.interact_type)
	if module == null or not _has_static(module, M_PROMPT):
		return ""
	return str(module.call(M_PROMPT, item))


## Módulo que atiende un tipo (el de por defecto si nadie lo reclama).
static func module_for(interact_type: String) -> Script:
	_ensure_scanned()
	var found: Script = _modules.get(interact_type) as Script
	return found if found != null else _default


static func has_handler(interact_type: String) -> bool:
	_ensure_scanned()
	return _modules.has(interact_type)


## tipo → ruta del script que lo atiende (depuración, pruebas, documentación).
static func handled_types_map() -> Dictionary:
	_ensure_scanned()
	var out: Dictionary = {}
	for interact_type: String in _modules:
		out[interact_type] = (_modules[interact_type] as Script).resource_path
	return out


## ctx del contrato: raíz de juego, interfaz, streamer, sala y planta.
static func build_context(item: Interactable, player: Node) -> Dictionary:
	var tree: SceneTree = item.get_tree() if item.is_inside_tree() else null
	var streamer: FloorStreamer = FloorStreamer.find_in(tree) if tree != null else null
	var room_id: String = item.room_id
	if room_id.is_empty() and streamer != null and player is Node2D:
		room_id = streamer.get_room_at((player as Node2D).global_position)
	return {
		"game_root": GameRoot.find(tree) if tree != null else null,
		"ui_root": UIRoot.find(tree) if tree != null else null,
		"streamer": streamer, "room_id": room_id,
		"floor": streamer.get_current_floor() if streamer != null else PlayerState.get_floor(),
	}


## Pruebas / herramientas: registra un módulo (sus tipos reemplazan a los existentes).
static func register_module(script: Script) -> bool:
	_ensure_scanned()
	if not _is_module(script):
		push_warning(WARN_INVALID % (script.resource_path if script != null else "null"))
		return false
	for interact_type: String in _types_of(script):
		_modules[interact_type] = script
	return true


## Olvida la tabla (el próximo uso vuelve a descubrir los módulos).
static func reset() -> void:
	_modules.clear()
	_caps.clear()
	_default = null
	_scanned = false


# ─── Descubrimiento ────────────────────────────────────────────

static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	_default = load(DEFAULT_MODULE) as Script if ResourceLoader.exists(DEFAULT_MODULE) else null
	for path: String in BUILTIN_MODULES + module_paths():
		_adopt(path)


## Scripts de MODULE_DIR (también exportados: .gdc y .remap), en orden, sin los privados ("_*").
static func module_paths() -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(MODULE_DIR):
		var file_name: String = file.trim_suffix(REMAP_SUFFIX)
		if file_name.begins_with(PRIVATE_PREFIX) or not SCRIPT_EXTENSIONS.has("." + file_name.get_extension()):
			continue
		var path: String = MODULE_DIR + file_name.get_basename() + ".gd"
		if not out.has(path):
			out.append(path)
	out.sort()
	return out


static func _adopt(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var script: Script = load(path) as Script
	if not _is_module(script):
		push_warning(WARN_INVALID % path)
		return
	for interact_type: String in _types_of(script):
		if _modules.has(interact_type):
			push_warning(WARN_DUPLICATE % [interact_type, (_modules[interact_type] as Script).resource_path, path])
			continue
		_modules[interact_type] = script


static func _is_module(script: Script) -> bool:
	return script != null and _has_static(script, M_TYPES) and _has_static(script, M_INTERACT)


static func _types_of(script: Script) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in script.call(M_TYPES):
		out.append(str(value))
	return out


static func _has_static(script: Script, method: String) -> bool:
	var caps: Dictionary = _caps.get(script, {})
	if caps.has(method):
		return bool(caps[method])
	var found: bool = false
	for info: Dictionary in script.get_script_method_list():
		if info["name"] == method and int(info["flags"]) & METHOD_FLAG_STATIC:
			found = true
	caps[method] = found
	_caps[script] = caps
	return found
