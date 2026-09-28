# named_specials_case.gd — Cuerpo de test_named_specials: Iggy (favores a crédito y cobro inoportuno), Alvin (aliado permanente, chat legible por IT) y Voss (sin información veraz).
# PROPIETARIO DE: nada.
# ESCUCHA: npc_reported_player (conexión temporal del escenario).
extends TestCase

const IGGY := "npc_iggy_robbins"
const ALVIN := "npc_alvin_pyne"
const VOSS := "npc_harlan_voss"
const GEORGE := "npc_george_penn"
const BAD_FACT := "caught_redhanded:insider_trade"

var _reports: Array = []


func run_case() -> void:
	if not check(new_run(), "Database loads the data files"):
		return
	EventBus.npc_reported_player.connect(func(n: String, t: String, _w: float, _l: String) -> void:
		_reports.append([n, t]))
	_check_iggy()
	_check_alvin()
	_check_voss()


func _check_iggy() -> void:
	check(NamedSpecials.grants_on_credit(IGGY, 10), "Iggy grants favours on credit")
	check(not NamedSpecials.grants_on_credit(GEORGE, 10), "an ordinary character does not")
	check(not NamedSpecials.grants_on_credit(IGGY, 1000), "Iggy's credit has a ceiling")
	NPCDirector.add_debt(IGGY, -20)
	EventBus.investigation_opened.emit("case_x", "theft", 3)
	var deadline: int = NamedSpecials.claim_deadline(IGGY)
	check(deadline > GameClock.get_day(), "an investigation is the inopportune moment: Iggy claims")
	NamedSpecials._on_day_advanced(deadline)
	check(_reports.has([IGGY, "superior"]), "unpaid, Iggy reports the player to the superior")
	check_eq(NPCDirector.get_debt(IGGY), 0, "the account is closed after the report")
	check_eq(NamedSpecials.claim_deadline(IGGY), NamedSpecials.NO_CLAIM, "no claim pending")


func _check_alvin() -> void:
	NPCDirector.add_favour(ALVIN, "credit", 5)
	check(not NamedSpecials.is_permanent_ally(ALVIN), "a favour without a threat is just a favour")
	BeliefNet.create_belief(GEORGE, ALVIN, BAD_FACT, 0.8, Belief.SOURCE_DIRECT, "")
	check(NamedSpecials.is_under_threat(ALVIN), "a negative belief about Alvin threatens him")
	NPCDirector.add_favour(ALVIN, "credit", 5)
	check(NamedSpecials.is_permanent_ally(ALVIN), "protecting Alvin makes him a permanent ally")
	check(NPCDirector.is_report_suppressed(ALVIN), "a permanent ally never reports the player")
	NamedSpecials.on_chat_logged("chat_3b", "player", BAD_FACT, 0.7)
	var seen: bool = false
	for b: Belief in BeliefNet.get_beliefs_held_by(ALVIN):
		seen = seen or (b.subject == "player" and b.fact == BAD_FACT)
	check(seen, "Alvin reads the IT-readable 3B chat and keeps what it says about the player")


func _check_voss() -> void:
	check(not NamedSpecials.accepts_rumour(VOSS, true, true), "Voss ignores what the player tells him")
	check(not NamedSpecials.accepts_rumour(VOSS, false, false), "no truthful rumour reaches Voss")
	check(NamedSpecials.accepts_rumour(VOSS, false, true), "planted rumours reach him through intermediaries")
	check(NamedSpecials.accepts_rumour(GEORGE, false, false), "ordinary characters hear everything")
	SocialGraph.inject_rumour_about(VOSS, GEORGE, "caught_redhanded:theft", 0.9)
	check(BeliefNet.get_beliefs_held_by(VOSS).is_empty() or not _holds(VOSS, "caught_redhanded:theft"),
			"a rumour planted in person on Voss leaves no belief")


func _holds(holder: String, fact: String) -> bool:
	for b: Belief in BeliefNet.get_beliefs_held_by(holder):
		if b.fact == fact:
			return true
	return false
