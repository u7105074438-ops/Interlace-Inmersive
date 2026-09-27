# map_case.gd — Cuerpo de test_map: corte completo, colores de acceso, capas, zoom, objetivos y entrada (PASO 36).
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Comprueba el modelo de acceso (verde/ámbar/rojo) con contextos fijos y con el del jugador, que
## el corte dibuja todas las plantas (S3..azotea + nave), las capas conmutables (API, señal y teclas
## 1-2-3), el zoom a planta (plano de FloorLayout y lista de salas), Esc en dos pasos, los puntos de
## personajes (objetivo aproximado sin rutina, conocido con rutina desbloqueada, expediente completo
## anticipado, desconocidos ocultos), los conos de cámara recortados a su sala, el orden de ↑/↓, el
## arrastre táctil (con ratón emulado), señalar sin desplazar, el refresco agrupado por el bus y la
## apertura desde UIRoot (modal que pausa el reloj; Tab de nuevo lo cierra; pistas táctiles).

const N1_DESK := "wing_3b"
const N1_TOOLS: Array[String] = ["keys_basic", "stamp"]
const VIEW_SIZE := Vector2(1920, 1080)
const PHONE_SIZE := Vector2(1170, 540)
const SETTLE_FRAMES := 3
const DRAG_STEPS := 5
const DRAG_STEP_PX := 20.0
const HOVER_MOVES := 12

var _toggled: Array[String] = []
var _closed: int = 0


func run_case() -> void:
	check(new_run(), "database loaded")
	_check_n1_floors()
	_check_alternatives()
	_check_extra_tables()
	_check_higher_clearances()
	_check_player_context()
	var map: MapView = await _open_view(VIEW_SIZE)
	_check_cut(map)
	_check_layers(map)
	await _check_zoom(map)
	await _check_steps(map)
	await _check_cameras(map)
	await _check_dots(map)
	await _check_unknown_hidden(map)
	await _check_refresh(map)
	await _check_early_file(map)
	map.queue_free()
	await wait_frames(2)
	var phone: MapView = await _open_view(PHONE_SIZE)
	await _check_touch_drag(phone)
	await _check_hover_stable(phone)
	phone.queue_free()
	await wait_frames(2)
	await _check_ui_root()


func _n1(disguise: String = "", extra_items: Array = []) -> Dictionary:
	var items: Array = N1_TOOLS.duplicate()
	items.append_array(extra_items)
	return MapView.make_access_context(1, [], N1_DESK, disguise, items)


func _room(id: String) -> RoomData:
	return Database.get_room(id)


func _check_n1_floors() -> void:
	var ctx: Dictionary = _n1()
	check_eq(MapView.floor_access(3, ctx), MapView.ACCESS_ALLOWED, "N1: P3 green")
	check_eq(MapView.floor_access(15, ctx), MapView.ACCESS_FORBIDDEN, "N1: P15 red")
	check_eq(MapView.floor_access(13, ctx), MapView.ACCESS_FORBIDDEN, "N1 without uniform: P13 red")
	check_eq(MapView.floor_access(20, ctx), MapView.ACCESS_FORBIDDEN, "N1: P20 red")
	check_eq(MapView.floor_access(0, ctx), MapView.ACCESS_ALLOWED, "N1: ground floor green")
	check_eq(MapView.room_access(_room(N1_DESK), ctx), MapView.ACCESS_ALLOWED, "N1: own wing 3B green")
	check_eq(MapView.room_access(_room("boardroom"), ctx), MapView.ACCESS_FORBIDDEN, "N1: boardroom red")
	var cleaning: Dictionary = _n1("uniform_cleaning")
	check_eq(MapView.floor_access(13, cleaning), MapView.ACCESS_ALTERNATIVE, "N1 + cleaning uniform: P13 amber")
	check_eq(MapView.alternative_method(_room("cleaning_closet_high@13"), cleaning), MapView.METHOD_UNIFORM,
			"cleaning closet of P13 reached by uniform")
	var guard: Dictionary = _n1("security")
	check_eq(MapView.floor_access(15, guard), MapView.ACCESS_ALTERNATIVE, "N1 + guard uniform (short id): P15 amber")
	check_eq(MapView.room_access(_room("monitor_room"), guard), MapView.ACCESS_ALTERNATIVE, "guard uniform: monitor room amber")


func _check_alternatives() -> void:
	var ctx: Dictionary = _n1()
	check_eq(MapView.alternative_method(_room("hr_office"), ctx), MapView.METHOD_VENT, "N1: HR reached through the P1 toilet duct")
	check_eq(MapView.room_access(_room("incident_archive"), ctx), MapView.ACCESS_FORBIDDEN, "N1: P15 archive duct leads nowhere usable")
	check_eq(MapView.alternative_method(_room("historic_designs_archive"), ctx), MapView.METHOD_OLD_KEYS, "N1: old desk keys open the P7 archive")
	check_eq(MapView.floor_access(7, ctx), MapView.ACCESS_ALTERNATIVE, "N1: P7 amber thanks to old keys")
	var no_keys: Dictionary = MapView.make_access_context(1, [], N1_DESK, "", [])
	check_eq(MapView.floor_access(7, no_keys), MapView.ACCESS_FORBIDDEN, "N1 without keys: P7 red")
	var card: Dictionary = _n1("", ["stolen_card"])
	check_eq(MapView.alternative_method(_room("aurora_room"), card), MapView.METHOD_CARD, "stolen card (N4) opens P12")
	check_eq(MapView.room_access(_room("cfo_office"), card), MapView.ACCESS_FORBIDDEN, "stolen card does not reach N5")
	var keys: Dictionary = _n1("", ["master_keys"])
	check_eq(MapView.room_access(_room("investor_lounge"), keys), MapView.ACCESS_ALTERNATIVE, "master keys reach N6")
	check_eq(MapView.room_access(_room("ceo_office"), keys), MapView.ACCESS_FORBIDDEN, "master keys stop below N7")
	var pick: Dictionary = _n1("", ["lockpick"])
	check_eq(MapView.alternative_method(_room("old_confidential_cage"), pick), MapView.METHOD_FORCED_LOCK, "lockpick forces the S2 cage")
	var maint: Dictionary = MapView.make_access_context(2, ["basements", "vents", "maintenance"], "maintenance_workshop", "", [])
	check_eq(MapView.room_access(_room("boiler_room"), maint), MapView.ACCESS_ALLOWED, "maintenance: boiler room green")
	check_eq(MapView.alternative_method(_room("incident_archive"), maint), MapView.METHOD_VENT, "maintenance: ducts reach P15 archive")
	var n6: Dictionary = MapView.make_access_context(6)
	check_eq(MapView.alternative_method(_room("rooftop_terrace"), n6), MapView.METHOD_ROOF_LEDGE, "N6: terrace by the gym ledge")


## Tablas de métodos alternativos ampliadas: herramientas de forzar, llaves de sala, mono de fábrica.
func _check_extra_tables() -> void:
	for tool_id: String in ["crowbar", "bolt_cutter", "angle_grinder"]:
		check_eq(MapView.alternative_method(_room("old_confidential_cage"), _n1("", [tool_id])), MapView.METHOD_FORCED_LOCK,
				"%s forces the S2 cage" % tool_id)
	check_eq(MapView.alternative_method(_room("ceo_office"), _n1("", ["ceo_office_key"])), MapView.METHOD_ROOM_KEY, "CEO office key: CEO office amber")
	check_eq(MapView.room_access(_room("ceo_boardroom"), _n1("", ["ceo_office_key"])), MapView.ACCESS_FORBIDDEN, "CEO office key opens only that office")
	check_eq(MapView.alternative_method(_room("office_supplies"), _n1("", ["supply_room_key"])), MapView.METHOD_ROOM_KEY, "supply room key")
	check_eq(MapView.floor_access(100, _n1("", ["factory_master_key"])), MapView.ACCESS_ALTERNATIVE, "factory master key: factory amber")
	check_eq(MapView.alternative_method(_room("assembly_line"), _n1("", ["factory_overalls"])), MapView.METHOD_UNIFORM, "factory overalls act as a uniform")
	check(not MapView.is_room_allowed(_room("loading_dock"), _n1("", ["factory_overalls"])), "overalls never make a room green")


func _check_higher_clearances() -> void:
	var n5: Dictionary = MapView.make_access_context(5)
	check_eq(MapView.floor_access(13, n5), MapView.ACCESS_ALLOWED, "N5: P13 green")
	check_eq(MapView.floor_access(15, n5), MapView.ACCESS_ALLOWED, "N5: P15 green")
	check_eq(MapView.floor_access(16, n5), MapView.ACCESS_ALTERNATIVE, "N5: P16 only a foothold (its N5 cleaning closet) → amber")
	check_eq(MapView.floor_access(18, n5), MapView.ACCESS_FORBIDDEN, "N5: P18 red")
	check_eq(MapView.floor_access(10, MapView.make_access_context(1)), MapView.ACCESS_FORBIDDEN, "N1: P10 red")
	var n7: Dictionary = MapView.make_access_context(7)
	var all_green: bool = true
	for f: int in Database.get_floor_ids():
		if f != Database.get_balance_int("mundo.planta_exterior"):
			all_green = all_green and MapView.floor_access(f, n7) == MapView.ACCESS_ALLOWED
	check(all_green, "N7: every floor green")
	var line: Dictionary = MapView.make_access_context(1, ["factory_floor"], "assembly_line")
	check_eq(MapView.floor_access(100, line), MapView.ACCESS_ALLOWED, "line operator: factory green before N3")
	check_eq(MapView.floor_access(100, _n1()), MapView.ACCESS_FORBIDDEN, "N1 office worker: factory red")


func _check_player_context() -> void:
	var ctx: Dictionary = MapView.player_access_context()
	check_eq(int(ctx[MapView.CTX_CLEARANCE]), 1, "player starts at N1")
	check_eq(str(ctx[MapView.CTX_OFFICE]), N1_DESK, "player office is wing 3B")
	check((ctx[MapView.CTX_ITEMS] as Array).has("keys_basic"), "issued desk keys count as held")
	PlayerState.set_disguise("uniform_cleaning")
	check_eq(MapView.floor_access(13, MapView.player_access_context()), MapView.ACCESS_ALTERNATIVE, "worn disguise read from PlayerState")
	PlayerState.set_disguise("")


func _open_view(view_size: Vector2) -> MapView:
	var map: MapView = MapView.new()
	map.setup({})
	map.layer_toggled.connect(func(layer: String, on: bool) -> void: _toggled.append("%s:%s" % [layer, on]))
	map.close_requested.connect(func() -> void: _closed += 1)
	map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(map)
	map.size = view_size
	await wait_frames(SETTLE_FRAMES)
	return map


func _check_cut(map: MapView) -> void:
	var floors: Array[int] = map.get_cut_floors()
	check_eq(floors.size(), 26, "cut = 3 basements + ground + 20 floors + roof + factory")
	var missing: Array[int] = []
	for f: int in range(-3, 22) + [Database.get_balance_int("mundo.planta_fabrica")]:
		if not floors.has(f) or map.get_cut_floor_rect(f).size.y <= 0.0 or map.get_cut_room_ids(f).is_empty():
			missing.append(f)
	check(missing.is_empty(), "every floor drawn with its rooms %s" % str(missing))
	check(not floors.has(Database.get_balance_int("mundo.planta_exterior")), "exterior is not in the cut")
	check(map.get_cut_floor_rect(20).position.y < map.get_cut_floor_rect(3).position.y, "higher floors drawn above")
	check(map.get_cut_floor_rect(-3).position.y > map.get_cut_floor_rect(0).position.y, "basements below ground")
	check(map.get_cut_floor_rect(20).size.x < map.get_cut_floor_rect(14).size.x and map.get_cut_floor_rect(14).size.x < map.get_cut_floor_rect(3).size.x,
			"setbacks follow the band order (throne narrower than power, power than pit)")
	check_eq(map.get_floor_status(3), MapView.ACCESS_ALLOWED, "view: P3 green for the N1 player")
	check_eq(map.get_floor_status(15), MapView.ACCESS_FORBIDDEN, "view: P15 red for the N1 player")
	check_eq(map.get_room_status("hr_office"), MapView.ACCESS_ALTERNATIVE, "view: HR amber")
	check_eq(map.get_room_method("hr_office"), MapView.METHOD_VENT, "view: HR method is the duct")
	check(not map.get_cut_room_ids(3).has("corridors_low@3"), "corridors are circulation, not blocks")
	check(not map.get_cut_canvas().is_scrollable(), "desktop cut fits without scrolling at medium text")


func _check_layers(map: MapView) -> void:
	for layer: String in MapView.LAYERS:
		check(not map.is_layer_on(layer), "layer %s off by default" % layer)
	map.set_layer(MapView.LAYER_CAMERAS, true)
	check(map.is_layer_on(MapView.LAYER_CAMERAS), "cameras layer on")
	map.toggle_layer(MapView.LAYER_ROUTES)
	check(map.is_layer_on(MapView.LAYER_ROUTES), "routes layer toggled on")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	map._unhandled_input(key)
	check(map.is_layer_on(MapView.LAYER_OCCUPANCY), "key 3 toggles occupancy")
	check_eq(_toggled, ["cameras:true", "routes:true", "occupancy:true"] as Array[String], "layer_toggled emitted per change")
	map.set_band("lunch")
	check_eq(map.get_band(), "lunch", "occupancy band selectable")
	for layer: String in MapView.LAYERS:
		map.set_layer(layer, false)
	check(not map.is_layer_on(MapView.LAYER_CAMERAS), "cameras layer off again")


func _check_zoom(map: MapView) -> void:
	map.zoom_to_floor(3)
	await wait_frames(SETTLE_FRAMES)
	check(map.is_zoomed() and map.get_zoomed_floor() == 3, "zoomed to P3")
	var plan: Dictionary = FloorLayout.compute(3)
	var ids: Array[String] = map.get_floor_plan_view().get_room_ids()
	check_eq(ids.size(), (plan["rooms"] as Dictionary).size(), "P3 plan draws every FloorLayout room")
	check(ids.has(N1_DESK) and ids.has("p3_pantry") and ids.has("corridors_low@3"), "P3 plan has wings, pantry and corridor")
	var listed: Array[String] = map.get_panel_room_ids()
	check(listed.has("wing_3a") and listed.has(N1_DESK) and listed.has("wing_3c"), "side panel lists the P3 wings")
	check_eq(listed.size(), MapView.floor_rooms(3).size(), "side panel lists every own room of P3")
	map.request_close()
	check(not map.is_zoomed() and _closed == 0, "Esc from the zoom returns to the section")
	map.zoom_to_floor(20)
	await wait_frames(SETTLE_FRAMES)
	check(map.get_floor_plan_view().get_room_ids().has("ceo_office"), "P20 plan has the CEO office")
	map.zoom_out()
	map.request_close()
	check_eq(_closed, 1, "Esc from the section asks to close")


## ↑/↓: la azotea es el tope (no salta a la nave) y desde la nave se va a PB.
func _check_steps(map: MapView) -> void:
	var up: InputEventKey = InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	map.zoom_to_floor(21)
	map._unhandled_input(up)
	check_eq(map.get_zoomed_floor(), 21, "↑ from the roof stays on the roof")
	map.zoom_to_floor(Database.get_balance_int("mundo.planta_fabrica"))
	map._unhandled_input(up)
	check_eq(map.get_zoomed_floor(), 0, "↑ from the factory annex goes to the ground floor")
	check(not map.get_step_floors().has(Database.get_balance_int("mundo.planta_fabrica")), "factory outside the ↑/↓ order")
	map.zoom_out()
	await wait_frames(1)


## Conos de cámara del plano: dentro del rectángulo de su sala (los muros ciegan).
func _check_cameras(map: MapView) -> void:
	map.set_layer(MapView.LAYER_CAMERAS, true)
	var outside: Array[String] = []
	var drawn: int = 0
	for f: int in [3, 11, 20, 0]:
		map.zoom_to_floor(f)
		await wait_frames(1)
		var plan_view: MapFloorPlan = map.get_floor_plan_view()
		for cam: Dictionary in plan_view.get_plan().get("cameras", []):
			var room: Rect2 = plan_view.room_rect(str(cam["room_id"])).grow(1.0)
			for part: PackedVector2Array in plan_view.camera_cone(cam):
				drawn += 1
				for p: Vector2 in part:
					if not room.has_point(p):
						outside.append(str(cam["id"]))
						break
	check(drawn > 0, "camera cones drawn on P3/P11/P20/PB")
	check(outside.is_empty(), "every cone clipped to its room %s" % str(outside))
	map.zoom_out()
	map.set_layer(MapView.LAYER_CAMERAS, false)


func _named_npcs() -> Array[NPCRuntime]:
	var named: Array[NPCRuntime] = []
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.is_named and npc.alive and not npc.home_room.is_empty() and not npc.current_room.is_empty():
			named.append(npc)
	return named


func _check_dots(map: MapView) -> void:
	var named: Array[NPCRuntime] = _named_npcs()
	if not check(named.size() >= 3, "population has named characters"):
		return
	map.setup({"targets": [named[0].id]})
	await wait_frames(1)
	var dots: Array[Dictionary] = map.get_visible_dots()
	check_eq(dots.size(), 1, "N1 files: only the marked target is shown")
	check(bool(dots[0]["target"]) and bool(dots[0]["approximate"]), "target without routine shown approximate")
	check_eq(str(dots[0]["room_id"]), named[0].home_room, "approximate target sits at its usual post")
	check_eq(map.get_panel_target_ids(), [named[0].id] as Array[String], "side panel lists the marked target")
	map.setup({"targets": [named[0].id], "file_levels": {named[1].id: 2, named[0].id: 2}})
	await wait_frames(1)
	var by_id: Dictionary = {}
	for dot: Dictionary in map.get_visible_dots():
		by_id[str(dot["npc_id"])] = dot
	check(by_id.has(named[1].id) and not bool(by_id[named[1].id]["target"]), "unlocked routine shows a known colleague")
	check(by_id.has(named[0].id) and not bool(by_id[named[0].id]["approximate"]), "target with routine shown at its room")
	check_eq(str(by_id.get(named[0].id, {}).get("room_id", "")), named[0].current_room, "target dot at current room")
	check_eq(map.get_target_dots().size(), 1, "one highlighted target")


## Con rutina desbloqueada (nivel 7 para todos) un desconocido sin relación sigue sin punto.
func _check_unknown_hidden(map: MapView) -> void:
	var levels: Dictionary = {}
	var stranger: String = ""
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		levels[npc.id] = 7
		if stranger.is_empty() and npc.alive and not npc.is_named and not NPCDirector.knows_player(npc.id):
			stranger = npc.id
	if not check(not stranger.is_empty(), "population has strangers"):
		return
	map.setup({"file_levels": levels, "targets": []})
	await wait_frames(1)
	var ids: Array[String] = []
	for dot: Dictionary in map.get_visible_dots():
		ids.append(str(dot["npc_id"]))
	check(not ids.has(stranger), "unknown NPC hidden even with routine unlocked")
	check(not ids.is_empty(), "known characters shown with routine unlocked")


## Varios avisos del bus en el mismo fotograma → un solo refresco; el disfraz cambia el mapa.
func _check_refresh(map: MapView) -> void:
	map.setup({})
	await wait_frames(1)
	var before: int = map.get_refresh_count()
	PlayerState.set_disguise("uniform_cleaning")
	EventBus.inventory_changed.emit("keys_basic", true)
	EventBus.room_entered.emit(N1_DESK, true)
	await wait_frames(2)
	check_eq(map.get_refresh_count(), before + 1, "bus notices coalesce into one refresh")
	check_eq(map.get_floor_status(13), MapView.ACCESS_ALTERNATIVE, "disguise_changed refreshes the map: P13 amber")
	check(map.is_floor_foothold(13), "P13 is only a foothold (service closet)")
	check(not map.is_floor_foothold(7), "P7 (old keys to an archive) is a real alternative")
	PlayerState.set_disguise("")
	await wait_frames(2)
	check_eq(map.get_floor_status(13), MapView.ACCESS_FORBIDDEN, "disguise removed: P13 red again")
	PlayerState.set_occupation("ceo", "test")
	await wait_frames(2)
	check_eq(map.get_floor_status(20), MapView.ACCESS_ALLOWED, "occupation change refreshes the map: P20 green at N7")
	PlayerState.set_occupation("email_worker_3b", "test")
	await wait_frames(2)
	check_eq(map.get_floor_status(20), MapView.ACCESS_FORBIDDEN, "back to N1: P20 red")


## Acceso anticipado (§13.4): un expediente completo por intrusión en RRHH desbloquea la rutina.
func _check_early_file(map: MapView) -> void:
	var named: Array[NPCRuntime] = _named_npcs()
	var target: NPCRuntime = named[named.size() - 1]
	map.setup({"targets": [target.id]})
	await wait_frames(1)
	check(bool(map.get_target_dots()[0]["approximate"]), "before the intrusion: target approximate")
	check(PlayerState.grant_full_file(target.id, PlayerStateSystem.REASON_HR_INTRUSION), "full file granted")
	map.refresh()
	var dot: Dictionary = map.get_target_dots()[0]
	check(not bool(dot["approximate"]) and str(dot["room_id"]) == target.current_room, "HR intrusion unlocks the target's routine")
	check_eq(map.file_level_for(target.id), PersonnelApp.max_level(), "full file = maximum file level")


## Arrastre táctil con la emulación de ratón del proyecto: el dedo y el ratón emulado llegan los
## dos; el corte debe desplazarse exactamente lo que se mueve el dedo.
func _check_touch_drag(map: MapView) -> void:
	var cut: MapView.CutCanvas = map.get_cut_canvas()
	if not check(cut.is_scrollable(), "phone-size cut scrolls"):
		return
	var at: Vector2 = (cut.get_parent() as Control).get_global_rect().get_center()
	cut.scroll_to((cut.size.y - cut.get_view_size().y) * 0.5)
	var before: float = cut.get_scroll()
	_push_touch(at, true)
	for i: int in DRAG_STEPS:
		var from: Vector2 = at - Vector2(0.0, DRAG_STEP_PX * float(i))
		_push_drag(from, from - Vector2(0.0, DRAG_STEP_PX))
	_push_touch(at - Vector2(0.0, DRAG_STEP_PX * DRAG_STEPS), false)
	await wait_frames(1)
	check_near(cut.get_scroll() - before, DRAG_STEP_PX * DRAG_STEPS, 1.0, "a 100 px finger drag scrolls the cut 100 px")
	check(not map.is_zoomed(), "a drag is not a tap (no zoom)")


func _push_touch(pos: Vector2, pressed: bool) -> void:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = pos
	touch.pressed = pressed
	get_viewport().push_input(touch, true)
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.position = pos
	mb.global_position = pos
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(mb, true)


func _push_drag(from: Vector2, to: Vector2) -> void:
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.position = to
	drag.relative = to - from
	get_viewport().push_input(drag, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)


## Señalar con el ratón en un corte desplazable no lo mueve (antes se realimentaba hasta el tope).
func _check_hover_stable(map: MapView) -> void:
	var cut: MapView.CutCanvas = map.get_cut_canvas()
	var clip: Rect2 = (cut.get_parent() as Control).get_global_rect()
	var at: Vector2 = Vector2(cut.floor_rect(10).get_center().x, clip.position.y + clip.size.y * 0.25)
	var before: float = cut.get_scroll()
	var hovered: Array[int] = []
	for i: int in HOVER_MOVES:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = at + Vector2(float(i % 2), 0.0)
		motion.global_position = motion.position
		motion.relative = Vector2(1.0 if i % 2 == 1 else -1.0, 0.0)
		get_viewport().push_input(motion, true)
		await wait_frames(1)
		if not hovered.has(map.get_selected_floor()):
			hovered.append(map.get_selected_floor())
	check_near(cut.get_scroll(), before, 0.5, "pointing at floors does not scroll the cut")
	check_eq(hovered.size(), 1, "a still pointer keeps the same floor selected %s" % str(hovered))


func _check_ui_root() -> void:
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await wait_frames(2)
	ui.open_map()
	await wait_frames(SETTLE_FRAMES)
	check(ui.get_top_modal() is MapView, "UIRoot.open_map() opens MapView")
	check(GameClock.is_paused(), "the map pauses the clock")
	ui.open_map()
	await wait_frames(2)
	check(not ui.has_modal(), "second Tab closes the map")
	ui.set_touch_mode(true)
	ui.open_map()
	await wait_frames(SETTLE_FRAMES)
	var map: MapView = ui.get_top_modal() as MapView
	check_eq(map._hint.text, tr("MAP_HINT_TOUCH"), "touch mode: tap hint on the cut")
	map.zoom_to_floor(3)
	check_eq(map._hint.text, tr("MAP_HINT_ZOOM_TOUCH"), "touch mode: touch hint on the zoom")
	check(not (map._toggles[MapView.LAYER_CAMERAS] as MapView.LayerChip).show_hotkey, "touch mode hides the hotkey caps")
	map.request_close()
	map.request_close()
	await wait_frames(2)
	check(not ui.has_modal(), "close_requested closes the modal")
	ui.set_touch_mode(false)
	ui.queue_free()
	await wait_frames(1)
