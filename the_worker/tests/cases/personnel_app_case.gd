extends TestCase

func run_case() -> void:
	new_run()
	var npcs: Array = NPCDirector.get_all_npcs()
	print("NPCS ", npcs.size())
	var seats: Array = Company.get_all_seats()
	print("SEATS ", seats.size(), " vacant ", Company.get_vacant_seats())
	var counts: Dictionary = {}
	for s: Dictionary in seats:
		counts[s["occupation_id"]] = counts.get(s["occupation_id"], 0) + 1
	print(counts)
	print("player seat ", Company.get_player_seat(), " rank ", PlayerState.get_rank(), " lvl ", PlayerState.get_personnel_file_level())
	for npc: NPCRuntime in npcs.slice(0, 4):
		var ctx: Dictionary = NPCDirector.build_context(npc.id, "belief", {"certainty": 1.0})
		var ev: Dictionary = UtilityAI.evaluate(npc, ctx)
		print(npc.name, " ", npc.archetype, " ", ev)
		print(Bribery.acceptance_probability(npc, Bribery.fair_price(npc, "look_away_once"), "look_away_once"), " price ", Bribery.estimated_price(npc, "look_away_once"))
		print(NPCDirector.get_day_plan(npc.id))
		print(SocialGraph.get_links(npc.id))
		print(NPCDirector.get_profile(npc.id))
	var roles: Dictionary = {}
	for npc: NPCRuntime in npcs:
		if npc.occupation_id.is_empty():
			roles[NPCDirector.get_role(npc.id)] = true
	print("roles ", roles.keys())
	print("clock ", GameClock.get_day(), " ", GameClock.get_time_string())
	check(true, "probe")
