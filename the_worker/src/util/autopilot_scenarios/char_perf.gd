# char_perf.gd (escenario) — Coste de dibujo de los personajes (ala 3B a las 10:00, cafetería a las 13:30) y diferencia de píxeles entre el dibujo de referencia y la malla por pose.
# PROPIETARIO DE: los nodos temporales del escenario y su informe (<shots>/char_perf.txt).
# ESCUCHA: nada.
extends Node

## SHOT_TIMEOUT=900 tools/screenshot.sh /tmp/shots_char_perf char_perf
## 1) Rendimiento: partida nueva (semilla fija) montada como npcs.gd; ala 3B a las 10:00 y
##    cafetería (PB) a las 13:30. En cada escena alterna los caminos de CharacterPainter
##    (set_reference_mode: true = una orden de dibujo por trazo, el camino anterior; false = una
##    malla por pose, con el tope de teselado de balance.json o sin tope) y mide: en frío (caché
##    vacía, COLD_FRAMES fotogramas: ms máximo y medio, el tirón de grabar las poses) y en régimen
##    (tras calentar): llamadas de dibujo del fotograma (RenderingServer.get_rendering_info), las de
##    los personajes (ocultándolos), primitivas, ms por fotograma de reloj y CPU/GPU de render del
##    viewport; en natural (cada personaje se redibuja al cambiar de fotograma) y forzando el
##    redibujo de todos cada fotograma (peor caso).
## 2) Aspecto: ejecuta la hoja de personajes (characters.gd) con un piloto que, en cada captura,
##    dibuja la misma hoja por los dos caminos (teselado sin tope de tiempo: todo malla) y los
##    compara (Image.compute_image_metrics + recuento de píxeles por encima de un umbral). Guarda
##    ref_/mesh_/diff_<hoja>.png.
## 3) micro: CPU de draw() de una pose ya en caché, por camino.
## Si CharacterPainter no tiene set_reference_mode (código anterior) mide solo el camino único.

const SEED := 12345
const WING := "wing_3b"
const CAFETERIA := "cafeteria"
const LIFECYCLE: Array[String] = ["GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet",
	"Security", "Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem"]
const PAINTER_PATH := "res://src/entities/character_painter.gd"
const CHARACTERS_PATH := "res://src/util/autopilot_scenarios/characters.gd"
const TOGGLE := "set_reference_mode"
const BUDGET := "set_tessellation_budget_ms"
const WING_ZOOM := 1.3
const CAFE_ZOOM := 0.95
const SETTLE_FRAMES := 24
const WARM_FRAMES := 20
const SAMPLE_FRAMES := 60
const ROUNDS := 2
const COLD_FRAMES := 30
const MODE_REF := "reference"
const MODE_MESH := "mesh"
const MODE_MESH_UNBUDGETED := "mesh_unbudgeted"
const DIFF_THRESHOLDS: Array[int] = [2, 8, 32]
const MICRO_DRAWS := 2000

var _streamer: FloorStreamer = null
var _layer: NPCLayer = null
var _player: Player = null
var _cam: Camera2D = null
var _cell: float = 48.0
var _painter: GDScript = null
var _out: PackedStringArray = PackedStringArray()
var _shot_dir: String = "user://"


func run(pilot: Autopilot) -> void:
	_painter = load(PAINTER_PATH) as GDScript
	_shot_dir = str(pilot.get_args().get("shots", "user://"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_new_run()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	_build_world()
	await _measure_scene(pilot, "wing_3b_10:00", 3, WING, 10, 0, WING_ZOOM)
	await _measure_scene(pilot, "cafeteria_13:30", 0, CAFETERIA, 13, 30, CAFE_ZOOM)
	await _micro_bench(pilot)
	_teardown_world()
	await _lineup_diff(pilot)
	_set_mode(false)
	_write_report()


func _has_toggle() -> bool:
	return _has_method(TOGGLE)


func _has_method(method: String) -> bool:
	for m: Dictionary in _painter.get_script_method_list():
		if str(m.get("name", "")) == method:
			return true
	return false


## Tope de teselado por fotograma (ms; < 0 sin límite, 0 = balance.json), si existe.
func _set_budget(ms: float) -> void:
	if _has_method(BUDGET):
		_painter.call(BUDGET, ms)


func _modes(with_unbudgeted: bool = false) -> Array[String]:
	if not _has_toggle():
		return [MODE_REF]
	if with_unbudgeted and _has_method(BUDGET):
		return [MODE_REF, MODE_MESH, MODE_MESH_UNBUDGETED]
	return [MODE_REF, MODE_MESH]


func _set_mode(reference: bool) -> void:
	if _has_toggle():
		_painter.call(TOGGLE, reference)


func _log(line: String) -> void:
	_out.append(line)
	print("[char_perf] ", line)


func _write_report() -> void:
	var file: FileAccess = FileAccess.open(_shot_dir.path_join("char_perf.txt"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_out) + "\n")


# ─── Montaje (como npcs.gd) ───────────────────────────────────

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


func _build_world() -> void:
	GameClock.set_time(1, 10, 0)
	EventBus.time_band_changed.emit("arrival", "work_morning")
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(3)
	_player = (load("res://scenes/world/player.tscn") as PackedScene).instantiate() as Player
	_player.with_camera = false
	_streamer.get_actor_layer().add_child(_player)
	_streamer.set_player(_player)
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_layer = NPCLayer.new()
	_layer.free_running = true
	add_child(_layer)
	_layer.set_streamer(_streamer)


func _teardown_world() -> void:
	for node: Node in [_layer, _streamer, _cam]:
		if node != null:
			node.queue_free()
	_layer = null
	_streamer = null


# ─── Rendimiento ──────────────────────────────────────────────

func _measure_scene(pilot: Autopilot, label: String, floor: int, room: String, hour: int, minute: int,
		zoom: float) -> void:
	GameClock.set_time(1, hour, minute)
	EventBus.time_band_changed.emit("arrival", "lunch" if hour >= 13 else "work_morning")
	if _streamer.get_current_floor() != floor:
		_streamer.load_floor(floor)
	var rect: Rect2 = _streamer.get_room_rect_px(room)
	_player.global_position = rect.position + Vector2(rect.size.x - _cell * 1.5, rect.size.y - _cell * 1.5)
	_player.velocity = Vector2.ZERO
	await pilot.frames(3)
	EventBus.room_entered.emit(room, true)
	_layer.sync_now()
	_cam.position = rect.get_center() + Vector2(0.0, _cell * 0.5)
	_cam.zoom = Vector2(zoom, zoom)
	await pilot.frames(SETTLE_FRAMES)
	for forced: bool in [false, true]:
		var acc: Dictionary = {}
		for r: int in ROUNDS:
			for mode: String in _modes(not forced):
				var s: Dictionary = await _sample(pilot, mode, forced)
				_accumulate(acc, mode, s)
		for mode: String in _modes(not forced):
			_report_sample(label + (" redraw_all" if forced else " natural"), mode, acc[mode])


func _accumulate(acc: Dictionary, mode: String, s: Dictionary) -> void:
	if not acc.has(mode):
		acc[mode] = {}
	var a: Dictionary = acc[mode]
	for k: String in s:
		a[k] = float(a.get(k, 0.0)) + float(s[k]) / float(ROUNDS)


func _report_sample(label: String, mode: String, s: Dictionary) -> void:
	var visible: float = maxf(float(s["visible"]), 1.0)
	_log("%s [%s] npcs=%d on_screen=%d draws=%d chars=%d per_char=%.2f prims=%d frame_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f process_ms=%.2f cold_max_ms=%.1f cold_avg_ms=%.1f poses=%d pending=%d" % [
		label, mode, int(s["nodes"]), int(s["visible"]), int(s["draws"]), int(s["chars"]),
		float(s["chars"]) / visible, int(s["prims"]), float(s["frame_ms"]), float(s["render_cpu"]),
		float(s["render_gpu"]), float(s["process"]), float(s["cold_max"]), float(s["cold_avg"]), int(s["poses"]),
		int(s["pending"])])


## Una muestra con caché vacía: arranque en frío, calentamiento (teselado sin tope), fotogramas de
## reloj en régimen con el tope del modo y, después, los mismos contadores sin personajes.
func _sample(pilot: Autopilot, mode: String, forced: bool) -> Dictionary:
	_set_mode(mode == MODE_REF)
	var budget: float = -1.0 if mode == MODE_MESH_UNBUDGETED else 0.0
	_set_budget(budget)
	_painter.call("clear_cache")
	_redraw_characters()
	var cold: Vector2 = await _cold_frames(pilot, forced)
	_set_budget(-1.0)
	await _frames_redrawing(pilot, WARM_FRAMES, forced)
	_set_budget(budget)
	var s: Dictionary = await _steady(pilot, forced)
	s["cold_max"] = cold.x
	s["cold_avg"] = cold.y
	return s


## ms máximo y medio de los primeros fotogramas tras vaciar la caché.
func _cold_frames(pilot: Autopilot, forced: bool) -> Vector2:
	var worst: float = 0.0
	var total: float = 0.0
	var last: int = Time.get_ticks_usec()
	for i: int in COLD_FRAMES:
		await _frames_redrawing(pilot, 1, forced)
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		total += ms
	return Vector2(worst, total / COLD_FRAMES)


func _steady(pilot: Autopilot, forced: bool) -> Dictionary:
	var vp: RID = get_viewport().get_viewport_rid()
	var cpu: float = 0.0
	var gpu: float = 0.0
	var process: float = 0.0
	var start: int = Time.get_ticks_usec()
	for i: int in SAMPLE_FRAMES:
		await _frames_redrawing(pilot, 1, forced)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var frame_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / SAMPLE_FRAMES
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var shown: int = _on_screen()
	for node: NPCNode in _layer.get_nodes():
		node.visible = false
	await pilot.frames(3)
	var without: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	for node: NPCNode in _layer.get_nodes():
		node.visible = true
	return {"nodes": _layer.get_nodes().size(), "visible": shown, "draws": draws, "chars": draws - without,
		"prims": prims, "frame_ms": frame_ms, "render_cpu": cpu / SAMPLE_FRAMES, "render_gpu": gpu / SAMPLE_FRAMES,
		"process": process / SAMPLE_FRAMES, "poses": _pose_count(),
		"pending": int(_painter.call("pending_pose_count")) if _has_method("pending_pose_count") else 0}


func _pose_count() -> int:
	return int(_painter.call("cached_pose_count"))


func _frames_redrawing(pilot: Autopilot, n: int, forced: bool) -> void:
	for i: int in n:
		if forced:
			_redraw_characters()
		await pilot.frames(1)


func _redraw_characters() -> void:
	for node: NPCNode in _layer.get_nodes():
		node.queue_redraw()
	_player.queue_redraw()


## Personajes dentro del rectángulo visible de la cámara.
func _on_screen() -> int:
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	var n: int = 0
	for node: NPCNode in _layer.get_nodes():
		if view.grow(_cell).has_point(node.global_position):
			n += 1
	return n


## CPU de emitir el dibujo de un personaje ya en caché (sin render): µs por llamada a draw().
func _micro_bench(pilot: Autopilot) -> void:
	var bench: Bench = Bench.new()
	for i: int in 20:
		bench.apps.append(CharacterPainter.appearance_from_seed(7000 + i * 13, 1 + i % 8, false, ""))
	add_child(bench)
	for mode: String in _modes():
		_set_mode(mode == MODE_REF)
		for app: Dictionary in bench.apps:
			CharacterPainter.prewarm(app, int(app["tier"]), "walk", Vector2.DOWN)
		bench.queue_redraw()
		await pilot.frames(2)
		_log("micro [%s] draw() of a cached pose (CPU, command emission incl. buffers): %.1f us/call" % [mode,
				bench.last_us])
	bench.queue_free()


## Lienzo de la medida: MICRO_DRAWS dibujos de poses en caché dentro de su _draw (vaciándolo entre uno y otro).
class Bench extends Node2D:
	var apps: Array[Dictionary] = []
	var last_us: float = 0.0

	func _draw() -> void:
		var rid: RID = get_canvas_item()
		var start: int = Time.get_ticks_usec()
		for i: int in MICRO_DRAWS:
			var app: Dictionary = apps[i % apps.size()]
			RenderingServer.canvas_item_clear(rid)
			CharacterPainter.draw(self, app, int(app["tier"]), CharacterPainter.make_pose("walk", i % 8, Vector2.DOWN))
		last_us = float(Time.get_ticks_usec() - start) / float(MICRO_DRAWS)
		RenderingServer.canvas_item_clear(rid)


# ─── Aspecto: hoja de personajes por los dos caminos ─────────

func _lineup_diff(pilot: Autopilot) -> void:
	if not _has_toggle():
		_log("lineup diff skipped: CharacterPainter has no %s" % TOGGLE)
		return
	_set_budget(-1.0)
	var diff_pilot: DiffPilot = DiffPilot.new()
	diff_pilot.owner_scenario = self
	diff_pilot.name = "DiffPilot"
	add_child(diff_pilot)
	var sheet: Node = (load(CHARACTERS_PATH) as GDScript).new() as Node
	add_child(sheet)
	await sheet.call("run", diff_pilot)
	sheet.queue_free()
	diff_pilot.queue_free()
	_set_budget(0.0)


## Compara la hoja actual dibujada por los dos caminos.
func compare_now(shot_name: String) -> void:
	var images: Dictionary = {}
	for mode: String in [MODE_REF, MODE_MESH]:
		_set_mode(mode == MODE_REF)
		_redraw_tree(get_tree().root)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		images[mode] = get_viewport().get_texture().get_image()
	var ref: Image = images[MODE_REF]
	var mesh: Image = images[MODE_MESH]
	ref.save_png(_shot_dir.path_join("ref_%s.png" % shot_name))
	mesh.save_png(_shot_dir.path_join("mesh_%s.png" % shot_name))
	_log("diff %s %s" % [shot_name, _diff_summary(ref, mesh, shot_name)])


func _redraw_tree(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	for child: Node in node.get_children():
		_redraw_tree(child)


## Métricas de Godot (0–255) + píxeles cuya mayor diferencia de canal supera cada umbral.
func _diff_summary(a: Image, b: Image, shot_name: String) -> String:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var metrics: Dictionary = a.compute_image_metrics(b, false)
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var counts: Array[int] = [0, 0, 0]
	var heat: Image = Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_L8)
	var hd: PackedByteArray = heat.get_data()
	var px: int = a.get_width() * a.get_height()
	for i: int in px:
		var o: int = i * 4
		var d: int = maxi(maxi(absi(da[o] - db[o]), absi(da[o + 1] - db[o + 1])), absi(da[o + 2] - db[o + 2]))
		if d <= DIFF_THRESHOLDS[0]:
			continue
		hd[i] = mini(d * 4, 255)
		for t: int in DIFF_THRESHOLDS.size():
			if d > DIFF_THRESHOLDS[t]:
				counts[t] += 1
	heat.set_data(a.get_width(), a.get_height(), false, Image.FORMAT_L8, hd)
	heat.save_png(_shot_dir.path_join("diff_%s.png" % shot_name))
	return "max=%d mean=%.4f rmse=%.4f psnr=%.1fdB px>%d=%d (%.4f%%) px>%d=%d (%.4f%%) px>%d=%d (%.4f%%)" % [
		int(metrics.get("max", -1)), float(metrics.get("mean", -1.0)), float(metrics.get("root_mean_squared", -1.0)),
		float(metrics.get("peak_snr", -1.0)), DIFF_THRESHOLDS[0], counts[0], 100.0 * counts[0] / px,
		DIFF_THRESHOLDS[1], counts[1], 100.0 * counts[1] / px, DIFF_THRESHOLDS[2], counts[2], 100.0 * counts[2] / px]


## Piloto para characters.gd: cada captura se convierte en una comparación de los dos caminos.
class DiffPilot extends Autopilot:
	var owner_scenario: Node = null

	func _ready() -> void:
		pass

	func shot(shot_name: String) -> void:
		await owner_scenario.call("compare_now", shot_name)
