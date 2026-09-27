# caught_handler.gd — Flagrancia (§12.2): ralentiza el reloj, abre la ventana de decisión, resuelve la elección y la reacción por arquetipo.
# PROPIETARIO DE: la ventana de flagrancia abierta, la cola de flagrancias pendientes, los cotilleos de flagrancia que esperan a la comida y su RNG.
# ESCUCHA: player_caught_redhanded, day_advanced, time_band_changed, npc_removed, bribe_result, game_over, run_started.
class_name CaughtHandler
extends Node

## Nodo que el World añade a la escena de juego. La interfaz (src/ui/caught_window.gd) escucha
## decision_window_opened / _updated / _closed y llama a choose_bribe() o choose_elimination().
## options = {npc_id, npc_name, crime_type, witnesses, seconds_left, deadline,
##   "bribe":     {enabled, price, favour, channel, counteroffer, label_key, disabled_reason_key},
##   "eliminate": {enabled, flagged_red, label_key, disabled_reason_key}}
## DECISIONES (contrato para el resto de sistemas):
##  · Con testigos la eliminación llega deshabilitada y marcada en rojo, y choose_elimination()
##    la rechaza también en lógica. Testigos = el número de player_caught_redhanded, o los ids
##    que Perception entregue con set_witness_ids() (entonces solo cuentan los que siguen vivos).
##  · Soborno inmediato = Bribery.offer(canal "immediate", favor silence_witnessed ×20) por el
##    precio de la ventana (el justo o el de la contraoferta); ofrecer menos se rechaza sin
##    efectos. Aceptado → no denuncia, conserva la creencia y gana material de chantaje;
##    denuncia → game over; silencio → creencia 0,9 + material; contraoferta → la ventana sigue
##    con el nuevo precio (el plazo NO se reinicia: como mínimo
##    flagrancia.plazo_minimo_contraoferta_segundos para responder); rechazo neutro → el
##    personaje reacciona según su arquetipo en el acto (no compra nada).
##  · Plazo = flagrancia.plazo_decision_segundos × (1 + plazo_extra_por_reputacion × reputación/100)
##    (§7.10: con reputación alta el testigo duda más antes de actuar).
##  · Inacción (§12.2) = caught_reaction del arquetipo (archetypes.json). Las denuncias (Seguridad
##    +20, superior +10, en puntos de sospecha que BeliefNet escala por la credibilidad del
##    denunciante, §7.2) se retiran si la deuda lo impide (§7.7: NPCDirector.is_report_suppressed;
##    consume registro.deuda_consumida_por_silencio) o si el testigo duda (§7.5/§7.9: rango del
##    jugador, temor y afecto del registro, atenuado por su valentía; hesitation_chance()).
##  · Cotilla: marca la creencia de la flagrancia; en la franja flagrancia.franja_cotilleo
##    (la comida; en el acto si ya es esa franja) la cuenta a TODOS sus vínculos
##    (SocialGraph.get_neighbours) con BeliefNet.transfer_belief(factor del vínculo ×
##    flagrancia.amplificacion_cotilla). Se cancela si el cotilla acepta un soborno o sale de
##    la plantilla. Se guarda con save_state().
##  · game_over cierra la ventana sin reacción y vacía la cola; npc_removed del testigo abierto
##    la cierra sin reacción ("void"); el reloj vuelve a su ritmo previo solo si nadie lo cambió.
## Dependencias sustituibles (herramientas y pruebas): npc_resolver (id → NPCRuntime; si no está
## o devuelve null, NPCDirector.get_npc), wallet (Bribery.Wallet, por defecto PlayerState),
## population_source (→ Array[NPCRuntime], por defecto NPCDirector.get_all_npcs) y roll_source
## (→ float en [0, 1), por defecto el RNG propio sembrado con la semilla de partida).

signal decision_window_opened(npc_id: String, options: Dictionary)
signal decision_window_updated(npc_id: String, options: Dictionary)
signal decision_window_closed(npc_id: String, outcome: String)

const PLAYER_ID := "player"
const OPTION_BRIBE := "bribe"
const OPTION_ELIMINATE := "eliminate"
const OUTCOME_INACTION := "inaction"
const OUTCOME_ELIMINATED := "eliminated"
const OUTCOME_GAME_OVER := "game_over"
const OUTCOME_VOID := "void"
const REASON_NO_WINDOW := "no_window"
const REASON_WITNESSES := "witnesses"
const REASON_BELOW_PRICE := "below_price"
const REMOVAL_CAUSE := "eliminated"
const CRIME_ELIMINATION := "elimination"
const SUPPRESSED_BY_DEBT := "debt"

const REACTION_SECURITY := "report_to_security"
const REACTION_SUPERIOR := "report_to_superior"
const REACTION_GOSSIP := "spread_at_lunch"
const REACTION_SILENT_BLACKMAIL := "silent_blackmail"
const REACTION_INDIFFERENT := "indifferent"
const REACTION_REMEMBERS := "remembers_quietly"
const REACTION_LEVERAGE := "use_as_leverage"
const REACTION_ASK_MONEY := "ask_for_money"
const REACTION_DEBT_SILENCE := "silenced_by_debt"
const REACTION_HESITATED := "hesitated"
const REPORT_REACTIONS: Array[String] = [REACTION_SECURITY, REACTION_SUPERIOR]
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

## Claves de la ventana, de la cola y de los cotilleos pendientes (también en save_state).
const W_NPC := "npc_id"
const W_CRIME := "crime_type"
const W_WITNESSES := "witnesses"
const W_WITNESS_IDS := "witness_ids"
const W_ROOM := "room_id"
const W_REMAINING := "remaining"
const W_DEADLINE := "deadline"
const W_COUNTER := "counteroffer"
const G_NPC := "npc_id"
const G_BELIEF := "belief_id"
const G_DAY := "day"
## Ritmo neutro de GameClock (valor de referencia, no un ajuste).
const NEUTRAL_SPEED := 1.0

const B_DEADLINE := "flagrancia.plazo_decision_segundos"
const B_DEADLINE_REPUTATION := "flagrancia.plazo_extra_por_reputacion"
const B_COUNTER_SECONDS := "flagrancia.plazo_minimo_contraoferta_segundos"
const B_SLOW := "flagrancia.multiplicador_tiempo"
const B_INDIFFERENCE := "flagrancia.prob_indiferencia"
const B_WEIGHT_SECURITY := "flagrancia.peso_denuncia_seguridad"
const B_WEIGHT_SUPERIOR := "flagrancia.peso_denuncia_superior"
const B_DOUBT_RANK := "flagrancia.duda_por_rango"
const B_DOUBT_FEAR := "flagrancia.duda_por_temor"
const B_DOUBT_AFFECTION := "flagrancia.duda_por_afecto"
const B_DOUBT_MAX := "flagrancia.duda_maxima"
const B_GOSSIP_BAND := "flagrancia.franja_cotilleo"
const B_GOSSIP_BOOST := "flagrancia.amplificacion_cotilla"
const B_DEBT_SILENCE := "registro.deuda_consumida_por_silencio"
const B_START_OCCUPATION := "jugador.ocupacion_inicial"
const PERCENT := 100.0

var npc_resolver: Callable = Callable()
var wallet: Bribery.Wallet = null
var population_source: Callable = Callable()
var roll_source: Callable = Callable()

var _window: Dictionary = {}
var _queue: Array[Dictionary] = []
var _pending_gossip: Array[Dictionary] = []
var _time_slowed: bool = false
var _speed_before: float = NEUTRAL_SPEED
var _busy: bool = false
var _game_over: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	EventBus.player_caught_redhanded.connect(_on_player_caught_redhanded)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.time_band_changed.connect(_on_time_band_changed)
	EventBus.npc_removed.connect(_on_npc_removed)
	EventBus.bribe_result.connect(_on_bribe_result)
	EventBus.game_over.connect(_on_game_over)
	EventBus.run_started.connect(_on_run_started)
	_rng.seed = _seed()


func _process(delta: float) -> void:
	if is_window_open():
		advance_timer(delta)


# ─── Ciclo de partida ──────────────────────────────────────────

func reset_for_new_run() -> void:
	_restore_time()
	_window = {}
	_queue.clear()
	_pending_gossip.clear()
	_speed_before = NEUTRAL_SPEED
	_busy = false
	_game_over = false
	_rng.seed = _seed()


func save_state() -> Dictionary:
	return {"window": _window.duplicate(true), "queue": _queue.duplicate(true),
			"pending_gossip": _pending_gossip.duplicate(true), "rng_state": str(_rng.state)}


func load_state(data: Dictionary) -> void:
	reset_for_new_run()
	_queue.assign(_dict_list(data.get("queue", [])))
	_pending_gossip.assign(_dict_list(data.get("pending_gossip", [])))
	var saved_state: String = str(data.get("rng_state", ""))
	if saved_state.is_valid_int():
		_rng.state = saved_state.to_int()
	var raw: Variant = data.get("window", {})
	if raw is Dictionary and (raw as Dictionary).has(W_NPC) \
			and _is_present(_resolve(str(raw[W_NPC]))):
		_window = _restored_window(raw)
		_slow_time()
		decision_window_opened.emit(str(_window[W_NPC]), get_options())


# ─── Consulta ──────────────────────────────────────────────────

func is_window_open() -> bool:
	return not _window.is_empty()


func is_time_slowed() -> bool:
	return _time_slowed


func get_queue_size() -> int:
	return _queue.size()


## Cotilleos de flagrancia que esperan a la franja de la comida (copias).
func get_pending_gossip() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _pending_gossip:
		out.append(entry.duplicate())
	return out


func get_options() -> Dictionary:
	if not is_window_open():
		return {}
	var npc: NPCRuntime = _resolve(str(_window[W_NPC]))
	var witnesses: int = _witness_count(_window)
	var price: int = _bribe_price(npc)
	var affordable: bool = npc != null and price > 0 and _wallet().can_afford(price)
	var countered: bool = not (_window.get(W_COUNTER, {}) as Dictionary).is_empty()
	return {
		"npc_id": str(_window[W_NPC]), "npc_name": npc.name if npc != null else "",
		"crime_type": str(_window[W_CRIME]), "witnesses": witnesses,
		"seconds_left": float(_window[W_REMAINING]), "deadline": float(_window[W_DEADLINE]),
		OPTION_BRIBE: {"enabled": affordable, "price": price,
				"favour": Bribery.FAVOUR_SILENCE, "channel": Bribery.CHANNEL_IMMEDIATE,
				"counteroffer": countered,
				"label_key": LABEL_COUNTEROFFER if countered else LABEL_BRIBE,
				"disabled_reason_key": "" if affordable else LABEL_NO_FUNDS},
		OPTION_ELIMINATE: {"enabled": witnesses == 0, "flagged_red": witnesses > 0,
				"label_key": LABEL_ELIMINATE,
				"disabled_reason_key": "" if witnesses == 0 else LABEL_WITNESSES},
	}


## §7.10: segundos de la ventana según la reputación del jugador (0–100).
static func decision_seconds(reputation: float) -> float:
	return Bribery.tunable(B_DEADLINE) * (1.0 + Bribery.tunable(B_DEADLINE_REPUTATION)
			* clampf(reputation, 0.0, PERCENT) / PERCENT)


# ─── Opciones ──────────────────────────────────────────────────

## Opción 1: soborno inmediato (favor silence_witnessed, ×20). amount < 0 = el precio de la
## ventana; menos que ese precio no se admite (ok = false, sin efectos). extra_ctx se pasa a
## Bribery.offer (p. ej. tiradas fijas).
func choose_bribe(amount: int = -1, extra_ctx: Dictionary = {}) -> Dictionary:
	if not is_window_open():
		return {"ok": false, "outcome": Bribery.OUTCOME_INVALID, "reason": REASON_NO_WINDOW}
	var bribe: Dictionary = get_options()[OPTION_BRIBE]
	if not bool(bribe["enabled"]):
		return {"ok": false, "outcome": Bribery.OUTCOME_NO_FUNDS,
				"text_key": Bribery.OUTCOME_TEXT_KEYS[Bribery.OUTCOME_NO_FUNDS]}
	var offered: int = int(bribe["price"]) if amount < 0 else amount
	if offered < int(bribe["price"]):
		return {"ok": false, "outcome": Bribery.OUTCOME_INVALID, "reason": REASON_BELOW_PRICE,
				"text_key": Bribery.OUTCOME_TEXT_KEYS[Bribery.OUTCOME_INVALID]}
	var npc: NPCRuntime = _resolve(str(_window[W_NPC]))
	_busy = true
	var result: Dictionary = Bribery.offer(npc, offered, Bribery.FAVOUR_SILENCE,
			Bribery.CHANNEL_IMMEDIATE, _bribe_ctx(extra_ctx))
	_busy = false
	_after_bribe(npc, result)
	return result


## Opción 2: eliminación. Solo sin testigos; con testigos no hace nada y devuelve ok = false.
func choose_elimination() -> Dictionary:
	if not is_window_open():
		return {"ok": false, "reason": REASON_NO_WINDOW}
	if _witness_count(_window) > 0:
		return {"ok": false, "reason": REASON_WITNESSES}
	var npc_id: String = str(_window[W_NPC])
	var room_id: String = str(_window[W_ROOM])
	_busy = true
	NPCDirector.remove_npc(npc_id, REMOVAL_CAUSE)
	_busy = false
	EventBus.crime_committed.emit(CRIME_ELIMINATION, room_id,
			{"npc_id": npc_id, "witnesses": 0, "interrupted_crime": _window[W_CRIME]})
	_close(OUTCOME_ELIMINATED)
	return {"ok": true, "npc_id": npc_id, "room_id": room_id}


## Descuenta tiempo real de la ventana; al agotarse el plazo reacciona el personaje.
func advance_timer(seconds: float) -> void:
	if not is_window_open():
		return
	_window[W_REMAINING] = float(_window[W_REMAINING]) - seconds
	if float(_window[W_REMAINING]) <= 0.0:
		resolve_inaction()


## Perception puede entregar quiénes más lo vieron: solo cuentan los que sigan vivos.
func set_witness_ids(npc_id: String, witness_ids: Array[String]) -> void:
	var entry: Dictionary = _entry_for(npc_id)
	if entry.is_empty():
		return
	entry[W_WITNESS_IDS] = witness_ids.duplicate()
	entry[W_WITNESSES] = witness_ids.size()
	if is_same(entry, _window):
		decision_window_updated.emit(npc_id, get_options())


## Tick diario del chantaje (lo dispara day_advanced): exigencias que vencen y plazos agotados.
func process_blackmail_day(day_number: int) -> Array[Dictionary]:
	var population: Array[NPCRuntime] = []
	if population_source.is_valid():
		population.assign(population_source.call())
	return Blackmail.process_day(day_number, population)


## La tercera consecuencia: sin elección, el personaje actúa según su arquetipo.
## roll < 0 = tirada propia (roll_source o RNG de partida). Un testigo que ya no está (retirado)
## cierra la ventana sin reacción.
func resolve_inaction(roll: float = -1.0) -> Dictionary:
	if not is_window_open():
		return {}
	var npc: NPCRuntime = _resolve(str(_window[W_NPC]))
	var reaction: Dictionary = {}
	if _is_present(npc):
		reaction = _react(npc, roll if roll >= 0.0 else _next_roll())
	_close(OUTCOME_VOID if reaction.is_empty() else OUTCOME_INACTION)
	return reaction


## Cuenta ya los cotilleos pendientes (lo dispara la franja de la comida). Devuelve a cuántos
## personajes ha llegado.
func process_gossip() -> int:
	var pending: Array[Dictionary] = _pending_gossip.duplicate()
	_pending_gossip.clear()
	var reached_total: int = 0
	for entry: Dictionary in pending:
		var npc: NPCRuntime = _resolve(str(entry[G_NPC]))
		if not _is_present(npc):
			continue
		var reached: Array[String] = spread_gossip(npc.id, str(entry[G_BELIEF]))
		reached_total += reached.size()
		EventBus.npc_decided.emit(npc.id, ACTION_GOSSIP, {"reaction": REACTION_GOSSIP,
				"subject": PLAYER_ID, "belief_id": entry[G_BELIEF], "amplified": true,
				"spread_to": reached})
	return reached_total


# ─── Reacción por arquetipo (§12.2, inacción) ──────────────────

static func archetype_reaction(archetype_id: String) -> String:
	var archetype: ArchetypeData = Database.get_archetype(archetype_id)
	return archetype.caught_reaction if archetype != null else REACTION_REMEMBERS


## Aplica el caught_reaction del arquetipo del personaje. Devuelve el contexto de la decisión
## ({npc_id, action, reaction, reported, report_type, weight, blackmail, ...}); siempre emite
## npc_decided y, si denuncia, npc_reported_player (weight = puntos de sospecha).
static func apply_caught_reaction(npc: NPCRuntime, crime_type: String, location: String,
		roll: float) -> Dictionary:
	var reaction: String = archetype_reaction(npc.archetype)
	if reaction == REACTION_INDIFFERENT:
		if roll < Bribery.tunable(B_INDIFFERENCE):
			return _decide(npc, reaction, ACTION_IGNORE, crime_type, location,
					{"indifferent": true})
		reaction = REACTION_REMEMBERS
	if REPORT_REACTIONS.has(reaction):
		var withheld: Dictionary = _withheld_report(npc, reaction, crime_type, location, roll)
		if not withheld.is_empty():
			return withheld
	match reaction:
		REACTION_SECURITY:
			return _report(npc, reaction, REPORT_SECURITY, B_WEIGHT_SECURITY, crime_type, location)
		REACTION_SUPERIOR:
			return _report(npc, reaction, REPORT_SUPERIOR, B_WEIGHT_SUPERIOR, crime_type, location)
		REACTION_GOSSIP:
			return _decide(npc, reaction, ACTION_GOSSIP, crime_type, location, {"amplified": true,
					"amplification": Bribery.tunable(B_GOSSIP_BOOST), "spread_band": gossip_band(),
					"belief_id": caught_belief_id(npc.id, crime_type)})
		REACTION_SILENT_BLACKMAIL:
			return _keep_material(npc, reaction, ACTION_STAY_SILENT, Blackmail.KIND_WITNESSED, "",
					crime_type, location)
		REACTION_LEVERAGE:
			return _keep_material(npc, reaction, ACTION_KEEP_LEVERAGE, Blackmail.KIND_LEVERAGE,
					Blackmail.DEMAND_PROMOTION, crime_type, location)
		REACTION_ASK_MONEY:
			return _ask_for_money(npc, crime_type, location)
	return _decide(npc, REACTION_REMEMBERS, ACTION_REMEMBER, crime_type, location, {})


## §7.7: deuda con el jugador (registro o arista de deuda) → no denuncia.
static func is_report_suppressed(npc: NPCRuntime) -> bool:
	if Bribery.is_managed(npc):
		return NPCDirector.is_report_suppressed(npc.id)
	return int(npc.ledger.get("debt", 0)) > 0


## Probabilidad de que un testigo que iba a denunciar calle: (duda_por_rango × rango relativo
## del jugador + duda_por_temor × temor/100 + duda_por_afecto × afecto/100) × (1 − valentía/100),
## acotada a [0, duda_maxima]. Nula para un jugador de rango inicial sin registro.
static func hesitation_chance(npc: NPCRuntime) -> float:
	var chance: float = Bribery.tunable(B_DOUBT_RANK) * _player_rank_share() \
			+ Bribery.tunable(B_DOUBT_FEAR) * float(npc.ledger.get("fear", 0)) / PERCENT \
			+ Bribery.tunable(B_DOUBT_AFFECTION) * float(npc.ledger.get("affection", 0)) / PERCENT
	chance *= 1.0 - float(npc.get_trait("courage")) / PERCENT
	return clampf(chance, 0.0, Bribery.tunable(B_DOUBT_MAX))


## Franja en la que el cotilla cuenta la flagrancia (flagrancia.franja_cotilleo).
static func gossip_band() -> String:
	return str(Database.get_balance(B_GOSSIP_BAND))


## La creencia de la flagrancia del personaje (caught_redhanded:<delito>); si no la tiene, su
## creencia más reciente sobre el jugador; "" si ninguna.
static func caught_belief_id(npc_id: String, crime_type: String) -> String:
	var fact: String = BeliefNetSystem.make_fact(BeliefNetSystem.FACT_CAUGHT_REDHANDED, crime_type)
	var exact: String = ""
	var latest: String = ""
	for belief: Belief in BeliefNet.get_beliefs_held_by(npc_id):
		if belief.subject != PLAYER_ID:
			continue
		latest = belief.id
		if belief.fact == fact:
			exact = belief.id
	return exact if not exact.is_empty() else latest


## Propagación amplificada (§12.2): el cotilla cuenta la creencia a todos sus vínculos que la
## transmiten, con factor del vínculo × flagrancia.amplificacion_cotilla (BeliefNet lo acota a
## creencias.amplificacion_rumor_max). Devuelve a quién ha llegado.
static func spread_gossip(npc_id: String, belief_id: String) -> Array[String]:
	var reached: Array[String] = []
	var belief: Belief = BeliefNet.get_belief(belief_id)
	if belief == null or belief.holder != npc_id:
		return reached
	var boost: float = Bribery.tunable(B_GOSSIP_BOOST)
	for neighbour: String in SocialGraph.get_neighbours(npc_id, 0.0):
		var factor: float = SocialGraph.get_transfer_factor(npc_id, neighbour, belief.fact,
				belief.subject)
		if factor <= 0.0:
			continue
		if not BeliefNet.transfer_belief(belief_id, neighbour, factor * boost).is_empty():
			reached.append(neighbour)
	return reached


static func _withheld_report(npc: NPCRuntime, reaction: String, crime_type: String,
		location: String, roll: float) -> Dictionary:
	if is_report_suppressed(npc):
		return _decide(npc, REACTION_DEBT_SILENCE, ACTION_STAY_SILENT, crime_type, location,
				{"intended": reaction, "suppressed_by": SUPPRESSED_BY_DEBT,
				"debt_consumed": _consume_debt(npc)})
	if roll < hesitation_chance(npc):
		return _decide(npc, REACTION_HESITATED, ACTION_STAY_SILENT, crime_type, location,
				{"intended": reaction, "hesitated": true})
	return {}


## Callar por deuda la consume (registro.deuda_consumida_por_silencio), como en NPCDirector.
static func _consume_debt(npc: NPCRuntime) -> int:
	var debt: int = int(npc.ledger.get("debt", 0))
	if debt <= 0:
		return 0
	var consumed: int = mini(Bribery.tunable_int(B_DEBT_SILENCE), debt)
	if Bribery.is_managed(npc):
		NPCDirector.add_debt(npc.id, -consumed)
	else:
		npc.ledger["debt"] = debt - consumed
	return consumed


## Rango del jugador por encima del de partida, de 0 a 1.
static func _player_rank_share() -> float:
	var start: OccupationData = Database.get_occupation(str(Database.get_balance(
			B_START_OCCUPATION)))
	var base: int = start.rank if start != null else 0
	var span: int = OccupationData.MAX_RANK - base
	if span <= 0:
		return 0.0
	return clampf(float(PlayerState.get_rank() - base) / float(span), 0.0, 1.0)


static func _decide(npc: NPCRuntime, reaction: String, action: String, crime_type: String,
		location: String, extra: Dictionary) -> Dictionary:
	var context: Dictionary = {"reaction": reaction, "crime_type": crime_type,
			"location": location, "subject": PLAYER_ID, "reported": false,
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


## El sobornable pide dinero en el acto, cara a cara (salario × chantaje.multiplicador).
static func _ask_for_money(npc: NPCRuntime, crime_type: String, location: String) -> Dictionary:
	var day: int = GameClock.get_day()
	var entry: Dictionary = Blackmail.add_material(npc, Blackmail.KIND_ASKED_MONEY, crime_type, day,
			Blackmail.DEMAND_MONEY, 0)
	var out: Dictionary = _decide(npc, REACTION_ASK_MONEY, ACTION_ASK_MONEY, crime_type, location,
			{"blackmail": true, "demand_type": Blackmail.DEMAND_MONEY})
	var demand: Dictionary = Blackmail.issue_demand(npc, entry, day, true)
	out["amount"] = demand["amount"]
	out["text_key"] = demand["text_key"]
	return out


# ─── Interno: señales ──────────────────────────────────────────

func _on_player_caught_redhanded(npc_id: String, crime_type: String, witnesses: int) -> void:
	if _game_over:
		return
	var caught: Dictionary = {W_NPC: npc_id, W_CRIME: crime_type, W_WITNESSES: witnesses,
			W_WITNESS_IDS: [], W_ROOM: PlayerState.get_room()}
	if is_window_open():
		if str(_window[W_NPC]) != npc_id and _queued(npc_id).is_empty():
			_queue.append(caught)
		return
	_open(caught)


func _on_day_advanced(day_number: int) -> void:
	process_blackmail_day(day_number)


func _on_time_band_changed(_old_band: String, new_band: String) -> void:
	if new_band == gossip_band():
		process_gossip()


## El testigo retirado se lleva su flagrancia: sin reacción, fuera de la cola y sin cotilleo.
func _on_npc_removed(npc_id: String, _cause: String) -> void:
	_drop_gossip(npc_id)
	var kept: Array[Dictionary] = []
	for caught: Dictionary in _queue:
		if str(caught[W_NPC]) != npc_id:
			kept.append(caught)
	_queue = kept
	if _busy or not is_window_open():
		return
	if str(_window[W_NPC]) == npc_id:
		_close(OUTCOME_VOID)
	elif _string_list(_window.get(W_WITNESS_IDS, [])).has(npc_id):
		decision_window_updated.emit(str(_window[W_NPC]), get_options())


## Un cotilla comprado ya no lo cuenta en la comida.
func _on_bribe_result(npc_id: String, accepted: bool, _outcome: String) -> void:
	if accepted:
		_drop_gossip(npc_id)


func _on_game_over(_cause: String, _ending_id: String, _snapshot: Dictionary) -> void:
	_game_over = true
	_queue.clear()
	_pending_gossip.clear()
	if is_window_open() and not _busy:
		_close(OUTCOME_GAME_OVER)


func _on_run_started(_run_seed: int) -> void:
	reset_for_new_run()


# ─── Interno: ventana ──────────────────────────────────────────

func _open(caught: Dictionary) -> bool:
	var npc: NPCRuntime = _resolve(str(caught[W_NPC]))
	if not _is_present(npc):
		return false
	_window = caught.duplicate(true)
	_window[W_DEADLINE] = decision_seconds(PlayerState.get_reputation())
	_window[W_REMAINING] = _window[W_DEADLINE]
	_window[W_COUNTER] = {}
	if str(_window.get(W_ROOM, "")).is_empty():
		_window[W_ROOM] = Bribery.npc_location(npc)
	_slow_time()
	decision_window_opened.emit(npc.id, get_options())
	return true


func _bribe_ctx(extra_ctx: Dictionary) -> Dictionary:
	var ctx: Dictionary = {"wallet": _wallet(), "crime_type": _window[W_CRIME],
			"room_id": _window[W_ROOM], "witnesses": _alive_witness_ids(_window),
			Bribery.CTX_COUNTEROFFER: _window.get(W_COUNTER, {})}
	ctx.merge(extra_ctx, true)
	return ctx


## Contraoferta: la ventana sigue (sin reiniciar el plazo). Rechazo neutro: no compra nada y el
## personaje reacciona según su arquetipo. El resto de resultados cierran la ventana.
func _after_bribe(npc: NPCRuntime, result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not is_window_open():
		return
	var outcome: String = str(result["outcome"])
	if outcome == Bribery.OUTCOME_COUNTEROFFER:
		_window[W_COUNTER] = result["counteroffer"]
		_window[W_REMAINING] = maxf(float(_window[W_REMAINING]),
				Bribery.tunable(B_COUNTER_SECONDS))
		decision_window_updated.emit(str(_window[W_NPC]), get_options())
		return
	if outcome == Bribery.OUTCOME_NEUTRAL and _is_present(npc):
		result["reaction"] = _react(npc, _next_roll())
	_close(outcome)


func _react(npc: NPCRuntime, roll: float) -> Dictionary:
	var reaction: Dictionary = apply_caught_reaction(npc, str(_window[W_CRIME]),
			str(_window[W_ROOM]), roll)
	_register_gossip(reaction)
	return reaction


func _register_gossip(reaction: Dictionary) -> void:
	if str(reaction.get("action", "")) != ACTION_GOSSIP:
		return
	var npc_id: String = str(reaction["npc_id"])
	var belief_id: String = str(reaction.get("belief_id", ""))
	if GameClock.get_current_band() == gossip_band():
		reaction["spread_to"] = spread_gossip(npc_id, belief_id)
		return
	_drop_gossip(npc_id)
	_pending_gossip.append({G_NPC: npc_id, G_BELIEF: belief_id, G_DAY: GameClock.get_day()})


func _close(outcome: String) -> void:
	var npc_id: String = str(_window.get(W_NPC, ""))
	_window = {}
	_restore_time()
	decision_window_closed.emit(npc_id, outcome)
	while not _game_over and not _queue.is_empty() and not is_window_open():
		_open(_queue.pop_front())


func _bribe_price(npc: NPCRuntime) -> int:
	var counter: Dictionary = _window.get(W_COUNTER, {})
	if not counter.is_empty():
		return int(counter.get(Bribery.TOKEN_ASKED, 0))
	return Bribery.fair_price(npc, Bribery.FAVOUR_SILENCE) if npc != null else 0


## La ventana abierta o la entrada en cola de ese personaje (la misma referencia); {} si no hay.
func _entry_for(npc_id: String) -> Dictionary:
	if is_window_open() and str(_window[W_NPC]) == npc_id:
		return _window
	return _queued(npc_id)


func _queued(npc_id: String) -> Dictionary:
	for caught: Dictionary in _queue:
		if str(caught[W_NPC]) == npc_id:
			return caught
	return {}


func _drop_gossip(npc_id: String) -> void:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _pending_gossip:
		if str(entry[G_NPC]) != npc_id:
			kept.append(entry)
	_pending_gossip = kept


func _witness_count(entry: Dictionary) -> int:
	if _string_list(entry.get(W_WITNESS_IDS, [])).is_empty():
		return int(entry.get(W_WITNESSES, 0))
	return _alive_witness_ids(entry).size()


func _alive_witness_ids(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for witness_id: String in _string_list(entry.get(W_WITNESS_IDS, [])):
		var witness: NPCRuntime = _resolve(witness_id)
		if witness == null or _is_present(witness):
			out.append(witness_id)
	return out


## Vivo y, si es de la plantilla, todavía en ella.
func _is_present(npc: NPCRuntime) -> bool:
	if npc == null or not npc.alive:
		return false
	return not Bribery.is_managed(npc) or NPCDirector.is_active(npc.id)


## Guarda el ritmo previo (p. ej. 0,4 dentro del ordenador) para restaurarlo al cerrar.
func _slow_time() -> void:
	if not _time_slowed:
		_speed_before = GameClock.get_speed_multiplier()
	GameClock.set_speed_multiplier(Bribery.tunable(B_SLOW))
	_time_slowed = true


## Devuelve el ritmo previo solo si el reloj sigue al de la flagrancia (nadie lo cambió ni lo
## reinició mientras tanto).
func _restore_time() -> void:
	if _time_slowed and is_equal_approx(GameClock.get_speed_multiplier(),
			Bribery.tunable(B_SLOW)):
		GameClock.set_speed_multiplier(_speed_before)
	_time_slowed = false


func _resolve(npc_id: String) -> NPCRuntime:
	var npc: NPCRuntime = npc_resolver.call(npc_id) as NPCRuntime if npc_resolver.is_valid() else null
	return npc if npc != null else NPCDirector.get_npc(npc_id)


func _wallet() -> Bribery.Wallet:
	return wallet if wallet != null else Bribery.Wallet.new()


func _next_roll() -> float:
	return float(roll_source.call()) if roll_source.is_valid() else _rng.randf()


func _seed() -> int:
	return hash([GameClock.get_run_seed(), get_script().get_global_name()])


static func _restored_window(raw: Dictionary) -> Dictionary:
	var window: Dictionary = raw.duplicate(true)
	window[W_CRIME] = str(window.get(W_CRIME, ""))
	window[W_ROOM] = str(window.get(W_ROOM, ""))
	window[W_WITNESSES] = int(window.get(W_WITNESSES, 0))
	window[W_WITNESS_IDS] = _string_list(window.get(W_WITNESS_IDS, []))
	window[W_REMAINING] = float(window.get(W_REMAINING, 0.0))
	window[W_DEADLINE] = float(window.get(W_DEADLINE, window[W_REMAINING]))
	var counter: Variant = window.get(W_COUNTER, {})
	window[W_COUNTER] = counter if counter is Dictionary else {}
	return window


static func _dict_list(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				out.append(entry)
	return out


static func _string_list(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for value: Variant in raw:
			out.append(str(value))
	return out
