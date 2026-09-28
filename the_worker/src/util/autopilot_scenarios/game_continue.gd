# game_continue.gd (escenario) — «Continuar» en un proceso nuevo, como desde el menú: la partida guardada al dormir (game_evening) se carga y el jugador despierta en su piso con su aspecto de siempre.
# PROPIETARIO DE: nada (la escena de juego la monta GameLaunch.start_game como en el juego real).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_evening game_continue   (tras game_evening, que deja run.json)
## Registra el hash del aspecto del jugador: debe coincidir con el «morning: look=» de game_evening.
## Captura: continue_01_flat.

const SETTLE_FRAMES := 20


func run(pilot: Autopilot) -> void:
	if not SaveSystem.run_exists():
		push_error("game_continue: there is no saved run (play game_evening first)")
		return
	GameLaunch.prepare_load()
	if not GameLaunch.start_game(get_tree()):
		push_error("game_continue: the game scene does not exist")
		return
	await pilot.frames(SETTLE_FRAMES)
	var game: GameRoot = GameRoot.find(get_tree())
	if game == null:
		push_error("game_continue: GameRoot did not start")
		return
	print("[game_continue] mode=%s day=%d room=%s time=%s look=%d tier=%d name=%s" % [game.get_mode(), GameClock.get_day(),
			PlayerState.get_room(), GameClock.get_time_string(), hash(game.player.get_appearance()), game.player.get_tier(),
			PlayerState.get_player_name()])
	await pilot.shot("continue_01_flat")
