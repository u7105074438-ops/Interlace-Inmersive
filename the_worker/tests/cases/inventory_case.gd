# inventory_case.gd — Cuerpo de test_inventory (§21, PASO 37): escondites §11.3, alijos, muelle de basuras, registro corporal §12.4.
# PROPIETARIO DE: nada.
# ESCUCHA: inventory_changed, item_hidden, item_disposed (conexión temporal).
extends TestCase

const DESK_SPOT := "hide_3b_desk"
const DESK_ROOM := "wing_3b"
const TRASH_SPOT := "trash_compactor"
const TRASH_ROOM := "trash_dock"

var _changed: Array = []
var _hidden: Array = []
var _disposed: Array = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded and a new run was created")
	EventBus.inventory_changed.connect(_on_changed)
	EventBus.item_hidden.connect(_on_hidden)
	EventBus.item_disposed.connect(_on_disposed)
	_test_security_table()
	_test_spot_classification()
	_test_can_hide_in()
	_test_stash_and_retrieve()
	_test_stash_capacity_and_full_inventory()
	_test_trash_dock_is_irreversible()
	_test_body_search()
	_test_investigation_search()
	_test_confiscation()
	EventBus.inventory_changed.disconnect(_on_changed)
	EventBus.item_hidden.disconnect(_on_hidden)
	EventBus.item_disposed.disconnect(_on_disposed)


# ─── Escenarios ────────────────────────────────────────────────

func _test_security_table() -> void:
	var expected: Dictionary = {
		"desk": "very_low", "locker": "medium", "dead_archive": "high", "vents": "high",
		"cleaning_closet": "medium", "trash_dock": "absolute",
	}
	for location: String in expected:
		check_eq(InventoryRules.get_location_security_level(location), expected[location],
				"§11.3 security of %s" % location)
	check(_security("desk") < _security("locker")
			and _security("locker") < _security("dead_archive"), "desk < locker < dead archive")
	check_eq(_security("locker"), _security("cleaning_closet"), "locker and cleaning closet: medium")
	check_eq(_security("dead_archive"), _security("vents"), "dead archive and vents: high")
	check(_security("vents") < _security("trash_dock"), "high < absolute")
	check_near(_security("trash_dock"), 1.0, 0.0001, "trash dock: absolute")
	for location: String in InventoryRules.LOCATIONS:
		check_eq(InventoryRules.is_irreversible(location), location == "trash_dock",
				"only the trash dock is irreversible (%s)" % location)
	check(InventoryRules.retrieval_minutes("vents") > InventoryRules.retrieval_minutes("desk"),
			"vents: slow retrieval")
	check(InventoryRules.daily_discovery_chance("cleaning_closet") > 0.0
			and InventoryRules.daily_discovery_chance("desk") == 0.0,
			"cleaning closets: Connie Marks may stumble on it daily")


func _test_spot_classification() -> void:
	var cases: Array = [
		[DESK_ROOM, DESK_SPOT, "desk"],
		["dead_archive", "hide_dead_archive_west", "dead_archive"],
		["dead_archive", "hide_dead_archive_crates", "dead_archive"],
		["cleaning_locker_room", "hide_cleaning_locker", "locker"],
		["vent_network@3", "hide_vent_duct@3", "vents"],
		["cleaning_closet_low@3", "hide_closet_low@3", "cleaning_closet"],
		[TRASH_ROOM, TRASH_SPOT, "trash_dock"],
		["forgotten_corridor", "hide_forgotten_crates", "forgotten_corridor"],
		["player_flat", "flat_stash", "home"],
	]
	for entry: Array in cases:
		var spot: Dictionary = InventoryRules.find_spot(entry[0], entry[1])
		check_eq(spot.get("location", ""), entry[2], "%s/%s is a %s" % entry)
	check_eq(InventoryRules.find_spot(DESK_ROOM, DESK_SPOT)["capacity"], 3, "3B desk capacity")
	check(InventoryRules.find_spot("ceo_office", "hide_ceo_curtain").is_empty(),
			"a curtain hides the player, not objects")
	check(InventoryRules.find_spot("no_such_room", "x").is_empty(), "unknown room")


func _test_can_hide_in() -> void:
	check(InventoryRules.can_hide_in("under_desk", "balaclava"), "balaclava fits in a desk")
	check(not InventoryRules.can_hide_in("under_desk", "product_box"), "a box does not fit a desk")
	check(not InventoryRules.can_hide_in("vent", "product_box"), "a box does not fit a vent")
	check(InventoryRules.can_hide_in("locker", "product_box"), "a box fits a locker")
	check(InventoryRules.can_hide_in("dead_archive", "product_box"), "a box fits the dead archive")
	check(InventoryRules.can_hide_in("trash_chute", "product_box"), "anything goes down the chute")
	check(not InventoryRules.can_hide_in("curtain", "balaclava"), "curtains hold no objects")
	check(not InventoryRules.can_hide_in("under_desk", "flashlight"), "post tools are not items")
	check(not InventoryRules.can_hide_in("under_desk", "cash_small"), "pocket cash is money")


func _test_stash_and_retrieve() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.add_item("balaclava")
	_clear()
	check(PlayerState.stash_item("balaclava", DESK_SPOT, DESK_ROOM), "stash in the own desk")
	check_eq(_hidden, [["balaclava", DESK_SPOT]], "item_hidden(item, spot)")
	check_eq(_changed, [["balaclava", false]], "inventory_changed(item, false)")
	check(not PlayerState.has_item("balaclava") and not PlayerState.has_hot_items(),
			"the stashed item is no longer carried")
	var stash: Dictionary = PlayerState.get_stashes().get(DESK_SPOT, {})
	check_eq([stash.get("room_id"), stash.get("location")], [DESK_ROOM, "desk"], "stash record")
	check_eq(stash["items"][0]["id"], "balaclava", "stash contents")
	check(not PlayerState.stash_item("balaclava", DESK_SPOT, DESK_ROOM), "cannot stash twice")
	check(not PlayerState.stash_item("phone", "hide_ceo_curtain", "ceo_office"),
			"cannot stash behind a curtain")
	check(PlayerState.retrieve_item(DESK_SPOT, "balaclava"), "retrieve from the desk")
	check(PlayerState.has_item("balaclava"), "carried again after retrieval")
	check(not PlayerState.get_stashes().has(DESK_SPOT), "an empty stash disappears")
	check(not PlayerState.retrieve_item(DESK_SPOT, "balaclava"), "nothing left to retrieve")


func _test_stash_capacity_and_full_inventory() -> void:
	new_run(DEFAULT_SEED, false)
	for _i: int in 4:
		PlayerState.add_item("foreign_document")
	for _i: int in 3:
		check(PlayerState.stash_item("foreign_document", DESK_SPOT, DESK_ROOM), "stash a document")
	check(not PlayerState.stash_item("foreign_document", DESK_SPOT, DESK_ROOM),
			"the 4th unit exceeds the desk capacity (3)")
	var records: Array = PlayerState.get_stashes()[DESK_SPOT]["items"]
	check_eq([records.size(), int(records[0]["stack"])], [1, 3], "stackables merge in the stash")
	PlayerState.remove_item("foreign_document")
	check(PlayerState.add_item("balaclava") and PlayerState.stash_item("balaclava",
			"hide_cleaning_locker", "cleaning_locker_room"), "stash a balaclava in a locker")
	for item_id: String in ["keys_basic", "stamp", "executive_suit", "stellar_shoes", "wallet",
			"lockpick"]:
		PlayerState.add_item(item_id)
	check_eq(PlayerState.get_free_slots(), 0, "inventory full")
	check(not PlayerState.retrieve_item("hide_cleaning_locker", "balaclava"),
			"cannot retrieve into a full inventory")
	check(PlayerState.get_stashes().has("hide_cleaning_locker"), "the item stays in the stash")


func _test_trash_dock_is_irreversible() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.add_item("balaclava")
	_clear()
	check(PlayerState.stash_item("balaclava", TRASH_SPOT, TRASH_ROOM), "throw it down the chute")
	check_eq(_disposed, [["balaclava", "trash_dock"]], "item_disposed(item, trash_dock)")
	check(_hidden.is_empty(), "the trash dock is not a stash")
	check(PlayerState.get_stashes().is_empty(), "no stash record")
	check(not PlayerState.has_item("balaclava"), "the item left the inventory")
	check(not PlayerState.retrieve_item(TRASH_SPOT, "balaclava"), "irreversible: no retrieval")
	PlayerState.add_item("lockpick")
	check(PlayerState.dispose_item("lockpick", "sold"), "dispose_item")
	check(not PlayerState.dispose_item("lockpick", "sold"), "cannot dispose twice")
	check_eq(_disposed.back(), ["lockpick", "sold"], "item_disposed(item, method)")


func _test_body_search() -> void:
	var weight: float = Database.get_balance_float(
			"investigaciones.pesos_evidencia.objeto_comprometedor")
	check_near(weight, 10.0, 0.0001, "balance: compromising object weight 10 (§12.4)")
	var clean: Dictionary = InventoryRules.resolve_body_search(["own_card", "phone"], 90.0)
	check_eq([clean["found_hot_items"], clean["evidence_weight"], clean["outcome"]],
			[0, 0.0, "clean"], "ordinary items: nothing found even with high suspicion")
	new_run(DEFAULT_SEED, false)
	PlayerState.add_item("balaclava")
	var caught: Dictionary = InventoryRules.resolve_body_search(PlayerState.get_inventory(), 0.0)
	check_eq([caught["found_hot_items"], caught["evidence_weight"]], [1, 10.0],
			"one compromising item: definitive evidence of weight 10")
	check_eq(caught["outcome"], "conviction_minor",
			"suspicion 0: weight 10 is not above the 10.0 major threshold -> minor")
	var high: Dictionary = InventoryRules.resolve_body_search(PlayerState.get_inventory(), 50.0)
	check_eq(high["outcome"], "conviction_major",
			"suspicion 50 lowers the major threshold to 8.5 (-0.03 x suspicion) -> major")
	PlayerState.add_item("product_pair")
	PlayerState.add_item("product_pair")
	var many: Dictionary = InventoryRules.resolve_body_search(PlayerState.get_inventory(), 50.0)
	check_eq([many["found_hot_items"], many["evidence_weight"]], [3, 10.0],
			"three hot units found; the evidence stays weight 10")
	check_eq(InventoryRules.classify_evidence(6.0, 0.0), "evidence_noted", "6 < 7: below minor")
	check_eq(InventoryRules.classify_evidence(6.0, 100.0), "conviction_minor",
			"suspicion 100 lowers the minor threshold 7 -> 4")
	PlayerState.set_occupation("cleaner", "lateral")
	PlayerState.add_item("uniform_cleaning")
	var issued: Dictionary = InventoryRules.resolve_body_search(PlayerState.get_inventory(), 50.0)
	check_eq(issued["found_hot_items"], 3, "the cleaner's issued uniform is not evidence")


func _test_investigation_search() -> void:
	check(InventoryRules.search_finds_stash("desk", 1, false),
			"the own desk is the first place any investigation searches")
	check(not InventoryRules.search_finds_stash("dead_archive", 3, false),
			"the dead archive survives investigations that do not search basements")
	check(InventoryRules.search_finds_stash("dead_archive", 4, true),
			"a high-severity investigation searching basements finds it in phase 2")
	check(not InventoryRules.search_finds_stash("vents", 4, true), "vents: only the gravest")
	check(InventoryRules.search_finds_stash("vents", 5, true), "vents found at severity 5")
	check(not InventoryRules.search_finds_stash("trash_dock", 5, true), "nothing left to find")
	check(not InventoryRules.search_finds_stash("forgotten_corridor", 5, true),
			"no investigation searches the forgotten corridor (§22.1)")
	check(InventoryRules.search_order("desk") < InventoryRules.search_order("dead_archive"),
			"search order: desk first")


func _test_confiscation() -> void:
	new_run(DEFAULT_SEED, false)
	PlayerState.add_item("balaclava")
	PlayerState.add_item("product_pair")
	PlayerState.add_item("product_pair")
	_clear()
	var taken: Array[String] = PlayerState.confiscate_hot_items()
	check_eq(taken.size(), 3, "every hot unit is confiscated")
	check(not PlayerState.has_hot_items() and PlayerState.has_item("phone"),
			"ordinary items stay")
	check_eq(_disposed.size(), 3, "item_disposed(..., confiscated) per unit")
	PlayerState.add_item("lockpick")
	PlayerState.stash_item("lockpick", DESK_SPOT, DESK_ROOM)
	check_eq(PlayerState.confiscate_stash(DESK_SPOT), ["lockpick"], "a found stash is removed")
	check(PlayerState.get_stashes().is_empty(), "no stash left")


# ─── Registro de señales ───────────────────────────────────────

func _security(location: String) -> float:
	return InventoryRules.get_location_security(location)


func _clear() -> void:
	_changed.clear()
	_hidden.clear()
	_disposed.clear()


func _on_changed(item_id: String, added: bool) -> void:
	_changed.append([item_id, added])


func _on_hidden(item_id: String, spot_id: String) -> void:
	_hidden.append([item_id, spot_id])


func _on_disposed(item_id: String, method: String) -> void:
	_disposed.append([item_id, method])
