# rumor_case.gd — Cuerpo de test_rumor: un rumor plantado a Debbie Foyle alcanza al menos a cinco personajes tras la franja de comida; certezas de §7.2/§7.13; chat legible por IT.
# PROPIETARIO DE: nada.
# ESCUCHA: rumor_spread (registra los saltos y, si BeliefNet aún no lo escucha, hace de puente como lo haría BeliefNet según el protocolo de social_graph.gd).
extends TestCase

const PLAYER := "player"
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const NATE := "npc_nate_brackley"
const CLAUDIA := "npc_claudia_reeves"
const RAY := "npc_ray_cudmore"
const SONIA := "npc_sonia_vail"
const BERNARD := "npc_bernard_lasker"
const DIANA := "npc_diana_sedgwick"
const CAFETERIA_CLAN := "cafeteria_clan"
const CHAT_3B := "chat_3b"
const LUNCH := "lunch"
const RUMOUR_FACT := "steals_ideas:npc_diana_sedgwick"
const PARTIAL_FACT := "seen_partially"
const PLANTED_CERTAINTY := 0.8
const MIN_REACH := 5
const EPS := 0.000001
# Números del manual (§7.2, §7.7, §7.13, §31).
const MANUAL_DEPARTMENT := 0.75
const MANUAL_RIVALRY := 1.15
const MANUAL_HIERARCHY := 0.85
const MANUAL_PARTIAL := 0.35
const MANUAL_GEORGE_RECEIVES := 0.26
const MANUAL_ROUNDING := 0.005
const MANUAL_DEBBIE_GEORGE_STRENGTH := 0.4
# Reloj: diez minutos antes de la franja de comida (13:00) y de una hora sin cambio de franja.
const DAY := 1
const BEFORE_LUNCH_HOUR := 12
const BEFORE_CHAT_HOUR := 10
const MINUTES_BEFORE := 50
const MINUTES_TO_ADVANCE := 10.0

## Saltos registrados: {from, to, id, fact, certainty}; certainty = la del receptor tras el
## salto (-1 si no la tiene).
var _hops: Array[Dictionary] = []


func run_case() -> void:
	check(new_run(), "Database loaded and a fresh run was created")
	_install_belief_bridge()
	EventBus.rumor_spread.connect(_on_rumor_spread)
	_test_setup()
	_test_lunch_reach()
	_test_manual_example()
	_test_direct_perception_chain()
	_test_chat_readable_by_it()


# ─── Puente con BeliefNet (protocolo documentado en social_graph.gd) ───

## Si BeliefNet todavía no escucha rumor_spread, el caso hace su parte (el caso es «manos»).
func _install_belief_bridge() -> void:
	for connection: Dictionary in EventBus.rumor_spread.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == BeliefNet:
			print("[rumor] BeliefNet handles rumor_spread itself")
			return
	EventBus.rumor_spread.connect(_bridge_rumor_spread)


func _bridge_rumor_spread(from_npc: String, to_npc: String, belief_id: String) -> void:
	if from_npc == PLAYER:
		var r: Dictionary = SocialGraph.get_injected_rumour(belief_id)
		if not r.is_empty():
			BeliefNet.create_belief(to_npc, r["subject"], r["fact"], r["certainty"],
					Belief.SOURCE_RUMOR, r["location"])
		return
	var src: Belief = BeliefNet.get_belief(belief_id)
	if src == null or SocialGraph.is_fact_killed(src.fact):
		return
	BeliefNet.transfer_belief(belief_id, to_npc,
			SocialGraph.get_transfer_factor(from_npc, to_npc, src.fact, src.subject))


func _on_rumor_spread(from_npc: String, to_npc: String, belief_id: String) -> void:
	var src: Dictionary = _source_of(from_npc, belief_id)
	var held: Belief = _held(to_npc, str(src.get("subject", "")), str(src.get("fact", "")))
	_hops.append({
		"from": from_npc, "to": to_npc, "id": belief_id, "fact": src.get("fact", ""),
		"certainty": held.certainty if held != null else -1.0,
	})


func _source_of(from_npc: String, belief_id: String) -> Dictionary:
	if from_npc == PLAYER:
		return SocialGraph.get_injected_rumour(belief_id)
	var b: Belief = BeliefNet.get_belief(belief_id)
	return {"subject": b.subject, "fact": b.fact} if b != null else {}


# ─── Escenarios ───────────────────────────────────────────────

func _test_setup() -> void:
	check_eq(SocialGraph.get_link_type(DEBBIE, GEORGE), "department", "Debbie–George: department")
	check_near(SocialGraph.get_link_strength(DEBBIE, GEORGE), MANUAL_DEBBIE_GEORGE_STRENGTH, EPS,
			"§7.13: the Debbie–George department link has strength 0.4")
	var clan: Array[String] = SocialGraph.get_gathering_participants(CAFETERIA_CLAN)
	for npc_id: String in [DEBBIE, GEORGE, NATE, CLAUDIA, RAY, SONIA]:
		check(clan.has(npc_id), "%s lunches with the cafeteria clan" % npc_id)
	check(not clan.has(BERNARD), "Bernard eats at his desk: not in the clan")
	check(SocialGraph.is_isolated(SONIA), "Sonia (rookie) has no social edges")


## §21 test_rumor: una creencia inyectada a un gossip alcanza cinco personajes tras la comida.
func _test_lunch_reach() -> void:
	GameClock.set_time(DAY, BEFORE_LUNCH_HOUR, MINUTES_BEFORE)
	_hops.clear()
	var id: String = SocialGraph.inject_rumour(DEBBIE, RUMOUR_FACT, PLANTED_CERTAINTY)
	check(not id.is_empty(), "inject_rumour returns a synthetic rumour id")
	check(not _hops.is_empty() and _hops[0]["from"] == PLAYER and _hops[0]["to"] == DEBBIE,
			"inject_rumour emits rumor_spread(player, Debbie, id)")
	check_eq(SocialGraph.get_injected_rumour(id).get("subject", ""), DIANA,
			"the rumour's subject comes from the fact detail")
	check_near(_certainty(DEBBIE, DIANA, RUMOUR_FACT), PLANTED_CERTAINTY, EPS,
			"BeliefNet holds the planted rumour in Debbie")
	check_eq(_holders(DIANA, RUMOUR_FACT).size(), 1, "before lunch only Debbie knows")
	GameClock.advance_minutes(MINUTES_TO_ADVANCE)
	check_eq(GameClock.get_current_band(), LUNCH, "the clock reached the lunch band")
	var reached: Array[String] = _holders(DIANA, RUMOUR_FACT)
	reached.erase(DEBBIE)
	check(reached.size() >= MIN_REACH,
			"the rumour reached at least five characters after lunch (got %d)" % reached.size())
	check(_hop_targets(RUMOUR_FACT).size() >= MIN_REACH,
			"rumor_spread reached at least five distinct characters")
	for npc_id: String in [GEORGE, NATE, CLAUDIA, RAY]:
		check(reached.has(npc_id), "%s heard it from Debbie at the cafeteria" % npc_id)
	check(reached.has(BERNARD), "hierarchy: relevant news ascends to Bernard at his desk")
	check(not reached.has(SONIA), "Sonia shared the table but, without edges, heard nothing")
	_check_lunch_certainties()


func _check_lunch_certainties() -> void:
	var department: float = PLANTED_CERTAINTY * MANUAL_DEPARTMENT
	check_near(_first_hop(DEBBIE, GEORGE), department, EPS, "department: George gets 0.8 × 0.75")
	check_near(_first_hop(DEBBIE, NATE), department, EPS, "department: Nate gets 0.8 × 0.75")
	check_near(_first_hop(DEBBIE, RAY), department, EPS, "department: Ray gets 0.8 × 0.75")
	check_near(_first_hop(DEBBIE, CLAUDIA), PLANTED_CERTAINTY * MANUAL_RIVALRY, EPS,
			"rivalry amplifies negative news: Claudia gets 0.8 × 1.15")
	check_near(_first_hop(DEBBIE, BERNARD), PLANTED_CERTAINTY * MANUAL_HIERARCHY, EPS,
			"hierarchy: Bernard gets 0.8 × 0.85")
	var max_certainty: float = 0.0
	for b: Belief in BeliefNet.get_beliefs_about(DIANA):
		max_certainty = maxf(max_certainty, b.certainty)
	check(max_certainty <= Belief.MAX_CERTAINTY, "no propagated certainty exceeds 1.0")


## §7.13: Debbie (0,35) se sienta con George; por la arista de departamento él recibe 0,26.
func _test_manual_example() -> void:
	new_run()
	_hops.clear()
	SocialGraph.inject_rumour(DEBBIE, PARTIAL_FACT, MANUAL_PARTIAL)
	check_near(_certainty(DEBBIE, PLAYER, PARTIAL_FACT), MANUAL_PARTIAL, EPS,
			"Debbie holds the partial sighting at 0.35")
	var spreads: int = SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check(spreads > 0, "the cafeteria clan propagated (%d hops)" % spreads)
	check_near(_first_hop(DEBBIE, GEORGE), MANUAL_PARTIAL * MANUAL_DEPARTMENT, EPS,
			"George receives 0.35 × 0.75")
	check_near(_first_hop(DEBBIE, GEORGE), MANUAL_GEORGE_RECEIVES, MANUAL_ROUNDING,
			"§7.13: George receives certainty 0.26")


## Una percepción directa de Debbie también se propaga (su amenaza simétrica, §8.3).
func _test_direct_perception_chain() -> void:
	new_run()
	_hops.clear()
	EventBus.player_seen_partially.emit(DEBBIE, MANUAL_PARTIAL, "wing_3b")
	var seen: float = _certainty(DEBBIE, PLAYER, PARTIAL_FACT)
	check(seen > 0.0, "Debbie's own partial sighting exists in BeliefNet")
	SocialGraph.propagate_at_gathering(CAFETERIA_CLAN)
	check_near(_first_hop(DEBBIE, GEORGE), seen * MANUAL_DEPARTMENT, EPS,
			"what Debbie saw reaches George at her certainty × 0.75")


## §7.7: el chat del 3B propaga de forma continua y queda legible por IT.
func _test_chat_readable_by_it() -> void:
	new_run()
	GameClock.set_time(DAY, BEFORE_CHAT_HOUR, MINUTES_BEFORE)
	_hops.clear()
	SocialGraph.inject_rumour(DEBBIE, RUMOUR_FACT, PLANTED_CERTAINTY)
	GameClock.advance_minutes(MINUTES_TO_ADVANCE)
	var log: Array[Dictionary] = SocialGraph.get_chat_log(CHAT_3B)
	check(not log.is_empty(), "the 3B group chat logged its hops for IT")
	var to_claudia: bool = false
	var to_ray: bool = false
	for entry: Dictionary in log:
		to_claudia = to_claudia or (entry["from"] == DEBBIE and entry["to"] == CLAUDIA
				and entry["fact"] == RUMOUR_FACT)
		to_ray = to_ray or entry["to"] == RAY
	check(to_claudia, "IT can read Debbie telling Claudia in the chat")
	check(not to_ray, "Ray is not in the 3B chat")
	check(SocialGraph.get_chat_log(CAFETERIA_CLAN).is_empty(),
			"the cafeteria leaves no digital log")


# ─── Utilidades ───────────────────────────────────────────────

func _held(holder: String, subject: String, fact: String) -> Belief:
	for b: Belief in BeliefNet.get_beliefs_held_by(holder):
		if b.subject == subject and b.fact == fact and not b.is_record:
			return b
	return null


func _certainty(holder: String, subject: String, fact: String) -> float:
	var b: Belief = _held(holder, subject, fact)
	return b.certainty if b != null else -1.0


## Portadores distintos de creencias (no registros) con ese sujeto y hecho.
func _holders(subject: String, fact: String) -> Array[String]:
	var out: Array[String] = []
	for b: Belief in BeliefNet.get_beliefs_about(subject):
		if b.fact == fact and not out.has(b.holder):
			out.append(b.holder)
	return out


func _hop_targets(fact: String) -> Array[String]:
	var out: Array[String] = []
	for hop: Dictionary in _hops:
		if hop["fact"] == fact and hop["from"] != PLAYER and not out.has(str(hop["to"])):
			out.append(str(hop["to"]))
	return out


func _first_hop(from_npc: String, to_npc: String) -> float:
	for hop: Dictionary in _hops:
		if hop["from"] == from_npc and hop["to"] == to_npc:
			return float(hop["certainty"])
	return -1.0
