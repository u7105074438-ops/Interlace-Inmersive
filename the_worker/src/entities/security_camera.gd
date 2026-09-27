# security_camera.gd — Cámara de videovigilancia: barrido, cuña de visión tenue y registro del jugador.
# PROPIETARIO DE: su ángulo de barrido, su estado activo y el enfriamiento de su última grabación.
# ESCUCHA: nada (consulta la posición del jugador del grupo "player").
class_name SecurityCamera
extends Node2D

## Contrato: camera_id, room_id, is_player_in_view(pos) -> bool, set_active(bool), is_active().
## Emite EventBus.camera_recorded_player(camera_id, room_id, día) al entrar el jugador en su campo
## (flanco de subida, con enfriamiento camaras.enfriamiento_grabacion). Grupo "security_cameras":
## un apagón (§22.1 electrical_room) puede usar call_group("security_cameras", "set_active", false).
## Visión: alcance camaras.alcance celdas, apertura camaras.angulo, barrido ±camaras.barrido/2 a
## camaras.velocidad_barrido º/s; la línea de visión la cortan muros (capa 1) y muebles altos (capa 2).
## Cuña (§14.1 legibilidad): camaras.rayos rayos con refinado en los saltos (bordes de puerta y
## jambas nítidos, sin astillas a través de muros); rojo de seguridad (camaras.color_cuna) con más
## alfa sobre suelos claros (the_throne) y borde marcado; set_wedge_colors(banda) lo ajusta.

signal player_spotted(camera_id: String)

const GROUP := "security_cameras"
const PLAYER_GROUP := "player"
const LOS_MASK := 0b11
const Z_CAMERA := 30
const C_BODY := Color("#2b2f36")
const C_BODY_LIGHT := Color("#59616b")
const C_LENS := Color("#0d1116")
const C_LED := Color("#ff4040")
const C_OUTLINE := Color("#111317")
const BLINK_SPEED := 2.0

var camera_id: String = ""
var room_id: String = ""
var base_rotation: float = 0.0
var cell_px: float = 48.0
var _active: bool = true
var _range_px: float = 0.0
var _fov: float = 0.0
var _sweep: float = 0.0
var _speed: float = 0.0
var _phase: float = 0.0
var _angle: float = 0.0
var _cooldown: float = 0.0
var _check_timer: float = 0.0
var _seeing: bool = false
var _wedge: PackedVector2Array = []
var _wedge_fill: Color = Color(1, 0.2, 0.15, 0.12)
var _wedge_edge: Color = Color(1, 0.2, 0.15, 0.5)
var _wedge_alert: Color = Color(1, 0.2, 0.15, 0.28)
var _time: float = 0.0
var _player: Node2D = null


## `rotation_deg`: grados horario, 0 = mira al sur (convención de §27).
func setup(p_id: String, p_room_id: String, p_cell_px: float, center_px: Vector2, rotation_deg: float) -> void:
	camera_id = p_id
	room_id = p_room_id
	cell_px = p_cell_px
	base_rotation = rotation_deg
	position = center_px
	name = "Cam_%s" % p_id.validate_node_name()
	z_as_relative = false
	z_index = Z_CAMERA
	_range_px = Database.get_balance_float("camaras.alcance") * p_cell_px
	_fov = deg_to_rad(Database.get_balance_float("camaras.angulo"))
	_sweep = deg_to_rad(Database.get_balance_float("camaras.barrido"))
	_speed = deg_to_rad(Database.get_balance_float("camaras.velocidad_barrido"))
	_phase = float(hash(p_id) % 1000) / 1000.0 * TAU
	_angle = _current_angle()
	add_to_group(GROUP)


func is_active() -> bool:
	return _active


## Colores de la cuña según la banda (record de art_bands): más opaca sobre suelos claros.
func set_wedge_colors(band_record: Dictionary) -> void:
	var rgb: Array = Database.get_balance("camaras.color_cuna")
	var base: Color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	var floor_c: Color = Color(str(band_record.get("palette", {}).get("floor", "#808080")))
	var light: bool = floor_c.get_luminance() >= Database.get_balance_float("camaras.luminancia_clara")
	var fill_a: float = Database.get_balance_float("camaras.alfa_cuna_clara" if light else "camaras.alfa_cuna_oscura")
	_wedge_fill = Color(base.darkened(0.15) if light else base.lightened(0.15), fill_a)
	_wedge_edge = Color(_wedge_fill, Database.get_balance_float("camaras.alfa_borde"))
	_wedge_alert = Color(base, Database.get_balance_float("camaras.alfa_cuna_alerta"))


func set_active(active: bool) -> void:
	_active = active
	_seeing = false
	queue_redraw()


## Dirección actual de la cámara (vector unitario, coordenadas de mundo).
func get_facing() -> Vector2:
	return Vector2.DOWN.rotated(_angle)


## true si `pos` (mundo) está dentro del alcance, la apertura y la línea de visión.
func is_player_in_view(pos: Vector2) -> bool:
	if not _active or not is_inside_tree():
		return false
	var to: Vector2 = pos - global_position
	if to.length() > _range_px or absf(get_facing().angle_to(to)) > _fov * 0.5:
		return false
	return _ray_hit(global_position, pos) == pos


func _current_angle() -> float:
	var swing: float = 0.0
	if _sweep > 0.0 and _speed > 0.0:
		swing = sin(_phase + _time * _speed / maxf(0.001, _sweep * 0.5)) * _sweep * 0.5
	return deg_to_rad(base_rotation) + swing


func _physics_process(delta: float) -> void:
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if not _active:
		return
	_angle = _current_angle()
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = Database.get_balance_float("camaras.intervalo_comprobacion")
		_rebuild_wedge()
		_check_player()
	queue_redraw()


func _check_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D
	var now: bool = _player != null and is_player_in_view(_player.global_position)
	if now and not _seeing and _cooldown <= 0.0:
		_cooldown = Database.get_balance_float("camaras.enfriamiento_grabacion")
		EventBus.camera_recorded_player.emit(camera_id, room_id, GameClock.get_day())
		player_spotted.emit(camera_id)
	_seeing = now


## Primer punto de impacto del rayo (o `to` si no choca con muros ni muebles altos).
func _ray_hit(from: Vector2, to: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return to
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, LOS_MASK)
	query.hit_from_inside = false
	var hit: Dictionary = space.intersect_ray(query)
	return to if hit.is_empty() else (hit["position"] as Vector2)


## Contorno de visión: camaras.rayos rayos y, donde dos vecinos difieren más de
## camaras.salto_refinado celdas, bisección (camaras.refinado niveles) para bordes nítidos.
func _rebuild_wedge() -> void:
	var rays: int = maxi(2, Database.get_balance_int("camaras.rayos"))
	var depth: int = Database.get_balance_int("camaras.refinado")
	var facing: Vector2 = get_facing()
	var pts: PackedVector2Array = [Vector2.ZERO]
	var prev_a: float = -_fov * 0.5
	var prev: Vector2 = _cast(facing, prev_a)
	pts.append(prev)
	for i: int in range(1, rays + 1):
		var a: float = -_fov * 0.5 + _fov * i / rays
		var hit: Vector2 = _cast(facing, a)
		_refine(pts, facing, prev_a, prev, a, hit, depth)
		pts.append(hit)
		prev_a = a
		prev = hit
	_wedge = pts


## Punto local donde acaba el rayo de ángulo `a` respecto a `facing`.
func _cast(facing: Vector2, a: float) -> Vector2:
	return to_local(_ray_hit(global_position, global_position + facing.rotated(a) * _range_px))


func _refine(pts: PackedVector2Array, facing: Vector2, a0: float, p0: Vector2, a1: float, p1: Vector2,
		depth: int) -> void:
	var jump: float = Database.get_balance_float("camaras.salto_refinado") * cell_px
	if depth <= 0 or absf(p0.length() - p1.length()) < jump:
		return
	var mid: float = (a0 + a1) * 0.5
	var pm: Vector2 = _cast(facing, mid)
	_refine(pts, facing, a0, p0, mid, pm, depth - 1)
	pts.append(pm)
	_refine(pts, facing, mid, pm, a1, p1, depth - 1)


func _draw() -> void:
	if _active and _wedge.size() >= 3:
		draw_colored_polygon(_wedge, _wedge_alert if _seeing else _wedge_fill)
		var edge: PackedVector2Array = _wedge.duplicate()
		edge.append(_wedge[0])
		draw_polyline(edge, _wedge_alert if _seeing else _wedge_edge, 2.0)
	_draw_body()


## Cuerpo de la cámara (camaras.tamano_cuerpo celdas): soporte al muro, carcasa, lente y piloto.
func _draw_body() -> void:
	var facing: Vector2 = get_facing()
	var side: Vector2 = Vector2(-facing.y, facing.x)
	var s: float = cell_px * Database.get_balance_float("camaras.tamano_cuerpo")
	draw_circle(Vector2(2, 3), s * 1.3, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(Vector2(-s * 0.5, -s * 0.5), Vector2(s, s)), C_BODY)
	draw_circle(Vector2.ZERO, s * 0.9, C_BODY_LIGHT)
	var body: PackedVector2Array = [-facing * s * 0.6 + side * s * 0.8, -facing * s * 0.6 - side * s * 0.8,
			facing * s * 1.6 - side * s * 0.6, facing * s * 1.6 + side * s * 0.6]
	draw_colored_polygon(body, C_BODY)
	var loop: PackedVector2Array = body.duplicate()
	loop.append(body[0])
	draw_polyline(loop, C_OUTLINE, 1.5)
	draw_circle(facing * s * 1.6, s * 0.45, C_LENS)
	if _active and fmod(_time * BLINK_SPEED, 1.0) < 0.5:
		draw_circle(-facing * s * 0.2 + side * s * 0.4, s * 0.22, C_LED)
