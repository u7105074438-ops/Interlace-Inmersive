# game_launch.gd — Traspaso estático entre el menú y la escena de juego (nueva partida / continuar).
# PROPIETARIO DE: la petición de arranque pendiente y la pantalla de entrada al volver al menú.
# ESCUCHA: nada.
class_name GameLaunch
extends RefCounted

## Flujo: el menú llama prepare_new_run() o prepare_load() y luego start_game(tree).
## game_root.gd llama GameLaunch.consume() en su _ready():
##   {mode: "new"|"load", player_name: String, difficulty: String, intro_skipped: bool, first_run: bool,
##    portrait_seed: int (solo "new": CharacterPainter.appearance_from_seed del protagonista)}
##   mode "" = nadie pidió nada (p. ej. un escenario de autopilot montó el juego directamente).
## Dificultad (§15.7): el menú ya deja activo el preset con Database.set_difficulty_preset() antes de
## cambiar de escena, también en "load": el preset de la partida en curso se recuerda en el perfil
## (bandera run_difficulty, remember_run_preset) porque run.json aún no lo guarda. game_root, al
## cargar, puede reaplicar request.difficulty si no está vacío (idempotente).
## Al terminar una partida: EpilogueScreen / game_root llaman return_to_menu(tree, entry).
## Android: los menús ponen SceneTree.quit_on_go_back = false (gestionan «atrás»); start_game lo
## devuelve a true para que la escena de juego decida.

const GAME_SCENE := "res://scenes/world/game.tscn"
const BOOT_SCENE := "res://scenes/boot.tscn"
const MODE_NEW := "new"
const MODE_LOAD := "load"
## Pantalla con la que abre el menú al volver: "" (título), "new_game", "gallery".
const ENTRY_TITLE := ""
const ENTRY_NEW_GAME := "new_game"
const ENTRY_GALLERY := "gallery"
## Bandera del perfil con el preset de la partida en curso.
const RUN_PRESET_SETTING := "run_difficulty"

static var menu_entry: String = ENTRY_TITLE
static var _pending: Dictionary = {}
static var _database_checked: bool = false
static var _database_ok: bool = false


## Pide una partida nueva. difficulty: "interno" | "estandar" | "auditoria".
static func prepare_new_run(player_name: String, difficulty: String, intro_skipped: bool = false,
		first_run: bool = true) -> void:
	_pending = {
		"mode": MODE_NEW, "player_name": player_name, "difficulty": difficulty,
		"intro_skipped": intro_skipped, "first_run": first_run, "portrait_seed": portrait_seed_for(player_name),
	}


## Semilla de apariencia del protagonista derivada del nombre (la misma foto que la credencial del alta).
static func portrait_seed_for(player_name: String) -> int:
	return absi(hash(player_name.strip_edges().to_lower()))


## Pide cargar la partida guardada (SaveSystem.load_run() lo hace game_root). difficulty = preset de
## la partida guardada ("" = desconocido); el llamante ya lo activó en Database.
static func prepare_load(difficulty: String = "") -> void:
	_pending = {
		"mode": MODE_LOAD, "player_name": "", "difficulty": difficulty, "intro_skipped": true, "first_run": false,
		"portrait_seed": 0,
	}


## Recuerda (perfil) y activa (Database) el preset de la partida que empieza.
static func remember_run_preset(preset: String) -> void:
	SettingsMenu.set_value(RUN_PRESET_SETTING, preset, true)
	apply_preset(preset)


## Preset de la partida guardada: la bandera del perfil si es válida; si no, el por defecto de balance.
static func run_preset() -> String:
	var saved: String = SettingsMenu.get_string(RUN_PRESET_SETTING)
	if SettingsMenu.PRESETS.has(saved):
		return saved
	return str(MenuKit.bal("presets_por_defecto"))


## Activa un preset en Database (si existe). true si quedó activo.
static func apply_preset(preset: String) -> bool:
	if preset.is_empty() or not Database.has_method("set_difficulty_preset"):
		return false
	return bool(Database.call("set_difficulty_preset", preset))


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
		out = {"mode": "", "player_name": "", "difficulty": "", "intro_skipped": false, "first_run": false,
			"portrait_seed": 0}
	return out


static func clear() -> void:
	_pending.clear()


static func game_scene_exists() -> bool:
	return ResourceLoader.exists(GAME_SCENE)


## Cambia a la escena de juego. false si aún no existe (el llamante muestra el aviso).
static func start_game(tree: SceneTree) -> bool:
	if not game_scene_exists():
		return false
	tree.quit_on_go_back = true
	return tree.change_scene_to_file(GAME_SCENE) == OK


## Vuelve al menú principal (escena de arranque) abriendo la pantalla `entry`.
static func return_to_menu(tree: SceneTree, entry: String = ENTRY_TITLE) -> void:
	menu_entry = entry
	tree.change_scene_to_file(BOOT_SCENE)


## Carga Database una sola vez por proceso y recuerda el resultado (load_all_or_halt si existe:
## además vuelca el informe de errores a la consola).
static func ensure_database() -> bool:
	if _database_checked:
		return _database_ok
	_database_checked = true
	if Database.has_method("load_all_or_halt"):
		_database_ok = bool(Database.call("load_all_or_halt"))
	else:
		_database_ok = Database.load_all()
	return _database_ok


## Consume la pantalla de entrada pedida para el menú.
static func take_menu_entry() -> String:
	var entry: String = menu_entry
	menu_entry = ENTRY_TITLE
	return entry
