# npcs.gd (escenario) — Capturas de los personajes vivos: ala 3B con conos e indicador, pasillo a la hora de comer, cafetería llena, bombilla de idea, los cuatro estados del indicador (normal y alto contraste), flagrancia y ficha rápida.
# PROPIETARIO DE: los nodos temporales del escenario (planta, jugador, capa de personajes, cámara, interfaz, leyenda).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_npcs npcs
## Partida nueva (semilla fija), reloj parado y fijado a mano; la capa corre libre (free_running).
## Capturas: npcs_wing_3b_calm (10:20, sentados, conos en reposo), npcs_wing_3b (forzando el cajón
## del jefe: indicador en progreso), npcs_flagrant (la misma escena sin trucos: quien decide
## denunciar se queda mirando hasta la flagrancia), npcs_corridor_lunch (13:00, colas hacia el
## ascensor), npcs_cafeteria (13:30, llena, sentados A la mesa), npcs_idea (bombilla sobre su
## dueña), npcs_indicator_states (cuatro estados normal + alto contraste), npcs_card (ficha),
## npcs_cones_debug (F1), npcs_pantry_chat (corrillos), npcs_phone (pantalla de móvil con
## indicador y ficha). Imprime "[perf]" (llamadas de dibujo totales y las de los personajes).

const SEED := 12345
const WING := "wing_3b"
const CORRIDOR := "corridors_low@3"
const CAFETERIA := "cafeteria"
const PANTRY := "p3_pantry"
const PANTRY_ZOOM := 1.9
const DRAWER := "lasker_drawer"
const IDEA_NPC := "npc_claudia_reeves"
const CARD_NPC := "npc_debbie_foyle"
const LIFECYCLE: Array[String] = ["GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet",
	"Security", "Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem"]
const WING_ZOOM := 1.3
const CORRIDOR_ZOOM := 1.15
const CAFE_ZOOM := 0.95
const CLOSE_ZOOM := 2.2
const PHONE_WINDOW := Vector2i(1170, 540)
const SETTLE_FRAMES := 8
const PERF_FRAMES := 30
const WAIT_LIMIT_S := 14.0

var _streamer: FloorStreamer = null
var _layer: NPCLayer = null
var _player: Player = null
var _cam: Camera2D = null
var _ui: UIRoot = null
var _cell: float = 48.0


func run(pilot: Autopilot) -> void:
	_new_run()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	_build_world()
	await _wing_shot(pilot)
	await _flagrant_shot(pilot)
	await _idea_shot(pilot)
	await _card_shot(pilot)
	await _debug_cones_shot(pilot)
	await _legend_shot(pilot)
	await _corridor_lunch_shot(pilot)
	await _cafeteria_shot(pilot)
	await _pantry_shot(pilot)
	await _phone_shot(pilot)


# ─── Montaje ──────────────────────────────────────────────────

func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(SEED)
	for system_name: String in LIFECYCLE:
		var node: Node = get_tree().root.get_node_or_null(NodePath(system_name))
		if node == null:
			continue
		if node.has_method("reset_for_new_run"):
			node.call("reset_for_new_run")
		if system_name == "GameClock":
			GameClock.set_run_seed(SEED)
		elif system_name == "NPCDirector":
			NPCDirector.generate_population()
		elif system_name == "SocialGraph" and node.has_method("build_initial_graph"):
			node.call("build_initial_graph")
	_cell = Database.get_balance_float("mundo.px_por_unidad")


func _set_time(hour: int, minute: int, old_band: String, new_band: String) -> void:
	GameClock.set_time(1, hour, minute)
	EventBus.time_band_changed.emit(old_band, new_band)


func _build_world() -> void:
	_set_time(10, 20, "arrival", "work_morning")
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(3)
	_player = (load("res://scenes/world/player.tscn") as PackedScene).instantiate() as Player
	_player.with_camera = false
	_streamer.get_actor_layer().add_child(_player)
	_streamer.set_player(_player)
	_place_player(WING, Vector2(7.0, 11.6))
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_layer = NPCLayer.new()
	_layer.free_running = true
	add_child(_layer)
	_layer.set_streamer(_streamer)
	_ui = UIRoot.new()
	add_child(_ui)


## Jugador en `cells` (celdas desde la esquina superior izquierda de la sala).
func _place_player(room_id: String, cells: Vector2) -> void:
	_player.global_position = _streamer.get_room_rect_px(room_id).position + cells * _cell
	_player.velocity = Vector2.ZERO


func _frame_on(point: Vector2, zoom: float) -> void:
	_cam.position = point
	_cam.zoom = Vector2(zoom, zoom)


## Fotograma completo (render por software en QA) y, aparte, la CPU de la capa de personajes.
func _perf(pilot: Autopilot, label: String) -> void:
	await pilot.frames(4)
	var start: int = Time.get_ticks_usec()
	var layer_usec: int = 0
	for i: int in PERF_FRAMES:
		await pilot.frames(1)
		layer_usec += _layer.last_advance_usec
	var ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / PERF_FRAMES
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	for node: NPCNode in _layer.get_nodes():
		node.visible = false
	await pilot.frames(2)
	var without: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	for node: NPCNode in _layer.get_nodes():
		node.visible = true
	print("[perf] %s nodes=%d draws=%d (characters %d) frame_ms=%.1f layer_cpu_ms=%.2f poses=%d" % [label,
			_layer.get_nodes().size(), draws, draws - without, ms, float(layer_usec) / 1000.0 / PERF_FRAMES,
			CharacterPainter.cached_pose_count()])


## Espera a que algún observador tenga el contador en [lo, hi] con estado `state` (o agota el plazo).
func _wait_for_state(pilot: Autopilot, state: int, lo: float, hi: float) -> NPCNode:
	var waited: float = 0.0
	while waited < WAIT_LIMIT_S:
		for node: NPCNode in _layer.get_nodes():
			var p: Perception = node.perception
			if p != null and p.get_state() == state and p.get_counter() >= lo and p.get_counter() <= hi:
				return node
		await pilot.frames(1)
		waited += get_physics_process_delta_time()
	return null


# ─── Capturas ─────────────────────────────────────────────────

## 10:20 en el ala 3B: todos en su puesto, conos a la vista y el jugador forzando el cajón del
## jefe: un indicador en progreso (amarillo) sobre quien empieza a verle.
func _wing_shot(pilot: Autopilot) -> void:
	_frame_on(_streamer.get_room_rect_px(WING).get_center() + Vector2(0.0, _cell * 0.5), WING_ZOOM)
	await pilot.frames(SETTLE_FRAMES * 3)
	await _perf(pilot, "wing_3b")
	await pilot.shot("npcs_wing_3b_calm")
	_stand_at_drawer()
	_player.begin_act("drawer_forced", 0.0)
	var watcher: NPCNode = await _wait_for_state(pilot, Perception.STATE_PROGRESS, 0.16, 0.36)
	print("[npcs] progress watcher: %s" % (watcher.npc_id if watcher != null else "none"))
	await pilot.shot("npcs_wing_3b")


func _stand_at_drawer() -> void:
	for item: Interactable in _streamer.get_interactables_in_room(WING):
		if item.interact_id == DRAWER:
			_player.global_position = item.global_position + Vector2(_cell * 1.1, _cell * 0.35)
			_player.set_facing(Vector2.LEFT)


## Sigue el acto hasta la flagrancia: círculo rojo con «!» y rayos de alarma, el testigo señala.
## Quien decide denunciar al verle de reojo no se va mientras le vigila (NPCNode aplaza el recado).
func _flagrant_shot(pilot: Autopilot) -> void:
	var catcher: NPCNode = await _wait_for_state(pilot, Perception.STATE_FLAGRANT, 0.0, 1.0)
	print("[npcs] flagrant by: %s" % (catcher.npc_id if catcher != null else "none"))
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("npcs_flagrant")
	_player.end_act()
	var ui_modal: bool = _ui.has_modal()
	if ui_modal:
		_ui.close_modal()
	_reset_perception()


func _reset_perception() -> void:
	for node: NPCNode in _layer.get_nodes():
		node.perception.reset_contact()
	_place_player(WING, Vector2(7.0, 11.6))
	_player.play_anim("")


## Bombilla de idea: la trepa acaba de tener una.
func _idea_shot(pilot: Autopilot) -> void:
	IdeaPool.generate_for_npc(IDEA_NPC)
	_layer.sync_now()
	var node: NPCNode = _layer.get_node_for(IDEA_NPC)
	await pilot.frames(SETTLE_FRAMES * 2)
	if node != null:
		_frame_on(node.get_visual_position() + Vector2(0.0, -_cell * 0.8), CLOSE_ZOOM)
	await pilot.frames(SETTLE_FRAMES * 2)
	await pilot.shot("npcs_idea")


## Ficha rápida (§13.7) de la cotilla.
func _card_shot(pilot: Autopilot) -> void:
	_frame_on(_streamer.get_room_rect_px(WING).get_center(), WING_ZOOM)
	await pilot.frames(SETTLE_FRAMES)
	_layer.open_card(CARD_NPC)
	await pilot.frames(SETTLE_FRAMES * 2)
	await pilot.shot("npcs_card")
	_layer.close_card()


## Conos de depuración (F1): todos, más marcados.
func _debug_cones_shot(pilot: Autopilot) -> void:
	DebugPanel.cones_visible = true
	for node: NPCNode in _layer.get_nodes():
		node.set_debug_cones(true)
	await pilot.frames(SETTLE_FRAMES * 3)
	await pilot.shot("npcs_cones_debug")
	DebugPanel.cones_visible = false
	for node: NPCNode in _layer.get_nodes():
		node.set_debug_cones(false)


## Los cuatro estados del indicador sobre cuatro personajes, en normal y alto contraste.
func _legend_shot(pilot: Autopilot) -> void:
	var legend: IndicatorLegend = IndicatorLegend.new()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = UIRoot.LAYER + 1
	add_child(layer)
	layer.add_child(legend)
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("npcs_indicator_states")
	layer.queue_free()


## 13:00: el ala se vacía camino del ascensor por el pasillo.
func _corridor_lunch_shot(pilot: Autopilot) -> void:
	_place_player(CORRIDOR, Vector2(9.0, 2.2))
	_set_time(13, 0, "work_morning", "lunch")
	EventBus.hour_passed.emit(13, 1)
	_layer.think_all()
	var rect: Rect2 = _streamer.get_room_rect_px(CORRIDOR)
	_frame_on(Vector2(rect.position.x + _cell * 14.0, rect.get_center().y + _cell * 1.5), CORRIDOR_ZOOM)
	await pilot.seconds(4.2)
	await pilot.shot("npcs_corridor_lunch")


## 13:30 en la cafetería (PB): mesas llenas, corrillos de pie.
func _cafeteria_shot(pilot: Autopilot) -> void:
	_set_time(13, 30, "work_morning", "lunch")
	_streamer.load_floor(0)
	_place_player(CAFETERIA, Vector2(15.0, 20.0))
	await pilot.frames(3)
	EventBus.room_entered.emit(CAFETERIA, true)
	_layer.sync_now()
	_frame_on(_streamer.get_room_rect_px(CAFETERIA).get_center() + Vector2(0.0, _cell), CAFE_ZOOM)
	await pilot.frames(SETTLE_FRAMES * 3)
	await _perf(pilot, "cafeteria")
	await pilot.shot("npcs_cafeteria")


## 10:35, pausa del café en el office de la planta 3: corrillos de pie (tics: la cotilla se
## inclina hacia quien le habla, el chivato mira a los lados).
func _pantry_shot(pilot: Autopilot) -> void:
	_set_time(10, 35, "arrival", "work_morning")
	_streamer.load_floor(3)
	_place_player(WING, Vector2(17.0, 4.0))
	EventBus.room_entered.emit(WING, true)
	_layer.sync_now()
	_frame_on(_streamer.get_room_rect_px(PANTRY).get_center() + Vector2(-_cell * 1.5, _cell * 0.5), PANTRY_ZOOM)
	await pilot.frames(SETTLE_FRAMES * 4)
	await pilot.shot("npcs_pantry_chat")


## Móvil: ventana apaisada pequeña (interfaz táctil), ala 3B con un indicador y la ficha abierta.
func _phone_shot(pilot: Autopilot) -> void:
	_set_time(10, 20, "arrival", "work_morning")
	_streamer.load_floor(3)
	_place_player(WING, Vector2(7.0, 11.6))
	EventBus.room_entered.emit(WING, true)
	_layer.sync_now()
	get_window().size = PHONE_WINDOW
	_ui.set_touch_mode(true)
	_frame_on(_streamer.get_room_rect_px(WING).get_center() + Vector2(-_cell * 3.0, _cell * 2.0), WING_ZOOM)
	await pilot.frames(SETTLE_FRAMES * 2)
	_stand_at_drawer()
	_player.begin_act("drawer_forced", 0.0)
	await _wait_for_state(pilot, Perception.STATE_PARTIAL, 0.5, 0.95)
	_layer.open_card(CARD_NPC)
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("npcs_phone")


## Leyenda de QA: panel con cuatro personajes y su indicador, fila normal y fila de alto contraste.
class IndicatorLegend extends Control:
	const STATES: Array[int] = [Perception.STATE_NONE, Perception.STATE_PROGRESS, Perception.STATE_PARTIAL,
		Perception.STATE_FLAGRANT]
	const LABELS: Array[String] = ["QA_NPCS_STATE_NONE", "QA_NPCS_STATE_PROGRESS", "QA_NPCS_STATE_PARTIAL",
		"QA_NPCS_STATE_FLAGRANT"]
	const COUNTERS: Array[float] = [0.0, 0.28, 0.7, 1.0]
	const PANEL := Rect2(230, 120, 1460, 840)
	const COLUMN_W := 320.0
	const ROW_Y: Array[float] = [520.0, 880.0]
	const FIGURE_SCALE := 2.2
	const ROW_LABEL_X := 40.0
	const FIRST_COLUMN := 300.0
	const LEGEND_RADIUS := 30.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font: Font = UITheme.font(UITheme.FONT_SEMIBOLD)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.55))
		draw_colored_polygon(UITheme.rounded_rect_points(PANEL, 18.0), Color("#8a8f7d"))
		draw_string(font, PANEL.position + Vector2(40, 64), tr("QA_NPCS_LEGEND_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("#12151a"))
		for row: int in 2:
			var contrast: bool = row == 1
			draw_string(font, Vector2(PANEL.position.x + ROW_LABEL_X, ROW_Y[row] - 120.0),
					tr("QA_NPCS_ROW_CONTRAST" if contrast else "QA_NPCS_ROW_NORMAL"), HORIZONTAL_ALIGNMENT_LEFT, 220.0, 26,
					Color("#12151a"))
			for i: int in STATES.size():
				_cell_at(i, row, contrast, font)

	func _cell_at(i: int, row: int, contrast: bool, font: Font) -> void:
		var x: float = PANEL.position.x + FIRST_COLUMN + COLUMN_W * i
		var feet: Vector2 = Vector2(x + 60.0, ROW_Y[row] - 30.0)
		var app: Dictionary = CharacterPainter.appearance_from_seed(5100 + i * 7, 1, false, "")
		var pose: Dictionary = CharacterPainter.make_pose("idle" if i < 2 else ("suspicion" if i == 2 else "point"), 0,
				Vector2(-1, 1).normalized(), {"origin": feet, "scale": FIGURE_SCALE})
		CharacterPainter.draw(self, app, 1, pose)
		var head: Vector2 = feet + Vector2(0.0, -130.0 - LEGEND_RADIUS * DetectionIndicator.ANCHOR_LIFT)
		if STATES[i] == Perception.STATE_NONE:
			draw_arc(head, LEGEND_RADIUS * 0.8, 0.0, TAU, 32, Color(0.1, 0.1, 0.1, 0.35), 2.0, true)
		DetectionIndicator.draw_state(self, head, LEGEND_RADIUS, STATES[i], COUNTERS[i], contrast, 0.25)
		draw_string(font, Vector2(x - 40.0, ROW_Y[row] + 10.0), tr(LABELS[i]), HORIZONTAL_ALIGNMENT_CENTER, 200.0, 20, Color("#12151a"))
