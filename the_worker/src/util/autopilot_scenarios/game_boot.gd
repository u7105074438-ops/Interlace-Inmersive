# game_boot.gd (escenario) — Los primeros instantes de una partida nueva: el alta pedida como lo hace el menú, la escena de juego y el jugador en los tornos de la PB a las 8:00.
# PROPIETARIO DE: nada (la escena de juego la monta GameLaunch.start_game como en el juego real).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_game_boot game_boot [--seed=N --force-rank=N]
## Capturas: game_boot_first (primer fotograma estable), game_boot_settled (segundos después: la
## gente llega), game_boot_turnstile (el jugador ante el torno, con la indicación contextual) y
## game_boot_pause (menú de pausa con Esc).

const PLAYER_NAME := "Alex Doe"
const DIFFICULTY := "estandar"
const FIRST_FRAMES := 12
const SETTLE_SECONDS := 2.5
const WALK_SECONDS := 0.9
const MENU_FRAMES := 10


func run(pilot: Autopilot) -> void:
	GameLaunch.prepare_new_run(PLAYER_NAME, DIFFICULTY, true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("game_boot: the game scene does not exist")
		return
	await pilot.frames(FIRST_FRAMES)
	var game: GameRoot = GameRoot.find(get_tree())
	if game == null:
		push_error("game_boot: GameRoot did not start")
		return
	print("[game_boot] mode=%s floor=%d room=%s time=%s seed=%d" % [game.get_mode(), game.streamer.get_current_floor(),
			PlayerState.get_room(), GameClock.get_time_string(), GameClock.get_run_seed()])
	await pilot.shot("game_boot_first")
	await pilot.seconds(SETTLE_SECONDS)
	await pilot.shot("game_boot_settled")
	await pilot.press("move_down", WALK_SECONDS)
	await pilot.frames(MENU_FRAMES)
	await pilot.shot("game_boot_turnstile")
	game.open_pause_menu()
	await pilot.frames(MENU_FRAMES)
	await pilot.shot("game_boot_pause")
	game.ui.close_modal()
	await pilot.frames(2)
