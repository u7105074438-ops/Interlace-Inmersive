# _security_kit.gd — Utilidades compartidas del módulo de seguridad e infraestructura: balance operativa.*, avisos, diálogos, listas, actos visibles (con ruido), testigos y banderas.
# PROPIETARIO DE: nada (biblioteca estática; las banderas secops.* viven en PlayerState y se guardan con él).
# ESCUCHA: nada.
class_name SecurityKit
extends RefCounted

## Privado del módulo security.gd (los archivos "_*" no son módulos del InteractionRouter).
## · Actos: act() = Player.begin_act + act_finished (moverse lo cancela: false). noisy_act() además
##   emite noise_emitted cada operativa.cerraduras.intervalo_ruido s mientras dura (forzar).
##   Con SecurityKeeper.instant (pruebas y QA) duran operativa.segundos_acto_minimo.
## · Las acciones LEGÍTIMAS (usar tu llave, apagar la maquinaria en tu ronda) no son actos: solo una
##   animación corta (legit_pause), para que la percepción no las tome por delitos.
## · watched_ok(): si alguien ve al jugador ahora mismo, avisa con su nombre antes de un delito
##   (equidad: nunca se pierde por no saber que te miraban).
## · pick(): lista o rejilla (FloorTravel.FloorSelectPanel) con pausa de reloj; todas las entradas
##   son elegibles (la semántica de "no disponible" la explica el módulo con un aviso).

const B := "operativa."
const FLAG := "secops."
const NO_POS := Vector2(INF, INF)
const PLAYER_ID := "player"
const UNIFORM_PREFIX := "uniform:"
const ACT_MIN := "segundos_acto_minimo"
const NOISE_INTERVAL := "cerraduras.intervalo_ruido"
const MSEC := 1000.0


# ─── Balance ──────────────────────────────────────────────────

static func bf(path: String) -> float:
	return Database.get_balance_float(B + path)


static func bi(path: String) -> int:
	return Database.get_balance_int(B + path)


static func bs(path: String) -> String:
	return str(Database.get_balance(B + path))


static func barr(path: String) -> Array:
	var value: Variant = Database.get_balance(B + path)
	return value if value is Array else []


static func bdict(path: String) -> Dictionary:
	var value: Variant = Database.get_balance(B + path)
	return value if value is Dictionary else {}


# ─── Banderas (PlayerState) ───────────────────────────────────

static func flag(key: String, default_value: Variant = null) -> Variant:
	return PlayerState.get_flag(FLAG + key, default_value)


static func set_flag(key: String, value: Variant) -> void:
	PlayerState.set_flag(FLAG + key, value)


static func flag_dict(key: String) -> Dictionary:
	var value: Variant = flag(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func flag_array(key: String) -> Array:
	var value: Variant = flag(key, [])
	return (value as Array).duplicate(true) if value is Array else []


static func today() -> int:
	return GameClock.get_day()


# ─── Contexto ─────────────────────────────────────────────────

static func ui(ctx: Dictionary) -> UIRoot:
	return ctx.get("ui_root") as UIRoot


static func tree_of(node: Node) -> SceneTree:
	return node.get_tree() if node != null and node.is_inside_tree() else Engine.get_main_loop() as SceneTree


static func streamer(ctx: Dictionary) -> FloorStreamer:
	return ctx.get("streamer") as FloorStreamer


static func room_of(ctx: Dictionary) -> String:
	return str(ctx.get("room_id", ""))


static func base_room(room_id: String) -> String:
	return DatabaseSystem.get_room_base_id(room_id)


static func instant(node: Node) -> bool:
	var keeper: SecurityKeeper = SecurityKeeper.find(tree_of(node))
	return keeper != null and keeper.instant


static func act_seconds(node: Node, seconds: float) -> float:
	return bf(ACT_MIN) if instant(node) else maxf(seconds, bf(ACT_MIN))


# ─── Avisos y sonido ──────────────────────────────────────────

static func toast(ctx: Dictionary, key: String, args: Array = [], kind: String = ToastStack.KIND_INFO) -> void:
	var root: UIRoot = ui(ctx)
	if root != null:
		root.toast(key, args, kind)


static func sfx(node: Node, id: String, pos: Vector2 = NO_POS) -> void:
	var audio: AudioDirector = AudioDirector.find(tree_of(node))
	if audio == null:
		return
	if pos.is_finite():
		audio.play_sfx(id, pos)
	else:
		audio.play_sfx(id)


## La indicación del objeto enfocado cambió sin cambiar el foco (esconderse, empezar a arrastrar):
## la interfaz la muestra ya (el jugador solo la refresca al cambiar de foco).
static func refresh_prompt(ctx: Dictionary, item: Interactable, key: String) -> void:
	var root: UIRoot = ui(ctx)
	if root == null or item == null or not is_instance_valid(item) or root.get_focused_interactable() != item:
		return
	root.set_context_action(key if not key.is_empty() else item.get_prompt_key(), UITheme.icon_for_interact_type(item.interact_type))


static func noise(pos: Vector2, radius: float, source: String) -> void:
	EventBus.noise_emitted.emit(pos, radius, source)


static func note(text_key: String, args: Array = []) -> void:
	EventBus.notebook_entry_added.emit("security", text_key, args)


# ─── Diálogos ─────────────────────────────────────────────────

## Diálogo de opciones (-1 = cancelado o sin interfaz).
static func choose(ctx: Dictionary, title_key: String, body_key: String, options: Array, args: Array = []) -> int:
	var root: UIRoot = ui(ctx)
	if root == null:
		return DialogBox.CANCEL
	return await root.show_dialog(title_key, body_key, options, args)


## Confirmación de algo irreversible: la opción peligrosa va primero pero el foco cae en Cancelar.
static func confirm(ctx: Dictionary, title_key: String, body_key: String, confirm_key: String, args: Array = []) -> bool:
	var options: Array = [{"text_key": confirm_key, "danger": true}, "UI_CANCEL"]
	return await choose(ctx, title_key, body_key, options, args) == 0


## Lista (o rejilla) de entradas ya traducidas. Devuelve el índice elegido o -1.
static func pick(ctx: Dictionary, title: String, hint: String, labels: Array[String], grid: bool = false,
		values: Array[int] = []) -> int:
	var root: UIRoot = ui(ctx)
	if root == null or labels.is_empty():
		return DialogBox.CANCEL
	var options: Array[Dictionary] = []
	for i: int in labels.size():
		options.append({"floor": values[i] if i < values.size() else i, "label": labels[i], "allowed": true, "clearance": 0})
	var panel: FloorTravel.FloorSelectPanel = FloorTravel.FloorSelectPanel.new()
	panel.setup(title, hint, options, grid, 0)
	root.open_modal(panel, true)
	var index: int = await panel.chosen
	if is_instance_valid(panel):
		root.close_modal_control(panel)
	return index if index >= 0 and index < labels.size() else DialogBox.CANCEL


## Alguien ve al jugador ahora: avisa con su nombre y pide confirmación. true = seguir.
static func watched_ok(ctx: Dictionary, player: Node) -> bool:
	var seen_by: Array[String] = witnesses(player)
	if seen_by.is_empty():
		return true
	var options: Array = [{"text_key": "SECOPS_WATCHED_GO", "danger": true}, "UI_CANCEL"]
	return await choose(ctx, "SECOPS_WATCHED_TITLE", "SECOPS_WATCHED_BODY", options, [npc_name(seen_by[0]), seen_by.size()]) == 0


## Personajes con la percepción activa (LOD 0) que ven al jugador ahora (cono + línea de visión).
static func witnesses(player: Node) -> Array[String]:
	var out: Array[String] = []
	if not player is Node2D or not player.is_inside_tree():
		return out
	var pos: Vector2 = (player as Node2D).global_position
	for node: Node in player.get_tree().get_nodes_in_group(Perception.GROUP):
		var eyes: Perception = node as Perception
		if eyes != null and eyes.is_active() and not eyes.npc_id.is_empty() and not out.has(eyes.npc_id) \
				and eyes.is_inside_tree() and eyes.sees_point(pos):
			out.append(eyes.npc_id)
	return out


# ─── Actos ────────────────────────────────────────────────────

## Acto ilegal visible (Perception lo puede sorprender). true si se completó sin moverse.
static func act(player: Node, crime: String, seconds: float) -> bool:
	if player == null or not player.has_method("begin_act"):
		return true
	player.call("begin_act", crime, act_seconds(player, seconds))
	var result: Array = await player.act_finished
	return result.size() > 1 and bool(result[1])


## Acto ruidoso: noise_emitted al empezar y cada intervalo mientras dure (forzar, cortar).
static func noisy_act(player: Node, crime: String, seconds: float, radius: float, source: String) -> bool:
	if not player is Node2D or not player.has_method("begin_act"):
		return true
	var state: Dictionary = {"done": false, "ok": false}
	var on_done: Callable = func(_crime: String, ok: bool) -> void:
		state["done"] = true
		state["ok"] = ok
	player.call("begin_act", crime, act_seconds(player, seconds))
	player.connect("act_finished", on_done, CONNECT_ONE_SHOT)
	var tree: SceneTree = player.get_tree()
	var last: int = Time.get_ticks_msec()
	noise((player as Node2D).global_position, radius, source)
	while not bool(state["done"]) and is_instance_valid(player):
		await tree.process_frame
		if Time.get_ticks_msec() - last >= int(bf(NOISE_INTERVAL) * MSEC) and not bool(state["done"]):
			last = Time.get_ticks_msec()
			noise((player as Node2D).global_position, radius, source)
	return bool(state["ok"])


## Gesto legítimo (no es un acto: la percepción no lo trata como delito).
static func legit_pause(player: Node, anim: String) -> void:
	if player == null or not player.has_method("play_anim"):
		return
	player.call("play_anim", anim)
	await tree_of(player).create_timer(act_seconds(player, bf("segundos_gesto"))).timeout


# ─── Objetos y nombres ────────────────────────────────────────

## Primer id de la lista que el jugador lleva encima ("" si ninguno).
static func carried_of(ids: Array) -> String:
	for id: Variant in ids:
		if PlayerState.is_carrying(str(id)):
			return str(id)
	return ""


## Primer id que tiene (encima o entregado por el puesto).
static func owned_of(ids: Array) -> String:
	for id: Variant in ids:
		if PlayerState.has_item(str(id)):
			return str(id)
	return ""


## Añade objetos al inventario: {taken: Array[String], left: Array[String], value: int}.
static func take_items(ids: Array) -> Dictionary:
	var taken: Array[String] = []
	var left: Array[String] = []
	var value: int = 0
	for id: Variant in ids:
		var item: ItemData = Database.get_item(str(id))
		if item != null and PlayerState.add_item(str(id)):
			taken.append(str(id))
			value += item.value
		else:
			left.append(str(id))
	return {"taken": taken, "left": left, "value": value}


static func item_name(item_id: String) -> String:
	var item: ItemData = Database.get_item(item_id)
	return TranslationServer.translate(item.name_key) if item != null else item_id


static func item_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id: Variant in ids:
		names.append(item_name(str(id)))
	return ", ".join(names)


static func npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id) if not npc_id.is_empty() else null
	return npc.name if npc != null else TranslationServer.translate("SECOPS_SOMEONE")


static func room_name(room_id: String) -> String:
	var room: RoomData = Database.get_room(base_room(room_id))
	return TranslationServer.translate(room.name_key) if room != null else room_id


static func floor_of_room(room_id: String) -> int:
	var room: RoomData = Database.get_room(base_room(room_id))
	if room == null:
		return PlayerState.get_floor()
	if room.floor == RoomData.TRANSVERSAL_FLOOR and room_id.contains("@"):
		return int(room_id.get_slice("@", 1))
	return room.floor


## Plantas de un rango [min, max] (balance) como enteros.
static func floor_range(path: String) -> Array[int]:
	var bounds: Array = barr(path)
	var out: Array[int] = []
	if bounds.size() < 2:
		return out
	for f: int in range(int(bounds[0]), int(bounds[1]) + 1):
		out.append(f)
	return out


static func floor_labels(floors: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for f: int in floors:
		out.append(MapView.floor_label_short(f))
	return out
