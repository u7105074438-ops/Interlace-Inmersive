extends TestCase
func run_case() -> void:
	allowed_engine_errors = -1
	check(new_run(), "run")
	var rules: Dictionary = Database.get_raw("npcs_generation")["link_generation"]
	var maxes: Dictionary = {"department": 5, "friendship": 2, "rivalry": 1}
	var over: Dictionary = {"department": 0, "friendship": 0, "rivalry": 0}
	var under: int = 0
	var gen: int = 0
	var hist: Dictionary = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		var counts: Dictionary = {"department": 0, "friendship": 0, "rivalry": 0, "hierarchy": 0, "couple": 0}
		for to: String in SocialGraph._links.get(npc.id, {}):
			var t: String = SocialGraph._links[npc.id][to]["type"]
			counts[t] = counts.get(t, 0) + 1
		for t: String in maxes:
			if counts[t] > maxes[t]:
				over[t] += 1
				print("OVER ", npc.id, " ", npc.is_named, " ", t, " ", counts[t])
		if not npc.is_named and npc.archetype != "rookie":
			gen += 1
			hist[counts["department"]] = hist.get(counts["department"], 0) + 1
			if counts["department"] < 2:
				under += 1
				print("UNDER ", npc.id, " dept=", npc.department, " ", counts)
	print("over ", over, " under ", under, " of ", gen, " dept hist ", hist)
	print("debbie links ", SocialGraph.get_links("npc_debbie_foyle").size())
	for id: String in ["npc_debbie_foyle", "npc_george_penn", "npc_nate_brackley", "npc_ray_cudmore", "npc_claudia_reeves"]:
		var npc: NPCRuntime = NPCDirector.get_npc(id)
		var arch: ArchetypeData = Database.get_archetype(npc.archetype)
		print(id, " factor=", arch.propagation_bonus * npc.get_trait("sociability") / 50.0, " occ=", npc.occupation_id, " dept=", npc.department)
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if npc.gatherings.has("accounting_couple"):
			print("acc member ", npc.id, " dept=", npc.department, " room=", npc.home_room, " arch=", npc.archetype)
	print("couple acc links: ", SocialGraph.get_all_links().filter(func(l: Dictionary) -> bool: return l["type"] == "couple").size())
	for id: String in ["npc_ray_cudmore", "npc_tom_iverson", "npc_frank_rudd", "npc_nate_brackley", "npc_iggy_robbins", "npc_bree_nash"]:
		for iv: Dictionary in NPCDirector.get_day_plan(id):
			if str(iv["room"]) in ["street", "foosball_room"]:
				print(id, " ", iv)
	for h: int in [10, 11, 12, 14, 16, 18]:
		GameClock.set_time(GameClock.get_day(), h, 0)
		var parts: Array[String] = SocialGraph.get_gathering_participants("smokers_circle")
		print("smokers at ", h, ": ", parts.size(), " ", parts.filter(func(x: String) -> bool: return NPCDirector.get_npc(x).is_named))
	GameClock.set_time(GameClock.get_day(), 13, 0)
	print("foosball at 13: ", SocialGraph.get_gathering_participants("foosball_circle"))
	print("accounting at 13: ", SocialGraph.get_gathering_participants("accounting_couple"))
	GameClock.set_time(GameClock.get_day(), 14, 0)
	print("foosball at 14: ", SocialGraph.get_gathering_participants("foosball_circle"))
	print("wing chief holder ", _h("wing_3b_chief"), " seat ", Company.get_npc_seat("npc_bernard_lasker"))
	print("chat members ", SocialGraph.get_gathering_participants("chat_3b"))
	print("frank links ", SocialGraph.get_links("npc_frank_rudd"))
	print("day ", GameClock.get_day(), " band ", GameClock.get_current_band())
func _h(occ: String) -> String:
	var n: NPCRuntime = NPCDirector.get_npc_by_occupation(occ)
	return n.id if n != null else ""
