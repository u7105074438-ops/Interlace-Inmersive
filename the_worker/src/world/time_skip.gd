# time_skip.gd — Salto temporal (§15.6): avanzar a la siguiente franja solo en un lugar seguro y sin observadores.
# PROPIETARIO DE: el salto en curso y su fundido.
# ESCUCHA: nada (tecla time_skip o el menú de pausa llaman a request_skip()).
class_name TimeSkip
extends Node

## GameRoot lo añade con setup(ui, player, travel). Tecla T (acción ACTION, se registra aquí si falta)
## o la entrada del menú de pausa. Reglas (balance salto_tiempo.*):
##  · Lugar seguro: la sala de trabajo del puesto (office_room), el domicilio (hogar.sala_domicilio)
##    o una sala cuyo id contenga algún patrón de salto_tiempo.patrones_seguros (aseos...).
##  · Sin observadores: GameClock.advance_to_band veta el salto con la función que registra GameRoot
##    (GameRoot.observers_present: alguien que le MIRA —cono de visión— o está a su lado, o una
##    cámara que lo tiene en campo); la negativa nombra a quien mira (GameRoot.observer_name).
##  · Nunca desde la franja de noche: en casa, T ofrece dormir (WorldBridges.request_sleep, que
##    guarda la partida); fuera, «vete a casa a dormir». Tampoco con una ventana abierta, un acto en
##    curso, un trayecto, una flagrancia o la policía en marcha.
##  · Saltar de la franja de salida a la noche dentro del edificio lleva al cierre (ClosingTime: el
##    vigilante acompaña fuera a quien no está escondido).
## check() → "" o el motivo (REASON_*); request_skip() pide confirmación y salta; skip_now() salta
## sin diálogo (pruebas). Cada negativa se explica con un aviso TIMESKIP_REFUSED_<MOTIVO>.

signal skipped(from_band: String, to_band: String)

const GROUP := "time_skip"
const ACTION := "time_skip"
const ACTION_KEY := KEY_T
const NIGHT_BAND := "night"
const REASON_NIGHT := "night"
const REASON_UNSAFE := "unsafe"
const REASON_OBSERVED := "observed"
const REASON_BUSY := "busy"
const REASON_POLICE := "police"
const REASON_NO_RUN := "no_run"
const REASON_SLEEP := "sleep"
const REFUSED_KEY := "TIMESKIP_REFUSED_%s"
const B_SAFE_PATTERNS := "salto_tiempo.patrones_seguros"
const B_HOME := "hogar.sala_domicilio"
const CLOCK_ICON := "clock"

## Pruebas: sin diálogo ni fundido.
var instant: bool = false
var _ui: UIRoot = null
var _player: Node2D = null
var _travel: FloorTravel = null
var _observers: Callable = Callable()
var _overlay: FloorTravel.TravelOverlay = null
var _busy: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	ensure_action()
	_overlay = FloorTravel.TravelOverlay.new()
	_overlay.name = "SkipOverlay"
	add_child(_overlay)


## `observers`: la misma función que GameClock.set_observer_check (para explicar la negativa).
func setup(ui: UIRoot, player: Node2D, travel: FloorTravel, observers: Callable) -> void:
	_ui = ui
	_player = player
	_travel = travel
	_observers = observers


static func find(tree: SceneTree) -> TimeSkip:
	return tree.get_first_node_in_group(GROUP) as TimeSkip if tree != null else null


## Registra la acción de teclado si nadie la definió (InputSetup no la conoce).
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = ACTION_KEY
	InputMap.action_add_event(ACTION, event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		get_viewport().set_input_as_handled()
		request_skip()


## Franja a la que llevaría el salto ("" si no hay).
static func next_band() -> String:
	var order: Array[String] = GameClock.get_band_order()
	var index: int = order.find(GameClock.get_current_band())
	if index < 0 or index + 1 >= order.size():
		return ""
	return order[index + 1]


## "" si se puede saltar ahora; si no, el motivo.
func check() -> String:
	if GameClock.get_day() <= 0 or SaveSystem.is_run_over():
		return REASON_NO_RUN
	if GameClock.get_current_band() == NIGHT_BAND or next_band().is_empty():
		return REASON_SLEEP if _at_home() else REASON_NIGHT
	if _is_busy():
		return REASON_BUSY
	var police: Police = get_tree().get_first_node_in_group(Police.GROUP) as Police if is_inside_tree() else null
	if police != null and police.is_active():
		return REASON_POLICE
	if not is_safe_room(PlayerState.get_room()):
		return REASON_UNSAFE
	if _observers.is_valid() and bool(_observers.call()):
		return REASON_OBSERVED
	return ""


static func _at_home() -> bool:
	return DatabaseSystem.get_room_base_id(PlayerState.get_room()) == str(Database.get_balance(B_HOME))


## Lugar seguro (§15.6): despacho propio, domicilio o sala con patrón seguro (aseos).
static func is_safe_room(room_id: String) -> bool:
	var base: String = DatabaseSystem.get_room_base_id(room_id)
	if base.is_empty():
		return false
	var occupation: OccupationData = PlayerState.get_occupation()
	if occupation != null and base == occupation.office_room:
		return true
	if base == str(Database.get_balance(B_HOME)):
		return true
	for pattern: Variant in Database.get_balance(B_SAFE_PATTERNS):
		if base.contains(str(pattern)):
			return true
	return false


func _is_busy() -> bool:
	if _busy or (_ui != null and _ui.has_modal()) or (_travel != null and _travel.is_busy()):
		return true
	if _player != null and _player.has_method("current_act") and not str(_player.call("current_act")).is_empty():
		return true
	var caught: CaughtHandler = _find_caught()
	return caught != null and caught.is_window_open()


func _find_caught() -> CaughtHandler:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(SaveSystemNode.SCENE_GROUP):
		if node is CaughtHandler:
			return node as CaughtHandler
	return null


## Tecla o menú: explica la negativa o pide confirmación y salta.
func request_skip() -> void:
	var reason: String = check()
	if reason == REASON_SLEEP:
		var bridges: WorldBridges = WorldBridges.find(get_tree())
		if bridges != null:
			await bridges.request_sleep()
		return
	if reason == REASON_OBSERVED:
		_toast_observed()
		return
	if not reason.is_empty():
		_toast(REFUSED_KEY % reason.to_upper(), [], ToastStack.KIND_WARN)
		return
	var band: String = next_band()
	if _ui != null and not instant:
		var args: Array = [band_name(band), UITheme.format_hour(GameClock.get_band_start_hour(band))]
		var options: Array = [{"text_key": "TIMESKIP_CONFIRM", "args": args, "icon": CLOCK_ICON}, "UI_CANCEL"]
		if await _ui.show_dialog("TIMESKIP_TITLE", "TIMESKIP_BODY", options, args) != 0:
			return
	await skip_now()


## Salta ya a la siguiente franja (con fundido salvo `instant`). true si el reloj avanzó.
func skip_now() -> bool:
	var from_band: String = GameClock.get_current_band()
	var band: String = next_band()
	if band.is_empty() or _busy:
		return false
	_busy = true
	var label: String = "%s · %s" % [band_name(band), UITheme.format_hour(GameClock.get_band_start_hour(band))]
	var floor_number: int = PlayerState.get_floor()
	await _overlay.play_in(CLOCK_ICON, floor_number, floor_number, label, false, instant)
	var ok: bool = GameClock.advance_to_band(band)
	await _overlay.play_out(instant)
	_busy = false
	if not ok:
		_toast_observed()
		return false
	_toast("TIMESKIP_DONE", [band_name(band), GameClock.get_time_string()], ToastStack.KIND_INFO)
	skipped.emit(from_band, band)
	return true


## «Te ve Fulano» (o el genérico si es una cámara o no se sabe quién).
func _toast_observed() -> void:
	var root: GameRoot = GameRoot.find(get_tree()) if is_inside_tree() else null
	var who: String = root.observer_name() if root != null else ""
	if who.is_empty():
		_toast(REFUSED_KEY % REASON_OBSERVED.to_upper(), [], ToastStack.KIND_WARN)
	else:
		_toast("TIMESKIP_REFUSED_OBSERVED_BY", [who], ToastStack.KIND_WARN)


static func band_name(band: String) -> String:
	return TranslationServer.translate(GameClock.get_band_name_key(band))


func _toast(key: String, args: Array, kind: String) -> void:
	if _ui != null:
		_ui.toast(key, args, kind)
