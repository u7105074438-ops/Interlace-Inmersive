# buyers_case.gd — Cuerpo de test_buyers: cartera y agenda de compradores de la sala de demostraciones y las cuatro operaciones (venta honesta, sobreprecio, venta fantasma, descuento con mordida) resueltas por los rasgos de cada comprador (§11.5, PASO 41).
# PROPIETARIO DE: nada.
# ESCUCHA: crime_committed, npc_reported_player, notebook_entry_added, investigation_opened (solo para comprobarlas).
extends TestCase

const EPS := 0.01
const DEMO_ROOM := "buyer_demo_room"
const SELLER := "senior_sales"
const ORDER_PAIRS := 100
const PRICE_FACTORS: Array[String] = ["perception", "greed", "loyalty"]
const HIGH := 90
const MID := 60
const LOW := 20
const LOW_ROLL := 0.1
const MID_ROLL := 0.5
const HIGH_ROLL := 0.95
const MARKUP := 0.2
const START_REPUTATION := 50.0
const SIGNALS: Array[String] = [
	"crime_committed", "npc_reported_player", "notebook_entry_added", "investigation_opened",
]

var _log: Dictionary = {}


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	_test_roster()
	_test_schedule()
	_test_requirements()
	_test_honest_sale()
	_test_overprice()
	_test_overprice_claim()
	_test_phantom_sale()
	_test_kickback()
	_test_resolution_matrix()
	_test_save_load()


# ─── Cartera y agenda ─────────────────────────────────────────

func _test_roster() -> void:
	var roster: Array[Dictionary] = Company.get_buyer_roster()
	check_eq(roster.size(), Database.get_balance_int("compradores.tamano_cartera"),
			"the roster has compradores.tamano_cartera buyers")
	var ids: Array = []
	var ok: bool = true
	for buyer: Dictionary in roster:
		ids.append(buyer["id"])
		ok = ok and not str(buyer["first_name"]).is_empty()
		ok = ok and not str(buyer["last_name"]).is_empty()
		ok = ok and str(buyer["firm_key"]).begins_with("BUYER_FIRM_")
		ok = ok and (buyer["traits"] as Dictionary).size() == Validate.TRAIT_NAMES.size()
		for value: Variant in (buyer["traits"] as Dictionary).values():
			ok = ok and int(value) >= Database.get_balance_int("compradores.rasgo_min") \
					and int(value) <= Database.get_balance_int("compradores.rasgo_max")
	check(ok, "every buyer has a name, a firm and the six standard traits in range")
	check_eq(_unique(ids).size(), roster.size(), "buyer ids are unique")
	_fresh()
	check_eq(Company.get_buyer_roster(), roster, "the same seed generates the same roster")


func _test_schedule() -> void:
	_fresh()
	var visit_days: Array = []
	for day: int in range(1, 11):
		if Company.is_buyer_visit_day(day):
			visit_days.append(day)
	check_eq(visit_days, [2, 4, 7, 9], "buyers come on the 2nd and 4th day of each week")
	check(Company.get_buyers_today().is_empty(), "day 1: nobody in the demo room")
	GameClock.advance_to_next_day()
	var today: Array[Dictionary] = Company.get_buyers_today()
	check_eq(today.size(), Database.get_balance_int("compradores.visitas_por_dia"),
			"day 2: the scheduled visits")
	var ok: bool = true
	var price: float = float(Company.get_fundamentals()["avg_price"])
	for visit: Dictionary in today:
		ok = ok and visit["status"] == "waiting" and int(visit["order_value"]) \
				== roundi(int(visit["pairs"]) * price)
		ok = ok and int(visit["pairs"]) >= Database.get_balance_int("compradores.pares_pedido_min")
		ok = ok and not str(visit["name"]).is_empty() and visit.has("traits")
	check(ok, "each visit: waiting, an order at the average price, with the buyer's card")
	check(today[0]["buyer_id"] != today[1]["buyer_id"], "two different buyers")
	check(_notes("NOTE_BUYERS_TODAY").has([today.size()]), "the notebook announces the buyers")


func _test_requirements() -> void:
	_fresh()
	var buyer: String = _visit({})
	check_eq(Buyers.can_operate(buyer)["reason"], "not_a_seller", "an email worker cannot sell")
	PlayerState.set_occupation(SELLER, "test")
	_enter("wing_3b")
	check_eq(Buyers.can_operate(buyer)["reason"], "not_in_demo_room",
			"buyers are received in the demo room")
	_enter(DEMO_ROOM)
	check(bool(Buyers.can_operate(buyer)["allowed"]), "a salesman in the demo room can deal")
	check_eq(Buyers.can_operate("buyer_nobody")["reason"], "not_visiting", "unknown buyer")
	check_eq(Buyers.operate(buyer, "barter")["reason"], "unknown_operation", "unknown operation")
	check_eq(Buyers.get_reason_label_key("not_in_demo_room"), "BUYER_REASON_NOT_IN_ROOM",
			"reasons have text keys")


# ─── Las cuatro operaciones ───────────────────────────────────

func _test_honest_sale() -> void:
	_fresh()
	var buyer: String = _seller_with({})
	var value: int = _value(buyer)
	var money: int = PlayerState.get_money()
	var result: Dictionary = Buyers.honest_sale(buyer)
	var commission: int = roundi(value * Database.get_balance_float("compradores.comision_legal"))
	check(bool(result["ok"]) and result["outcome"] == "sold", "the honest sale closes")
	check_eq(PlayerState.get_money() - money, commission, "a small legal commission")
	check(_calls("crime_committed").is_empty() and _calls("npc_reported_player").is_empty(),
			"no crime, no complaint: no risk")
	check_eq(Company.get_buyer_visit(buyer)["status"], "closed", "the visit is closed")
	check_eq(Buyers.honest_sale(buyer)["reason"], "already_served", "one deal per visit")


func _test_overprice() -> void:
	_fresh()
	PlayerState.modify_reputation(START_REPUTATION, "test")
	var sharp: String = _seller_with({"perception": HIGH})
	var money: int = PlayerState.get_money()
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	var result: Dictionary = Buyers.overprice(sharp, MARKUP)
	check(result["outcome"] == "detected" and int(result["income"]) == 0,
			"a perceptive buyer detects the overprice on the spot: no deal")
	check(PlayerState.get_money() == money and _crimes("fraud").is_empty(), "nothing pocketed")
	check_near(PlayerState.get_reputation(), START_REPUTATION
			- Database.get_balance_float("compradores.reputacion_por_queja"), EPS,
			"the complaint costs reputation")
	check(_calls("npc_reported_player").has([sharp, "superior", 0.0, DEMO_ROOM]),
			"the buyer complains to the superior (npc_reported_player)")
	check(BeliefNet.calculate_player_suspicion() > suspicion, "the complaint raises suspicion")
	var dull: String = _next_buyer({"perception": LOW})
	var value: int = _value(dull)
	result = Buyers.overprice(dull, MARKUP, {"roll": HIGH_ROLL})
	check(result["outcome"] == "sold" and int(result["income"]) == roundi(value * MARKUP),
			"an unobservant buyer pays: the whole difference goes to the pocket")
	check_eq(PlayerState.get_money() - money, roundi(value * MARKUP), "money in the pocket")
	var fraud: Array = _crimes("fraud")
	check(fraud.size() == 1 and int(fraud[0][2]["amount"]) == roundi(value * MARKUP),
			"crime_committed(fraud, {amount}): accounting can find it")
	check(int(result["claim_due_day"]) == -1 and Company.get_pending_buyer_claims().is_empty(),
			"a high roll: no claim")
	var greedy_markup: String = _next_buyer({"perception": LOW})
	var capped: Dictionary = Buyers.overprice(greedy_markup, 1.0, {"roll": HIGH_ROLL})
	check_eq(int(capped["income"]), roundi(_value(greedy_markup)
			* Database.get_balance_float("compradores.sobreprecio_max")), "the markup is capped")


## §11.5 «el comprador puede reclamar semanas después».
func _test_overprice_claim() -> void:
	_fresh()
	var buyer: String = _seller_with({"perception": MID})
	var today: int = GameClock.get_day()
	var result: Dictionary = Buyers.overprice(buyer, MARKUP, {"roll": LOW_ROLL})
	var due: int = int(result["claim_due_day"])
	var week: int = Database.get_balance_int("tiempo.jornadas_por_semana")
	var earliest: int = today + _bi("compradores.semanas_reclamacion_min") * week
	var latest: int = today + _bi("compradores.semanas_reclamacion_max") * week
	check(result["outcome"] == "sold" and due >= earliest and due <= latest,
			"a mid-perception buyer will claim weeks later")
	check_eq(Company.get_pending_buyer_claims().size(), 1, "the claim waits in Company")
	check(_calls("npc_reported_player").is_empty(), "no complaint on the day of the sale")
	var soon: String = _next_buyer({})
	Company.schedule_buyer_claim(soon, 100, today + 1, "overprice")
	GameClock.advance_to_next_day()
	check(_calls("npc_reported_player").has([soon, "superior", 0.0, DEMO_ROOM]),
			"when the claim falls due the buyer complains to the superior")
	check_eq(Company.get_pending_buyer_claims().size(), 1, "only the due claim is consumed")
	check(_notes("NOTE_BUYER_CLAIM").size() == 1, "the notebook records the claim")


func _test_phantom_sale() -> void:
	_fresh()
	var greedy: String = _seller_with({"greed": HIGH})
	var value: int = _value(greedy)
	var money: int = PlayerState.get_money()
	var losses: float = Company.get_total_theft_losses()
	var result: Dictionary = Buyers.phantom_sale(greedy)
	check(result["outcome"] == "sold" and PlayerState.get_money() - money == value,
			"a greedy buyer takes the off-the-books deal: the full amount to the pocket")
	check(_crimes("fraud").size() == 1 and bool(_crimes("fraud")[0][2]["loss_booked"]),
			"a fraud whose loss Company carries")
	check_eq(Company.get_pending_sales_frauds().size(), 1, "the missing goods wait for month close")
	check_near(Company.get_total_theft_losses(), losses, EPS, "nothing shows before month close")
	var honest: String = _next_buyer({"greed": LOW, "loyalty": HIGH})
	result = Buyers.phantom_sale(honest)
	check(result["outcome"] == "reported" and bool(result["reported"]),
			"a loyal, honest buyer refuses and complains")
	var shy: String = _next_buyer({"greed": LOW, "loyalty": LOW})
	check_eq(Buyers.phantom_sale(shy)["outcome"], "refused", "a disloyal honest buyer just refuses")
	EventBus.month_closed.emit(1)
	check_near(Company.get_total_theft_losses() - losses, float(value), EPS,
			"month close: the inventory does not match, the loss enters the books")
	check_eq(int(Company.get_last_month_report()["pairs"]), ORDER_PAIRS, "the month report")
	check(_opened("fraud_at_month_close"), "and Security surfaces the fraud at month close")


func _test_kickback() -> void:
	_fresh()
	var greedy: String = _seller_with({"greed": HIGH})
	var value: int = _value(greedy)
	var money: int = PlayerState.get_money()
	var result: Dictionary = Buyers.kickback_discount(greedy, 0.0, {"roll": HIGH_ROLL})
	var discount: int = roundi(value * _bf("compradores.descuento_por_defecto"))
	var kickback: int = roundi(discount * _bf("compradores.fraccion_mordida"))
	check(result["outcome"] == "sold", "a greedy buyer accepts the kickback without objection")
	check_eq(PlayerState.get_money() - money, kickback, "the buyer pays the player directly")
	check_eq(int(Company.get_pending_sales_frauds()[0]["amount"]), discount,
			"the discount is the company's loss at month close")
	var leverage: Array[Dictionary] = Company.get_buyer_leverage()
	check(leverage.size() == 1 and leverage[0]["buyer_id"] == greedy
			and leverage[0]["material"][0]["type"] == "kickback",
			"the buyer gains blackmail material")
	check(bool(Company.get_buyer_visit(greedy)["holds_material"]), "visible on the buyer's card")
	var tempted: String = _next_buyer({"greed": 40, "loyalty": LOW})
	check_eq(Buyers.kickback_discount(tempted, 0.0, {"roll": LOW_ROLL})["outcome"], "sold",
			"a mid-greed buyer accepts with probability greed/100 (low roll)")
	var firm: String = _next_buyer({"greed": 40, "loyalty": LOW})
	check_eq(Buyers.kickback_discount(firm, 0.0, {"roll": MID_ROLL})["outcome"], "refused",
			"… and refuses on a high roll")
	var upright: String = _next_buyer({"greed": 40, "loyalty": HIGH})
	check_eq(Buyers.kickback_discount(upright, 0.0, {"roll": MID_ROLL})["outcome"], "reported",
			"a loyal buyer who refuses complains")


func _test_resolution_matrix() -> void:
	var cases: Array = [
		["honest_sale", {}, HIGH_ROLL, "sold"],
		["overprice", {"perception": 70}, HIGH_ROLL, "detected"],
		["overprice", {"perception": 69}, LOW_ROLL, "sold"],
		["phantom_sale", {"greed": 60}, HIGH_ROLL, "sold"],
		["phantom_sale", {"greed": 59, "loyalty": 70}, LOW_ROLL, "reported"],
		["phantom_sale", {"greed": 59, "loyalty": 69}, LOW_ROLL, "refused"],
		["kickback_discount", {"greed": 70}, HIGH_ROLL, "sold"],
		["kickback_discount", {"greed": 30}, 0.29, "sold"],
		["kickback_discount", {"greed": 30, "loyalty": 70}, 0.3, "reported"],
	]
	for c: Array in cases:
		check_eq(Buyers.resolve(c[0], c[1], c[2]), c[3], "%s with %s, roll %.2f → %s" % c)
	check_near(Buyers.claim_probability({"perception": MID}), 0.6, EPS,
			"claim probability = perception/100")


func _test_save_load() -> void:
	_fresh()
	var buyer: String = _seller_with({"perception": MID, "greed": HIGH})
	Buyers.overprice(buyer, MARKUP, {"roll": LOW_ROLL})
	var other: String = _next_buyer({"greed": HIGH})
	Buyers.kickback_discount(other)
	var roster: Array[Dictionary] = Company.get_buyer_roster()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(saved)
	check_eq(Company.get_buyer_roster(), roster, "the roster (traits, material) survives JSON")
	check(Company.get_buyer(buyer)["traits"]["perception"] is int, "traits come back as ints")
	check_eq(Company.get_pending_buyer_claims().size(), 1, "pending claims survive")
	check_eq(Company.get_pending_sales_frauds().size(), 1, "pending sales frauds survive")
	check_eq(Company.get_buyer_visit(buyer)["status"], "closed", "today's visits survive")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


## Trae hoy al primer comprador de la cartera que aún no vino, con esos rasgos (resto: medios).
func _visit(traits: Dictionary) -> String:
	for buyer: Dictionary in Company.get_buyer_roster():
		var id: String = str(buyer["id"])
		if Company.schedule_buyer_visit(id, ORDER_PAIRS):
			var full: Dictionary = {"perception": MID - 1, "greed": MID - 1, "loyalty": MID - 1}
			full.merge(traits, true)
			Company.set_buyer_traits(id, full)
			return id
	return ""


func _seller_with(traits: Dictionary) -> String:
	PlayerState.set_occupation(SELLER, "test")
	_enter(DEMO_ROOM)
	return _visit(traits)


func _next_buyer(traits: Dictionary) -> String:
	return _visit(traits)


func _value(buyer_id: String) -> int:
	return int(Company.get_buyer_visit(buyer_id)["order_value"])


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _enter(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)


func _crimes(crime_type: String) -> Array:
	var out: Array = []
	for call: Array in _calls("crime_committed"):
		if call[0] == crime_type:
			out.append(call)
	return out


func _opened(incident_type: String) -> bool:
	for call: Array in _calls("investigation_opened"):
		if call[1] == incident_type:
			return true
	return false


func _notes(text_key: String) -> Array:
	var out: Array = []
	for call: Array in _calls("notebook_entry_added"):
		if call[1] == text_key:
			out.append(call[2])
	return out


static func _unique(values: Array) -> Array:
	var out: Array = []
	for value: Variant in values:
		if not out.has(value):
			out.append(value)
	return out


func _connect_bus() -> void:
	for signal_name: String in SIGNALS:
		EventBus.connect(signal_name, _record.bind(signal_name))


func _record(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	if not _log.has(signal_name):
		_log[signal_name] = []
	_log[signal_name].append(args)


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()
