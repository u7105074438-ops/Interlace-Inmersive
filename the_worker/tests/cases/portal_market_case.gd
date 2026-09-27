# portal_market_case.gd — Cuerpo de test_portal_market: organigrama de 50 puestos con vacantes, ascenso solo tras confirmar, agenda de Voss, vistas compactas, MARKET oculto bajo R25 (órdenes, avisos, tratos con inversores, paquete R30 solo desde R30 y con confirmación) y las tres fases de la pantalla de resultados (estrado cerrado fuera del día, confirmaciones, soborno en la sala).
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends TestCase

const START_POST := "email_worker_3b"
const TARGET_POST := "copy_operator"
const MARKET_POST := "cfo"
const STAKE_POST := "board_investor"
const VOSS := "npc_harlan_voss"
const OCCUPATIONS := 50
const REPUTATION := 60.0
const MERIT := 12
const STAKE_MONEY := 400000
const ORDER := 10
const HUGE_ORDER := 100000000
const INFO_HUNTER := "inv_victor_sallow"
const ACTIVIST := "inv_margaret_ash"
const MOMENTUM := "inv_tania_brekke"
const RETAIL := "inv_bobby_kerr"
const LEVERAGE_ITEM := "blackmail_file"


func run_case() -> void:
	check(new_run(), "database loaded and run created")
	_check_org_chart()
	await _check_promotion_confirmation()
	_check_agenda_and_calendar()
	await _check_market()
	await _check_results_screen()


func _check_org_chart() -> void:
	var tiers: Array[Dictionary] = PortalApp.build_org_chart()
	check_eq(tiers.size(), 8, "org chart has the eight tiers")
	check_eq(int(tiers[0]["tier"]), 8, "top tier first")
	check_eq(PortalApp.occupation_count(), OCCUPATIONS, "org chart lists the fifty posts")
	var seats: int = 0
	for tier: Dictionary in tiers:
		for entry: Dictionary in tier["occupations"]:
			seats += (entry["seats"] as Array).size()
	check_eq(seats, Company.get_all_seats().size(), "every seat of Company appears")
	var before: int = PortalApp.vacancy_count()
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation("wing_3b_chief")
	NPCDirector.remove_npc(holder.id, "expelled")
	check_eq(PortalApp.vacancy_count(), before + 1, "a dismissal opens a vacancy")
	var found: bool = false
	for tier: Dictionary in PortalApp.build_org_chart():
		for entry: Dictionary in tier["occupations"]:
			if str(entry["id"]) == "wing_3b_chief":
				found = int(entry["vacant"]) == 1 and bool(entry["seats"][0]["vacant"])
	check(found, "the vacancy is highlighted on its post")


func _check_promotion_confirmation() -> void:
	PlayerState.set_occupation(START_POST, "test")
	var app: PortalApp = PortalApp.new()
	add_child(app)
	await wait_frames(2)
	app.request_promotion(TARGET_POST)
	check(not app.has_pending_confirmation(), "a promotion that is not allowed never reaches the dialog")
	var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(TARGET_POST)
	NPCDirector.remove_npc(holder.id, "expelled")
	PlayerState.modify_reputation(REPUTATION, "test")
	Company.register_merit("test", MERIT)
	check(bool(PortalApp.promotion_status(TARGET_POST)["allowed"]), "promotion conditions met")
	app.request_promotion(TARGET_POST)
	check(app.has_pending_confirmation(), "the request opens a confirmation dialog")
	check_eq(PlayerState.get_occupation_id(), START_POST, "nothing happens with a single press")
	app.cancel_pending()
	check_eq(PlayerState.get_occupation_id(), START_POST, "cancelling keeps the current post")
	app.request_promotion(TARGET_POST)
	check(app.confirm_pending(), "confirming promotes the player")
	check_eq(PlayerState.get_occupation_id(), TARGET_POST, "player now holds the requested post")
	app.size = Vector2(PersonnelApp.OsKit.px(PortalApp.COMPACT_EM * 0.6), app.size.y)
	await wait_frames(2)
	check(app.is_compact(), "PORTAL switches to the compact layout on a phone-width window")
	app.call("_on_card_picked", "ceo")
	check_eq(app.get_selected(), "ceo", "compact: tapping a card opens its record")
	app.queue_free()
	await wait_frames(1)


func _check_agenda_and_calendar() -> void:
	check(PortalApp.shows_agenda("ceo"), "directors' agendas are visible")
	check(not PortalApp.shows_agenda(START_POST), "base posts have no public agenda")
	var agenda: Array[Dictionary] = PortalApp.agenda_for(VOSS)
	check(not agenda.is_empty(), "Voss has an agenda")
	var office_hours: bool = false
	for block: Dictionary in agenda:
		office_hours = office_hours or str(block["room"]) == "ceo_office"
	check(office_hours, "Voss's office hours appear in his agenda")
	var week: Array[Dictionary] = PortalApp.week_calendar()
	check_eq(week.size(), Database.get_balance_int("tiempo.jornadas_por_semana"), "calendar shows the working week")
	var aurora: int = 0
	for day: Dictionary in week:
		aurora += 1 if bool(day["aurora"]) else 0
	check_eq(aurora, 1, "one Aurora meeting per week")


func _check_market() -> void:
	PlayerState.set_occupation(START_POST, "test")
	check(not MarketApp.is_available(), "MARKET hidden below R25")
	var denied: MarketApp = MarketApp.new()
	add_child(denied)
	await wait_frames(2)
	check(denied.get_quantity() == 0, "denied window builds without trading controls")
	denied.queue_free()
	PlayerState.set_occupation(MARKET_POST, "test")
	check(MarketApp.is_available(), "MARKET available at R28")
	var snap: Dictionary = MarketApp.snapshot()
	check_eq((snap["investors"] as Array).size(), 6, "the six investors with their confidence")
	check(float(snap["price"]) > 0.0, "share price shown")
	_check_calendar(snap["calendar"])
	PlayerState.add_money(STAKE_MONEY, "test")
	var app: MarketApp = MarketApp.new()
	add_child(app)
	await wait_frames(2)
	await _check_orders(app)
	_check_deals(app)
	app.set_quantity(0)
	app.buy_stake()
	check(app.has_pending_confirmation(), "the stake always asks for confirmation")
	check(not app.confirm_pending(), "R28 cannot buy the board stake even after confirming")
	check(not Market.has_board_stake(), "stake not bought below R30")
	check(not app.get_notice().is_empty(), "a refused stake explains why")
	PlayerState.set_occupation(STAKE_POST, "test")
	app.buy_stake()
	check(app.has_pending_confirmation(), "board stake asks for confirmation")
	check(not Market.has_board_stake(), "no stake before confirming")
	check(app.confirm_pending(), "stake bought after confirming")
	check(Market.has_board_stake(), "board stake owned")
	app.size = Vector2(PersonnelApp.OsKit.px(MarketApp.COMPACT_EM * 0.6), app.size.y)
	await wait_frames(2)
	check(app.is_compact(), "MARKET switches to the stacked phone layout")
	app.queue_free()
	await wait_frames(1)


func _check_calendar(rows: Array) -> void:
	var ids: Array[String] = []
	var results: int = 0
	for row: Dictionary in rows:
		check(not ids.has(str(row["id"])), "calendar: one line per event (%s)" % row["id"])
		ids.append(str(row["id"]))
		if bool(row["results"]):
			results += 1
			check_eq(str(row["periodicity"]), "quarterly", "only the quarterly presentation is flagged as results")
	check_eq(results, 1, "exactly one results line in the calendar")


func _check_orders(app: MarketApp) -> void:
	var qty: LineEdit = app.get("_qty_edit")
	qty.text = str(ORDER)
	qty.text_changed.emit(qty.text)
	check_eq(app.get_quantity(), ORDER, "a typed quantity counts without pressing Enter")
	app.buy()
	if app.has_pending_confirmation():
		check(app.confirm_pending(), "informed buy goes through after confirming")
	check_eq(Market.get_player_shares(), ORDER, "buying shares from the terminal")
	check(app.get_last_result() and not app.get_notice().is_empty(), "a filled order leaves a notice")
	app.set_quantity(HUGE_ORDER)
	app.buy()
	if app.has_pending_confirmation():
		app.confirm_pending()
	check(not app.get_last_result(), "an unaffordable order is refused")
	check(not app.get_notice().is_empty(), "a refused order explains why")
	await wait_frames(1)


func _check_deals(app: MarketApp) -> void:
	var cash: int = PlayerState.get_money()
	app.request_investor_action(INFO_HUNTER, MarketApp.ACT_TIP)
	check(app.has_pending_confirmation(), "a tip asks for confirmation")
	check_eq(PlayerState.get_money(), cash, "no tip sold before confirming")
	check(app.confirm_pending(), "tip sold to the information hunter")
	check_eq(PlayerState.get_money(), cash + Market.get_tip_payment(INFO_HUNTER), "the tip is paid")
	var blackmail: Dictionary = _action(ACTIVIST, MarketApp.ACT_BLACKMAIL)
	check(not blackmail.is_empty() and not bool(blackmail["enabled"]), "blackmail needs material")
	PlayerState.add_item(LEVERAGE_ITEM)
	app.request_investor_action(ACTIVIST, MarketApp.ACT_BLACKMAIL)
	check(app.confirm_pending(), "blackmail with material coerces the activist")
	check(Market.is_investor_ally(ACTIVIST), "the coerced activist is an ally this quarter")
	check(not _action(ACTIVIST, MarketApp.ACT_CAMPAIGN).is_empty(), "a coerced activist can be aimed")
	check(MarketApp.pattern_band() >= 0, "the insider pattern is shown as a fuzzy band")


func _action(investor_id: String, action_id: String) -> Dictionary:
	for action: Dictionary in MarketApp.investor_actions(investor_id):
		if str(action["id"]) == action_id:
			return action
	return {}


func _check_results_screen() -> void:
	PlayerState.set_occupation(START_POST, "test")
	var screen: ResultsPresentationScreen = await _new_screen()
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PREPARATION), "phase 1: preparation")
	check(not screen.choose_inflation(0.1), "an unauthorised post cannot adjust the figures")
	screen.queue_free()
	PlayerState.set_occupation(MARKET_POST, "test")
	screen = await _new_screen()
	check(not screen.stage_open(), "the stage is closed outside results day")
	check(screen.choose_inflation(0.1), "the CFO can adjust the figures")
	var fuse: Dictionary = screen.audit_preview()
	check(int(fuse["weeks"]) >= 2 and int(fuse["weeks"]) <= 8, "audit fuse warning within [2, 8] weeks")
	screen.request_lock_figures()
	check(not screen.has_pending_confirmation(), "the lock button does nothing off results day")
	check(not screen.confirm_figures(), "figures cannot be locked off results day")
	check(Company.get_audit_fuse().is_empty(), "no audit fuse burnt for nothing")
	screen.queue_free()
	var day: int = Market.get_presentation_day()
	GameClock.set_time(day, 11, 0)
	EventBus.day_advanced.emit(day)
	screen = await _new_screen()
	await _check_lock_and_deal(screen)
	await _check_present(screen)


func _new_screen() -> ResultsPresentationScreen:
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.new()
	screen.setup({"quarter": 1})
	add_child(screen)
	await wait_frames(2)
	return screen


func _check_lock_and_deal(screen: ResultsPresentationScreen) -> void:
	check(screen.stage_open(), "the stage opens on results day")
	screen.choose_inflation(0.1)
	screen.request_lock_figures()
	check(screen.has_pending_confirmation(), "locking the figures asks for confirmation")
	check(Company.get_audit_fuse().is_empty(), "nothing is reported with a single press")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PREPARATION), "still preparing until confirmed")
	check(screen.confirm_pending(), "adjusted figures reported after confirming")
	check(not Company.get_audit_fuse().is_empty(), "reporting adjusted figures lights the fuse")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PRESENTATION), "phase 2: presentation")
	var levels: Dictionary = screen.available_levels()
	check(bool(levels["none"]) and bool(levels["assist"]), "unprepared and A.S.S.I.S.T. always possible")
	check(not bool(levels["real_work"]), "real work needs the report duty done honestly")
	var allies: int = Market.get_investor_allies().size()
	screen.request_deal(RETAIL, MarketApp.ACT_BRIBE)
	check(screen.has_pending_confirmation(), "a bribe in the room asks for confirmation")
	screen.confirm_pending()
	check(not screen.get_deal_message().is_empty(), "the bribe's outcome is reported")
	check(Market.get_investor_allies().size() == allies + (1 if Market.is_investor_ally(RETAIL) else 0),
			"an accepted bribe adds an ally in the room")
	await wait_frames(1)


func _check_present(screen: ResultsPresentationScreen) -> void:
	screen.request_present()
	check(screen.has_pending_confirmation(), "taking the stage asks for confirmation")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PRESENTATION), "nothing moves with a single press")
	screen.cancel_pending()
	check(not screen.has_pending_confirmation(), "cancelling closes the dialog")
	screen.request_present()
	check(screen.confirm_pending(), "presenting after confirming")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.REACTION), "phase 3: reaction")
	check(ResultsPresentationScreen.quip_for(MOMENTUM, -1) != ResultsPresentationScreen.quip_for(RETAIL, -1),
			"the two momentum investors react differently")
	check(ResultsPresentationScreen.question_for(Market.get_investor(MOMENTUM))
			!= ResultsPresentationScreen.question_for(Market.get_investor(RETAIL)),
			"the two momentum investors ask different questions")
	screen.finish()
	await wait_frames(1)
