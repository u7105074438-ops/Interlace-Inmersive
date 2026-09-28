# game_rules_case.gd — Cuerpo de test_game_rules: reglas de juego de la sesión tras la revisión (arranque sin registros, puertas y registro al cruzar, apaños del módulo por defecto, bloqueos por dueño, observadores con cono, cierre de las 19:00, trayecto, degradación, resumen, dormir desde la cama, continuar en frío y guardado ilegible).
# PROPIETARIO DE: nada (monta y libera la escena de juego; su carpeta de guardado se borra al final).
# ESCUCHA: nada.
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const STORAGE_FORMAT := "user://test_game_rules_%d"
const RUN_SEED := 5151
const PORTRAIT := 777
const OFFICE := "wing_3b"
const FLAT := "player_flat"
const STREET := "street"
const RECEPTION := "main_reception"
const TURNSTILES := "turnstiles"
const GATE := "turnstile_gate_2"
const ACCOUNTANT := "junior_accountant"
const GUARD := "security_guard"
const GATE_PUBLIC := Vector2(4.5, 2.6)
const GATE_FAR := Vector2(4.5, 0.5)
const GATE_INSIDE := Vector2(4.5, 4.6)
const START_WAIT := 0.6
const FRAMES_SETTLE := 3
const MAX_SCENE_WAITS := 120
const EPS_MINUTES := 1.5
const OBSERVER_WAIT := 1.2
const PROBE_CELLS: Array[float] = [2.5, 3.5, 4.5]

var _dir: String = ""
var _game: GameRoot = null
var _saved_look: Dictionary = {}


func run_case() -> void:
	allowed_engine_errors = 0
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	check(new_run(RUN_SEED), "Database loaded")
	_test_tutorial_rule()
	_game = await _spawn_game({"mode": "new", "seed": RUN_SEED, "player_name": "Rita Rules", "portrait_seed": PORTRAIT})
	await _test_quiet_start()
	await _test_door_rules()
	await _test_swipe_on_crossing()
	await _test_default_module()
	await _test_lock_owners()
	await _test_observers()
	await _test_summary_names()
	await _test_demotion_escort()
	await _test_commute()
	await _test_closing_sweep()
	await _test_sleep_by_bed()
	await _test_closing_hidden()
	await _test_continue_appearance()
	await _test_load_failure()
	_cleanup()


# ─── Montaje ──────────────────────────────────────────────────

func _spawn_game(overrides: Dictionary) -> GameRoot:
	var game: GameRoot = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	game.request_overrides = overrides
	game.epilogue_delay_override = 0.0
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.travel.instant = true
	game.time_skip.instant = true
	game.promotion.instant = true
	game.bridges.instant = true
	await _settle()
	return game


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _free_game() -> void:
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame


func _place(room_id: String, cells: Vector2) -> void:
	_game.player.global_position = _game.streamer.get_room_rect_px(room_id).position + cells * RoomBuilder.cell_px()


func _find_item(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


func _find_by_id(room_id: String, interact_id: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_id == interact_id:
			return item
	return null


## ¿Hay a la vista un aviso de esa clave? (compara el texto fijo anterior al primer argumento).
func _saw_toast(key: String) -> bool:
	var stem: String = TranslationServer.translate(key).get_slice("%", 0).strip_edges()
	var toasts: ToastStack = _game.ui.get_toasts()
	for i: int in toasts.get_toast_count():
		if toasts.get_toast_text(i).begins_with(stem) or (stem.is_empty() and not toasts.get_toast_text(i).is_empty()):
			return true
	return false


# ─── Arranque ─────────────────────────────────────────────────

func _test_tutorial_rule() -> void:
	var request: Dictionary = {"mode": "new", "intro_skipped": true, "first_run": true}
	check(GameSession.wants_tutorial(request), "tutorial: skipping the opening cinematic does not skip the tutorial")
	request["skip_intro"] = true
	check(not GameSession.wants_tutorial(request), "tutorial: the QA --skip-intro skips it")


## Informe #5/#13: el jugador empieza fuera del sensor de los tornos (nada se abre ni se registra
## antes de moverse) y a una hora con la plantilla ya llegando.
func _test_quiet_start() -> void:
	await get_tree().create_timer(START_WAIT).timeout
	check_eq(Security.get_access_log().size(), 0, "start: no card swipe is logged before the player moves")
	check(not _game.doors.is_armed(GATE), "start: the nearest gate is not armed by the spawn point")
	check(NPCDirector.get_npcs_on_floor(0).size() > 3, "start: colleagues are already on the ground floor (%d)" % NPCDirector.get_npcs_on_floor(0).size())


# ─── Puertas ──────────────────────────────────────────────────

## Informe #3: la regla del despacho propio solo abre la puerta que protege ese despacho.
func _test_door_rules() -> void:
	var initial: String = str(Database.get_balance("jugador.ocupacion_inicial"))
	for occupation_id: String in [ACCOUNTANT, GUARD]:
		var occ: OccupationData = Database.get_occupation(occupation_id)
		PlayerState.set_occupation(occupation_id, "qa")
		_game.travel.teleport_to_room(occ.office_room)
		await _settle()
		var inner_refused: int = 0
		for door: Door in _game.streamer.get_doors():
			if DatabaseSystem.get_room_base_id(door.room_b) == occ.office_room:
				check(DoorAccess.allows(door), "doors: %s's own office door opens (%s)" % [occupation_id, door.door_id])
			elif DatabaseSystem.get_room_base_id(door.room_a) == occ.office_room and not DoorAccess.meets_door(door):
				check(not DoorAccess.allows(door), "doors: %s cannot pass %s into a higher room" % [occupation_id, door.door_id])
				inner_refused += 1
		# §5.2: las llaves maestras del vigilante (master_keys_no_offices, ≤ N6) abren las salas
		# interiores de su planta; el resto de puestos sigue con alguna cerrada por encima del nivel.
		if occupation_id != GUARD:
			check(inner_refused > 0, "doors: %s has an inner door above the card that stays shut" % occupation_id)
	PlayerState.set_occupation(initial, "qa")


## Informe #4: acercarse a un torno no deja rastro; cruzarlo sí (una vez, ese torno).
func _test_swipe_on_crossing() -> void:
	_game.travel.teleport_to_room(TURNSTILES)
	_place(TURNSTILES, GATE_FAR)
	await _settle()
	var gate: Door = _game.streamer.get_door_by_id(GATE)
	var logged: int = Security.get_access_log().size()
	_place(TURNSTILES, GATE_PUBLIC)
	check(_game.doors.policy(gate, _game.player), "swipe: an R1 card opens the turnstile")
	await _settle()
	check_eq(Security.get_access_log().size(), logged, "swipe: approaching the gate logs nothing")
	_place(TURNSTILES, GATE_FAR)
	await _settle()
	check(not _game.doors.is_armed(GATE), "swipe: walking away forgets the swipe")
	check_eq(Security.get_access_log().size(), logged, "swipe: walking away logs nothing")
	_place(TURNSTILES, GATE_PUBLIC)
	_game.doors.policy(gate, _game.player)
	_place(TURNSTILES, GATE_INSIDE)
	await _settle()
	check_eq(Security.get_access_log().size(), logged + 1, "swipe: crossing logs exactly one swipe")
	var last: Dictionary = Security.get_access_log().back() if Security.get_access_log().size() > logged else {}
	check_eq(str(last.get("reader_id", "")), GATE, "swipe: the log names the gate that was crossed")


# ─── Módulo por defecto ───────────────────────────────────────

## Informe #7: ninguna indicación promete lo que no hace.
func _test_default_module() -> void:
	var unclaimed: Interactable = Interactable.new()
	unclaimed.setup("qa_unclaimed", "qa_unclaimed_type", "", {}, RoomBuilder.cell_px(), Vector2.ZERO)
	check_eq(InteractionRouter.prompt_key_for(unclaimed), "UI_INTERACT_EXAMINE", "default: an unclaimed type only promises a look")
	unclaimed.free()
	var gate_item: Interactable = _find_by_id(TURNSTILES, GATE)
	if gate_item != null and not InteractionRouter.has_handler("turnstile"):
		check_eq(InteractionRouter.prompt_key_for(gate_item), "", "default: the turnstile keeps its 'Clock in' prompt")
		var logged: int = Security.get_access_log().size()
		_place(TURNSTILES, GATE_PUBLIC)
		InteractionRouter.interact(gate_item, _game.player)
		check(_game.streamer.get_door_by_id(gate_item.interact_id).is_open(), "default: E on a turnstile swipes the card and opens it")
		check_eq(Security.get_access_log().size(), logged, "default: the manual swipe is logged only when crossing")
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	var desk: Interactable = _find_item(OFFICE, "desk")
	if desk != null and not InteractionRouter.has_handler("desk"):
		check_eq(InteractionRouter.prompt_key_for(desk), "UI_INTERACT_OWN_DESK", "default: the own desk promises the computer")
		InteractionRouter.interact(desk, _game.player)
		await _settle()
		check(_game.ui.get_top_modal() is StellarOS, "default: E on the own desk opens the computer")
		_game.ui.close_modal()
		await _settle()


## Informe #15: cerrar una ventana no desbloquea un trayecto en curso.
func _test_lock_owners() -> void:
	_game.player.set_input_locked(true, FloorTravel.LOCK_OWNER)
	var panel: Control = Control.new()
	_game.ui.open_modal(panel, true)
	_game.ui.close_modal()
	await _settle()
	check(_game.player.is_input_locked(), "locks: closing a window keeps the travel lock")
	_game.player.set_input_locked(false, FloorTravel.LOCK_OWNER)
	check(not _game.player.is_input_locked(), "locks: the travel releases its own lock")


# ─── Observadores ─────────────────────────────────────────────

## Informe #10: un compañero que mira hacia otro lado no es un observador.
func _test_observers() -> void:
	_advance_to(10 * 60)
	_game.travel.teleport_to_room(OFFICE)
	await get_tree().create_timer(OBSERVER_WAIT).timeout
	var probe: Dictionary = _observer_probe()
	check(not probe.is_empty(), "observers: an active colleague with a clear line was found")
	if probe.is_empty():
		return
	var eyes: Perception = probe["eyes"]
	var dir: Vector2 = probe["dir"]
	_game.player.global_position = probe["pos"]
	eyes.set_view(dir, true)
	check(eyes.sees_point(probe["pos"]) and _game.observers_present(), "observers: a colleague looking at the player counts")
	eyes.set_view(-dir, true)
	check(str(_game.find_observer().get("id", "")) != str(probe["id"]), "observers: the same colleague looking away does not")


## Un compañero activo y un punto transitable a su alcance, lejos del radio «a su lado», con línea.
func _observer_probe() -> Dictionary:
	var cell: float = RoomBuilder.cell_px()
	var near: float = Database.get_balance_float("salto_tiempo.radio_testigo_cercano_celdas") * cell
	for node: NPCNode in _game.npc_layer.get_nodes():
		var eyes: Perception = node.perception
		if eyes == null or not eyes.is_active():
			continue
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			for cells: float in PROBE_CELLS:
				var pos: Vector2 = _game.streamer.nearest_walkable_point(eyes.global_position + dir * cells * cell)
				var d: float = eyes.global_position.distance_to(pos)
				if pos != Vector2.INF and d > near * 1.2 and eyes.has_line_of_sight(pos) and eyes.can_notice(pos):
					return {"eyes": eyes, "dir": (pos - eyes.global_position).normalized(), "pos": pos, "id": node.npc_id}
	return {}


# ─── Resumen y degradación ────────────────────────────────────

## Informe #9: el resumen al dormir muestra nombres de deber, no ids.
func _test_summary_names() -> void:
	var duties: Array[Dictionary] = PlayerState.get_todays_duties()
	check(not duties.is_empty(), "summary: the player has duties today")
	if duties.is_empty():
		return
	var duty_id: String = str(duties[0]["id"])
	EventBus.day_summary_ready.emit({"day": GameClock.get_day(), "missed_duties": [duty_id], "completed_duties": []})
	await _settle()
	var view: DaySummary = _game.ui.get_top_modal() as DaySummary
	check(view != null, "summary: day_summary_ready shows the summary")
	if view != null:
		var shown: String = str((view.get_summary().get("missed_duties", [""]) as Array)[0])
		check(shown != duty_id and shown == str(duties[0].get("name_key", "")), "summary: the duty is shown by its name key (%s)" % shown)
		_game.ui.close_modal_control(view)
	await _settle()


## Informe #19: degradado en una sala que ya le queda vetada → Seguridad le lleva a su mesa nueva.
func _test_demotion_escort() -> void:
	var initial: String = str(Database.get_balance("jugador.ocupacion_inicial"))
	var occ: OccupationData = Database.get_occupation(ACCOUNTANT)
	PlayerState.set_occupation(ACCOUNTANT, "qa")
	_game.travel.teleport_to_room(occ.office_room)
	await _settle()
	PlayerState.set_occupation(initial, "demotion")
	await _settle()
	var forbidden: bool = BeliefNet.is_room_forbidden_for_player(occ.office_room)
	check(forbidden, "demotion: precondition — the accountants' room is above the new card")
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), OFFICE, "demotion: escorted to the new desk")


# ─── Trayecto ─────────────────────────────────────────────────

## Informe #11: de recepción a casa y de casa al trabajo con el trayecto (sin cruzar la calle a pie).
func _test_commute() -> void:
	_game.travel.teleport_to_room(RECEPTION)
	await _settle()
	var out_door: Interactable = _exit_to(RECEPTION, STREET)
	check(out_door != null, "commute: the reception has a street door")
	if out_door == null:
		return
	var dest: Dictionary = _game.travel.destinations_for(out_door)[0]
	check_eq(FloorTravel.commute_zone_for(out_door, dest), "home", "commute: the reception door offers going home")
	var before: float = GameClock.get_total_minutes()
	await _game.travel.travel_to(out_door, dest.merged({"commute": "home"}))
	await _settle()
	check_eq(PlayerState.get_room(), FLAT, "commute: home by the usual route")
	var commute: float = Database.get_balance_float("hogar.minutos_trayecto_casa")
	check_near(GameClock.get_total_minutes() - before, commute, EPS_MINUTES, "commute: it costs the commute minutes")
	var door: Interactable = null
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if (node as Interactable).interact_id == WorldBridges.COMMUTE_DOOR_ID:
			door = node as Interactable
	check(door != null and door.interact_type == FloorTravel.COMMUTE_TYPE, "commute: the flat has a 'go to work' door")
	check_eq(InteractionRouter.module_for(FloorTravel.COMMUTE_TYPE).resource_path, "res://src/world/floor_travel.gd", "commute: FloorTravel handles it")
	if door != null:
		before = GameClock.get_total_minutes()
		await _game.travel.use_commute("work")
		await _settle()
		check_eq(PlayerState.get_room(), RECEPTION, "commute: arrival inside the reception, by its street door")
		check_near(GameClock.get_total_minutes() - before, commute, EPS_MINUTES, "commute: going to work costs the same")


func _exit_to(room_id: String, target: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == "exit" and str(item.data.get("target_room", "")) == target:
			return item
	return null


# ─── Cierre de las 19:00 ──────────────────────────────────────

## Informe #1: avisos antes de las 19:00 y, a las 19:00, fuera sin un solo registro nocturno.
func _test_closing_sweep() -> void:
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	_advance_to(17 * 60 + 59)
	_game.ui.get_toasts().clear()
	_advance_to(18 * 60 + 1)
	await _settle()
	check(_saw_toast("CLOSING_WARN_EARLY"), "closing: a warning at clock-out time")
	_advance_to(18 * 60 + 59)
	await _settle()
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	var logged: int = Security.get_access_log().size()
	_advance_to(19 * 60 + 1)
	await _settle()
	check_eq(_game.streamer.get_current_floor(), Database.get_balance_int("mundo.planta_exterior"), "closing: walked out of the building at 19:00")
	check_eq(PlayerState.get_room(), STREET, "closing: standing in the street by the reception door")
	check_eq(Security.get_access_log().size(), logged, "closing: no night card swipe")
	check_near(BeliefNet.calculate_player_suspicion(), suspicion, 0.01, "closing: an honest late leaver gains no suspicion")
	check(_saw_toast("CLOSING_SWEPT"), "closing: the player is told the guard walked them out")


func _advance_to(day_minute: int) -> void:
	var left: float = float(day_minute) - GameClock.get_day_minutes()
	if left > 0.0:
		GameClock.advance_minutes(left)


## Escondido a las 19:00: se queda dentro, avisado de que ahora todo cuenta.
func _test_closing_hidden() -> void:
	_game.travel.teleport_to_room(OFFICE)
	await _settle()
	_advance_to(18 * 60 + 50)
	_game.player.set_hiding(true)
	_game.ui.get_toasts().clear()
	_advance_to(19 * 60 + 5)
	await _settle()
	check_eq(DatabaseSystem.get_room_base_id(PlayerState.get_room()), OFFICE, "closing: a hidden player stays inside")
	check(_saw_toast("CLOSING_HIDDEN"), "closing: the hidden player is told the night has begun")
	_game.player.set_hiding(false)


# ─── Dormir y continuar ───────────────────────────────────────

## Informe #2: la cama duerme y guarda; T en casa de noche también ofrece dormir.
func _test_sleep_by_bed() -> void:
	_advance_to(21 * 60)
	_game.travel.teleport_to_room(FLAT)
	await _settle()
	check_eq(_game.time_skip.check(), TimeSkip.REASON_SLEEP, "sleep: T at home at night means bed, not 'go home'")
	var bed: Interactable = _find_item(FLAT, "bed")
	check(bed != null, "sleep: the flat has a bed")
	if bed == null:
		return
	if not InteractionRouter.has_handler("bed"):
		check_eq(InteractionRouter.prompt_key_for(bed), "UI_INTERACT_SLEEP", "sleep: the bed promises sleep")
	var day: int = GameClock.get_day()
	InteractionRouter.interact(bed, _game.player)
	await _settle()
	check_eq(GameClock.get_day(), day + 1, "sleep: E on the bed ends the day")
	check(SaveSystem.run_exists(), "sleep: E on the bed saves the run")
	check(_game.ui.get_top_modal() is DaySummary, "sleep: the day summary is shown")
	while _game.ui.has_modal():
		_game.ui.close_modal()
	await _settle()
	check(not _game.player.is_input_locked(), "sleep: the player can move again once the summary is closed")
	_saved_look = _game.player.get_appearance()


## Informe #6: continuar en frío (estado del jugador vacío) devuelve el mismo aspecto.
func _test_continue_appearance() -> void:
	await _free_game()
	PlayerState.reset_for_new_run()
	_game = await _spawn_game({"mode": "load"})
	check_eq(_game.get_mode(), "load", "continue: the run loads")
	check_eq(_game.player.get_appearance(), _saved_look, "continue: the character looks as when the run was saved")
	check_eq(int(PlayerState.get_flag(Player.PORTRAIT_FLAG, 0)), PORTRAIT, "continue: the portrait seed came back from the save")


## Informe #14: un guardado ilegible no se borra en silencio.
func _test_load_failure() -> void:
	await _free_game()
	var file: FileAccess = FileAccess.open(SaveSystem.get_run_path(), FileAccess.WRITE)
	file.store_string("{ not a save")
	file.close()
	_game = await _spawn_game({"mode": "load"})
	var box: DialogBox = _game.ui.get_top_modal() as DialogBox
	check(box != null, "load failure: the player is told the save is unreadable")
	check(SaveSystem.run_exists(), "load failure: nothing was deleted")
	check_eq(_game.get_mode(), "", "load failure: no run started behind the player's back")
	if box != null:
		var failed: Array = []
		_game.load_failed.connect(func() -> void: failed.append(true))
		box.choose(0)
		await _settle()
		check_eq(failed.size(), 1, "load failure: 'Back to title' leaves for the menu")
	check(SaveSystem.run_exists(), "load failure: the damaged file is still there")
	_game = null


func _cleanup() -> void:
	for i: int in MAX_SCENE_WAITS:
		var scene: Node = get_tree().current_scene
		if scene != null and not scene is GameRoot:
			break
		await get_tree().process_frame
	var current: Node = get_tree().current_scene
	if current != null:
		current.queue_free()
	SaveSystem.delete_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.get_profile_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	GameRoot.spawn_audio = true
	MenuKit.spawn_audio = true
	InteractionRouter.reset()
