# character_perf_case.gd — Cuerpo de test_character_perf: cada pose es UNA malla (1 llamada de dibujo), el teselado reproduce la geometría del motor, respeta su presupuesto por fotograma, la caché LRU sus topes y un lienzo retiene las mallas que dibuja.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

## Headless (sin GPU): las llamadas de dibujo y los píxeles se miden en el escenario char_perf
## (tools/screenshot.sh <dir> char_perf). Aquí: API compatible, una orden por pose para todas
## las animaciones × escalones × rumbos × sentado × uniformes × tics, recuentos y posiciones del
## teselado frente a las fórmulas del motor, LRU por número y por bytes, retención, fotos, coste de
## grabar/vaciar, presupuesto de teselado por fotograma (lo que no cabe se dibuja con la lista de
## órdenes y el lienzo se redibuja solo), memo de claves lleno sin vaciar la caché e invalidación al
## cambiar de disfraz o de escalón.

const DIRS: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(1, -1), Vector2(0, -1),
	Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1)]
const UNIFORMS: Array[String] = ["", "security", "cleaning", "maintenance", "factory"]
## Firma pública de CharacterPainter que usan jugador, NPC e interfaz: nombre → nº de argumentos.
const PAINTER_API: Dictionary = {
	"appearance_from_seed": 4, "appearance_for_named": 2, "appearance_for_npc": 1, "draw": 4,
	"draw_portrait": 3, "pose_recording": 3, "prewarm": 5, "make_pose": 4, "seat_origin": 3,
	"anim_fps": 1, "anim_frames": 1, "cached_pose_count": 0, "clear_cache": 0, "uniform_for_occupation": 2,
	"uniform_for_disguise": 1, "tic_for_archetype": 1, "reserved_combos": 0, "hair_pool": 1,
	"presentation_for_name": 1,
}
const CANVAS_API: Dictionary = {
	"draw_colored_polygon": 2, "draw_polyline": 4, "draw_circle": 6, "draw_arc": 8, "draw_line": 5,
	"draw_rect": 4, "finish": 0, "size": 0, "replay": 1, "segments_for": 1,
}
const EPS := 0.0001
const WORKING_SET_CHARACTERS := 45
const WORKING_SET_FRAMES := 12
const MAX_RECORD_MS := 40.0
const TIMING_POSES := 60
const EVICT_PROBE_MAX := 4000
const MAX_EVICT_MS := 60.0
const BUDGET_WAIT_FRAMES := 60


## Multitud que dibuja varias poses nuevas en un fotograma y apunta cuántas siguen sin malla.
class Crowd extends Node2D:
	var apps: Array[Dictionary] = []
	var pending_log: Array[int] = []

	func _draw() -> void:
		var pending: int = 0
		for i: int in apps.size():
			var pose: Dictionary = CharacterPainter.make_pose("walk", i % 8, Vector2.DOWN, {"origin": Vector2(i * 40, 0)})
			CharacterPainter.draw(self, apps[i], int(apps[i]["tier"]), pose)
			if not CharacterPainter.pose_recording(apps[i], int(apps[i]["tier"]), pose).is_built():
				pending += 1
		pending_log.append(pending)


## Lienzo que dibuja una pose (o una foto) en su _draw.
class Probe extends Node2D:
	var app: Dictionary = {}
	var tier: int = 1
	var pose: Dictionary = {}
	var portrait: bool = false
	var drawn: int = 0

	func _draw() -> void:
		if portrait:
			CharacterPainter.draw_portrait(self, app, Rect2(0, 0, 120, 140))
		else:
			CharacterPainter.draw(self, app, tier, pose)
		drawn += 1


func run_case() -> void:
	check(new_run(), "database loaded")
	CharacterPainter.set_reference_mode(false)
	CharacterPainter.set_cache_limits(0, 0)
	CharacterPainter.set_tessellation_budget_ms(-1.0)
	_check_api()
	_check_one_order_per_pose()
	_check_canonical_keys()
	_check_key_memo()
	_check_invalidation()
	_check_line_geometry()
	_check_polyline_geometry()
	_check_round_geometry()
	_check_width_compensation()
	_check_reference_path()
	_check_lru()
	_check_byte_budget()
	await _check_hold()
	await _check_portraits()
	_check_working_set()
	_check_timings()
	await _check_budget()
	CharacterPainter.set_cache_limits(0, 0)
	CharacterPainter.set_tessellation_budget_ms(0.0)


func _methods(script: Script) -> Dictionary:
	var out: Dictionary = {}
	for m: Dictionary in script.get_script_method_list():
		out[str(m["name"])] = (m["args"] as Array).size()
	return out


func _check_api() -> void:
	var painter: Dictionary = _methods(load("res://src/entities/character_painter.gd") as Script)
	var missing: Array[String] = []
	for name: String in PAINTER_API:
		if int(painter.get(name, -1)) != int(PAINTER_API[name]):
			missing.append(name)
	check(missing.is_empty(), "CharacterPainter keeps its public signatures (%s)" % ", ".join(missing))
	var canvas: Dictionary = _methods(load("res://src/entities/character_canvas.gd") as Script)
	missing.clear()
	for name: String in CANVAS_API:
		if int(canvas.get(name, -1)) != int(CANVAS_API[name]):
			missing.append(name)
	check(missing.is_empty(), "CharacterCanvas keeps the CanvasItem drawing API of the painters (%s)" % ", ".join(missing))


## Todas las animaciones × escalones (rumbo, sentado, uniforme y tic rotando) + nominados: una
## sola orden (la malla) por personaje.
func _check_one_order_per_pose() -> void:
	CharacterPainter.clear_cache()
	var bad: Array[String] = []
	var total: int = 0
	var i: int = 0
	var start: int = Time.get_ticks_usec()
	for anim: String in CharacterAnim.CATALOGUE:
		for tier: int in range(1, 9):
			var app: Dictionary = CharacterPainter.appearance_from_seed(900 + i * 37, tier, false, "")
			app["uniform"] = UNIFORMS[i % UNIFORMS.size()]
			var pose: Dictionary = CharacterPainter.make_pose(anim, i % CharacterAnim.frame_count(anim),
					DIRS[i % DIRS.size()], {"tic": CharacterAnim.TICS[i % CharacterAnim.TICS.size()],
					"seated": i % 3 == 0, "look": DIRS[(i * 5) % DIRS.size()]})
			total += 1
			if not _is_single_mesh(CharacterPainter.pose_recording(app, tier, pose)):
				bad.append("%s/%d" % [anim, tier])
			i += 1
	for npc: NPCData in Database.get_all_named_npcs():
		var named: Dictionary = CharacterPainter.appearance_for_named(npc, 1 + i % 8)
		total += 1
		if not _is_single_mesh(CharacterPainter.pose_recording(named, 1 + i % 8,
				CharacterPainter.make_pose("walk", i % 8, DIRS[i % 8]))):
			bad.append(npc.id)
		i += 1
	var ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(total)
	print("[character_perf] %d poses recorded, %.2f ms per pose (tessellation + mesh upload)" % [total, ms])
	check(bad.is_empty(), "all %d poses (anims x tiers x facings x seated x uniforms x tics + named) are ONE mesh draw %s"
			% [total, str(bad.slice(0, 5))])
	check(ms < MAX_RECORD_MS, "recording a pose stays cheap (%.2f ms < %.0f ms)" % [ms, MAX_RECORD_MS])


func _is_single_mesh(rec: CharacterCanvas) -> bool:
	return rec != null and rec.is_built() and rec.size() == 1 and rec.get_mesh() != null \
			and rec.get_mesh().get_surface_count() == 1 and rec.triangle_count() > 0 \
			and rec.byte_size() == rec.vertex_count() * CharacterCanvas.VERTEX_BYTES + rec.triangle_count() * 6


## Línea suavizada del motor: quad central (anchura compensada) + 4 franjas + 4 esquinas.
func _check_line_geometry() -> void:
	var c: CharacterCanvas = CharacterCanvas.new()
	c.draw_line(Vector2.ZERO, Vector2(10, 0), Color(0.2, 0.4, 0.6), 2.0, true)
	c.tessellate()
	var pts: PackedVector2Array = c.pending_points()
	check(pts.size() == 16 and c.pending_indices().size() == 18 * 3,
			"AA line = 16 shared vertices / 18 triangles (engine: quad + 8 feather quads)")
	check(pts[0].is_equal_approx(Vector2(0, 0.5)) and pts[2].is_equal_approx(Vector2(10, -0.5)),
			"AA line width 2 is compensated to 1.0 (engine canvas_item_get_compensated_antialiasing_width)")
	check(pts[4].is_equal_approx(Vector2(0, 1.75)) and c.pending_colors()[4].a == 0.0,
			"AA line feather is 1.25 local units wide and fades to alpha 0")
	check_near(c.pending_colors()[0].r, 0.2 + 0.5 / 255.0, EPS, "vertex colours carry half a byte so 8-bit truncation rounds")
	var plain: CharacterCanvas = CharacterCanvas.new()
	plain.draw_line(Vector2.ZERO, Vector2(0, 10), Color.WHITE, 3.0)
	plain.tessellate()
	check(plain.pending_points().size() == 4 and plain.pending_indices().size() == 6, "plain line = one quad")


## Polilíneas: remates en los extremos, bucle si se cierra, unión en inglete.
func _check_polyline_geometry() -> void:
	var open: CharacterCanvas = CharacterCanvas.new()
	open.draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 10)]), Color.BLACK, 1.6, true)
	open.tessellate()
	check(open.pending_points().size() == 4 * 3 + 8 and open.pending_indices().size() == 26 * 3,
			"open AA polyline: middle strip with end caps + both feather strips sharing its edge vertices")
	var closed: CharacterCanvas = CharacterCanvas.new()
	var square: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(8, 8), Vector2(0, 8),
			Vector2.ZERO])
	closed.draw_polyline(square, Color.BLACK, 1.6, true)
	closed.tessellate()
	check(closed.pending_points().size() == 4 * 5 and closed.pending_indices().size() == 24 * 3,
			"closed AA polyline (first == last point) is a loop without end caps")
	var mitre: CharacterCanvas = CharacterCanvas.new()
	mitre.draw_polyline(PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 10)]), Color.BLACK, 4.0)
	mitre.tessellate()
	var m: PackedVector2Array = mitre.pending_points()
	check(m.size() == 6 and m[0].is_equal_approx(Vector2(0, -2)) and m[2].is_equal_approx(Vector2(12, -2))
			and m[3].is_equal_approx(Vector2(8, 2)), "polyline joint uses the engine's clamped bisector (mitre)")


## Círculos y arcos: abanico de 64 del motor si se suaviza; polígono de la grabación si no.
func _check_round_geometry() -> void:
	var aa: CharacterCanvas = CharacterCanvas.new()
	aa.draw_circle(Vector2(5, 5), 3.0, Color.RED, true, -1.0, true)
	aa.tessellate()
	check(aa.pending_points().size() == 65 + 1 + 65 and aa.pending_indices().size() == (64 + 128) * 3,
			"AA filled circle = engine 64-segment fan + feather strip")
	check_near(aa.pending_points()[0].x, 5.0 + 3.0 - 1.25 * 0.25, EPS, "AA circle radius shrinks a quarter feather")
	var flat: CharacterCanvas = CharacterCanvas.new()
	flat.draw_circle(Vector2.ZERO, 4.0, Color.RED)
	flat.tessellate()
	check(flat.pending_points().size() == CharacterCanvas.segments_for(4.0), "plain filled circle = recorded polygon")
	var arc: CharacterCanvas = CharacterCanvas.new()
	arc.draw_arc(Vector2.ZERO, 4.8, 0.0, TAU, 18, Color.BLACK, 1.4, true)
	arc.tessellate()
	check(arc.pending_points().size() == 4 * 18 and arc.pending_indices().size() == 3 * 3 * (2 * 18 - 2),
			"full AA arc closes into a loop like the engine polyline")
	var rect: CharacterCanvas = CharacterCanvas.new()
	rect.draw_rect(Rect2(0, 0, 4, 3), Color.BLUE)
	rect.tessellate()
	check(rect.pending_points().size() == 4 and rect.pending_indices().size() == 6, "filled rect = one quad")


func _check_width_compensation() -> void:
	check_near(CharacterCanvas.compensated_width(1.0), 0.5, EPS, "AA width 1.0 -> 0.5")
	check_near(CharacterCanvas.compensated_width(2.5), 1.25, EPS, "AA width 2.5 -> 1.25")
	check_near(CharacterCanvas.compensated_width(4.0), 2.825, EPS, "AA width 4.0 -> 2.825 (remap band)")
	check_near(CharacterCanvas.compensated_width(6.0), 5.375, EPS, "AA width 6.0 -> 5.375 (constant offset)")


## Camino de referencia (QA): la lista de órdenes anterior, muchas llamadas por personaje.
func _check_reference_path() -> void:
	var app: Dictionary = CharacterPainter.appearance_from_seed(5150, 6, false, "")
	var pose: Dictionary = CharacterPainter.make_pose("walk", 2, Vector2(1, 0.4))
	var mesh_rec: CharacterCanvas = CharacterPainter.pose_recording(app, 6, pose)
	CharacterPainter.set_reference_mode(true)
	var ref: CharacterCanvas = CharacterPainter.pose_recording(app, 6, pose)
	check(not ref.is_built() and ref.size() > 6 and ref.get_mesh() == null,
			"reference mode records the old per-stroke order list (%d orders vs 1 mesh)" % ref.size())
	CharacterPainter.set_reference_mode(false)
	check(CharacterPainter.cached_pose_count() == 0 and not CharacterPainter.is_reference_mode(),
			"switching paths empties the caches")
	check(_is_single_mesh(CharacterPainter.pose_recording(app, 6, pose)) and mesh_rec.size() == 1,
			"back to one mesh per pose")


## LRU: la pose que se sigue usando sobrevive; la menos usada se descarta; el tope se respeta.
func _check_lru() -> void:
	CharacterPainter.set_cache_limits(20, 1 << 20)
	var app: Dictionary = CharacterPainter.appearance_from_seed(6060, 3, false, "")
	var keep: CharacterCanvas = CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", 0, DIRS[0]))
	var early: CharacterCanvas = CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", 1, DIRS[0]))
	var peak: int = 0
	for i: int in 40:
		CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", i % 8, DIRS[1 + i / 8 % 7]))
		CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", 0, DIRS[0]))
		peak = maxi(peak, CharacterPainter.cached_pose_count())
	check(peak <= 20, "pose cache never exceeds its count limit (peak %d / 20)" % peak)
	check(CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", 0, DIRS[0])) == keep,
			"the pose in constant use survives eviction (LRU)")
	check(CharacterPainter.pose_recording(app, 3, CharacterPainter.make_pose("walk", 1, DIRS[0])) != early,
			"the least recently used pose was evicted")
	CharacterPainter.set_cache_limits(0, 0)


func _check_byte_budget() -> void:
	var app: Dictionary = CharacterPainter.appearance_from_seed(7070, 5, false, "")
	var one: int = CharacterPainter.pose_recording(app, 5, CharacterPainter.make_pose("idle", 0, DIRS[0])).byte_size()
	var budget_kb: int = maxi(one * 8 / 1024, 1)
	CharacterPainter.set_cache_limits(1000, budget_kb)
	var peak: int = 0
	for i: int in 40:
		CharacterPainter.pose_recording(app, 5, CharacterPainter.make_pose("walk", i % 8, DIRS[i / 8 % 8]))
		peak = maxi(peak, CharacterPainter.cached_mesh_bytes())
	check(peak <= budget_kb * 1024 + one * 2 and CharacterPainter.cached_mesh_bytes() <= budget_kb * 1024,
			"mesh bytes stay within cache_mallas_kb (%d B <= %d KB)" % [CharacterPainter.cached_mesh_bytes(), budget_kb])
	CharacterPainter.set_cache_limits(0, 0)


## Un lienzo retiene la malla que dibujó aunque la caché la descarte; al redibujar la suelta.
func _check_hold() -> void:
	CharacterPainter.set_cache_limits(2, 1 << 20)
	var probe: Probe = Probe.new()
	probe.app = CharacterPainter.appearance_from_seed(8080, 2, false, "")
	probe.tier = 2
	probe.pose = CharacterPainter.make_pose("idle", 0, DIRS[0])
	add_child(probe)
	await wait_frames(2)
	var first: CharacterCanvas = CharacterPainter.pose_recording(probe.app, 2, probe.pose)
	var watch: WeakRef = weakref(first)
	for i: int in 8:
		CharacterPainter.pose_recording(probe.app, 2, CharacterPainter.make_pose("walk", i, DIRS[3]))
	var held: Array = probe.get_meta(CharacterPainter.HELD_META, []) as Array
	check(probe.drawn > 0 and held.has(first) and first.get_mesh() != null,
			"an evicted pose that is still on screen stays alive (held by its canvas)")
	first = null
	held = []
	probe.pose = CharacterPainter.make_pose("walk", 5, DIRS[6])
	probe.queue_redraw()
	await wait_frames(2)
	check(watch.get_ref() == null, "after the canvas redraws, the evicted mesh is released")
	probe.queue_free()
	CharacterPainter.set_cache_limits(0, 0)


func _check_portraits() -> void:
	var probe: Probe = Probe.new()
	probe.portrait = true
	probe.app = CharacterPainter.appearance_for_named(Database.get_all_named_npcs()[0], 3)
	add_child(probe)
	await wait_frames(2)
	var rec: CharacterCanvas = CharacterPainter.portrait_recording(probe.app)
	check(probe.drawn > 0 and _is_single_mesh(rec) and CharacterPainter.cached_portrait_count() == 1,
			"portrait bust is one cached mesh (+ one background mesh per tier)")
	CharacterPainter.set_reference_mode(true)
	probe.queue_redraw()
	await wait_frames(2)
	check(not CharacterPainter.portrait_recording(probe.app).is_built(),
			"reference mode draws portraits with the old order list")
	CharacterPainter.set_reference_mode(false)
	probe.queue_free()


## Presupuesto de balance.json frente al conjunto de trabajo de la cafetería (45 personajes ×
## 12 fotogramas): cabe sin descartar poses en pantalla.
func _check_working_set() -> void:
	CharacterPainter.set_cache_limits(0, 0)
	var bytes: int = 0
	var verts: int = 0
	var n: int = 0
	for i: int in 24:
		var tier: int = 1 + i % 8
		var app: Dictionary = CharacterPainter.appearance_from_seed(9900 + i * 11, tier, false, "")
		var rec: CharacterCanvas = CharacterPainter.pose_recording(app, tier,
				CharacterPainter.make_pose(["sit", "chat", "walk", "idle"][i % 4], i % 8, DIRS[i % 8], {"seated": i % 4 < 2}))
		bytes += rec.byte_size()
		verts += rec.vertex_count()
		n += 1
	var avg: float = float(bytes) / float(n)
	var budget: int = Database.get_balance_int(CharacterPainter.CACHE_BYTES_PATH) * 1024
	var need: float = avg * WORKING_SET_CHARACTERS * WORKING_SET_FRAMES
	print("[character_perf] avg pose mesh: %.0f vertices, %.1f KB; cafeteria working set %.1f MB; budget %.1f MB"
			% [float(verts) / n, avg / 1024.0, need / 1048576.0, float(budget) / 1048576.0])
	check(need <= float(budget), "cache_mallas_kb holds the cafeteria working set (45 x 12 poses)")
	check(Database.get_balance_int(CharacterPainter.CACHE_PATH) >= WORKING_SET_CHARACTERS * WORKING_SET_FRAMES,
			"cache_poses holds the cafeteria working set")


## Coste de grabar una pose (malla frente a lista de órdenes) y tirón del vaciado LRU con los
## topes reales de balance.json.
func _check_timings() -> void:
	CharacterPainter.set_cache_limits(0, 0)
	var mesh_ms: float = _record_ms(11000)
	CharacterPainter.set_reference_mode(true)
	var ref_ms: float = _record_ms(11000)
	CharacterPainter.set_reference_mode(false)
	print("[character_perf] record per pose: mesh %.2f ms, reference (old order list) %.2f ms" % [mesh_ms, ref_ms])
	var worst: float = 0.0
	var evicted: bool = false
	var i: int = 0
	while not evicted and i < EVICT_PROBE_MAX:
		var app: Dictionary = CharacterPainter.appearance_from_seed(20000 + i, 1 + i % 8, false, "")
		var before: int = CharacterPainter.cached_pose_count()
		var start: int = Time.get_ticks_usec()
		CharacterPainter.pose_recording(app, 1 + i % 8, CharacterPainter.make_pose("walk", i % 8, DIRS[i % 8]))
		worst = float(Time.get_ticks_usec() - start) / 1000.0
		evicted = CharacterPainter.cached_pose_count() < before
		i += 1
	print("[character_perf] LRU eviction after %d poses (%.1f MB): recording + eviction took %.2f ms"
			% [i, float(CharacterPainter.cached_mesh_bytes()) / 1048576.0, worst])
	check(evicted and worst < MAX_EVICT_MS, "LRU eviction with the real limits is a small hitch (%.2f ms)" % worst)


func _record_ms(seed_base: int) -> float:
	var start: int = Time.get_ticks_usec()
	for i: int in TIMING_POSES:
		var tier: int = 1 + i % 8
		var app: Dictionary = CharacterPainter.appearance_from_seed(seed_base + i * 3, tier, false, "")
		CharacterPainter.pose_recording(app, tier, CharacterPainter.make_pose(["walk", "idle", "sit_type", "chat"][i % 4],
				i % 8, DIRS[i % 8]))
	return float(Time.get_ticks_usec() - start) / 1000.0 / float(TIMING_POSES)


## Presupuesto de teselado: lo que no cabe en el fotograma se dibuja con la lista de órdenes y el
## lienzo se redibuja solo, fotograma a fotograma, hasta que todas sus poses tienen malla.
func _check_budget() -> void:
	CharacterPainter.clear_cache()
	CharacterPainter.set_tessellation_budget_ms(0.001)
	var crowd: Crowd = Crowd.new()
	for i: int in 6:
		crowd.apps.append(CharacterPainter.appearance_from_seed(12000 + i * 7, 1 + i, false, ""))
	add_child(crowd)
	var waited: int = 0
	while waited < BUDGET_WAIT_FRAMES and (crowd.pending_log.is_empty() or crowd.pending_log[-1] > 0):
		await wait_frames(1)
		waited += 1
	check(not crowd.pending_log.is_empty() and crowd.pending_log[0] > 0,
			"over budget, new poses are drawn with their order list first (%s)" % str(crowd.pending_log))
	check(crowd.pending_log.size() > 1 and crowd.pending_log[-1] == 0,
			"the canvas redraws itself until every pose is a mesh (%d passes)" % crowd.pending_log.size())
	crowd.queue_free()
	CharacterPainter.set_tessellation_budget_ms(-1.0)


## Claves canónicas: poses brutas con el mismo esqueleto comparten grabación; las que cambian
## el dibujo no.
func _check_canonical_keys() -> void:
	CharacterPainter.clear_cache()
	var app: Dictionary = CharacterPainter.appearance_from_seed(13130, 2, false, "")
	var held_a: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 0, DIRS[0]))
	var held_b: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 1, DIRS[0]))
	check(held_a == held_b, "a key frame held for two frames (idle 0 and 1) shares one recording")
	var deaf: String = "headphones_never_turns_head"
	var tic_a: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 0, DIRS[0],
			{"tic": deaf, "tic_frame": 0}))
	var tic_b: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 0, DIRS[0],
			{"tic": deaf, "tic_frame": 7}))
	check(tic_a == tic_b, "tic frames that change nothing share one recording")
	var sweep: String = "slow_wide_gaze_sweep"
	var sw_a: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 0, DIRS[0],
			{"tic": sweep, "tic_frame": 0}))
	var sw_b: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("idle", 0, DIRS[0],
			{"tic": sweep, "tic_frame": 3}))
	var walk_a: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("walk", 0, DIRS[0]))
	var walk_b: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("walk", 1, DIRS[0]))
	var turned: CharacterCanvas = CharacterPainter.pose_recording(app, 2, CharacterPainter.make_pose("walk", 0, DIRS[2]))
	check(sw_a != sw_b and walk_a != walk_b and walk_a != turned,
			"poses that change the drawing (head sweep, walk phase, facing) keep their own recordings")


## Memo de claves lleno: se vacía solo el memo (la caché de poses sigue entera), los ids no se
## reutilizan (una pose nueva nunca recibe la grabación de otra) y la pose recién usada sigue en caché.
func _check_key_memo() -> void:
	CharacterPainter.clear_cache()
	CharacterPainter.set_key_memo_limits(3, 2)
	var resets: int = int(CharacterPainter.cache_stats()["resets"])
	var app: Dictionary = CharacterPainter.appearance_from_seed(14140, 4, false, "")
	var recs: Array[CharacterCanvas] = []
	for i: int in 6:
		recs.append(CharacterPainter.pose_recording(app, 4, CharacterPainter.make_pose("walk", i, DIRS[0])))
	var distinct: bool = true
	for i: int in recs.size():
		for j: int in range(i + 1, recs.size()):
			distinct = distinct and recs[i] != recs[j]
	resets = int(CharacterPainter.cache_stats()["resets"]) - resets
	check(distinct and CharacterPainter.cached_pose_count() == recs.size() and resets > 0,
			"a full key memo empties only itself: the pose cache stays and ids are never reused (%d resets)" % resets)
	check(CharacterPainter.pose_recording(app, 4, CharacterPainter.make_pose("walk", 5, DIRS[0])) == recs[5],
			"the pose just used is still found after the memo resets")
	CharacterPainter.set_key_memo_limits(0, 0)


## Cambiar la apariencia (disfraz, escalón) da otra grabación, también si se modifica el mismo
## diccionario después de dibujarlo; volver a la de antes recupera la suya.
func _check_invalidation() -> void:
	CharacterPainter.clear_cache()
	var app: Dictionary = CharacterPainter.appearance_from_seed(15150, 2, false, "")
	var pose: Dictionary = CharacterPainter.make_pose("walk", 3, DIRS[1])
	var plain: CharacterCanvas = CharacterPainter.pose_recording(app, 2, pose)
	app["uniform"] = CharacterPainter.uniform_for_disguise("uniform_cleaning")
	var disguised: CharacterCanvas = CharacterPainter.pose_recording(app, 2, pose)
	var promoted: CharacterCanvas = CharacterPainter.pose_recording(app, 3, pose)
	app["uniform"] = ""
	var back: CharacterCanvas = CharacterPainter.pose_recording(app, 2, pose)
	check(disguised != plain and promoted != disguised and promoted != plain and back == plain,
			"disguise and tier changes (even mutating the same appearance) get their own recordings; undoing them finds the old one")
