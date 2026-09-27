# buyers.gd — Compradores de la sala de demostraciones (§11.5): cartera y agenda (generación pura) y las cuatro operaciones del jugador resueltas por los rasgos de cada comprador.
# PROPIETARIO DE: nada (cartera, visitas, reclamaciones, material y fraudes pendientes los guarda Company; dinero y reputación, PlayerState).
# ESCUCHA: nada.
class_name Buyers
extends RefCounted

## Manual §11.5, §9.4 (cierre mensual: afloran los fraudes), §7.9; PASO 41; BUILD_NOTES §2, §12.
## MANOS DEL MUNDO: la mesa demo_table de buyer_demo_room (data.operations = OPERATIONS) muestra
## Company.get_buyers_today() y llama a operate(comprador, operación, opciones) o a
## honest_sale / overprice / phantom_sale / kickback_discount. can_operate(comprador) da el
## motivo si no se puede (REASON_*; get_reason_label_key).
## Resultado de una operación: {ok, buyer_id, operation, outcome, reason, order_value, income,
## company_loss, claim_due_day, reported}.
## DECISIONES:
##  · Los compradores son fichas con los seis rasgos estándar (no personajes de NPCDirector):
##    id "buyer_N", nombre del name_bank de npcs_generation, empresa (clave BUYER_FIRM_*).
##    Company genera la cartera (semilla de partida) y la agenda de cada jornada (semilla de
##    partida + jornada): compradores.visitas_por_dia visitas los días de dias_visita_semana.
##  · Requisitos: el comprador espera hoy (status waiting), el jugador está en la sala
##    (compradores.sala) y ocupa un puesto de compradores.ocupaciones_venta. Una operación por
##    visita (cierra la visita).
##  · Venta honesta: comisión legal = pedido × comision_legal. Sin riesgo.
##  · Sobreprecio (markup ≤ sobreprecio_max; ≤ 0 = sobreprecio_por_defecto): perspicacia ≥
##    perspicacia_detecta_sobreprecio → lo detecta en el acto: no hay venta, se queja. Si no, la
##    diferencia íntegra al bolsillo, crime_committed("fraud", {amount}) (contabilidad: Security lo
##    destapa en el cierre mensual si el fraude del periodo llega a su mínimo) y, con probabilidad
##    perspicacia/100 × factor_prob_reclamacion, reclamará al cabo de semanas_reclamacion_min..max
##    semanas (Company emite entonces su queja).
##  · Venta fantasma: acepta el trato fuera de libros con codicia ≥ codicia_min_venta_fantasma →
##    importe íntegro al bolsillo, fraude contable y descuadre de pares en el cierre mensual
##    (Company.register_sales_fraud → theft_losses).
##  · Descuento con mordida (descuento ≤ descuento_max; ≤ 0 = descuento_por_defecto): acepta sin
##    objeción con codicia ≥ codicia_acepta_mordida; por debajo, con probabilidad codicia/100 →
##    fraccion_mordida del descuento al bolsillo, fraude contable, pérdida del descuento en el
##    cierre mensual y el comprador guarda material de chantaje (Company.add_buyer_material).
##  · Rechazo (fantasma o mordida): con lealtad ≥ lealtad_denuncia se queja → "reported".
##  · Queja en el acto: reputación − reputacion_por_queja y npc_reported_player(comprador,
##    canal_queja, 0, sala): BeliefNet y Security la tratan como una denuncia ante el superior.
##  · Tiradas: opciones.roll (pruebas y escenas) o RNG sembrado con partida + jornada + comprador +
##    operación (reproducible, sin estado).

const PLAYER_ID := "player"
const OP_HONEST := "honest_sale"
const OP_OVERPRICE := "overprice"
const OP_PHANTOM := "phantom_sale"
const OP_KICKBACK := "kickback_discount"
const OPERATIONS: Array[String] = [OP_HONEST, OP_OVERPRICE, OP_PHANTOM, OP_KICKBACK]
const OPERATION_LABEL_KEYS: Dictionary = {
	OP_HONEST: "BUYER_OP_HONEST_SALE", OP_OVERPRICE: "BUYER_OP_OVERPRICE",
	OP_PHANTOM: "BUYER_OP_PHANTOM_SALE", OP_KICKBACK: "BUYER_OP_KICKBACK_DISCOUNT",
}
const OUTCOME_SOLD := "sold"
const OUTCOME_DETECTED := "detected"
const OUTCOME_REFUSED := "refused"
const OUTCOME_REPORTED := "reported"
const OUTCOME_LABEL_KEYS: Dictionary = {
	OUTCOME_SOLD: "BUYER_OUTCOME_SOLD", OUTCOME_DETECTED: "BUYER_OUTCOME_DETECTED",
	OUTCOME_REFUSED: "BUYER_OUTCOME_REFUSED", OUTCOME_REPORTED: "BUYER_OUTCOME_REPORTED",
}
const COMPLAINT_OUTCOMES: Array[String] = [OUTCOME_DETECTED, OUTCOME_REPORTED]
const REASON_UNKNOWN_OPERATION := "unknown_operation"
const REASON_NOT_VISITING := "not_visiting"
const REASON_ALREADY_SERVED := "already_served"
const REASON_NOT_A_SELLER := "not_a_seller"
const REASON_NOT_IN_ROOM := "not_in_demo_room"
const REASON_LABEL_KEYS: Dictionary = {
	REASON_UNKNOWN_OPERATION: "BUYER_REASON_UNKNOWN_OPERATION",
	REASON_NOT_VISITING: "BUYER_REASON_NOT_VISITING",
	REASON_ALREADY_SERVED: "BUYER_REASON_ALREADY_SERVED",
	REASON_NOT_A_SELLER: "BUYER_REASON_NOT_A_SELLER", REASON_NOT_IN_ROOM: "BUYER_REASON_NOT_IN_ROOM",
}
const STATUS_WAITING := "waiting"
const STATUS_CLOSED := "closed"
const CRIME_FRAUD := "fraud"
const MATERIAL_KICKBACK := "kickback"
const MONEY_REASON_FORMAT := "buyer_%s"
const REPUTATION_REASON := "buyer_complaint"
const RNG_SALT := "buyers"
const BUYER_ID_FORMAT := "buyer_%d"
const NAME_FORMAT := "%s %s"
const GENERATION_FILE := "npcs_generation"
const NAME_BANK_KEY := "name_bank"
const FIRST_NAMES_KEY := "first_names"
const LAST_NAMES_KEY := "last_names"
const TRAIT_PERCEPTION := "perception"
const TRAIT_GREED := "greed"
const TRAIT_LOYALTY := "loyalty"
## Los rasgos van de 0 a 100: rasgo/100 es una probabilidad.
const TRAIT_SCALE := 100.0

# Ficha de un comprador (cartera de Company).
const B_ID := "id"
const B_FIRST := "first_name"
const B_LAST := "last_name"
const B_FIRM := "firm_key"
const B_TRAITS := "traits"
const B_SEED := "portrait_seed"
const B_MATERIAL := "material"
# Visita (agenda de la jornada).
const V_BUYER := "buyer_id"
const V_DAY := "day"
const V_HOUR := "hour"
const V_PAIRS := "pairs"
const V_PRICE := "unit_price"
const V_VALUE := "order_value"
const V_STATUS := "status"
const V_OPERATION := "operation"
const V_OUTCOME := "outcome"
const VISIT_INT_KEYS: Array[String] = [V_HOUR, V_PAIRS, V_VALUE]

const P_ROOM := "compradores.sala"
const P_SELLERS := "compradores.ocupaciones_venta"
const P_ROSTER_SIZE := "compradores.tamano_cartera"
const P_FIRMS := "compradores.empresas"
const P_TRAIT_MIN := "compradores.rasgo_min"
const P_TRAIT_MAX := "compradores.rasgo_max"
const P_VISIT_DAYS := "compradores.dias_visita_semana"
const P_VISITS := "compradores.visitas_por_dia"
const P_HOURS := "compradores.horas_visita"
const P_PAIRS_MIN := "compradores.pares_pedido_min"
const P_PAIRS_MAX := "compradores.pares_pedido_max"
const P_COMMISSION := "compradores.comision_legal"
const P_MARKUP := "compradores.sobreprecio_por_defecto"
const P_MARKUP_MAX := "compradores.sobreprecio_max"
const P_DETECT := "compradores.perspicacia_detecta_sobreprecio"
const P_CLAIM_FACTOR := "compradores.factor_prob_reclamacion"
const P_CLAIM_WEEKS_MIN := "compradores.semanas_reclamacion_min"
const P_CLAIM_WEEKS_MAX := "compradores.semanas_reclamacion_max"
const P_PHANTOM_GREED := "compradores.codicia_min_venta_fantasma"
const P_DISCOUNT := "compradores.descuento_por_defecto"
const P_DISCOUNT_MAX := "compradores.descuento_max"
const P_KICKBACK_SHARE := "compradores.fraccion_mordida"
const P_KICKBACK_GREED := "compradores.codicia_acepta_mordida"
const P_LOYALTY_REPORT := "compradores.lealtad_denuncia"
const P_CHANNEL := "compradores.canal_queja"
const P_REPUTATION := "compradores.reputacion_por_queja"
const P_DAYS_PER_WEEK := "tiempo.jornadas_por_semana"
const P_DAY_START := "tiempo.hora_inicio_jornada"


# ─── Cartera y agenda (puro; lo llama Company) ───────────────

## Cartera de compradores de la partida (compradores.tamano_cartera fichas).
static func generate_roster(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var bank: Dictionary = _as_dict(Database.get_raw(GENERATION_FILE).get(NAME_BANK_KEY, {}))
	var firsts: Array = bank.get(FIRST_NAMES_KEY, [])
	var lasts: Array = bank.get(LAST_NAMES_KEY, [])
	var firms: Array = _strings(Database.get_balance(P_FIRMS))
	var out: Array[Dictionary] = []
	for i: int in Database.get_balance_int(P_ROSTER_SIZE):
		out.append({
			B_ID: BUYER_ID_FORMAT % (i + 1), B_FIRST: _pick(firsts, rng), B_LAST: _pick(lasts, rng),
			B_FIRM: _pick(firms, rng), B_TRAITS: _roll_traits(rng), B_SEED: rng.randi(),
			B_MATERIAL: [],
		})
	return out


## Día de visita: jornada de la semana (1 = primera) en compradores.dias_visita_semana.
static func is_visit_day(day: int) -> bool:
	var per_week: int = maxi(Database.get_balance_int(P_DAYS_PER_WEEK), 1)
	var weekday: int = posmod(day - 1, per_week) + 1
	return _ints(Database.get_balance(P_VISIT_DAYS)).has(weekday)


## Agenda de la jornada: compradores distintos de la cartera, horas de compradores.horas_visita.
static func generate_visits(day: int, roster: Array[Dictionary], rng: RandomNumberGenerator,
		unit_price: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if roster.is_empty() or not is_visit_day(day):
		return out
	var ids: Array[String] = []
	for buyer: Dictionary in roster:
		ids.append(str(buyer[B_ID]))
	_shuffle(ids, rng)
	var hours: Array[int] = _ints(Database.get_balance(P_HOURS))
	var count: int = mini(Database.get_balance_int(P_VISITS), ids.size())
	for i: int in count:
		var hour: int = hours[i % hours.size()] if not hours.is_empty() \
				else Database.get_balance_int(P_DAY_START)
		out.append(make_visit(ids[i], day, hour, roll_pairs(rng), unit_price))
	return out


static func make_visit(buyer_id: String, day: int, hour: int, pairs: int,
		unit_price: float) -> Dictionary:
	return {
		V_BUYER: buyer_id, V_DAY: day, V_HOUR: hour, V_PAIRS: pairs, V_PRICE: unit_price,
		V_VALUE: roundi(pairs * unit_price), V_STATUS: STATUS_WAITING, V_OPERATION: "",
		V_OUTCOME: "",
	}


static func roll_pairs(rng: RandomNumberGenerator) -> int:
	var low: int = Database.get_balance_int(P_PAIRS_MIN)
	return rng.randi_range(low, maxi(Database.get_balance_int(P_PAIRS_MAX), low))


## Visita + ficha del comprador (lo que ve la interfaz).
static func visit_view(visit: Dictionary, buyer: Dictionary) -> Dictionary:
	var out: Dictionary = visit.duplicate(true)
	out["name"] = display_name(buyer)
	out[B_FIRST] = str(buyer.get(B_FIRST, ""))
	out[B_LAST] = str(buyer.get(B_LAST, ""))
	out[B_FIRM] = str(buyer.get(B_FIRM, ""))
	out[B_TRAITS] = _as_dict(buyer.get(B_TRAITS, {})).duplicate()
	out[B_SEED] = int(buyer.get(B_SEED, 0))
	out["holds_material"] = not (buyer.get(B_MATERIAL, []) as Array).is_empty()
	return out


## Nombre propio del comprador (del name_bank: literal permitido).
static func display_name(buyer: Dictionary) -> String:
	return NAME_FORMAT % [str(buyer.get(B_FIRST, "")), str(buyer.get(B_LAST, ""))]


## Ficha leída de JSON con sus tipos (rasgos y semilla enteros).
static func normalize_buyer(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	var traits: Dictionary = {}
	var source: Dictionary = _as_dict(raw.get(B_TRAITS, {}))
	for key: Variant in source:
		traits[str(key)] = int(source[key])
	out[B_TRAITS] = traits
	out[B_SEED] = int(raw.get(B_SEED, 0))
	out[B_MATERIAL] = (raw.get(B_MATERIAL, []) as Array).duplicate(true) \
			if raw.get(B_MATERIAL, []) is Array else []
	return out


# ─── Resolución por rasgos (puro) ─────────────────────────────

## Resultado de una operación según los rasgos del comprador y una tirada en [0, 1).
static func resolve(operation: String, traits: Dictionary, roll: float) -> String:
	match operation:
		OP_HONEST:
			return OUTCOME_SOLD
		OP_OVERPRICE:
			return OUTCOME_DETECTED if detects_overprice(traits) else OUTCOME_SOLD
		OP_PHANTOM:
			return OUTCOME_SOLD if _trait(traits, TRAIT_GREED) \
					>= Database.get_balance_int(P_PHANTOM_GREED) else _refusal(traits)
		OP_KICKBACK:
			return OUTCOME_SOLD if accepts_kickback(traits, roll) else _refusal(traits)
	return ""


## «Uno con Perspicacia elevada detecta el sobreprecio en el acto».
static func detects_overprice(traits: Dictionary) -> bool:
	return _trait(traits, TRAIT_PERCEPTION) >= Database.get_balance_int(P_DETECT)


## «Uno con Codicia elevada acepta la mordida sin objeción»; por debajo, codicia/100.
static func accepts_kickback(traits: Dictionary, roll: float) -> bool:
	var greed: int = _trait(traits, TRAIT_GREED)
	return greed >= Database.get_balance_int(P_KICKBACK_GREED) or roll < greed / TRAIT_SCALE


## Probabilidad de que un sobreprecio no detectado acabe en reclamación.
static func claim_probability(traits: Dictionary) -> float:
	return clampf(_trait(traits, TRAIT_PERCEPTION) / TRAIT_SCALE
			* Database.get_balance_float(P_CLAIM_FACTOR), 0.0, 1.0)


static func get_operation_label_key(operation: String) -> String:
	return str(OPERATION_LABEL_KEYS.get(operation, ""))


static func get_outcome_label_key(outcome: String) -> String:
	return str(OUTCOME_LABEL_KEYS.get(outcome, ""))


static func get_reason_label_key(reason: String) -> String:
	return str(REASON_LABEL_KEYS.get(reason, ""))


# ─── Operaciones (manos) ──────────────────────────────────────

## {allowed, reason}: el comprador espera hoy, el jugador vende y está en la sala.
static func can_operate(buyer_id: String) -> Dictionary:
	var visit: Dictionary = Company.get_buyer_visit(buyer_id)
	var reason: String = ""
	if visit.is_empty():
		reason = REASON_NOT_VISITING
	elif str(visit[V_STATUS]) != STATUS_WAITING:
		reason = REASON_ALREADY_SERVED
	elif not _strings(Database.get_balance(P_SELLERS)).has(PlayerState.get_occupation_id()):
		reason = REASON_NOT_A_SELLER
	elif InvestigationEngine.base_room(PlayerState.get_room()) != str(Database.get_balance(P_ROOM)):
		reason = REASON_NOT_IN_ROOM
	return {"allowed": reason.is_empty(), "reason": reason}


static func honest_sale(buyer_id: String, options: Dictionary = {}) -> Dictionary:
	return operate(buyer_id, OP_HONEST, options)


## markup ≤ 0 = compradores.sobreprecio_por_defecto.
static func overprice(buyer_id: String, markup: float = 0.0, options: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = options.duplicate()
	opts["markup"] = markup
	return operate(buyer_id, OP_OVERPRICE, opts)


static func phantom_sale(buyer_id: String, options: Dictionary = {}) -> Dictionary:
	return operate(buyer_id, OP_PHANTOM, options)


## discount ≤ 0 = compradores.descuento_por_defecto.
static func kickback_discount(buyer_id: String, discount: float = 0.0,
		options: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = options.duplicate()
	opts["discount"] = discount
	return operate(buyer_id, OP_KICKBACK, opts)


## Ejecuta una operación. opciones: markup, discount, roll (tirada fija en [0, 1)).
static func operate(buyer_id: String, operation: String, options: Dictionary = {}) -> Dictionary:
	if not OPERATIONS.has(operation):
		return _failure(buyer_id, operation, REASON_UNKNOWN_OPERATION)
	var check: Dictionary = can_operate(buyer_id)
	if not bool(check["allowed"]):
		return _failure(buyer_id, operation, str(check["reason"]))
	var visit: Dictionary = Company.get_buyer_visit(buyer_id)
	var rng: RandomNumberGenerator = _rng_for(buyer_id, operation)
	var roll: float = float(options.get("roll", rng.randf()))
	var outcome: String = resolve(operation, _as_dict(visit.get(B_TRAITS, {})), roll)
	var result: Dictionary = {
		"ok": true, "buyer_id": buyer_id, "operation": operation, "outcome": outcome,
		"reason": "", "order_value": int(visit[V_VALUE]), "income": 0, "company_loss": 0.0,
		"claim_due_day": -1, "reported": COMPLAINT_OUTCOMES.has(outcome),
	}
	if outcome == OUTCOME_SOLD:
		_apply_sale(result, visit, options, roll, rng)
	elif bool(result["reported"]):
		_complain(buyer_id)
	Company.close_buyer_visit(buyer_id, operation, outcome)
	return result


# ─── Internos ─────────────────────────────────────────────────

static func _apply_sale(result: Dictionary, visit: Dictionary, options: Dictionary, roll: float,
		rng: RandomNumberGenerator) -> void:
	var value: int = int(visit[V_VALUE])
	var buyer_id: String = str(visit[V_BUYER])
	var operation: String = str(result["operation"])
	match operation:
		OP_HONEST:
			result["income"] = roundi(value * Database.get_balance_float(P_COMMISSION))
		OP_OVERPRICE:
			result["income"] = roundi(value * _fraction(options, "markup", P_MARKUP, P_MARKUP_MAX))
			result["claim_due_day"] = _maybe_claim(visit, int(result["income"]), roll, rng)
		OP_PHANTOM:
			result["income"] = value
			result["company_loss"] = float(value)
			Company.register_sales_fraud(buyer_id, operation, int(visit[V_PAIRS]), float(value))
		OP_KICKBACK:
			var discount: int = roundi(value * _fraction(options, "discount", P_DISCOUNT,
					P_DISCOUNT_MAX))
			result["income"] = roundi(discount * Database.get_balance_float(P_KICKBACK_SHARE))
			result["company_loss"] = float(discount)
			Company.register_sales_fraud(buyer_id, operation, 0, float(discount))
			Company.add_buyer_material(buyer_id, {"type": MATERIAL_KICKBACK,
					"amount": int(result["income"])})
	PlayerState.add_money(int(result["income"]), MONEY_REASON_FORMAT % operation)
	if operation != OP_HONEST:
		_emit_fraud(result)


## Contabilidad (§9.4): el fraude del periodo (lo desviado: la diferencia, el importe fantasma o
## el descuento) lo destapa Security en el cierre mensual. La pérdida de la compañía ya la lleva
## Company (register_sales_fraud): loss_booked.
static func _emit_fraud(result: Dictionary) -> void:
	var amount: int = int(result["income"])
	if str(result["operation"]) == OP_KICKBACK:
		amount = roundi(float(result["company_loss"]))
	EventBus.crime_committed.emit(CRIME_FRAUD, str(Database.get_balance(P_ROOM)), {
		"amount": amount, "operation": result["operation"], "buyer_id": result["buyer_id"],
		"loss_booked": true,
	})


## Sobreprecio no detectado: reclamará con probabilidad perspicacia/100 × factor. Devuelve la
## jornada de la reclamación (-1 si no reclamará).
static func _maybe_claim(visit: Dictionary, amount: int, roll: float,
		rng: RandomNumberGenerator) -> int:
	if roll >= claim_probability(_as_dict(visit.get(B_TRAITS, {}))):
		return -1
	var weeks: int = rng.randi_range(Database.get_balance_int(P_CLAIM_WEEKS_MIN),
			maxi(Database.get_balance_int(P_CLAIM_WEEKS_MAX),
			Database.get_balance_int(P_CLAIM_WEEKS_MIN)))
	var due: int = GameClock.get_day() + weeks * Database.get_balance_int(P_DAYS_PER_WEEK)
	Company.schedule_buyer_claim(str(visit[V_BUYER]), amount, due, OP_OVERPRICE)
	return due


## Queja en el acto ante el superior: reputación y denuncia (BeliefNet + Security).
static func _complain(buyer_id: String) -> void:
	PlayerState.modify_reputation(-Database.get_balance_float(P_REPUTATION), REPUTATION_REASON)
	EventBus.npc_reported_player.emit(buyer_id, str(Database.get_balance(P_CHANNEL)), 0.0,
			str(Database.get_balance(P_ROOM)))


static func _refusal(traits: Dictionary) -> String:
	return OUTCOME_REPORTED if _trait(traits, TRAIT_LOYALTY) \
			>= Database.get_balance_int(P_LOYALTY_REPORT) else OUTCOME_REFUSED


## Fracción pedida (markup / discount) acotada a (0, máximo]; ≤ 0 = la de por defecto.
static func _fraction(options: Dictionary, key: String, default_path: String,
		max_path: String) -> float:
	var value: float = float(options.get(key, 0.0))
	if value <= 0.0:
		value = Database.get_balance_float(default_path)
	return minf(value, Database.get_balance_float(max_path))


static func _failure(buyer_id: String, operation: String, reason: String) -> Dictionary:
	return {"ok": false, "buyer_id": buyer_id, "operation": operation, "outcome": "",
			"reason": reason, "order_value": 0, "income": 0, "company_loss": 0.0,
			"claim_due_day": -1, "reported": false}


static func _rng_for(buyer_id: String, operation: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([RNG_SALT, GameClock.get_run_seed(), GameClock.get_day(), buyer_id, operation])
	return rng


static func _roll_traits(rng: RandomNumberGenerator) -> Dictionary:
	var low: int = Database.get_balance_int(P_TRAIT_MIN)
	var high: int = maxi(Database.get_balance_int(P_TRAIT_MAX), low)
	var out: Dictionary = {}
	for trait_name: String in Validate.TRAIT_NAMES:
		out[trait_name] = rng.randi_range(low, high)
	return out


static func _trait(traits: Dictionary, trait_name: String) -> int:
	return int(traits.get(trait_name, Validate.TRAIT_MIN))


## Fisher-Yates con el RNG de la agenda (reproducible).
static func _shuffle(values: Array[String], rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = values[i]
		values[i] = values[j]
		values[j] = tmp


static func _pick(values: Array, rng: RandomNumberGenerator) -> String:
	return "" if values.is_empty() else str(values[rng.randi_range(0, values.size() - 1)])


static func _as_dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out


static func _ints(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for item: Variant in value:
			out.append(int(item))
	return out
