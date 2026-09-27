# floors.gd (escenario) — Capturas de plantas completas y primeros planos de juego (PASO 7 / PASO 40).
# PROPIETARIO DE: los nodos temporales del escenario (streamer, cámara, figuras de referencia).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_floors floors
## Plantas 3 (ala 3B, paleta the_pit), 1, 12, 16, 20 (oro/mármol/cristal), -2 (archivo muerto),
## fábrica (100), exterior (200), PB (vestíbulo + tornos), S1, S3, azotea y P7 enteras; después a
## zoom de juego (1 celda = 48 px): ala 3B con compañeros sentados EXACTAMENTE en el punto de su
## asiento (get_seats_in_room → pos) y el jugador en el suyo, call center (puestos espalda con
## espalda), control de tornos, puertas con lector (cerrada/abierta), cuñas de cámara en P3 y P20,
## y un recorrido de salas por banda. Imprime "[perf]" (llamadas de dibujo, primitivas y ms por
## fotograma) de cada planta a vista completa y a zoom de juego.

const SHOT_FLOORS: Array[int] = [3, 1, 12, 16, 20, -2, 100, 200, 0, -1, -3, 21, 7, 2]
const FIT_MARGIN := 0.97
const SETTLE_FRAMES := 4
const PERF_FRAMES := 12
const CLOSE_UP_ZOOM := 1.0
const PHONE_ZOOM := 0.8
const SEATED_ANIMS: Array[String] = ["sit_type", "type_intense", "sit", "phone_sneak"]
## Primeros planos extra a zoom de juego para revisar siluetas por banda.
const CLOSE_ROOMS: Array[String] = ["ceo_office", "investor_lounge", "assembly_line", "dead_archive", "street",
		"cafeteria", "aurora_room", "garage", "server_room", "supermarket", "p1_toilets", "main_elevator_1@3"]


## Figura de CharacterPainter con su origen en el nodo (sin trucos de z ni desplazamientos).
class Figure extends Node2D:
	var app: Dictionary = {}
	var tier: int = 1
	var anim: String = "idle"
	var facing: Vector2 = Vector2.DOWN
	var seated: bool = false

	func _draw() -> void:
		CharacterPainter.draw(self, app, tier, CharacterPainter.make_pose(anim, 0, facing, {"seated": seated}))


func run(pilot: Autopilot) -> void:
	Database.load_all()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	for f: int in SHOT_FLOORS:
		streamer.load_floor(f)
		_fit(cam, streamer.get_floor_rect_px())
		await pilot.frames(SETTLE_FRAMES)
		await _perf(pilot, "F%d overview" % f)
		await pilot.shot("floor_%s" % _label(f))
		cam.zoom = Vector2(CLOSE_UP_ZOOM, CLOSE_UP_ZOOM)
		await _perf(pilot, "F%d gameplay" % f)
	await _wing_3b(pilot, streamer, cam)
	await _call_center(pilot, streamer, cam)
	await _turnstiles(pilot, streamer, cam)
	await _cameras(pilot, streamer, cam)
	for room_id: String in CLOSE_ROOMS:
		await _room_shot(pilot, streamer, cam, room_id)


func _room_shot(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D, room_id: String) -> void:
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return
	streamer.load_floor(room.floor if not room.is_transversal() else int(room_id.get_slice("@", 1)))
	cam.zoom = Vector2(CLOSE_UP_ZOOM, CLOSE_UP_ZOOM)
	cam.position = streamer.get_room_rect_px(room_id).get_center()
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("room_%s" % room_id.replace("@", "_at_"))


func _label(f: int) -> String:
	return ("m%d" % absi(f)) if f < 0 else str(f)


func _fit(cam: Camera2D, rect: Rect2) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var z: float = minf(view.x / rect.size.x, view.y / rect.size.y) * FIT_MARGIN
	cam.zoom = Vector2(z, z)
	cam.position = rect.get_center()


## Coste de dibujo del fotograma: llamadas, primitivas y ms medios de PERF_FRAMES fotogramas.
func _perf(pilot: Autopilot, label: String) -> void:
	await pilot.frames(2)
	var start: int = Time.get_ticks_usec()
	await pilot.frames(PERF_FRAMES)
	var ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / PERF_FRAMES
	print("[perf] %s draws=%d prims=%d frame_ms=%.1f" % [label,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), ms])


# ─── Primeros planos ──────────────────────────────────────────

## Ala 3B: compañeros sentados en el punto exacto de su asiento, el jugador en el suyo y un
## compañero de pie en el pasillo (PASO 7: doce cubículos gris verdoso).
func _wing_3b(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D) -> void:
	streamer.load_floor(3)
	var figures: Array[Figure] = _seat_everyone(streamer, "wing_3b", 3)
	var walker: Figure = _figure(streamer, streamer.get_spawn_point("wing_3b") + Vector2(0, 150), 7777, 1, "walk", false)
	figures.append(walker)
	cam.zoom = Vector2(CLOSE_UP_ZOOM, CLOSE_UP_ZOOM)
	cam.position = streamer.get_room_rect_px("wing_3b").get_center() + Vector2(0, 40)
	await pilot.frames(SETTLE_FRAMES * 3)
	await pilot.shot("wing_3b_closeup")
	cam.zoom = Vector2(PHONE_ZOOM * 0.6, PHONE_ZOOM * 0.6)
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("wing_3b_phone")
	_free(figures)


## Figuras sentadas en cada asiento de la sala (salvo uno de cada `skip`) con su pose de trabajo.
func _seat_everyone(streamer: FloorStreamer, room_id: String, skip: int) -> Array[Figure]:
	var out: Array[Figure] = []
	var seats: Array[Dictionary] = streamer.get_seats_in_room(room_id)
	for i: int in seats.size():
		if skip > 0 and i % skip == skip - 1 and str(seats[i]["owner"]) != "player_start":
			continue
		var tier: int = 1
		var app: Dictionary = CharacterPainter.appearance_from_seed(4100 + i * 53, tier, false, "")
		var at: Vector2 = CharacterPainter.seat_origin(seats[i]["pos"], app, tier)
		var fig: Figure = _figure(streamer, at, 4100 + i * 53, tier, SEATED_ANIMS[i % SEATED_ANIMS.size()], true)
		fig.facing = seats[i]["facing"]
		out.append(fig)
	return out


func _figure(streamer: FloorStreamer, pos: Vector2, look: int, tier: int, anim: String, seated: bool) -> Figure:
	var fig: Figure = Figure.new()
	fig.app = CharacterPainter.appearance_from_seed(look, tier, false, "")
	fig.tier = tier
	fig.anim = anim
	fig.seated = seated
	fig.add_to_group("player")
	streamer.get_actor_layer().add_child(fig)
	fig.global_position = pos
	return fig


func _free(figures: Array[Figure]) -> void:
	for fig: Figure in figures:
		fig.queue_free()


## Call center: filas apiladas espalda con espalda y todos los puestos ocupados.
func _call_center(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D) -> void:
	streamer.load_floor(2)
	var figures: Array[Figure] = _seat_everyone(streamer, "call_center", 0)
	cam.zoom = Vector2(CLOSE_UP_ZOOM * 0.8, CLOSE_UP_ZOOM * 0.8)
	cam.position = streamer.get_room_rect_px("call_center").get_center() + Vector2(-260, -120)
	await pilot.frames(SETTLE_FRAMES * 3)
	await pilot.shot("call_center_closeup")
	_free(figures)


## Planta baja: control de tornos (compuerta, barandillas, tornos) y puertas con lector.
func _turnstiles(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D) -> void:
	streamer.load_floor(0)
	cam.zoom = Vector2(CLOSE_UP_ZOOM * 0.75, CLOSE_UP_ZOOM * 0.75)
	cam.position = streamer.get_room_rect_px("turnstiles").get_center() + Vector2(0, 60)
	var gate: Door = streamer.get_door_by_id("turnstile_gate_2")
	if gate != null:
		gate.open_for(30.0)
	var monitor: Door = streamer.get_door_node("turnstiles", "monitor_room")
	await pilot.frames(SETTLE_FRAMES * 4)
	await pilot.shot("turnstiles_closeup")
	if monitor != null:
		monitor.open_for(30.0)
	cam.position = streamer.get_room_rect_px("monitor_room").get_center()
	await pilot.frames(SETTLE_FRAMES * 4)
	await pilot.shot("reader_door_open")


## Cuñas de visión de cámara sobre suelo oscuro (pasillo de P3) y claro (P20, mármol).
func _cameras(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D) -> void:
	streamer.load_floor(3)
	cam.zoom = Vector2(PHONE_ZOOM, PHONE_ZOOM)
	cam.position = streamer.get_room_rect_px("corridors_low@3").get_center()
	await pilot.frames(SETTLE_FRAMES * 6)
	await pilot.shot("corridor_3_camera")
	streamer.load_floor(20)
	cam.position = streamer.get_room_rect_px("corridors_high@20").get_center() + Vector2(-400, 0)
	await pilot.frames(SETTLE_FRAMES * 6)
	await pilot.shot("f20_camera_wedge")
