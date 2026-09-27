# caught_handler.gd — Flagrancia (§12.2): ralentiza el reloj, abre la ventana de decisión y resuelve la elección.
# PROPIETARIO DE: la ventana de flagrancia abierta, la cola de flagrancias pendientes y su RNG.
# ESCUCHA: player_caught_redhanded, day_advanced.
class_name CaughtHandler
extends Node

## Nodo que el World añade a la escena de juego. La interfaz (src/ui/caught_window.gd) escucha
## decision_window_opened / _updated / _closed y llama a choose_bribe() o choose_elimination().
## options = {npc_id, npc_name, crime_type, witnesses, seconds_left,
##   "bribe":     {enabled, price, favour, channel, counteroffer, label_key, disabled_reason_key},
##   "eliminate": {enabled, flagged_red, label_key, disabled_reason_key}}
## Con testigos la eliminación llega deshabilitada y marcada en rojo, y choose_elimination()
## la rechaza también en lógica: no se puede perder la partida por un error de interfaz.
## Sin elección en flagrancia.plazo_decision_segundos, el personaje reacciona según el
## caught_reaction de su arquetipo (apply_caught_reaction). Una flagrancia que llega con la
## ventana abierta espera en cola.
## Dependencias sustituibles (herramientas y pruebas): npc_resolver (id → NPCRuntime, por
## defecto NPCDirector.get_npc), wallet (can_afford/spend_money, por defecto PlayerState),
## population_source (→ Array[NPCRuntime], por defecto NPCDirector.get_all_npcs).

signal decision_window_opened(npc_id: String, options: Dictionary)
signal decision_window_updated(npc_id: String, options: Dictionary)
signal decision_window_closed(npc_id: String, outcome: String)

const OPTION_BRIBE := "bribe"
const OPTION_ELIMINATE := "eliminate"
const OUTCOME_INACTION := "inaction"
const OUTCOME_ELIMINATED := "eliminated"
const REASON_NO_WINDOW := "no_window"
const REASON_WITNESSES := "witnesses"
const REMOVAL_CAUSE := "eliminated"
const CRIME_ELIMINATION := "elimination"
const NEUTRAL_SPEED := 1.0

const REACTION_SECURITY := "report_to_security"
const REACTION_SUPERIOR := "report_to_superior"
const REACTION_GOSSIP := "spread_at_lunch"
const REACTION_SILENT_BLACKMAIL := "silent_blackmail"
const REACTION_INDIFFERENT := "indifferent"
const REACTION_REMEMBERS := "remembers_quietly"
const REACTION_LEVERAGE := "use_as_leverage"
const REACTION_ASK_MONEY := "ask_for_money"
const ACTION_REPORT_SECURITY := "report_to_security"
const ACTION_REPORT_SUPERIOR := "report_to_superior"
const ACTION_GOSSIP := "gossip"
const ACTION_STAY_SILENT := "stay_silent"
const ACTION_IGNORE := "ignore"
const ACTION_REMEMBER := "remember"
const ACTION_KEEP_LEVERAGE := "keep_leverage"
const ACTION_ASK_MONEY := "blackmail_player"
const REPORT_SECURITY := "security"
const REPORT_SUPERIOR := "superior"

const LABEL_BRIBE := "UI_CAUGHT_BRIBE"
const LABEL_COUNTEROFFER := "UI_CAUGHT_BRIBE_COUNTEROFFER"
const LABEL_NO_FUNDS := "UI_CAUGHT_BRIBE_NO_FUNDS"
const LABEL_ELIMINATE := "UI_CAUGHT_ELIMINATE"
const LABEL_WITNESSES := "UI_CAUGHT_ELIMINATE_WITNESSES"

var npc_resolver: Callable = Callable()
var wallet: Object = null
var population_source: Callable = Callable()

var _window: Dictionary = {}
var _queue: Array[Dictionary] = []
var _time_slowed: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.player_caught_redhanded.connect(_on_player_caught_redhanded)
	EventBus.day_advanced.connect(_on_day_advanced)
	_rng.seed = _seed()


func _process(delta: float) -> void:
	if is_window_open():
		advance_timer(delta)


# ─── Ciclo de partida ──────────────────────────────────────────

func reset_for_new_run() -> void:
	_queue.clear()
	_window = {}
	_restore_time()
	_rng.seed = _seed()


func save_state() -> Dictionary:
	return {"window": _window.duplicate(true), "queue": _queue.duplicate(true),
			"rng_state": str(_rng.state)}


func load_state(data: Dictionary) -> void:
	reset_for_new_run()
	_queue.assign(data.get("queue", []))
	var saved_state: String = str(data.get("rng_state", ""))
	if saved_state.is_valid_int():
		_rng.state = saved_state.to_int()
	var window: Dictionary = data.get("window", {})
	if not window.is_empty():
		_window = window.duplicate(true)
		_slow_time()
		decision_window_opened.emit(str(_window["npc_id"]), get_options())


# ─── Consulta ──────────────────────────────────────────────────

func is_window_open() -> bool:
	return not _window.is_empty()


func is_time_slowed() -> bool:
	return _time_slowed


func get_queue_size() -> int:
	return _queue.size()


func get_options() -> Dictionary:
	if not is_window_open():
		return {}
	var npc: NPCRuntime = _resolve(str(_window["npc_id"]))
	var witnesses: int = int(_window["witnesses"])
	var price: int = _bribe_price(npc)
	var affordable: bool = bool(_wallet().call("can_afford", price))
	var countered: bool = int(_window.get("asked_price", 0)) > 0
	return {
		"npc_id": str(_window["npc_id"]), "npc_name": npc.name if npc != null else "",
		"crime_type": str(_window["crime_type"]), "witnesses": witnesses,
		"seconds_left": float(_window["remaining"]),
		OPTION_BRIBE: {"enabled": affordable and npc != null, "price": price,
				"favour": Bribery.FAVOUR_SILENCE, "channel": Bribery.CHANNEL_IMMEDIATE,
				"counteroffer": countered, "label_key": LABEL_COUNTEROFFER if countered else LABEL_BRIBE,
				"disabled_reason_key": "" if affordable else LABEL_NO_FUNDS},
		OPTION_ELIMINATE: {"enabled": witnesses == 0, "flagged_red": witnesses > 0,
				"label_key": LABEL_ELIMINATE,
				"disabled_reason_key": "" if witnesses == 0 else LABEL_WITNESSES},
	}


# ─── Opciones ──────────────────────────────────────────────────

## Opción 1: soborno inmediato (favor silence_witnessed, ×20). amount < 0 = el precio pedido.
## extra_ctx se pasa a Bribery.offer (p. ej. tiradas fijas). Contraoferta: la ventana sigue
## abierta con el nuevo precio y el plazo reiniciado.
func choose_bribe(amount: int = -1, extra_ctx: Dictionary = {}) -> Dictionary:
	if not is_window_open():
		return {"ok": false, "outcome": Bribery.OUTCOME_INVALID, "reason": REASON_NO_WINDOW}
	var bribe: Dictionary = get_options()[OPTION_BRIBE]
	if not bool(bribe["enabled"]):
		return {"ok": false, "outcome": Bribery.OUTCOME_NO_FUNDS,
				"text_key": Bribery.OUTCOME_TEXT_KEYS[Bribery.OUTCOME_NO_FUNDS]}
	var npc: NPCRuntime = _resolve(str(_window["npc_id"]))
	var ctx: Dictionary = {"wallet": _wallet(), "crime_type": _window["crime_type"],
			"room_id": _window["room_id"], "asked_price": int(_window.get("asked_price", 0))}
	ctx.merge(extra_ctx, true)
	var offered: int = int(bribe["price"]) if amount < 0 else amount
	var result: Dictionary = Bribery.offer(npc, offered, Bribery.FAVOUR_SILENCE,
			Bribery.CHANNEL_IMMEDIATE, ctx)
	_after_bribe(result)
	return result


## Opción 2: eliminación. Solo sin testigos; con testigos no hace nada y devuelve ok = false.
func choose_elimination() -> Dictionary:
	if not is_window_open():
		return {"ok": false, "reason": REASON_NO_WINDOW}
	if int(_window["witnesses"]) > 0:
		return {"ok": false, "reason": REASON_WITNESSES}
	var npc_id: String = str(_window["npc_id"])
	var room_id: String = str(_window["room_id"])
	NPCDirector.remove_npc(npc_id, REMOVAL_CAUSE)
	EventBus.crime_committed.emit(CRIME_ELIMINATION, room_id,
			{"npc_id": npc_id, "witnesses": 0, "interrupted_crime": _window["crime_type"]})
	_close(OUTCOME_ELIMINATED)
	return {"ok": true, "npc_id": npc_id, "room_id": room_id}


## Descuenta tiempo real de la ventana; al agotarse el plazo reacciona el personaje.
func advance_timer(seconds: float) -> void:
	if not is_window_open():
		return
	_window["remaining"] = float(_window["remaining"]) - seconds
	if float(_window["remaining"]) <= 0.0:
		resolve_inaction()


## La tercera consecuencia: sin elección, el personaje actúa según su arquetipo.
## roll < 0 = tirada del RNG propio (semilla de partida).
func resolve_inaction(roll: float = -1.0) -> Dictionary:
	if not is_window_open():
		return {}
	var npc: NPCRuntime = _resolve(str(_window["npc_id"]))
	var used_roll: float = roll if roll >= 0.0 else _rng.randf()
	var reaction: Dictionary = {}
	if npc != null:
		reaction = apply_caught_reaction(npc, str(_window["crime_type"]), str(_window["room_id"]),
				used_roll)
	_close(OUTCOME_INACTION)
	return reaction


# ─── Reacción por arquetipo (§12.2, inacción) ──────────────────

static func archetype_reaction(archetype_id: String) -> String:
	var archetype: ArchetypeData = Database.get_archetype(archetype_id)
	return archetype.caught_reaction if archetype != null else REACTION_REMEMBERS


## Aplica el caught_reaction del arquetipo del personaje. Devuelve el contexto de la decisión
## ({npc_id, action, reaction, reported, report_type, weight, blackmail, ...}); siempre emite
## npc_decided y, si denuncia, npc_reported_player (el peso es la subida de sospecha).
static func apply_caught_reaction(npc: NPCRuntime, crime_type: String, location: String,
		roll: float) -> Dictionary:
	var reaction: String = archetype_reaction(npc.archetype)
	if reaction == REACTION_INDIFFERENT:
		if roll < Bribery.tunable("flagrancia.prob_indiferencia"):
			return _decide(npc, reaction, ACTION_IGNORE, crime_type, location, {"indifferent": true})
		reaction = REACTION_REMEMBERS
	match reaction:
		REACTION_SECURITY:
			return _report(npc, reaction, REPORT_SECURITY, "flagrancia.peso_denuncia_seguridad",
					crime_type, location)
		REACTION_SUPERIOR:
			return _report(npc, reaction, REPORT_SUPERIOR, "flagrancia.peso_denuncia_superior",
					crime_type, location)
		REACTION_GOSSIP:
			return _decide(npc, reaction, ACTION_GOSSIP, crime_type, location, {"amplified": true,
					"amplification": Bribery.tunable("creencias.amplificacion_rumor_max"),
					"belief_id": _latest_belief_about_player(npc.id)})
		REACTION_SILENT_BLACKMAIL:
			return _keep_material(npc, reaction, ACTION_STAY_SILENT, Blackmail.KIND_WITNESSED, "",
					crime_type, location)
		REACTION_LEVERAGE:
			return _keep_material(npc, reaction, ACTION_KEEP_LEVERAGE, Blackmail.KIND_LEVERAGE,
					Blackmail.DEMAND_PROMOTION, crime_type, location)
		REACTION_ASK_MONEY:
			return _ask_for_money(npc, crime_type, location)
	return _decide(npc, REACTION_REMEMBERS, ACTION_REMEMBER, crime_type, location, {})


static func _decide(npc: NPCRuntime, reaction: String, action: String, crime_type: String,
		location: String, extra: Dictionary) -> Dictionary:
	var context: Dictionary = {"reaction": reaction, "crime_type": crime_type,
			"location": location, "subject": Bribery.PLAYER_ID, "reported": false,
			"blackmail": false, "indifferent": false}
	context.merge(extra, true)
	EventBus.npc_decided.emit(npc.id, action, context)
	var out: Dictionary = context.duplicate(true)
	out["npc_id"] = npc.id
	out["action"] = action
	return out


static func _report(npc: NPCRuntime, reaction: String, report_type: String, weight_key: String,
		crime_type: String, location: String) -> Dictionary:
	var weight: float = Bribery.tunable(weight_key)
	var action: String = ACTION_REPORT_SECURITY if report_type == REPORT_SECURITY \
			else ACTION_REPORT_SUPERIOR
	var out: Dictionary = _decide(npc, reaction, action, crime_type, location, {"reported": true,
			"report_type": report_type, "weight": weight,
			"file_annotation": report_type == REPORT_SUPERIOR})
	EventBus.npc_reported_player.emit(npc.id, report_type, weight, location)
	return out


static func _keep_material(npc: NPCRuntime, reaction: String, action: String, kind: String,
		demand_type: String, crime_type: String, location: String) -> Dictionary:
	var entry: Dictionary = Blackmail.add_material(npc, kind, crime_type, GameClock.get_day(),
			demand_type)
	return _decide(npc, reaction, action, crime_type, location, {"blackmail": true,
			"demand_day": entry["demand_day"], "will_demand": entry["will_demand"]})


static func _ask_for_money(npc: NPCRuntime, crime_type: String, location: String) -> Dictionary:
	var day: int = GameClock.get_day()
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_ASKED_MONEY, crime_type, day,
			Blackmail.DEMAND_MONEY, 0)
	var out: Dictionary = _decide(npc, REACTION_ASK_MONEY, ACTION_ASK_MONEY, crime_type, location,
			{"blackmail": true, "demand_type": Blackmail.DEMAND_MONEY})
	var demand: Dictionary = Blackmail.issue_demand(npc, entry, day)
	out["amount"] = demand["amount"]
	return out


static func _latest_belief_about_player(npc_id: String) -> String:
	var best_id: String = ""
	var best_day: int = -1
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject == Bribery.PLAYER_ID and belief.timestamp >= best_day:
			best_id = belief.id
			best_day = belief.timestamp
	return best_id


# ─── Interno ───────────────────────────────────────────────────

func _on_player_caught_redhanded(npc_id: String, crime_type: String, witnesses: int) -> void:
	var caught: Dictionary = {"npc_id": npc_id, "crime_type": crime_type, "witnesses": witnesses}
	if is_window_open():
		if str(_window["npc_id"]) != npc_id and not _is_queued(npc_id):
			_queue.append(caught)
		return
	_open(caught)


func _on_day_advanced(day_number: int) -> void:
	var population: Array[NPCRuntime] = []
	if population_source.is_valid():
		population.assign(population_source.call())
	Blackmail.process_day(day_number, population)


func _open(caught: Dictionary) -> bool:
	var npc: NPCRuntime = _resolve(str(caught["npc_id"]))
	if npc == null or not npc.alive:
		return false
	_window = caught.duplicate(true)
	_window["remaining"] = Bribery.tunable("flagrancia.plazo_decision_segundos")
	_window["asked_price"] = 0
	_window["room_id"] = _room_of(npc)
	_slow_time()
	decision_window_opened.emit(npc.id, get_options())
	return true


func _after_bribe(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	var outcome: String = str(result["outcome"])
	if outcome == Bribery.OUTCOME_COUNTEROFFER:
		_window["asked_price"] = int(result["asked_price"])
		_window["remaining"] = Bribery.tunable("flagrancia.plazo_decision_segundos")
		decision_window_updated.emit(str(_window["npc_id"]), get_options())
		return
	if outcome == Bribery.OUTCOME_DENOUNCED:
		_queue.clear()
	_close(outcome)


func _close(outcome: String) -> void:
	var npc_id: String = str(_window.get("npc_id", ""))
	_window = {}
	_restore_time()
	decision_window_closed.emit(npc_id, outcome)
	while not _queue.is_empty() and not is_window_open():
		_open(_queue.pop_front())


func _bribe_price(npc: NPCRuntime) -> int:
	var asked: int = int(_window.get("asked_price", 0))
	if asked > 0 or npc == null:
		return asked
	return Bribery.fair_price(npc, Bribery.FAVOUR_SILENCE)


func _is_queued(npc_id: String) -> bool:
	for caught: Dictionary in _queue:
		if str(caught["npc_id"]) == npc_id:
			return true
	return false


func _slow_time() -> void:
	GameClock.set_speed_multiplier(Bribery.tunable("flagrancia.multiplicador_tiempo"))
	_time_slowed = true


func _restore_time() -> void:
	if _time_slowed:
		GameClock.set_speed_multiplier(NEUTRAL_SPEED)
	_time_slowed = false


func _resolve(npc_id: String) -> NPCRuntime:
	if npc_resolver.is_valid():
		return npc_resolver.call(npc_id) as NPCRuntime
	return NPCDirector.get_npc(npc_id)


func _wallet() -> Object:
	return wallet if wallet != null else PlayerState


func _room_of(npc: NPCRuntime) -> String:
	var location: String = NPCDirector.get_current_location(npc.id)
	return location if not location.is_empty() else npc.current_room


func _seed() -> int:
	return hash([GameClock.get_run_seed(), get_script().get_global_name()])
