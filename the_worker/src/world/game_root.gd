# game_root.gd — Escena de juego (BUILD_NOTES §2/§14): monta mundo, interfaz y nodos de simulación, arranca o carga la partida, coloca al jugador y cierra la partida con el epílogo.
# PROPIETARIO DE: el árbol de la sesión (streamer, jugador, capa de personajes, interfaz, audio, nodos de simulación, viaje, puentes, ascensos, salto temporal) y la petición de arranque consumida.
# ESCUCHA: FloorStreamer.floor_loaded (encuadre), la salida del árbol de la raíz (cierre del proceso: recoge los renders de audio); el resto lo escuchan sus hijos (WorldBridges: game_over).
class_name GameRoot
extends Node2D

## scenes/world/game.tscn. Flujo de _ready():
##   InputSetup → GameSession.read_request() (GameLaunch + --seed/--force-rank/--skip-intro) →
##   Database.load_all_or_halt() (si falla: pantalla de errores de BootScreen y nada más) →
##   NUEVA: GameSession.begin_new_run() (preset, semilla, resets §2, población, grafo, nombre)
##   → mundo e hijos → jugador en los tornos de la PB a las 8:00 (o en la sala de formación si
##   corre el tutorial: tutorial_hook) → EventBus.run_started(semilla) (el reloj echa a andar).
##   CONTINUAR: mundo e hijos → GameSession.load_saved_run() (SaveSystem.load_run → run_loaded,
##   reparte el estado a los nodos de escena) → jugador en su piso (se guarda al dormir). Si el
##   guardado no se puede leer, NADA se borra en silencio: diálogo «volver al título» (por
##   defecto) o «empezar de cero» (confirmado; el run_started de la partida nueva lo borra).
## Hijos: World (FloorStreamer; Player bajo su capa de actores), NPCLayer, UIRoot, AudioDirector
## (salvo spawn_audio = false), CaughtHandler, DutySystem, HomeCycle, Police, NightOps, Endgame,
## FloorTravel, DoorAccess (política de puertas + registro al cruzar), WorldBridges (grupo
## item_drop_handlers), ClosingTime (cierre de las 19:00), PromotionFlow, TimeSkip. Instala
## CaughtWindow, BlackmailDialog y PhoneOverlay. GameClock.set_observer_check(observers_present).
## Esc sin ventana abierta (o «atrás» en Android) → menú de pausa: seguir, salto temporal, ascensos,
## ajustes, salir al título (con confirmación: se pierde lo no guardado desde la última noche).
## end_run(causa, final) (lo llama WorldBridges con game_over): para el mundo, deja ver la
## reacción partida.retardo_epilogo_segundos y cambia al epílogo (EpilogueScreen) → menú.
## Hook del tutorial (§13.8, otro constructor): GameRoot.tutorial_hook = func(root: GameRoot)
## -> void. Si la partida nueva lo pide (GameSession.wants_tutorial) y el hook existe, el jugador
## empieza en partida.sala_tutorial y el hook toma el control (run_started ya emitido).

signal session_ready(mode: String)
signal run_ended(cause: String, ending_id: String)
## Continuar falló y el jugador eligió volver al título (pruebas).
signal load_failed()

const GROUP := "game_root"
const PLAYER_SCENE := "res://scenes/world/player.tscn"
const MODE_NEW := "new"
const MODE_LOAD := "load"
const B_START_ROOM := "partida.sala_inicio"
const B_START_CELLS := "partida.celda_inicio"
const B_TUTORIAL_ROOM := "partida.sala_tutorial"
const B_HOME := "hogar.sala_domicilio"
const B_EPILOGUE_DELAY := "partida.retardo_epilogo_segundos"
const PAUSE_OWNER := "game_root_end"
const LOCK_OWNER := "game_root_end"
const B_NEAR_WITNESS := "salto_tiempo.radio_testigo_cercano_celdas"
const OBSERVER_NPC := "npc"
const OBSERVER_CAMERA := "camera"
const LOAD_FAIL_NEW := 1
## Salida del proceso: espera máxima y paso (ms reales) al recoger los renders de audio pendientes.
const AUDIO_DRAIN_MAX_MS := 4000
const AUDIO_DRAIN_STEP_MS := 5
const MENU_RESUME := 0
const MENU_SKIP := 1
const MENU_PROMOTIONS := 2
const MENU_SETTINGS := 3
const MENU_QUIT := 4

## Pruebas: sin AudioDirector (síntesis en hilos). También lo apaga MenuKit.spawn_audio = false (el
## interruptor de audio de las pruebas de menús, que pueden llegar a cargar esta escena).
static var spawn_audio: bool = true
## Tutorial (§13.8): func(root: GameRoot) -> void. Lo registra el constructor del tutorial.
static var tutorial_hook: Callable = Callable()

## Pruebas: se superpone a la petición de GameLaunch ({mode, seed, player_name, difficulty...}).
var request_overrides: Dictionary = {}
## Pruebas: segundos reales antes del epílogo (< 0 = balance).
var epilogue_delay_override: float = -1.0
var streamer: FloorStreamer = null
var player: Player = null
var npc_layer: NPCLayer = null
var ui: UIRoot = null
var audio: AudioDirector = null
var travel: FloorTravel = null
var doors: DoorAccess = null
var closing: ClosingTime = null
var bridges: WorldBridges = null
var promotion: PromotionFlow = null
var time_skip: TimeSkip = null
var sim_nodes: Dictionary = {}
var _request: Dictionary = {}
var _mode: String = ""
var _ended: bool = false
var _menu_open: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	get_tree().root.tree_exiting.connect(_drain_audio_on_quit)
	InputSetup.register_actions()
	TimeSkip.ensure_action()
	get_tree().quit_on_go_back = false
	_request = GameSession.read_request(request_overrides)
	if not Database.load_all_or_halt():
		_show_data_error()
		return
	_start()


func _exit_tree() -> void:
	GameClock.set_observer_check(Callable())
	GameClock.resume_by(PAUSE_OWNER)
	if not _ended:
		GameClock.pause()


## Cierre del proceso (la raíz solo sale del árbol al cerrar el juego; un cambio de escena no pasa
## por aquí): recoge los renders de audio en segundo plano (hilo musical, ambiente, efectos). Un
## trabajo del WorkerThreadPool sin recoger al salir abortaba el proceso (134) y uno en curso lo
## colgaba. Solo con las API públicas de audio; ver REQUEST al dueño de audio_director.gd.
func _drain_audio_on_quit() -> void:
	if audio == null:
		return
	var ambience: Ambience = audio.get_ambience()
	var deadline: int = Time.get_ticks_msec() + AUDIO_DRAIN_MAX_MS
	while Time.get_ticks_msec() < deadline:
		MuzakLibrary.poll()
		Ambience.poll_jobs()
		SfxBank.poll_prewarm()
		if not MuzakLibrary.is_rendering() and (ambience == null or not ambience.is_busy()) and SfxBank.is_prewarmed():
			return
		OS.delay_msec(AUDIO_DRAIN_STEP_MS)


static func find(tree: SceneTree) -> GameRoot:
	return tree.get_first_node_in_group(GROUP) as GameRoot if tree != null else null


func get_mode() -> String:
	return _mode


func get_request() -> Dictionary:
	return _request.duplicate()


func is_run_ended() -> bool:
	return _ended


# ─── Arranque ─────────────────────────────────────────────────

func _start() -> void:
	var loading: bool = str(_request.get("mode", "")) == GameSession.MODE_LOAD
	if not loading:
		GameSession.begin_new_run(_request)
	_build_world()
	_build_simulation()
	_build_flows()
	if loading and GameSession.load_saved_run():
		_mode = MODE_LOAD
		travel.teleport_to_room(str(Database.get_balance(B_HOME)))
		session_ready.emit(_mode)
	elif loading:
		_on_load_failed()
	else:
		_begin_new()


func _begin_new() -> void:
	_mode = MODE_NEW
	_place_new_run()
	EventBus.run_started.emit(GameClock.get_run_seed())
	if _tutorial_runs():
		tutorial_hook.call(self)
	session_ready.emit(_mode)


## El guardado no se pudo leer: nada se borra sin preguntar. Volver al título (opción por defecto)
## o empezar de cero con confirmación (el run_started de la partida nueva borra el archivo dañado).
func _on_load_failed() -> void:
	var options: Array = ["GAME_LOAD_FAILED_MENU", {"text_key": "GAME_LOAD_FAILED_NEW", "danger": true}]
	var choice: int = await ui.show_dialog("GAME_LOAD_FAILED_TITLE", "GAME_LOAD_FAILED_BODY", options, [], true, false)
	if choice == LOAD_FAIL_NEW:
		var confirm: Array = [{"text_key": "GAME_LOAD_FAILED_CONFIRM", "danger": true}, "UI_CANCEL"]
		if await ui.show_dialog("GAME_LOAD_FAILED_TITLE", "GAME_LOAD_FAILED_CONFIRM_BODY", confirm) == 0:
			_request["mode"] = GameSession.MODE_NEW
			GameSession.begin_new_run(_request)
			_begin_new()
			return
	load_failed.emit()
	GameLaunch.return_to_menu(get_tree())


func _place_new_run() -> void:
	if _tutorial_runs():
		travel.teleport_to_room(str(Database.get_balance(B_TUTORIAL_ROOM)))
		return
	var cells: Array = Database.get_balance(B_START_CELLS)
	travel.teleport_to_room(str(Database.get_balance(B_START_ROOM)), Vector2(float(cells[0]), float(cells[1])))


func _tutorial_runs() -> bool:
	return tutorial_hook.is_valid() and GameSession.wants_tutorial(_request)


func _build_world() -> void:
	streamer = FloorStreamer.new()
	streamer.name = "World"
	add_child(streamer)
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	streamer.get_actor_layer().add_child(player)
	streamer.set_player(player)
	npc_layer = NPCLayer.new()
	npc_layer.name = "NPCLayer"
	add_child(npc_layer)
	npc_layer.set_streamer(streamer)
	ui = UIRoot.new()
	add_child(ui)
	if spawn_audio and MenuKit.spawn_audio:
		audio = AudioDirector.new()
		audio.name = "AudioDirector"
		add_child(audio)
	travel = FloorTravel.new()
	travel.name = "FloorTravel"
	add_child(travel)
	travel.setup(streamer, player)
	streamer.floor_loaded.connect(func(_floor: int) -> void: travel.refresh_camera.call_deferred())
	doors = DoorAccess.new()
	doors.name = "DoorAccess"
	add_child(doors)
	doors.setup(streamer, player)
	GameClock.set_observer_check(observers_present)


## Nodos de escena con estado de partida (se guardan en run.json: SaveSystemNode.SCENE_GROUP).
func _build_simulation() -> void:
	for entry: Array in [["CaughtHandler", CaughtHandler], ["DutySystem", DutySystem], ["HomeCycle", HomeCycle],
			["Police", Police], ["NightOps", NightOps], ["Endgame", Endgame]]:
		var node: Node = (entry[1] as GDScript).new() as Node
		node.name = str(entry[0])
		add_child(node)
		sim_nodes[str(entry[0])] = node
	CaughtWindow.install(ui, sim_nodes["CaughtHandler"] as CaughtHandler)
	BlackmailDialog.install(ui)
	PhoneOverlay.install(ui)


func _build_flows() -> void:
	bridges = WorldBridges.new()
	bridges.name = "WorldBridges"
	add_child(bridges)
	bridges.setup(self, streamer, player, ui, travel)
	closing = ClosingTime.new()
	closing.name = "ClosingTime"
	add_child(closing)
	closing.setup(self)
	promotion = PromotionFlow.new()
	promotion.name = "PromotionFlow"
	add_child(promotion)
	promotion.setup(ui, travel)
	time_skip = TimeSkip.new()
	time_skip.name = "TimeSkip"
	add_child(time_skip)
	time_skip.setup(ui, player, travel, observers_present)
	PlacesKeeper.ensure(get_tree())
	SecurityKeeper.ensure(get_tree())


func _show_data_error() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	layer.add_child(BootScreen.build_error_screen(Database.get_load_errors()))


# ─── Observadores (§15.6, GameClock.set_observer_check) ───────

## true si alguien observa al jugador (find_observer): el veto del salto temporal.
func observers_present() -> bool:
	return not find_observer().is_empty()


## Quién le observa: {kind: "npc", id, looking: true} si un personaje activo le tiene en su cono de visión (le
## MIRA) o a su lado (salto_tiempo.radio_testigo_cercano_celdas) con línea de visión; {kind:
## "camera", id} si una cámara activa lo tiene en campo; {} si nadie. Un compañero de espaldas o
## absorto en su pantalla no observa; uno a su lado sin mirarle devuelve looking=false (con solo alcance + línea de visión, en una sala diáfana
## nunca se podía saltar desde la mesa).
## Con `act_seconds` >= 0, "catches" dice si ese testigo llegaría a flagrancia en un acto de esa
## duración (Perception.would_catch_in; una cámara siempre registra); sin él, catches = looking.
func find_observer(act_seconds: float = -1.0) -> Dictionary:
	if player == null or streamer == null:
		return {}
	var pos: Vector2 = player.global_position
	var near: float = Database.get_balance_float(B_NEAR_WITNESS) * RoomBuilder.cell_px()
	var nearby: Dictionary = {}
	if npc_layer != null:
		for node: NPCNode in npc_layer.get_nodes():
			var eyes: Perception = node.perception
			if eyes == null or not eyes.is_active():
				continue
			if eyes.sees_point(pos):
				return {"kind": OBSERVER_NPC, "id": node.npc_id, "looking": true,
						"catches": act_seconds < 0.0 or eyes.would_catch_in(pos, act_seconds)}
			if eyes.global_position.distance_to(pos) <= near and eyes.has_line_of_sight(pos):
				nearby = {"kind": OBSERVER_NPC, "id": node.npc_id, "looking": false, "catches": false}
	for cam: SecurityCamera in streamer.get_cameras():
		if cam.is_active() and cam.is_player_in_view(pos):
			return {"kind": OBSERVER_CAMERA, "id": cam.camera_id, "looking": true, "catches": true}
	# Alguien al lado pero sin mirar: vetar el salto temporal sí, pero sin decir que te ve (§12.2:
	# a lo sumo percepción parcial). "looking" distingue ambos casos para la UI.
	return nearby


## Nombre de quien le mira ("" si es una cámara o nadie).
func observer_name() -> String:
	var who: Dictionary = find_observer()
	if str(who.get("kind", "")) != OBSERVER_NPC:
		return ""
	var npc: NPCRuntime = NPCDirector.get_npc(str(who["id"]))
	return npc.name if npc != null else ""


# ─── Fin de partida (§12.7) ───────────────────────────────────

## Para el mundo, deja ver la reacción y pasa al epílogo (que vuelve al menú). Idempotente.
func end_run(cause: String, ending_id: String) -> void:
	if _ended:
		return
	_ended = true
	GameClock.pause()
	GameClock.pause_by(PAUSE_OWNER)
	if player != null:
		player.set_input_locked(true, LOCK_OWNER)
	run_ended.emit(cause, ending_id)
	var delay: float = epilogue_delay_override if epilogue_delay_override >= 0.0 else Database.get_balance_float(B_EPILOGUE_DELAY)
	if delay > 0.0:
		await get_tree().create_timer(delay, true).timeout
	if is_inside_tree():
		EpilogueScreen.show_epilogue(get_tree(), ending_id, epilogue_context(cause))


func epilogue_context(cause: String) -> Dictionary:
	return {"name": PlayerState.get_player_name(), "days": str(GameClock.get_day()), "cause": cause,
			"dominant_axis": Tracking.get_dominant_axis(), "ruin_tier": Tracking.get_ruin_tier()}


# ─── Menú de pausa y «atrás» ──────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _ended or ui == null or ui.has_modal():
		return
	if event.is_action_pressed("pause_menu") and not event.is_echo():
		get_viewport().set_input_as_handled()
		open_pause_menu()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or ui == null or _ended:
		return
	var top: Control = ui.get_top_modal()
	if top == null:
		open_pause_menu()
	elif top.has_method("request_close"):
		top.call("request_close")
	else:
		ui.close_modal()


## Menú de pausa (pausa el reloj: §15.1, el único menú que lo detiene es el de configuración).
func open_pause_menu() -> void:
	if _menu_open or ui == null:
		return
	_menu_open = true
	var offers: int = Company.get_available_promotions().size()
	var options: Array = ["PAUSE_RESUME", {"text_key": "PAUSE_TIME_SKIP", "icon": "clock"},
			{"text_key": "PAUSE_PROMOTIONS", "args": [offers], "disabled": offers == 0, "icon": "star"},
			"PAUSE_SETTINGS", {"text_key": "PAUSE_QUIT", "danger": true}]
	var index: int = await ui.show_dialog("PAUSE_TITLE", "PAUSE_BODY", options,
			[GameClock.get_day(), GameClock.get_time_string()])
	_menu_open = false
	match index:
		MENU_SKIP:
			time_skip.request_skip()
		MENU_PROMOTIONS:
			promotion.open_offer()
		MENU_SETTINGS:
			ui.open_modal(SettingsMenu.new(), true)
		MENU_QUIT:
			_confirm_quit()


func _confirm_quit() -> void:
	var options: Array = [{"text_key": "PAUSE_QUIT_CONFIRM", "danger": true}, "UI_CANCEL"]
	if await ui.show_dialog("PAUSE_QUIT_TITLE", "PAUSE_QUIT_BODY", options) == 0:
		GameLaunch.return_to_menu(get_tree())
