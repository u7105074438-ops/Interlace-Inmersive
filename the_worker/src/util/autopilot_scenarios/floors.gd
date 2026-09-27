# floors.gd (escenario) — Capturas de plantas completas y primer plano del ala 3B (PASO 7 / PASO 40).
# PROPIETARIO DE: los nodos temporales del escenario (streamer, cámara, figura de referencia).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_floors floors
## Plantas 3 (ala 3B, paleta the_pit), 1, 12, 16, 20 (oro/mármol/cristal), -2 (archivo muerto),
## fábrica (100) y exterior (200) enteras (más PB, S1, S3, azotea y P7 como extra); después primer plano de wing_3b a zoom de juego
## (1 celda = 48 px) con una figura de referencia en el grupo "player" junto a un cajón.

const SHOT_FLOORS: Array[int] = [3, 1, 12, 16, 20, -2, 100, 200, 0, -1, -3, 21, 7]
const FIT_MARGIN := 0.97
const SETTLE_FRAMES := 4
const CLOSE_UP_ZOOM := 1.0
const PHONE_ZOOM := 0.8
## Primeros planos extra a zoom de juego para revisar siluetas por banda.
const CLOSE_ROOMS: Array[String] = ["ceo_office", "investor_lounge", "assembly_line", "dead_archive", "street",
		"cafeteria", "aurora_room", "garage", "server_room", "supermarket"]


class ScaleFigure extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(3, 4), 15.0, Color(0, 0, 0, 0.25))
		draw_colored_polygon(PackedVector2Array([Vector2(-15, 2), Vector2(15, 2), Vector2(11, -22), Vector2(-11, -22)]),
				Color("#3a5a8a"))
		draw_circle(Vector2(0, -30), 10.0, Color("#e2b48f"))
		draw_arc(Vector2(0, -30), 10.0, 0.0, TAU, 20, Color("#1b1b1b"), 2.0)


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
		await pilot.shot("floor_%s" % _label(f))
	await _close_up(pilot, streamer, cam)
	for room_id: String in CLOSE_ROOMS:
		await _room_shot(pilot, streamer, cam, room_id)


func _room_shot(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D, room_id: String) -> void:
	var room: RoomData = Database.get_room(room_id)
	if room == null:
		return
	streamer.load_floor(room.floor)
	cam.zoom = Vector2(CLOSE_UP_ZOOM, CLOSE_UP_ZOOM)
	cam.position = streamer.get_room_rect_px(room_id).get_center()
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("room_%s" % room_id)


func _label(f: int) -> String:
	return ("m%d" % absi(f)) if f < 0 else str(f)


func _fit(cam: Camera2D, rect: Rect2) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var z: float = minf(view.x / rect.size.x, view.y / rect.size.y) * FIT_MARGIN
	cam.zoom = Vector2(z, z)
	cam.position = rect.get_center()


func _close_up(pilot: Autopilot, streamer: FloorStreamer, cam: Camera2D) -> void:
	streamer.load_floor(3)
	var figure: ScaleFigure = ScaleFigure.new()
	figure.add_to_group("player")
	streamer.get_actor_layer().add_child(figure)
	var seat: Dictionary = streamer.get_seats_in_room("wing_3b")[1]
	figure.position = seat["pos"] + Vector2(0, 40)
	cam.zoom = Vector2(CLOSE_UP_ZOOM, CLOSE_UP_ZOOM)
	cam.position = streamer.get_room_rect_px("wing_3b").get_center() + Vector2(0, 60)
	await pilot.frames(SETTLE_FRAMES * 4)
	await pilot.shot("wing_3b_closeup")
	cam.zoom = Vector2(PHONE_ZOOM, PHONE_ZOOM)
	cam.position = streamer.get_room_rect_px("corridors_low@3").get_center()
	figure.position = streamer.get_spawn_point("corridors_low@3")
	await pilot.frames(SETTLE_FRAMES * 4)
	await pilot.shot("corridor_3_camera")
	figure.queue_free()
