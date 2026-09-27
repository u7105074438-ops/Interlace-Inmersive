# bribery_fixtures.gd — Utilidades comunes de test_bribe, test_caught y test_blackmail.
# PROPIETARIO DE: nada.
# ESCUCHA: las señales de EventBus que se le pidan (SignalLog, solo durante el caso).
extends RefCounted

## Uso: const Fixtures := preload("res://tests/cases/bribery_fixtures.gd")
##   Fixtures.named("npc_frank_rudd") · Fixtures.synthetic("test_x", "coward", {"greed": 10})
##   Fixtures.FakeWallet.new(1000) · Fixtures.SignalLog.new().watch(["bribe_result", ...])

const DEFAULT_OCCUPATION := "email_worker_3b"
const DEFAULT_ROOM := "wing_3b"


## Monedero de prueba (Bribery.Wallet) que usan Bribery, CaughtHandler y Blackmail.
class FakeWallet:
	extends Bribery.Wallet
	var money: int = 0
	var spent: Array[Dictionary] = []

	func _init(initial_money: int) -> void:
		money = initial_money

	func can_afford(amount: int) -> bool:
		return money >= amount

	func spend_money(amount: int, reason: String) -> bool:
		if money < amount:
			return false
		money -= amount
		spent.append({"amount": amount, "reason": reason})
		return true

	func get_money() -> int:
		return money


## Registro de emisiones del EventBus: [nombre, argumentos].
class SignalLog:
	extends RefCounted
	var events: Array[Array] = []
	var _connections: Array[Array] = []

	func watch(names: Array[String]) -> SignalLog:
		for signal_name: String in names:
			var callback: Callable = func(...args: Array) -> void: events.append([signal_name, args])
			EventBus.connect(signal_name, callback)
			_connections.append([signal_name, callback])
		return self

	func stop() -> void:
		for pair: Array in _connections:
			if EventBus.is_connected(pair[0], pair[1]):
				EventBus.disconnect(pair[0], pair[1])
		_connections.clear()

	func clear() -> void:
		events.clear()

	func count(signal_name: String) -> int:
		return all(signal_name).size()

	func all(signal_name: String) -> Array[Array]:
		var out: Array[Array] = []
		for event: Array in events:
			if event[0] == signal_name:
				out.append(event[1])
		return out

	func last(signal_name: String) -> Array:
		var found: Array[Array] = all(signal_name)
		return found[found.size() - 1] if not found.is_empty() else []

	## Emisiones cuyo primer argumento es `first_arg`.
	func count_for(signal_name: String, first_arg: String) -> int:
		var total: int = 0
		for args: Array in all(signal_name):
			if not args.is_empty() and str(args[0]) == first_arg:
				total += 1
		return total


## Personaje nominado: el vivo de NPCDirector si existe; si no, construido desde Database.
static func named(npc_id: String) -> NPCRuntime:
	var live: NPCRuntime = NPCDirector.get_npc(npc_id)
	if live != null:
		return live
	var data: NPCData = Database.get_named_npc(npc_id)
	if data == null:
		return null
	var npc: NPCRuntime = NPCRuntime.from_named(data)
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	npc.tier = occupation.tier if occupation != null else int(data.extra.get("tier", 1))
	return npc


## Personaje sintético con los rasgos base del arquetipo (más `overrides`), desconocido para
## NPCDirector: el registro de relaciones que se lee es el suyo propio.
static func synthetic(npc_id: String, archetype: String, overrides: Dictionary = {},
		occupation_id: String = DEFAULT_OCCUPATION) -> NPCRuntime:
	var npc: NPCRuntime = NPCRuntime.new()
	npc.id = npc_id
	npc.name = npc_id
	npc.archetype = archetype
	var data: ArchetypeData = Database.get_archetype(archetype)
	npc.traits = data.traits.duplicate() if data != null else Validate.default_traits()
	npc.traits.merge(overrides, true)
	npc.occupation_id = occupation_id
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	npc.tier = occupation.tier if occupation != null else 1
	npc.home_room = DEFAULT_ROOM
	npc.current_room = DEFAULT_ROOM
	return npc


static func find_belief(result: Dictionary, holder: String, fact: String) -> Dictionary:
	for belief: Variant in result.get("beliefs", []):
		if belief is Dictionary and belief["holder"] == holder and belief["fact"] == fact:
			return belief
	return {}


static func material_of_kind(npc: NPCRuntime, kind: String) -> Dictionary:
	for entry: Dictionary in Blackmail.get_material(npc):
		if entry.get("kind", "") == kind:
			return entry
	return {}
