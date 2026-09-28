# closing_time.gd — Cierre del edificio (§5.6 «Salida: ocultarse para permanecer en el edificio»): avisos antes de las 19:00 y, al empezar la franja nocturna, el vigilante acompaña fuera a quien siga dentro sin esconderse.
# PROPIETARIO DE: los avisos dados hoy, la jornada ya cerrada y el desalojo pendiente.
# ESCUCHA: time_band_changed, day_advanced, run_started, run_loaded.
class_name ClosingTime
extends Node

## GameRoot lo añade con setup(root). Reglas (balance cierre.*):
##  · AVISOS: cierre.avisos = [{minutos_antes, text_key}] antes del inicio de la franja nocturna
##    (tiempo.franjas_hora_inicio.night), solo si el jugador está dentro del edificio (zona «work» de
##    WorldBridges) y su puesto no tiene cierre (deberes is_closing: vigilante, Dir. de Seguridad).
##  · DESALOJO a las 19:00 (time_band_changed → night): quien sigue dentro sin estar escondido
##    (Player.is_hiding) sale acompañado a la calle, ante la puerta de recepción (FloorTravel.
##    place_outside_building): no queda NINGÚN registro nocturno de un empleado honrado que se
##    retrasó. Escondido = se queda (aviso: a partir de ahora todo registro cuenta). Si en ese
##    instante hay un trayecto, un acto, la ventana de flagrancia, la policía o una escena abierta,
##    el desalojo queda pendiente y se hace en cuanto se pueda; FloorTravel llama a
##    resolve_during_travel() tras avanzar el reloj de un trayecto (no llega dentro: sale fuera).
##  · Una vez por jornada: volver a entrar de noche es actividad nocturna (BeliefNet la incrimina).

signal swept()
signal stayed_hidden()

const GROUP := "closing_time"
const NIGHT_BAND := "night"
const CLOSABLE_KINDS: Array[String] = ["computer", "phone", "map", "inventory", "dialog"]
const SFX_WARN := "ui_notify"
const SFX_SWEEP := "guard_radio"
const K_MINUTES := "minutos_antes"
const K_TEXT := "text_key"
const B_WARNINGS := "cierre.avisos"
const B_EXTERIOR := "mundo.planta_exterior"
const MINUTES_PER_HOUR := 60.0

var _root: GameRoot = null
var _warned: Dictionary = {}
var _handled_day: int = -1
var _pending: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.day_advanced.connect(func(_day: int) -> void: _reset_day())
	EventBus.run_started.connect(func(_seed: int) -> void: _reset_day())
	EventBus.run_loaded.connect(func(_day: int) -> void: _reset_day())


func setup(root: GameRoot) -> void:
	_root = root


static func find(tree: SceneTree) -> ClosingTime:
	return tree.get_first_node_in_group(GROUP) as ClosingTime if tree != null else null


func _reset_day() -> void:
	_warned.clear()
	_pending = false
	_handled_day = -1


func is_pending() -> bool:
	return _pending


## Minuto del día en que cierra el edificio (inicio de la franja nocturna).
static func closing_minute() -> float:
	return float(GameClock.get_band_start_hour(NIGHT_BAND)) * MINUTES_PER_HOUR


## El puesto del jugador exige quedarse al cierre (rondas is_closing).
static func has_closing_duty() -> bool:
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation == null:
		return false
	for duty: Dictionary in occupation.duties:
		if bool(duty.get(DutySystem.KEY_IS_CLOSING, false)):
			return true
	return false


static func is_inside() -> bool:
	return WorldBridges.zone_of(PlayerState.get_room()) == WorldBridges.ZONE_WORK


# ─── Avisos ───────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _root == null or _root.is_run_ended() or GameClock.get_day() <= 0:
		return
	if _pending:
		_retry()
	elif GameClock.get_current_band() != NIGHT_BAND and is_inside() and not has_closing_duty():
		_check_warnings()


func _check_warnings() -> void:
	var left: float = closing_minute() - GameClock.get_day_minutes()
	if left <= 0.0:
		return
	var due: Dictionary = {}
	for entry: Variant in Database.get_balance(B_WARNINGS):
		var minutes: float = float((entry as Dictionary).get(K_MINUTES, 0.0))
		if left <= minutes and not _warned.has(minutes):
			_warned[minutes] = true
			if due.is_empty() or minutes < float(due.get(K_MINUTES, 0.0)):
				due = entry
	if not due.is_empty():
		_root.ui.toast(str(due[K_TEXT]), [UITheme.format_hour(GameClock.get_band_start_hour(NIGHT_BAND)), ceili(left)],
				ToastStack.KIND_WARN)
		_play(SFX_WARN)


# ─── Desalojo ─────────────────────────────────────────────────

func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	if new_band != NIGHT_BAND or _root == null or _handled_day == GameClock.get_day():
		return
	_handled_day = GameClock.get_day()
	if not is_inside() or has_closing_duty():
		return
	_pending = true
	_retry()


func _retry() -> void:
	if not is_inside() or has_closing_duty():
		_pending = false
		return
	if _root.player.is_hiding():
		_pending = false
		_root.ui.toast("CLOSING_HIDDEN", [], ToastStack.KIND_WARN)
		stayed_hidden.emit()
		return
	if not _blocked():
		sweep()


## Algo que no se puede interrumpir: trayecto, acto, flagrancia, policía o una escena abierta.
func _blocked() -> bool:
	if _root.travel.is_busy() or not _root.player.current_act().is_empty() or _root.is_run_ended():
		return true
	var caught: CaughtHandler = _root.sim_nodes.get("CaughtHandler") as CaughtHandler
	var police: Police = _root.sim_nodes.get("Police") as Police
	if (caught != null and caught.is_window_open()) or (police != null and police.is_active()):
		return true
	for control: Control in _root.ui.get_modals():
		if not _closable(control):
			return true
	return false


func _closable(control: Control) -> bool:
	return control is FloorTravel.FloorSelectPanel or CLOSABLE_KINDS.has(str(control.get_meta(UIRoot.META_KIND, "")))


## Acompaña al jugador a la calle ya (cierra ordenador, móvil, mapa, diálogos y el panel de planta).
func sweep(from_travel: bool = false) -> void:
	_pending = false
	while _root.ui.has_modal() and _closable(_root.ui.get_top_modal()):
		_root.ui.close_modal_control(_root.ui.get_top_modal())
	_root.travel.place_outside_building(not from_travel)
	_root.ui.toast("CLOSING_SWEPT", [], ToastStack.KIND_WARN)
	_play(SFX_SWEEP)
	swept.emit()


## FloorTravel, tras avanzar el reloj de un trayecto: true = el cierre saca al jugador (no llega).
func resolve_during_travel(dest_room: String, dest_floor: int) -> bool:
	if not _pending:
		return false
	var inside: bool = WorldBridges.zone_of(dest_room) == WorldBridges.ZONE_WORK if not dest_room.is_empty() \
			else dest_floor != Database.get_balance_int(B_EXTERIOR)
	if not inside or has_closing_duty():
		_pending = false
		return false
	sweep(true)
	return true


func _play(id: String) -> void:
	if _root.audio != null:
		_root.audio.play_sfx(id)
