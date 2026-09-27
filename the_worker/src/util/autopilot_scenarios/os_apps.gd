# os_apps.gd (escenario) — Capturas de PERSONNEL (N1 y N7 del mismo personaje, comparación), PORTAL (organigrama con vacantes), MARKET (R28) y las tres fases de la presentación de resultados.
# PROPIETARIO DE: nada (monta una partida de muestra y abre cada aplicación suelta).
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
const SAMPLE_DAY := 3
const SAMPLE_HOUR := 10
const SAMPLE_MINUTE := 42
const MARKET_DAYS := 24
const SAMPLE_MONEY := 60000
const SYSTEMS: Array[String] = [
	"GameClock", "PlayerState", "NPCDirector", "SocialGraph", "BeliefNet", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking", "SaveSystem",
]


func run(pilot: Autopilot) -> void:
	_new_run()
	GameClock.set_time(SAMPLE_DAY, SAMPLE_HOUR, SAMPLE_MINUTE)
	await _shot_personnel(pilot)
	await _shot_portal(pilot)
	await _shot_market(pilot)
	await _shot_results(pilot)
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
	PersonnelApp.reset_session()


func _close(node: Node, pilot: Autopilot) -> void:
	node.queue_free()
	await pilot.frames(2)


func _shot_personnel(pilot: Autopilot) -> void:
	PlayerState.set_occupation(N1_POST, "qa")
	var app: PersonnelApp = PersonnelApp.open(self, {"npc_id": SUBJECT})
	await pilot.frames(8)
	await pilot.shot("personnel_n1")
	await _close(app, pilot)
	PlayerState.set_occupation(N7_POST, "qa")
	NPCDirector.add_favour(SUBJECT, "bribe_paid", 2)
	NPCDirector.add_grievance(SUBJECT, "idea_stolen", 3)
	NPCDirector.add_debt(SUBJECT, 1)
	PersonnelApp.set_marked(SUBJECT, true)
	PersonnelApp.add_note(SUBJECT, "Writes the Pantry Post. Feed her the Vaile rumour on Thursday.")
	PersonnelApp.study(SUBJECT, PersonnelApp.STUDY_BRIBE)
	app = PersonnelApp.open(self, {"npc_id": SUBJECT})
	await pilot.frames(8)
	await pilot.shot("personnel_n7")
	app.compare(SUBJECT, OTHER)
	await pilot.frames(6)
	await pilot.shot("personnel_compare")
	await _close(app, pilot)
	PlayerState.set_occupation(N1_POST, "qa")
	app = PersonnelApp.open(self, {"npc_id": SUBJECT, "compare_with": OTHER})
	await pilot.frames(8)
	await pilot.shot("personnel_compare_n1")
	await _close(app, pilot)


func _shot_portal(pilot: Autopilot) -> void:
	PlayerState.set_occupation(N1_POST, "qa")
	for occupation_id: String in ["order_filer", "wing_3b_chief", "c10_director"]:
		Company.vacate_seat(occupation_id, "expelled")
	var app: PortalApp = PortalApp.open(self, {"occupation_id": "wing_3b_chief"})
	await pilot.frames(8)
	await pilot.shot("portal_org_chart")
	app.select_occupation("ceo")
	await pilot.frames(4)
	await pilot.shot("portal_ceo_agenda")
	app.select_occupation("order_filer")
	app.request_promotion("order_filer")
	await pilot.frames(4)
	await pilot.shot("portal_confirm")
	await _close(app, pilot)


func _shot_market(pilot: Autopilot) -> void:
	PlayerState.set_occupation(MARKET_POST, "qa")
	PlayerState.add_money(SAMPLE_MONEY, "qa")
	for day: int in range(SAMPLE_DAY + 1, SAMPLE_DAY + MARKET_DAYS):
		GameClock.set_time(day, SAMPLE_HOUR, SAMPLE_MINUTE)
		EventBus.day_advanced.emit(day)
	MarketTrading.buy(120)
	var app: MarketApp = MarketApp.open(self)
	app.set_quantity(250)
	await pilot.frames(8)
	await pilot.shot("market_r28")
	await _close(app, pilot)


func _shot_results(pilot: Autopilot) -> void:
	var screen: ResultsPresentationScreen = ResultsPresentationScreen.open(self, Market.quarter_of(
			Market.get_current_day()))
	await pilot.frames(8)
	await pilot.shot("results_1_preparation")
	screen.choose_inflation(0.1)
	await pilot.frames(4)
	await pilot.shot("results_1_inflated")
	screen.confirm_figures()
	await pilot.frames(8)
	await pilot.shot("results_2_presentation")
	screen.present()
	await pilot.frames(8)
	await pilot.shot("results_3_reaction")
	await _close(screen, pilot)


func _shot_phone(pilot: Autopilot) -> void:
	get_window().size = PHONE_WINDOW
	PlayerState.set_occupation(N7_POST, "qa")
	var app: PersonnelApp = PersonnelApp.open(self, {"npc_id": SUBJECT})
	await pilot.frames(10)
	await pilot.shot("personnel_phone")
	await _close(app, pilot)
	var portal: PortalApp = PortalApp.open(self)
	await pilot.frames(8)
	await pilot.shot("portal_phone")
	await _close(portal, pilot)
