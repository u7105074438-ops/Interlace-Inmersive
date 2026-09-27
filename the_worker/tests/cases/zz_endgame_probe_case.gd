extends TestCase
func run_case() -> void:
	new_run()
	print("DAY ", GameClock.get_day(), " ", GameClock.get_time_string())
	for p: Dictionary in NPCDirector.get_day_plan("npc_harlan_voss"):
		print("VOSS ", p)
	for n: NPCRuntime in NPCDirector.get_all_npcs():
		if NPCDirector.get_role(n.id) == "notary":
			print("NOTARY ", n.id, " ", n.name, " ", n.traits, " room ", n.home_room)
	print("PEARL ", NPCDirector.get_npc("npc_pearl_osgood").traits, " ", NPCDirector.get_current_location("npc_pearl_osgood"))
	print("CEO holder ", Company.get_seat_holder("ceo"))
	print("rep ", PlayerState.get_reputation(), " susp ", PlayerState.get_suspicion())
	print("items ", PlayerState.get_inventory().map(func(i: ItemData) -> String: return i.id))
	print("has stamp ", PlayerState.has_item("stamp"), " carrying ", PlayerState.is_carrying("stamp"))
	var r: RoomData = Database.get_room("notary")
	print("notary room ", r.interactables if r != null else null)
	print("ceo_office floor ", Database.get_room("ceo_office").floor)
	check(true, "probe")
