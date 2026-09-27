# factory_case.gd — Cuerpo de test_factory: las tres escalas del robo en fábrica y sus requisitos, el recuento semanal como consecuencia retardada, la pérdida en los fundamentales y los albaranes falsificados que desvían el descuadre (§11.6, PASO 41).
# PROPIETARIO DE: nada.
# ESCUCHA: crime_committed, investigation_opened, evidence_added, notebook_entry_added, week_closed (solo para comprobarlas).
extends TestCase

const EPS := 0.01
## Tabla §11.6 del manual: [pares min, pares max, ingreso min, ingreso max, rango min].
const MANUAL_SCALES: Dictionary = {
	"pocket": [1, 2, 40, 80, 3], "box": [10, 20, 400, 900, 8],
	"pallet": [200, 400, 8000, 18000, 15],
}
const FACTORY_ROOM := "finished_goods"
const DOCK_ROOM := "loading_dock"
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


func run_case() -> void:
	check(new_run(), "Database loaded and a populated run was created")
	_connect_bus()
	FactoryTheft.connect_calendar()
	FactoryTheft.connect_calendar()
	check(FactoryTheft.is_calendar_connected(),
			"the weekly count is wired to week_closed (idempotent)")
	_test_manual_table()
	_test_requirements()
	_test_pallet_requirements()
	_test_delayed_weekly_detection()
	_test_pocket_is_absorbed()
	_test_responsible_foreman()
	_test_forged_notes_redirect()
	_test_pallet_in_margins()
	_test_save_load()


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


# ─── El recuento semanal ──────────────────────────────────────

## §11.6: «los robos no se detectan en el momento: afloran en el recuento posterior».
func _test_delayed_weekly_detection() -> void:
	_fresh()
	_become("senior_sales", FACTORY_ROOM)
	var money: int = PlayerState.get_money()
	var losses: float = Company.get_total_theft_losses()
	var theft_line: float = float(Company.get_fundamentals()["theft_losses"])
	var result: Dictionary = FactoryTheft.steal("box", {"pairs": BOX_PAIRS})
	check(bool(result["ok"]) and int(result["pairs"]) == BOX_PAIRS, "a box of 15 pairs is taken")
	check_eq(PlayerState.get_money() - money, BOX_INCOME, "the income goes to the player at once")
	var crime: Array = _crime("theft_product")
	check(not crime.is_empty(), "crime_committed(theft_product) is emitted")
	var details: Dictionary = crime[2] if not crime.is_empty() else {}
	check(bool(details.get("loss_booked", false)) and not bool(details.get("leaves_record", true))
			and int(details.get("quantity", 0)) == BOX_PAIRS and int(details.get("value", 0))
			== BOX_INCOME, "details: value, quantity, loss_booked, no immediate record")
	check(_mismatch_cases().is_empty(), "no incident at the moment of the theft")
	check_near(Company.get_total_theft_losses(), losses, EPS, "no loss booked at the moment")
	check_near(float(Company.get_fundamentals()["theft_losses"]), theft_line, EPS,
			"the fundamentals do not see it yet")
	check_eq(Company.get_pending_factory_thefts().size(), 1, "the theft waits for the count")
	check_eq(Company.get_finished_goods_stock(),
			Database.get_balance_int("fabrica.stock_base_pares") - BOX_PAIRS,
			"the physical stock is short already")
	GameClock.advance_to_next_day()
	check(_mismatch_cases().is_empty(), "a day later it is still undetected")
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
	check_eq(_mismatch_cases().size(), 1, "Security opens an inventory_mismatch case at the count")
	check_near(Company.get_total_theft_losses() - losses_before, loss, EPS,
			"the loss (pairs × average price) enters Company costs at the count")
	var window: float = Database.get_balance_float("empresa.jornadas_ventana_contable")
	check_near(float(Company.get_fundamentals()["theft_losses"]),
			loss / window * NewsFeed.get_event_multiplier("costs_multiplier"), EPS,
			"the theft-loss line of the fundamentals shows it")
	check(_notes("NOTE_INVENTORY_MISMATCH").has([BOX_PAIRS]), "the notebook records the count")
	check_eq(_points_of(_mismatch_cases().back()), [""],
			"without forged notes nor inventory post, the gap points at nobody yet")
	check(Company.get_pending_factory_thefts().is_empty(), "the count clears the pending thefts")


## Bolsillo: «prácticamente ningún rastro»: la merma de la semana se absorbe.
func _test_pocket_is_absorbed() -> void:
	_fresh()
	_become("line_operator", FACTORY_ROOM)
	check(bool(FactoryTheft.steal("pocket", {"pairs": 2})["ok"]), "a pocket theft of 2 pairs")
	EventBus.week_closed.emit(1)
	var report: Dictionary = _last_report()
	check(bool(report["absorbed"]) and not bool(report["mismatch"]),
			"2 pairs vanish in the count's shrinkage tolerance")
	check(_mismatch_cases().is_empty() and _notes("NOTE_INVENTORY_MISMATCH").is_empty(),
			"no incident, no notebook entry")
	check_near(Company.get_total_theft_losses(),
			2 * float(Company.get_fundamentals()["avg_price"]), EPS,
			"the loss still enters the books at the count")
	for i: int in 3:
		FactoryTheft.steal("pocket", {"pairs": 2})
	EventBus.week_closed.emit(2)
	report = _last_report()
	check(bool(report["mismatch"]) and report["scale"] == "pocket",
			"many pockets in one week (6 pairs) do show up")
	check(bool(report["reported"]), "and that mismatch is handed to Security too")


## §11.6 riesgo del capataz: «inventory_gap_points_to_foreman».
func _test_responsible_foreman() -> void:
	_fresh()
	_become("factory_foreman", FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	EventBus.week_closed.emit(1)
	check_eq(_last_report()["points_to"], "player", "the foreman answers for the inventory gap")
	check(_points_of(_mismatch_cases().back()).has("player"),
			"the case evidence points at the player")


# ─── Albaranes falsificados ───────────────────────────────────

func _test_forged_notes_redirect() -> void:
	_fresh()
	_become("factory_foreman", FACTORY_ROOM)
	var superior: String = FactoryTheft.find_direct_superior()
	check(not superior.is_empty() and superior == Company.get_seat_holder("factory_director"),
			"the foreman's direct superior is the factory director")
	check_eq(FactoryTheft.forge_delivery_notes()["reason"], "not_at_delivery_notes",
			"delivery notes are only at the dock or the foreman's office")
	_enter(DOCK_ROOM)
	var silk: int = PlayerState.get_tracking("silk")
	var forged: Dictionary = FactoryTheft.forge_delivery_notes()
	check(bool(forged["ok"]) and forged["target"] == superior, "the notes are forged")
	check(_crime("forgery").size() > 0 and _crime("forgery")[2]["subject"] == superior,
			"crime_committed(forgery) names the superior as the document's subject")
	check(_crime("framing").size() > 0 and _crime("framing")[2]["target"] == superior,
			"crime_committed(framing) targets the superior")
	check(PlayerState.get_tracking("silk") > silk, "forgery feeds the SILK axis")
	check_eq(Company.get_forged_delivery_target(), superior, "this week's count will point at them")
	_enter(FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	var suspicion: float = BeliefNet.calculate_player_suspicion()
	EventBus.week_closed.emit(1)
	_check_framed_count(superior, suspicion)


func _check_framed_count(superior: String, suspicion_before: float) -> void:
	var report: Dictionary = _last_report()
	check(report["framed_to"] == superior and report["points_to"] == superior,
			"the mismatch points at the superior")
	var case_id: String = _mismatch_cases().back() if not _mismatch_cases().is_empty() else ""
	var pieces: Array = _pieces(case_id)
	check(_has_piece(pieces, superior, "forged_document"),
			"the forged notes are a forged_document piece against the superior")
	check(not _has_piece(pieces, "player", ""), "no piece points at the player")
	check(BeliefNet.calculate_player_suspicion() > suspicion_before,
			"the player's suspicion rises: they had access too")
	check(_has_access_record(), "an access record puts the player in the goods room")
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
	var result: Dictionary = FactoryTheft.steal("pallet", {"pairs": PALLET_PAIRS,
			"accomplice_id": carrier})
	check(bool(result["ok"]) and int(result["income"]) == PALLET_INCOME
			and result["accomplice"] == carrier, "a pallet of 300 pairs with the carrier: 13 000 €")
	Company.recalculate_fundamentals()
	var before: Dictionary = Company.get_fundamentals()
	EventBus.week_closed.emit(1)
	var after: Dictionary = Company.get_fundamentals()
	var loss: float = PALLET_PAIRS * float(before["avg_price"])
	var window: float = Database.get_balance_float("empresa.jornadas_ventana_contable")
	var line: float = loss / window * NewsFeed.get_event_multiplier("costs_multiplier")
	check_near(float(before["profit"]) - float(after["profit"]), line, EPS,
			"the pallet is visible in the company's margins at the count")
	var report: Dictionary = _last_report()
	check(bool(report["cfo_detected"]), "the CFO sees it in the margins")
	check_near(float(report["weight"]),
			Database.get_balance_float("fabrica.escalas.pallet.peso_incidente")
			* Database.get_balance_float("fabrica.factor_peso_cfo"), EPS,
			"the CFO's eye weighs on the incident")
	check_eq(int(report["severity"]), Database.get_balance_int("fabrica.escalas.pallet.gravedad"),
			"pallet severity")
	check_eq(_mismatch_cases().size(), 1, "and Security opens the case")


func _test_save_load() -> void:
	_fresh()
	_become("senior_sales", DOCK_ROOM)
	var target: String = str(FactoryTheft.forge_delivery_notes()["target"])
	_enter(FACTORY_ROOM)
	FactoryTheft.steal("box", {"pairs": SMALL_BOX_PAIRS})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(saved)
	var pending: Array[Dictionary] = Company.get_pending_factory_thefts()
	check(pending.size() == 1 and pending[0]["pairs"] is int
			and int(pending[0]["pairs"]) == SMALL_BOX_PAIRS, "pending thefts survive a JSON save")
	check(not target.is_empty() and Company.get_forged_delivery_target() == target,
			"the forged notes survive too")
	check_eq(Company.get_factory_theft_count(), 1, "and the theft counter")
	EventBus.week_closed.emit(1)
	check_eq(_last_report()["framed_to"], target, "the loaded week counts as it would have")
	var again: Dictionary = JSON.parse_string(JSON.stringify(Company.save_state(), "", true, true))
	_fresh()
	Company.load_state(again)
	check(Company.get_inventory_reports().back()["missing"] is int,
			"count reports keep their types")


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
	return Company.get_seat_holders(occupation_id)[0]


func _dock_worker() -> String:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(npc.id) == "dock_worker":
			return npc.id
	return ""


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


func _has_access_record() -> bool:
	for record: Belief in BeliefNet.get_records_about("player"):
		if record.fact == "card_log" and record.location == FACTORY_ROOM:
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
