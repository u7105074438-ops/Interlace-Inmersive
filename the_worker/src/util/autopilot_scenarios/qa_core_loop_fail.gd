# qa_core_loop_fail.gd (escenario QA) — El jugador que nunca va a trabajar (§4.4, §6.1, §6.5): se queda en casa, salta las franjas con T y duerme, jornada tras jornada, hasta el fin de partida o la jornada 10. Registra salario, comidas, escalera de fallos (aviso → descenso a R0 → expulsión) e inanición.
# PROPIETARIO DE: nada.
# ESCUCHA: EventBus (registro).
extends Node

## tools/screenshot.sh /tmp/qa_fail qa_core_loop_fail
## Variante: --force-rank=0 empieza como becario eterno (fracasar en R0 = expulsión definitiva).
## Capturas: qa_fail_dN_summary por jornada y qa_fail_end.

const TAG := "[qa_core_loop_fail]"
const MAX_DAYS := 10
const SHORT_FRAMES := 8
const WAIT_TIMEOUT := 20.0

var _pilot: Autopilot = null
var _game: GameRoot = null
var _over: String = ""


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("Idle Tester", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		print("%s FAIL game did not start" % TAG)
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	EventBus.duty_failed.connect(func(id: String, c: String) -> void: _log("duty_failed %s -> %s" % [id, c]))
	EventBus.occupation_changed.connect(func(a: String, b: String, r: String) -> void: _log("occupation %s -> %s (%s)" % [a, b, r]))
	EventBus.money_changed.connect(func(a: int, b: int, r: String) -> void: _log("money %d->%d %s" % [a, b, r]))
	EventBus.notebook_entry_added.connect(func(c: String, k: String, a: Array) -> void:
		if c != "contacts":
			_log("note %s %s" % [k, str(a)]))
	EventBus.game_over.connect(func(c: String, e: String, _s: Dictionary) -> void:
		_over = c
		_log("GAME OVER cause=%s ending=%s" % [c, e]))
	_game.travel.teleport_to_room("player_flat")
	await pilot.frames(SHORT_FRAMES)
	for i: int in MAX_DAYS:
		if not _over.is_empty():
			break
		await _idle_day()
	await pilot.seconds(3.0)
	await pilot.shot("qa_fail_end")
	print("%s RESULT days=%d over='%s' occupation=%s money=%d rep=%.1f" % [TAG, GameClock.get_day(), _over,
			PlayerState.get_occupation_id(), PlayerState.get_money(), PlayerState.get_reputation()])
	if _over.is_empty():
		print("%s FAIL %d days without ever working and no game over (§4.4 incumplimiento reiterado)" % [TAG, MAX_DAYS])


func _idle_day() -> void:
	var day: int = GameClock.get_day()
	_log("morning: occ=%s money=%d rep=%.1f" % [PlayerState.get_occupation_id(), PlayerState.get_money(), PlayerState.get_reputation()])
	for i: int in 8:
		if _game.time_skip.check() != "" or not _over.is_empty():
			break
		await _game.time_skip.skip_now()
		await _pilot.frames(SHORT_FRAMES)
	if not _over.is_empty():
		return
	_log("evening check=%s" % _game.time_skip.check())
	var hc: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle
	var result: Dictionary = hc.sleep()
	await _pilot.seconds(0.6)
	await _pilot.shot("qa_fail_d%d_summary" % day)
	while _game.ui.has_modal() and _over.is_empty():
		_game.ui.close_modal()
		await _pilot.frames(2)
	_log("slept ok=%s reason=%s hungry=%d" % [str(result.get("ok")), str(result.get("reason", "")), hc.get_hungry_days()])


func _log(text: String) -> void:
	print("%s d%d %s %s" % [TAG, GameClock.get_day(), GameClock.get_time_string(), text])
