# test_case.gd — Base de los cuerpos de escenario (tests/cases/*_case.gd).
# PROPIETARIO DE: los contadores de comprobaciones del escenario en curso.
# ESCUCHA: nada.
class_name TestCase
extends Node

## Un caso hace `extends TestCase` y sobrescribe run_case() (puede usar `await` y los globales
## de los autoloads). No depende de ningún archivo de src/: accede a los autoloads por nombre.
##   check(cond, msg) · check_eq(a, b, msg) · check_near(a, b, eps, msg)
##   new_run(seed) → partida nueva y reproducible (orden de ciclo de vida de BUILD_NOTES §2).
## Salida: una línea "PASS: msg" / "FAIL: msg" por comprobación.

const DEFAULT_SEED := 12345
const BALANCE_FILE := "res://data/balance.json"
## Orden de ciclo de vida (BUILD_NOTES §2), tras Database.load_all().
const LIFECYCLE_ORDER: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]

static var _database_loaded: bool = false

var passes: int = 0
var failures: int = 0
## Errores del motor (push_error, ERR_*) tolerados durante el caso; -1 = sin límite.
## Los SCRIPT ERROR siempre cuentan como fallo.
var allowed_engine_errors: int = 0
## Reputación con la que new_run() deja al jugador (los casos se escribieron con reputación 0);
## < 0 conserva jugador.reputacion_inicial de balance.json.
var baseline_reputation: float = 0.0


## Sobrescribir en el caso.
func run_case() -> void:
	pass


func run_all() -> void:
	await run_case()
	print("[case] %d passed, %d failed" % [passes, failures])


func check(cond: bool, msg: String) -> bool:
	if cond:
		passes += 1
		print("PASS: %s" % msg)
	else:
		failures += 1
		print("FAIL: %s" % msg)
	return cond


func check_eq(a: Variant, b: Variant, msg: String) -> bool:
	var same: bool = values_equal(a, b)
	if same:
		return check(true, msg)
	return check(false, "%s (got %s, expected %s)" % [msg, _repr(a), _repr(b)])


func check_near(a: float, b: float, eps: float, msg: String) -> bool:
	if absf(a - b) <= eps:
		return check(true, msg)
	return check(false, "%s (got %s, expected %s ± %s)" % [msg, str(a), str(b), str(eps)])


## Igualdad tolerante a tipos: int y float se comparan por valor; tipos distintos → false
## (sin el error de GDScript al comparar tipos incompatibles).
static func values_equal(a: Variant, b: Variant) -> bool:
	var numeric: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if numeric.has(typeof(a)) and numeric.has(typeof(b)):
		return float(a) == float(b)
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta == TYPE_STRING_NAME:
		ta = TYPE_STRING
	if tb == TYPE_STRING_NAME:
		tb = TYPE_STRING
	if ta != tb:
		return false
	return a == b


## Partida nueva con semilla fija. Devuelve true si Database cargó los datos.
## Orden: Database.load_all() (una vez por proceso, solo si hay datos) → GameClock → PlayerState
## → NPCDirector (reset + generate_population) → SocialGraph (reset + build_initial_graph)
## → reset_for_new_run() del resto. Todo protegido con has_method.
func new_run(run_seed: int = DEFAULT_SEED, with_population: bool = true) -> bool:
	var db_ok: bool = _ensure_database()
	_set_seed(run_seed)
	for system_name: String in LIFECYCLE_ORDER:
		_reset_system(system_name, db_ok and with_population)
		if system_name == "PlayerState" and baseline_reputation >= 0.0:
			autoload("PlayerState").set("_reputation", baseline_reputation)
		if system_name == "GameClock":
			_set_seed(run_seed)
	return db_ok


func autoload(autoload_name: String) -> Node:
	return get_tree().root.get_node_or_null(NodePath(autoload_name))


func wait_frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _ensure_database() -> bool:
	if _database_loaded:
		return true
	var db: Node = autoload("Database")
	if db == null or not db.has_method("load_all") or not FileAccess.file_exists(BALANCE_FILE):
		return false
	var result: Variant = db.call("load_all")
	_database_loaded = result is bool and result
	return _database_loaded


func _set_seed(run_seed: int) -> void:
	var clock: Node = autoload("GameClock")
	if clock != null and clock.has_method("set_run_seed"):
		clock.call("set_run_seed", run_seed)


func _reset_system(system_name: String, populate: bool) -> void:
	var node: Node = autoload(system_name)
	if node == null:
		return
	if node.has_method("reset_for_new_run"):
		node.call("reset_for_new_run")
	if not populate:
		return
	if system_name == "NPCDirector" and node.has_method("generate_population"):
		node.call("generate_population")
	elif system_name == "SocialGraph" and node.has_method("build_initial_graph"):
		node.call("build_initial_graph")


static func _repr(value: Variant) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % value
	return "%s %s" % [type_string(typeof(value)), str(value)]
