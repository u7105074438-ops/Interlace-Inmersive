# door.gd — Puerta con control de acceso (lector, cerradura antigua, servicio) o compuerta de torno.
# PROPIETARIO DE: su estado abierta/cerrada, su bloqueo y su temporizador de cierre.
# ESCUCHA: nada (su sensor detecta cuerpos de las capas físicas 4 jugador y 5 NPC).
class_name Door
extends StaticBody2D

## Cerrada bloquea el paso y la vista (capa 1; la compuerta de torno, capa 3). Comportamiento:
##  - desbloqueada: se abre sola al acercarse cualquiera y se cierra al quedar libre;
##  - bloqueada: se abre para los NPC (llevan su tarjeta o llave); para el jugador consulta
##    `policy` (Callable(door, body) -> bool, la fija FloorStreamer; p. ej. acreditación + registro
##    del lector) y, si la deniega, emite access_requested y sigue cerrada;
##  - open_for(s): abierta al menos s segundos (tarjeta robada, forzar cerradura, torno);
##    quien va detrás cruza mientras sigue abierta (colarse, §5.6).
## Nunca se cierra con un cuerpo en el hueco. Grupo "doors". El dibujo (hoja, lector, aleta) es propio.

signal state_changed(door: Door, is_open: bool, locked: bool)
## El jugador llegó a la puerta bloqueada y la política no le abrió (HUD, sonido de lector rojo).
signal access_requested(door: Door, body: Node2D)
## La puerta se abrió con este cuerpo junto a ella (registros de paso, colarse detrás de alguien).
signal door_used(door: Door, body: Node2D)

const GROUP := "doors"
const KIND_READER := "reader"
const KIND_OLD_LOCK := "old_lock"
const KIND_SERVICE := "service"
const KIND_TURNSTILE := "turnstile"
const PLAYER_GROUP := "player"
const NPC_GROUP := "npcs"
const LAYER_WALLS := 1
const LAYER_LOW := 3
const LAYER_PLAYER := 4
const LAYER_NPC := 5
const Z_DOOR := -8
const ANIM_SPEED := 6.0
const C_LED_LOCKED := Color("#ff4d4d")
const C_LED_OPEN := Color("#5dff8a")
const C_GLASS := Color(0.62, 0.85, 0.95, 0.55)

var door_id: String = ""
var kind: String = KIND_READER
var room_a: String = ""
var room_b: String = ""
var clearance: int = 0
var special_access: Array[String] = []
var special_mode: String = ""
var vertical: bool = false
var span_px: float = 96.0
var thickness_px: float = 14.0
var into_positive: bool = true
var cell_px: float = 48.0
var leaf_color: Color = Color("#6d7a5c")
var outline_color: Color = Color("#2c2f28")
var policy: Callable = Callable()
var _locked: bool = true
var _open: bool = false
var _open_left: float = 0.0
var _close_wait: float = 0.0
var _anim: float = 0.0
var _occupants: Array[Node2D] = []
var _asked: Dictionary = {}
var _shape: CollisionShape2D = null


## `data`: {id, kind, a, b, clearance, special_access, special_mode, vertical, span, thickness,
## into_positive, locked, cell, leaf, outline}. `origin_px`: inicio del hueco en el padre.
func setup(data: Dictionary, origin_px: Vector2) -> void:
	door_id = str(data["id"])
	kind = str(data["kind"])
	room_a = str(data.get("a", ""))
	room_b = str(data.get("b", ""))
	clearance = int(data.get("clearance", 0))
	special_access.assign(data.get("special_access", []))
	special_mode = str(data.get("special_mode", ""))
	vertical = bool(data.get("vertical", false))
	span_px = float(data["span"])
	thickness_px = float(data["thickness"])
	into_positive = bool(data.get("into_positive", true))
	cell_px = float(data.get("cell", cell_px))
	leaf_color = data.get("leaf", leaf_color)
	outline_color = data.get("outline", outline_color)
	_locked = bool(data.get("locked", true))
	position = origin_px
	name = "Door_%s" % door_id.validate_node_name()
	_build_body()
	_build_sensor()
	add_to_group(GROUP)


func _build_body() -> void:
	collision_layer = 1 << ((LAYER_LOW if kind == KIND_TURNSTILE else LAYER_WALLS) - 1)
	collision_mask = 0
	z_as_relative = false
	z_index = Z_DOOR
	_shape = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = gap_rect().size
	_shape.shape = box
	_shape.position = gap_rect().get_center()
	add_child(_shape)


## Sensor a ambos lados del hueco (profundidad mundo.puertas.sensor celdas).
func _build_sensor() -> void:
	var sensor: Area2D = Area2D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = (1 << (LAYER_PLAYER - 1)) | (1 << (LAYER_NPC - 1))
	sensor.monitorable = false
	var depth: float = Database.get_balance_float("mundo.puertas.sensor") * cell_px
	var r: Rect2 = gap_rect().grow_side(SIDE_LEFT if vertical else SIDE_TOP, depth) \
			.grow_side(SIDE_RIGHT if vertical else SIDE_BOTTOM, depth)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = r.size
	shape.shape = box
	shape.position = r.get_center()
	sensor.add_child(shape)
	sensor.body_entered.connect(_on_body_entered)
	sensor.body_exited.connect(_on_body_exited)
	add_child(sensor)


## Hueco de paso en coordenadas locales (el grosor del muro centrado en la línea).
func gap_rect() -> Rect2:
	if vertical:
		return Rect2(-thickness_px * 0.5, 0.0, thickness_px, span_px)
	return Rect2(0.0, -thickness_px * 0.5, span_px, thickness_px)


# ─── API ──────────────────────────────────────────────────────

func is_locked() -> bool:
	return _locked


func is_open() -> bool:
	return _open


func set_locked(locked: bool) -> void:
	if locked == _locked:
		return
	_locked = locked
	state_changed.emit(self, _open, _locked)
	queue_redraw()


## Abre al menos `seconds` (≤ 0: mundo.puertas.apertura_s) aunque esté bloqueada.
func open_for(seconds: float = 0.0) -> void:
	var span: float = seconds if seconds > 0.0 else Database.get_balance_float("mundo.puertas.apertura_s")
	_open_left = maxf(_open_left, span)
	_set_open(true)


func close() -> void:
	_open_left = 0.0
	if not _body_in_gap():
		_set_open(false)


# ─── Comportamiento ───────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if not _occupants.has(body):
		_occupants.append(body)


func _on_body_exited(body: Node2D) -> void:
	_occupants.erase(body)
	_asked.erase(body.get_instance_id())


func _physics_process(delta: float) -> void:
	_occupants = _occupants.filter(func(b: Node2D) -> bool: return is_instance_valid(b))
	_open_left = maxf(0.0, _open_left - delta)
	var wanted: bool = _open_left > 0.0 or _wants_open()
	if wanted:
		_close_wait = Database.get_balance_float("mundo.puertas.cierre_s")
		_set_open(true)
	elif _open:
		_close_wait -= delta
		if _close_wait <= 0.0 and not _body_in_gap():
			_set_open(false)
	var target: float = 1.0 if _open else 0.0
	if not is_equal_approx(_anim, target):
		_anim = move_toward(_anim, target, delta * ANIM_SPEED)
		queue_redraw()


## Alguien presente que puede pasar: cualquiera si está desbloqueada; NPC siempre; el jugador si
## la política se lo concede (se consulta una vez por aproximación).
func _wants_open() -> bool:
	var wanted: bool = false
	for body: Node2D in _occupants:
		if not _locked or body.is_in_group(NPC_GROUP):
			wanted = true
		elif body.is_in_group(PLAYER_GROUP) and not _asked.has(body.get_instance_id()):
			_asked[body.get_instance_id()] = true
			if policy.is_valid() and bool(policy.call(self, body)):
				_open_left = maxf(_open_left, Database.get_balance_float("mundo.puertas.apertura_s"))
				wanted = true
			else:
				access_requested.emit(self, body)
	return wanted


func _body_in_gap() -> bool:
	var gap: Rect2 = gap_rect().grow(cell_px * 0.35)
	for body: Node2D in _occupants:
		if gap.has_point(to_local(body.global_position)):
			return true
	return false


func _set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	_shape.set_deferred("disabled", open)
	if open:
		for body: Node2D in _occupants:
			door_used.emit(self, body)
	state_changed.emit(self, _open, _locked)
	queue_redraw()


# ─── Dibujo ───────────────────────────────────────────────────

func _draw() -> void:
	if kind == KIND_TURNSTILE:
		_draw_flap()
		return
	var along: Vector2 = Vector2(0, 1) if vertical else Vector2(1, 0)
	var across: Vector2 = (Vector2(1, 0) if vertical else Vector2(0, 1)) * (1.0 if into_positive else -1.0)
	var t: float = thickness_px * 0.8
	var hinge: Vector2 = Vector2.ZERO
	var closed_dir: Vector2 = along
	var dir: Vector2 = closed_dir.lerp(across, _anim).normalized()
	var tip: Vector2 = hinge + dir * span_px * 0.96
	if _anim > 0.05:
		draw_arc(hinge, span_px * 0.96, along.angle(), dir.angle(), 12, Color(outline_color, 0.35), 1.5)
	var side: Vector2 = Vector2(-dir.y, dir.x) * t * 0.5
	var leaf: PackedVector2Array = [hinge - side, tip - side, tip + side, hinge + side]
	draw_colored_polygon(leaf, leaf_color)
	draw_polyline(PackedVector2Array([leaf[0], leaf[1], leaf[2], leaf[3], leaf[0]]), outline_color, 2.0)
	draw_circle(hinge + dir * span_px * 0.82, t * 0.28, Color("#d9d2c0"))
	var led: Vector2 = hinge + along * (span_px + thickness_px * 0.9) - across * thickness_px * 0.9
	draw_circle(led, 3.2, C_LED_LOCKED if _locked and not _open else C_LED_OPEN)


## Aleta de cristal del torno: cruza la calle cerrada y se recoge al abrir.
func _draw_flap() -> void:
	var gap: Rect2 = gap_rect()
	var reach: float = lerpf(gap.size.x * 0.82, gap.size.x * 0.1, _anim)
	var flap: Rect2 = Rect2(gap.position.x + gap.size.x * 0.3, gap.get_center().y - 3.0, reach, 6.0)
	draw_rect(flap, C_GLASS)
	draw_rect(flap, outline_color, false, 1.5)
	draw_circle(Vector2(gap.position.x + gap.size.x * 0.3, gap.get_center().y - 10.0), 3.0,
			C_LED_LOCKED if _locked and not _open else C_LED_OPEN)
