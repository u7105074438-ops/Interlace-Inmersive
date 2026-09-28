# tutorial_director.gd — El primer día guionizado (§13.8, PASO 46): el vídeo de bienvenida en la sala de formación (que ES el aprendizaje de movimiento), el paseo con HR hasta la mesa y las tres tareas de la primera jornada; con salto en partidas posteriores y tope de diez minutos.
# PROPIETARIO DE: el paso en curso, el tiempo activo del tutorial, las muestras de movimiento del jugador, los figurantes y los personajes retirados mientras actúan (NPCDirector.set_lod), la pausa "tutorial" del reloj y la bandera de perfil tutorial_seen al terminar.
# ESCUCHA: nada directamente (TutorialWalk escucha floor_changed; el gancho de la pantalla de formación es PlacesScenes.training_hook).

class_name TutorialDirector
extends Node

## Entrada: GameRoot.tutorial_hook = TutorialDirector.begin (lo instala Tutorial.install() desde el
## menú). GameRoot ya puso al jugador en partida.sala_tutorial y emitió run_started.
## Partes (cada una espera condiciones reales con un presupuesto de balance tutorial.*):
##   1. Vídeo (reloj en pausa "tutorial"; NPCLayer.free_running para que el edificio siga vivo sin
##      que corra la jornada): cada frase del Voss de 2011 pide una acción (mover, sigilo, agacharse,
##      esprintar, E en la pantalla) y avanza cuando el jugador la hace; si no, sigue sola.
##   2. TutorialWalk: el asistente de HR acompaña hasta la mesa (reloj en marcha).
##   3. TutorialFirstDay: correos, la idea de Claudia Reeves, la ronda de Bernard Lasker.
## Tiempo: wait_for() solo cuenta con el juego en marcha o en una ventana de trabajo (ordenador,
## mapa, móvil); no con un diálogo encima (menú de pausa, confirmaciones). La suma de presupuestos
## (total_budget_seconds) cabe en tutorial.duracion_max_segundos: el tutorial nunca pasa de diez
## minutos activos. Salto (skip): en partidas posteriores (perfil tutorial_seen) un diálogo lo ofrece;
## «siempre» fija skip_tutorial_seen (alias de skip_seen_intro). Terminar o saltar fija tutorial_seen.
## Pruebas: budget_scale, actor_speed_scale e instant (sin fundidos).

signal step_changed(step_id: String)
signal finished(skipped: bool)

const GROUP := "tutorial_director"
const PAUSE_OWNER := "tutorial"
const SETTING_SEEN := "tutorial_seen"
const SETTING_SKIP := "skip_tutorial_seen"
const SKIP_NOW := 1
const SKIP_ALWAYS := 2
const B := "tutorial."
const B_TUTORIAL_ROOM := "partida.sala_tutorial"
const B_CELL := "mundo.px_por_unidad"
const VOSS_ID := "npc_harlan_voss"
const NOTE_CATEGORY := "files"
const FILE_KEY := "TUT_VIDEO_FILE"
const SPEAKER_KEY := "TUT_VIDEO_SPEAKER"
const PRAISE_KEYS: Array[String] = ["TUT_VIDEO_PRAISE_1", "TUT_VIDEO_PRAISE_2", "TUT_VIDEO_PRAISE_3", "TUT_VIDEO_PRAISE_4"]
const MOVE_KEYS: Array[String] = ["move_up", "move_left", "move_down", "move_right"]
const TWICE_SUFFIX := " ×2"
## Frases del vídeo: acción que piden (check) y teclas que enseñan (keys / touch en móvil).
const VIDEO_STEPS: Array[Dictionary] = [
	{"id": "intro", "line": "TUT_VIDEO_INTRO"},
	{"id": "move", "line": "TUT_VIDEO_MOVE", "check": true, "keys": MOVE_KEYS, "touch": "TUT_TOUCH_MOVE"},
	{"id": "sneak", "line": "TUT_VIDEO_SNEAK", "check": true, "keys": ["sneak"], "touch": "TUT_TOUCH_SNEAK"},
	{"id": "crouch", "line": "TUT_VIDEO_CROUCH", "check": true, "keys": ["crouch"], "touch": "TUT_TOUCH_CROUCH"},
	{"id": "sprint", "line": "TUT_VIDEO_SPRINT", "check": true, "keys": MOVE_KEYS, "touch": "TUT_TOUCH_SPRINT", "twice": true},
	{"id": "interact", "line": "TUT_VIDEO_INTERACT", "check": true, "keys": ["interact"], "touch": "TUT_TOUCH_INTERACT"},
	{"id": "outro", "line": "TUT_VIDEO_OUTRO"},
]
const BUDGET_GROUPS: Array[String] = ["video.presupuesto", "guia.presupuesto", "tareas.presupuesto"]
## Esperas fijas que se suman a los presupuestos: [ruta de balance, veces] (más un elogio o un
## empujón por cada frase del vídeo que pide una acción).
const FIXED_WAITS: Array[Array] = [["retardo_inicio_segundos", 1], ["video.segundos_fin_cinta", 1], ["segundos_fundido", 4], ["guia.segundos_despedida", 1],
		["patrulla.segundos_vuelta", 1], ["patrulla.reintento_segundos", 1], ["tareas.pausa_entre_tareas", 2]]
const LOCK_TYPE := "lock_old"
const OPENS_SUFFIX := "_opens"
const B_BASIC_KEY := "operativa.cerraduras.llave_basica"

var root: GameRoot = null
var ui: Tutorial = null
var screen: TutorialScreen = null
## Pruebas: escala de presupuestos y lecturas; velocidad de los figurantes; fundidos instantáneos.
var budget_scale: float = 1.0
var actor_speed_scale: float = 1.0
var instant: bool = false
var _step: String = ""
var _ended: bool = false
var _started: bool = false
var _elapsed: float = 0.0
var _samples: Dictionary = {}
var _last_pos: Vector2 = Vector2.INF
var _acknowledged: bool = false
var _praise_i: int = 0
var _free_running: bool = false
var _notes_given: bool = false
var _pins: Array[String] = []
var _actors: Array[TutorialActor] = []
var _walk: TutorialWalk = null
var _day: TutorialFirstDay = null


## Gancho de GameRoot (partida nueva con tutorial): crea el director y arranca.
static func begin(game: GameRoot) -> void:
	var director: TutorialDirector = TutorialDirector.new()
	director.name = "TutorialDirector"
	director.root = game
	game.add_child(director)
	director.start()


static func find(tree: SceneTree) -> TutorialDirector:
	return tree.get_first_node_in_group(GROUP) as TutorialDirector if tree != null else null


## Peor caso del tutorial (s activos): presupuestos de todos los pasos + esperas fijas. Cabe en
## tutorial.duracion_max_segundos.
static func total_budget_seconds() -> float:
	var total: float = 0.0
	for group: String in BUDGET_GROUPS:
		var table: Variant = Database.get_balance(B + group)
		if table is Dictionary:
			for key: Variant in table:
				if not str(key).begins_with("_"):
					total += float(table[key])
	for wait: Array in FIXED_WAITS:
		total += Database.get_balance_float(B + str(wait[0])) * float(wait[1])
	for step: Dictionary in VIDEO_STEPS:
		if bool(step.get("check", false)):
			total += Database.get_balance_float(B + "video.segundos_elogio")
	return total


func start() -> void:
	if _started:
		return
	_started = true
	add_to_group(GROUP)
	GameClock.pause_by(PAUSE_OWNER)
	ui = Tutorial.new()
	root.add_child(ui)
	_place_player()
	_set_free_running(true)
	PlacesScenes.training_hook = _on_training_screen
	reset_samples()
	_run.call_deferred()


func _exit_tree() -> void:
	if not _ended:
		_ended = true
		_cleanup()


func _run() -> void:
	if await _offer_skip():
		return
	await _run_video()
	if _ended:
		return
	_walk = TutorialWalk.new(self)
	await _walk.run()
	if _ended:
		return
	_day = TutorialFirstDay.new(self)
	await _day.run()
	finish()


# ─── Estado público ───────────────────────────────────────────

func get_step() -> String:
	return _step


func set_step(step_id: String) -> void:
	_step = step_id
	print("[tutorial] step %s at %.1fs (%s)" % [step_id, _elapsed, GameClock.get_time_string()])
	step_changed.emit(step_id)


func is_ended() -> bool:
	return _ended


## Segundos activos de tutorial (sin diálogos encima).
func get_elapsed() -> float:
	return _elapsed


func get_walk() -> TutorialWalk:
	return _walk


func get_first_day() -> TutorialFirstDay:
	return _day


## El reloj de la jornada vuelve a correr (fin del vídeo).
func resume_clock() -> void:
	_set_free_running(false)
	GameClock.resume_by(PAUSE_OWNER)


# ─── Balance y tiempos ────────────────────────────────────────

func bal(path: String) -> Variant:
	return Database.get_balance(B + path)


func bal_f(path: String) -> float:
	return Database.get_balance_float(B + path)


## Presupuesto o espera guionizada (s), escalado para pruebas.
func budget(path: String) -> float:
	return bal_f(path) * budget_scale


func cell() -> float:
	return Database.get_balance_float(B_CELL)


## Tiempo de lectura de una frase: mínimo + por carácter, con tope.
func read_time(text: String) -> float:
	var t: float = maxf(bal_f("lectura.segundos_min"), text.length() * bal_f("lectura.segundos_por_caracter"))
	return minf(t, bal_f("lectura.segundos_max")) * budget_scale


## ¿Corre el tiempo del tutorial? No con un diálogo modal encima (pausa, confirmaciones).
func counts_time() -> bool:
	return root == null or root.ui == null or not (root.ui.get_top_modal() is DialogBox)


## Espera a que `cond` se cumpla o se agoten `seconds` de tiempo activo. true = se cumplió.
func wait_for(cond: Callable, seconds: float) -> bool:
	var left: float = seconds
	while not _ended and is_inside_tree():
		if bool(cond.call()):
			return true
		if left <= 0.0:
			return false
		await get_tree().process_frame
		if counts_time():
			left -= get_process_delta_time()
	return false


func hold(seconds: float) -> void:
	await wait_for(func() -> bool: return false, seconds)


func _process(delta: float) -> void:
	if _ended:
		return
	if counts_time():
		_elapsed += delta
	if _free_running and root.npc_layer != null:
		root.npc_layer.free_running = not root.ui.has_modal()


# ─── Muestras de movimiento del jugador (vídeo) ───────────────

func reset_samples() -> void:
	_samples = {"moved": 0.0, "sneak": 0.0, "crouch": 0.0, "sprint": 0.0}
	_last_pos = Vector2.INF


func get_samples() -> Dictionary:
	return _samples.duplicate()


func _physics_process(delta: float) -> void:
	if _ended or root == null or root.player == null:
		return
	var p: Player = root.player
	if _last_pos.is_finite():
		var step: float = p.global_position.distance_to(_last_pos)
		if step < cell():
			_samples["moved"] = float(_samples["moved"]) + step
	_last_pos = p.global_position
	var mode: String = p.movement_mode()
	if mode == Player.MODE_SNEAK:
		_samples["sneak"] = float(_samples["sneak"]) + delta
	elif mode == Player.MODE_SPRINT:
		_samples["sprint"] = float(_samples["sprint"]) + delta
	if p.is_crouching():
		_samples["crouch"] = float(_samples["crouch"]) + delta


func _check(step_id: String) -> bool:
	match step_id:
		"move":
			return float(_samples["moved"]) >= bal_f("video.celdas_mover") * cell()
		"sneak":
			return float(_samples["sneak"]) >= bal_f("video.segundos_sigilo")
		"crouch":
			return float(_samples["crouch"]) >= bal_f("video.segundos_agachado")
		"sprint":
			return float(_samples["sprint"]) >= bal_f("video.segundos_esprint")
		"interact":
			return _acknowledged
	return true


# ─── Parte 1: el vídeo de bienvenida ──────────────────────────

func _run_video() -> void:
	var voss: Dictionary = TutorialVideoFeed.young_voss_appearance()
	screen = TutorialScreen.create(root.streamer, tutorial_room(), voss)
	await hold(budget("retardo_inicio_segundos"))
	if _ended:
		return
	var npc: NPCRuntime = NPCDirector.get_npc(VOSS_ID)
	ui.show_video(voss, npc.tier if npc != null else CharacterStyle.OUTFIT_COUNT, FILE_KEY, SPEAKER_KEY)
	if screen != null:
		screen.turn_on()
	sfx("ui_notify")
	subtitle("SUB_TUT_JINGLE", screen.get_screen_rect().get_center() if screen != null else Vector2.INF)
	for step: Dictionary in VIDEO_STEPS:
		if _ended:
			return
		await _video_step(step)
	await _end_tape()


func _video_step(step: Dictionary) -> void:
	var id: String = str(step["id"])
	set_step("video_" + id)
	reset_samples()
	_acknowledged = false
	ui.set_video_mode(TutorialVideoFeed.MODE_TALK)
	var caption: String = video_line(step)
	ui.set_caption(caption)
	var limit: float = budget("video.presupuesto." + id)
	if not bool(step.get("check", false)):
		await hold(minf(read_time(Tutorial.plain(caption)), limit))
		return
	var shown_at: float = _elapsed
	var min_shown: float = budget("video.segundos_min_paso")
	var done: bool = await wait_for(func() -> bool: return _elapsed - shown_at >= min_shown and _check(id), limit)
	if _ended:
		return
	if done:
		await _praise()
	else:
		await _nudge()


## Frase del vídeo con sus teclas dibujadas (o el control táctil).
func video_line(step: Dictionary) -> String:
	var actions: Array = step.get("keys", [])
	if actions.is_empty():
		return Tutorial.line(str(step["line"]))
	var touch: bool = root.ui != null and root.ui.is_touch_mode()
	var caps: String = Tutorial.keycaps(actions, touch, str(step.get("touch", "")))
	if bool(step.get("twice", false)) and not touch:
		caps += TWICE_SUFFIX
	return Tutorial.line(str(step["line"]), [caps])


func _praise() -> void:
	ui.set_video_mode(TutorialVideoFeed.MODE_PRAISE)
	ui.set_caption(Tutorial.line(PRAISE_KEYS[_praise_i % PRAISE_KEYS.size()]))
	_praise_i += 1
	sfx("ui_confirm")
	await hold(budget("video.segundos_elogio"))


func _nudge() -> void:
	ui.set_caption(Tutorial.line("TUT_VIDEO_NUDGE"))
	await hold(budget("video.segundos_elogio"))


func _end_tape() -> void:
	set_step("video_end")
	ui.set_video_mode(TutorialVideoFeed.MODE_END)
	ui.set_caption("")
	if screen != null:
		screen.show_end()
	subtitle("SUB_TUT_TAPE_END", screen.get_screen_rect().get_center() if screen != null else Vector2.INF)
	await hold(budget("video.segundos_fin_cinta"))
	ui.hide_video()
	if screen != null:
		screen.turn_off()
	_clear_training_hook()


## E en la pantalla de formación (PlacesScenes.training_hook) mientras dura el vídeo.
func _on_training_screen(_item: Interactable, _player: Node, _ctx: Dictionary) -> void:
	if _step == "video_interact":
		_acknowledged = true
		toast("TUT_VIDEO_ACK", [], ToastStack.KIND_GOOD)
	else:
		toast("TUT_VIDEO_BUSY")


func _clear_training_hook() -> void:
	if PlacesScenes.training_hook == Callable(self, "_on_training_screen"):
		PlacesScenes.training_hook = Callable()


# ─── Salto y final ────────────────────────────────────────────

## Partidas posteriores (perfil tutorial_seen): ofrecer saltarlo. true = saltado.
func _offer_skip() -> bool:
	if not SettingsMenu.get_bool(SETTING_SEEN) or root.ui == null:
		return false
	var options: Array = ["TUT_SKIP_ATTEND", "TUT_SKIP_NOW", "TUT_SKIP_ALWAYS"]
	set_step("offer_skip")
	var choice: int = await root.ui.show_dialog("TUT_SKIP_TITLE", "TUT_SKIP_BODY", options, [], true, false)
	if _ended:
		return true
	if choice == SKIP_NOW or choice == SKIP_ALWAYS:
		await skip(choice == SKIP_ALWAYS)
		return true
	return false


## Salta el primer día: a la mesa, con lo esencial en el cuaderno (zonas restringidas y llaves).
func skip(always: bool = false) -> void:
	if _ended:
		return
	_ended = true
	set_step("skipped")
	if always:
		SettingsMenu.set_value(SETTING_SKIP, true)
	await ui.fade(true, 0.0 if instant else bal_f("segundos_fundido"))
	_cleanup()
	deliver_notes()
	place_player_at_desk()
	toast("TUT_SKIPPED")
	await ui.fade(false, 0.0 if instant else bal_f("segundos_fundido"))
	_close(true)


## Final normal (tras la despedida de la tercera parte).
func finish() -> void:
	if _ended:
		return
	_ended = true
	set_step("finished")
	_cleanup()
	_close(false)


func _cleanup() -> void:
	GameClock.resume_by(PAUSE_OWNER)
	_set_free_running(false)
	_clear_training_hook()
	release_all_actors()
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = null


func _close(skipped: bool) -> void:
	SettingsMenu.set_value(SETTING_SEEN, true)
	finished.emit(skipped)
	if ui != null and is_instance_valid(ui):
		ui.hide_speech()
		ui.hide_note()
		ui.hide_video()
		var doomed: Tutorial = ui
		get_tree().create_timer(UITheme.tune(Tutorial.B_PANEL_ANIM) + 0.1).timeout.connect(doomed.queue_free)
	queue_free()


func _set_free_running(on: bool) -> void:
	_free_running = on
	if root != null and root.npc_layer != null:
		root.npc_layer.free_running = on


# ─── Lugares ──────────────────────────────────────────────────

func tutorial_room() -> String:
	return str(Database.get_balance(B_TUTORIAL_ROOM))


func office_room() -> String:
	var occ: OccupationData = PlayerState.get_occupation()
	return occ.office_room if occ != null else ""


func office_floor() -> int:
	var room: RoomData = Database.get_room(office_room())
	return room.floor if room != null else 0


func player_floor() -> int:
	return root.streamer.get_current_floor() if root.streamer != null else 0


func player_room() -> String:
	return root.streamer.get_room_at(root.player.global_position) if root.streamer != null else ""


## Centro de la mesa del puesto del jugador (px globales; planta de la oficina cargada).
func desk_center() -> Vector2:
	var occ: OccupationData = PlayerState.get_occupation()
	var rect: Rect2 = root.streamer.get_room_rect_px(office_room())
	return rect.position + (Vector2(occ.desk_position) + Vector2(0.5, 0.5)) * cell()


## Silla del jugador: el asiento de la oficina más cercano a su mesa.
func seat_point() -> Vector2:
	var desk: Vector2 = desk_center()
	var best: Vector2 = desk
	var best_d: float = INF
	for seat: Dictionary in root.streamer.get_seats_in_room(office_room()):
		var pos: Vector2 = seat["pos"]
		if pos.distance_to(desk) < best_d:
			best_d = pos.distance_to(desk)
			best = pos
	return best


func place_player_at_desk() -> void:
	root.travel.teleport_to_room(office_room())
	root.travel.teleport(office_floor(), seat_point())
	root.player.set_facing(Vector2.UP)


func _place_player() -> void:
	var cells: Array = bal("celda_inicio")
	if cells.size() == 2:
		root.travel.teleport_to_room(tutorial_room(), Vector2(float(cells[0]), float(cells[1])))
	root.player.set_facing(Vector2.UP)


# ─── Figurantes ───────────────────────────────────────────────

## Retira el nodo real del personaje (LOD 2 fijado) y pone su figurante en `at`.
func spawn_actor(npc_id: String, at: Vector2, speed_cells: float) -> TutorialActor:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not NPCDirector.is_active(npc_id):
		return null
	if not _pins.has(npc_id):
		_pins.append(npc_id)
		NPCDirector.set_lod(npc_id, NPCRuntime.LOD_STATISTICAL)
	var node: NPCNode = root.npc_layer.get_node_for(npc_id) if root.npc_layer != null else null
	if node != null:
		node.visible = false
	var actor: TutorialActor = TutorialActor.new()
	actor.setup(npc, root.streamer, speed_cells)
	actor.speed_scale = actor_speed_scale
	root.streamer.get_actor_layer().add_child(actor)
	actor.global_position = at
	_actors.append(actor)
	return actor


## Libera el figurante y devuelve el personaje a NPCDirector (su nodo real reaparece).
func release_actor(actor: TutorialActor) -> void:
	if actor == null:
		return
	_actors.erase(actor)
	var npc_id: String = actor.npc_id
	if is_instance_valid(actor):
		actor.queue_free()
	if _pins.has(npc_id):
		_pins.erase(npc_id)
		NPCDirector.clear_lod(npc_id)


## Quita un figurante de escena sin devolver el personaje a su agenda (cambio de planta: sigue retirado).
func drop_actor(actor: TutorialActor) -> void:
	_actors.erase(actor)
	if actor != null and is_instance_valid(actor):
		actor.queue_free()


func release_all_actors() -> void:
	for actor: TutorialActor in _actors.duplicate():
		release_actor(actor)
	for npc_id: String in _pins.duplicate():
		NPCDirector.clear_lod(npc_id)
	_pins.clear()


func get_actors() -> Array[TutorialActor]:
	return _actors.duplicate()


# ─── Voz, avisos y cuaderno ───────────────────────────────────

## Tarjeta de diálogo de `npc_id` (nombre, puesto, busto) y bocadillo en su figurante o nodo.
func speak(npc_id: String, bbcode: String, fallback_name_key: String = "") -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var name_text: String = npc.name if npc != null else tr(fallback_name_key)
	var occ: OccupationData = Database.get_occupation(npc.occupation_id) if npc != null else null
	var role: String = tr(occ.name_key) if occ != null else ""
	var app: Dictionary = CharacterPainter.appearance_for_npc(npc) if npc != null else {}
	var seconds: float = read_time(Tutorial.plain(bbcode))
	ui.show_speech(name_text, role, app, bbcode, seconds * bal_f("lectura.factor_permanencia"))
	for actor: TutorialActor in _actors:
		if actor.npc_id == npc_id and is_instance_valid(actor):
			actor.say(seconds)
			return
	var node: NPCNode = root.npc_layer.get_node_for(npc_id) if root.npc_layer != null else null
	if node != null:
		node.show_emote(NPCBubble.KIND_TALK, seconds)


func toast(key: String, args: Array = [], kind: String = ToastStack.KIND_INFO) -> void:
	if root.ui != null:
		root.ui.toast(key, args, kind)


func sfx(id: String, pos: Vector2 = AudioDirector.NO_POSITION) -> void:
	if root.audio != null:
		root.audio.play_sfx(id, pos)


func subtitle(key: String, pos: Vector2) -> void:
	EventBus.subtitle_posted.emit(key, pos, SfxBank.IMPORTANCE_INFO)


## Zonas restringidas que enumera HR (balance tutorial.zonas_restringidas, las que existen).
func restricted_zones() -> Array[RoomData]:
	var out: Array[RoomData] = []
	for id: Variant in bal("zonas_restringidas"):
		var room: RoomData = Database.get_room(str(id))
		if room != null:
			out.append(room)
	return out


## Salas con una cerradura antigua que abren las llaves básicas, de la planta de la oficina hacia fuera.
func key_rooms() -> Array[RoomData]:
	var out: Array[RoomData] = []
	var key_id: String = str(Database.get_balance(B_BASIC_KEY))
	for room: RoomData in Database.get_all_rooms():
		for item: Dictionary in room.interactables:
			if str(item.get("type", "")) == LOCK_TYPE and bool(item.get(key_id + OPENS_SUFFIX, false)):
				out.append(room)
				break
	var here: int = office_floor()
	out.sort_custom(func(a: RoomData, b: RoomData) -> bool: return absi(a.floor - here) < absi(b.floor - here) or (absi(a.floor - here) == absi(b.floor - here) and a.id < b.id))
	return out.slice(0, int(bal("max_llaves")))


## «Sala (Planta N)» de cada sala, unidas con comas e «y».
func room_list(rooms: Array[RoomData]) -> String:
	var names: Array[String] = []
	for room: RoomData in rooms:
		names.append(tr("TUT_ZONE_FMT") % [tr(room.name_key), MapView.floor_name(room.floor)])
	return Tutorial.escape(join_list(names))


static func join_list(items: Array[String]) -> String:
	if items.size() <= 1:
		return "" if items.is_empty() else items[0]
	var head: Array[String] = items.slice(0, items.size() - 1)
	return ", ".join(head) + TranslationServer.translate("TUT_LIST_AND") + items[items.size() - 1]


## Lo que HR deja por escrito (zonas restringidas y cerraduras de las llaves): una vez por partida.
func deliver_notes() -> void:
	if _notes_given:
		return
	_notes_given = true
	for room: RoomData in restricted_zones():
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, "TUT_NOTE_RESTRICTED", [room.name_key, MapView.floor_name(room.floor)])
	for room: RoomData in key_rooms():
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, "TUT_NOTE_KEYS", [room.name_key, MapView.floor_name(room.floor)])
