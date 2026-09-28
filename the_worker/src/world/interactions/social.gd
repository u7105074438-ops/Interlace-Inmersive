# social.gd — Módulo SOCIAL del InteractionRouter (BUILD_NOTES §15, §6.4, §8, §10.5, §11.1, §12.2, §13.7): E junto a un personaje abre el menú de conversación compacto (sin pausar el mundo).
# PROPIETARIO DE: nada (módulo estático; el menú abierto es de NPCInteractionMenu, el estado de juego de sus dueños y las marcas "social.*" de PlayerState).
# ESCUCHA: nada (al cargarse engancha SocialDeals.hook(): entrega en el mundo de los sobornos de mirar hacia otro lado y de préstamo).
class_name SocialInteractions
extends RefCounted

## Contrato del InteractionRouter: reclama "npc" (el interactivo invisible de cada NPCNode, data
## {npc_id}, room_id "" a propósito: la sala del personaje es NPCDirector.get_current_location).
## Conserva el apaño de _default.gd: la ficha rápida (§13.7 «tocar a un personaje») se abre desde
## la cabecera del menú (y E sobre un personaje que no puede hablar la abre directamente).
## Piezas privadas (los "_*" no son módulos del router):
##   SocialKit (_social_kit.gd) utilidades · SocialTalk (_social_talk.gd) réplicas por escalón,
##   charla, indicaciones, mérito regalado · SocialDeals (_social_deals.gd) favores a cuenta de la
##   deuda, préstamos, mirar hacia otro lado, delegación y entrega de sobornos · SocialLeverage
##   (_social_leverage.gd) chantaje e ideas · SocialRules (_social_rules.gd) opciones, rumores y
##   eliminación · SocialWorld (_social_world.gd) testigos, cámaras y la escena de la eliminación.
## Interfaz: src/ui/npc_interaction_menu.gd (NPCInteractionMenu). Mientras está abierto el mundo
## sigue (reloj en marcha, percepción activa: el jugador está expuesto); solo se bloquea el
## movimiento con el dueño "social_menu". E otra vez, Esc, alejarse o que el personaje se vaya lo
## cierran.

const TYPES: Array[String] = ["npc"]
const PROMPT := "UI_INTERACT_NPC"
const DATA_NPC := "npc_id"


static func _static_init() -> void:
	if not Engine.is_editor_hint():
		SocialDeals.hook()


static func handled_types() -> Array[String]:
	return TYPES.duplicate()


static func interact(interactable: Interactable, player: Node, ctx: Dictionary) -> void:
	var npc_id: String = str(interactable.data.get(DATA_NPC, ""))
	var ui: UIRoot = ctx.get("ui_root") as UIRoot
	var tree: SceneTree = interactable.get_tree() if interactable.is_inside_tree() else null
	if npc_id.is_empty() or tree == null:
		return
	var open: NPCInteractionMenu = NPCInteractionMenu.find(tree)
	if open != null and open.npc_id == npc_id:
		open.close()
		return
	if ui == null or not NPCDirector.is_active(npc_id) or _caught_window_open(ctx):
		_open_card(tree, npc_id)
		return
	NPCInteractionMenu.open(ui, npc_id, player as Node2D)


static func is_available(interactable: Interactable, _player: Node) -> bool:
	return NPCDirector.is_active(str(interactable.data.get(DATA_NPC, "")))


static func prompt_key(_interactable: Interactable) -> String:
	return PROMPT


## Con la ventana de flagrancia abierta manda CaughtHandler (§12.2): aquí solo la ficha.
static func _caught_window_open(ctx: Dictionary) -> bool:
	var root: GameRoot = ctx.get("game_root") as GameRoot
	var handler: CaughtHandler = root.sim_nodes.get("CaughtHandler") as CaughtHandler if root != null else null
	return handler != null and handler.is_window_open()


static func _open_card(tree: SceneTree, npc_id: String) -> void:
	var layer: NPCLayer = NPCLayer.find(tree)
	if layer != null:
		layer.open_card(npc_id)
	else:
		CharacterCard.open_for(tree, npc_id)
