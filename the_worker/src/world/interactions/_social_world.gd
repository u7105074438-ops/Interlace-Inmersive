# _social_world.gd — Lo que el módulo social pregunta al mundo: el nodo del personaje, la distancia de charla, quién más ve la escena (testigos y cámaras) y la escena de la eliminación resuelta por elipsis (fundido a negro + sonido, §3.1).
# PROPIETARIO DE: nada (consultas a NPCLayer / FloorStreamer / Perception / SecurityCamera; la capa del fundido vive lo que dura la escena).
# ESCUCHA: nada.
class_name SocialWorld
extends RefCounted

## TESTIGOS (§12.2, la regla de la flagrancia aplicada a la charla): cualquier OTRO personaje de la
## planta cuyo cono ve al jugador o a la víctima, o que está a social.eliminar.radio_testigo_celdas
## con línea de visión (aunque mire a otro lado: se giraría). Cuentan también los de LOD 1 (sin
## percepción activa): mejor de más que perder por un testigo invisible. CÁMARAS: activas que ven
## al jugador o a la víctima. El soborno en persona usa la misma lista (§8.2: testigos y cámaras).
## ESCENA (§3.1, nunca gráfica): fundido a negro (social.eliminar.fundido_segundos), GOLPE SECO
## (caught_thud, con subtítulo), el mundo cambia a oscuras (callback: retirada + cuerpo) y
## vuelve la imagen tras negro_segundos. Con SocialKit.qa_instant no espera.

const SFX_ELIMINATION := "caught_thud"
const FADE_LAYER := 90
const FADE_NAME := "SocialFade"
const LOCK_OWNER := "social_scene"
## Suelo técnico de un acto en QA (un acto de 0 s sería «hasta end_act()» en Player.begin_act).
const QA_ACT_SECONDS := 0.01


static func npc_node(tree: SceneTree, npc_id: String) -> NPCNode:
	var layer: NPCLayer = NPCLayer.find(tree) if tree != null else null
	return layer.get_node_for(npc_id) if layer != null else null


static func talk_range_px() -> float:
	return SocialKit.bf("distancia_charla_celdas") * RoomBuilder.cell_px()


## El personaje sigue en la planta y a distancia de charla del jugador.
static func in_range(player: Node2D, npc_id: String) -> bool:
	var node: NPCNode = npc_node(player.get_tree(), npc_id) if player != null and player.is_inside_tree() else null
	return node != null and NPCDirector.is_active(npc_id) \
			and node.global_position.distance_to(player.global_position) <= talk_range_px()


## {room_id, witnesses, cameras} ahora mismo (sin escena: nadie).
static func exposure(player: Node2D, npc_id: String) -> Dictionary:
	var env: Dictionary = {"room_id": PlayerState.get_room(), "witnesses": [] as Array[String], "cameras": [] as Array[String]}
	if player == null or not player.is_inside_tree():
		return env
	var streamer: FloorStreamer = FloorStreamer.find_in(player.get_tree())
	if streamer != null:
		var here: String = streamer.get_room_at(player.global_position)
		env["room_id"] = here if not here.is_empty() else env["room_id"]
	env["witnesses"] = witnesses(player, npc_id)
	env["cameras"] = cameras(player, npc_id, streamer)
	return env


static func witnesses(player: Node2D, npc_id: String) -> Array[String]:
	var out: Array[String] = []
	var layer: NPCLayer = NPCLayer.find(player.get_tree())
	if layer == null:
		return out
	var victim: NPCNode = layer.get_node_for(npc_id)
	var near: float = SocialKit.bf("eliminar.radio_testigo_celdas") * RoomBuilder.cell_px()
	for node: NPCNode in layer.get_nodes():
		var eyes: Perception = node.perception
		if node == victim or eyes == null or not eyes.is_inside_tree() or out.has(node.npc_id):
			continue
		if _sees(eyes, player.global_position, near) or (victim != null and eyes.sees_point(victim.global_position)):
			out.append(node.npc_id)
	return out


static func _sees(eyes: Perception, pos: Vector2, near: float) -> bool:
	if eyes.sees_point(pos):
		return true
	return eyes.global_position.distance_to(pos) <= near and eyes.has_line_of_sight(pos)


static func cameras(player: Node2D, npc_id: String, streamer: FloorStreamer) -> Array[String]:
	var out: Array[String] = []
	if streamer == null:
		return out
	var victim: NPCNode = npc_node(player.get_tree(), npc_id)
	for cam: SecurityCamera in streamer.get_cameras():
		if not cam.is_active():
			continue
		if cam.is_player_in_view(player.global_position) or (victim != null and cam.is_player_in_view(victim.global_position)):
			out.append(cam.camera_id)
	return out


# ─── Escena de la eliminación (§3.1) ──────────────────────────

## Fundido a negro → golpe seco → on_black (retirada, cuerpo) → vuelve la imagen.
static func play_elimination(player: Node2D, npc_id: String, on_black: Callable) -> void:
	var tree: SceneTree = player.get_tree()
	var node: NPCNode = npc_node(tree, npc_id)
	var at: Vector2 = node.global_position if node != null else player.global_position
	player.call("set_input_locked", true, LOCK_OWNER)
	var veil: CanvasLayer = _veil(tree)
	var rect: ColorRect = veil.get_child(0) as ColorRect
	await _fade(tree, rect, 1.0)
	SocialKit.sfx(SFX_ELIMINATION, at)
	on_black.call()
	if not SocialKit.qa_instant:
		await tree.create_timer(SocialKit.bf("eliminar.negro_segundos")).timeout
	await _fade(tree, rect, 0.0)
	veil.queue_free()
	if is_instance_valid(player):
		player.call("set_input_locked", false, LOCK_OWNER)


static func _veil(tree: SceneTree) -> CanvasLayer:
	var veil: CanvasLayer = CanvasLayer.new()
	veil.name = FADE_NAME
	veil.layer = FADE_LAYER
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(UITheme.color("ink"), 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(rect)
	tree.root.add_child(veil)
	return veil


static func _fade(tree: SceneTree, rect: ColorRect, alpha: float) -> void:
	if SocialKit.qa_instant:
		rect.color.a = alpha
		await tree.process_frame
		return
	var tween: Tween = rect.create_tween()
	tween.tween_property(rect, "color:a", alpha, SocialKit.bf("eliminar.fundido_segundos"))
	await tween.finished


## Acto visible de la eliminación: cualquiera que entre puede pillarlo (flagrancia), salvo la
## propia víctima, que es el blanco y no un testigo (su percepción calla mientras dura; ver
## REQUESTS: Perception debería ignorar al objetivo de un acto). true si se completó quieto.
static func act(player: Node, seconds: float, victim_id: String) -> bool:
	if player == null or not player.has_method("begin_act") or not player.is_inside_tree():
		return true
	var tree: SceneTree = player.get_tree()
	var state: Dictionary = {"done": false, "ok": false}
	var on_done: Callable = func(_crime: String, ok: bool) -> void:
		state["done"] = true
		state["ok"] = ok
	_mute_victim(tree, victim_id, true)
	player.call("begin_act", SocialRules.CRIME_ELIMINATION, QA_ACT_SECONDS if SocialKit.qa_instant else seconds)
	player.connect("act_finished", on_done, CONNECT_ONE_SHOT)
	while not bool(state["done"]) and is_instance_valid(player):
		_mute_victim(tree, victim_id, false)
		await tree.process_frame
	var node: NPCNode = npc_node(tree, victim_id)
	if node != null and node.perception != null:
		node.perception.set_active(node.lod == NPCRuntime.LOD_FULL)
	return bool(state["ok"])


## La víctima no se cuenta como testigo de su propia eliminación (la capa la reactiva al sincronizar).
static func _mute_victim(tree: SceneTree, victim_id: String, reset: bool) -> void:
	var node: NPCNode = npc_node(tree, victim_id)
	if node == null or node.perception == null:
		return
	if reset:
		node.perception.reset_contact()
	node.perception.set_active(false)
