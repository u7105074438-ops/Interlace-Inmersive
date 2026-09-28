# char_perf.gd (escenario) — Coste de dibujo de los personajes (ala 3B a las 10:00, cafetería a las 13:30) y diferencia de píxeles entre el dibujo de referencia y la malla por pose.
# PROPIETARIO DE: los nodos temporales del escenario y su informe (<shots>/char_perf.txt).
# ESCUCHA: nada.
extends Node

## SHOT_TIMEOUT=3000 tools/screenshot.sh /tmp/shots_char_perf char_perf [--part=...]
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
## 4) poses (--part=poses): barrida exhaustiva por los dos caminos, hoja a hoja (llamadas de dibujo
##    de cada camino + diferencia de píxeles): cada animación × fotograma × rumbo de pie y sentado,
##    cada tic × animación con tic × fotograma de tic (con y sin mirada), rumbo × mirada, figuras
##    semitransparentes (jugador escondido), a zoom grande, fotos de PERSONNEL grandes y pequeñas y
##    personajes a caballo de los bordes de la pantalla (un lienzo cada uno: recorte del motor);
##    apariencias rotando entre un genérico por escalón, los cuatro uniformes y los nominados.
##    Guarda sweep_ref_/sweep_mesh_ de la primera hoja de cada grupo y de toda hoja con diferencia
##    (--save_all: de todas; con el código anterior dibuja su único camino, para comparar versiones).
## 5) soak (--part=soak): la capa de personajes recorre plantas y horas (cada cambio de planta crea
##    y destruye NPC) con el tope de teselado del juego; en cada parada apunta la caché (poses, MB,
##    descartes, memo de claves), objetos, recursos, memoria estática y búferes de render, y el
##    ritmo de la animación de quienes caminan (fotogramas por segundo de mundo y de la malla dibujada).
## --part=perf|ws|diff|poses|soak (por defecto, todas: SHOT_TIMEOUT=3000).
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
const PART_ALL := "all"
const PART_PERF := "perf"
const PART_WS := "ws"
const PART_DIFF := "diff"
## Conjunto de trabajo: fotogramas de juego natural con la caché sin topes.
const WS_FRAMES := 300
const WS_UNLIMITED_POSES := 1000000
const WS_UNLIMITED_KB := 4194304
const PART_POSES := "poses"
const PART_SOAK := "soak"
## Barrida de poses: rejilla de cada hoja, escala de figura y de la hoja a zoom grande, opacidad de
## la hoja semitransparente, fotos grandes, fondo y diferencia (0–255) a partir de la que se guardan
## las dos capturas de una hoja.
const SWEEP_COLS := 16
const SWEEP_ROWS := 6
const SWEEP_SCALE := 1.5
const SWEEP_BIG_SCALE := 6.0
const SWEEP_BIG_ANIMS: Array[String] = ["walk", "bribe", "phone", "caught", "drawer"]
const SWEEP_ALPHA := 0.6
const SWEEP_BIG_PORTRAIT := Vector2(300, 350)
const SWEEP_SMALL_PORTRAIT := Vector2(96, 112)
const SWEEP_BACKGROUND := Color("#c9cdb8")
## Figuras en los bordes: escala, pies junto al borde de arriba y por debajo del de abajo.
const SWEEP_EDGE_SCALE := 3.0
const SWEEP_EDGE_TOP := 40.0
const SWEEP_EDGE_BELOW := 120.0
const SWEEP_SAVE_ABOVE := 2
## --save_all: guarda las capturas de todas las hojas (para compararlas con las de otra versión).
const SAVE_ALL_ARG := "save_all"
const SWEEP_DIRS: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1),
	Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const SWEEP_UNIFORMS: Array[String] = ["security", "cleaning", "maintenance", "factory"]
const SWEEP_LOOK_ANIMS: Array[String] = ["idle", "walk", "chat", "phone_sneak", "sit_type"]
## Resistencia: paradas (planta, hora, minuto), vueltas, fotogramas por parada y zoom.
const SOAK_STOPS: Array[Vector3i] = [Vector3i(3, 10, 0), Vector3i(0, 13, 30), Vector3i(2, 11, 0),
	Vector3i(5, 15, 0), Vector3i(0, 12, 45), Vector3i(3, 16, 30), Vector3i(1, 9, 15), Vector3i(4, 14, 0)]
const SOAK_ROUNDS := 3
const SOAK_FRAMES := 90
const SOAK_ZOOM := 0.7
const SOAK_WALK := "walk"
const HELD_META := &"_character_recordings"
const BYTES_PER_MB := 1048576.0

var _streamer: FloorStreamer = null
var _layer: NPCLayer = null
var _player: Player = null
var _cam: Camera2D = null
var _cell: float = 48.0
var _painter: GDScript = null
var _out: PackedStringArray = PackedStringArray()
var _shot_dir: String = "user://"
var _part: String = PART_ALL
var _save_all: bool = false


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
	_part = str(pilot.get_args().get("part", PART_ALL))
	if _wants(PART_PERF) or _wants(PART_WS) or _wants(PART_SOAK):
		_build_world()
		if _wants(PART_PERF) or _wants(PART_WS):
			await _measure_scene(pilot, "wing_3b_10:00", 3, WING, 10, 0, WING_ZOOM)
			await _measure_scene(pilot, "cafeteria_13:30", 0, CAFETERIA, 13, 30, CAFE_ZOOM)
		if _wants(PART_PERF):
			await _micro_bench(pilot)
		if _wants(PART_SOAK):
			await _soak(pilot)
		_teardown_world()
	if _wants(PART_DIFF):
		await _lineup_diff(pilot)
	if _wants(PART_POSES):
		await _pose_sweep(pilot)
	_set_mode(false)
	_write_report()


## Parte pedida con --part=perf|ws|diff|poses|soak (por defecto, todas).
func _wants(part: String) -> bool:
	return _part == PART_ALL or _part == part


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
	if _wants(PART_WS):
		await _working_set(pilot, label)
	if not _wants(PART_PERF):
		return
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


## Poses distintas que pide la escena (caché sin topes, sin tope de teselado) en WS_FRAMES
## fotogramas de juego natural, y su memoria: dimensiona cache_poses / cache_mallas_kb.
func _working_set(pilot: Autopilot, label: String) -> void:
	if not _has_method("cache_stats"):
		return
	_set_mode(false)
	_painter.call("set_cache_limits", WS_UNLIMITED_POSES, WS_UNLIMITED_KB)
	_set_budget(-1.0)
	_painter.call("reset_cache_stats")
	var start: int = Time.get_ticks_msec()
	var poses_at: Array[int] = []
	for i: int in WS_FRAMES:
		await pilot.frames(1)
		if i % (WS_FRAMES / 5) == WS_FRAMES / 5 - 1:
			poses_at.append(_pose_count())
	var st: Dictionary = _painter.call("cache_stats")
	var npcs: int = maxi(_layer.get_nodes().size(), 1)
	_log("%s working set: %d frames (%.1f s) -> %d poses (%.1f per NPC, growth %s), %.1f MB of meshes (%.1f KB/pose), hits=%d misses=%d" % [
		label, WS_FRAMES, float(Time.get_ticks_msec() - start) / 1000.0, int(st["poses"]),
		float(st["poses"]) / npcs, str(poses_at), float(st["bytes"]) / 1048576.0,
		float(st["bytes"]) / 1024.0 / maxf(float(st["poses"]), 1.0), int(st["hits"]), int(st["misses"])])
	_painter.call("set_cache_limits", 0, 0)
	_set_budget(0.0)


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


# ─── Barrida de poses: todo el catálogo por los dos caminos ───

## Lienzo de la barrida: figuras (en su orden) y fotos de PERSONNEL.
class SweepCanvas extends Node2D:
	var figures: Array[Dictionary] = []
	var portraits: Array[Dictionary] = []

	func _draw() -> void:
		for f: Dictionary in figures:
			CharacterPainter.draw(self, f["app"], int(f["tier"]), f["pose"])
		for p: Dictionary in portraits:
			CharacterPainter.draw_portrait(self, p["app"], p["rect"])


func _pose_sweep(pilot: Autopilot) -> void:
	_save_all = pilot.get_args().has(SAVE_ALL_ARG)
	_set_budget(-1.0)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var bg: ColorRect = ColorRect.new()
	bg.color = SWEEP_BACKGROUND
	bg.size = get_viewport().get_visible_rect().size
	layer.add_child(bg)
	var canvas: SweepCanvas = SweepCanvas.new()
	layer.add_child(canvas)
	await pilot.frames(2)
	var apps: Array[Dictionary] = _sweep_apps()
	var standing: Array[Dictionary] = _action_figures(apps, false)
	await _sweep_group(canvas, "standing", standing, false)
	await _sweep_group(canvas, "seated", _action_figures(apps, true), false)
	await _sweep_group(canvas, "tics", _tic_figures(apps), false)
	await _sweep_group(canvas, "looks", _look_figures(apps), false)
	await _sweep_group(canvas, "big", _big_figures(apps), true)
	canvas.modulate.a = SWEEP_ALPHA
	await _sweep_group(canvas, "alpha", standing.slice(0, SWEEP_COLS * SWEEP_ROWS), false)
	canvas.modulate.a = 1.0
	await _sweep_portraits(canvas, apps)
	await _sweep_edges(canvas, apps)
	layer.queue_free()
	_set_budget(0.0)


## Un personaje por lienzo (como un NPC): el recorte del lienzo lo calcula el motor con sus órdenes.
class EdgeFigure extends Node2D:
	var figure: Dictionary = {}

	func _draw() -> void:
		CharacterPainter.draw(self, figure["app"], int(figure["tier"]), figure["pose"])


## Personajes a caballo de los bordes de la pantalla, cada uno en su propio lienzo: si el motor
## calculara mal el rectángulo de la malla (con la transformación de la pose) los descartaría.
func _sweep_edges(canvas: SweepCanvas, apps: Array[Dictionary]) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var spots: Array[Vector2] = [Vector2(0, view.y * 0.3), Vector2(0, view.y * 0.75), Vector2(view.x, view.y * 0.3),
		Vector2(view.x, view.y * 0.75), Vector2(view.x * 0.25, SWEEP_EDGE_TOP), Vector2(view.x * 0.6, SWEEP_EDGE_TOP),
		Vector2(view.x * 0.4, view.y + SWEEP_EDGE_BELOW), Vector2(view.x * 0.8, view.y + SWEEP_EDGE_BELOW),
		Vector2.ZERO, Vector2(view.x, view.y + SWEEP_EDGE_BELOW)]
	for i: int in spots.size():
		var edge: EdgeFigure = EdgeFigure.new()
		var extra: Dictionary = {"scale": SWEEP_EDGE_SCALE, "tic": "leans_on_walls"} if i % 3 == 0 else {"scale": SWEEP_EDGE_SCALE}
		edge.figure = _sweep_figure(apps, i * 5, CharacterPainter.make_pose("idle" if i % 3 == 0 else "walk", i,
				SWEEP_DIRS[i % SWEEP_DIRS.size()].normalized(), extra))
		edge.position = spots[i]
		canvas.add_child(edge)
	var agg: Dictionary = {"sheets": 0, "max": 0, "psnr": INF, "ref": 0, "mesh": 0}
	_merge_sheet(agg, await _compare_sheet(canvas, "edges", true))
	for child: Node in canvas.get_children():
		child.queue_free()
	_log_sweep("edges", spots.size(), agg)


## Un genérico por escalón, los cuatro uniformes (disfraces) y los nominados con su escalón.
func _sweep_apps() -> Array[Dictionary]:
	var apps: Array[Dictionary] = []
	for tier: int in range(1, CharacterStyle.OUTFIT_COUNT + 1):
		apps.append({"app": CharacterPainter.appearance_from_seed(SEED + tier * 31, tier, false, ""), "tier": tier})
	for i: int in SWEEP_UNIFORMS.size():
		var app: Dictionary = CharacterPainter.appearance_from_seed(SEED + 500 + i * 7, 1 + i, false, "")
		app["uniform"] = SWEEP_UNIFORMS[i]
		apps.append({"app": app, "tier": 1 + i})
	for npc: NPCData in Database.get_all_named_npcs():
		var occupation: OccupationData = Database.get_occupation(npc.occupation)
		var tier: int = occupation.tier if occupation != null else 1
		apps.append({"app": CharacterPainter.appearance_for_named(npc, tier), "tier": tier})
	return apps


func _sweep_figure(apps: Array[Dictionary], i: int, pose: Dictionary) -> Dictionary:
	var a: Dictionary = apps[i % apps.size()]
	return {"app": a["app"], "tier": a["tier"], "pose": pose}


## Cada animación × fotograma × rumbo; sentado: las no locomotoras con pose.seated.
func _action_figures(apps: Array[Dictionary], seated: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anim: String in CharacterAnim.CATALOGUE:
		if seated and CharacterAnim.is_locomotion(anim):
			continue
		for frame: int in CharacterAnim.frame_count(anim):
			for dir: Vector2 in SWEEP_DIRS:
				out.append(_sweep_figure(apps, out.size(),
						CharacterPainter.make_pose(anim, frame, dir.normalized(), {"seated": seated})))
	return out


## Cada tic × animación con tics × fotograma de tic (la mitad con mirada dirigida, charla a veces sentada).
func _tic_figures(apps: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tic: String in CharacterAnim.TICS:
		for anim: String in CharacterAnim.TIC_ANIMS:
			for f: int in CharacterAnim.TIC_CYCLE:
				var k: int = out.size()
				var extra: Dictionary = {"tic": tic, "tic_frame": f, "seated": anim == "chat" and f % 3 == 0}
				if k % 2 == 1:
					extra["look"] = SWEEP_DIRS[(k * 3) % SWEEP_DIRS.size()]
				var dir: Vector2 = SWEEP_DIRS[k % SWEEP_DIRS.size()].normalized()
				out.append(_sweep_figure(apps, k,
						CharacterPainter.make_pose(anim, k % CharacterAnim.frame_count(anim), dir, extra)))
	return out


## Rumbo × mirada (8 × 8 + sin mirada) en varias animaciones.
func _look_figures(apps: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anim: String in SWEEP_LOOK_ANIMS:
		for dir: Vector2 in SWEEP_DIRS:
			for l: int in SWEEP_DIRS.size() + 1:
				var extra: Dictionary = {} if l == SWEEP_DIRS.size() else {"look": SWEEP_DIRS[l]}
				var frame: int = out.size() % CharacterAnim.frame_count(anim)
				out.append(_sweep_figure(apps, out.size(), CharacterPainter.make_pose(anim, frame, dir.normalized(), extra)))
	return out


## Zoom grande (nitidez del vector): nominados con su accesorio único.
func _big_figures(apps: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in SWEEP_BIG_ANIMS.size():
		var dir: Vector2 = SWEEP_DIRS[(i * 3 + 1) % SWEEP_DIRS.size()].normalized()
		out.append(_sweep_figure(apps, apps.size() - 1 - i * 3, CharacterPainter.make_pose(SWEEP_BIG_ANIMS[i], 3, dir)))
	return out


## Coloca las figuras en la rejilla de la hoja (origen = pies) a la escala dada.
func _layout(figures: Array[Dictionary], cols: int, rows: int, scale: float) -> void:
	var cell: Vector2 = get_viewport().get_visible_rect().size / Vector2(cols, rows)
	for i: int in figures.size():
		var pose: Dictionary = figures[i]["pose"]
		pose["origin"] = Vector2(cell.x * (float(i % cols) + 0.5), cell.y * (float(i / cols) + 0.85))
		pose["scale"] = scale


## Un grupo en hojas de SWEEP_COLS × SWEEP_ROWS figuras (o una fila a zoom grande): peor diferencia,
## peor PSNR y llamadas de dibujo por figura de cada camino.
func _sweep_group(canvas: SweepCanvas, group: String, figures: Array[Dictionary], big: bool) -> void:
	var cols: int = figures.size() if big else SWEEP_COLS
	var rows: int = 1 if big else SWEEP_ROWS
	var per: int = cols * rows
	var agg: Dictionary = {"sheets": 0, "max": 0, "psnr": INF, "ref": 0, "mesh": 0}
	for start: int in range(0, figures.size(), per):
		var chunk: Array[Dictionary] = figures.slice(start, start + per)
		_layout(chunk, cols, rows, SWEEP_BIG_SCALE if big else SWEEP_SCALE)
		canvas.figures = chunk
		var r: Dictionary = await _compare_sheet(canvas, "%s_%02d" % [group, start / per], start == 0)
		_merge_sheet(agg, r)
	canvas.figures = []
	_log_sweep(group, figures.size(), agg)


func _merge_sheet(agg: Dictionary, r: Dictionary) -> void:
	agg["sheets"] = int(agg["sheets"]) + 1
	agg["max"] = maxi(int(agg["max"]), int(r["max"]))
	agg["psnr"] = minf(float(agg["psnr"]), float(r["psnr"]))
	agg["ref"] = int(agg["ref"]) + int(r["ref"])
	agg["mesh"] = int(agg["mesh"]) + int(r["mesh"])


func _log_sweep(group: String, count: int, agg: Dictionary) -> void:
	_log("sweep %s: %d figures in %d sheets, max diff %d/255, min psnr %.1f dB, draw calls per sheet ref=%.1f mesh=%.1f" % [
		group, count, int(agg["sheets"]), int(agg["max"]), float(agg["psnr"]),
		float(agg["ref"]) / maxf(float(agg["sheets"]), 1.0), float(agg["mesh"]) / maxf(float(agg["sheets"]), 1.0)])


## Fotos de PERSONNEL: tres grandes y una rejilla de pequeñas (nominados y genéricos).
func _sweep_portraits(canvas: SweepCanvas, apps: Array[Dictionary]) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var shown: Array[Dictionary] = []
	for i: int in 3:
		var pos: Vector2 = Vector2(40.0 + float(i) * (SWEEP_BIG_PORTRAIT.x + 30.0), 40.0)
		shown.append({"app": apps[apps.size() - 1 - i]["app"], "rect": Rect2(pos, SWEEP_BIG_PORTRAIT)})
	var cols: int = int((view.x - 1040.0) / (SWEEP_SMALL_PORTRAIT.x + 12.0))
	for i: int in apps.size():
		var pos: Vector2 = Vector2(1040.0 + float(i % cols) * (SWEEP_SMALL_PORTRAIT.x + 12.0),
				40.0 + float(i / cols) * (SWEEP_SMALL_PORTRAIT.y + 12.0))
		shown.append({"app": apps[i]["app"], "rect": Rect2(pos, SWEEP_SMALL_PORTRAIT)})
	canvas.portraits = shown
	var agg: Dictionary = {"sheets": 0, "max": 0, "psnr": INF, "ref": 0, "mesh": 0}
	_merge_sheet(agg, await _compare_sheet(canvas, "portraits", true))
	canvas.portraits = []
	_log_sweep("portraits", shown.size(), agg)


## Dibuja la hoja por los dos caminos: {max, psnr, ref, mesh (llamadas de dibujo)}; guarda las
## capturas si `keep`, con --save_all o si la diferencia pasa de SWEEP_SAVE_ABOVE. Con el código
## anterior (sin set_reference_mode) dibuja el único camino y guarda sweep_ref_ para compararlo
## fuera con las de otra versión.
func _compare_sheet(canvas: CanvasItem, shot_name: String, keep: bool) -> Dictionary:
	var images: Dictionary = {}
	var draws: Dictionary = {}
	for mode: String in _modes():
		_set_mode(mode == MODE_REF)
		_redraw_tree(canvas)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		images[mode] = get_viewport().get_texture().get_image()
		draws[mode] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ref: Image = images[MODE_REF]
	var mesh: Image = images.get(MODE_MESH, ref)
	var metrics: Dictionary = ref.compute_image_metrics(mesh, false)
	var worst: int = int(metrics.get("max", -1))
	if keep or _save_all or worst > SWEEP_SAVE_ABOVE:
		ref.save_png(_shot_dir.path_join("sweep_ref_%s.png" % shot_name))
		if images.has(MODE_MESH):
			mesh.save_png(_shot_dir.path_join("sweep_mesh_%s.png" % shot_name))
	if worst > SWEEP_SAVE_ABOVE:
		_log("sweep sheet %s differs: %s" % [shot_name, _diff_summary(ref, mesh, "sweep_" + shot_name)])
	return {"max": worst, "psnr": float(metrics.get("peak_snr", -1.0)), "ref": draws[MODE_REF],
		"mesh": int(draws.get(MODE_MESH, 0))}


# ─── Resistencia: plantas, horas, altas y bajas de NPC ────────

func _soak(pilot: Autopilot) -> void:
	if not _has_method("cache_stats"):
		_log("soak skipped: CharacterPainter has no cache_stats")
		return
	_set_mode(false)
	_set_budget(0.0)
	_painter.call("set_cache_limits", 0, 0)
	_painter.call("reset_cache_stats")
	_log_memory("soak start")
	for r: int in SOAK_ROUNDS:
		for stop: Vector3i in SOAK_STOPS:
			await _soak_stop(pilot, r, stop)


## Una parada: planta y hora (la gente replanifica: hour_passed + think_all y echa a andar),
## cámara sobre la gente, SOAK_FRAMES fotogramas de juego natural.
func _soak_stop(pilot: Autopilot, round_i: int, stop: Vector3i) -> void:
	var old_band: String = GameClock.get_current_band()
	GameClock.set_time(1, stop.y, stop.z)
	EventBus.time_band_changed.emit(old_band, GameClock.get_current_band())
	if _streamer.get_current_floor() != stop.x:
		_streamer.load_floor(stop.x)
	await pilot.frames(2)
	_layer.sync_now()
	EventBus.hour_passed.emit(stop.y, 1)
	_layer.think_all()
	await pilot.frames(2)
	_frame_crowd()
	var start: int = Time.get_ticks_usec()
	var rate: Dictionary = await _anim_rate(pilot, SOAK_FRAMES)
	var ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / SOAK_FRAMES
	_log_memory("soak r%d floor %d %02d:%02d nodes=%d frame_ms=%.1f walk_fps(world)=%.2f walk_mesh_changes/s=%.2f walkers=%d speed_mod=%.2f" % [
		round_i, stop.x, stop.y, stop.z, _layer.get_nodes().size(), ms, float(rate["fps"]),
		float(rate["mesh_fps"]), int(rate["walkers"]), float(rate["speed"])])


## Cámara en el centro de la gente de la planta.
func _frame_crowd() -> void:
	var sum: Vector2 = Vector2.ZERO
	var nodes: Array[NPCNode] = _layer.get_nodes()
	for node: NPCNode in nodes:
		sum += node.global_position
	_cam.position = sum / float(nodes.size()) if not nodes.is_empty() else _player.global_position
	_cam.zoom = Vector2(SOAK_ZOOM, SOAK_ZOOM)


## Ritmo de la animación de quienes caminan: fotogramas avanzados y cambios de la malla dibujada
## (metadato del lienzo) por segundo de mundo de caminata.
func _anim_rate(pilot: Autopilot, frames: int) -> Dictionary:
	var last: Dictionary = {}
	var acc: Dictionary = {"steps": 0, "mesh": 0, "time": 0.0, "walkers": {}, "speed": 0.0, "speed_n": 0}
	for i: int in frames:
		var before: float = float(_layer.get("_world_time"))
		await pilot.frames(1)
		var dt: float = float(_layer.get("_world_time")) - before
		for node: NPCNode in _layer.get_nodes():
			_anim_sample(node, dt, last, acc)
	var t: float = maxf(float(acc["time"]), 0.001)
	return {"fps": float(acc["steps"]) / t, "mesh_fps": float(acc["mesh"]) / t,
		"walkers": (acc["walkers"] as Dictionary).size(), "speed": float(acc["speed"]) / maxf(float(acc["speed_n"]), 1.0)}


func _anim_sample(node: NPCNode, dt: float, last: Dictionary, acc: Dictionary) -> void:
	var anim: String = str(node.get("_anim"))
	var frame: int = int(node.get("_frame"))
	var held: Array = node.get_meta(HELD_META, []) as Array
	var rec: Object = held[1] if held.size() > 1 else null
	var id: int = node.get_instance_id()
	var prev: Array = last.get(id, [])
	if anim == SOAK_WALK and not prev.is_empty() and str(prev[0]) == SOAK_WALK:
		acc["time"] = float(acc["time"]) + dt
		acc["steps"] = int(acc["steps"]) + posmod(frame - int(prev[1]), CharacterAnim.frame_count(SOAK_WALK))
		acc["mesh"] = int(acc["mesh"]) + (1 if rec != prev[2] else 0)
		(acc["walkers"] as Dictionary)[id] = true
		acc["speed"] = float(acc["speed"]) + float(node.get("_speed_mod"))
		acc["speed_n"] = int(acc["speed_n"]) + 1
	last[id] = [anim, frame, rec]


func _log_memory(label: String) -> void:
	var st: Dictionary = _painter.call("cache_stats")
	_log("%s | cache poses=%d %.1f MB pending=%d hits=%d misses=%d evicted=%d canon_raw=%d canon_sigs=%d resets=%d | objects=%d resources=%d static=%.1f MB render_buffers=%.1f MB video=%.1f MB" % [
		label, int(st["poses"]), float(st["bytes"]) / BYTES_PER_MB, int(st["pending"]), int(st["hits"]),
		int(st["misses"]), int(st["evicted"]), int(st.get("canon_raw", -1)), int(st.get("canon_sigs", -1)),
		int(st.get("resets", -1)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / BYTES_PER_MB,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MB])
