# player_state.gd — Estado del jugador: ocupación, capital, medidores, inventario, alijos, deberes y posición.
# PROPIETARIO DE: ocupación, capital, reputación, caché de sospecha, inventario, alijos (objetos ocultos), deberes de la jornada, rachas de fallos, sala/planta/disfraz/nombre, RNG de hallazgos casuales en alijos, memoria externa (notas, registro del cuaderno, contactos, objetivos marcados, expedientes concedidos, estudios, banderas de misión) (§19.3, §13.3-§13.5, BUILD_NOTES §13).
# ESCUCHA: day_advanced, hour_passed, occupation_changed, room_entered, room_exited, floor_changed, player_searched, evidence_added, notebook_entry_added, favour_added, blackmail_demanded, phone_message_received.
class_name PlayerStateSystem
extends Node

## Manual §4.4, §6, §10, §11.3, §12.8, §15.4, §15.6, §19.3, §23 (PASO 6, PASO 37); BUILD_NOTES §2,
## §11, §13.
## Emite: occupation_changed, clearance_changed, money_changed, reputation_changed, inventory_changed,
## item_hidden, item_disposed, duty_assigned, duty_completed, duty_failed, duty_progressed,
## duty_deadline_warned, disguise_changed, tracking_event_recorded, notebook_entry_added.
## DECISIONES:
##  · Partida nueva: ocupación balance jugador.ocupacion_inicial (email_worker_3b, R1), capital
##    economia.dinero_inicial, reputación jugador.reputacion_inicial, inventario inventario.inicial.
##    reset_for_new_run() y load_state() no emiten señales (estado silencioso).
##  · Sospecha: la calcula BeliefNet y la escribe aquí SOLO con _set_suspicion_from_beliefnet() (uso
##    EXCLUSIVO de BeliefNet, PASO 6), antes de emitir suspicion_changed. PlayerState no escucha
##    suspicion_changed: ninguna otra fuente puede sobrescribir la caché.
##  · occupation_changed emitida por otro sistema (p. ej. Company al promover) se adopta aquí sin
##    reemitirla; set_occupation() la emite. Ambos caminos reconstruyen los deberes, reinician las
##    rachas por deber y emiten clearance_changed si cambia la acreditación.
##  · Gastos diarios (§15.4): punto medio de desayuno y cena + alquiler + estatus del escalón
##    (economia.estatus_por_escalon). R1: 5 + 10 + 7 = 22 € (margen 30 − 22 = 8 €). get_daily_expenses()
##    solo calcula: los COBRA el ciclo exterior con spend_money al oír day_advanced (no "al dormir":
##    la jornada también avanza a las 06:00 si el jugador no duerme, y la inanición §4.4 debe
##    comprobarse igual).
##  · Deberes: se construyen al empezar la jornada (day_advanced) y al cambiar de ocupación; el id es
##    el de occupations.json. Periodicidad (get_duty_frequency): campo "frequency" si existe; si no,
##    el prefijo del subtype según deberes.frecuencia_por_prefijo_subtipo (weekly_ / monthly_ /
##    quarterly_); por defecto daily. Los periódicos solo se asignan la última jornada del periodo
##    (días 5, 10… / 20, 40… / 25, 50…). Un deber cuyo plazo ya pasó al asignarse no se asigna. Aviso
##    tiempo.aviso_deber_pendiente_horas_antes antes del plazo (duty_deadline_warned); si se asigna
##    ya dentro de esa ventana, el aviso sale en el acto (§15.6). Al llegar deadline_hour, el
##    pendiente falla solo.
##  · Fallos: fail_duty() aplica deberes.penalizacion_reputacion_fallo y emite duty_failed(id,
##    consecuencia) "none" | "warning" | "demotion" | "expulsion" = la mayor de: (a) la escalera de
##    JORNADAS consecutivas con algún fallo (get_consecutive_failures: una jornada con tres deberes
##    fallidos cuenta una vez): ≥ fallos_para_aviso → aviso; al ALCANZAR fallos_para_descenso →
##    descenso (una sola vez por racha: la racha sobrevive al descenso y la jornada siguiente vuelve a
##    ser aviso); ≥ fallos_para_expulsion → expulsión; (b) la mínima de fail_penalty
##    (deberes.consecuencia_minima_por_penalizacion; expulsion = R0 y cierres); (c) fail_penalty
##    "demotion_risk": descenso cuando ESE deber falla deberes.fallos_para_descenso_riesgo veces
##    seguidas (dos meses / dos trimestres deficientes, §23.5, §23.7). Como mucho un descenso por
##    jornada: los demás fallos de ese día se rebajan a aviso. La racha de jornadas vuelve a 0 al
##    cerrar una jornada sin fallos y con algún deber cumplido; la de cada deber, al cumplirlo o al
##    cambiar de ocupación. Ejecutar la consecuencia es cosa de DutySystem/Company.
##  · Reentrada: el estado se actualiza antes de emitir y los bucles recorren la lista de la
##    jornada que empezaron; si un oyente cambia la ocupación (descenso síncrono) la lista nueva no
##    se toca ni se reconstruye dos veces.
##  · Inventario: 8 posiciones (inventario.capacidad). Apilables comparten posición (ItemData.stack
##    = unidades). Herramientas de puesto (kind post_tool) no se pueden recoger. El efectivo
##    ordinario se convierte en capital al recogerlo.
##  · Material entregado por el puesto (occupation.tools: llaves, estampa, uniforme del limpiador,
##    llaves maestras del vigilante...): has_item() es true aunque no se lleve encima (ACCESO);
##    is_carrying() dice si está físicamente en el inventario (lo que remove_item / stash_item /
##    dispose_item pueden retirar). Si se lleva NO cuenta como comprometedor mientras la ocupación
##    actual lo entregue (get_inventory() devuelve su copia como "ordinary" con extra.issued = true).
##    Al dejar el puesto, lo que se conserve vuelve a ser comprometedor.
##  · Alijos: stash_item() en un escondite de trash_dock equivale a dispose_item(id, "trash_dock").
##    Requisas por eventos (BUILD_NOTES §2, sin llamadas entre autoloads): player_searched con
##    found_hot_items > 0 → confiscate_hot_items(); evidence_added de tipo compromising_item → se
##    cruzan los hallazgos de Security.get_found_items() (solo lectura) y cada objeto hallado en un
##    alijo propio se retira de él (item_disposed "confiscated" + cuaderno). Hallazgo casual §11.3:
##    en day_advanced, cada alijo cuya ubicación tenga prob_hallazgo_diaria se vacía con esa
##    probabilidad (RNG propio sembrado con GameClock.get_run_seed()) si su descubridor (Connie
##    Marks) sigue activo; item_disposed "found_by_staff" + cuaderno. Recuperar cuesta
##    get_stash_retrieval_minutes(): InventoryRules.retrieve_from_stash() avanza el reloj.
##  · Ejes de seguimiento: los posee Tracking. add_tracking() solo emite tracking_event_recorded;
##    get_tracking()/get_dominant_axis() leen Tracking.
##  · get_name() de BUILD_NOTES §13 no puede existir en un Node (choca con Node.get_name()):
##    se llama get_player_name().
##  · MEMORIA EXTERNA (§13.3-§13.5; datos en PlayerRecords, guardados aquí): la UI no guarda estado
##    propio. Notas {id, day, hour, minute, text, npc_id} (add_note/remove_note; con npc_id son las
##    anotaciones de PERSONNEL y dejan PERS_NOTE_ENTRY en el cuaderno); bloc libre (get_notepad /
##    set_notepad); registro del cuaderno = cada notebook_entry_added de la partida
##    {category, text_key, args, day, hour, minute} (get_notebook_entries; dos idénticas seguidas en
##    el mismo minuto cuentan una; tope jugador.cuaderno_entradas_guardadas).
##  · CONTACTOS (§13.5) {npc_id, source, day}, source ∈ proximity | favour | hr | purchase |
##    messaged. Automáticos: proximity = movil.horas_proximidad_contacto horas de trabajo (tick
##    hour_passed en horario laboral) en la misma sala; favour = favour_added; messaged =
##    blackmail_demanded / phone_message_received de un personaje; hr = grant_full_file(id,
##    "hr_intrusion"). purchase: add_contact de las manos. Trabajar en el departamento
##    movil.departamento_rrhh da TODOS los números (get_contacts/has_contact los incluyen con source
##    hr sin guardarlos). Contacto nuevo → cuaderno NOTE_CONTACT_ADDED.
##  · OBJETIVOS MARCADOS (§13.4, §13.6): mark_target/unmark_target emiten notebook_entry_added
##    ("targets", PERS_NOTE_TARGET_MARKED | _CLEARED, [nombre]); NPCDirector lo oye y sincroniza su
##    LOD 0 forzado ("marked_target") con get_marked_targets(). Expedientes anticipados
##    (grant_full_file/has_full_file) y estudios (record_study/get_studies) de PERSONNEL.
##  · BANDERAS (get_flag/set_flag): estado genérico de misiones y del final, guardado.

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
## Índices de CONSEQUENCE_LADDER.
const LEVEL_NONE := 0
const LEVEL_WARNING := 1
const LEVEL_DEMOTION := 2
const LEVEL_EXPULSION := 3
const PENALTY_DEMOTION_RISK := "demotion_risk"
const METHOD_CONFISCATED := "confiscated"
const METHOD_FOUND_BY_STAFF := "found_by_staff"
const NOTE_CATEGORY := "stashes"
const NOTE_STASH_FOUND := "NOTE_STASH_FOUND_BY_STAFF"
const NOTE_STASH_SEIZED := "NOTE_STASH_SEIZED"
const REASON_DUTY_FAILED := "duty_failed"
const CASH_REASON_FORMAT := "cash_pickup:%s"
const DEFAULT_NAME_KEY := "PLAYER_DEFAULT_NAME"
const EXTRA_ISSUED := "issued"
const UNKNOWN_OCCUPATION_WARNING := "PlayerState: ocupación desconocida '%s'"
const RNG_SALT := "player_state"
const COMMENT_PREFIX := "_"
const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440
const NPC_PLAYER := "player"
const NOTE_CATEGORY_TARGETS := "targets"
const NOTE_TARGET_MARKED := "PERS_NOTE_TARGET_MARKED"
const NOTE_TARGET_CLEARED := "PERS_NOTE_TARGET_CLEARED"
const NOTE_CATEGORY_PERSONNEL := "personnel"
const NOTE_PERSONNEL_ENTRY := "PERS_NOTE_ENTRY"
const NOTE_CATEGORY_CONTACTS := "contacts"
const NOTE_CONTACT_ADDED := "NOTE_CONTACT_ADDED"
const CONTACT_SOURCE_KEY_FORMAT := "CONTACT_SOURCE_%s"
const REASON_HR_INTRUSION := "hr_intrusion"
const DEPARTMENT_KEY := "department"

# Campos de cada deber de la jornada (además de los de occupations.json).
const D_ID := "id"
const D_TYPE := "type"
const D_SUBTYPE := "subtype"
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
# Hallazgos de Security.get_found_items(): {case_id, spot_id, item_id, room_id, day}.
const F_CASE := "case_id"
const F_SPOT := "spot_id"
const F_ITEM := "item_id"
const FIND_KEY_FORMAT := "%s|%s|%s"

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
const P_FAILS_DEMOTION_RISK := "deberes.fallos_para_descenso_riesgo"
const P_FAIL_REPUTATION := "deberes.penalizacion_reputacion_fallo"
const P_PENALTY_FLOOR_FORMAT := "deberes.consecuencia_minima_por_penalizacion.%s"
const P_FREQ_BY_PREFIX := "deberes.frecuencia_por_prefijo_subtipo"
const P_WARN_HOURS := "tiempo.aviso_deber_pendiente_horas_antes"
const P_ROLLOVER := "tiempo.hora_cambio_jornada"
const P_DAYS_WEEK := "tiempo.jornadas_por_semana"
const P_DAYS_MONTH := "tiempo.jornadas_por_mes"
const P_DAYS_QUARTER := "tiempo.jornadas_por_trimestre"
const P_PROXIMITY_HOURS := "movil.horas_proximidad_contacto"
const P_HR_DEPARTMENT := "movil.departamento_rrhh"
const P_NOTE_MAX_CHARS := "ordenador.cuaderno_max_caracteres"
const P_MAX_NOTES := "jugador.notas_max"
const P_LOG_CAP := "jugador.cuaderno_entradas_guardadas"

const S_OCCUPATION := "occupation_id"
const S_MONEY := "money"
const S_REPUTATION := "reputation"
const S_SUSPICION := "suspicion"
const S_INVENTORY := "inventory"
const S_STASHES := "stashes"
const S_DUTIES := "duties"
const S_DUTY_DAY := "duty_day"
const S_FAILURES := "consecutive_failures"
const S_LAST_FAILED_DAY := "last_failed_day"
const S_SEVERE_DAY := "severe_consequence_day"
const S_DUTY_STREAKS := "duty_failure_streaks"
const S_PROCESSED_FINDS := "processed_finds"
const S_RNG_SEED := "rng_seed"
const S_RNG_STATE := "rng_state"
const S_ROOM := "room"
const S_FLOOR := "floor"
const S_DISGUISE := "disguise"
const S_NAME := "player_name"
const S_RECORDS := "records"

var _active: bool = false
var _occupation: OccupationData = null
var _money: int = 0
var _reputation: float = 0.0
var _suspicion: float = 0.0
## Una entrada por posición ocupada; ItemData.stack = unidades en esa posición.
var _slots: Array[ItemData] = []
var _stashes: Dictionary = {}
## Deberes de la jornada. Se REEMPLAZA (nunca se vacía en sitio) al reconstruirse, para que un
## bucle en curso siga recorriendo la lista que empezó.
var _duties: Array[Dictionary] = []
var _duty_day: int = 0
## Jornadas consecutivas con al menos un deber fallido.
var _consecutive_failures: int = 0
## Última jornada que sumó a _consecutive_failures y última con un descenso/expulsión emitido.
var _last_failed_day: int = 0
var _severe_day: int = 0
## duty_id → fallos consecutivos de ese deber (demotion_risk).
var _duty_streaks: Dictionary = {}
## Hallazgos de Security ya aplicados a los alijos ("caso|escondite|objeto").
var _processed_finds: Array[String] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _room: String = ""
var _floor: int = 0
var _disguise: String = ""
var _player_name: String = ""
## Notas, cuaderno, contactos, objetivos, expedientes, estudios y banderas (§13.3-§13.5).
var _records: PlayerRecords = PlayerRecords.new()


func _ready() -> void:
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.room_exited.connect(_on_room_exited)
	EventBus.floor_changed.connect(_on_floor_changed)
	EventBus.player_searched.connect(_on_player_searched)
	EventBus.evidence_added.connect(_on_evidence_added)
	EventBus.notebook_entry_added.connect(_on_notebook_entry_added)
	EventBus.favour_added.connect(func(npc_id: String, _t: String, _m: int) -> void:
		_auto_contact(npc_id, PlayerRecords.SOURCE_FAVOUR))
	EventBus.blackmail_demanded.connect(func(npc_id: String, _t: String, _a: int) -> void:
		_auto_contact(npc_id, PlayerRecords.SOURCE_MESSAGED))
	EventBus.phone_message_received.connect(func(from_id: String, _k: String, _c: bool) -> void:
		_auto_contact(from_id, PlayerRecords.SOURCE_MESSAGED))


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
	_processed_finds.clear()
	_reset_failure_state()
	_rng.seed = GameClock.get_run_seed() ^ RNG_SALT.hash()
	_disguise = ""
	_player_name = ""
	_records.clear()
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
	if id != get_occupation_id():
		_adopt_occupation(id, reason, true)


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

## Copias (una por posición; stack = unidades). Lo que entrega el puesto actual figura como
## "ordinary" con extra.issued = true (no es comprometedor para quien lo tiene asignado).
func get_inventory() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item: ItemData in _slots:
		var copy: ItemData = _copy_item(item)
		if _is_issued(item.id):
			copy.category = ItemData.CATEGORY_ORDINARY
			copy.extra[EXTRA_ISSUED] = true
		out.append(copy)
	return out


## false si está lleno o si es una herramienta de puesto (kind post_tool). El efectivo ordinario
## pasa al capital (money_changed) y devuelve true sin ocupar posición.
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


## ACCESO: true si está en el inventario o si lo entrega la ocupación actual (occupation.tools),
## aunque no se lleve encima. Para retirarlo (remove_item, stash_item, dispose_item) compruebe
## is_carrying().
func has_item(item_id: String) -> bool:
	return is_carrying(item_id) or _is_issued(item_id)


## EXTRA: posesión física (al menos una unidad en el inventario).
func is_carrying(item_id: String) -> bool:
	return _find_slot(item_id) >= 0


func has_hot_items() -> bool:
	return get_hot_item_count() > 0


## Unidades comprometedoras transportadas (sin contar el material entregado por el puesto actual).
func get_hot_item_count() -> int:
	var count: int = 0
	for item: ItemData in _slots:
		if _is_hot(item):
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


## EXTRA: requisa todo lo comprometedor (item_disposed "confiscated" por unidad). Se aplica sola al
## oír player_searched con found_hot_items > 0; las manos también pueden llamarla (idempotente).
func confiscate_hot_items() -> Array[String]:
	var taken: Array[String] = []
	for index: int in range(_slots.size() - 1, -1, -1):
		var item: ItemData = _slots[index]
		if not _is_hot(item):
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


## EXTRA: minutos de juego que cuesta recuperar algo de ese alijo (inventario.escondites.
## <ubicación>.minutos_recuperacion; 0 si no existe). Los cobra InventoryRules.retrieve_from_stash.
func get_stash_retrieval_minutes(spot_id: String) -> int:
	if not _stashes.has(spot_id):
		return 0
	return InventoryRules.retrieval_minutes(str(_stashes[spot_id][K_LOCATION]))


## EXTRA (manos): retira el alijo entero (item_disposed "confiscated"). Los autoloads no la llaman:
## las requisas de Security llegan por evidence_added (ver DECISIONES).
func confiscate_stash(spot_id: String) -> Array[String]:
	return _empty_stash(spot_id, METHOD_CONFISCATED)


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
	_duty_streaks.erase(duty_id)
	EventBus.duty_completed.emit(duty_id, quality, method)


## Consecuencia en duty_failed según DECISIONES (escalera por jornadas, mínima de fail_penalty,
## racha de demotion_risk, un descenso por jornada como mucho).
func fail_duty(duty_id: String) -> void:
	var duty: Dictionary = _find_pending_duty(duty_id)
	if not duty.is_empty():
		_fail_entry(duty)


func get_pending_duties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for duty: Dictionary in _duties:
		if duty[D_STATUS] == STATUS_PENDING:
			out.append(duty.duplicate(true))
	return out


## Jornadas consecutivas con al menos un deber fallido (no deberes: una jornada cuenta una vez).
func get_consecutive_failures() -> int:
	return _consecutive_failures


## EXTRA: fallos consecutivos de un deber concreto (racha de demotion_risk).
func get_duty_failure_streak(duty_id: String) -> int:
	return int(_duty_streaks.get(duty_id, 0))


## EXTRA: "daily" | "weekly" | "monthly" | "quarterly" de una definición o deber de la jornada:
## campo "frequency" o, si falta, prefijo del subtype (deberes.frecuencia_por_prefijo_subtipo).
func get_duty_frequency(duty: Dictionary) -> String:
	if duty.has(D_FREQUENCY):
		return str(duty[D_FREQUENCY])
	var subtype: String = str(duty.get(D_SUBTYPE, ""))
	var by_prefix: Variant = Database.get_balance(P_FREQ_BY_PREFIX)
	if by_prefix is Dictionary:
		for prefix: Variant in by_prefix:
			var text: String = str(prefix)
			if not text.begins_with(COMMENT_PREFIX) and subtype.begins_with(text):
				return str(by_prefix[prefix])
	return FREQ_DAILY


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


# ─── Memoria externa: notas y cuaderno (§13.3) ─────────────────

## EXTRA: notas del jugador {id, day, hour, minute, text, npc_id}, de la más antigua a la última.
func get_notes() -> Array[Dictionary]:
	return _records.get_notes()


## EXTRA: anotaciones vinculadas a un personaje (PERSONNEL, §13.4).
func get_notes_about(npc_id: String) -> Array[Dictionary]:
	return _records.get_notes(npc_id, true)


## EXTRA: guarda una nota (texto recortado a ordenador.cuaderno_max_caracteres). Con npc_id es una
## anotación de expediente y deja PERS_NOTE_ENTRY en el cuaderno. Devuelve el id (-1 si vacía).
func add_note(text: String, npc_id: String = "") -> int:
	var note_id: int = _records.add_note(text, npc_id, _stamp(),
			Database.get_balance_int(P_NOTE_MAX_CHARS), Database.get_balance_int(P_MAX_NOTES))
	if note_id != PlayerRecords.NO_NOTE and not npc_id.is_empty():
		var notes: Array[Dictionary] = _records.get_notes()
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY_PERSONNEL, NOTE_PERSONNEL_ENTRY,
				[_npc_name(npc_id), str(notes.back()[PlayerRecords.K_TEXT])])
	return note_id


## EXTRA: false si no existe.
func remove_note(note_id: int) -> bool:
	return _records.remove_note(note_id)


## EXTRA: bloc de notas libre del NOTEBOOK (un único texto).
func get_notepad() -> String:
	return _records.notepad


func set_notepad(text: String) -> void:
	_records.notepad = text.left(Database.get_balance_int(P_NOTE_MAX_CHARS))


## EXTRA: registro automático (§13.7): cada notebook_entry_added de la partida
## {category, text_key, args, day, hour, minute}, de la más antigua a la última.
func get_notebook_entries() -> Array[Dictionary]:
	return _records.get_log()


# ─── Memoria externa: contactos (§13.5) ────────────────────────

## EXTRA: [{npc_id, source, day}] en orden de adquisición; en RR. HH., además todos los personajes
## en plantilla (source "hr", day = hoy).
func get_contacts() -> Array[Dictionary]:
	var out: Array[Dictionary] = _records.get_contacts()
	if not _works_in_hr():
		return out
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not _records.has_contact(npc.id):
			out.append({PlayerRecords.K_NPC: npc.id, PlayerRecords.K_SOURCE: PlayerRecords.SOURCE_HR,
					PlayerRecords.K_DAY: GameClock.get_day()})
	return out


func has_contact(npc_id: String) -> bool:
	if _records.has_contact(npc_id):
		return true
	return _works_in_hr() and NPCDirector.is_active(npc_id)


## EXTRA: source ∈ proximity | favour | hr | purchase | messaged (también "colleague"/"bought").
## false si ya lo era, si la fuente no vale o si no es un personaje. Nota en el cuaderno.
func add_contact(npc_id: String, source: String) -> bool:
	if npc_id == NPC_PLAYER or NPCDirector.get_npc(npc_id) == null:
		return false
	if not _records.add_contact(npc_id, source, GameClock.get_day()):
		return false
	var canonical: String = PlayerRecords.canonical_source(source)
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY_CONTACTS, NOTE_CONTACT_ADDED,
			[_npc_name(npc_id), contact_source_key(canonical)])
	return true


## EXTRA: fuente del contacto ("" si no lo es; "hr" si lo es por trabajar en RR. HH.).
func get_contact_source(npc_id: String) -> String:
	for entry: Dictionary in _records.get_contacts():
		if str(entry[PlayerRecords.K_NPC]) == npc_id:
			return str(entry[PlayerRecords.K_SOURCE])
	return PlayerRecords.SOURCE_HR if has_contact(npc_id) else ""


## EXTRA: horas de trabajo compartidas con el personaje (vía proximidad).
func get_proximity_hours(npc_id: String) -> int:
	return int(_records.proximity_hours.get(npc_id, 0))


static func contact_source_key(source: String) -> String:
	return CONTACT_SOURCE_KEY_FORMAT % source.to_upper()


# ─── Memoria externa: objetivos, expedientes, estudios (§13.4) ──

## EXTRA: marca un objetivo (mapa, HUD, cuaderno; NPCDirector lo pone en LOD 0). false si no es
## un personaje o ya estaba marcado.
func mark_target(npc_id: String) -> bool:
	if NPCDirector.get_npc(npc_id) == null or not _records.mark(npc_id):
		return false
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY_TARGETS, NOTE_TARGET_MARKED, [_npc_name(npc_id)])
	return true


func unmark_target(npc_id: String) -> bool:
	if not _records.unmark(npc_id):
		return false
	EventBus.notebook_entry_added.emit(NOTE_CATEGORY_TARGETS, NOTE_TARGET_CLEARED,
			[_npc_name(npc_id)])
	return true


func get_marked_targets() -> Array[String]:
	return _records.targets.duplicate()


func is_marked(npc_id: String) -> bool:
	return _records.targets.has(npc_id)


## EXTRA (§13.4 vías de acceso anticipado): expediente completo de un personaje concreto
## ("hr_intrusion", "blackmail"...). La intrusión en RR. HH. da además su número (contacto hr).
func grant_full_file(npc_id: String, reason: String) -> bool:
	if NPCDirector.get_npc(npc_id) == null or not _records.grant_full_file(npc_id, reason):
		return false
	if reason == REASON_HR_INTRUSION:
		add_contact(npc_id, PlayerRecords.SOURCE_HR)
	return true


func has_full_file(npc_id: String) -> bool:
	return _records.full_files.has(npc_id)


## EXTRA: motivo del expediente concedido ("" si no hay).
func get_full_file_reason(npc_id: String) -> String:
	return str(_records.full_files.get(npc_id, ""))


## EXTRA: guarda el resultado de un estudio (§13.4) de `action` sobre el personaje.
func record_study(npc_id: String, action: String, result: Dictionary) -> void:
	_records.record_study(npc_id, action, result)


## EXTRA: {acción: resultado} de los estudios hechos sobre el personaje (copia).
func get_studies(npc_id: String) -> Dictionary:
	return (_records.studies.get(npc_id, {}) as Dictionary).duplicate(true)


# ─── Banderas de misión (fase de final) ────────────────────────

## EXTRA: bandera guardada de misiones y del final (documentos notariados, fases...).
func get_flag(key: String, default_value: Variant = null) -> Variant:
	return _records.flags.get(key, default_value)


## EXTRA: `value` debe ser serializable (escalares, Array, Dictionary). null la borra.
func set_flag(key: String, value: Variant) -> void:
	if key.is_empty():
		return
	if value == null:
		_records.flags.erase(key)
	else:
		_records.flags[key] = value


func has_flag(key: String) -> bool:
	return _records.flags.has(key)


# ─── Persistencia ──────────────────────────────────────────────

func save_state() -> Dictionary:
	var inventory: Array[Dictionary] = []
	for item: ItemData in _slots:
		inventory.append(item.to_dict())
	return {
		S_OCCUPATION: get_occupation_id(), S_MONEY: _money, S_REPUTATION: _reputation,
		S_SUSPICION: _suspicion, S_INVENTORY: inventory, S_STASHES: _stashes.duplicate(true),
		S_DUTIES: get_todays_duties(), S_DUTY_DAY: _duty_day,
		S_FAILURES: _consecutive_failures, S_LAST_FAILED_DAY: _last_failed_day,
		S_SEVERE_DAY: _severe_day, S_DUTY_STREAKS: _duty_streaks.duplicate(),
		S_PROCESSED_FINDS: _processed_finds.duplicate(), S_RNG_SEED: str(_rng.seed),
		S_RNG_STATE: str(_rng.state), S_ROOM: _room, S_FLOOR: _floor,
		S_DISGUISE: _disguise, S_NAME: _player_name, S_RECORDS: _records.to_dict(),
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
	_last_failed_day = int(data.get(S_LAST_FAILED_DAY, 0))
	_severe_day = int(data.get(S_SEVERE_DAY, 0))
	_duty_streaks = _normalize_int_dict(data.get(S_DUTY_STREAKS, {}))
	_processed_finds.assign(_normalize_strings(data.get(S_PROCESSED_FINDS, [])))
	_rng.seed = str(data.get(S_RNG_SEED, "0")).to_int()
	_rng.state = str(data.get(S_RNG_STATE, "0")).to_int()
	_room = str(data.get(S_ROOM, ""))
	_floor = int(data.get(S_FLOOR, 0))
	_disguise = str(data.get(S_DISGUISE, ""))
	_player_name = str(data.get(S_NAME, ""))
	var records: Variant = data.get(S_RECORDS, {})
	_records = PlayerRecords.from_dict(records if records is Dictionary else {})


# ─── Oyentes ───────────────────────────────────────────────────

## Cierra la jornada anterior, asigna la nueva (salvo que un descenso durante el cierre ya la
## asignara) y tira los hallazgos casuales de los alijos.
func _on_day_advanced(_day_number: int) -> void:
	if not _active:
		return
	_close_duty_day()
	if _duty_day != GameClock.get_day():
		_build_duties(true)
	_roll_stash_discoveries()


func _on_hour_passed(_hour: int, _day_number: int) -> void:
	if _active:
		_check_deadlines()
		_tick_proximity()


## Registro del cuaderno: toda entrada de la partida (también las propias).
func _on_notebook_entry_added(category: String, text_key: String, args: Array) -> void:
	if _active:
		_records.log_entry(category, text_key, args, _stamp(), Database.get_balance_int(P_LOG_CAP))


## Otro sistema (Company al promover/degradar) cambió la ocupación del jugador: se adopta.
func _on_occupation_changed(_old_id: String, new_id: String, reason: String) -> void:
	if _active and new_id != get_occupation_id():
		_adopt_occupation(new_id, reason, false)


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		_room = room_id


func _on_room_exited(room_id: String, by_player: bool) -> void:
	if by_player and _room == room_id:
		_room = ""


func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	_floor = new_floor


## Un registro corporal encontró material comprometedor: se requisa (item_disposed "confiscated").
func _on_player_searched(found_hot_items: int, _outcome: String) -> void:
	if _active and found_hot_items > 0:
		confiscate_hot_items()


## Una investigación añadió la pieza de un objeto comprometedor: cada hallazgo nuevo de
## Security.get_found_items() (solo lectura) que esté en un alijo propio se retira de él.
func _on_evidence_added(_case_id: String, evidence_type: String, _weight: float,
		_points_to: String) -> void:
	if not _active or evidence_type != InvestigationEngine.EV_ITEM:
		return
	for find: Dictionary in Security.get_found_items():
		var spot_id: String = str(find.get(F_SPOT, ""))
		var item_id: String = str(find.get(F_ITEM, ""))
		var key: String = FIND_KEY_FORMAT % [str(find.get(F_CASE, "")), spot_id, item_id]
		if _processed_finds.has(key):
			continue
		_processed_finds.append(key)
		if _take_from_stash(spot_id, item_id, METHOD_CONFISCATED) > 0:
			EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_STASH_SEIZED, [])


# ─── Interno: memoria externa ──────────────────────────────────

func _stamp() -> Dictionary:
	return {PlayerRecords.K_DAY: GameClock.get_day(), PlayerRecords.K_HOUR: GameClock.get_hour(),
			PlayerRecords.K_MINUTE: GameClock.get_minute()}


func _npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc.name if npc != null and not npc.name.is_empty() else npc_id


## Contacto automático (favores, mensajes): solo personajes conocidos por NPCDirector.
func _auto_contact(npc_id: String, source: String) -> void:
	if _active and not npc_id.is_empty():
		add_contact(npc_id, source)


func _works_in_hr() -> bool:
	if _occupation == null:
		return false
	var hr: String = str(Database.get_balance(P_HR_DEPARTMENT))
	return not hr.is_empty() and str(_occupation.extra.get(DEPARTMENT_KEY, "")) == hr


## §13.5 «trabajando en proximidad»: cada hora laboral compartida en la misma sala suma; al llegar a
## movil.horas_proximidad_contacto el personaje pasa a ser contacto.
func _tick_proximity() -> void:
	if _room.is_empty() or not GameClock.is_working_hours():
		return
	var needed: int = Database.get_balance_int(P_PROXIMITY_HOURS)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if _records.has_contact(npc.id) or not _same_room(npc.current_room, _room):
			continue
		if _records.add_proximity_hour(npc.id) >= needed:
			add_contact(npc.id, PlayerRecords.SOURCE_PROXIMITY)


## Misma sala; una copia transversal ("corridors_low@3") coincide con su id base sin planta.
static func _same_room(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if a == b:
		return true
	var separator: String = DatabaseSystem.INSTANCE_SEPARATOR
	return (not a.contains(separator) or not b.contains(separator)) \
			and DatabaseSystem.get_room_base_id(a) == DatabaseSystem.get_room_base_id(b)


# ─── Interno: ocupación y posición ─────────────────────────────

## Cambia la ocupación y reconstruye los deberes (los pendientes del puesto anterior se descartan
## sin fallar). Orden: duty_assigned… → occupation_changed (si `announce`) → clearance_changed
## (si cambia). false si el id no existe.
func _adopt_occupation(id: String, reason: String, announce: bool) -> bool:
	var occupation: OccupationData = Database.get_occupation(id)
	if occupation == null:
		push_warning(UNKNOWN_OCCUPATION_WARNING % id)
		return false
	var old_id: String = get_occupation_id()
	var old_clearance: int = get_clearance()
	_occupation = occupation
	_duty_streaks.clear()
	_build_duties(true)
	if announce:
		EventBus.occupation_changed.emit(old_id, id, reason)
	if occupation.clearance != old_clearance:
		EventBus.clearance_changed.emit(old_clearance, occupation.clearance)
	return true


func _place_at_office() -> void:
	_room = _occupation.office_room if _occupation != null else ""
	var room: RoomData = Database.get_room(_room) if not _room.is_empty() else null
	_floor = room.floor if room != null else 0


# ─── Interno: deberes ──────────────────────────────────────────

## Reemplaza la lista de la jornada (una lista NUEVA: un bucle en curso conserva la anterior).
func _build_duties(emit: bool) -> void:
	var duties: Array[Dictionary] = []
	_duties = duties
	_duty_day = GameClock.get_day()
	if _occupation == null:
		return
	var now: float = GameClock.get_day_minutes()
	for definition: Dictionary in _occupation.duties:
		if _is_due_today(definition) and now < _deadline_minutes(definition):
			duties.append(_new_duty(definition))
	if emit:
		_announce_duties(duties, now)


func _new_duty(definition: Dictionary) -> Dictionary:
	var duty: Dictionary = definition.duplicate(true)
	duty.merge({
		D_STATUS: STATUS_PENDING, D_PROGRESS: 0.0, D_QUALITY: 0.0, D_METHOD: "",
		D_WARNED: false, D_DAY: _duty_day, D_CONSEQUENCE: "",
	}, true)
	return duty


## duty_assigned por deber y, si ya está dentro de la ventana de aviso, duty_deadline_warned en el
## acto (§15.6: asignar un deber a menos de una hora del plazo sin avisar sería injusto).
func _announce_duties(duties: Array[Dictionary], now: float) -> void:
	for duty: Dictionary in duties:
		if not is_same(duties, _duties):
			return
		EventBus.duty_assigned.emit(str(duty[D_ID]), str(duty.get(D_TYPE, "")),
				int(duty.get(D_DEADLINE, 0)))
		_warn_if_due(duty, now)


func _is_due_today(definition: Dictionary) -> bool:
	var day: int = GameClock.get_day()
	match get_duty_frequency(definition):
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
	var duties: Array[Dictionary] = _duties
	var now: float = GameClock.get_day_minutes()
	for duty: Dictionary in duties:
		if not is_same(duties, _duties):
			return
		if duty[D_STATUS] != STATUS_PENDING:
			continue
		if now >= _deadline_minutes(duty):
			_fail_entry(duty)
		else:
			_warn_if_due(duty, now)


func _warn_if_due(duty: Dictionary, now: float) -> void:
	if duty[D_STATUS] != STATUS_PENDING or bool(duty[D_WARNED]):
		return
	var deadline: float = _deadline_minutes(duty)
	var window: float = float(Database.get_balance_int(P_WARN_HOURS) * MINUTES_PER_HOUR)
	if now >= deadline - window:
		duty[D_WARNED] = true
		EventBus.duty_deadline_warned.emit(str(duty[D_ID]), (deadline - now) / MINUTES_PER_HOUR)


## Cierre de la jornada: falla lo que siga pendiente (red de seguridad) y, si la jornada fue
## limpia (algún deber cumplido y ninguno fallido), reinicia la racha de jornadas con fallos.
func _close_duty_day() -> void:
	var closing: Array[Dictionary] = _duties
	for duty: Dictionary in closing:
		if not is_same(closing, _duties):
			break
		if duty[D_STATUS] == STATUS_PENDING:
			_fail_entry(duty)
	var completed: bool = false
	var failed: bool = false
	for duty: Dictionary in closing:
		completed = completed or duty[D_STATUS] == STATUS_COMPLETED
		failed = failed or duty[D_STATUS] == STATUS_FAILED
	if completed and not failed:
		_consecutive_failures = 0


func _find_pending_duty(duty_id: String) -> Dictionary:
	for duty: Dictionary in _duties:
		if duty[D_ID] == duty_id and duty[D_STATUS] == STATUS_PENDING:
			return duty
	return {}


## Marca el deber, actualiza las rachas y decide la consecuencia ANTES de emitir duty_failed (un
## oyente puede degradar al jugador y reconstruir la lista de deberes).
func _fail_entry(duty: Dictionary) -> void:
	var duty_id: String = str(duty[D_ID])
	var day: int = int(duty.get(D_DAY, GameClock.get_day()))
	duty[D_STATUS] = STATUS_FAILED
	var first_today: bool = _count_failed_day(day)
	_duty_streaks[duty_id] = int(_duty_streaks.get(duty_id, 0)) + 1
	var consequence: String = _failure_consequence(duty, first_today, day)
	duty[D_CONSEQUENCE] = consequence
	EventBus.duty_failed.emit(duty_id, consequence)
	modify_reputation(Database.get_balance_float(P_FAIL_REPUTATION), REASON_DUTY_FAILED)


## Suma una jornada a la racha la primera vez que falla algo en ella. true si es ese primer fallo.
func _count_failed_day(day: int) -> bool:
	if _last_failed_day == day:
		return false
	_last_failed_day = day
	_consecutive_failures += 1
	return true


func _failure_consequence(duty: Dictionary, first_today: bool, day: int) -> String:
	var level: int = maxi(_ladder_level(first_today),
			_penalty_floor(str(duty.get(D_FAIL_PENALTY, ""))))
	if _demotion_risk_due(duty):
		level = maxi(level, LEVEL_DEMOTION)
	if level == LEVEL_DEMOTION and _severe_day == day:
		level = LEVEL_WARNING
	if level >= LEVEL_DEMOTION:
		_severe_day = day
	return CONSEQUENCE_LADDER[level]


## Escalera por jornadas consecutivas: el descenso se emite al ALCANZAR su umbral (una vez por
## racha, en el primer fallo de esa jornada); la expulsión, desde su umbral.
func _ladder_level(first_today: bool) -> int:
	var streak: int = _consecutive_failures
	if streak >= Database.get_balance_int(P_FAILS_EXPULSION):
		return LEVEL_EXPULSION
	if first_today and streak == Database.get_balance_int(P_FAILS_DEMOTION):
		return LEVEL_DEMOTION
	if streak >= Database.get_balance_int(P_FAILS_WARNING):
		return LEVEL_WARNING
	return LEVEL_NONE


func _penalty_floor(fail_penalty: String) -> int:
	var path: String = P_PENALTY_FLOOR_FORMAT % fail_penalty
	if fail_penalty.is_empty() or not Database.has_balance(path):
		return LEVEL_NONE
	return maxi(CONSEQUENCE_LADDER.find(str(Database.get_balance(path))), LEVEL_NONE)


## demotion_risk: ese mismo deber lleva fallos_para_descenso_riesgo fallos seguidos.
func _demotion_risk_due(duty: Dictionary) -> bool:
	if str(duty.get(D_FAIL_PENALTY, "")) != PENALTY_DEMOTION_RISK:
		return false
	var streak: int = int(_duty_streaks.get(str(duty[D_ID]), 0))
	return streak >= Database.get_balance_int(P_FAILS_DEMOTION_RISK)


func _reset_failure_state() -> void:
	_consecutive_failures = 0
	_last_failed_day = 0
	_severe_day = 0
	_duty_streaks.clear()


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


## Material entregado por la ocupación actual (occupation.tools).
func _is_issued(item_id: String) -> bool:
	return _occupation != null and _occupation.tools.has(item_id)


func _is_hot(item: ItemData) -> bool:
	return item.is_compromising() and not _is_issued(item.id)


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


## Vacía un alijo entero (item_disposed(id, method) por unidad). Devuelve las unidades retiradas.
func _empty_stash(spot_id: String, method: String) -> Array[String]:
	var taken: Array[String] = []
	if not _stashes.has(spot_id):
		return taken
	for record: Dictionary in _stashes[spot_id][K_ITEMS]:
		for _unit: int in maxi(int(record.get("stack", 1)), 1):
			taken.append(str(record.get("id", "")))
	_stashes.erase(spot_id)
	for item_id: String in taken:
		EventBus.item_disposed.emit(item_id, method)
	return taken


## Retira del alijo todas las unidades de `item_id` (item_disposed por unidad). Devuelve cuántas.
func _take_from_stash(spot_id: String, item_id: String, method: String) -> int:
	if not _stashes.has(spot_id):
		return 0
	var records: Array = _stashes[spot_id][K_ITEMS]
	var units: int = 0
	var index: int = _find_record(records, item_id)
	while index >= 0:
		units += maxi(int((records[index] as Dictionary).get("stack", 1)), 1)
		records.remove_at(index)
		index = _find_record(records, item_id)
	if records.is_empty():
		_stashes.erase(spot_id)
	for _unit: int in units:
		EventBus.item_disposed.emit(item_id, method)
	return units


## §11.3 (cuartos de limpieza): cada alijo cuya ubicación tenga prob_hallazgo_diaria > 0 se
## descubre con esa probabilidad si su descubridor sigue activo, y se vacía entero
## (item_disposed "found_by_staff" + cuaderno). Orden de escondites estable (reproducible).
func _roll_stash_discoveries() -> void:
	var spots: Array = _stashes.keys()
	spots.sort()
	for spot_id: Variant in spots:
		if not _stashes.has(spot_id):
			continue
		var location: String = str(_stashes[spot_id][K_LOCATION])
		var chance: float = InventoryRules.daily_discovery_chance(location)
		if chance <= 0.0 or not _discoverer_active(location):
			continue
		if _rng.randf() < chance:
			_empty_stash(str(spot_id), METHOD_FOUND_BY_STAFF)
			EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_STASH_FOUND, [])


## Sin descubridor designado, o sin población simulada (NPCDirector no lo conoce), el riesgo es de
## la ubicación; si el personaje existe, tiene que seguir activo (vivo y en plantilla).
func _discoverer_active(location: String) -> bool:
	var npc_id: String = InventoryRules.daily_discoverer(location)
	if npc_id.is_empty() or NPCDirector.get_npc(npc_id) == null:
		return true
	return NPCDirector.is_active(npc_id)


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
	var category: String = str(record.get("category", ItemData.CATEGORY_ORDINARY))
	var item: ItemData = ItemData.make(str(record.get("id", "")),
			str(record.get("name_key", "")), category)
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


static func _normalize_int_dict(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			out[str(key)] = int(raw[key])
	return out


static func _normalize_strings(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			out.append(str(value))
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
