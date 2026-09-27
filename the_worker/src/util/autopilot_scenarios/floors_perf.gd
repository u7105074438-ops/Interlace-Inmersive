# floors_perf.gd (escenario) — Coste de dibujo de cada planta por capas (PASO 40), sin capturas útiles.
# PROPIETARIO DE: los nodos temporales del escenario (streamer, cámara).
# ESCUCHA: nada.
extends Node

## tools/screenshot.sh /tmp/shots_floors_perf floors_perf → <dir>/perf.txt
## Por planta, a vista completa y a zoom de juego (1 celda = 48 px): llamadas de dibujo, primitivas
## y ms por fotograma con todo y ocultando por turnos fondo, suelos, muros, luz, muebles y sombra.

const FLOORS: Array[int] = [3, 2, 0, -1, -2, 20, 100, 200]
const FRAMES := 10
const LAYERS: Array[String] = ["Backdrop", "Floor_", "Walls_", "Light_", "Props", "Shade", "Door_", "Cam_", "I_"]

var _out: PackedStringArray = []


func run(pilot: Autopilot) -> void:
	Database.load_all()
	var scene: Node = get_tree().current_scene
	if scene is CanvasItem:
		(scene as CanvasItem).visible = false
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	for f: int in FLOORS:
		streamer.load_floor(f)
		var rect: Rect2 = streamer.get_floor_rect_px()
		var view: Vector2 = get_viewport().get_visible_rect().size
		var fit: float = minf(view.x / rect.size.x, view.y / rect.size.y)
		cam.position = rect.get_center()
		for zoom: float in [fit, 1.0]:
			cam.zoom = Vector2(zoom, zoom)
			await _measure(pilot, streamer, "F%d z%.2f" % [f, zoom])
	var file: FileAccess = FileAccess.open(str(pilot.get_args().get("shots", "user://")) + "/perf.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_out))
	await pilot.shot("perf_done")


func _measure(pilot: Autopilot, streamer: FloorStreamer, label: String) -> void:
	var line: String = "%s all=%s" % [label, await _sample(pilot)]
	for layer: String in LAYERS:
		var hidden: Array[CanvasItem] = _hide(streamer, layer)
		line += " | -%s %s" % [layer, await _sample(pilot)]
		for item: CanvasItem in hidden:
			item.visible = true
	_out.append(line)
	print("[perf] ", line)


func _sample(pilot: Autopilot) -> String:
	await pilot.frames(3)
	var start: int = Time.get_ticks_usec()
	await pilot.frames(FRAMES)
	var ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / FRAMES
	return "d%d p%d %.0fms" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), ms]


## Oculta los CanvasItem cuyo nombre empieza por `prefix` (y el nodo de muebles si es "Props").
func _hide(streamer: FloorStreamer, prefix: String) -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	if prefix == "Props":
		var props: CanvasItem = streamer.get_actor_layer().get_child(0) as CanvasItem
		props.visible = false
		out.append(props)
		return out
	for node: Node in streamer.find_children(prefix + "*", "CanvasItem", true, false):
		var item: CanvasItem = node as CanvasItem
		var painter_layer: bool = prefix in ["Floor_", "Walls_", "Light_"]
		if painter_layer and not (item is RoomPainter):
			continue
		if item.visible:
			item.visible = false
			out.append(item)
	return out
