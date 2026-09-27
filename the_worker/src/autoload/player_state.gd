# player_state.gd — Estado del jugador: ocupación, capital, medidores, inventario, alijos, deberes y posición.
# PROPIETARIO DE: ocupación, capital, reputación, caché de sospecha, inventario, alijos (objetos ocultos), deberes de la jornada, fallos consecutivos, sala/planta/disfraz/nombre (§19.3, BUILD_NOTES §13).
# ESCUCHA: day_advanced, hour_passed, occupation_changed, room_entered, room_exited, floor_changed, suspicion_changed.
class_name PlayerStateSystem
extends Node

## Manual §4.4, §6, §10, §11.3, §12.8, §15.4, §19.3 (PASO 6, PASO 37); BUILD_NOTES §2, §11, §13.
## Emite: occupation_changed, clearance_changed, money_changed, reputation_changed, inventory_changed,
## item_hidden, item_disposed, duty_assigned, duty_completed, duty_failed, duty_progressed,
## duty_deadline_warned, disguise_changed, tracking_event_recorded.
## DECISIONES:
##  · Partida nueva: ocupación balance jugador.ocupacion_inicial (email_worker_3b, R1), capital
##    economia.dinero_inicial, reputación jugador.reputacion_inicial, inventario inventario.inicial.
##    reset_for_new_run() y load_state() no emiten señales (estado silencioso).
##  · Sospecha: la calcula BeliefNet; aquí solo se guarda en caché mediante
##    _set_suspicion_from_beliefnet() (uso EXCLUSIVO de BeliefNet) o la señal suspicion_changed.
##  · occupation_changed emitida por otro sistema (p. ej. Company al promover) se adopta aquí sin
##    reemitirla; set_occupation() la emite. Ambos caminos reconstruyen los deberes y emiten
##    clearance_changed si cambia la acreditación.
##  · Gastos diarios (§15.4): punto medio de desayuno y cena + alquiler + estatus del escalón
##    (economia.estatus_por_escalon). R1: 5 + 10 + 7 = 22 € (margen 30 − 22 = 8 €). get_daily_expenses()
##    solo calcula: los COBRA quien gestione la comida y el descanso (ciclo exterior) con spend_money.
##  · Deberes: se construyen al empezar la jornada (day_advanced) y al cambiar de ocupación; el id
##    es el del deber en occupations.json. Campo opcional "frequency" (daily | weekly | monthly |
##    quarterly; por defecto daily): los periódicos solo aparecen la última jornada del periodo.
##    Un deber cuyo plazo ya pasó al asignarse no se asigna ese día. Aviso tiempo.aviso_deber_
##    pendiente_horas_antes antes del plazo (duty_deadline_warned); al llegar deadline_hour, el deber
##    pendiente falla solo. fail_duty() aplica deberes.penalizacion_reputacion_fallo y emite
##    duty_failed(id, consecuencia): "warning" | "demotion" | "expulsion" | "none", la mayor entre la
##    escalera de fallos consecutivos (deberes.fallos_para_*) y la mínima de fail_penalty
##    (deberes.consecuencia_minima_por_penalizacion). Ejecutar la consecuencia es cosa de
##    DutySystem/Company. Los fallos consecutivos vuelven a 0 al cerrar una jornada sin fallos y con
##    algún deber cumplido.
##  · Inventario: 8 posiciones (inventario.capacidad). Apilables comparten posición (ItemData.stack
##    = unidades). Herramientas de puesto (post_tool) no ocupan posición: has_item() es true si la
##    ocupación las concede. El efectivo ordinario se convierte en capital al recogerlo.
##  · Alijos: stash_item() en un escondite de trash_dock equivale a dispose_item(id, "trash_dock").
##  · Ejes de seguimiento: los posee Tracking. add_tracking() solo emite tracking_event_recorded;
##    get_tracking()/get_dominant_axis() leen Tracking.
##  · get_name() de BUILD_NOTES §13 no puede existir en un Node (choca con Node.get_name()):
##    se llama get_player_name().

const AXES: Array[String] = ["blood", "gold", "silk", "sweat", "ruin"]
const TRACKING_SOURCE := "player_state"
const STATUS_PENDING := "pending"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
const FREQ_DAILY := "daily"
const FREQ_WEEKLY := "weekly"
const FREQ_MONTHLY := "monthly"
const FREQ_QUARTERLY := "quarterly"
const CONSEQ_NONE := "none"
const CONSEQ_WARNING := "warning"
const CONSEQ_DEMOTION := "demotion"
const CONSEQ_EXPULSION := "expulsion"
const CONSEQUENCE_LADDER: Array[String] = [
	CONSEQ_NONE, CONSEQ_WARNING, CONSEQ_DEMOTION, CONSEQ_EXPULSION,
]
const METHOD_CONFISCATED := "confiscated"
const REASON_DUTY_FAILED := "duty_failed"
const CASH_REASON_FORMAT := "cash_pickup:%s"
const DEFAULT_NAME_KEY := "PLAYER_DEFAULT_NAME"
const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440

# Campos de cada deber de la jornada (además de los de occupations.json).
const D_ID := "id"
const D_TYPE := "type"
const D_DEADLINE := "deadline_hour"
const D_FREQUENCY := "frequency"
const D_FAIL_PENALTY := "fail_penalty"
const D_STATUS := "status"
const D_PROGRESS := "progress"
const D_QUALITY := "quality"
const D_METHOD := "method"
const D_WARNED := "warned"
const D_DAY := "day"
const D_CONSEQUENCE := "consequence"
const DUTY_SAVE_INT_KEYS: Array[String] = [D_DAY]

# Campos de cada alijo: spot_id → {room_id, location, day, items: [ItemData.to_dict()]}.
const K_ROOM := "room_id"
const K_LOCATION := "location"
const K_DAY := "day"
const K_ITEMS := "items"

const P_START_OCCUPATION := "jugador.ocupacion_inicial"
const P_START_REPUTATION := "jugador.reputacion_inicial"
const P_MAX_REPUTATION := "jugador.reputacion_maxima"
const P_START_MONEY := "economia.dinero_inicial"
const P_BREAKFAST_MIN := "economia.desayuno_min"
const P_BREAKFAST_MAX := "economia.desayuno_max"
const P_DINNER_MIN := "economia.cena_min"
const P_DINNER_MAX := "economia.cena_max"
const P_RENT := "economia.alquiler_diario"
const P_STATUS_FORMAT := "economia.estatus_por_escalon.%d"
const P_CAPACITY := "inventario.capacidad"
const P_START_ITEMS := "inventario.inicial"
const P_FAILS_WARNING := "deberes.fallos_para_aviso"
const P_FAILS_DEMOTION := "deberes.fallos_para_descenso"
const P_FAILS_EXPULSION := "deberes.fallos_para_expulsion"
const P_FAIL_REPUTATION := "deberes.penalizacion_reputacion_fallo"
const P_PENALTY_FLOOR_FORMAT := "deberes.consecuencia_minima_por_penalizacion.%s"
const P_WARN_HOURS := "tiempo.aviso_deber_pendiente_horas_antes"
const P_ROLLOVER := "tiempo.hora_cambio_jornada"
const P_DAYS_WEEK := "tiempo.jornadas_por_semana"
const P_DAYS_MONTH := "tiempo.jornadas_por_mes"
const P_DAYS_QUARTER := "tiempo.jornadas_por_trimestre"

const S_OCCUPATION := "occupation_id"
const S_MONEY := "money"
const S_REPUTATION := "reputation"
const S_SUSPICION := "suspicion"
const S_INVENTORY := "inventory"
const S_STASHES := "stashes"
const S_DUTIES := "duties"
const S_DUTY_DAY := "duty_day"
const S_FAILURES := "consecutive_failures"
const S_ROOM := "room"
const S_FLOOR := "floor"
const S_DISGUISE := "disguise"
const S_NAME := "player_name"

var _active: bool = false
var _occupation: OccupationData = null
var _money: int = 0
var _reputation: float = 0.0
var _suspicion: float = 0.0
## Una entrada por posición ocupada; ItemData.stack = unidades en esa posición.
var _slots: Array[ItemData] = []
var _stashes: Dictionary = {}
var _duties: Array[Dictionary] = []
var _duty_day: int = 0
var _consecutive_failures: int = 0
var _room: String = ""
var _floor: int = 0
var _disguise: String = ""
var _player_name: String = ""


func _ready() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.room_exited.connect(_on_room_exited)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.suspicion_changed.connect(_on_suspicion_changed)


func reset_for_new_run() -> void:
	_active = true
	_occupation = Database.get_occupation(str(Database.get_balance(P_START_OCCUPATION)))
	_money = Database.get_balance_int(P_START_MONEY)
	_reputation = Database.get_balance_float(P_START_REPUTATION)
	_suspicion = 0.0
	_slots.clear()
	for item_id: Variant in _balance_array(P_START_ITEMS):
		var item: ItemData = InventoryRules.make_item(str(item_id))
		if InventoryRules.occupies_slot(item) and _can_accept(item):
			_insert_item(item)
	_stashes.clear()
	_consecutive_failures = 0
	_disguise = ""
	_player_name = ""
	_place_at_office()
	_build_duties(false)


# ─── Ocupación ─────────────────────────────────────────────────

## Compartido y de solo lectura (Database). null antes de la primera partida.
func get_occupation() -> OccupationData:
	return _occupation


## EXTRA.
func get_occupation_id() -> String:
	return _occupation.id if _occupation != null else ""


func get_rank() -> int:
	return _occupation.rank if _occupation != null else 0


func get_tier() -> int:
	return _occupation.tier if _occupation != null else 0


func get_clearance() -> int:
	return _occupation.clearance if _occupation != null else 0


## EXTRA: salario diario de la ocupación actual (lo abona quien gestione el cierre de jornada).
func get_daily_wage() -> int:
	return _occupation.daily_wage if _occupation != null else 0


## Cambia la ocupación, reconstruye los deberes de la jornada y emite occupation_changed y, si
## cambia la acreditación, clearance_changed. Id desconocido o igual al actual: no hace nada.
func set_occupation(id: String, reason: String) -> void:
	var old_id: String = get_occupation_id()
	if id == old_id or not _adopt_occupation(id):
		return
	EventBus.occupation_changed.emit(old_id, id, reason)


func get_personnel_file_level() -> int:
	return _occupation.personnel_file_level if _occupation != null else 0


# ─── Capital ───────────────────────────────────────────────────

func get_money() -> int:
	return _money


## Solo importes positivos (los cargos van por spend_money). Emite money_changed.
func add_money(amount: int, source: String) -> void:
	if amount <= 0:
		return
	var old_value: int = _money
	_money += amount
	EventBus.money_changed.emit(old_value, _money, source)


## false si es insuficiente (o negativo): entonces el capital no cambia y no se emite nada.
func spend_money(amount: int, reason: String) -> bool:
	if amount < 0 or amount > _money:
		return false
	if amount == 0:
		return true
	var old_value: int = _money
	_money -= amount
	EventBus.money_changed.emit(old_value, _money, reason)
	return true


func can_afford(amount: int) -> bool:
	return amount <= _money


## Desayuno + cena (punto medio de su rango) + alquiler + gastos de estatus del escalón (§15.4).
func get_daily_expenses() -> int:
	return int(get_daily_expense_breakdown()["total"])


## EXTRA: {breakfast, dinner, rent, status, total} en € (para el resumen de jornada).
func get_daily_expense_breakdown() -> Dictionary:
	var breakfast: int = _range_midpoint(P_BREAKFAST_MIN, P_BREAKFAST_MAX)
	var dinner: int = _range_midpoint(P_DINNER_MIN, P_DINNER_MAX)
	var rent: int = Database.get_balance_int(P_RENT)
	var status: int = get_status_expense()
	return {
		"breakfast": breakfast, "dinner": dinner, "rent": rent, "status": status,
		"total": breakfast + dinner + rent + status,
	}


## EXTRA: gastos de estatus diarios del escalón actual (0 por debajo del escalón 5).
func get_status_expense() -> int:
	var path: String = P_STATUS_FORMAT % get_tier()
	return Database.get_balance_int(path) if Database.has_balance(path) else 0


# ─── Medidores ─────────────────────────────────────────────────

func get_reputation() -> float:
	return _reputation


## Limita a [0, jugador.reputacion_maxima]. Emite reputation_changed si el valor cambia.
func modify_reputation(delta: float, reason: String) -> void:
	var old_value: float = _reputation
	var max_value: float = Database.get_balance_float(P_MAX_REPUTATION)
	_reputation = clampf(_reputation + delta, 0.0, max_value)
	if not is_equal_approx(old_value, _reputation):
		EventBus.reputation_changed.emit(old_value, _reputation)


## Cacheado desde BeliefNet.
func get_suspicion() -> float:
	return _suspicion


## Solo BeliefNet invoca. PlayerState NUNCA calcula ni modifica la sospecha por su cuenta: la
## almacena en caché para las consultas de los demás sistemas (§19.3). No emite señales
## (suspicion_changed la emite BeliefNet).
func _set_suspicion_from_beliefnet(value: float) -> void:
	_suspicion = value


# ─── Inventario ────────────────────────────────────────────────

## Copias (una por posición; stack = unidades).
func get_inventory() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item: ItemData in _slots:
		out.append(_copy_item(item))
	return out


## false si está lleno o si es una herramienta de puesto. El efectivo ordinario pasa al capital
## (money_changed) y devuelve true sin ocupar posición.
func add_item(item_id: String) -> bool:
	return add_item_data(InventoryRules.make_item(item_id))


## EXTRA: como add_item con un ItemData ya construido (p. ej. documentos con datos en extra).
func add_item_data(item: ItemData) -> bool:
	if item == null or not InventoryRules.occupies_slot(item):
		return false
	if InventoryRules.is_pocket_cash(item):
		add_money(item.value * maxi(item.stack, 1), CASH_REASON_FORMAT % item.id)
		return true
	var unit: ItemData = _copy_item(item)
	unit.stack = maxi(unit.stack, 1) if InventoryRules.is_stackable(unit) else 1
	if not _can_accept(unit):
		return false
	_insert_item(unit)
	EventBus.inventory_changed.emit(unit.id, true)
	return true


## Retira una unidad.
func remove_item(item_id: String) -> bool:
	var index: int = _find_slot(item_id)
	if index < 0:
		return false
	_take_unit(index)
	EventBus.inventory_changed.emit(item_id, false)
	return true


## true si está en el inventario o es una herramienta de puesto de la ocupación actual.
func has_item(item_id: String) -> bool:
	return _find_slot(item_id) >= 0 or _grants_post_tool(item_id)


func has_hot_items() -> bool:
	return get_hot_item_count() > 0


## Unidades comprometedoras transportadas.
func get_hot_item_count() -> int:
	var count: int = 0
	for item: ItemData in _slots:
		if item.is_compromising():
			count += item.stack
	return count


func get_free_slots() -> int:
	return maxi(Database.get_balance_int(P_CAPACITY) - _slots.size(), 0)


## EXTRA: unidades de un objeto en el inventario.
func get_item_count(item_id: String) -> int:
	var count: int = 0
	for item: ItemData in _slots:
		if item.id == item_id:
			count += item.stack
	return count


## EXTRA: retira del juego una unidad del inventario (comida consumida, venta, destrucción,
## muelle de basuras...). Emite inventory_changed y item_disposed. Irreversible.
func dispose_item(item_id: String, method: String) -> bool:
	var index: int = _find_slot(item_id)
	if index < 0:
		return false
	_take_unit(index)
	EventBus.inventory_changed.emit(item_id, false)
	EventBus.item_disposed.emit(item_id, method)
	return true


## EXTRA: requisa todo lo comprometedor tras un registro (item_disposed "confiscated").
func confiscate_hot_items() -> Array[String]:
	var taken: Array[String] = []
	for index: int in range(_slots.size() - 1, -1, -1):
		var item: ItemData = _slots[index]
		if not item.is_compromising():
			continue
		for _unit: int in item.stack:
			taken.append(item.id)
			EventBus.inventory_changed.emit(item.id, false)
			EventBus.item_disposed.emit(item.id, METHOD_CONFISCATED)
		_slots.remove_at(index)
	return taken


# ─── Alijos (BUILD_NOTES §13) ──────────────────────────────────

## Oculta una unidad en el escondite `spot_id` de la sala `room_id` (datos de sala: hiding_spots o
## interactables). Falla si no la lleva, si el escondite no admite ese objeto o está lleno
## (capacity). En el muelle de basuras equivale a dispose_item(item_id, "trash_dock").
func stash_item(item_id: String, spot_id: String, room_id: String) -> bool:
	var index: int = _find_slot(item_id)
	if index < 0:
		return false
	var spot: Dictionary = InventoryRules.find_spot(room_id, spot_id)
	if spot.is_empty():
		return false
	var location: String = spot[InventoryRules.SPOT_LOCATION]
	if not InventoryRules.can_hide_in(location, item_id):
		return false
	if InventoryRules.is_irreversible(location):
		return dispose_item(item_id, location)
	if _stash_units(spot_id) >= int(spot[InventoryRules.SPOT_CAPACITY]):
		return false
	var unit: ItemData = _take_unit(index)
	_add_to_stash(spot_id, room_id, location, unit)
	EventBus.inventory_changed.emit(item_id, false)
	EventBus.item_hidden.emit(item_id, spot_id)
	return true


## Recupera una unidad del alijo. Falla si no está o si el inventario no puede aceptarla.
func retrieve_item(spot_id: String, item_id: String) -> bool:
	if not _stashes.has(spot_id):
		return false
	var records: Array = _stashes[spot_id][K_ITEMS]
	var record_index: int = _find_record(records, item_id)
	if record_index < 0:
		return false
	var unit: ItemData = _item_from_dict(records[record_index])
	unit.stack = 1
	if not _can_accept(unit):
		return false
	_remove_record_unit(spot_id, record_index)
	_insert_item(unit)
	EventBus.inventory_changed.emit(item_id, true)
	return true


## spot_id → {room_id, location, day, items: [ItemData.to_dict()]} (copia profunda).
func get_stashes() -> Dictionary:
	return _stashes.duplicate(true)


## EXTRA: una investigación encontró el alijo: se retira entero (item_disposed "confiscated").
func confiscate_stash(spot_id: String) -> Array[String]:
	var taken: Array[String] = []
	if not _stashes.has(spot_id):
		return taken
	for record: Dictionary in _stashes[spot_id][K_ITEMS]:
		for _unit: int in maxi(int(record.get("stack", 1)), 1):
			taken.append(str(record.get("id", "")))
	_stashes.erase(spot_id)
	for item_id: String in taken:
		EventBus.item_disposed.emit(item_id, METHOD_CONFISCATED)
	return taken


# ─── Deberes ───────────────────────────────────────────────────

## Copia de los deberes de la jornada: campos de occupations.json + status ("pending" |
## "completed" | "failed"), progress, quality, method, warned, day, consequence.
func get_todays_duties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for duty: Dictionary in _duties:
		out.append(duty.duplicate(true))
	return out


func complete_duty(duty_id: String, quality: float, method: String) -> void:
	var duty: Dictionary = _find_pending_duty(duty_id)
	if duty.is_empty():
		return
	duty[D_STATUS] = STATUS_COMPLETED
	duty[D_QUALITY] = quality
	duty[D_METHOD] = method
	duty[D_PROGRESS] = 1.0
	EventBus.duty_completed.emit(duty_id, quality, method)


func fail_duty(duty_id: String) -> void:
	var duty: Dictionary = _find_pending_duty(duty_id)
	if duty.is_empty():
		return
	duty[D_STATUS] = STATUS_FAILED
	_consecutive_failures += 1
	var consequence: String = _failure_consequence(str(duty.get(D_FAIL_PENALTY, "")))
	duty[D_CONSEQUENCE] = consequence
	EventBus.duty_failed.emit(duty_id, consequence)
	modify_reputation(Database.get_balance_float(P_FAIL_REPUTATION), REASON_DUTY_FAILED)


func get_pending_duties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for duty: Dictionary in _duties:
		if duty[D_STATUS] == STATUS_PENDING:
			out.append(duty.duplicate(true))
	return out


func get_consecutive_failures() -> int:
	return _consecutive_failures


## EXTRA: progreso 0-1 de un deber pendiente (minijuegos de deber). Emite duty_progressed.
func set_duty_progress(duty_id: String, progress: float) -> void:
	var duty: Dictionary = _find_pending_duty(duty_id)
	if duty.is_empty():
		return
	duty[D_PROGRESS] = clampf(progress, 0.0, 1.0)
	EventBus.duty_progressed.emit(duty_id, duty[D_PROGRESS])


## EXTRA: copia de un deber de la jornada ({} si no existe).
func get_duty(duty_id: String) -> Dictionary:
	for duty: Dictionary in _duties:
		if duty[D_ID] == duty_id:
			return duty.duplicate(true)
	return {}


# ─── Seguimiento (fachada de Tracking, BUILD_NOTES §13) ─────────

## "blood"|"gold"|"silk"|"sweat"|"ruin". Solo emite tracking_event_recorded: Tracking suma.
func add_tracking(axis: String, amount: int) -> void:
	if not AXES.has(axis) or amount <= 0:
		return
	EventBus.tracking_event_recorded.emit(axis, amount, TRACKING_SOURCE)


func get_tracking(axis: String) -> int:
	return Tracking.get_axis(axis)


func get_dominant_axis() -> String:
	return Tracking.get_dominant_axis()


# ─── Posición, disfraz e identidad (BUILD_NOTES §13) ───────────

func get_room() -> String:
	return _room


func get_floor() -> int:
	return _floor


## "" = sin disfraz.
func get_disguise() -> String:
	return _disguise


func set_disguise(uniform_id: String) -> void:
	if uniform_id == _disguise:
		return
	_disguise = uniform_id
	EventBus.disguise_changed.emit(uniform_id)


## Sustituye a get_name() de BUILD_NOTES §13 (Node.get_name() no se puede redefinir).
func get_player_name() -> String:
	return _player_name if not _player_name.is_empty() else tr(DEFAULT_NAME_KEY)


## El jugador elige el nombre al iniciar la partida (§42, recomendación).
func set_player_name(player_name: String) -> void:
	_player_name = player_name.strip_edges()


# ─── Persistencia ──────────────────────────────────────────────

func save_state() -> Dictionary:
	var inventory: Array[Dictionary] = []
	for item: ItemData in _slots:
		inventory.append(item.to_dict())
	return {
		S_OCCUPATION: get_occupation_id(), S_MONEY: _money, S_REPUTATION: _reputation,
		S_SUSPICION: _suspicion, S_INVENTORY: inventory, S_STASHES: _stashes.duplicate(true),
		S_DUTIES: get_todays_duties(), S_DUTY_DAY: _duty_day,
		S_FAILURES: _consecutive_failures, S_ROOM: _room, S_FLOOR: _floor,
		S_DISGUISE: _disguise, S_NAME: _player_name,
	}


func load_state(data: Dictionary) -> void:
	_active = true
	_occupation = Database.get_occupation(str(data.get(S_OCCUPATION, "")))
	_money = int(data.get(S_MONEY, 0))
	_reputation = float(data.get(S_REPUTATION, 0.0))
	_suspicion = float(data.get(S_SUSPICION, 0.0))
	_slots.clear()
	for record: Variant in data.get(S_INVENTORY, []):
		if record is Dictionary:
			_slots.append(_item_from_dict(record))
	_stashes = _normalize_stashes(data.get(S_STASHES, {}))
	_duties = _normalize_duties(data.get(S_DUTIES, []))
	_duty_day = int(data.get(S_DUTY_DAY, 0))
	_consecutive_failures = int(data.get(S_FAILURES, 0))
	_room = str(data.get(S_ROOM, ""))
	_floor = int(data.get(S_FLOOR, 0))
	_disguise = str(data.get(S_DISGUISE, ""))
	_player_name = str(data.get(S_NAME, ""))


# ─── Oyentes ───────────────────────────────────────────────────

func _on_day_advanced(_day_number: int) -> void:
	if not _active:
		return
	_close_duty_day()
	_build_duties(true)


func _on_hour_passed(_hour: int, _day_number: int) -> void:
	if _active:
		_check_deadlines()


## Otro sistema (Company al promover/degradar) cambió la ocupación del jugador: se adopta.
func _on_occupation_changed(_old_id: String, new_id: String, _reason: String) -> void:
	if _active and new_id != get_occupation_id():
		_adopt_occupation(new_id)


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		_room = room_id


func _on_room_exited(room_id: String, by_player: bool) -> void:
	if by_player and _room == room_id:
		_room = ""


func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	_floor = new_floor


func _on_suspicion_changed(_old_value: float, new_value: float) -> void:
	_suspicion = new_value


# ─── Interno: ocupación y posición ─────────────────────────────

## Cambia la ocupación sin emitir occupation_changed. false si el id no existe.
func _adopt_occupation(id: String) -> bool:
	var occupation: OccupationData = Database.get_occupation(id)
	if occupation == null:
		push_warning("PlayerState: ocupación desconocida '%s'" % id)
		return false
	var old_clearance: int = get_clearance()
	_occupation = occupation
	_build_duties(true)
	if occupation.clearance != old_clearance:
		EventBus.clearance_changed.emit(old_clearance, occupation.clearance)
	return true


func _place_at_office() -> void:
	_room = _occupation.office_room if _occupation != null else ""
	var room: RoomData = Database.get_room(_room) if not _room.is_empty() else null
	_floor = room.floor if room != null else 0


# ─── Interno: deberes ──────────────────────────────────────────

func _build_duties(emit: bool) -> void:
	_duties.clear()
	_duty_day = GameClock.get_day()
	if _occupation == null:
		return
	var now: float = GameClock.get_day_minutes()
	for definition: Dictionary in _occupation.duties:
		if not _is_due_today(definition) or now >= _deadline_minutes(definition):
			continue
		var duty: Dictionary = definition.duplicate(true)
		duty.merge({
			D_STATUS: STATUS_PENDING, D_PROGRESS: 0.0, D_QUALITY: 0.0, D_METHOD: "",
			D_WARNED: false, D_DAY: _duty_day, D_CONSEQUENCE: "",
		}, true)
		_duties.append(duty)
		if emit:
			EventBus.duty_assigned.emit(duty[D_ID], str(duty.get(D_TYPE, "")),
					int(duty.get(D_DEADLINE, 0)))


func _is_due_today(definition: Dictionary) -> bool:
	var day: int = GameClock.get_day()
	match str(definition.get(D_FREQUENCY, FREQ_DAILY)):
		FREQ_WEEKLY:
			return _is_period_end(day, Database.get_balance_int(P_DAYS_WEEK))
		FREQ_MONTHLY:
			return _is_period_end(day, Database.get_balance_int(P_DAYS_MONTH))
		FREQ_QUARTERLY:
			return _is_period_end(day, Database.get_balance_int(P_DAYS_QUARTER))
	return true


## Plazo en minutos de la jornada (misma escala que GameClock.get_day_minutes()).
func _deadline_minutes(duty: Dictionary) -> float:
	var minutes: float = float(int(duty.get(D_DEADLINE, 0)) * MINUTES_PER_HOUR)
	if minutes < float(Database.get_balance_int(P_ROLLOVER) * MINUTES_PER_HOUR):
		minutes += MINUTES_PER_DAY
	return minutes


func _check_deadlines() -> void:
	var now: float = GameClock.get_day_minutes()
	var warn_minutes: float = float(Database.get_balance_int(P_WARN_HOURS) * MINUTES_PER_HOUR)
	for duty: Dictionary in _duties:
		if duty[D_STATUS] != STATUS_PENDING:
			continue
		var deadline: float = _deadline_minutes(duty)
		if now >= deadline:
			fail_duty(str(duty[D_ID]))
		elif not bool(duty[D_WARNED]) and now >= deadline - warn_minutes:
			duty[D_WARNED] = true
			EventBus.duty_deadline_warned.emit(str(duty[D_ID]),
					(deadline - now) / MINUTES_PER_HOUR)


## Cierre de la jornada: falla lo que siga pendiente (red de seguridad) y, si la jornada fue
## limpia (algún deber cumplido y ninguno fallido), reinicia los fallos consecutivos.
func _close_duty_day() -> void:
	for duty: Dictionary in _duties:
		if duty[D_STATUS] == STATUS_PENDING:
			fail_duty(str(duty[D_ID]))
	var completed: bool = false
	var failed: bool = false
	for duty: Dictionary in _duties:
		completed = completed or duty[D_STATUS] == STATUS_COMPLETED
		failed = failed or duty[D_STATUS] == STATUS_FAILED
	if completed and not failed:
		_consecutive_failures = 0


func _find_pending_duty(duty_id: String) -> Dictionary:
	for duty: Dictionary in _duties:
		if duty[D_ID] == duty_id and duty[D_STATUS] == STATUS_PENDING:
			return duty
	return {}


func _failure_consequence(fail_penalty: String) -> String:
	var level: int = 0
	if _consecutive_failures >= Database.get_balance_int(P_FAILS_EXPULSION):
		level = CONSEQUENCE_LADDER.find(CONSEQ_EXPULSION)
	elif _consecutive_failures >= Database.get_balance_int(P_FAILS_DEMOTION):
		level = CONSEQUENCE_LADDER.find(CONSEQ_DEMOTION)
	elif _consecutive_failures >= Database.get_balance_int(P_FAILS_WARNING):
		level = CONSEQUENCE_LADDER.find(CONSEQ_WARNING)
	var floor_path: String = P_PENALTY_FLOOR_FORMAT % fail_penalty
	if Database.has_balance(floor_path):
		level = maxi(level, CONSEQUENCE_LADDER.find(str(Database.get_balance(floor_path))))
	return CONSEQUENCE_LADDER[level]


static func _is_period_end(day: int, days_per_period: int) -> bool:
	return days_per_period > 0 and day > 0 and day % days_per_period == 0


# ─── Interno: inventario ───────────────────────────────────────

## Índice de la última posición con ese objeto; -1 si no está.
func _find_slot(item_id: String) -> int:
	for index: int in range(_slots.size() - 1, -1, -1):
		if _slots[index].id == item_id:
			return index
	return -1


func _can_accept(item: ItemData) -> bool:
	if InventoryRules.is_stackable(item) and _find_slot(item.id) >= 0:
		return true
	return _slots.size() < Database.get_balance_int(P_CAPACITY)


## Supone _can_accept(item) == true.
func _insert_item(item: ItemData) -> void:
	var index: int = _find_slot(item.id)
	if InventoryRules.is_stackable(item) and index >= 0:
		_slots[index].stack += maxi(item.stack, 1)
		return
	if not InventoryRules.is_stackable(item):
		item.stack = 1
	_slots.append(item)


## Retira una unidad de la posición `index` y la devuelve (copia con stack 1).
func _take_unit(index: int) -> ItemData:
	var slot: ItemData = _slots[index]
	var unit: ItemData = _copy_item(slot)
	unit.stack = 1
	slot.stack -= 1
	if slot.stack <= 0:
		_slots.remove_at(index)
	return unit


func _grants_post_tool(item_id: String) -> bool:
	if _occupation == null or not _occupation.tools.has(item_id):
		return false
	var item: ItemData = Database.get_item(item_id)
	return item != null and not InventoryRules.occupies_slot(item)


# ─── Interno: alijos ───────────────────────────────────────────

func _add_to_stash(spot_id: String, room_id: String, location: String, unit: ItemData) -> void:
	if not _stashes.has(spot_id):
		_stashes[spot_id] = {
			K_ROOM: room_id, K_LOCATION: location, K_DAY: GameClock.get_day(), K_ITEMS: [],
		}
	var records: Array = _stashes[spot_id][K_ITEMS]
	var index: int = _find_record(records, unit.id)
	if index >= 0 and InventoryRules.is_stackable(unit):
		records[index]["stack"] = int(records[index].get("stack", 1)) + 1
		return
	records.append(unit.to_dict())


func _remove_record_unit(spot_id: String, record_index: int) -> void:
	var records: Array = _stashes[spot_id][K_ITEMS]
	var record: Dictionary = records[record_index]
	record["stack"] = int(record.get("stack", 1)) - 1
	if int(record["stack"]) <= 0:
		records.remove_at(record_index)
	if records.is_empty():
		_stashes.erase(spot_id)


func _stash_units(spot_id: String) -> int:
	var units: int = 0
	if _stashes.has(spot_id):
		for record: Dictionary in _stashes[spot_id][K_ITEMS]:
			units += maxi(int(record.get("stack", 1)), 1)
	return units


static func _find_record(records: Array, item_id: String) -> int:
	for index: int in records.size():
		if str((records[index] as Dictionary).get("id", "")) == item_id:
			return index
	return -1


# ─── Interno: utilidades y normalización de datos guardados ────

func _range_midpoint(min_path: String, max_path: String) -> int:
	var low: int = Database.get_balance_int(min_path)
	var high: int = Database.get_balance_int(max_path)
	return roundi(float(low + high) / 2.0)


func _balance_array(path: String) -> Array:
	var value: Variant = Database.get_balance(path)
	return value as Array if value is Array else []


static func _copy_item(item: ItemData) -> ItemData:
	var out: ItemData = ItemData.make(item.id, item.name_key, item.category)
	out.value = item.value
	out.stack = item.stack
	out.extra = item.extra.duplicate(true)
	return out


## Reconstruye un ItemData desde ItemData.to_dict() (tras JSON los enteros llegan como float).
static func _item_from_dict(record: Dictionary) -> ItemData:
	var item: ItemData = ItemData.make(str(record.get("id", "")),
			str(record.get("name_key", "")), str(record.get("category", ItemData.CATEGORY_ORDINARY)))
	item.value = int(record.get("value", 0))
	item.stack = maxi(int(record.get("stack", ItemData.MIN_STACK)), ItemData.MIN_STACK)
	var extra: Variant = record.get("extra", {})
	item.extra = (extra as Dictionary).duplicate(true) if extra is Dictionary else {}
	return item


static func _normalize_stashes(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for spot_id: Variant in raw:
		var entry: Dictionary = raw[spot_id] if raw[spot_id] is Dictionary else {}
		var records: Array = []
		for record: Variant in entry.get(K_ITEMS, []):
			if record is Dictionary:
				records.append(_item_from_dict(record).to_dict())
		out[str(spot_id)] = {
			K_ROOM: str(entry.get(K_ROOM, "")), K_LOCATION: str(entry.get(K_LOCATION, "")),
			K_DAY: int(entry.get(K_DAY, 0)), K_ITEMS: records,
		}
	return out


static func _normalize_duties(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for record: Variant in raw:
		if not (record is Dictionary):
			continue
		var duty: Dictionary = (record as Dictionary).duplicate(true)
		for key: String in OccupationData.DUTY_INT_KEYS + DUTY_SAVE_INT_KEYS:
			if duty.has(key):
				duty[key] = int(duty[key])
		out.append(duty)
	return out
