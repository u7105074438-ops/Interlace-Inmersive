# autopilot.gd — Arnés de QA: ejecuta escenarios guionizados y guarda capturas (BUILD_NOTES §9).
# PROPIETARIO DE: los argumentos de línea de comandos de QA y el directorio de capturas.
# ESCUCHA: nada.
class_name Autopilot
extends Node

## Uso: godot --path . -- --autopilot=<escenario> --shots=<dir> [--force-rank=N --seed=N --skip-intro]
## El escenario es res://src/util/autopilot_scenarios/<escenario>.gd: un Node con
##   func run(pilot: Autopilot) -> void   (puede usar await)
## que monta lo que necesite (p. ej. la escena de juego), llama pilot.shot("nombre") y termina.
## Cada constructor es propietario de su propio archivo de escenario.

const SCENARIO_DIR := "res://src/util/autopilot_scenarios/"
const DEFAULT_SHOT_DIR := "user://shots"

var _args: Dictionary = {}
var _shot_dir: String = DEFAULT_SHOT_DIR


## Devuelve los argumentos de usuario (--clave=valor → {clave: valor}; --flag → {flag: "true"}).
static func parse_user_args() -> Dictionary:
	var out: Dictionary = {}
	for raw: String in OS.get_cmdline_user_args():
		var arg: String = raw.trim_prefix("--")
		var eq: int = arg.find("=")
		if eq >= 0:
			out[arg.substr(0, eq)] = arg.substr(eq + 1)
		else:
			out[arg] = "true"
	return out


## True si se ha pedido un escenario por línea de comandos.
static func is_requested() -> bool:
	return parse_user_args().has("autopilot")


static func get_arg(key: String, default_value: String = "") -> String:
	return str(parse_user_args().get(key, default_value))


## Lanza el escenario pedido como hijo de la raíz. Lo invoca boot.gd al arrancar.
static func launch(tree: SceneTree) -> void:
	var pilot: Autopilot = Autopilot.new()
	pilot.name = "Autopilot"
	tree.root.add_child.call_deferred(pilot)


func _ready() -> void:
	_args = parse_user_args()
	_shot_dir = str(_args.get("shots", DEFAULT_SHOT_DIR))
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_run_scenario.call_deferred(str(_args.get("autopilot", "")))


func get_args() -> Dictionary:
	return _args.duplicate()


func _run_scenario(scenario: String) -> void:
	var path: String = SCENARIO_DIR + scenario + ".gd"
	if not ResourceLoader.exists(path):
		push_error("Autopilot: unknown scenario '%s' (%s)" % [scenario, path])
		get_tree().quit(2)
		return
	var script: GDScript = load(path) as GDScript
	var node: Node = script.new() as Node
	node.name = "Scenario"
	add_child(node)
	print("[autopilot] running scenario %s" % scenario)
	await node.call("run", self)
	print("[autopilot] scenario %s finished" % scenario)
	get_tree().quit(0)


## Espera n fotogramas renderizados.
func frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## Espera t segundos reales.
func seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Guarda una captura PNG del viewport en el directorio de capturas.
func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _shot_dir.path_join(shot_name + ".png")
	var err: Error = img.save_png(path)
	print("[autopilot] shot %s -> %s (%s)" % [shot_name, path, error_string(err)])


## Simula pulsar/soltar una acción de entrada.
func press(action: String, hold_seconds: float = 0.0) -> void:
	Input.action_press(action)
	if hold_seconds > 0.0:
		await seconds(hold_seconds)
	Input.action_release(action)
