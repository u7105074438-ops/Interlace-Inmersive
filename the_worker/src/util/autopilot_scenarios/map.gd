# map.gd (escenario) — Capturas del mapa de evacuación: corte a N1 y N7, capas, zoom a P3 y P20, español y móvil.
# PROPIETARIO DE: los nodos temporales del escenario (mundo de fondo, figura del jugador, UIRoot).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_map map
## Partida nueva con semilla fija (orden de ciclo de vida de BUILD_NOTES §2), planta 3 cargada detrás
## con el jugador en el ala 3B y dos objetivos marcados; después el jugador asciende a N7 (CEO).

const RUN_SEED := 4242
const START_FLOOR := 3
const START_ROOM := "wing_3b"
const TOP_OCCUPATION := "ceo"
const PHONE_WINDOW := Vector2i(1170, 540)
const SETTLE_FRAMES := 8
const LIFECYCLE: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]

var _ui: UIRoot
var _streamer: FloorStreamer
var _targets: Array[String] = []


func run(pilot: Autopilot) -> void:
	_new_run()
	_build_world()
	_ui = UIRoot.new()
	add_child(_ui)
	await pilot.frames(3)
	EventBus.floor_changed.emit(0, START_FLOOR)
	EventBus.room_entered.emit(START_ROOM, true)
	_targets = _pick_targets()
	_ui.open_map({"targets": _targets, "band": "work_morning"})
	await pilot.frames(SETTLE_FRAMES)
	var map: MapView = _map()
	map.select_floor(START_FLOOR)
	await _shot(pilot, "map_cut_n1")
	await _shots_n1_layers(pilot, map)
	await _shots_n7(pilot, map)
	await _shot_spanish(pilot, map)
	await _shots_phone(pilot, map)


func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(RUN_SEED)
	for system_name: String in LIFECYCLE:
		var node: Node = get_tree().root.get_node_or_null(NodePath(system_name))
		if node == null:
			continue
		if node.has_method("reset_for_new_run"):
			node.call("reset_for_new_run")
		if system_name == "GameClock":
			GameClock.set_run_seed(RUN_SEED)
		elif system_name == "NPCDirector" and node.has_method("generate_population"):
			node.call("generate_population")
		elif system_name == "SocialGraph" and node.has_method("build_initial_graph"):
			node.call("build_initial_graph")
	GameClock.set_time(GameClock.get_day(), 10, 30)


func _build_world() -> void:
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(START_FLOOR)
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.position = _streamer.get_room_rect_px(START_ROOM).get_center()
	cam.make_current()
	var figure: Node2D = Node2D.new()
	figure.name = "PreviewPlayer"
	figure.add_to_group(Player.GROUP)
	figure.position = _streamer.get_spawn_point(START_ROOM)
	add_child(figure)


## Dos personajes nominados como objetivos (uno de planta alta, otro de la base).
func _pick_targets() -> Array[String]:
	var out: Array[String] = []
	var high: NPCRuntime = null
	var low: NPCRuntime = null
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.is_named or npc.home_room.is_empty():
			continue
		var room: RoomData = Database.get_room(npc.home_room)
		if room == null:
			continue
		if room.floor >= 13 and room.floor <= 20 and high == null:
			high = npc
		elif room.floor >= 1 and room.floor <= 5 and low == null and npc.home_room != START_ROOM:
			low = npc
	for npc: NPCRuntime in [high, low]:
		if npc != null:
			out.append(npc.id)
	return out


func _map() -> MapView:
	return _ui.get_top_modal() as MapView


func _shot(pilot: Autopilot, shot_name: String) -> void:
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot(shot_name)


func _shots_n1_layers(pilot: Autopilot, map: MapView) -> void:
	for layer: String in MapView.LAYERS:
		map.set_layer(layer, true)
	map.select_floor(1)
	await _shot(pilot, "map_cut_n1_layers")
	map.zoom_to_floor(START_FLOOR)
	await _shot(pilot, "map_zoom_p3_layers")
	for layer: String in MapView.LAYERS:
		map.set_layer(layer, false)
	await _shot(pilot, "map_zoom_p3")
	map.zoom_out()


func _shots_n7(pilot: Autopilot, map: MapView) -> void:
	PlayerState.set_occupation(TOP_OCCUPATION, "qa")
	PlayerState.set_disguise("")
	await pilot.frames(2)
	map.refresh()
	map.select_floor(20)
	await _shot(pilot, "map_cut_n7")
	map.set_layer(MapView.LAYER_CAMERAS, true)
	map.zoom_to_floor(20)
	await _shot(pilot, "map_zoom_p20")
	map.set_layer(MapView.LAYER_CAMERAS, false)
	map.zoom_out()
	PlayerState.set_occupation("email_worker_3b", "qa")
	PlayerState.set_disguise("uniform_cleaning")
	await pilot.frames(2)
	map.refresh()
	map.select_floor(13)
	map.set_layer(MapView.LAYER_ROUTES, true)
	await _shot(pilot, "map_cut_n1_disguised")
	map.set_layer(MapView.LAYER_ROUTES, false)
	PlayerState.set_disguise("")


func _shot_spanish(pilot: Autopilot, map: MapView) -> void:
	TranslationServer.set_locale("es")
	map.refresh()
	map.select_floor(START_FLOOR)
	await _shot(pilot, "map_cut_es")
	map.zoom_to_floor(START_FLOOR)
	await _shot(pilot, "map_zoom_p3_es")
	map.zoom_out()
	TranslationServer.set_locale("en")
	map.refresh()


func _shots_phone(pilot: Autopilot, map: MapView) -> void:
	get_window().size = PHONE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	map.refresh()
	await _shot(pilot, "map_phone_cut")
	map.zoom_to_floor(START_FLOOR)
	await _shot(pilot, "map_phone_zoom")
