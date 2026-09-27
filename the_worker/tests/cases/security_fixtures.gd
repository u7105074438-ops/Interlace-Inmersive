# security_fixtures.gd — Utilidades comunes de test_security, test_investigation, test_cold_case y test_interrogation.
# PROPIETARIO DE: nada.
# ESCUCHA: las señales de EventBus que se le pidan (SignalLog, solo durante el caso).
extends RefCounted

## Uso: const Fx := preload("res://tests/cases/security_fixtures.gd")
##   var log := Fx.SignalLog.new().watch(["investigation_opened", ...]) ... log.stop()
##   Fx.enter_room("monitor_room") · Fx.set_suspicion(80.0) · Fx.become("chief_auditor")

const PLAYER := "player"
## Sala sin acreditación (clearance 0): cualquiera tiene acceso (+2,0 de oportunidad).
const OPEN_ROOM := "main_reception"
## Sala de clearance 7: ni el jugador de rango bajo ni un personaje sin ocupación tienen acceso.
const SEALED_ROOM := "ceo_office"
const WITNESS := "npc_george_penn"
const SCAPEGOAT := "npc_ray_cudmore"


## Registro de emisiones de señales de EventBus.
class SignalLog:
	extends RefCounted
	var events: Array[Dictionary] = []
	var _callables: Dictionary = {}

	func watch(names: Array[String]) -> SignalLog:
		for signal_name: String in names:
			var callable: Callable = func(...args: Array) -> void:
				events.append({"signal": signal_name, "args": args})
			EventBus.connect(signal_name, callable)
			_callables[signal_name] = callable
		return self

	func stop() -> void:
		for signal_name: String in _callables:
			if EventBus.is_connected(signal_name, _callables[signal_name]):
				EventBus.disconnect(signal_name, _callables[signal_name])
		_callables.clear()

	func clear() -> void:
		events.clear()

	## Argumentos de cada emisión de `signal_name`, en orden.
	func of(signal_name: String) -> Array[Array]:
		var out: Array[Array] = []
		for event: Dictionary in events:
			if event["signal"] == signal_name:
				out.append(event["args"])
		return out

	func count(signal_name: String) -> int:
		return of(signal_name).size()

	func last(signal_name: String) -> Array:
		var all: Array[Array] = of(signal_name)
		return [] if all.is_empty() else all[all.size() - 1]


## El jugador entra en una sala (PlayerState y Security la siguen por room_entered).
static func enter_room(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)


## Nueva sospecha del jugador tal como la publica BeliefNet.
static func set_suspicion(value: float) -> void:
	EventBus.suspicion_changed.emit(Security.get_known_suspicion(), value)


## El jugador pasa a ocupar `occupation_id` (por PlayerState si ya está implementado).
static func become(occupation_id: String) -> void:
	var before: OccupationData = PlayerState.get_occupation()
	PlayerState.set_occupation(occupation_id, "test")
	var after: OccupationData = PlayerState.get_occupation()
	if after == null or after.id != occupation_id:
		EventBus.occupation_changed.emit("" if before == null else before.id, occupation_id, "test")


## Pone el uniforme `uniform_id` (por PlayerState si ya expone set_disguise).
static func wear(uniform_id: String) -> void:
	var current: String = ""
	if PlayerState.has_method("set_disguise"):
		PlayerState.call("set_disguise", uniform_id)
	if PlayerState.has_method("get_disguise"):
		current = str(PlayerState.call("get_disguise"))
	if current != uniform_id:
		EventBus.disguise_changed.emit(uniform_id)


## Avanza `count` jornadas con el tic de Security (sin difundir day_advanced al resto).
static func advance_days(count: int) -> void:
	for _i: int in count:
		Security.process_day(Security.get_current_day() + 1)


## Caso de denuncia de testigo directo (4,0 → jugador) en `location` a la hora `hour`.
static func open_witness_case(location: String, hour: int, severity: int = 0) -> String:
	return Security.report_incident("direct_witness_report", severity, location, true, {
		"subject": PLAYER, "witness": WITNESS, "evidence_type": "direct_witness", "hour": hour})


## Lleva un caso activo hasta la fase indicada con advance_phase.
static func push_to_phase(case_id: String, phase: int) -> void:
	var inv: Investigation = Security.get_investigation(case_id)
	var guard: int = Investigation.MAX_PHASE
	while inv != null and inv.is_active() and inv.phase < phase and guard > 0:
		Security.advance_phase(case_id)
		guard -= 1


## Tipos de las piezas de un caso, en orden.
static func piece_types(case_id: String) -> Array[String]:
	var out: Array[String] = []
	for piece: Dictionary in Security.get_investigation(case_id).evidence:
		out.append(str(piece["type"]))
	return out


static func piece_of_type(case_id: String, evidence_type: String) -> Dictionary:
	for piece: Dictionary in Security.get_investigation(case_id).evidence:
		if piece["type"] == evidence_type:
			return piece
	return {}


static func bal(path: String) -> float:
	return Database.get_balance_float(path)
