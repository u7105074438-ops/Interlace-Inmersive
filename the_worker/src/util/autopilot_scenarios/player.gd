# player.gd (escenario) — El jugador en el ala 3B: caminar, sigilo, agachado, esprint, acto, ascenso y disfraz.
# PROPIETARIO DE: los nodos temporales del escenario (planta, jugador, figuras de ambiente, anillos de ruido).
# ESCUCHA: EventBus.noise_emitted (para dibujar los anillos de ruido de QA).
extends Node

## tools/screenshot.sh /tmp/shots_player player
## Capturas: player_idle (indicación contextual), player_walk, player_sneak, player_crouch,
## player_sprint (anillos = radio de ruido de cada pisada), player_act (forzar cajón),
## player_tier5 (silueta tras un ascenso), player_disguise (uniforme de limpieza), player_phone.

const FLOOR := 3
const ROOM := "wing_3b"
## Cajón del jefe de ala (mesa abierta, sin cubículo): indicación contextual y acto de forzarlo.
const TARGET_DRAWER := "lasker_drawer"
## Punto de partida de los desplazamientos: celdas desde la esquina inferior izquierda de la sala.
const AISLE_CELLS := Vector2(7.0, 2.6)
const MOVE_SECONDS := 1.1
const SETTLE_FRAMES := 6
const HUD_SIZE := 26
## Silla del cubículo (FurniturePainter._draw_cubicle): centro del hueco + desplazamiento, en px de referencia.
const CHAIR_OFFSET_REF := Vector2(6.0, -16.0)
const REFERENCE_CELL := 48.0
const RING_LIFE := 0.9
const RING_COLORS: Dictionary = {"sneak": Color("#7ee081"), "crouch": Color("#7ee081"),
	"walk": Color("#ffd23f"), "sprint": Color("#ff5a4e"), "still": Color.WHITE}


## Compañero de trabajo dibujado con CharacterPainter (ambiente; el NPC real es de otro constructor).
class Figure extends Node2D:
	var app: Dictionary = {}
	var tier: int = 1
	var anim: String = "sit_type"
	var facing: Vector2 = Vector2.UP
	var tic: String = ""
	var seated: bool = false
	## Desplazamiento del dibujo respecto al nodo (sentados: el nodo ordena por el borde del mueble).
	var origin: Vector2 = Vector2.ZERO
	var _frame: int = 0
	var _clock: float = 0.0

	func _process(delta: float) -> void:
		_clock += delta
		var fps: float = CharacterPainter.anim_fps(anim)
		if fps > 0.0 and _clock >= 1.0 / fps:
			_clock = 0.0
			_frame = maxi(CharacterAnim.next_frame(anim, _frame), 0)
			queue_redraw()

	func _draw() -> void:
		CharacterPainter.draw(self, app, tier, CharacterPainter.make_pose(anim, _frame, facing,
				{"tic": tic, "tic_frame": _frame, "origin": origin, "seated": seated}))


## Anillos de ruido: cada pisada del jugador dibuja su radio (metros × px por celda).
class NoiseRings extends Node2D:
	var cell: float = 48.0
	var rings: Array[Dictionary] = []

	func add(pos: Vector2, radius: float, color: Color) -> void:
		rings.append({"pos": pos, "r": radius * cell, "age": 0.0, "color": color})

	func _process(delta: float) -> void:
		for ring: Dictionary in rings:
			ring["age"] = float(ring["age"]) + delta
		rings = rings.filter(func(r: Dictionary) -> bool: return float(r["age"]) < RING_LIFE)
		queue_redraw()

	func _draw() -> void:
		for ring: Dictionary in rings:
			var t: float = float(ring["age"]) / RING_LIFE
			var col: Color = ring["color"]
			var radius: float = float(ring["r"]) * (0.6 + 0.4 * t)
			draw_arc(ring["pos"], radius, 0.0, TAU, 64, Color(col, 0.9 * (1.0 - t)), 3.0, true)


var _player: Player = null
var _streamer: FloorStreamer = null
var _rings: NoiseRings = null
var _hud: Label = null
var _last_noise: float = 0.0


func run(pilot: Autopilot) -> void:
	Database.load_all()
	PlayerState.reset_for_new_run()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	_build_world()
	_build_hud()
	EventBus.noise_emitted.connect(_on_noise)
	await pilot.frames(SETTLE_FRAMES)
	await _idle_shot(pilot)
	await _move_shot(pilot, "walk", Vector2.RIGHT)
	await _move_shot(pilot, "sneak", Vector2(1, 1).normalized())
	await _move_shot(pilot, "crouch", Vector2.LEFT)
	await _move_shot(pilot, "sprint", Vector2.RIGHT)
	await _act_shot(pilot)
	await _progress_shots(pilot)
	await _phone_shot(pilot)


func _build_world() -> void:
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(FLOOR)
	_rings = NoiseRings.new()
	_rings.cell = RoomBuilder.cell_px()
	_rings.z_index = 50
	add_child(_rings)
	_player = (load("res://scenes/world/player.tscn") as PackedScene).instantiate() as Player
	_streamer.get_actor_layer().add_child(_player)
	_streamer.set_player(_player)
	_place_player()
	_add_coworkers()


## Pasillo inferior despejado del ala (sin cubículos que tapen al jugador).
func _place_player() -> void:
	var rect: Rect2 = _streamer.get_room_rect_px(ROOM)
	var cell: float = RoomBuilder.cell_px()
	_player.global_position = rect.position + Vector2(cell * AISLE_CELLS.x, rect.size.y - cell * AISLE_CELLS.y)
	_player.velocity = Vector2.ZERO
	var cam: PlayerCamera = _player.get_node_or_null("Camera") as PlayerCamera
	if cam != null:
		cam.set_bounds(_streamer.get_floor_rect_px())
		cam.snap_to_target()


## Compañeros sentados en las sillas de sus cubículos (orden Y del nivel de actores, sin trucos de z).
func _add_coworkers() -> void:
	var seats: Array[Dictionary] = _streamer.get_seats_in_room(ROOM)
	for i: int in seats.size():
		if i % 3 == 1 or str(seats[i]["type"]) != "cubicle":
			continue
		var fig: Figure = Figure.new()
		fig.tier = 1
		fig.app = CharacterPainter.appearance_from_seed(9100 + i * 37, fig.tier, false, "")
		fig.facing = seats[i]["facing"]
		fig.anim = ["sit_type", "type_intense", "phone_sneak", "sit"][i % 4]
		fig.seated = true
		fig._frame = i % 8
		var seat_at: Vector2 = CharacterPainter.seat_origin(_chair_center(seats[i]), fig.app, fig.tier)
		fig.position = Vector2(seat_at.x, maxf(seat_at.y, _furniture_bottom(seats[i]) + 1.0))
		fig.origin = seat_at - fig.position
		_streamer.get_actor_layer().add_child(fig)
	var chat: Figure = Figure.new()
	chat.app = CharacterPainter.appearance_from_seed(9555, 1, false, "")
	chat.anim = "chat"
	chat.tic = "leans_toward_interlocutor"
	chat.facing = Vector2(-1, 0.3).normalized()
	chat.position = _streamer.get_spawn_point(ROOM) + Vector2(RoomBuilder.cell_px() * 3.0, RoomBuilder.cell_px() * 1.5)
	_streamer.get_actor_layer().add_child(chat)


## Borde inferior (px) del mueble del puesto: el sentado ordena justo delante de su propio cubículo.
func _furniture_bottom(seat: Dictionary) -> float:
	var room: RoomData = Database.get_room(ROOM)
	var index: int = int(seat["furniture_index"])
	if room == null or index < 0 or index >= room.furniture.size():
		return (seat["pos"] as Vector2).y
	var fp: Rect2i = FurniturePainter.footprint(room.furniture[index])
	return _streamer.get_room_rect_px(ROOM).position.y + float(fp.end.y) * RoomBuilder.cell_px()


## Centro del asiento de la silla dibujada en el cubículo (mesa arriba, silla abajo).
func _chair_center(seat: Dictionary) -> Vector2:
	var room: RoomData = Database.get_room(ROOM)
	var index: int = int(seat["furniture_index"])
	if room == null or index < 0 or index >= room.furniture.size() or (seat["facing"] as Vector2) != Vector2.UP:
		return seat["pos"]
	var cell: float = RoomBuilder.cell_px()
	var k: float = cell / REFERENCE_CELL
	var fp: Rect2i = FurniturePainter.footprint(room.furniture[index])
	var r: Rect2 = Rect2(_streamer.get_room_rect_px(ROOM).position + Vector2(fp.position) * cell, Vector2(fp.size) * cell)
	return Vector2(r.get_center().x, r.end.y) + CHAIR_OFFSET_REF * k


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(32, 24)
	_hud.add_theme_font_size_override("font_size", HUD_SIZE)
	_hud.add_theme_color_override("font_outline_color", CharacterStyle.OUTLINE)
	_hud.add_theme_constant_override("outline_size", 8)
	layer.add_child(_hud)


func _on_noise(pos: Vector2, radius: float, source: String) -> void:
	if source != Player.NOISE_SOURCE:
		return
	_last_noise = radius
	_rings.add(pos, radius, RING_COLORS.get(_player.movement_mode(), Color.WHITE))
	_update_hud()


func _update_hud() -> void:
	var mode: String = _player.movement_mode()
	var text: String = tr("QA_PLAYER_TITLE") + "  ·  " + tr("MOVE_MODE_" + mode.to_upper())
	if mode != Player.MODE_STILL:
		text += "  ·  " + tr("QA_PLAYER_NOISE") % _last_noise
	_hud.text = text


# ─── Capturas ──────────────────────────────────────────────────

func _stand_at_target(side_view: bool) -> void:
	var cell: float = RoomBuilder.cell_px()
	for item: Interactable in _streamer.get_interactables_in_room(ROOM):
		if item.interact_id != TARGET_DRAWER:
			continue
		if side_view:
			_player.global_position = item.global_position + Vector2(cell * 1.1, cell * 0.35)
			_player.set_facing(Vector2.LEFT)
		else:
			_player.global_position = item.global_position + Vector2(0, cell * 0.9)
			_player.set_facing(Vector2.UP)


func _idle_shot(pilot: Autopilot) -> void:
	_stand_at_target(false)
	_update_hud()
	await pilot.seconds(0.4)
	await pilot.shot("player_idle")


func _move_shot(pilot: Autopilot, mode: String, dir: Vector2) -> void:
	_place_player()
	_player.set_sneak_held(mode == "sneak")
	_player.set_crouching(mode == "crouch")
	_player.set_virtual_input(dir, mode == "sprint")
	await pilot.seconds(MOVE_SECONDS)
	_update_hud()
	await pilot.shot("player_" + mode)
	_player.set_virtual_input(Vector2.ZERO, false)
	_player.set_sneak_held(false)
	_player.set_crouching(false)
	await pilot.seconds(0.3)


func _act_shot(pilot: Autopilot) -> void:
	_stand_at_target(true)
	_player.begin_act("drawer_forced", 3.0)
	await pilot.seconds(0.6)
	_update_hud()
	_hud.text += "  ·  " + tr("QA_PLAYER_ACT") % tr("ANIM_DRAWER")
	await pilot.shot("player_act")
	_player.end_act()


func _progress_shots(pilot: Autopilot) -> void:
	PlayerState.set_occupation("a10_marketing_director", "qa")
	_place_player()
	_player.set_virtual_input(Vector2(1, 0.25).normalized(), false)
	await pilot.seconds(0.7)
	await pilot.shot("player_tier5")
	PlayerState.set_occupation("email_worker_3b", "qa")
	PlayerState.set_disguise("uniform_cleaning")
	_place_player()
	_player.set_virtual_input(Vector2(1, -0.3).normalized(), false)
	await pilot.seconds(0.7)
	await pilot.shot("player_disguise")
	_player.set_virtual_input(Vector2.ZERO, false)
	PlayerState.set_disguise("")


func _phone_shot(pilot: Autopilot) -> void:
	get_window().size = Vector2i(1200, 540)
	var cam: PlayerCamera = _player.get_node_or_null("Camera") as PlayerCamera
	if cam != null:
		cam.set_zoom_level(Database.get_balance_int(PlayerCamera.MOBILE_LEVEL_PATH))
	_place_player()
	_player.set_virtual_input(Vector2.RIGHT, false)
	await pilot.seconds(0.8)
	await pilot.shot("player_phone")
	_player.set_virtual_input(Vector2.ZERO, false)
