# portal_market_case.gd — Cuerpo de test_portal_market: organigrama de 50 puestos con vacantes, ascenso solo tras confirmar, agenda de Voss, MARKET oculto bajo R25 y con confirmación del paquete R30, y las tres fases de la pantalla de resultados.
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
	PlayerState.add_money(STAKE_MONEY, "test")
	var app: MarketApp = MarketApp.new()
	add_child(app)
	await wait_frames(2)
	app.set_quantity(ORDER)
	app.buy()
	if app.has_pending_confirmation():
		check(app.confirm_pending(), "informed buy goes through after confirming")
	check_eq(Market.get_player_shares(), ORDER, "buying shares from the terminal")
	app.buy_stake()
	check(not app.has_pending_confirmation() or not Market.has_board_stake(), "stake not bought below R30")
	app.cancel_pending()
	PlayerState.set_occupation(STAKE_POST, "test")
	app.buy_stake()
	check(app.has_pending_confirmation(), "board stake asks for confirmation")
	check(not Market.has_board_stake(), "no stake before confirming")
	check(app.confirm_pending(), "stake bought after confirming")
	check(Market.has_board_stake(), "board stake owned")
	app.queue_free()
	await wait_frames(1)


func _check_results_screen() -> void:
	PlayerState.set_occupation(START_POST, "test")
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.new()
	screen.setup({"quarter": 1})
	add_child(screen)
	await wait_frames(2)
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PREPARATION), "phase 1: preparation")
	check(not screen.choose_inflation(0.1), "an unauthorised post cannot adjust the figures")
	screen.queue_free()
	PlayerState.set_occupation(MARKET_POST, "test")
	screen = ResultsPresentationScreen.new()
	screen.setup({"quarter": 1})
	add_child(screen)
	await wait_frames(2)
	check(screen.choose_inflation(0.1), "the CFO can adjust the figures")
	var fuse: Dictionary = screen.audit_preview()
	check(int(fuse["weeks"]) >= 2 and int(fuse["weeks"]) <= 8, "audit fuse warning within [2, 8] weeks")
	check(screen.confirm_figures(), "adjusted figures reported")
	check(not Company.get_audit_fuse().is_empty(), "reporting adjusted figures lights the fuse")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.PRESENTATION), "phase 2: presentation")
	var levels: Dictionary = screen.available_levels()
	check(bool(levels["none"]) and bool(levels["assist"]), "unprepared and A.S.S.I.S.T. always possible")
	check(not bool(levels["real_work"]), "real work needs the report duty done honestly")
	check(screen.present().is_empty(), "the stage is closed outside results day")
	var day: int = Market.get_presentation_day()
	GameClock.set_time(day, 11, 0)
	EventBus.day_advanced.emit(day)
	var result: Dictionary = screen.present()
	check(result.has("confidence_changes"), "presenting returns each investor's reaction")
	check_eq(int(screen.get_phase()), int(ResultsPresentation.Phase.REACTION), "phase 3: reaction")
	screen.finish()
	await wait_frames(1)
