# factory_case.gd — Cuerpo de test_factory: las tres escalas del robo en fábrica y sus requisitos (existencias, tope semanal, inventario), el producto robado como contrabando hasta su reventa, el recuento semanal como consecuencia retardada (peso §12.3, lotes y patrón), la pérdida en los fundamentales y en los márgenes, y los albaranes falsificados del capataz que desvían el descuadre (§11.3, §11.6, §12.3, PASO 41).
# PROPIETARIO DE: nada.
# ESCUCHA: crime_committed, investigation_opened, evidence_added, notebook_entry_added, week_closed (solo para comprobarlas).
extends TestCase

const EPS := 0.01
## Tabla §11.6 del manual: [pares min, pares max, ingreso min, ingreso max, rango min].
const MANUAL_SCALES: Dictionary = {
	"pocket": [1, 2, 40, 80, 3], "box": [10, 20, 400, 900, 8],
	"pallet": [200, 400, 8000, 18000, 15],
}
## §12.3 fase 1: «Descuadre de inventario: 2,0».
const MANUAL_MISMATCH_WEIGHT := 2.0
const FACTORY_ROOM := "finished_goods"
const DOCK_ROOM := "loading_dock"
const FOREMAN_OFFICE := "foreman_office"
const STORE_ROOM := "flagship_store"
const OFFICE_ROOM := "wing_3b"
const BOX_PAIRS := 15
const BOX_INCOME := 650
const SMALL_BOX_PAIRS := 12
const PALLET_PAIRS := 300
const PALLET_INCOME := 13000
const WEEK_DAYS := 5
const SIGNALS: Array[String] = [
	"crime_committed", "investigation_opened", "evidence_added", "notebook_entry_added",
	"week_closed",
]

var _log: Dictionary = {}
## Incidentes de descuadre pendientes en Security justo tras el último week_closed (antes de que
## el cambio de jornada los caduque).
var _pending_at_close: Array = []


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	check(FactoryTheft.is_calendar_connected(),
			"Company wires the weekly count to week_closed at boot (no hands call needed)")
	_test_manual_table()
	_test_requirements()
	_test_goods_limits()
	_test_pallet_requirements()
	_test_contraband_and_fence()
	_test_delayed_weekly_detection()
	_test_quantity_opens_a_case()
	_test_weekly_pattern()
	_test_compensated_inventory()
	_test_pocket_is_absorbed()
	_test_responsible_foreman()
	_test_forgery_is_the_foremans()
	_test_forged_notes_redirect()
	_test_pallet_in_margins()
	_test_save_load_without_hands()


# ─── Tabla y requisitos ───────────────────────────────────────

func _test_manual_table() -> void:
	for scale: String in MANUAL_SCALES:
		var cfg: Dictionary = FactoryTheft.get_scale_config(scale)
		var row: Array = MANUAL_SCALES[scale]
		check_eq([int(cfg["pares_min"]), int(cfg["pares_max"]), int(cfg["ingreso_min"]),
				int(cfg["ingreso_max"]), int(cfg["rango_min"])], row,
				"§11.6 table row for %s" % scale)
		check_eq(FactoryTheft.income_for(scale, int(row[0])), int(row[2]),
				"%s: the fewest pairs pay the table minimum" % scale)
		check_eq(FactoryTheft.income_for(scale, int(row[1])), int(row[3]),
				"%s: the most pairs pay the table maximum" % scale)
	check_eq(FactoryTheft.income_for("box", BOX_PAIRS), BOX_INCOME, "income interpolates by pairs")
	check_near(FactoryTheft.incident_base_weight(), MANUAL_MISMATCH_WEIGHT, EPS,
			"the count uses the §12.3 weight of an inventory mismatch")


func _test_requirements() -> void:
	_fresh()
	_become("email_worker_3b", FACTORY_ROOM)
	check_eq(_missing("pocket", {}), ["rank"], "R1 inside the factory: rank too low for a pocket")
	_become("line_operator", FACTORY_ROOM)
	check(bool(FactoryTheft.check_requirements("pocket")["allowed"]),
			"R3 inside the factory: pocket")
	_enter(OFFICE_ROOM)
	check_eq(_missing("pocket", {}), ["location"], "a pocket theft needs to be inside the factory")
	_enter(FACTORY_ROOM)
	check(_missing("box", {}).has("rank"), "R3 cannot take a box (R8+)")
	_become("junior_accountant", FACTORY_ROOM)
	check_eq(_missing("box", {}), ["cart"], "R8 without cart nor freight clearance: needs a cart")
	check(bool(FactoryTheft.check_requirements("box", {"cart": true})["allowed"]),
			"R8 pushing a cart can take a box")
	_check_cart_item()
	_become("senior_sales", FACTORY_ROOM)
	check(bool(FactoryTheft.check_requirements("box")["allowed"]),
			"R10 with freight-elevator clearance can take a box")
	check_eq(_missing("crate", {}), ["scale"], "an unknown scale is refused")
	var money: int = PlayerState.get_money()
	_clear()
	_become("email_worker_3b", FACTORY_ROOM)
	var result: Dictionary = FactoryTheft.steal("box")
	check(not bool(result["ok"]) and result["reason"] == "requirements",
			"a refused theft reports why")
	check(PlayerState.get_money() == money and _calls("crime_committed").is_empty(),
			"a refused theft pays nothing and commits nothing")
	check_eq(FactoryTheft.get_missing_label_key("cart"), "FACTORY_MISSING_CART",
			"each missing requirement has a text key")


## Un puesto que entrega un carrito (fabrica.objetos_carro) cumple el requisito de la caja.
func _check_cart_item() -> void:
	var tools: Array[String] = PlayerState.get_occupation().tools
	var cart: String = str(Database.get_balance("fabrica.objetos_carro")[0])
	tools.append(cart)
	check(FactoryTheft.has_cart_or_freight() and bool(FactoryTheft.check_requirements("box")
			["allowed"]), "R8 whose post issues a trolley can take a box")
	tools.erase(cart)
	check(not FactoryTheft.has_cart_or_freight(), "without the trolley, no cart again")


## «No un botón de generación de capital»: existencias, tope semanal e inventario lleno.
func _test_goods_limits() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	for i: int in _bi("fabrica.escalas.box.max_por_semana"):
		check(bool(FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})["ok"]),
				"box %d of the week" % (i + 1))
	check(_missing("box", {}).has("limit"), "the weekly cap of boxes is reached")
	check_eq(FactoryTheft.steal("box")["missing"], ["limit"], "a further box is refused")
	check(bool(FactoryTheft.check_requirements("pocket")["allowed"]), "other scales still can")
	EventBus.week_closed.emit(1)
	check(not _missing("box", {}).has("limit"), "the count resets the weekly cap")
	Company.register_factory_theft("pallet", Company.get_finished_goods_stock() - SMALL_BOX_PAIRS
			+ 1, 0.0, FACTORY_ROOM)
	check(_missing("box", {"pairs": SMALL_BOX_PAIRS}).has("stock"),
			"the shelves hold fewer pairs than the box: refused")
	check(not _missing("pocket", {}).has("stock"), "a pocket still fits in what is left")
	check(PlayerState.get_item_count("product_box") == 2 and not _missing("box", {})
			.has("capacity"), "the carried boxes stack in one position")
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	_fill_inventory()
	check(_missing("box", {}).has("capacity"), "no room to carry the box: refused")
	check(_missing("pocket", {}).has("capacity"), "nor a pair without a stack to join")


func _test_pallet_requirements() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	var missing: Array = _missing("pallet", {})
	check(missing.has("rank") and missing.has("occupation"),
			"R10 salesman: a pallet needs R15+ and the foreman/director post")
	_become("wing_3b_chief", FACTORY_ROOM)
	check(_missing("pallet", {}).has("occupation") and not _missing("pallet", {}).has("rank"),
			"R15 outside the factory line: occupation missing")
	_become("factory_foreman", DOCK_ROOM)
	check_eq(FactoryTheft.find_accomplice(), "", "no haulier owes the player anything yet")
	check_eq(_missing("pallet", {}), ["accomplice"], "foreman without an accomplice carrier")
	var carrier: String = _dock_worker()
	check(not carrier.is_empty(), "the population has dock workers (carriers)")
	NPCDirector.add_debt(carrier, 1)
	check(FactoryTheft.is_accomplice(carrier), "a carrier who owes the player is an accomplice")
	check(bool(FactoryTheft.check_requirements("pallet")["allowed"]),
			"foreman + accomplice: pallet")
	check_eq(_missing("pallet", {"accomplice_id": _seat("email_worker_3b")}), ["accomplice"],
			"an office worker is no haulier")
	_fresh()
	_become("factory_director", DOCK_ROOM)
	check(FactoryTheft.hires_accomplices() and bool(FactoryTheft.check_requirements("pallet")
			["allowed"]), "the factory director hires accomplice hauliers (§23.6)")


# ─── Contrabando y reventa (§11.3) ─────────────────────────────

func _test_contraband_and_fence() -> void:
	_fresh()
	_become("line_operator", FACTORY_ROOM)
	var money: int = PlayerState.get_money()
	var result: Dictionary = FactoryTheft.steal("pocket", {"pairs": 2})
	check(bool(result["ok"]) and int(result["income"]) == 0
			and int(result["resale_value"]) == 80, "a pocket theft pays nothing yet (worth 80 €)")
	check_eq(PlayerState.get_item_count("product_pair"), 2, "two pairs in the pocket")
	check(PlayerState.has_hot_items(), "stolen product is compromising (§11.3)")
	check_eq(PlayerState.get_money(), money, "no money until the goods are fenced")
	check_eq(FactoryTheft.fence()["reason"], "not_at_fence", "nobody buys it in the factory")
	_enter(STORE_ROOM)
	var sold: Dictionary = FactoryTheft.fence()
	check(bool(sold["ok"]) and int(sold["income"]) == 80 and int(sold["units"]) == 2,
			"slipped into the flagship store stock: 80 €")
	check(PlayerState.get_money() - money == 80 and not PlayerState.has_hot_items(),
			"paid, and nothing compromising left on the player")
	check(Company.get_stolen_goods().is_empty(), "the resale lot is used up")
	check_eq(FactoryTheft.fence()["reason"], "nothing_to_fence", "nothing left to fence")
	check_eq(FactoryTheft.get_reason_label_key("not_at_fence"), "FACTORY_REASON_NOT_AT_FENCE",
			"fence reasons have text keys")
	_check_box_contraband()


func _check_box_contraband() -> void:
	_become("senior_sales", FACTORY_ROOM)
	var money: int = PlayerState.get_money()
	FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	check_eq(PlayerState.get_item_count("product_box"), 1, "a box goes onto the cart")
	check(InventoryRules.is_bulky(InventoryRules.make_item("product_box")),
			"a box is bulky: it does not fit every hiding spot")
	_enter(STORE_ROOM)
	check_eq(int(FactoryTheft.fence()["income"]), BOX_INCOME, "the box resells for its lot value")
	check_eq(PlayerState.get_money() - money, BOX_INCOME, "650 € once fenced")


# ─── El recuento semanal ──────────────────────────────────────

## §11.6: «los robos no se detectan en el momento: afloran en el recuento posterior».
func _test_delayed_weekly_detection() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	var losses: float = Company.get_total_theft_losses()
	var theft_line: float = float(Company.get_fundamentals()["theft_losses"])
	var result: Dictionary = FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	check(bool(result["ok"]) and int(result["pairs"]) == BOX_PAIRS, "a box of 15 pairs is taken")
	var crime: Array = _crime("theft_product")
	check(not crime.is_empty(), "crime_committed(theft_product) is emitted")
	var details: Dictionary = crime[2] if crime.size() > 2 else {}
	check(bool(details.get("loss_booked", false)) and not bool(details.get("leaves_record", true))
			and int(details.get("quantity", 0)) == BOX_PAIRS and int(details.get("value", 0))
			== BOX_INCOME, "details: value, quantity, loss_booked, no immediate record")
	check(_mismatch_cases().is_empty() and _pending_mismatches().is_empty(),
			"no incident at the moment of the theft")
	check_near(Company.get_total_theft_losses(), losses, EPS, "no loss booked at the moment")
	check_near(float(Company.get_fundamentals()["theft_losses"]), theft_line, EPS,
			"the fundamentals do not see it yet")
	check_eq(Company.get_pending_factory_thefts().size(), 1, "the theft waits for the count")
	check_eq(Company.get_finished_goods_stock(), _bi("fabrica.stock_base_pares") - BOX_PAIRS,
			"the physical stock is short already")
	GameClock.advance_to_next_day()
	check(_pending_mismatches().is_empty(), "a day later it is still undetected")
	_advance_to_week_close()
	_check_box_count(losses)


func _check_box_count(losses_before: float) -> void:
	var loss: float = BOX_PAIRS * float(Company.get_fundamentals()["avg_price"])
	var report: Dictionary = _last_report()
	check(bool(report.get("mismatch", false)) and int(report.get("missing", 0)) == BOX_PAIRS,
			"the weekly count finds 15 pairs missing")
	check_eq(int(report.get("counted", 0)), int(report.get("expected", 0)) - BOX_PAIRS,
			"counted = expected − missing")
	check(bool(report.get("reported", false)), "the mismatch was handed to Security")
	var pending: Array = _pending_at_close
	check(pending.size() == 1 and absf(float(pending[0]["weight"]) - MANUAL_MISMATCH_WEIGHT)
			< EPS, "a lone box: an incident of weight 2.0, pending under the 3.0 threshold")
	check(_mismatch_cases().is_empty(), "one box alone does not open a case (§12.3)")
	check_near(Company.get_total_theft_losses() - losses_before, loss, EPS,
			"the loss (pairs × average price) enters Company costs at the count")
	var window: float = _bf("empresa.jornadas_ventana_contable")
	check_near(float(Company.get_fundamentals()["theft_losses"]),
			loss / window * NewsFeed.get_event_multiplier("costs_multiplier"), EPS,
			"the theft-loss line of the fundamentals shows it")
	check(_notes("NOTE_INVENTORY_MISMATCH").has([BOX_PAIRS]), "the notebook records the count")
	check(Company.get_pending_factory_thefts().is_empty(), "the count clears the pending thefts")


## Dos cajas la misma semana: dos lotes, 4,0 > 3,0: caso abierto, gravedad al alza.
func _test_quantity_opens_a_case() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	EventBus.week_closed.emit(1)
	var report: Dictionary = _last_report()
	check_eq(int(report["lots"]), 2, "two boxes are two missing lots")
	check_near(float(report["weight"]), 2 * MANUAL_MISMATCH_WEIGHT, EPS, "weight 2.0 per lot")
	check_eq(int(report["severity"]), _bi("fabrica.escalas.box.gravedad")
			+ _bi("fabrica.gravedad_por_lote_extra"), "each extra lot raises the severity")
	check_eq(_mismatch_cases().size(), 1, "Security opens an inventory_mismatch case at the count")
	var case_id: String = _last_case()
	check_eq(_points_of(case_id), [""], "without forged notes nor inventory post, it points at nobody")


## Una caja por semana: la segunda semana seguida el descuadre es un patrón y abre caso.
func _test_weekly_pattern() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	_advance_to_week_close()
	check(_mismatch_cases().is_empty(), "week 1: a lone box stays pending")
	FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	var closes: int = _calls("week_closed").size()
	_advance_to_week_close()
	check(_calls("week_closed").size() > closes, "a second week closes")
	check_eq(int(_last_report()["lots"]), 1 + _bi("fabrica.lotes_por_semana_previa"),
			"the previous mismatch week adds a lot")
	check_eq(_mismatch_cases().size(), 1, "week 2 in a row: the recurring gap opens a case")


## §12.3 palanca: «inventario compensado» — devolver el producto antes del recuento.
func _test_compensated_inventory() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	FactoryTheft.steal("pocket", {"pairs": 2})
	FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	_enter(OFFICE_ROOM)
	check_eq(FactoryTheft.return_goods()["reason"], "not_in_factory", "goods go back to the plant")
	_enter(FACTORY_ROOM)
	var back: Dictionary = FactoryTheft.return_goods()
	check(bool(back["ok"]) and int(back["units"]) == 4
			and int(back["pairs"]) == 2 + BOX_PAIRS + SMALL_BOX_PAIRS,
			"two pairs and two boxes back on the shelves")
	check(not PlayerState.has_hot_items() and Company.get_stolen_goods().is_empty(),
			"nothing left to carry or to resell")
	check(Company.get_pending_factory_thefts().is_empty()
			and Company.get_finished_goods_stock() == _bi("fabrica.stock_base_pares"),
			"the stock is whole again")
	EventBus.week_closed.emit(1)
	check(not bool(_last_report()["mismatch"]) and _pending_at_close.is_empty(),
			"the count matches: no incident at all")
	check_near(Company.get_total_theft_losses(), 0.0, EPS, "and no loss for the company")
	check_eq(FactoryTheft.return_goods()["reason"], "nothing_to_fence", "nothing left to return")


## Bolsillo: «prácticamente ningún rastro»: la merma de la semana se absorbe.
func _test_pocket_is_absorbed() -> void:
	_fresh()
	_become("line_operator", FACTORY_ROOM)
	check(bool(FactoryTheft.steal("pocket", {"pairs": 2})["ok"]), "a pocket theft of 2 pairs")
	EventBus.week_closed.emit(1)
	var report: Dictionary = _last_report()
	check(bool(report["absorbed"]) and not bool(report["mismatch"]),
			"2 pairs vanish in the count's shrinkage tolerance")
	check(_pending_mismatches().is_empty() and _notes("NOTE_INVENTORY_MISMATCH").is_empty(),
			"no incident, no notebook entry")
	check_near(Company.get_total_theft_losses(),
			2 * float(Company.get_fundamentals()["avg_price"]), EPS,
			"the loss still enters the books at the count")
	for i: int in 3:
		FactoryTheft.steal("pocket", {"pairs": 2})
	EventBus.week_closed.emit(2)
	report = _last_report()
	check(bool(report["mismatch"]) and report["scale"] == "pocket" and int(report["lots"]) == 1,
			"many pockets in one week (6 pairs) do show up, as one lot")
	check(bool(report["reported"]) and _pending_mismatches().size() == 1,
			"and that mismatch is handed to Security too")


## §11.6 riesgo del capataz: «inventory_gap_points_to_foreman».
func _test_responsible_foreman() -> void:
	_fresh()
	_become("factory_foreman", FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	EventBus.week_closed.emit(1)
	check_eq(_last_report()["points_to"], "player", "the foreman answers for the inventory gap")
	check(_points_of(_last_case()).has("player"), "the case evidence points at the player")


# ─── Albaranes falsificados ───────────────────────────────────

## §23.4: «Albaranes falsificables» es oportunidad del capataz; el muelle deja constancia.
func _test_forgery_is_the_foremans() -> void:
	_fresh()
	_become("line_operator", DOCK_ROOM)
	check_eq(FactoryTheft.forge_delivery_notes()["reason"], "not_foreman",
			"a line operator cannot sign delivery notes")
	_become("senior_sales", DOCK_ROOM)
	check_eq(FactoryTheft.forge_delivery_notes()["reason"], "not_foreman", "nor a salesman")
	check(_crime("forgery").is_empty() and Company.get_forged_delivery_target().is_empty(),
			"a refused forgery leaves nothing behind")
	_become("factory_foreman", FOREMAN_OFFICE)
	var records: int = _card_logs(FOREMAN_OFFICE)
	var forged: Dictionary = FactoryTheft.forge_delivery_notes()
	check(bool(forged["ok"]) and not bool(forged["traced"]) and _card_logs(FOREMAN_OFFICE)
			== records, "the foreman's own notes leave no issue log")
	_enter(DOCK_ROOM)
	forged = FactoryTheft.forge_delivery_notes()
	check(bool(forged["traced"]) and _card_logs(DOCK_ROOM) == 1,
			"the dock's notes are traceable: an issue log names the player")


func _test_forged_notes_redirect() -> void:
	_fresh()
	_become("factory_foreman", FACTORY_ROOM)
	var superior: String = FactoryTheft.find_direct_superior()
	check(not superior.is_empty() and superior == Company.get_seat_holder("factory_director"),
			"the foreman's direct superior is the factory director")
	check_eq(FactoryTheft.forge_delivery_notes()["reason"], "not_at_delivery_notes",
			"delivery notes are only at the dock or the foreman's office")
	_enter(FOREMAN_OFFICE)
	var silk: int = PlayerState.get_tracking("silk")
	var forged: Dictionary = FactoryTheft.forge_delivery_notes()
	check(bool(forged["ok"]) and forged["target"] == superior, "the notes are forged")
	var forgery: Array = _crime("forgery")
	check(forgery.size() > 2 and forgery[2]["subject"] == superior,
			"crime_committed(forgery) names the superior as the document's subject")
	var framing: Array = _crime("framing")
	check(framing.size() > 2 and framing[2]["target"] == superior,
			"crime_committed(framing) targets the superior")
	check(PlayerState.get_tracking("silk") > silk, "forgery feeds the SILK axis")
	check_eq(Company.get_forged_delivery_target(), superior, "this week's count will point at them")
	_enter(FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	EventBus.week_closed.emit(1)
	_check_framed_count(superior, suspicion)


## Una sola caja (2,0) bajo el umbral: los albaranes documentan el desvío y el caso se abre igual.
func _check_framed_count(superior: String, suspicion_before: float) -> void:
	var report: Dictionary = _last_report()
	check(report["framed_to"] == superior and report["points_to"] == superior,
			"the mismatch points at the superior")
	check_eq(_mismatch_cases().size(), 1, "the forged paperwork opens the case even for one box")
	var case_id: String = _last_case()
	var pieces: Array = _pieces(case_id)
	check(_has_piece(pieces, superior, "forged_document"),
			"the forged notes are a forged_document piece against the superior")
	check(not _has_piece(pieces, "player", ""), "no piece points at the player")
	check(BeliefNet.calculate_player_suspicion() > suspicion_before,
			"the player's suspicion rises: they had access too")
	check(_card_logs(FACTORY_ROOM) > 0, "an access record puts the player in the goods room")
	check_eq(Company.get_forged_delivery_target(), "", "the forged notes cover one count only")
	Security.resolve_investigation(case_id, "other_guilty", superior)
	check(not NPCDirector.is_active(superior), "the framed superior is expelled")
	check(Company.is_seat_vacant("factory_director"), "their expulsion frees the vacancy")
	check(bool(Security.get_case_report(case_id).get("culprit_innocent", false)),
			"Security's file knows the culprit was innocent")


# ─── Palé: visible en los márgenes ────────────────────────────

func _test_pallet_in_margins() -> void:
	_fresh()
	_become("factory_foreman", DOCK_ROOM)
	var carrier: String = _dock_worker()
	NPCDirector.add_debt(carrier, 1)
	var cfo: String = Company.get_seat_holder("cfo")
	check(not cfo.is_empty() and cfo != "player", "an NPC holds the CFO seat")
	var money: int = PlayerState.get_money()
	var result: Dictionary = FactoryTheft.steal("pallet", {"pairs": PALLET_PAIRS,
			"accomplice_id": carrier})
	check(bool(result["ok"]) and int(result["income"]) == PALLET_INCOME
			and result["accomplice"] == carrier, "a pallet of 300 pairs with the carrier: 13 000 €")
	check_eq(PlayerState.get_money() - money, PALLET_INCOME, "the carrier sells it: paid at once")
	check_eq(PlayerState.get_item_count("product_pallet_note"), 1,
			"the player keeps the consignment note (a compromising document)")
	check_eq(NPCDirector.get_debt(carrier), 0, "the accomplice's debt is spent on the pallet")
	check(_holds_belief_about_player(carrier), "and the accomplice knows what they carried")
	check_eq(FactoryTheft.steal("pallet", {"pairs": PALLET_PAIRS})["missing"].has("limit"), true,
			"one pallet a week")
	_check_pallet_count(cfo)


func _check_pallet_count(cfo: String) -> void:
	var before: Dictionary = Company.get_fundamentals()
	EventBus.week_closed.emit(1)
	var report: Dictionary = _last_report()
	check(bool(report["cfo_detected"]) and report["cfo_id"] == cfo, "the CFO sees it in the margins")
	check_eq(_mismatch_cases().size(), 1, "the CFO's accounting trail opens the case")
	var case_id: String = _last_case()
	check(_has_piece(_pieces(case_id), "player", "accounting_trail"),
			"an accounting-trail piece (the foreman answers for the inventory)")
	var holders: Dictionary = Security.save_state()["meta"].get(case_id, {}).get("holders", {})
	check(holders.values().has(cfo), "the CFO is the witness who holds it")
	var loss: float = PALLET_PAIRS * float(before["avg_price"]) \
			* _bf("fabrica.escalas.pallet.factor_coste_margenes")
	check_near(float(report["margin_loss"]), loss, EPS, "the lost consignment's cost")
	GameClock.advance_to_next_day()
	var hit: Dictionary = Company.get_fundamentals()
	var line: float = float(hit["theft_losses"])
	check_near(line, loss * NewsFeed.get_event_multiplier("costs_multiplier"), EPS,
			"the next day's margins carry the whole loss")
	check(line > _bf("mercado.ruido_diario_max") * (float(hit["profit"]) + line),
			"a dent in the daily profit larger than the Market's daily noise")
	GameClock.advance_to_next_day()
	check_near(float(Company.get_fundamentals()["theft_losses"]), 0.0, EPS,
			"an extraordinary item: one day only")


# ─── Guardado sin manos ───────────────────────────────────────

## La entrega no depende de que las manos llamen a connect_calendar tras cargar.
func _test_save_load_without_hands() -> void:
	_fresh()
	_become("factory_foreman", DOCK_ROOM)
	var target: String = str(FactoryTheft.forge_delivery_notes()["target"])
	_enter(FACTORY_ROOM)
	FactoryTheft.steal("pocket", {"pairs": 2})
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(saved)
	var pending: Array[Dictionary] = Company.get_pending_factory_thefts()
	check(pending.size() == 2 and pending[1]["pairs"] is int
			and int(pending[1]["pairs"]) == SMALL_BOX_PAIRS, "pending thefts survive a JSON save")
	check(not target.is_empty() and Company.get_forged_delivery_target() == target,
			"the forged notes survive too")
	check(Company.get_stolen_goods().size() == 2 and Company.get_stolen_goods()[0]["units"] is int,
			"and the resale lots, with their types")
	EventBus.week_closed.emit(1)
	check_eq(_last_report().get("framed_to", ""), target, "the loaded week counts as it would have")
	check_eq(_mismatch_cases().size(), 1, "and Security gets the case at this very count")
	var again: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(again)
	var reports: Array[Dictionary] = Company.get_inventory_reports()
	check(not reports.is_empty() and reports.back()["missing"] is int
			and reports.back()["lots"] is int, "count reports keep their types")


# ─── Utilidades ────────────────────────────────────────────────

func _fresh() -> void:
	new_run()
	_clear()


func _become(occupation_id: String, room_id: String) -> void:
	PlayerState.set_occupation(occupation_id, "test")
	_enter(room_id)


func _enter(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)


func _missing(scale: String, options: Dictionary) -> Array:
	return FactoryTheft.check_requirements(scale, options)["missing"]


func _seat(occupation_id: String) -> String:
	var holders: Array[String] = Company.get_seat_holders(occupation_id)
	return holders[0] if not holders.is_empty() else ""


func _dock_worker() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) == "dock_worker":
			return npc.id
	return ""


## Llena el inventario con objetos no apilables hasta que no quede posición libre.
func _fill_inventory() -> void:
	while PlayerState.get_free_slots() > 0:
		if not PlayerState.add_item("product_pallet_note"):
			return


## Avanza jornadas con el reloj real hasta que se cierre la semana en curso.
func _advance_to_week_close() -> void:
	var closes: int = _calls("week_closed").size()
	for i: int in WEEK_DAYS:
		if _calls("week_closed").size() > closes:
			return
		GameClock.advance_to_next_day()


func _last_report() -> Dictionary:
	var reports: Array[Dictionary] = Company.get_inventory_reports()
	return reports.back() if not reports.is_empty() else {}


## Casos abiertos por descuadre de inventario desde el último _clear().
func _mismatch_cases() -> Array:
	var out: Array = []
	for call: Array in _calls("investigation_opened"):
		if call[1] == "inventory_mismatch":
			out.append(call[0])
	return out


func _last_case() -> String:
	var cases: Array = _mismatch_cases()
	return str(cases.back()) if not cases.is_empty() else ""


## Incidentes de descuadre pendientes en Security (bajo el umbral de apertura).
func _pending_mismatches() -> Array:
	var out: Array = []
	for incident: Variant in Security.save_state().get("pending", []):
		if incident is Dictionary and (incident as Dictionary).get("type", "") == "inventory_mismatch":
			out.append(incident)
	return out


func _points_of(case_id: String) -> Array:
	var out: Array = []
	for call: Array in _calls("evidence_added"):
		if call[0] == case_id and not out.has(call[3]):
			out.append(call[3])
	return out


func _pieces(case_id: String) -> Array:
	var inv: Investigation = Security.get_investigation(case_id)
	return inv.evidence if inv != null else []


## Pieza que apunta a ese sujeto (y de ese tipo si no es "").
func _has_piece(pieces: Array, points_to: String, piece_type: String) -> bool:
	for piece: Dictionary in pieces:
		var same_type: bool = piece_type.is_empty() or piece["type"] == piece_type
		if piece["points_to"] == points_to and same_type:
			return true
	return false


func _card_logs(room_id: String) -> int:
	var count: int = 0
	for record: Belief in BeliefNet.get_records_about("player"):
		if record.fact == "card_log" and record.location == room_id:
			count += 1
	return count


func _holds_belief_about_player(npc_id: String) -> bool:
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject == "player":
			return true
	return false


## Último crime_committed de ese tipo ([] si no hubo).
func _crime(crime_type: String) -> Array:
	var found: Array = []
	for call: Array in _calls("crime_committed"):
		if call[0] == crime_type:
			found = call
	return found


func _notes(text_key: String) -> Array:
	var out: Array = []
	for call: Array in _calls("notebook_entry_added"):
		if call[1] == text_key:
			out.append(call[2])
	return out


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _connect_bus() -> void:
	for signal_name: String in SIGNALS:
		EventBus.connect(signal_name, _record.bind(signal_name))


func _record(...args: Array) -> void:
	var signal_name: String = args.pop_back()
	if not _log.has(signal_name):
		_log[signal_name] = []
	_log[signal_name].append(args)
	if signal_name == "week_closed":
		_pending_at_close = _pending_mismatches()


func _calls(signal_name: String) -> Array:
	return _log.get(signal_name, [])


func _clear() -> void:
	_log.clear()
