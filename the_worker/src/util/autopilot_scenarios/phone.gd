# phone.gd (escenario) — Capturas del móvil (contactos, chat, soborno a ciegas y con N5, llamada), de la flagrancia (con y sin testigos, contraoferta, inacción) y del chantaje.
# PROPIETARIO DE: los nodos temporales del escenario (planta 3, jugador, figuras, UIRoot, CaughtHandler).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_phone phone
## Capturas: phone_contacts, phone_chat, phone_bribe_blind (N1), phone_bribe_n5, phone_call_exposed,
## phone_call_private, caught_witnesses, caught_clear, caught_confirm, caught_counteroffer,
## caught_inaction, blackmail_demand, phone_es, phone_mobile_contacts, phone_mobile_bribe,
## caught_mobile (pantalla 20:9 con controles táctiles).

const FLOOR := 3
const ROOM := "wing_3b"
const TOILETS := "p3_toilets"
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
	await _caught_shots(pilot)
	await _blackmail_shot(pilot)
	await _spanish_shot(pilot)
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
	for npc_id: String in [CHIEF, GOSSIP, SNITCH, OBLIVIOUS, COWARD, HARDLINER]:
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		if npc != null:
			npc.current_room = ROOM
			npc.floor = FLOOR


func _build_world() -> void:
	_streamer = FloorStreamer.new()
	add_child(_streamer)
	_streamer.load_floor(FLOOR)
	_player = (load("res://scenes/world/player.tscn") as PackedScene).instantiate() as Player
	_streamer.get_actor_layer().add_child(_player)
	_streamer.set_player(_player)
	var rect: Rect2 = _streamer.get_room_rect_px(ROOM)
	var cell: float = RoomBuilder.cell_px()
	_player.global_position = rect.position + Vector2(cell * PLAYER_CELLS.x, rect.size.y - cell * PLAYER_CELLS.y)
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


# ─── Móvil ─────────────────────────────────────────────────────────

func _phone_shots(pilot: Autopilot) -> void:
	_ui.open_phone()
	await pilot.seconds(0.5)
	_phone().get_contacts_tab().select(GOSSIP)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_contacts")
	await _chat_shot(pilot)
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	_phone().get_bribe_panel().select_favour("look_away_once")
	_phone().get_bribe_panel().set_amount(180)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_blind")
	await _call_shots(pilot)
	await _estimate_shot(pilot)
	_ui.close_modal()


## Exigencia de chantaje de George por chat y un trato previo con Debbie.
func _chat_shot(pilot: Autopilot) -> void:
	var snitch: NPCRuntime = NPCDirector.get_npc(COWARD)
	var entry: Dictionary = Blackmail.add_material(snitch, Blackmail.KIND_WITNESSED, "drawer_forced",
			GameClock.get_day(), Blackmail.DEMAND_MONEY, 0)
	Blackmail.issue_demand(snitch, entry, GameClock.get_day())
	await pilot.frames(2)
	_ui.close_modal_control(_ui.get_top_modal() as Control)
	await pilot.frames(2)
	_phone().open_chat(COWARD)
	await pilot.seconds(0.9)
	await pilot.shot("phone_chat")


func _call_shots(pilot: Autopilot) -> void:
	_phone().close_bribe()
	_phone().open_call(GOSSIP)
	_phone().refresh_exposure()
	await pilot.seconds(1.3)
	await pilot.shot("phone_call_exposed")
	_phone().get_call_tab().hang_up()
	_move_player_to(TOILETS)
	_phone().refresh_exposure()
	_phone().open_bribe(OBLIVIOUS, Bribery.CHANNEL_PHONE_CALL)
	_phone().get_bribe_panel().select_favour("lend_access")
	_phone().get_bribe_panel().set_amount(300)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_call_private")
	_move_player_to(ROOM)


func _estimate_shot(pilot: Autopilot) -> void:
	_ui.close_modal()
	PlayerState.set_occupation(DIRECTOR_OCCUPATION, "qa")
	PlayerState.add_money(4800, "qa")
	_ui.open_phone()
	await pilot.seconds(0.4)
	_phone().open_bribe(HARDLINER, Bribery.CHANNEL_MOBILE_CHAT)
	_phone().get_bribe_panel().select_favour("praise_to_superior")
	await pilot.frames(SETTLE)
	await pilot.shot("phone_bribe_n5")
	PlayerState.set_occupation(START_OCCUPATION, "qa")


func _move_player_to(room_id: String) -> void:
	EventBus.room_entered.emit(room_id, true)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.current_room == room_id and room_id == TOILETS:
			npc.current_room = ROOM


# ─── Flagrancia ────────────────────────────────────────────────────

func _caught_shots(pilot: Autopilot) -> void:
	_ui.open_phone()
	await pilot.frames(4)
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
	await pilot.seconds(0.5)
	await pilot.shot("caught_inaction")
	await pilot.seconds(PhoneOverlay.tune("interfaz.flagrancia_resultado_segundos"))


# ─── Chantaje, idioma y pantalla de móvil ──────────────────────────

func _blackmail_shot(pilot: Autopilot) -> void:
	var npc: NPCRuntime = NPCDirector.get_npc(SNITCH)
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_LEVERAGE, "idea_stolen",
			GameClock.get_day(), Blackmail.DEMAND_PROMOTION, 0)
	Blackmail.issue_demand(npc, entry, GameClock.get_day())
	await pilot.seconds(0.5)
	await pilot.shot("blackmail_demand")
	_ui.close_modal()
	await pilot.frames(2)
	while _ui.has_modal():
		_ui.close_modal()
		await pilot.frames(1)


func _spanish_shot(pilot: Autopilot) -> void:
	TranslationServer.set_locale("es")
	_ui.open_phone()
	await pilot.seconds(0.4)
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_PHONE_CALL)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_es")
	_ui.close_modal()
	TranslationServer.set_locale("en")


func _mobile_shots(pilot: Autopilot) -> void:
	get_window().size = MOBILE_WINDOW
	_ui.set_text_options(UITheme.TEXT_LARGE, false)
	_ui.set_touch_mode(true)
	await pilot.frames(SETTLE)
	_ui.open_phone()
	await pilot.seconds(0.5)
	await pilot.shot("phone_mobile_contacts")
	_phone().open_bribe(GOSSIP, Bribery.CHANNEL_MOBILE_CHAT)
	await pilot.frames(SETTLE)
	await pilot.shot("phone_mobile_bribe")
	_ui.close_modal()
	EventBus.player_caught_redhanded.emit(COWARD, "drawer_forced", 1)
	await pilot.seconds(CAUGHT_RUN_SECONDS)
	await pilot.shot("caught_mobile")
	_handler.resolve_inaction(0.9)
	get_window().size = DESKTOP_WINDOW
