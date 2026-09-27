# phone.gd (escenario) — Capturas del móvil (contactos, chat, soborno a ciegas/N5/contraoferta, llamada expuesta, baños y escalera de servicio, alto contraste, respuesta a chantaje), de la flagrancia (con y sin testigos, contraoferta, inacción, cola) y del chantaje, también en pantalla de móvil.
# PROPIETARIO DE: los nodos temporales del escenario (planta 3, jugador, figuras, UIRoot, CaughtHandler).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_phone phone
## Escritorio: phone_contacts, phone_chat, phone_bribe_result, phone_chat_deal, phone_bribe_blind (N1),
## phone_bribe_counter (contraoferta sin fondos), phone_call_exposed, phone_call_private (baños de
## verdad), phone_call_stairs (escalera de servicio), phone_bribe_n5, phone_blackmail_reply,
## phone_high_contrast, phone_large_bribe (texto grande), caught_witnesses, caught_clear, caught_confirm, caught_counteroffer,
## caught_inaction, blackmail_face, blackmail_confirm, blackmail_demand, phone_es.
## Móvil (1170×540, táctil, texto grande): phone_mobile_contacts, phone_mobile_chat, phone_mobile_bribe,
## phone_mobile_result, phone_mobile_call, caught_mobile, caught_mobile_confirm, blackmail_mobile.

const FLOOR := 3
const ROOM := "wing_3b"
const TOILETS := "p3_toilets"
const STAIRS := "service_stairs@3"
const SEED := 4242
const START_OCCUPATION := "email_worker_3b"
const DIRECTOR_OCCUPATION := "a10_marketing_director"
const CHIEF := "npc_bernard_lasker"
const GOSSIP := "npc_debbie_foyle"
const SNITCH := "npc_george_penn"
const OBLIVIOUS := "npc_nate_brackley"
const COWARD := "npc_sonia_vail"
const BRIBABLE := "npc_tom_iverson"
const HARDLINER := "npc_ray_cudmore"
const CLIMBER := "npc_claudia_reeves"
const COLLEAGUES: Array[String] = [GOSSIP, OBLIVIOUS, COWARD, CLIMBER, CHIEF]
const MOBILE_WINDOW := Vector2i(1170, 540)
const DESKTOP_WINDOW := Vector2i(1600, 900)
const SETTLE := 8
const CAUGHT_RUN_SECONDS := 1.2
const START_MONEY := 1240
const WATCHER_OFFSET := Vector2(-150, -40)
const PLAYER_CELLS := Vector2(9.0, 2.6)


## Figura de ambiente dibujada con CharacterPainter (el NPC real es de otro constructor).
class Figure extends Node2D:
	var app: Dictionary = {}
	var tier: int = 1
	var anim: String = "idle"
	var facing: Vector2 = Vector2.DOWN
	var tic: String = ""

	func _draw() -> void:
		CharacterPainter.draw(self, app, tier, CharacterPainter.make_pose(anim, 0, facing, {"tic": tic}))


var _ui: UIRoot
var _streamer: FloorStreamer
var _player: Player
var _handler: CaughtHandler
var _figures: Node2D
var _desk: Vector2 = Vector2.ZERO


func run(pilot: Autopilot) -> void:
	_new_run()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	_build_world()
	_ui = UIRoot.new()
	add_child(_ui)
	PhoneOverlay.install(_ui)
	BlackmailDialog.install(_ui)
	_handler = CaughtHandler.new()
	add_child(_handler)
	CaughtWindow.install(_ui, _handler)
	await pilot.frames(SETTLE)
	await _phone_shots(pilot)
	await _privacy_shots(pilot)
	await _estimate_and_reply_shots(pilot)
	await _caught_shots(pilot)
	await _blackmail_shot(pilot)
	await _spanish_shot(pilot)
	await _contrast_shot(pilot)
	await _mobile_shots(pilot)


# ─── Montaje ───────────────────────────────────────────────────────

func _new_run() -> void:
	Database.load_all()
	GameClock.set_run_seed(SEED)
	GameClock.reset_for_new_run()
	GameClock.set_run_seed(SEED)
	PlayerState.reset_for_new_run()
	NPCDirector.reset_for_new_run()
	NPCDirector.generate_population()
	SocialGraph.reset_for_new_run()
	SocialGraph.build_initial_graph()
	for system: Node in [BeliefNet, Security, Company, Market, NewsFeed, IdeaPool, Tracking]:
		system.call("reset_for_new_run")
	GameClock.set_time(3, 10, 42)
	PlayerState.add_money(START_MONEY - PlayerState.get_money(), "qa")
	EventBus.room_entered.emit(ROOM, true)
	for npc_id: String in [CHIEF, GOSSIP, SNITCH, OBLIVIOUS, COWARD, HARDLINER, CLIMBER]:
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		if npc != null:
			npc.current_room = ROOM
			npc.floor = FLOOR
	for npc_id: String in COLLEAGUES:
		PlayerState.add_contact(npc_id, PhoneContactsTab.SOURCE_COLLEAGUE)
	PlayerState.add_contact(HARDLINER, PhoneContactsTab.SOURCE_FAVOUR)
	PlayerState.add_contact("npc_diana_sedgwick", PhoneContactsTab.SOURCE_BOUGHT)


func _build_world() -> void:
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(FLOOR)
	_player = (load("res://scenes/world/player.tscn") as PackedScene).instantiate() as Player
	_streamer.get_actor_layer().add_child(_player)
	_streamer.set_player(_player)
	var rect: Rect2 = _streamer.get_room_rect_px(ROOM)
	var cell: float = RoomBuilder.cell_px()
	_desk = rect.position + Vector2(cell * PLAYER_CELLS.x, rect.size.y - cell * PLAYER_CELLS.y)
	_player.global_position = _desk
	_player.set_facing(Vector2.DOWN)
	_player.play_anim("phone")
	var cam: PlayerCamera = _player.get_node_or_null("Camera") as PlayerCamera
	if cam != null:
		cam.set_bounds(_streamer.get_floor_rect_px())
		cam.snap_to_target()
	_figures = Node2D.new()
	_streamer.get_actor_layer().add_child(_figures)
	_add_figure(CHIEF, WATCHER_OFFSET, Vector2(1, 0.3).normalized(), "idle")
	_add_figure(GOSSIP, Vector2(210, 70), Vector2(-1, -0.2).normalized(), "chat")
	_add_figure(OBLIVIOUS, Vector2(330, -20), Vector2.UP, "phone_sneak")


func _add_figure(npc_id: String, offset: Vector2, facing: Vector2, anim: String) -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return
	var fig: Figure = Figure.new()
	fig.app = CharacterPainter.appearance_for_npc(npc)
	fig.tier = npc.tier
	fig.anim = anim
	fig.facing = facing
	fig.tic = CharacterPainter.tic_for_archetype(npc.archetype)
	fig.position = _player.global_position + offset
	_figures.add_child(fig)


func _phone() -> PhoneOverlay:
	return _ui.get_top_modal() as PhoneOverlay


## Lleva el nodo del jugador de verdad a otra sala (la cámara lo sigue y el streamer emite room_entered).
func _move_player_to(room_id: String) -> void:
	var rect: Rect2 = _streamer.get_room_rect_px(room_id)
	var at: Vector2 = _desk if room_id == ROOM else rect.get_center()
	if room_id == STAIRS:
		at = Vector2(rect.position.x + RoomBuilder.cell_px() * 1.5, rect.get_center().y)
	_player.global_position = at
	var cam: PlayerCamera = _player.get_node_or_null("Camera") as PlayerCamera
	if cam != null:
		cam.snap_to_target()
	EventBus.room_entered.emit(room_id, true)
	_figures.visible = room_id == ROOM
	if room_id == ROOM:
		return
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.current_room == room_id:
			npc.current_room = ROOM


func _open_phone(pilot: Autopilot) -> void:
	if _phone() == null:
		_ui.open_phone()
	await pilot.seconds(0.5)
	_phone().get_contacts_tab().flush_rows()


# ─── Móvil ─────────────────────────────────────────────────────────

func _phone_shots(pilot: Autopilot) -> void:
	await _open_phone(pilot)
	_phone().get_contacts_tab().select(GOSSIP)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_contacts")
	await _chat_shot(pilot)
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	_phone().get_bribe_panel().select_favour("look_away_once")
	_phone().get_bribe_panel().set_amount(180)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_blind")
	await _counter_shot(pilot)
	_phone().close_bribe()
	_phone().open_call(GOSSIP)
	_phone().refresh_exposure()
	await pilot.seconds(1.3)
	await pilot.shot("phone_call_exposed")
	_phone().get_call_tab().hang_up()
	_ui.close_modal()


## Exigencia de chantaje de Sonia por chat y un trato con Debbie.
func _chat_shot(pilot: Autopilot) -> void:
	_demand(COWARD, Blackmail.KIND_WITNESSED, "drawer_forced", Blackmail.DEMAND_MONEY)
	await pilot.frames(2)
	_ui.close_modal_control(_ui.get_top_modal() as Control)
	await pilot.frames(2)
	_phone().open_chat(COWARD)
	await pilot.seconds(0.9)
	await pilot.shot("phone_chat")
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	_fixed_rolls(_phone().get_bribe_panel(), 0.0)
	_phone().get_bribe_panel().set_amount(Bribery.fair_price(NPCDirector.get_npc(GOSSIP), "look_away_once"))
	_phone().get_bribe_panel().request_offer()
	_phone().get_bribe_panel().confirm_offer()
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_result")
	_phone().open_chat(GOSSIP)
	await pilot.seconds(0.4)
	await pilot.shot("phone_chat_deal")


func _demand(npc_id: String, kind: String, crime: String, demand_type: String) -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	var entry: Dictionary = Blackmail.add_material(npc, kind, crime, GameClock.get_day(), demand_type, 0)
	Blackmail.issue_demand(npc, entry, GameClock.get_day())


func _fixed_rolls(panel: BribePanel, roll: float) -> void:
	var phone: PhoneOverlay = _phone()
	panel.ctx_provider = func(channel: String) -> Dictionary:
		var ctx: Dictionary = phone.offer_context(channel)
		ctx["roll"] = roll
		ctx["counter_roll"] = 0.5
		return ctx


## Tom pide más de lo que el jugador tiene: «Ofrecer lo que pide» queda deshabilitado y explicado.
func _counter_shot(pilot: Autopilot) -> void:
	var panel: BribePanel = _phone().get_bribe_panel()
	_phone().open_bribe(BRIBABLE, Bribery.CHANNEL_MOBILE_CHAT)
	_fixed_rolls(panel, 0.99)
	panel.select_favour("praise_to_superior")
	panel.set_amount(Bribery.fair_price(NPCDirector.get_npc(BRIBABLE), "praise_to_superior"))
	panel.request_offer()
	panel.confirm_offer()
	var short: int = PlayerState.get_money() - panel.asked_price() + 45
	if panel.asked_price() > 0 and short > 0:
		PlayerState.add_money(-short, "qa")
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_counter")
	if panel.asked_price() > 0 and short > 0:
		PlayerState.add_money(short, "qa")


func _privacy_shots(pilot: Autopilot) -> void:
	_move_player_to(TOILETS)
	await pilot.frames(SETTLE)
	await _open_phone(pilot)
	_phone().refresh_exposure()
	_phone().open_bribe(OBLIVIOUS, Bribery.CHANNEL_PHONE_CALL)
	_phone().get_bribe_panel().select_favour("lend_access")
	_phone().get_bribe_panel().set_amount(300)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_call_private")
	_phone().close_bribe()
	_move_player_to(STAIRS)
	await pilot.frames(SETTLE)
	_phone().refresh_exposure()
	_phone().open_call(CLIMBER)
	await pilot.seconds(1.1)
	await pilot.shot("phone_call_stairs")
	_phone().get_call_tab().hang_up()
	_ui.close_modal()
	_move_player_to(ROOM)
	await pilot.frames(SETTLE)


func _estimate_and_reply_shots(pilot: Autopilot) -> void:
	PlayerState.set_occupation(DIRECTOR_OCCUPATION, "qa")
	PlayerState.add_money(4800, "qa")
	await _open_phone(pilot)
	_phone().open_bribe(HARDLINER, Bribery.CHANNEL_MOBILE_CHAT)
	_phone().get_bribe_panel().select_favour("praise_to_superior")
	_phone().get_bribe_panel().nudge(-6)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_n5")
	PlayerState.set_occupation(START_OCCUPATION, "qa")
	_phone().close_bribe()
	_phone().open_chat(COWARD)
	await pilot.frames(SETTLE)
	_phone().get_chat_tab().answer_demand()
	await pilot.seconds(0.5)
	await pilot.shot("phone_blackmail_reply")
	await _close_all(pilot)


# ─── Flagrancia ────────────────────────────────────────────────────

func _caught_shots(pilot: Autopilot) -> void:
	await _open_phone(pilot)
	EventBus.player_caught_redhanded.emit(GOSSIP, "drawer_forced", 2)
	await pilot.seconds(CAUGHT_RUN_SECONDS)
	await pilot.shot("caught_witnesses")
	_handler.resolve_inaction(0.0)
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos") + 0.3)
	EventBus.player_caught_redhanded.emit(OBLIVIOUS, "theft_small", 0)
	await pilot.seconds(CAUGHT_RUN_SECONDS)
	await pilot.shot("caught_clear")
	(_ui.get_top_modal() as CaughtWindow).press_elimination()
	await pilot.frames(SETTLE)
	await pilot.shot("caught_confirm")
	(_ui.get_top_modal() as CaughtWindow).back_out()
	_handler.resolve_inaction(0.9)
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos") + 0.3)
	await _counteroffer_shot(pilot)
	await _inaction_shot(pilot)


func _counteroffer_shot(pilot: Autopilot) -> void:
	var guard: NPCRuntime = NPCDirector.get_npc(BRIBABLE)
	guard.current_room = ROOM
	EventBus.player_caught_redhanded.emit(BRIBABLE, "theft_product", 1)
	await pilot.frames(4)
	var window: CaughtWindow = _ui.get_top_modal() as CaughtWindow
	window.bribe_ctx = {"roll": 0.99, "counter_roll": 0.5}
	window.press_bribe()
	window.confirm()
	await pilot.seconds(0.6)
	await pilot.shot("caught_counteroffer")
	_handler.resolve_inaction(0.9)
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos") + 0.3)


func _inaction_shot(pilot: Autopilot) -> void:
	EventBus.player_caught_redhanded.emit(CHIEF, "file_copied", 1)
	await pilot.frames(4)
	_handler.advance_timer(float(_handler.get_options().get("seconds_left", 0.0)) + 0.01)
	await pilot.seconds(0.8)
	await pilot.shot("caught_inaction")
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos"))


# ─── Chantaje, idioma, contraste y pantalla de móvil ───────────────

func _blackmail_shot(pilot: Autopilot) -> void:
	await _close_all(pilot)
	var face: BlackmailDialog = BlackmailDialog.open_for(_ui, BRIBABLE)
	if face != null:
		await pilot.seconds(0.4)
		await pilot.shot("blackmail_face")
		face.press_pay()
		await pilot.frames(SETTLE)
		await pilot.shot("blackmail_confirm")
	await _close_all(pilot)
	_demand(SNITCH, Blackmail.KIND_LEVERAGE, "idea_stolen", Blackmail.DEMAND_PROMOTION)
	await pilot.seconds(0.5)
	await pilot.shot("blackmail_demand")
	await _close_all(pilot)


func _close_all(pilot: Autopilot) -> void:
	await pilot.frames(2)
	while _ui.has_modal():
		_ui.close_modal()
		await pilot.frames(1)
	_ui.get_toasts().clear()


func _spanish_shot(pilot: Autopilot) -> void:
	TranslationServer.set_locale("es")
	await _open_phone(pilot)
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_PHONE_CALL)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_es")
	_ui.close_modal()
	TranslationServer.set_locale("en")


func _contrast_shot(pilot: Autopilot) -> void:
	_ui.set_text_options(UITheme.TEXT_MEDIUM, true)
	await pilot.frames(2)
	await _open_phone(pilot)
	_phone().get_contacts_tab().select(OBLIVIOUS)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_high_contrast")
	_ui.close_modal()
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	await pilot.frames(2)
	await _open_phone(pilot)
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_PHONE_CALL)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_large_bribe")
	_ui.close_modal()
	_ui.set_text_options(UITheme.TEXT_MEDIUM, false)
	await pilot.frames(2)


func _mobile_shots(pilot: Autopilot) -> void:
	get_window().size = MOBILE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	await pilot.frames(SETTLE)
	await _open_phone(pilot)
	await pilot.shot("phone_mobile_contacts")
	_phone().open_chat(SNITCH)
	await pilot.seconds(0.6)
	await pilot.shot("phone_mobile_chat")
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_mobile_bribe")
	await _mobile_result(pilot)
	_phone().open_call(GOSSIP)
	await pilot.seconds(0.6)
	await pilot.shot("phone_mobile_call")
	_ui.close_modal()
	await _mobile_caught(pilot)
	get_window().size = DESKTOP_WINDOW


func _mobile_result(pilot: Autopilot) -> void:
	var panel: BribePanel = _phone().get_bribe_panel()
	_phone().open_bribe(BRIBABLE, Bribery.CHANNEL_MOBILE_CHAT)
	_fixed_rolls(panel, 0.99)
	panel.select_favour("lend_access")
	panel.set_amount(Bribery.fair_price(NPCDirector.get_npc(BRIBABLE), "lend_access"))
	panel.request_offer()
	panel.confirm_offer()
	await pilot.frames(SETTLE)
	await pilot.shot("phone_mobile_result")
	_phone().close_bribe()


func _mobile_caught(pilot: Autopilot) -> void:
	EventBus.player_caught_redhanded.emit(COWARD, "drawer_forced", 1)
	await pilot.seconds(CAUGHT_RUN_SECONDS)
	await pilot.shot("caught_mobile")
	_handler.resolve_inaction(0.9)
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos") + 0.3)
	EventBus.player_caught_redhanded.emit(CLIMBER, "file_copied", 0)
	await pilot.seconds(CAUGHT_RUN_SECONDS)
	(_ui.get_top_modal() as CaughtWindow).press_elimination()
	await pilot.frames(SETTLE)
	await pilot.shot("caught_mobile_confirm")
	_handler.resolve_inaction(0.9)
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos") + 0.3)
	await _close_all(pilot)
	_demand(HARDLINER, Blackmail.KIND_WITNESSED, "theft_small", Blackmail.DEMAND_MONEY)
	await pilot.seconds(0.6)
	await pilot.shot("blackmail_mobile")
	await _close_all(pilot)
