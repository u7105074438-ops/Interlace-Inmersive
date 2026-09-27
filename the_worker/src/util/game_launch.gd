# game_launch.gd — Traspaso estático entre el menú y la escena de juego (nueva partida / continuar).
# PROPIETARIO DE: la petición de arranque pendiente y la pantalla de entrada al volver al menú.
# ESCUCHA: nada.
class_name GameLaunch
extends RefCounted

## Flujo: el menú llama prepare_new_run() o prepare_load() y luego start_game(tree).
## game_root.gd llama GameLaunch.consume() en su _ready():
##   {mode: "new"|"load", player_name: String, difficulty: String, intro_skipped: bool, first_run: bool}
##   mode "" = nadie pidió nada (p. ej. un escenario de autopilot montó el juego directamente).
## Al terminar una partida: EpilogueScreen / game_root llaman return_to_menu(tree, entry).

const GAME_SCENE := "res://scenes/world/game.tscn"
const BOOT_SCENE := "res://scenes/boot.tscn"
const MODE_NEW := "new"
const MODE_LOAD := "load"
## Pantalla con la que abre el menú al volver: "" (título), "new_game", "gallery".
const ENTRY_TITLE := ""
const ENTRY_NEW_GAME := "new_game"
const ENTRY_GALLERY := "gallery"

static var menu_entry: String = ENTRY_TITLE
static var _pending: Dictionary = {}
static var _database_checked: bool = false
static var _database_ok: bool = false


## Pide una partida nueva. difficulty: "interno" | "estandar" | "auditoria".
static func prepare_new_run(player_name: String, difficulty: String, intro_skipped: bool = false,
		first_run: bool = true) -> void:
	_pending = {
		"mode": MODE_NEW, "player_name": player_name, "difficulty": difficulty,
		"intro_skipped": intro_skipped, "first_run": first_run,
	}


## Pide cargar la partida guardada (SaveSystem.load_run() lo hace game_root).
static func prepare_load() -> void:
	_pending = {
		"mode": MODE_LOAD, "player_name": "", "difficulty": "", "intro_skipped": true, "first_run": false,
	}


static func has_pending() -> bool:
	return not _pending.is_empty()


## Copia de la petición sin consumirla.
static func peek() -> Dictionary:
	return _pending.duplicate()


## Devuelve la petición y la borra. Sin petición: {mode: ""}.
static func consume() -> Dictionary:
	var out: Dictionary = _pending.duplicate()
	_pending.clear()
	if out.is_empty():
		out = {"mode": "", "player_name": "", "difficulty": "", "intro_skipped": false, "first_run": false}
	return out


static func clear() -> void:
	_pending.clear()


static func game_scene_exists() -> bool:
	return ResourceLoader.exists(GAME_SCENE)


## Cambia a la escena de juego. false si aún no existe (el llamante muestra el aviso).
static func start_game(tree: SceneTree) -> bool:
	if not game_scene_exists():
		return false
	return tree.change_scene_to_file(GAME_SCENE) == OK


## Vuelve al menú principal (escena de arranque) abriendo la pantalla `entry`.
static func return_to_menu(tree: SceneTree, entry: String = ENTRY_TITLE) -> void:
	menu_entry = entry
	tree.change_scene_to_file(BOOT_SCENE)


## Carga Database una sola vez por proceso y recuerda el resultado.
static func ensure_database() -> bool:
	if _database_checked:
		return _database_ok
	_database_checked = true
	_database_ok = Database.load_all()
	return _database_ok


## Consume la pantalla de entrada pedida para el menú.
static func take_menu_entry() -> String:
	var entry: String = menu_entry
	menu_entry = ENTRY_TITLE
	return entry
