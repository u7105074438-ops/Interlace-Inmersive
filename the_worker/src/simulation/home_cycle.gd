# home_cycle.gd — Ciclo de tarde y noche (§4.2, §4.4, §12.7, §15.4, PASO 39): salario, compras, comidas, gastos diarios, inanición y dormir (resumen → cambio de jornada → guardado → desayuno).
# PROPIETARIO DE: la contabilidad de la jornada en curso (comidas hechas y su origen, ingresos y gastos por motivo, medidores al empezar), jornadas seguidas sin comer, última jornada liquidada, último salario pagado y la marca de fin de partida enviada.
# ESCUCHA: day_advanced, hour_passed, money_changed, run_started, run_loaded, game_over.
class_name HomeCycle
extends Node

## Manual §4.2, §4.4, §12.7, §15.4, §22.4, §22.8, §22.16, PASO 39; BUILD_NOTES §2, §11, §13.
## Balance: hogar.*, economia.*. Emite: day_summary_ready, game_over ("starvation"), crime_committed
## ("theft_small" de comida), notebook_entry_added; el dinero lo mueve PlayerState (money_changed).
## game_root añade este nodo (grupo GROUP); la cama de player_flat llama a sleep(), los mostradores
## (shop_counter) a buy(), la nevera/mesa de casa a eat(), las fuentes de comida del edificio
## (kitchen_food, food_fridge ajenas) a steal_food().
## DECISIONES:
##  · SALARIO: PlayerState.get_daily_wage() a la hora tiempo.hora_fin_jornada (hour_passed), una vez
##    por jornada (motivo "wage"); si la jornada se liquida sin haberlo cobrado, se cobra entonces.
##  · COMIDAS (desayuno y cena, §4.2): eat(comida) come de la despensa (inventario y alijos de
##    hogar.sala_domicilio; objetos de hogar.comidas.<comida> en ese orden, sin coste al comerlos:
##    comprados antes o ROBADOS, §22.4/§22.8 «elimina el gasto de manutención») o, si no hay, la
##    compra a su precio (PlayerState.get_daily_expense_breakdown: el punto medio de economia.*,
##    motivos "breakfast"/"dinner"). Sin comida ni dinero, la comida se pierde. Comer (eat) avanza
##    el reloj hogar.minutos_comida.<comida> tras anotarla; la liquidación sin dormir y la cena
##    de sleep() no (el salto a la mañana ya la absorbe).
##  · GASTOS DIARIOS (PlayerState.get_daily_expenses, §15.4) = comidas + alquiler + estatus. Se
##    liquidan al cerrar la jornada (sleep() o day_advanced, lo primero; idempotente): salario si
##    faltaba → comidas no hechas (despensa → compra → perdida) → alquiler ("rent") y estatus
##    ("status") con lo que alcance (lo que falte se pierde con nota en el cuaderno). La comida va
##    primero: la inanición (§4.4) es lo que mata.
##  · INANICIÓN (THE GAP): una jornada con menos de hogar.comidas_minimas_jornada comidas es una
##    jornada sin comer; hogar.jornadas_sin_comer_inanicion seguidas = game_over("starvation") con
##    Tracking.evaluate_ending_for_cause / get_snapshot_for_cause. La primera deja aviso.
##  · DORMIR (§4.2, §12.7): solo en hogar.sala_domicilio, con hora >= hogar.hora_minima_dormir o
##    antes de tiempo.hora_cambio_jornada, sin persecución policial (Police.is_active). Orden: cena
##    (si faltaba) → liquidación de la jornada → day_summary_ready({day = jornada que cierra, income,
##    expenses, income_lines, expense_lines, money, reputation(_delta), suspicion(_delta),
##    completed_duties, missed_duties, meals, hungry_days}) ANTES de GameClock.advance_to_next_day()
##    → SaveSystem.save_run() (único guardado, §12.7) → desayuno de la jornada nueva. Al cargar una
##    partida se repite el desayuno si no consta (el guardado es previo a él): al oír run_loaded
##    o, si el nodo se crea después de load_run(), al reclamar su estado en _ready.
##  · COMPRAS: buy(objeto, tienda) solo lo que vende el mostrador de la sala (sells); precio de
##    price_keys (balance economia.*: pasamontañas 45, traje 1800) o el valor del objeto. Motivo
##    "food" (comida) o "purchase". steal_food(sala) coge hogar.objeto_comida_robada de una fuente
##    de comida ajena y emite crime_committed("theft_small", sala, {item_id, value, food: true,
##    leaves_record: false}): el riesgo son los testigos (Perception), no una investigación.

const GROUP := "home_cycle"
const SAVE_KEY := "HomeCycle"
const MEAL_BREAKFAST := "breakfast"
const MEAL_DINNER := "dinner"
const MEALS: Array[String] = [MEAL_BREAKFAST, MEAL_DINNER]
const SOURCE_STOCK := "stock"
const SOURCE_BOUGHT := "bought"
const CAUSE_STARVATION := "starvation"
const REASON_WAGE := "wage"
const REASON_RENT := "rent"
const REASON_STATUS := "status"
const REASON_FOOD := "food"
const REASON_PURCHASE := "purchase"
const METHOD_EATEN := "eaten"
const CRIME_THEFT := "theft_small"
const KIND_FOOD := "food"
const OK := ""
const ERR_NOT_HOME := "not_home"
const ERR_NOT_NIGHT := "not_night"
const ERR_POLICE := "police"
const ERR_GAME_OVER := "game_over"
const ERR_NOT_SOLD := "not_sold"
const ERR_FUNDS := "insufficient_funds"
const ERR_INVENTORY := "inventory_full"
const ERR_NO_SOURCE := "no_food_source"
const ERR_KEY_FORMAT := "HOME_ERR_%s"
const NOTE_CATEGORY := "home"
const NOTE_HUNGRY := "HOME_NOTE_HUNGRY"
const NOTE_RENT_UNPAID := "HOME_NOTE_RENT_UNPAID"
const K_SELLS := "sells"
const K_PRICE_KEYS := "price_keys"
const K_CONTAINS := "contains"
const K_OWNER := "owner"
const OWNER_PLAYER := "player"
const R_ALREADY := "already"

const B_HOME := "hogar.sala_domicilio"
const B_SLEEP_HOUR := "hogar.hora_minima_dormir"
const B_MIN_MEALS := "hogar.comidas_minimas_jornada"
const B_STARVATION_DAYS := "hogar.jornadas_sin_comer_inanicion"
const B_MEAL_ITEMS := "hogar.comidas"
const B_FOOD_SOURCES := "hogar.tipos_fuente_comida"
const B_STOLEN_FOOD := "hogar.objeto_comida_robada"
const B_COUNTER := "hogar.tipo_mostrador"
const B_COMMUTE := "hogar.minutos_trayecto_casa"
const B_SHOPPING := "hogar.minutos_compra"
const B_MEAL_MINUTES := "hogar.minutos_comida"
const B_DAY_END := "tiempo.hora_fin_jornada"
const B_ROLLOVER := "tiempo.hora_cambio_jornada"

var _day: int = 0
## comida → origen ("" = no hecha, SOURCE_STOCK, SOURCE_BOUGHT) de la jornada _day.
var _meals: Dictionary = {}
## motivo → € de la jornada _day.
var _income: Dictionary = {}
var _expenses: Dictionary = {}
var _start_reputation: float = 0.0
var _start_suspicion: float = 0.0
var _hungry_days: int = 0
var _settled_day: int = 0
var _wage_day: int = 0
var _game_over_sent: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.hour_passed.connect(_on_hour_passed)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.run_started.connect(func(_seed: int) -> void: reset_for_new_run())
	EventBus.run_loaded.connect(_on_run_loaded)
	EventBus.game_over.connect(func(_c: String, _e: String, _s: Dictionary) -> void:
		_game_over_sent = true)
	reset_for_new_run()
	add_to_group(SaveSystemNode.SCENE_GROUP)
	var saved: Dictionary = SaveSystem.claim_scene_state(SAVE_KEY)
	if not saved.is_empty():
		load_state(saved)
		_repeat_breakfast()


func get_save_key() -> String:
	return SAVE_KEY


func reset_for_new_run() -> void:
	_hungry_days = 0
	_settled_day = GameClock.get_day() - 1
	_wage_day = _settled_day
	_game_over_sent = false
	_start_day(GameClock.get_day())


static func reason_key(code: String) -> String:
	return ERR_KEY_FORMAT % code.to_upper()


# ─── Comidas ──────────────────────────────────────────────────

## Come `meal` (breakfast | dinner): despensa → compra → nada. {eaten, source, cost}. Comer
## lleva hogar.minutos_comida.<comida> de juego.
func eat(meal: String) -> Dictionary:
	var result: Dictionary = _eat(meal)
	if bool(result["eaten"]) and not bool(result.get(R_ALREADY, false)):
		GameClock.advance_minutes(Database.get_balance_float(B_MEAL_MINUTES + "." + meal))
	result.erase(R_ALREADY)
	return result


## Como eat() sin tiempo (liquidación y cena al acostarse). R_ALREADY si ya estaba hecha.
func _eat(meal: String) -> Dictionary:
	if not MEALS.has(meal) or has_eaten(meal):
		return {"eaten": has_eaten(meal), "source": str(_meals.get(meal, "")), "cost": 0,
				R_ALREADY: true}
	var source: String = ""
	var cost: int = 0
	if _consume_stock(meal):
		source = SOURCE_STOCK
	else:
		cost = meal_price(meal)
		if PlayerState.spend_money(cost, meal):
			source = SOURCE_BOUGHT
		else:
			cost = 0
	_meals[meal] = source
	return {"eaten": not source.is_empty(), "source": source, "cost": cost}


func has_eaten(meal: String) -> bool:
	return not str(_meals.get(meal, "")).is_empty()


## Precio de comprar la comida hecha (§15.4: punto medio de su rango).
func meal_price(meal: String) -> int:
	return int(PlayerState.get_daily_expense_breakdown().get(meal, 0))


## Unidades de comida disponibles para `meal` (inventario + alijos de casa).
func get_food_stock(meal: String) -> int:
	var total: int = 0
	for item_id: String in _meal_items(meal):
		total += PlayerState.get_item_count(item_id) + _home_stash_units(item_id)
	return total


## Coge comida de una fuente ajena (cocina de la cafetería, office, §22.4 §22.8). OK o ERR_*.
func steal_food(room_id: String) -> String:
	var source: Dictionary = _food_source(room_id)
	if source.is_empty():
		return ERR_NO_SOURCE
	var contents: Array = source.get(K_CONTAINS, [])
	var item_id: String = str(contents[0]) if not contents.is_empty() \
			else str(Database.get_balance(B_STOLEN_FOOD))
	if not PlayerState.add_item(item_id):
		return ERR_INVENTORY
	var item: ItemData = Database.get_item(item_id)
	EventBus.crime_committed.emit(CRIME_THEFT, room_id, {"item_id": item_id,
			"value": item.value if item != null else 0, "food": true, "leaves_record": false})
	return OK


# ─── Compras ──────────────────────────────────────────────────

## Objetos que vende el mostrador de la sala: [{item_id, price, name_key}].
func get_shop_items(shop_room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counter: Dictionary = _counter(shop_room_id)
	for item_id: Variant in counter.get(K_SELLS, []):
		var item: ItemData = Database.get_item(str(item_id))
		out.append({"item_id": str(item_id), "price": _price(counter, str(item_id)),
				"name_key": item.name_key if item != null else ""})
	return out


## Compra una unidad. OK o ERR_NOT_SOLD | ERR_FUNDS | ERR_INVENTORY. Cuesta hogar.minutos_compra.
func buy(item_id: String, shop_room_id: String) -> String:
	var counter: Dictionary = _counter(shop_room_id)
	if not (counter.get(K_SELLS, []) as Array).has(item_id):
		return ERR_NOT_SOLD
	var price: int = _price(counter, item_id)
	if not PlayerState.can_afford(price):
		return ERR_FUNDS
	if not PlayerState.add_item(item_id):
		return ERR_INVENTORY
	var item: ItemData = Database.get_item(item_id)
	var food: bool = item != null and InventoryRules.get_kind(item) == KIND_FOOD
	PlayerState.spend_money(price, REASON_FOOD if food else REASON_PURCHASE)
	GameClock.advance_minutes(Database.get_balance_float(B_SHOPPING))
	return OK


## Desplazamiento edificio ↔ casa (§4.2): avanza el reloj y devuelve los minutos.
func commute() -> int:
	var minutes: int = Database.get_balance_int(B_COMMUTE)
	GameClock.advance_minutes(float(minutes))
	return minutes


# ─── Dormir (§4.2, §12.7) ─────────────────────────────────────

## OK o el motivo por el que no se puede dormir ahora.
func can_sleep() -> String:
	if _game_over_sent or SaveSystem.is_run_over():
		return ERR_GAME_OVER
	var home: String = str(Database.get_balance(B_HOME))
	if DatabaseSystem.get_room_base_id(PlayerState.get_room()) != home:
		return ERR_NOT_HOME
	var hour: int = GameClock.get_hour()
	if hour < Database.get_balance_int(B_SLEEP_HOUR) \
			and hour >= Database.get_balance_int(B_ROLLOVER):
		return ERR_NOT_NIGHT
	var police: Police = _police()
	if police != null and police.is_active():
		return ERR_POLICE
	return OK


## Cena, liquida, emite el resumen, avanza la jornada, guarda y desayuna.
## {ok, reason, summary, saved, breakfast}.
func sleep() -> Dictionary:
	var reason: String = can_sleep()
	if reason != OK:
		return {"ok": false, "reason": reason}
	_eat(MEAL_DINNER)
	settle_day()
	if _game_over_sent:
		return {"ok": false, "reason": ERR_GAME_OVER}
	var summary: Dictionary = build_day_summary()
	EventBus.day_summary_ready.emit(summary)
	GameClock.advance_to_next_day()
	var saved: bool = SaveSystem.save_run()
	var breakfast: Dictionary = eat(MEAL_BREAKFAST)
	return {"ok": true, "reason": OK, "summary": summary, "saved": saved, "breakfast": breakfast}


## Liquida la jornada en curso (idempotente): salario, comidas, alquiler, estatus, inanición.
func settle_day() -> void:
	if _day <= _settled_day or _game_over_sent:
		return
	_settled_day = _day
	_pay_wage()
	for meal: String in MEALS:
		_eat(meal)
	var breakdown: Dictionary = PlayerState.get_daily_expense_breakdown()
	var unpaid: int = _charge(int(breakdown.get(REASON_RENT, 0)), REASON_RENT)
	unpaid += _charge(int(breakdown.get(REASON_STATUS, 0)), REASON_STATUS)
	if unpaid > 0:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_RENT_UNPAID, [unpaid])
	_check_starvation()


## Resumen de la jornada en curso (contrato de DaySummary).
func build_day_summary() -> Dictionary:
	var completed: Array[String] = []
	var missed: Array[String] = []
	for duty: Dictionary in PlayerState.get_todays_duties():
		var status: String = str(duty.get(PlayerStateSystem.D_STATUS, ""))
		if status == PlayerStateSystem.STATUS_COMPLETED:
			completed.append(str(duty.get(PlayerStateSystem.D_ID, "")))
		elif status == PlayerStateSystem.STATUS_FAILED:
			missed.append(str(duty.get(PlayerStateSystem.D_ID, "")))
	return {
		"day": _day, "income": _sum(_income), "expenses": _sum(_expenses),
		"income_lines": _lines(_income), "expense_lines": _lines(_expenses),
		"money": PlayerState.get_money(), "reputation": PlayerState.get_reputation(),
		"reputation_delta": PlayerState.get_reputation() - _start_reputation,
		"suspicion": PlayerState.get_suspicion(),
		"suspicion_delta": PlayerState.get_suspicion() - _start_suspicion,
		"completed_duties": completed, "missed_duties": missed,
		"meals": _meals.duplicate(), "hungry_days": _hungry_days,
	}


func get_hungry_days() -> int:
	return _hungry_days


func get_current_day() -> int:
	return _day


func get_settled_day() -> int:
	return _settled_day


# ─── Persistencia ─────────────────────────────────────────────

func save_state() -> Dictionary:
	return {
		"day": _day, "meals": _meals.duplicate(), "income": _income.duplicate(),
		"expenses": _expenses.duplicate(), "start_reputation": _start_reputation,
		"start_suspicion": _start_suspicion, "hungry_days": _hungry_days,
		"settled_day": _settled_day, "wage_day": _wage_day, "game_over_sent": _game_over_sent,
	}


func load_state(data: Dictionary) -> void:
	_day = int(data.get("day", GameClock.get_day()))
	_meals = _string_map(data.get("meals", {}))
	_income = _int_map(data.get("income", {}))
	_expenses = _int_map(data.get("expenses", {}))
	_start_reputation = float(data.get("start_reputation", PlayerState.get_reputation()))
	_start_suspicion = float(data.get("start_suspicion", PlayerState.get_suspicion()))
	_hungry_days = int(data.get("hungry_days", 0))
	_settled_day = int(data.get("settled_day", _day - 1))
	_wage_day = int(data.get("wage_day", _day - 1))
	_game_over_sent = bool(data.get("game_over_sent", false))


# ─── Internos ─────────────────────────────────────────────────

func _start_day(day: int) -> void:
	_day = day
	_meals = {MEAL_BREAKFAST: "", MEAL_DINNER: ""}
	_income = {}
	_expenses = {}
	_start_reputation = PlayerState.get_reputation()
	_start_suspicion = PlayerState.get_suspicion()


func _pay_wage() -> void:
	if _wage_day >= _day or _game_over_sent:
		return
	_wage_day = _day
	PlayerState.add_money(PlayerState.get_daily_wage(), REASON_WAGE)


## Cobra `amount` con lo que haya; devuelve lo que quedó sin pagar.
func _charge(amount: int, reason: String) -> int:
	var paid: int = mini(amount, PlayerState.get_money())
	if paid > 0:
		PlayerState.spend_money(paid, reason)
	return amount - maxi(paid, 0)


func _check_starvation() -> void:
	var eaten: int = 0
	for meal: String in MEALS:
		if has_eaten(meal):
			eaten += 1
	if eaten >= Database.get_balance_int(B_MIN_MEALS):
		_hungry_days = 0
		return
	_hungry_days += 1
	var limit: int = Database.get_balance_int(B_STARVATION_DAYS)
	if _hungry_days < limit:
		EventBus.notebook_entry_added.emit(NOTE_CATEGORY, NOTE_HUNGRY, [limit - _hungry_days])
		return
	_game_over_sent = true
	EventBus.game_over.emit(CAUSE_STARVATION, Tracking.evaluate_ending_for_cause(CAUSE_STARVATION),
			Tracking.get_snapshot_for_cause(CAUSE_STARVATION))


## Come una unidad de la despensa (inventario, luego alijos de casa). false si no hay.
func _consume_stock(meal: String) -> bool:
	for item_id: String in _meal_items(meal):
		if PlayerState.is_carrying(item_id):
			return PlayerState.dispose_item(item_id, METHOD_EATEN)
		for spot_id: String in _home_spots_with(item_id):
			if PlayerState.retrieve_item(spot_id, item_id):
				return PlayerState.dispose_item(item_id, METHOD_EATEN)
	return false


func _meal_items(meal: String) -> Array[String]:
	var out: Array[String] = []
	var table: Variant = Database.get_balance(B_MEAL_ITEMS)
	if table is Dictionary:
		for item_id: Variant in (table as Dictionary).get(meal, []):
			out.append(str(item_id))
	return out


func _home_spots_with(item_id: String) -> Array[String]:
	var out: Array[String] = []
	var home: String = str(Database.get_balance(B_HOME))
	var stashes: Dictionary = PlayerState.get_stashes()
	for spot_id: Variant in stashes:
		var stash: Dictionary = stashes[spot_id]
		if DatabaseSystem.get_room_base_id(str(stash.get(PlayerStateSystem.K_ROOM, ""))) != home:
			continue
		for record: Variant in stash.get(PlayerStateSystem.K_ITEMS, []):
			if record is Dictionary and str(record.get("id", "")) == item_id:
				out.append(str(spot_id))
				break
	return out


func _home_stash_units(item_id: String) -> int:
	var total: int = 0
	var stashes: Dictionary = PlayerState.get_stashes()
	for spot_id: String in _home_spots_with(item_id):
		for record: Variant in stashes[spot_id].get(PlayerStateSystem.K_ITEMS, []):
			if record is Dictionary and str(record.get("id", "")) == item_id:
				total += maxi(int(record.get("stack", 1)), 1)
	return total


func _police() -> Police:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(Police.GROUP) as Police


## Mostrador de la sala (hogar.tipo_mostrador); {} si no hay.
func _counter(shop_room_id: String) -> Dictionary:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(shop_room_id))
	if room == null:
		return {}
	var counter_type: String = str(Database.get_balance(B_COUNTER))
	for entry: Dictionary in room.interactables:
		if str(entry.get("type", "")) == counter_type:
			return entry
	return {}


func _price(counter: Dictionary, item_id: String) -> int:
	var keys: Variant = counter.get(K_PRICE_KEYS, {})
	if keys is Dictionary and (keys as Dictionary).has(item_id):
		return Database.get_balance_int(str(keys[item_id]))
	var item: ItemData = Database.get_item(item_id)
	return item.value if item != null else 0


## Fuente de comida ajena de la sala (hogar.tipos_fuente_comida, no del jugador); {} si no hay.
func _food_source(room_id: String) -> Dictionary:
	var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(room_id))
	if room == null:
		return {}
	var types: Variant = Database.get_balance(B_FOOD_SOURCES)
	for entry: Dictionary in room.interactables:
		if types is Array and (types as Array).has(str(entry.get("type", ""))) \
				and str(entry.get(K_OWNER, "")) != OWNER_PLAYER:
			return entry
	return {}


static func _sum(ledger: Dictionary) -> int:
	var total: int = 0
	for reason: Variant in ledger:
		total += int(ledger[reason])
	return total


static func _lines(ledger: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for reason: Variant in ledger:
		out.append({"reason": str(reason), "amount": int(ledger[reason])})
	return out


static func _int_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for key: Variant in raw:
			out[str(key)] = int(raw[key])
	return out


static func _string_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {MEAL_BREAKFAST: "", MEAL_DINNER: ""}
	if raw is Dictionary:
		for key: Variant in raw:
			out[str(key)] = str(raw[key])
	return out


# ─── Oyentes ──────────────────────────────────────────────────

## Cierre de la jornada sin dormir (o tras dormir: ya liquidada) y arranque de la nueva.
func _on_day_advanced(day_number: int) -> void:
	if _day < day_number:
		settle_day()
	_start_day(day_number)


func _on_hour_passed(hour: int, day_number: int) -> void:
	if hour == Database.get_balance_int(B_DAY_END) and day_number == _day:
		_pay_wage()


func _on_money_changed(old_value: int, new_value: int, reason: String) -> void:
	var delta: int = new_value - old_value
	if delta > 0:
		_income[reason] = int(_income.get(reason, 0)) + delta
	elif delta < 0:
		_expenses[reason] = int(_expenses.get(reason, 0)) - delta


## El guardado es previo al desayuno (sleep): al cargar, si no consta, se desayuna.
func _on_run_loaded(_day_number: int) -> void:
	_repeat_breakfast()


## Desayuno tras cargar (idempotente: solo por la mañana y si no consta).
func _repeat_breakfast() -> void:
	var morning: bool = GameClock.get_hour() < Database.get_balance_int(B_DAY_END)
	if morning and not has_eaten(MEAL_BREAKFAST):
		eat(MEAL_BREAKFAST)
