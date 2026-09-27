# os_apps.gd (escenario) — Capturas de PERSONNEL (N1 y N7 del mismo personaje, comparación), PORTAL (organigrama con vacantes), MARKET (R28, tratos), las tres fases de la presentación de resultados (con confirmaciones y tratos en la sala), alto contraste, español y tamaño de teléfono.
# PROPIETARIO DE: nada (monta una partida de muestra y abre cada aplicación).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_os_apps os_apps
## Partida nueva con semilla fija (orden de ciclo de vida de BUILD_NOTES §2) y datos de muestra
## inyectados con las APIs de los sistemas (las «manos» del juego).

const RUN_SEED := 4242
const SUBJECT := "npc_debbie_foyle"
const OTHER := "npc_george_penn"
const N1_POST := "email_worker_3b"
const N7_POST := "vice_ceo"
const MARKET_POST := "cfo"
const PHONE_WINDOW := Vector2i(1170, 540)
const DESKTOP_WINDOW := Vector2i(1600, 900)
const SAMPLE_DAY := 3
const SAMPLE_HOUR := 10
const SAMPLE_MINUTE := 42
const VACANCY_POSTS: Array[String] = ["wing_3b_chief", "c10_director", "junior_accountant"]
const NEWS_EVENTS: Array[String] = ["viral_moment", "competitor_launch"]
const PROMOTION_TARGET := "copy_operator"
const SAMPLE_REPUTATION := 58.0
const SAMPLE_MERIT := 12
const SAMPLE_MONEY := 60000
const SAMPLE_SHARES := 120
const SAMPLE_ORDER := 250
const SAMPLE_INFLATION := 0.1
const ACTIVIST := "inv_margaret_ash"
const LEVERAGE_ITEM := "blackmail_file"
const APP_WAIT_FRAMES := 120
const SYSTEMS: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]


var _os: StellarOS


func run(pilot: Autopilot) -> void:
	_new_run()
	GameClock.set_time(SAMPLE_DAY, SAMPLE_HOUR, SAMPLE_MINUTE)
	await _shot_personnel(pilot)
	await _shot_portal(pilot)
	await _shot_market(pilot)
	await _shot_results_variants(pilot)
	await _shot_results(pilot)
	await _shot_contrast(pilot)
	await _shot_spanish(pilot)
	await _shot_phone(pilot)


func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(RUN_SEED)
	for system_name: String in SYSTEMS:
		var node: Node = get_tree().root.get_node_or_null(NodePath(system_name))
		if node == null:
			continue
		if node.has_method("reset_for_new_run"):
			node.call("reset_for_new_run")
		if system_name == "GameClock":
			GameClock.set_run_seed(RUN_SEED)
		elif system_name == "NPCDirector":
			NPCDirector.generate_population()
		elif system_name == "SocialGraph":
			SocialGraph.build_initial_graph()


func _close(node: Node, pilot: Autopilot) -> void:
	node.queue_free()
	await pilot.frames(2)


## Abre el ordenador (StellarOS, modo QA instantáneo) con una aplicación y la devuelve cuando está montada.
func _open_os(pilot: Autopilot, app_id: String, extra: Dictionary = {}) -> Control:
	_os = StellarOS.new()
	var ctx: Dictionary = {"app": app_id, "instant": true}
	ctx.merge(extra, true)
	_os.setup(ctx)
	add_child(_os)
	for i: int in APP_WAIT_FRAMES:
		await pilot.frames(1)
		if _os.get_open_app_id() == app_id and _os.get_open_app() != null:
			break
	await pilot.frames(6)
	return _os.get_open_app()


func _shot_personnel(pilot: Autopilot) -> void:
	PlayerState.set_occupation(N1_POST, "qa")
	await _open_os(pilot, PersonnelApp.APP_ID, {"file_npc_id": SUBJECT})
	await pilot.shot("personnel_n1")
	await _close(_os, pilot)
	PlayerState.set_occupation(N7_POST, "qa")
	NPCDirector.add_favour(SUBJECT, "bribe_paid", 2)
	NPCDirector.add_grievance(SUBJECT, "idea_stolen", 3)
	NPCDirector.add_debt(SUBJECT, 1)
	PersonnelApp.set_marked(SUBJECT, true)
	PersonnelApp.add_note(SUBJECT, "Writes the Pantry Post. Feed her the Vaile rumour on Thursday.")
	PersonnelApp.study(SUBJECT, PersonnelApp.STUDY_BRIBE)
	var app: PersonnelApp = await _open_os(pilot, PersonnelApp.APP_ID, {"file_npc_id": SUBJECT}) as PersonnelApp
	await pilot.shot("personnel_n7")
	app.compare(SUBJECT, OTHER)
	await pilot.frames(6)
	await pilot.shot("personnel_compare")
	await _close(_os, pilot)
	PlayerState.set_occupation(N1_POST, "qa")
	app = PersonnelApp.open(self, {"npc_id": SUBJECT, "compare_with": OTHER})
	await pilot.frames(8)
	await pilot.shot("personnel_compare_n1_standalone")
	await _close(app, pilot)


func _shot_portal(pilot: Autopilot) -> void:
	PlayerState.set_occupation(N1_POST, "qa")
	for occupation_id: String in VACANCY_POSTS:
		var holder: NPCRuntime = NPCDirector.get_npc_by_occupation(occupation_id)
		if holder != null:
			NPCDirector.remove_npc(holder.id, "expelled")
	var app: PortalApp = await _open_os(pilot, PortalApp.APP_ID, {"occupation_id": "wing_3b_chief"}) as PortalApp
	await pilot.shot("portal_org_chart")
	app.select_occupation("ceo")
	await pilot.frames(4)
	await pilot.shot("portal_ceo_agenda")
	var target: NPCRuntime = NPCDirector.get_npc_by_occupation(PROMOTION_TARGET)
	if target != null:
		NPCDirector.remove_npc(target.id, "expelled")
	PlayerState.modify_reputation(SAMPLE_REPUTATION, "qa")
	Company.register_merit("qa", SAMPLE_MERIT)
	app.refresh()
	app.select_occupation(PROMOTION_TARGET)
	await pilot.frames(4)
	await pilot.shot("portal_promotion_ready")
	app.request_promotion(PROMOTION_TARGET)
	await pilot.frames(4)
	await pilot.shot("portal_confirm")
	await _close(_os, pilot)


func _shot_market(pilot: Autopilot) -> void:
	PlayerState.set_occupation(MARKET_POST, "qa")
	PlayerState.add_money(SAMPLE_MONEY, "qa")
	var results_day: int = Market.get_presentation_day()
	for day: int in range(SAMPLE_DAY + 1, results_day - 1):
		GameClock.set_time(day, SAMPLE_HOUR, SAMPLE_MINUTE)
		EventBus.day_advanced.emit(day)
	MarketTrading.buy(SAMPLE_SHARES)
	for i: int in NEWS_EVENTS.size():
		NewsFeed.schedule_market_event(NEWS_EVENTS[i], GameClock.get_day() + i + 1)
	var app: MarketApp = await _open_os(pilot, MarketApp.APP_ID) as MarketApp
	app.set_quantity(SAMPLE_ORDER)
	app.buy()
	if app.has_pending_confirmation():
		app.confirm_pending()
	await pilot.frames(4)
	await pilot.shot("market_r28")
	app.request_investor_action("inv_victor_sallow", MarketApp.ACT_TIP)
	await pilot.frames(4)
	await pilot.shot("market_deal_confirm")
	app.cancel_pending()
	await _close(_os, pilot)
	GameClock.set_time(results_day, SAMPLE_HOUR, SAMPLE_MINUTE)
	EventBus.day_advanced.emit(results_day)


func _results_quarter() -> int:
	return Market.quarter_of(Market.get_current_day())


## Preparación a tamaño de teléfono y en alto contraste (sin cerrar nada: el trimestre sigue abierto).
func _shot_results_variants(pilot: Autopilot) -> void:
	get_window().size = PHONE_WINDOW
	UITheme.current_text_size = UITheme.TEXT_LARGE
	UITheme.touch_scale_active = true
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.open(self, _results_quarter())
	await pilot.frames(8)
	await pilot.shot("results_phone")
	await _close(screen, pilot)
	get_window().size = DESKTOP_WINDOW
	UITheme.current_text_size = UITheme.TEXT_MEDIUM
	UITheme.touch_scale_active = false
	UITheme.current_high_contrast = true
	screen = ResultsPresentationScreen.open(self, _results_quarter())
	await pilot.frames(8)
	screen.choose_inflation(SAMPLE_INFLATION)
	await pilot.frames(4)
	await pilot.shot("results_contrast")
	await _close(screen, pilot)
	UITheme.current_high_contrast = false


func _shot_results(pilot: Autopilot) -> void:
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.open(self, _results_quarter())
	await pilot.frames(8)
	await pilot.shot("results_1_preparation")
	PlayerState.add_item(LEVERAGE_ITEM)
	screen.request_deal(ACTIVIST, MarketApp.ACT_BLACKMAIL)
	screen.confirm_pending()
	screen.choose_inflation(SAMPLE_INFLATION)
	await pilot.frames(4)
	await pilot.shot("results_1_inflated")
	screen.request_lock_figures()
	await pilot.frames(4)
	await pilot.shot("results_1_confirm")
	screen.confirm_pending()
	screen.select_preparation(ResultsPresentation.LEVEL_ASSIST)
	await pilot.frames(8)
	await pilot.shot("results_2_presentation")
	screen.present()
	await pilot.frames(8)
	await pilot.shot("results_3_reaction")
	await _close(screen, pilot)


## Localización española (textos más largos).
func _shot_spanish(pilot: Autopilot) -> void:
	TranslationServer.set_locale("es")
	PlayerState.set_occupation(N7_POST, "qa")
	await _open_os(pilot, PersonnelApp.APP_ID, {"file_npc_id": SUBJECT})
	await pilot.shot("personnel_es")
	await _close(_os, pilot)
	PlayerState.set_occupation(N1_POST, "qa")
	await _open_os(pilot, PersonnelApp.APP_ID, {"file_npc_id": SUBJECT})
	await pilot.shot("personnel_es_n1")
	await _close(_os, pilot)
	await _open_os(pilot, PortalApp.APP_ID, {"occupation_id": PROMOTION_TARGET})
	await pilot.shot("portal_es")
	await _close(_os, pilot)
	TranslationServer.set_locale("en")


## Alto contraste (§13.10): el aspecto contrast se impone a cualquier nivel de equipo.
func _shot_contrast(pilot: Autopilot) -> void:
	UITheme.current_high_contrast = true
	PlayerState.set_occupation(N7_POST, "qa")
	await _open_os(pilot, PersonnelApp.APP_ID, {"file_npc_id": SUBJECT})
	await pilot.shot("personnel_contrast")
	await _close(_os, pilot)
	PlayerState.set_occupation(MARKET_POST, "qa")
	await _open_os(pilot, MarketApp.APP_ID)
	await pilot.shot("market_contrast")
	await _close(_os, pilot)
	UITheme.current_high_contrast = false


func _shot_phone(pilot: Autopilot) -> void:
	get_window().size = PHONE_WINDOW
	UITheme.current_text_size = UITheme.TEXT_LARGE
	UITheme.touch_scale_active = true
	PlayerState.set_occupation(N7_POST, "qa")
	var app: PersonnelApp = await _open_os(pilot, PersonnelApp.APP_ID) as PersonnelApp
	await pilot.shot("personnel_phone_list")
	app.call("_on_row_picked", SUBJECT)
	await pilot.frames(6)
	await pilot.shot("personnel_phone")
	await _close(_os, pilot)
	PlayerState.set_occupation(N1_POST, "qa")
	var portal: PortalApp = await _open_os(pilot, PortalApp.APP_ID) as PortalApp
	await pilot.shot("portal_phone")
	portal.call("_on_card_picked", "wing_3b_chief")
	await pilot.frames(4)
	await pilot.shot("portal_phone_detail")
	await _close(_os, pilot)
	PlayerState.set_occupation(MARKET_POST, "qa")
	await _open_os(pilot, MarketApp.APP_ID)
	await pilot.shot("market_phone")
	await _close(_os, pilot)
