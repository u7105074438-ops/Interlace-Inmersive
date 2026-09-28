# _office_kit.gd — Utilidades compartidas del módulo de oficina (office.gd): contexto, avisos con sonido, actos ilegales vigilados, marcas por jornada y azar reproducible.
# PROPIETARIO DE: nada (estático; lo que deba recordarse vive en PlayerState como banderas "office.*").
# ESCUCHA: nada.
class_name OfficeKit
extends RefCounted

## Archivo privado ("_"): el InteractionRouter no lo trata como módulo. Reglas comunes (§15):
##  · Todo acto ilegal pasa por run_act(): si alguien mira (GameRoot.find_observer) se pregunta
##    antes con el nombre de quien mira (la opción segura lleva el foco, §13.7); después
##    player.begin_act(delito, segundos) y se espera act_finished: moverse lo cancela y
##    Perception puede pillarlo mientras dura. El delito (crime_committed) lo emite quien llama,
##    solo si el acto terminó.
##  · Las acciones legales son inmediatas: animación corta + minutos de reloj + aviso.
##  · Recordar «ya lo hice hoy»: banderas de PlayerState (se guardan con la partida).
##  · Duraciones y minutos: balance oficina.segundos_acto.* y oficina.minutos.*.
##    qa_act_seconds >= 0 (solo pruebas y escenarios QA) sustituye la duración de los actos.

const B_ACT_SECONDS := "oficina.segundos_acto."
const B_MINUTES := "oficina.minutos."
const FLAG_DAY := "office.day."
const FLAG_LIST := "office.list."
const NO_DAY := -1
## «Nunca»: jornadas desde algo que no ha pasado (mayor que cualquier enfriamiento).
const NEVER_DAYS := 1_000_000
## Suelo técnico de un acto (un acto de 0 s sería «hasta end_act()» en Player.begin_act).
const MIN_ACT_SECONDS := 0.1
const QA_MIN_SECONDS := 0.01
const NO_POSITION := Vector2.INF
const OBSERVER_NPC := "npc"
const CHOICE_PROCEED := 1
const SFX_OK := "ui_confirm"
const SFX_ERROR := "ui_error"
const SFX_INFO := "ui_notify"
const SFX_CASH := "cash"
const SFX_CHAT := "chatter"
const PLAYER_ID := "player"
const NOTE_FILES := "files"
const ACT_SIGNAL := "act_finished"
const GENERATED_OWNER := "generated"
const INFO_BODY := "OFFICE_INFO_BODY"
const CLOSE_KEY := "OFFICE_CLOSE"
const LINE_JOIN := "\n• "
const LINE_BULLET := "• "

## QA: >= 0 sustituye la duración (segundos reales) de todos los actos de oficina.
static var qa_act_seconds: float = -1.0


# ─── Contexto ─────────────────────────────────────────────────

static func ui(ctx: Dictionary) -> UIRoot:
	return ctx.get("ui_root") as UIRoot


static func root(ctx: Dictionary) -> GameRoot:
	return ctx.get("game_root") as GameRoot


static func tree_of(node: Node) -> SceneTree:
	return node.get_tree() if node != null and node.is_inside_tree() else Engine.get_main_loop() as SceneTree


## Nodo de simulación de la partida (GameRoot.sim_nodes) o, sin raíz, el primero de su grupo.
static func sim(ctx: Dictionary, node_name: String, group: String) -> Node:
	var game: GameRoot = root(ctx)
	if game != null and game.sim_nodes.has(node_name):
		return game.sim_nodes[node_name] as Node
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group(group) if tree != null else null


static func pos_of(node: Node) -> Vector2:
	return (node as Node2D).global_position if node is Node2D else NO_POSITION


# ─── Avisos y sonido ──────────────────────────────────────────

static func sfx(node: Node, sfx_id: String, at: Vector2 = NO_POSITION) -> void:
	var tree: SceneTree = tree_of(node)
	var audio: AudioDirector = AudioDirector.find(tree) if tree != null else null
	if audio != null and not sfx_id.is_empty():
		audio.play_sfx(sfx_id, at)


## Aviso (toast) con su sonido: toda acción responde algo (§15).
static func say(ctx: Dictionary, key: String, args: Array = [], kind: String = ToastStack.KIND_INFO,
		sfx_id: String = SFX_INFO) -> void:
	var view: UIRoot = ui(ctx)
	if view != null:
		view.toast(key, args, kind)
	sfx(view, sfx_id)


static func good(ctx: Dictionary, key: String, args: Array = [], sfx_id: String = SFX_OK) -> void:
	say(ctx, key, args, ToastStack.KIND_GOOD, sfx_id)


static func refuse(ctx: Dictionary, key: String, args: Array = []) -> void:
	say(ctx, key, args, ToastStack.KIND_WARN, SFX_ERROR)


## Ficha de lectura (terminales, pizarras, archivos): título sin argumentos y líneas ya traducidas.
static func show_lines(ctx: Dictionary, title_key: String, lines: Array[String]) -> void:
	var view: UIRoot = ui(ctx)
	sfx(view, SFX_INFO)
	if view == null or lines.is_empty():
		return
	await view.show_dialog(title_key, INFO_BODY, [CLOSE_KEY], [bullets(lines)])


static func bullets(lines: Array[String]) -> String:
	return LINE_BULLET + LINE_JOIN.join(PackedStringArray(lines))


## Menú de opciones (claves o {text_key, args, danger}); devuelve el índice o -1.
static func choose(ctx: Dictionary, title_key: String, body_key: String, options: Array, args: Array = []) -> int:
	var view: UIRoot = ui(ctx)
	if view == null:
		return DialogBox.CANCEL
	return await view.show_dialog(title_key, body_key, options, args)


## Confirmación de algo grave: la opción peligrosa va en 1 y el foco en «Mejor no» (§13.7).
static func confirm(ctx: Dictionary, title_key: String, body_key: String, go_key: String, args: Array = []) -> bool:
	var index: int = await choose(ctx, title_key, body_key,
			["OFFICE_NOT_NOW", {"text_key": go_key, "args": args, "danger": true}], args)
	return index == CHOICE_PROCEED


# ─── Actos ilegales ───────────────────────────────────────────

## Segundos reales de un acto (oficina.segundos_acto.<clase>; QA: qa_act_seconds).
static func act_seconds(kind: String) -> float:
	if qa_act_seconds >= 0.0:
		return maxf(qa_act_seconds, QA_MIN_SECONDS)
	return maxf(Database.get_balance_float(B_ACT_SECONDS + kind), MIN_ACT_SECONDS)


static func minutes(kind: String) -> float:
	return Database.get_balance_float(B_MINUTES + kind)


static func spend_minutes(kind: String) -> void:
	var m: float = minutes(kind)
	if m > 0.0:
		GameClock.advance_minutes(m)


## Si alguien ve al jugador, pregunta antes (nombra al testigo o la cámara). true = adelante.
static func confirm_if_watched(ctx: Dictionary) -> bool:
	var game: GameRoot = root(ctx)
	if game == null:
		return true
	var who: Dictionary = game.find_observer()
	if who.is_empty():
		return true
	var watcher: String = npc_name(str(who.get("id", ""))) if str(who.get("kind", "")) == OBSERVER_NPC \
			else tr_key("OFFICE_WATCHED_CAMERA")
	return await confirm(ctx, "OFFICE_WATCHED_TITLE", "OFFICE_WATCHED_BODY", "OFFICE_WATCHED_PROCEED", [watcher])


## Acto ilegal visible: begin_act(delito) durante oficina.segundos_acto.<clase>. true si terminó
## (moverse, que te pillen o un testigo que te detiene lo cancelan).
static func run_act(ctx: Dictionary, player: Node, crime: String, kind: String, ask: bool = true) -> bool:
	if ask and not await confirm_if_watched(ctx):
		say(ctx, "OFFICE_ACT_ABORTED")
		return false
	if player == null or not player.has_method("begin_act") or not player.has_signal(ACT_SIGNAL):
		return true
	player.call("begin_act", crime, act_seconds(kind))
	var result: Variant = await Signal(player, ACT_SIGNAL)
	var done: bool = result is Array and (result as Array).size() > 1 and bool((result as Array)[1])
	if not done:
		say(ctx, "OFFICE_ACT_INTERRUPTED", [], ToastStack.KIND_WARN, SFX_ERROR)
	return done


static func commit(crime: String, room_id: String, details: Dictionary) -> void:
	EventBus.crime_committed.emit(crime, room_id, details)


## Ruido del acto (noise_emitted en la posición del jugador; radio en celdas de balance).
static func noise(player: Node, radius_path: String, source: String) -> void:
	if player is Node2D:
		EventBus.noise_emitted.emit((player as Node2D).global_position,
				Database.get_balance_float(radius_path), source)


static func play(player: Node, anim: String) -> void:
	if player != null and player.has_method("play_anim"):
		player.call("play_anim", anim)


# ─── Memoria (banderas de PlayerState) ────────────────────────

static func used_today(key: String) -> bool:
	return last_day(key) == GameClock.get_day()


static func mark_today(key: String) -> void:
	PlayerState.set_flag(FLAG_DAY + key, GameClock.get_day())


static func last_day(key: String) -> int:
	var v: Variant = PlayerState.get_flag(FLAG_DAY + key, NO_DAY)
	return int(v) if v is int or v is float else NO_DAY


## Jornadas desde la última vez (muchas si nunca).
static func days_since(key: String) -> int:
	var day: int = last_day(key)
	return GameClock.get_day() - day if day != NO_DAY else NEVER_DAYS


static func get_list(key: String) -> Array:
	var v: Variant = PlayerState.get_flag(FLAG_LIST + key, [])
	return (v as Array).duplicate() if v is Array else []


static func set_list(key: String, values: Array) -> void:
	PlayerState.set_flag(FLAG_LIST + key, values if not values.is_empty() else null)


## Azar reproducible por partida, jornada y objeto (mismo resultado si se repite el día).
static func rng(salt: String) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash([GameClock.get_run_seed(), GameClock.get_day(), salt])
	return r


## Elige una entrada {que, peso} de una tabla de balance.
static func roll_table(table: Array, r: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for entry: Variant in table:
		if entry is Dictionary:
			total += maxf(float((entry as Dictionary).get("peso", 0.0)), 0.0)
	var roll: float = r.randf() * total
	for entry: Variant in table:
		if not entry is Dictionary:
			continue
		roll -= maxf(float((entry as Dictionary).get("peso", 0.0)), 0.0)
		if roll < 0.0:
			return str((entry as Dictionary).get("que", ""))
	return ""


# ─── Nombres, salas y puestos ─────────────────────────────────

static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)


static func item_name(item_id: String) -> String:
	var item: ItemData = Database.get_item(item_id)
	return tr_key(item.name_key) if item != null else item_id


static func item_value(item_id: String) -> int:
	var item: ItemData = Database.get_item(item_id)
	return item.value if item != null else 0


## Copia independiente del objeto del catálogo (make_item devuelve el del catálogo: no se toca).
static func item_copy(item_id: String, extra: Dictionary = {}) -> ItemData:
	var src: ItemData = InventoryRules.make_item(item_id)
	var copy: ItemData = ItemData.make(src.id, src.name_key, src.category)
	copy.value = src.value
	copy.extra = src.extra.duplicate(true)
	copy.extra.merge(extra, true)
	return copy


## ¿Cabe una unidad más? (apilable ya presente, efectivo de bolsillo o hueco libre).
static func can_take(item_id: String) -> bool:
	var item: ItemData = InventoryRules.make_item(item_id)
	if InventoryRules.is_pocket_cash(item):
		return true
	if InventoryRules.is_stackable(item) and PlayerState.is_carrying(item_id):
		return true
	return PlayerState.get_free_slots() > 0


static func npc_name(npc_id: String) -> String:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc != null and not npc.name.is_empty():
		return npc.name
	var named: NPCData = Database.get_named_npc(npc_id)
	if named != null:
		return named.name
	var investor: InvestorData = Database.get_investor(npc_id)
	return investor.name if investor != null else tr_key("OFFICE_SOMEONE")


static func base_room(room_id: String) -> String:
	return DatabaseSystem.get_room_base_id(room_id)


static func is_own_room(room_id: String) -> bool:
	var occ: OccupationData = PlayerState.get_occupation()
	return occ != null and not room_id.is_empty() and base_room(room_id) == occ.office_room


static func has_post(posts: Variant) -> bool:
	return posts is Array and (posts as Array).has(PlayerState.get_occupation_id())


static func has_access(access: String) -> bool:
	var occ: OccupationData = PlayerState.get_occupation()
	return occ != null and occ.special_access.has(access)


## Dueño de un mueble: el de los datos o, si es "generated", el personaje de esa sala cuyo puesto
## (desk_position) queda más cerca del mueble; "" si nadie.
static func owner_of(item: Interactable) -> String:
	var owner: String = str(item.data.get("owner", ""))
	if owner != GENERATED_OWNER:
		return owner
	var raw: Variant = item.data.get("pos", Vector2i.ZERO)
	var at: Vector2i = raw as Vector2i if raw is Vector2i else Vector2i.ZERO
	var best: String = ""
	var best_d: float = INF
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if not npc.alive or base_room(npc.home_room) != base_room(item.room_id):
			continue
		var d: float = Vector2(npc.desk_position - at).length()
		if d < best_d:
			best_d = d
			best = npc.id
	return best


## El personaje está ahora en esa sala (NPCDirector).
static func is_present(npc_id: String, room_id: String) -> bool:
	return not npc_id.is_empty() and NPCDirector.is_active(npc_id) \
			and IdeaPoolSystem.same_room(NPCDirector.get_current_location(npc_id), room_id)


## Deja constancia en el cuaderno (memoria externa, §13.3).
static func note(category: String, key: String, args: Array = []) -> void:
	EventBus.notebook_entry_added.emit(category, key, args)
