# qa_core_loop_access.gd (escenario QA) — Accesos especiales por ocupación (§5.2): para cada puesto-llave compara lo que el MAPA pinta como permitido (MapView.is_room_allowed) con lo que la PUERTA deja pasar (DoorAccess.allows) en las plantas relevantes.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/qa_access qa_core_loop_access
## Imprime "[qa_core_loop_access] MISMATCH <puesto> <sala> map=<bool> door=<bool>" por cada desacuerdo y
## "FAIL" cuando el manual promete un acceso que ninguna de las dos capas concede.

const TAG := "[qa_core_loop_access]"
const SHORT_FRAMES := 6
## puesto → plantas a recorrer.
const CASES: Dictionary = {
	"order_filer": [2],
	"copy_operator": [1, 3],
	"line_operator": [100],
	"mail_courier": [1, 5, 9],
	"maintenance_aide": [-1, -2, -3],
	"cleaner": [3, 10],
	"security_guard": [5, 10, 13, 16],
	"hr_assistant": [1],
	"it_technician": [-2, 8],
}
## Promesas del manual §5.2 (puesto → salas que debe poder abrir).
const PROMISES: Dictionary = {
	"order_filer": ["orders_archive"],
	"copy_operator": ["main_copyroom"],
	"maintenance_aide": ["forgotten_corridor", "boiler_room", "dead_archive", "server_room"],
	"security_guard": ["accounting", "a10_general_office", "treasury", "trading_room"],
	"mail_courier": ["accounting", "legal_firm"],
	"cleaner": ["wing_3a", "a10_general_office"],
}

var _game: GameRoot = null


func run(pilot: Autopilot) -> void:
	GameLaunch.prepare_new_run("Access Tester", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		print("%s FAIL game did not start" % TAG)
		return
	await pilot.frames(SHORT_FRAMES)
	_game = GameRoot.find(get_tree())
	GameClock.advance_minutes(20.0 * 60.0 - GameClock.get_day_minutes())
	await pilot.frames(SHORT_FRAMES)
	var granted: Dictionary = {}
	for occ: String in CASES:
		PlayerState.set_occupation(occ, "qa")
		await pilot.frames(2)
		granted[occ] = []
		for f: int in CASES[occ]:
			_game.travel.teleport(f, _game.streamer.get_floor_rect_px().get_center())
			await pilot.frames(SHORT_FRAMES)
			var ctx: Dictionary = MapView.player_access_context()
			for door: Door in _game.streamer.get_doors():
				var room: RoomData = Database.get_room(DatabaseSystem.get_room_base_id(door.room_b))
				if room == null:
					continue
				var on_map: bool = MapView.is_room_allowed(room, ctx)
				var opens: bool = DoorAccess.allows(door)
				if opens:
					(granted[occ] as Array).append(room.id)
				if on_map != opens:
					print("%s MISMATCH %s %s(N%d %s) map=%s door=%s" % [TAG, occ, room.id, room.clearance_required,
							str(room.special_access), str(on_map), str(opens)])
		for promised: String in PROMISES.get(occ, []):
			var room2: RoomData = Database.get_room(promised)
			var ok: bool = (granted[occ] as Array).has(promised) or (room2 != null and MapView.is_room_allowed(room2, MapView.player_access_context()))
			print("%s %s %s promised §5.2 %s -> %s (door opened: %s)" % [TAG, "PASS" if ok else "FAIL", occ, promised,
					str(ok), str((granted[occ] as Array).has(promised))])
	await pilot.shot("qa_access_done")
	print("%s DONE" % TAG)
