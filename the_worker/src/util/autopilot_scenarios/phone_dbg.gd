# phone_dbg.gd (escenario temporal) — depuración de maquetación del móvil.
# PROPIETARIO DE: nada.
# ESCUCHA: nada.
extends Node

func run(pilot: Autopilot) -> void:
	Database.load_all()
	PlayerState.reset_for_new_run()
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	await pilot.frames(3)
	ui.open_phone()
	await pilot.seconds(0.5)
	var phone: PhoneOverlay = ui.get_top_modal() as PhoneOverlay
	var dev: Control = phone.get_node("Device")
	print("overlay ", phone.size, " device ", dev.size, " screen ", dev.get_node("Screen").size, " min ", dev.get_node("Screen").get_combined_minimum_size())
	var col: Control = dev.get_node("Screen").get_child(0)
	print("col ", col.size, " ", col.position)
	for c in col.get_children():
		print("  child ", c.name, " ", c.size, " min ", c.get_combined_minimum_size())
	await pilot.shot("dbg")
