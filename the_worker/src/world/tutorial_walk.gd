# tutorial_walk.gd — Segunda parte del primer día (§13.8): el asistente de Recursos Humanos acompaña al jugador de la sala de formación a su mesa y, sin advertirlo, le cuenta todo lo necesario para delinquir (tarjeta, llaves, fichaje, zonas restringidas, horario de comida).
# PROPIETARIO DE: el guía en escena (su figurante), su ruta en la planta cargada y los avisos dados (tarjeta vista, espera, planta equivocada).
# ESCUCHA: EventBus.floor_changed (el guía «sube» con el jugador: reaparece a su lado en la planta de la oficina).
class_name TutorialWalk
extends RefCounted

## Guía: el asistente de RR. HH. generado (ocupación tutorial.guia.ocupacion que no es nominado; si
## no hay, cualquiera de esa ocupación). Mientras actúa, su nodo real está retirado (director).
## Cada frase (BEATS) se muestra en la tarjeta de diálogo mientras el guía camina a un punto de su
## ruta (fracción `at`: 0 = donde empieza, 1 = el ascensor en la planta de la sala de formación, la
## mesa del jugador en la de la oficina) con correa: si el jugador se queda atrás, le espera
## mirándole. Una frase termina con su tiempo de lectura, el guía en su punto y, en «elevator», el
## jugador en la planta de la oficina (por el ascensor, la escalera o lo que sea). Presupuesto
## agotado en «elevator» o «desk»: el guía «le lleva del codo» (fundido y mesa).
## Frases de la planta de la oficina esperan a que el jugador esté en ella.

const LEG_START := "start"
const LEG_OFFICE := "office"
const BEATS: Array[Dictionary] = [
	{"id": "hello", "line": "TUT_GUIDE_HELLO", "leg": LEG_START, "at": 0.0},
	{"id": "card", "line": "TUT_GUIDE_CARD", "leg": LEG_START, "at": 0.45},
	{"id": "keys", "line": "TUT_GUIDE_KEYS", "leg": LEG_START, "at": 0.8},
	{"id": "elevator", "line": "TUT_GUIDE_ELEVATOR", "leg": LEG_START, "at": 1.0},
	{"id": "clockin", "line": "TUT_GUIDE_CLOCKIN", "leg": LEG_OFFICE, "at": 0.3},
	{"id": "restricted", "line": "TUT_GUIDE_RESTRICTED", "leg": LEG_OFFICE, "at": 0.6},
	{"id": "lunch", "line": "TUT_GUIDE_LUNCH", "leg": LEG_OFFICE, "at": 0.85},
	{"id": "desk", "line": "TUT_GUIDE_DESK", "leg": LEG_OFFICE, "at": 1.0},
]
const ELEVATOR_KIND := "elevator"
const INVENTORY_KIND := "inventory"
const LUNCH_BAND := "lunch"
const AFTER_LUNCH_BAND := "work_afternoon"
const CORRIDOR_PREFIX := "corridors"

var guide_id: String = ""
var guide: TutorialActor = null
var _d: TutorialDirector = null
var _route: PackedVector2Array = PackedVector2Array()
var _route_floor: int = -9999
var _card_seen: bool = false
var _wait_warned: bool = false
var _waiting_since: float = -1.0
var _beat: String = ""
## Tiempo activo que aún se espera a que el jugador llegue a la planta de su oficina (un solo fondo).
var _climb_left: float = -1.0


func _init(director: TutorialDirector) -> void:
	_d = director
	guide_id = pick_guide()


## El asistente de RR. HH. generado (el nominado del puesto, Amelia Cole, no hace acogidas).
static func pick_guide() -> String:
	var occupation: String = str(Database.get_balance(TutorialDirector.B + "guia.ocupacion"))
	var fallback: String = ""
	for npc: NPCRuntime in NPCDirector.get_npcs_by_occupation(occupation):
		if not NPCDirector.is_active(npc.id):
			continue
		if not npc.is_named:
			return npc.id
		fallback = npc.id if fallback.is_empty() else fallback
	return fallback


func guide_name() -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(guide_id)
	return npc.name if npc != null else ""


func get_beat() -> String:
	return _beat


func run() -> void:
	_d.resume_clock()
	EventBus.floor_changed.connect(_on_floor_changed)
	_spawn_at_door()
	for beat: Dictionary in BEATS:
		if _d.is_ended():
			break
		await _run_beat(beat)
	if not _d.is_ended():
		await _goodbye()
	if EventBus.floor_changed.is_connected(_on_floor_changed):
		EventBus.floor_changed.disconnect(_on_floor_changed)


# ─── Frases ───────────────────────────────────────────────────

func _run_beat(beat: Dictionary) -> void:
	var id: String = str(beat["id"])
	_beat = id
	_d.set_step("walk_" + id)
	if str(beat["leg"]) == LEG_OFFICE and not await _reach_office_floor():
		await _escort()
	var text: String = beat_line(id)
	_d.speak(guide_id, text)
	_walk_to(_target(beat))
	var shown_at: float = _d.get_elapsed()
	var reading: float = _d.read_time(Tutorial.plain(text))
	_wait_warned = false
	var done: bool = await _d.wait_for(func() -> bool: return _beat_done(id, shown_at, reading), _d.budget("guia.presupuesto." + id))
	if not done and not _d.is_ended() and (id == "elevator" or id == "desk"):
		await _escort()


func _beat_done(id: String, shown_at: float, reading: float) -> bool:
	_watch_player(id)
	if _d.get_elapsed() - shown_at < reading:
		return false
	if guide != null and is_instance_valid(guide) and guide.is_moving():
		return false
	if id == "elevator":
		return _d.player_floor() == _d.office_floor()
	return true


## Texto de cada frase con sus datos (teclas, listas, horas, plantas).
func beat_line(id: String) -> String:
	var touch: bool = _d.root.ui != null and _d.root.ui.is_touch_mode()
	match id:
		"hello":
			return Tutorial.line("TUT_GUIDE_HELLO", [Tutorial.escape(guide_name())])
		"card":
			return Tutorial.line("TUT_GUIDE_CARD", [Tutorial.keycaps(["inventory"], touch, "TUT_TOUCH_INVENTORY")])
		"keys":
			var rooms: Array[RoomData] = _d.key_rooms()
			var list: String = _d.room_list(rooms) if not rooms.is_empty() else Tutorial.line("TUT_KEYS_FALLBACK")
			return Tutorial.line("TUT_GUIDE_KEYS", [list])
		"elevator":
			return Tutorial.line("TUT_GUIDE_ELEVATOR", [Tutorial.keycaps(["interact"], touch, "TUT_TOUCH_INTERACT"), _d.office_floor()])
		"restricted":
			_d.deliver_notes()
			return Tutorial.line("TUT_GUIDE_RESTRICTED", [_d.room_list(_d.restricted_zones())])
		"lunch":
			return Tutorial.line("TUT_GUIDE_LUNCH", [UITheme.format_hour(GameClock.get_band_start_hour(LUNCH_BAND)),
					UITheme.format_hour(GameClock.get_band_start_hour(AFTER_LUNCH_BAND))])
		"desk":
			return Tutorial.line("TUT_GUIDE_DESK", [Tutorial.keycaps(["interact"], touch, "TUT_TOUCH_INTERACT")])
	return Tutorial.line("TUT_GUIDE_CLOCKIN")


## Reacciones durante una frase: la tarjeta en el inventario, la espera del guía.
func _watch_player(id: String) -> void:
	if id == "card" and not _card_seen and _inventory_open():
		_card_seen = true
		_d.toast("TUT_GUIDE_CARD_SEEN", [], ToastStack.KIND_GOOD)
	if guide == null or not is_instance_valid(guide) or not guide.is_waiting():
		_waiting_since = -1.0
		return
	if _waiting_since < 0.0:
		_waiting_since = _d.get_elapsed()
	elif not _wait_warned and _d.get_elapsed() - _waiting_since >= _d.budget("guia.segundos_espera_aviso"):
		_wait_warned = true
		guide.emote(NPCBubble.KIND_EXCLAIM, _d.budget("guia.segundos_espera_aviso"))
		_d.toast("TUT_GUIDE_WAIT", [], ToastStack.KIND_WARN)


func _inventory_open() -> bool:
	var top: Control = _d.root.ui.get_top_modal() if _d.root.ui != null else null
	return top != null and str(top.get_meta(UIRoot.META_KIND, "")) == INVENTORY_KIND


## Espera a que el jugador esté en la planta de la oficina (fondo común guia.presupuesto.subir para
## todo el paseo). false = no llegó a tiempo.
func _reach_office_floor() -> bool:
	if _d.player_floor() == _d.office_floor():
		return true
	if _climb_left < 0.0:
		_climb_left = _d.budget("guia.presupuesto.subir")
	_d.toast("TUT_OBJ_FLOOR", [_d.office_floor()])
	var t0: float = _d.get_elapsed()
	var arrived: bool = await _d.wait_for(func() -> bool: return _d.player_floor() == _d.office_floor(), _climb_left)
	_climb_left = maxf(_climb_left - (_d.get_elapsed() - t0), 0.0)
	return arrived


# ─── Guía y ruta ──────────────────────────────────────────────

## El guía entra por la puerta de la sala de formación; su ruta acaba en el ascensor.
func _spawn_at_door() -> void:
	var room: String = _d.tutorial_room()
	var door: Vector2 = _door_point(room)
	guide = _d.spawn_actor(guide_id, door, _d.bal_f("guia.velocidad_celdas"))
	if guide == null:
		return
	guide.set_leash(_d.root.player, _d.bal_f("guia.distancia_seguir_celdas") * _d.cell())
	_route_floor = _d.player_floor()
	_route = _d.root.streamer.find_path_to_point(door, _elevator_point())


## Frente a la puerta de la sala que da al pasillo (dentro de la sala), o su punto de aparición.
func _door_point(room_id: String) -> Vector2:
	var streamer: FloorStreamer = _d.root.streamer
	var rect: Rect2 = streamer.get_room_rect_px(room_id)
	var best: Dictionary = {}
	for door: Dictionary in streamer.get_plan().get("doors", []):
		var other: String = str(door["b"]) if str(door["a"]) == room_id else (str(door["a"]) if str(door["b"]) == room_id else "")
		if other.is_empty():
			continue
		if best.is_empty() or DatabaseSystem.get_room_base_id(other).begins_with(CORRIDOR_PREFIX):
			best = door
	if best.is_empty():
		return streamer.get_spawn_point(room_id)
	var p: Vector2 = streamer.cell_to_world(best["cell"])
	return streamer.nearest_walkable_point(p + (rect.get_center() - p).normalized() * _d.cell())


## Centro del ascensor más cercano a la sala de formación.
func _elevator_point() -> Vector2:
	var streamer: FloorStreamer = _d.root.streamer
	var from: Vector2 = streamer.get_room_rect_px(_d.tutorial_room()).get_center()
	var best: Vector2 = streamer.get_spawn_point(_d.tutorial_room())
	var best_d: float = INF
	for t: Dictionary in streamer.get_plan().get("transit", []):
		if str(t["kind"]) != ELEVATOR_KIND:
			continue
		var p: Vector2 = streamer.get_spawn_point(str(t["room_id"]))
		if p.distance_to(from) < best_d:
			best_d = p.distance_to(from)
			best = p
	return best


## Junto a la mesa del jugador, en el pasillo del cubículo.
func desk_side_point() -> Vector2:
	var seat: Vector2 = _d.seat_point()
	return _d.root.streamer.nearest_walkable_point(seat + Vector2(_d.bal_f("guia.lado_mesa_celdas") * _d.cell(), 0.0))


func _target(beat: Dictionary) -> Vector2:
	if guide == null or not is_instance_valid(guide):
		return Vector2.INF
	var office_leg: bool = str(beat["leg"]) == LEG_OFFICE
	if office_leg != (_d.player_floor() == _d.office_floor()) or _route.is_empty():
		return Vector2.INF
	if str(beat["id"]) == "hello":
		var p: Vector2 = _d.root.player.global_position
		return p + (guide.global_position - p).normalized() * _d.bal_f("guia.distancia_saludo_celdas") * _d.cell()
	return point_along(_route, float(beat["at"]))


func _walk_to(point: Vector2) -> void:
	if point.is_finite() and guide != null and is_instance_valid(guide):
		guide.walk_to(point)


## Punto a la fracción `t` (0-1) de la longitud de una ruta.
static func point_along(route: PackedVector2Array, t: float) -> Vector2:
	if route.is_empty():
		return Vector2.INF
	var total: float = 0.0
	for i: int in range(1, route.size()):
		total += route[i - 1].distance_to(route[i])
	var goal: float = clampf(t, 0.0, 1.0) * total
	for i: int in range(1, route.size()):
		var seg: float = route[i - 1].distance_to(route[i])
		if goal <= seg and seg > 0.0:
			return route[i - 1].lerp(route[i], goal / seg)
		goal -= seg
	return route[route.size() - 1]


## Cambio de planta: el guía de la planta anterior desaparece; en la de la oficina reaparece junto
## al jugador (ha subido con él) en cuanto el viaje le deja allí.
func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	_d.drop_actor(guide)
	guide = null
	if _d.is_ended():
		return
	if new_floor == _d.office_floor():
		_respawn_in_office.call_deferred()
	else:
		_d.toast("TUT_GUIDE_WRONG_FLOOR", [guide_name(), _d.office_floor()], ToastStack.KIND_WARN)


func _respawn_in_office() -> void:
	if _d.is_ended() or _d.player_floor() != _d.office_floor():
		return
	var p: Vector2 = _d.root.player.global_position
	var at: Vector2 = _d.root.npc_layer.free_point_near(p, 2, hash(guide_id)) if _d.root.npc_layer != null else p
	if not at.is_finite():
		at = p
	guide = _d.spawn_actor(guide_id, at, _d.bal_f("guia.velocidad_celdas"))
	if guide == null:
		return
	guide.set_leash(_d.root.player, _d.bal_f("guia.distancia_seguir_celdas") * _d.cell())
	guide.face_point(p)
	_route_floor = _d.player_floor()
	_route = _d.root.streamer.find_path_to_point(at, desk_side_point())


## «Te lleva del codo»: fundido y a la mesa (planta de la oficina: el guía reaparece allí).
func _escort() -> void:
	_d.toast("TUT_GUIDE_ESCORT", [guide_name()])
	await _d.ui.fade(true, 0.0 if _d.instant else _d.bal_f("segundos_fundido"))
	_d.place_player_at_desk()
	await _d.root.get_tree().process_frame
	await _d.ui.fade(false, 0.0 if _d.instant else _d.bal_f("segundos_fundido"))


## Se despide y vuelve a RR. HH.: sale por la puerta de la oficina y el personaje vuelve a su agenda.
func _goodbye() -> void:
	_d.set_step("walk_goodbye")
	if guide == null or not is_instance_valid(guide):
		return
	guide.set_leash(null, 0.0)
	guide.emote(NPCBubble.KIND_TALK, _d.budget("guia.segundos_despedida"))
	guide.walk_to(_door_point(_d.office_room()))
	await _d.wait_for(func() -> bool: return not is_instance_valid(guide) or not guide.is_moving(), _d.budget("guia.segundos_despedida"))
	_d.release_actor(guide)
	guide = null
