# endings_case.gd — Cuerpo de test_endings: incrementos exactos de §12.8, estilo dominante e híbrido, variantes de ruina, los nueve finales de §12.9 y el epílogo.
# PROPIETARIO DE: nada.
# ESCUCHA: nada (emite señales de dominio para alimentar a Tracking).
extends TestCase

# §12.8 (números del manual, no de balance.json).
const BLOOD_ELIMINATION := 10
const BLOOD_BODY := 5
const BLOOD_VIOLENCE := 3
const GOLD_PER_1000_BRIBED := 1
const GOLD_PER_2000_STOLEN := 1
const GOLD_FRAUD := 5
const SILK_IDEA := 8
const SILK_FRAMING := 5
const SILK_RUMOUR := 3
const SILK_FORGERY := 5
const SWEAT_HONEST := 2
const SWEAT_REPORT := 10
const SWEAT_PRESENTATION := 5
const RUIN_PER_LOSS_POINT := 1
const RUIN_TALENT := 5
const RUIN_SCANDAL := 10
const HUSK_THRESHOLD := 150
const HYBRID_SHARE := 0.4

const VICTIM := "npc_bree_nash"
const VICTIM_NAME := "Bree Nash"
const FRAMED := "npc_george_penn"
const IDEA_OWNER := "npc_george_penn"
const PLAYER_NAME := "Ana Test"
const R33 := "ceo"
const R32 := "vice_ceo"
const R20 := "b10_director"
const R10 := "senior_sales"
const R0 := "eternal_intern"
const STASH_ROOM := "dead_archive"
const STASH_SPOT := "hide_dead_archive_west"
const DEFEAT_FILE: Array[String] = [
	"investigation_conclusive", "witnessed_elimination", "bribe_denounced", "arrested_by_police",
]
const DEFEAT_GAP: Array[String] = [
	"starvation", "failed_at_r0", "duty_failure_expulsion", "results_failure_expulsion",
]


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	_test_blood_and_gold()
	_test_silk()
	_test_sweat()
	_test_ruin()
	_test_dominance_and_hybrid()
	_test_ruin_tier()
	_test_full_victories()
	_test_partial_victories()
	_test_defeats()
	_test_epilogue()
	_test_snapshot_and_state()


# ─── §12.8: incrementos exactos desde señales de dominio ──────

func _test_blood_and_gold() -> void:
	new_run(DEFAULT_SEED, false)
	EventBus.npc_removed.emit(VICTIM, "eliminated")
	check_eq(Tracking.get_axis("blood"), BLOOD_ELIMINATION, "elimination → BLOOD +10")
	EventBus.npc_removed.emit("npc_somebody", "expelled")
	EventBus.crime_committed.emit("elimination", "office", {"npc_id": VICTIM, "violent": true})
	check_eq(Tracking.get_axis("blood"), BLOOD_ELIMINATION, "an expulsion and the elimination crime add no extra blood")
	EventBus.body_hidden.emit("body_" + VICTIM, STASH_SPOT)
	EventBus.body_hidden.emit("body_" + VICTIM, "another_spot")
	check_eq(Tracking.get_axis("blood"), BLOOD_ELIMINATION + BLOOD_BODY, "hidden body → +5, once per body")
	EventBus.crime_committed.emit("sabotage", "garage", {"violent": true})
	check_eq(Tracking.get_axis("blood"), BLOOD_ELIMINATION + BLOOD_BODY + BLOOD_VIOLENCE,
			"violence without death → +3")
	_bribe("npc_a", 1500, 1500, true)
	check_eq(Tracking.get_axis("gold"), GOLD_PER_1000_BRIBED, "1.500 € accepted bribe → GOLD +1")
	_bribe("npc_b", 600, 600, true)
	check_eq(Tracking.get_axis("gold"), 2 * GOLD_PER_1000_BRIBED, "2.100 € paid in total → +2 (tranches on the total)")
	_bribe("npc_c", 5000, 0, false)
	_bribe("npc_d", 3000, 0, true)
	check_eq(Tracking.get_total("bribes"), 2100, "refused or unpaid bribes do not count")
	EventBus.crime_committed.emit("theft_small", "p03_desk", {"value": 1500})
	check_eq(Tracking.get_axis("gold"), 2 * GOLD_PER_1000_BRIBED, "1.500 € stolen → nothing yet")
	EventBus.crime_committed.emit("burglary", "", {"value": 600})
	check_eq(Tracking.get_axis("gold"), 2 * GOLD_PER_1000_BRIBED + GOLD_PER_2000_STOLEN, "2.100 € stolen → +1")
	EventBus.crime_committed.emit("fraud", "", {})
	check_eq(Tracking.get_axis("gold"), 2 * GOLD_PER_1000_BRIBED + GOLD_PER_2000_STOLEN + GOLD_FRAUD,
			"fraud → +5")
	check_eq(Tracking.get_axis("ruin"), 0, "none of that touches RUIN")


## bribe_offered → crime_committed("bribe", {paid}) → bribe_result, como Bribery.offer().
func _bribe(npc_id: String, amount: int, paid: int, accepted: bool) -> void:
	EventBus.bribe_offered.emit(npc_id, amount, "silence")
	EventBus.crime_committed.emit("bribe", "office", {"npc_id": npc_id, "amount": amount,
			"paid": paid, "accepted": accepted})
	EventBus.bribe_result.emit(npc_id, accepted, "accepted" if accepted else "neutral")


func _test_silk() -> void:
	new_run(DEFAULT_SEED, false)
	var stolen: String = IdeaPool.generate_idea(IDEA_OWNER, "general")
	check(IdeaPool.acquire(stolen, "overhear"), "the player overhears an idea")
	check_eq(Tracking.get_axis("silk"), SILK_IDEA, "stolen idea → SILK +8")
	EventBus.idea_acquired.emit("idea_x", "steal_file")
	EventBus.idea_acquired.emit("idea_y", "gifted")
	EventBus.idea_acquired.emit("idea_z", "purchase")
	check_eq(Tracking.get_axis("silk"), 2 * SILK_IDEA, "stolen file +8; gifted and bought ideas add nothing")
	EventBus.crime_committed.emit("rumour_planted", "cafeteria", {})
	EventBus.crime_committed.emit("forgery", "", {})
	check_eq(Tracking.get_axis("silk"), 2 * SILK_IDEA + SILK_RUMOUR + SILK_FORGERY, "rumour +3, forgery +5")
	var before: int = Tracking.get_axis("silk")
	EventBus.crime_committed.emit("framing", "", {"target": FRAMED})
	check_eq(Tracking.get_axis("silk"), before, "planting the frame is not yet a success")
	EventBus.investigation_resolved.emit("case_test", "other_guilty", "npc_innocent_bystander")
	check_eq(Tracking.get_axis("silk"), before, "someone else convicted (not framed) → nothing")
	EventBus.investigation_resolved.emit("case_test", "other_guilty", FRAMED)
	check_eq(Tracking.get_axis("silk"), before + SILK_FRAMING, "the framed colleague is convicted → +5")
	EventBus.seat_vacated.emit("junior_shoe_designer", FRAMED, "framed")
	check_eq(Tracking.get_axis("silk"), before + SILK_FRAMING, "a framing pays silk once per victim")
	check(Tracking.get_scapegoats().has(FRAMED), "the framed colleague is a scapegoat for the epilogue")


func _test_sweat() -> void:
	new_run(DEFAULT_SEED, false)
	EventBus.duty_completed.emit("duty_emails_r1", 1.0, "honest")
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST, "honest duty → SWEAT +2")
	EventBus.duty_completed.emit("duty_emails_r1", 1.0, "assist")
	EventBus.duty_completed.emit("duty_emails_r1", 1.0, "stolen_material")
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST, "A.S.S.I.S.T. or stolen material → nothing")
	EventBus.duty_completed.emit("duty_campaign_pieces_r11", 1.0, "honest")
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST + SWEAT_REPORT, "an honest delivery is a real report → +10")
	EventBus.tracking_event_recorded.emit("sweat", SWEAT_PRESENTATION, "presentation_prepared")
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST + SWEAT_REPORT + SWEAT_PRESENTATION,
			"ResultsPresentation real work (tracking_event_recorded) → +5")
	var idea: String = IdeaPool.generate_idea(IDEA_OWNER, "general")
	IdeaPool.acquire(idea, "steal_file")
	check(IdeaPool.set_preparation(idea, "real"), "the player prepares the presentation for real")
	EventBus.idea_presented.emit(idea, "player", 10)
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST + SWEAT_REPORT + 2 * SWEAT_PRESENTATION,
			"a prepared idea presentation → +5")
	EventBus.idea_presented.emit(idea, IDEA_OWNER, 10)
	check_eq(Tracking.get_axis("sweat"), SWEAT_HONEST + SWEAT_REPORT + 2 * SWEAT_PRESENTATION,
			"someone else's presentation adds nothing")
	PlayerState.add_tracking("sweat", 4)
	check_eq(Tracking.get_breakdown().get("player_state", {}).get("sweat", 0), 4,
			"PlayerState.add_tracking reaches Tracking through tracking_event_recorded")


func _test_ruin() -> void:
	new_run(DEFAULT_SEED, false)
	EventBus.crime_committed.emit("theft_product", "factory_floor", {"value": 2500, "quantity": 26})
	check_eq(Tracking.get_axis("ruin"), 2 * RUIN_PER_LOSS_POINT, "2.500 € of product → 2 loss points → RUIN +2")
	check_eq(Tracking.get_axis("gold"), GOLD_PER_2000_STOLEN, "…and GOLD +1 for the 2.000 € stolen")
	EventBus.crime_committed.emit("theft_small", "office_supplies", {"value": 100, "company_loss": 700})
	check_eq(Tracking.get_axis("ruin"), 3 * RUIN_PER_LOSS_POINT, "company_loss accumulates (3.200 € → 3 points)")
	EventBus.seat_vacated.emit("junior_sales", "npc_talent", "expelled")
	check_eq(Tracking.get_axis("ruin"), 3 + RUIN_TALENT, "talent expelled → +5")
	EventBus.seat_vacated.emit("junior_sales", "npc_other", "promoted")
	EventBus.seat_vacated.emit("email_worker_3b", "player", "expelled")
	check_eq(Tracking.get_axis("ruin"), 3 + RUIN_TALENT, "promotions and the player's own seat do not count")
	var kept: String = NewsFeed.publish("NEWS_FRAUD_UNCOVERED", -0.2, true)
	var buried: String = NewsFeed.publish("NEWS_BODY_FOUND", -0.2, true)
	NewsFeed.bury(buried, "npc_bree_nash")
	var day: int = GameClock.get_day()
	for offset: int in range(1, Database.get_balance_int("noticias.dias_consolidacion") + 1):
		NewsFeed.advance_day(day + offset)
	check(NewsFeed.get_news(kept).get("consolidated", false), "the unburied scandal settles")
	EventBus.day_advanced.emit(day + 1)
	check_eq(Tracking.get_axis("ruin"), 3 + RUIN_TALENT + RUIN_SCANDAL,
			"scandal not buried → +10; the buried one adds nothing")
	check_eq(Tracking.get_axis("ruin"), 3 + RUIN_TALENT + RUIN_SCANDAL, "a settled scandal is counted once")


# ─── Estilo dominante, híbrido y variante de ruina ────────────

func _test_dominance_and_hybrid() -> void:
	new_run(DEFAULT_SEED, false)
	check_eq(Tracking.get_dominant_axis(), "sweat", "all four at zero → tie-break gives SWEAT")
	check(not Tracking.is_hybrid(), "a run with no tracked acts is not hybrid")
	_set_axes({"blood": 10, "gold": 10})
	check_eq(Tracking.get_dominant_axis(), "gold", "blood/gold tie → tie-break order prefers gold")
	_set_axes({"blood": 40, "gold": 20, "silk": 20, "sweat": 20})
	check(Tracking.is_hybrid(), "40% of the total does not exceed the 0.4 share → hybrid")
	_set_axes({"blood": 41, "gold": 20, "silk": 20, "sweat": 19})
	check(not Tracking.is_hybrid(), "41% exceeds the 0.4 share → not hybrid")
	check_eq(Tracking.get_dominant_axis(), "blood", "the largest axis dominates")
	_set_axes({"silk": 30, "ruin": 1000})
	check_eq(Tracking.get_dominant_axis(), "silk", "RUIN never competes for the dominant style")
	var rules: Dictionary = Database.get_raw("endings")
	check_near(float(rules["hybrid_rule"]["max_axis_share"]), HYBRID_SHARE, 0.0001, "hybrid share 0.4 in endings.json")


func _test_ruin_tier() -> void:
	_set_axes({"ruin": HUSK_THRESHOLD - 1})
	check_eq(Tracking.get_ruin_tier(), "empire", "RUIN 149 → empire")
	Tracking.add("ruin", 1, "test")
	check_eq(Tracking.get_ruin_tier(), "husk", "RUIN 150 → husk (hollowed-out company)")
	var rules: Dictionary = Database.get_raw("endings")
	check_eq(int(rules["ruin_modifier"]["husk_threshold"]), HUSK_THRESHOLD, "endings.json husk threshold is 150")
	check_eq(Database.get_balance_int("seguimiento.umbral_ruina_cascaron"), HUSK_THRESHOLD,
			"balance duplicate of the husk threshold is 150")


# ─── Los nueve finales (§12.9) ────────────────────────────────

func _test_full_victories() -> void:
	var styles: Dictionary = {
		"the_butcher": {"blood": 60, "gold": 10, "silk": 10, "sweat": 10},
		"the_buyer": {"blood": 5, "gold": 70, "silk": 10, "sweat": 10},
		"the_ghost": {"blood": 5, "gold": 5, "silk": 50, "sweat": 10},
		"the_worker": {"blood": 2, "gold": 2, "silk": 2, "sweat": 30},
		"the_full_suite": {"blood": 25, "gold": 25, "silk": 25, "sweat": 25},
	}
	for ending_id: String in styles:
		_run_as(R33, true, styles[ending_id])
		check_eq(Tracking.evaluate_ending(), ending_id, "R33 + documents + notary + %s → %s" % [
				str(styles[ending_id]), ending_id])
	_run_as(R33, true, {})
	check_eq(Tracking.evaluate_ending(), "the_worker", "a spotless full victory is THE WORKER")
	_run_as(R33, true, {"blood": 60, "gold": 5, "ruin": HUSK_THRESHOLD})
	check_eq(Tracking.evaluate_ending(), "the_butcher", "RUIN does not change which victory it is")
	check_eq(Tracking.get_ruin_tier(), "husk", "…only its variant")
	_run_as(R33, false, {"blood": 60})
	check(not Tracking.has_ownership_documents(), "no documents yet")
	var stashed: bool = PlayerState.add_item("ownership_documents") \
			and PlayerState.stash_item("ownership_documents", STASH_SPOT, STASH_ROOM)
	check(stashed and not PlayerState.has_item("ownership_documents"), "the documents are hidden in the archive")
	check(Tracking.has_ownership_documents(), "hidden documents still count as owned")
	check_eq(Tracking.evaluate_ending(), "the_gap", "owned but not notarised, no terminal cause → no victory")
	EventBus.ownership_notarised.emit()
	check_eq(Tracking.get_terminal_cause(), "ownership_notarised", "notarising is the terminal cause")
	check_eq(Tracking.evaluate_ending(), "the_butcher", "…and the notarised owner wins")


func _test_partial_victories() -> void:
	for cause: String in ["board_removal", "ceo_term_without_ownership"]:
		_run_as(R33, false, {"blood": 60})
		check_eq(_end_with(cause), "the_figurehead", "R33 without documents, cause %s → THE FIGUREHEAD" % cause)
	for occupation: String in [R32, R20, R0]:
		_run_as(occupation, false, {"sweat": 60})
		PlayerState.add_item("ownership_documents")
		check_eq(_end_with("investigation_conclusive"), "the_owner_in_exile",
				"documents at %s and caught → THE OWNER IN EXILE (before THE FILE)" % occupation)
	_run_as(R20, false, {})
	PlayerState.add_item("ownership_documents")
	check_eq(_end_with("starvation"), "the_owner_in_exile", "documents without the chair, any cause → exile")
	_run_as(R33, false, {})
	PlayerState.add_item("ownership_documents")
	check_eq(_end_with("board_removal"), "the_gap",
			"R33 with unnotarised documents removed by the board matches nothing → fallback THE GAP")


func _test_defeats() -> void:
	for cause: String in DEFEAT_FILE:
		_run_as(R10, false, {"blood": 90})
		check_eq(Tracking.evaluate_ending_for_cause(cause), "the_file", "cause %s → THE FILE" % cause)
		check_eq(_end_with(cause), "the_file", "game_over(%s) is remembered by evaluate_ending()" % cause)
	for cause: String in DEFEAT_GAP:
		_run_as(R0 if cause == "failed_at_r0" else R10, false, {"sweat": 90})
		check_eq(_end_with(cause), "the_gap", "cause %s → THE GAP" % cause)
	_run_as(R10, false, {})
	check_eq(Tracking.evaluate_ending(), "the_gap", "no terminal cause yet → fallback THE GAP")
	check_eq(Tracking.get_terminal_cause(), "", "no terminal cause while the run goes on")


## Partida limpia con la ocupación, documentos (y notaría) y ejes dados.
func _run_as(occupation: String, notarised: bool, axes: Dictionary) -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_occupation(occupation, "test")
	if notarised:
		PlayerState.add_item("ownership_documents")
		EventBus.ownership_notarised.emit()
	for axis: String in axes:
		Tracking.add(axis, int(axes[axis]), "test")


func _end_with(cause: String) -> String:
	EventBus.game_over.emit(cause, "", Tracking.get_snapshot())
	return Tracking.evaluate_ending()


func _set_axes(axes: Dictionary) -> void:
	Tracking.reset_for_new_run()
	for axis: String in axes:
		Tracking.add(axis, int(axes[axis]), "test")


# ─── Epílogo y estado ─────────────────────────────────────────

func _test_epilogue() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.set_player_name(PLAYER_NAME)
	EventBus.npc_removed.emit(VICTIM, "eliminated")
	Tracking.add("ruin", HUSK_THRESHOLD, "test")
	var ctx: Dictionary = {"company_value": "€9", "share_price": "€1.00"}
	var values: Dictionary = {"name": PLAYER_NAME, "days": str(GameClock.get_day()), "victims": VICTIM_NAME,
			"company_value": "€9", "share_price": "€1.00"}
	var expected: String = tr("EPILOGUE_THE_BUTCHER").format(values) + "\n\n" \
			+ tr("EPILOGUE_THE_BUTCHER_HUSK").format(values)
	check_eq(Tracking.get_epilogue("the_butcher", ctx), expected,
			"THE BUTCHER epilogue = text + husk paragraph, victims named, placeholders filled")
	ctx["ruin_tier"] = "empire"
	check(Tracking.get_epilogue("the_butcher", ctx).ends_with(tr("EPILOGUE_THE_BUTCHER_EMPIRE").format(values)),
			"the context can ask for the empire variant")
	var gap: String = Tracking.get_epilogue("the_gap")
	check(not gap.contains("{") and gap.contains(PLAYER_NAME), "THE GAP has no raw placeholders")
	check(not gap.contains("\n\n"), "defeats carry no ruin variant paragraph")
	check(_mentions_bank_name(gap), "THE GAP names a generated graduate as successor")
	check_eq(Tracking.get_epilogue("the_gap"), gap, "the successor's name is fixed for the run seed")
	check_eq(Tracking.get_epilogue("the_gap", {"successor": "Bob Hale"}),
			tr("EPILOGUE_THE_GAP").format({"name": PLAYER_NAME, "days": str(GameClock.get_day()),
			"successor": "Bob Hale"}), "context values override the run's own")
	var file_text: String = Tracking.get_epilogue("the_file")
	check(file_text.contains(tr("UI_EPILOGUE_REDACTED")), "unknown case data is redacted in THE FILE")
	check_eq(Tracking.get_epilogue("no_such_ending"), "", "unknown ending → empty text")
	var english: String = Tracking.get_epilogue("the_butcher", ctx)
	TranslationServer.set_locale("es")
	var spanish: String = Tracking.get_epilogue("the_butcher", ctx)
	TranslationServer.set_locale("en")
	check(spanish != english and spanish.contains(VICTIM_NAME), "the epilogue follows the language setting")


func _mentions_bank_name(text: String) -> bool:
	var bank: Dictionary = Database.get_raw("npcs_generation").get("name_bank", {})
	var first: bool = false
	var last: bool = false
	for entry: Variant in bank.get("first_names", []):
		first = first or text.contains("%s " % entry)
	for entry: Variant in bank.get("last_names", []):
		last = last or text.contains(" %s" % entry)
	return first and last


func _test_snapshot_and_state() -> void:
	_run_as(R33, true, {"blood": 12, "gold": 3, "silk": 4, "sweat": 5, "ruin": 7})
	EventBus.npc_removed.emit(VICTIM, "eliminated")
	_bribe("npc_a", 1200, 1200, true)
	var snapshot: Dictionary = Tracking.get_snapshot()
	check_eq(snapshot["axes"], {"blood": 22, "gold": 4, "silk": 4, "sweat": 5, "ruin": 7}, "snapshot axes")
	check_eq(snapshot["dominant_axis"], "blood", "snapshot dominant axis")
	check(snapshot["notarised"] and snapshot["has_ownership_documents"], "snapshot ownership flags")
	check((snapshot["victims"] as Array).size() == 1 and snapshot["victims"][0] == VICTIM, "snapshot victims")
	check_eq(snapshot["bribes_total"], 1200, "snapshot bribes total")
	var saved: Dictionary = Tracking.save_state()
	var json: JSON = JSON.new()
	json.parse(JSON.stringify(saved, "", true, true))
	Tracking.reset_for_new_run()
	check_eq(Tracking.get_axis("blood"), 0, "reset clears the axes")
	Tracking.load_state(json.data)
	check_eq(JSON.stringify(Tracking.save_state(), "", true), JSON.stringify(saved, "", true),
			"save_state → JSON → load_state reproduces the exact state")
	check_eq(Tracking.evaluate_ending(), "the_butcher", "the loaded run still evaluates the same ending")
