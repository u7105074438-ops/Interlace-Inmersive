# test_base.gd — Lanzador común de los escenarios headless (manual §21, BUILD_NOTES §7).
# PROPIETARIO DE: el ciclo de un escenario: carga del caso, límite de tiempo, errores y salida.
# ESCUCHA: nada.
extends SceneTree

## Uso:  tests/test_x.gd →  extends "res://tests/test_base.gd"
##                            func case_path() -> String: return "res://tests/cases/x_case.gd"
## Este script se compila antes de que existan los autoloads: no usar aquí sus globales.
## Código de salida = número de fallos (0 = PASS). Cuentan como fallo:
##  - cada check() fallido del caso,
##  - un caso que no ejecuta ninguna comprobación,
##  - cualquier SCRIPT ERROR durante el caso (el intérprete continúa tras ellos),
##  - errores del motor por encima de `allowed_engine_errors` del caso (-1 = sin límite),
##  - superar TIMEOUT_SECONDS.

const TIMEOUT_SECONDS := 60.0
const MAX_EXIT_CODE := 125


class ErrorCounter extends Logger:
	var script_errors: int = 0
	var engine_errors: int = 0
	var first_messages: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			script_errors += 1
		else:
			engine_errors += 1
		if first_messages.size() < 5:
			var text: String = rationale if not rationale.is_empty() else code
			first_messages.append("%s (%s:%d %s)" % [text, file, line, function])
		_mutex.unlock()


var _finished: bool = false
var _counter: ErrorCounter = ErrorCounter.new()


## Sobrescribir: ruta del cuerpo del escenario (script que extiende TestCase).
func case_path() -> String:
	return ""


func _initialize() -> void:
	OS.add_logger(_counter)
	_run()


func _run() -> void:
	await process_frame
	var timer: SceneTreeTimer = create_timer(TIMEOUT_SECONDS, true, false, true)
	timer.timeout.connect(_on_timeout)
	var case_node: Node = _instantiate_case()
	if case_node == null:
		_finish(1, "could not load or instantiate case '%s'" % case_path())
		return
	print("[test] %s" % case_path().get_file().get_basename())
	root.add_child(case_node)
	await case_node.run_all()
	_finish(_count_failures(case_node), "")


func _instantiate_case() -> Node:
	if case_path().is_empty() or not ResourceLoader.exists(case_path()):
		return null
	var script: Script = load(case_path()) as Script
	if script == null or not script.can_instantiate():
		return null
	var instance: Object = script.new()
	if not (instance is Node and instance.has_method("run_all")):
		return null
	return instance as Node


func _count_failures(case_node: Node) -> int:
	var passes: int = int(case_node.get("passes"))
	var failures: int = int(case_node.get("failures"))
	var allowed: int = int(case_node.get("allowed_engine_errors"))
	print("[test] checks: %d passed, %d failed" % [passes, failures])
	if passes + failures == 0:
		print("FAIL: the case ran no checks")
		failures += 1
	if _counter.script_errors > 0:
		print("FAIL: %d SCRIPT ERROR(s) during the case" % _counter.script_errors)
		failures += _counter.script_errors
	if allowed >= 0 and _counter.engine_errors > allowed:
		print("FAIL: %d engine error(s) during the case (allowed %d)"
				% [_counter.engine_errors, allowed])
		failures += 1
	for message: String in _counter.first_messages:
		print("  error: %s" % message)
	return failures


func _on_timeout() -> void:
	_finish(1, "timeout: the case did not finish in %d s" % int(TIMEOUT_SECONDS))


func _finish(failures: int, reason: String) -> void:
	if _finished:
		return
	_finished = true
	if not reason.is_empty():
		print("FAIL: %s" % reason)
	print("[test] RESULT: %s (%d failure(s))" % ["PASS" if failures == 0 else "FAIL", failures])
	OS.remove_logger(_counter)
	quit(clampi(failures, 0, MAX_EXIT_CODE))
