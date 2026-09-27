# boot.gd (escenario) — Captura la pantalla de arranque.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends Node


func run(pilot: Autopilot) -> void:
	await pilot.frames(10)
	await pilot.shot("boot")
