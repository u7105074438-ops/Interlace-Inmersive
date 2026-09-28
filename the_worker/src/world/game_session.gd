# game_session.gd — Ciclo de vida de la partida (BUILD_NOTES §2): partida nueva o continuar, semilla, preset, nombre y rango forzado.
# PROPIETARIO DE: nada (orquesta los reset_for_new_run/load_state de los autoloads; el estado es de cada sistema).
# ESCUCHA: nada.
class_name GameSession
extends RefCounted

## API estática (la usa GameRoot y las pruebas):
##   read_request(overrides) → la petición de GameLaunch.consume() completada con los argumentos de QA:
##     {mode: "new"|"load"|"", player_name, difficulty, intro_skipped, first_run, portrait_seed,
##      seed: int, force_rank: int (-1 = no), skip_intro: bool}
##     skip_intro = SOLO el argumento de QA --skip-intro (salta apertura y tutorial). intro_skipped
##     (el jugador saltó la cinemática en el menú) NO salta el tutorial.
##   begin_new_run(request) → orden de BUILD_NOTES §2: preset de dificultad → set_run_seed →
##     GameClock (reset + partida.minutos_inicio: la jornada empieza con la gente ya llegando a los
##     tornos) → PlayerState → NPCDirector (reset + generate_population) → SocialGraph (reset +
##     build_initial_graph) → resto de autoloads → nombre y semilla de retrato del jugador (bandera
##     Player.PORTRAIT_FLAG) → rango forzado (QA).
##     NO emite run_started: lo hace GameRoot con el mundo ya construido (el reloj sigue en pausa).
##   load_saved_run() → SaveSystem.load_run() (emite run_loaded: llamarlo con el mundo ya montado).
##   wants_tutorial(request) → la partida nueva empieza en la sala de formación (§13.8).
## "" (sin petición: un escenario de QA montó la escena) = partida nueva con semilla de QA.

const MODE_NEW := "new"
const MODE_LOAD := "load"
const NO_RANK := -1
## Orden del ciclo de vida tras Database.load_all() (BUILD_NOTES §2).
const LIFECYCLE: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]
const POPULATION_STEPS: Dictionary = {
	"NPCDirector": "generate_population", "SocialGraph": "build_initial_graph",
}
const ARG_SEED := "seed"
const ARG_FORCE_RANK := "force-rank"
const ARG_SKIP_INTRO := "skip-intro"
const REASON_FORCED := "debug"
const B_QA_SEED := "partida.semilla_qa"
const SETTING_SKIP_SEEN := "skip_seen_intro"
const DEFAULT_NAME_KEY := "GAME_DEFAULT_PLAYER_NAME"
const B_START_MINUTES := "partida.minutos_inicio"


## Petición de arranque: GameLaunch (menú) + argumentos de línea de comandos (QA). `overrides`
## (pruebas) se superpone a la petición: {mode, seed, player_name, difficulty...}.
static func read_request(overrides: Dictionary = {}) -> Dictionary:
	var request: Dictionary = GameLaunch.consume()
	request.merge(overrides, true)
	if str(request.get("mode", "")).is_empty():
		request["mode"] = MODE_NEW
		request["qa"] = true
	request["seed"] = resolve_seed(request)
	request["force_rank"] = _int_arg(ARG_FORCE_RANK, NO_RANK)
	request["skip_intro"] = Autopilot.get_arg(ARG_SKIP_INTRO) == "true" or bool(request.get("skip_intro", false))
	return request


## Semilla: la de la petición (pruebas), --seed=N, la de QA (partida sin menú) o una aleatoria ≠ 0.
static func resolve_seed(request: Dictionary) -> int:
	if int(request.get("seed", 0)) != 0:
		return int(request["seed"])
	var arg: int = _int_arg(ARG_SEED, 0)
	if arg != 0:
		return arg
	if bool(request.get("qa", false)) or Autopilot.is_requested():
		return Database.get_balance_int(B_QA_SEED)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return maxi(1, rng.randi())


## Partida nueva (BUILD_NOTES §2). Database ya cargado (GameRoot usa load_all_or_halt).
static func begin_new_run(request: Dictionary) -> void:
	var difficulty: String = str(request.get("difficulty", ""))
	if not difficulty.is_empty() and Database.get_difficulty_presets().has(difficulty):
		Database.set_difficulty_preset(difficulty)
	var run_seed: int = int(request.get("seed", Database.get_balance_int(B_QA_SEED)))
	GameClock.set_run_seed(run_seed)
	for system_name: String in LIFECYCLE:
		var node: Node = _autoload(system_name)
		if node == null:
			continue
		node.call("reset_for_new_run")
		if system_name == LIFECYCLE[0]:
			GameClock.advance_minutes(Database.get_balance_float(B_START_MINUTES))
		if POPULATION_STEPS.has(system_name):
			node.call(str(POPULATION_STEPS[system_name]))
	PlayerState.set_player_name(player_name_of(request))
	if int(request.get("portrait_seed", 0)) != 0:
		PlayerState.set_flag(Player.PORTRAIT_FLAG, int(request["portrait_seed"]))
	apply_force_rank(int(request.get("force_rank", NO_RANK)))


## Nombre elegido en el alta o, en QA, el genérico traducido.
static func player_name_of(request: Dictionary) -> String:
	var chosen: String = str(request.get("player_name", "")).strip_edges()
	return chosen if not chosen.is_empty() else TranslationServer.translate(DEFAULT_NAME_KEY)


## --force-rank=N (QA): la primera ocupación de ese rango. Company sincroniza la silla en silencio.
static func apply_force_rank(rank: int) -> bool:
	if rank < OccupationData.MIN_RANK or rank > OccupationData.MAX_RANK:
		return false
	var options: Array[OccupationData] = Database.get_occupations_by_rank(rank)
	if options.is_empty():
		return false
	PlayerState.set_occupation(options[0].id, REASON_FORCED)
	return true


## Continuar: carga run.json (emite run_loaded y reanuda el reloj). false si no hay guardado válido.
static func load_saved_run() -> bool:
	if not SaveSystem.run_exists():
		return false
	return SaveSystem.load_run()


## Tutorial (§13.8): partida nueva, no saltado por QA (--skip-intro), y primera partida o el jugador
## no omite lo ya visto (ajuste skip_seen_intro). Saltar la cinemática no salta el tutorial.
static func wants_tutorial(request: Dictionary) -> bool:
	if str(request.get("mode", "")) != MODE_NEW or bool(request.get("qa", false)):
		return false
	if bool(request.get("skip_intro", false)):
		return false
	return bool(request.get("first_run", false)) or not SettingsMenu.get_bool(SETTING_SKIP_SEEN)


static func _int_arg(key: String, fallback: int) -> int:
	var raw: String = Autopilot.get_arg(key)
	return raw.to_int() if raw.is_valid_int() else fallback


static func _autoload(system_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath(system_name)) if tree != null else null
