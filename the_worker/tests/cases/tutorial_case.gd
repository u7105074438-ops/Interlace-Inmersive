# tutorial_case.gd — Cuerpo de test_tutorial: el primer día en la escena de juego real (vídeo que avanza con cada acción, paseo con HR entre plantas, correos, idea de Claudia, ronda de Lasker), el salto en partidas posteriores y el tope de diez minutos.
# PROPIETARIO DE: nada (monta y libera la escena de juego; su carpeta de guardado y perfil se borra al final).
# ESCUCHA: TutorialDirector.step_changed / finished (historial de pasos del caso).
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const STORAGE_FORMAT := "user://test_tutorial_%d"
const RUN_SEED := 4646
const SCALE := 0.2
## Tras el vídeo (que necesita tiempo real de entrada) las lecturas y esperas van más deprisa.
const FAST_SCALE := 0.08
const ACTOR_SPEED := 6.0
const STEP_WAIT := 12.0
const FRAMES_SETTLE := 3
const NOT_YET_SECONDS := 0.5
const WALK_SECONDS := 1.3
const SNEAK_SECONDS := 1.4
const CROUCH_SECONDS := 1.0
const SPRINT_SECONDS := 0.8
const MAX_MINUTES := 10.0
const SECONDS_PER_MINUTE := 60.0

var _dir_path: String = ""
var _game: GameRoot = null
var _director: TutorialDirector = null
var _steps: Array[String] = []
var _finished: Array = []
var _elapsed_at_end: float = -1.0


func run_case() -> void:
	allowed_engine_errors = 0
	_dir_path = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir_path)
	SaveSystem.delete_run()
	SettingsMenu.clear_session_cache()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	check(new_run(RUN_SEED), "Database loaded")
	SettingsMenu.set_value(TutorialDirector.SETTING_SEEN, false)
	SettingsMenu.set_value("skip_seen_intro", false)
	_test_static_rules()
	await _test_first_run()
	await _test_skip_now()
	await _test_attend_then_skip_always()
	_cleanup()


# ─── Montaje ──────────────────────────────────────────────────

func _spawn(first_run: bool) -> void:
	_steps.clear()
	_finished.clear()
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	_game.request_overrides = {"mode": "new", "seed": RUN_SEED, "player_name": "Tina Trainee", "first_run": first_run,
			"intro_skipped": true}
	_game.epilogue_delay_override = 0.0
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_game.travel.instant = true
	_game.time_skip.instant = true
	_game.promotion.instant = true
	_game.bridges.instant = true
	_director = TutorialDirector.find(get_tree())
	if _director != null:
		_director.budget_scale = SCALE
		_director.actor_speed_scale = ACTOR_SPEED
		_director.instant = true
		_steps.append(_director.get_step())
		_director.step_changed.connect(func(step: String) -> void: _steps.append(step))
		_director.finished.connect(_on_finished)
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame


func _on_finished(skipped: bool) -> void:
	_finished.append(skipped)
	_elapsed_at_end = _director.get_elapsed() if is_instance_valid(_director) else -1.0


func _free_game() -> void:
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	_game = null
	_director = null
	await get_tree().process_frame
	await get_tree().process_frame


func _cleanup() -> void:
	GameRoot.tutorial_hook = Callable()
	SaveSystem.delete_run()
	for file: String in DirAccess.get_files_at(_dir_path):
		DirAccess.remove_absolute(_dir_path.path_join(file))
	DirAccess.remove_absolute(_dir_path)


## Espera a que el historial de pasos incluya `step` (true si llegó a tiempo).
func _wait_step(step: String, timeout: float = STEP_WAIT) -> bool:
	var left: float = timeout
	while not _steps.has(step) and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
	return _steps.has(step)


func _hold_input(dir: Vector2, sprint: bool, seconds: float) -> void:
	_game.player.set_virtual_input(dir, sprint)
	await get_tree().create_timer(seconds).timeout
	_game.player.set_virtual_input(Vector2.ZERO, false)


func _last_step() -> String:
	return _steps[_steps.size() - 1] if not _steps.is_empty() else ""


# ─── Reglas estáticas ─────────────────────────────────────────

func _test_static_rules() -> void:
	GameRoot.tutorial_hook = Callable()
	Tutorial.install()
	check(GameRoot.tutorial_hook.is_valid() and Tutorial.is_installed(), "install: the menu hook registers the tutorial on GameRoot")
	var total: float = TutorialDirector.total_budget_seconds()
	var cap: float = Database.get_balance_float("tutorial.duracion_max_segundos")
	check(total > 0.0 and total <= cap, "duration: worst case of every step %.0fs fits in %.0fs" % [total, cap])
	check(cap <= MAX_MINUTES * SECONDS_PER_MINUTE, "duration: the cap is at most ten real minutes")
	for id: Variant in Database.get_balance("tutorial.zonas_restringidas"):
		check(Database.get_room(str(id)) != null, "zones: restricted room '%s' exists" % str(id))
	var npc: String = TutorialWalk.pick_guide()
	check(not npc.is_empty() and not NPCDirector.get_npc(npc).is_named, "guide: a generated HR assistant walks the player (%s)" % npc)
	check(Tutorial.plain(Tutorial.keycaps(["interact"])).strip_edges() == ContextPrompt.key_text("interact"), "keycaps: the interact key is drawn as a key")
	var later: Dictionary = {"mode": "new", "first_run": false}
	check(GameSession.wants_tutorial(later), "rules: later runs still get the induction unless the player skips seen content")


# ─── Primera partida ──────────────────────────────────────────

func _test_first_run() -> void:
	await _spawn(true)
	check(_director != null, "first run: the tutorial hook starts the director")
	if _director == null:
		await _free_game()
		return
	check_eq(PlayerState.get_room(), "training_room", "first run: the new hire starts in the P1 training room")
	check(GameClock.is_paused_by(TutorialDirector.PAUSE_OWNER), "video: the work clock waits while the welcome video plays")
	check(_game.npc_layer.free_running, "video: the building keeps moving while the clock waits")
	await _test_video()
	_director.budget_scale = FAST_SCALE
	await _test_walk()
	await _test_emails()
	await _test_idea()
	await _test_patrol()
	await _test_first_run_end()
	await _free_game()


func _test_video() -> void:
	check(await _wait_step("video_move"), "video: after the intro the MOVE line waits for the player")
	check(_director.ui.is_video_visible() and _director.ui.get_caption_text().contains(ContextPrompt.key_text("move_up")),
			"video: the caption on screen shows the movement keys")
	await get_tree().create_timer(NOT_YET_SECONDS).timeout
	check_eq(_last_step(), "video_move", "video: standing still does not advance the video")
	await _hold_input(Vector2.LEFT, false, WALK_SECONDS)
	check(await _wait_step("video_sneak"), "video: walking three cells advances to the sneak line")
	await _hold_input(Vector2.RIGHT, false, WALK_SECONDS)
	check_eq(_last_step(), "video_sneak", "video: plain walking does not count as sneaking")
	_game.player.set_sneak_held(true)
	await _hold_input(Vector2.LEFT, false, SNEAK_SECONDS)
	_game.player.set_sneak_held(false)
	check(await _wait_step("video_crouch"), "video: sneaking advances to the crouch line")
	_game.player.set_crouching(true)
	await get_tree().create_timer(CROUCH_SECONDS).timeout
	_game.player.set_crouching(false)
	check(await _wait_step("video_sprint"), "video: crouching advances to the sprint line")
	await _hold_input(Vector2.DOWN, true, SPRINT_SECONDS)
	check(await _wait_step("video_interact"), "video: sprinting advances to the interact line")
	var screen: Interactable = _find_item(_director.tutorial_room(), "training_screen")
	check(screen != null, "video: the training screen is an interactable of the room")
	if screen != null:
		await InteractionRouter.interact(screen, _game.player)
	check(await _wait_step("video_outro"), "video: E at the screen confirms the viewing and moves on")
	check(await _wait_step("walk_hello"), "video: the tape ends and HR arrives")
	check(not GameClock.is_paused_by(TutorialDirector.PAUSE_OWNER) and not _game.npc_layer.free_running,
			"walk: the work clock runs again once the video is over")
	check(not PlacesScenes.training_hook.is_valid(), "video: the training screen gets its normal behaviour back")


# ─── Paseo con HR ─────────────────────────────────────────────

func _test_walk() -> void:
	var walk: TutorialWalk = _director.get_walk()
	check(walk != null and walk.guide != null, "walk: the HR assistant is on stage")
	if walk == null or walk.guide == null:
		return
	check_eq(NPCDirector.get_lod(walk.guide_id), NPCRuntime.LOD_STATISTICAL, "walk: the guide's real node steps aside while the actor plays him")
	check(await _wait_step("walk_card"), "walk: the guide explains the access card")
	var far: Vector2 = _game.streamer.get_room_rect_px(_director.tutorial_room()).end - Vector2.ONE * RoomBuilder.cell_px()
	_game.player.global_position = _game.streamer.nearest_walkable_point(far)
	await get_tree().create_timer(NOT_YET_SECONDS).timeout
	check(walk.guide.is_waiting() or not walk.guide.is_moving(), "walk: the guide waits when the player lags behind")
	check(await _wait_step("walk_elevator", STEP_WAIT * 2.0), "walk: the guide reaches the elevator line")
	await get_tree().create_timer(NOT_YET_SECONDS).timeout
	check_eq(_last_step(), "walk_elevator", "walk: the elevator line waits for the player to go up")
	_game.travel.teleport_to_room(_director.office_room())
	check(await _wait_step("walk_clockin"), "walk: reaching the office floor continues the walk there")
	await get_tree().process_frame
	check(walk.guide != null and is_instance_valid(walk.guide), "walk: the guide rode up and reappears next to the player")
	_game.player.global_position = walk.desk_side_point()
	check(await _wait_step("walk_restricted", STEP_WAIT * 2.0), "walk: the guide lists the restricted areas")
	check(_count_notes("TUT_NOTE_RESTRICTED") == _director.restricted_zones().size(), "walk: every restricted area lands in the notebook")
	check(_count_notes("TUT_NOTE_KEYS") > 0, "walk: the rooms the basic keys open land in the notebook")
	check(await _wait_step("walk_desk", STEP_WAIT * 2.0), "walk: the walk ends at the player's desk")
	check(await _wait_step("day_emails", STEP_WAIT * 2.0), "walk: the guide says goodbye and the first day starts")
	check(_director.get_actors().is_empty(), "walk: the guide goes back to HR (the real character returns to his agenda)")


func _count_notes(key: String) -> int:
	var n: int = 0
	for entry: Dictionary in PlayerState.get_notebook_entries():
		if str(entry.get("text_key", "")) == key:
			n += 1
	return n


func _find_item(room_id: String, interact_type: String) -> Interactable:
	for item: Interactable in _game.streamer.get_interactables_in_room(room_id):
		if item.interact_type == interact_type:
			return item
	return null


# ─── Primera jornada ──────────────────────────────────────────

func _test_emails() -> void:
	var day: TutorialFirstDay = _director.get_first_day()
	check(day != null and _director.ui.is_note_visible(), "day: the first-day note appears with its three tasks")
	var duty_id: String = day.email_duty() if day != null else ""
	check(not duty_id.is_empty(), "emails: the email duty of the day is found")
	var duties: DutySystem = _game.sim_nodes["DutySystem"] as DutySystem
	for i: int in 2:
		duties.submit_unit(duty_id, int(duties.get_unit_content(duty_id).get("correct_reply", -1)))
	await get_tree().process_frame
	check(_director.ui.get_task_text(0).contains("2/3") and _last_step() == "day_emails", "emails: two answers update the note (2/3) and wait for the third")
	duties.submit_unit(duty_id, int(duties.get_unit_content(duty_id).get("correct_reply", -1)))
	check(await _wait_step("day_idea"), "emails: the third answered email completes the task")
	check_eq(_director.ui.get_task_state(0), Tutorial.STATE_DONE, "emails: the task is struck on the note")


func _test_idea() -> void:
	var owner: String = str(Database.get_balance("tutorial.tareas.idea_npc"))
	await _stay_near(owner, func() -> bool: return _steps.has("day_idea_watch"))
	check(_steps.has("day_idea_watch"), "idea: being close to Claudia Reeves makes her have the idea")
	check(not IdeaPool.get_ideas_by_owner(owner).is_empty(), "idea: Claudia Reeves really owns a new idea (IdeaPool)")
	var day: TutorialFirstDay = _director.get_first_day()
	var confidant: String = day.get_confidant() if day != null else ""
	check(not confidant.is_empty(), "idea: she tells it to a colleague out loud (%s)" % confidant)
	var told: bool = false
	for idea: Idea in IdeaPool.get_ideas_by_owner(owner):
		told = told or idea.known_by.has(confidant)
	check(told, "idea: the colleague now knows the idea (a real overhearing window)")
	await _stay_near(owner, func() -> bool: return _steps.has("day_hide"))
	check(_steps.has("day_hide"), "idea: watching her for a few seconds completes the task")
	check(_count_notes("TUT_NOTE_IDEA") == 1, "idea: the sighting is written in the notebook")


## Mantiene al jugador junto al nodo de `npc_id` hasta que `done` o el límite.
func _stay_near(npc_id: String, done: Callable) -> void:
	var left: float = STEP_WAIT
	while not bool(done.call()) and left > 0.0:
		var node: NPCNode = _game.npc_layer.get_node_for(npc_id)
		if node != null:
			_game.player.global_position = _game.streamer.nearest_walkable_point(node.get_visual_position() + Vector2(0.0, RoomBuilder.cell_px()))
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()


func _test_patrol() -> void:
	var day: TutorialFirstDay = _director.get_first_day()
	var bernard: TutorialActor = day.bernard if day != null else null
	check(bernard != null and bernard.perception != null, "patrol: Bernard Lasker walks his round with a real vision cone")
	if bernard == null:
		return
	check_eq(NPCDirector.get_lod(bernard.npc_id), NPCRuntime.LOD_STATISTICAL, "patrol: his real node steps aside during the scripted round")
	await _be_spotted(day)
	check(day.get_patrol_outcomes().has(TutorialFirstDay.OUT_SPOTTED), "patrol: standing in his way gets you spotted (and another round)")
	check_eq(_last_step(), "day_hide", "patrol: being spotted does not complete the task")
	var spot: HidingSpot = day.hiding_spot()
	check(spot != null, "patrol: the supply closet of wing 3B is the hiding spot")
	if spot != null:
		_game.player.global_position = spot.global_position
		_game.player.set_hiding(true)
	check(await _wait_step("day_done", STEP_WAIT * 2.0), "patrol: hidden in the closet while he passes completes the task")
	check(day.get_patrol_outcomes().has(TutorialFirstDay.OUT_HIDDEN), "patrol: the round that passed records the player as hidden")
	_game.player.set_hiding(false)


## Se planta delante del jefe (en su camino, dentro de su cono) hasta que la ronda le ve.
func _be_spotted(day: TutorialFirstDay) -> void:
	var left: float = STEP_WAIT * 2.0
	while not day.get_patrol_outcomes().has(TutorialFirstDay.OUT_SPOTTED) and left > 0.0 and is_instance_valid(day.bernard):
		var b: TutorialActor = day.bernard
		var ahead: Vector2 = b.global_position + b.perception.get_view_direction() * RoomBuilder.cell_px() * 2.0
		_game.player.global_position = _game.streamer.nearest_walkable_point(ahead)
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()


func _test_first_run_end() -> void:
	var wait_left: float = STEP_WAIT
	while _finished.is_empty() and wait_left > 0.0:
		await get_tree().process_frame
		wait_left -= get_process_delta_time()
	check_eq(_finished, [false], "end: the tutorial finishes on its own after the three tasks")
	check(SettingsMenu.get_bool(TutorialDirector.SETTING_SEEN), "end: the profile remembers the induction was seen")
	check(_elapsed_at_end > 0.0 and _elapsed_at_end <= TutorialDirector.total_budget_seconds() * SCALE,
			"end: the active time %.1fs stays inside the scaled cap" % _elapsed_at_end)
	check(not GameClock.is_paused_by(TutorialDirector.PAUSE_OWNER), "end: no tutorial pause is left on the clock")
	await get_tree().process_frame
	check(TutorialDirector.find(get_tree()) == null, "end: the director leaves the scene")
	var bernard: String = str(Database.get_balance("tutorial.patrulla.npc"))
	check(NPCDirector.get_lod(bernard) != NPCRuntime.LOD_STATISTICAL, "end: Bernard Lasker is back to his own agenda")


# ─── Partidas posteriores ─────────────────────────────────────

func _test_skip_now() -> void:
	await _spawn(false)
	check(_director != null, "skip: a later run still starts the induction (skip_seen_intro off)")
	if _director == null:
		await _free_game()
		return
	var box: DialogBox = await _skip_dialog()
	check(box != null, "skip: later runs offer to skip the induction")
	if box != null:
		box.choose(TutorialDirector.SKIP_NOW)
	var left: float = STEP_WAIT
	while _finished.is_empty() and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
	check_eq(_finished, [true], "skip: choosing skip ends the tutorial as skipped")
	check_eq(_game.streamer.get_room_at(_game.player.global_position), _director_office(), "skip: the player lands at their desk in wing 3B")
	check(_count_notes("TUT_NOTE_RESTRICTED") > 0, "skip: the restricted areas still reach the notebook")
	check(SettingsMenu.get_bool(TutorialDirector.SETTING_SEEN), "skip: the profile keeps tutorial_seen")
	check(not SettingsMenu.get_bool(TutorialDirector.SETTING_SKIP), "skip: skipping once does not turn on 'skip seen content'")
	check(not GameClock.is_paused_by(TutorialDirector.PAUSE_OWNER), "skip: the clock runs after skipping")
	await _free_game()


func _test_attend_then_skip_always() -> void:
	await _spawn(false)
	var box: DialogBox = await _skip_dialog()
	check(box != null, "attend: the offer appears again")
	if box == null or _director == null:
		await _free_game()
		return
	box.choose(0)
	check(await _wait_step("video_intro"), "attend: choosing to attend plays the welcome video")
	await _director.skip(true)
	check_eq(_finished, [true], "skip always: skipping from inside the induction ends it")
	check(SettingsMenu.get_bool(TutorialDirector.SETTING_SKIP) and SettingsMenu.get_bool("skip_seen_intro"),
			"skip always: the profile flag skip_tutorial_seen is set (alias of skip_seen_intro)")
	check(not GameSession.wants_tutorial({"mode": "new", "first_run": false}), "skip always: later runs no longer start the induction")
	check(GameSession.wants_tutorial({"mode": "new", "first_run": true}), "skip always: a first run would still get it")
	await _free_game()


func _skip_dialog() -> DialogBox:
	var left: float = STEP_WAIT
	while left > 0.0:
		var top: Control = _game.ui.get_top_modal()
		if top is DialogBox:
			return top as DialogBox
		await get_tree().process_frame
		left -= get_process_delta_time()
	return null


func _director_office() -> String:
	var occ: OccupationData = PlayerState.get_occupation()
	return occ.office_room if occ != null else ""
