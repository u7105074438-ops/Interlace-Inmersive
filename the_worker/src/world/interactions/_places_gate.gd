# _places_gate.gd — Los tornos de la PB (§4.1 fichaje, §5.6 franja de llegada): pasar la tarjeta (queda registrado al cruzar) o colarse detrás de un compañero en la hora punta (sin registro).
# PROPIETARIO DE: nada (la intención de colarse la guarda PlacesKeeper; el registro, DoorAccess y Security).
# ESCUCHA: nada.
class_name PlacesGate
extends RefCounted

## · "turnstile" (cada compuerta): E = pasar la tarjeta a mano (DoorAccess.swipe: abre y arma el
##   registro, que se escribe al cruzar) o el pitido rojo si la acreditación no llega. En la hora
##   punta con compañeros alrededor, la primera vez de la jornada se recuerda que se puede colarse.
## · "turnstile_queue" (punto de cola de PlacesKeeper, lejos del sensor): solo en las franjas de
##   lugares.torno.franjas_colarse y con un compañero junto a un torno. E = colarse: el keeper
##   abre ese torno sin armar el registro y el jugador pasa pegado al compañero (paso guiado al paso
##   sigiloso, con la entrada bloqueada). Sin card_log: la cámara sí graba.
## · Colarse también funciona sin la cola: entrar sigiloso (Mayús) o agachado detrás de alguien.

const T_GATE := "turnstile"
const T_QUEUE := "turnstile_queue"
const TYPES: Array[String] = [T_GATE, T_QUEUE]
const B_BANDS := "lugares.torno.franjas_colarse"
const B_RADIUS := "lugares.torno.radio_colarse_celdas"
const B_INTENT := "lugares.torno.segundos_intencion"
const B_PASS := "lugares.torno.segundos_paso"
const B_BEFORE := "lugares.torno.celdas_antes"
const B_BEYOND := "lugares.torno.celdas_mas_alla"
const B_OPEN := "mundo.puertas.apertura_s"
const LOCK_OWNER := "places_tailgate"
const HINT_KEY := "gate_hint"
const SFX_DENIED := "card_denied"
const ANIM_CLOCK := "clock_in"
const ANIM_SNEAK := "sneak"
const GAIT_SNEAK := "sneak"
const HALF := 0.5


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if item.interact_type == T_QUEUE:
		await slip_in(player, ctx)
		return
	swipe(item, player, ctx)


static func is_available(item: Interactable) -> bool:
	return item.interact_type != T_QUEUE or rush_now()


# ─── Fichar ───────────────────────────────────────────────────

## E ante una compuerta: tarjeta a mano (conserva el apaño de _default.gd).
static func swipe(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var game: GameRoot = PlacesKit.root(ctx)
	var gate: Door = game.streamer.get_door_by_id(item.interact_id) if game != null and game.streamer != null else null
	if game == null or gate == null or game.doors == null:
		PlacesKit.say(ctx, "INTERACT_NOTHING_USEFUL")
		return
	if not game.doors.swipe(gate):
		PlacesKit.sfx(item, SFX_DENIED, gate.global_position)
		PlacesKit.say(ctx, "WORLD_TURNSTILE_DENIED", [gate.clearance], ToastStack.KIND_WARN, "")
		return
	PlacesKit.play(player, ANIM_CLOCK)
	PlacesKit.good(ctx, "INTERACT_TURNSTILE_OPEN")
	if rush_now() and not PlacesKit.used_today(HINT_KEY) and not cover_npc(game, gate).is_empty():
		PlacesKit.mark_today(HINT_KEY)
		PlacesKit.say(ctx, "PLACES_GATE_HINT")


# ─── Colarse ──────────────────────────────────────────────────

## Hora punta de los tornos (lugares.torno.franjas_colarse).
static func rush_now() -> bool:
	return PlacesKit.bal_strings(B_BANDS).has(GameClock.get_current_band())


## Compañero más cercano al torno dentro de lugares.torno.radio_colarse_celdas ("" si nadie).
static func cover_npc(game: GameRoot, gate: Door) -> String:
	if game == null or game.npc_layer == null or gate == null:
		return ""
	var centre: Vector2 = gate.to_global(gate.gap_rect().get_center())
	var best: String = ""
	var best_d: float = Database.get_balance_float(B_RADIUS) * RoomBuilder.cell_px()
	for node: NPCNode in game.npc_layer.get_nodes():
		var d: float = node.global_position.distance_to(centre)
		if d <= best_d and NPCDirector.is_active(node.npc_id):
			best_d = d
			best = node.npc_id
	return best


## El torno con un compañero cerca más próximo al jugador (null si ninguno).
static func tailgate_gate(game: GameRoot, player: Node2D) -> Door:
	var best: Door = null
	var best_d: float = INF
	for door: Door in game.streamer.get_doors():
		if door.kind != Door.KIND_TURNSTILE or cover_npc(game, door).is_empty():
			continue
		var d: float = door.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = door
	return best


## Desde la cola: colarse detrás de alguien por el torno más cercano con cobertura.
static func slip_in(player: Node, ctx: Dictionary) -> void:
	var game: GameRoot = PlacesKit.root(ctx)
	var keeper: PlacesKeeper = PlacesKeeper.ensure(PlacesKit.tree_of(player))
	if game == null or keeper == null or not player is Node2D:
		return
	if not rush_now():
		PlacesKit.refuse(ctx, "PLACES_GATE_NO_RUSH")
		return
	var gate: Door = tailgate_gate(game, player as Node2D)
	if gate == null:
		PlacesKit.refuse(ctx, "PLACES_GATE_NOBODY")
		return
	var cover: String = cover_npc(game, gate)
	keeper.allow_tailgate(gate.door_id, Database.get_balance_float(B_INTENT))
	await walk_through(player as Node2D, gate)
	PlacesKit.good(ctx, "PLACES_GATE_SLIPPED", [PlacesKit.npc_name(cover)])


## Segundos de un tramo del paso guiado, al paso sigiloso del jugador (o la mitad de
## lugares.torno.segundos_paso si no se conoce su velocidad).
static func leg_seconds(player: Node2D, from: Vector2, to: Vector2) -> float:
	var speed: float = float(player.call("get_mode_speed", GAIT_SNEAK)) if player.has_method("get_mode_speed") else 0.0
	if speed <= 0.0:
		return Database.get_balance_float(B_PASS) * HALF
	return from.distance_to(to) / speed


## Paso guiado a través del torno (antes del hueco → más allá del sensor), entrada bloqueada.
static func walk_through(player: Node2D, gate: Door) -> void:
	var centre: Vector2 = gate.gap_rect().get_center()
	var normal: Vector2 = Vector2(1.0, 0.0) if gate.vertical else Vector2(0.0, 1.0)
	var side: float = signf(DoorAccess.across(gate, player.global_position))
	side = side if side != 0.0 else -1.0
	var cell: float = RoomBuilder.cell_px()
	var before: Vector2 = gate.to_global(centre + normal * side * cell * Database.get_balance_float(B_BEFORE))
	var after: Vector2 = gate.to_global(centre - normal * side * cell * Database.get_balance_float(B_BEYOND))
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", true, LOCK_OWNER)
	PlacesKit.play(player, ANIM_SNEAK)
	var tween: Tween = player.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(player, "global_position", before, leg_seconds(player, player.global_position, before))
	tween.tween_callback(func() -> void: gate.open_for(Database.get_balance_float(B_OPEN)))
	tween.tween_property(player, "global_position", after, leg_seconds(player, before, after))
	await tween.finished
	PlacesKit.play(player, "")
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", false, LOCK_OWNER)
