# floor_travel.gd — Viaje entre plantas (§5.2-§5.5, §22.15): ascensores, escaleras, escalera de servicio, montacargas, conductos, cornisas y salidas; panel de destino, reglas, coste de tiempo y trayecto.
# PROPIETARIO DE: el trayecto en curso (bloqueo del jugador, fundido, panel abierto) y el RNG de los encuentros en la escalera de servicio.
# ESCUCHA: run_started, run_loaded (resiembra el RNG de encuentros); InteractionRouter le entrega los interactivos de tránsito.
class_name FloorTravel
extends Node

## Módulo del InteractionRouter (BUILTIN_MODULES) para los tipos de TYPE_KINDS y nodo de la escena de
## juego (GameRoot lo añade y llama setup(streamer, player)). API pública:
##   use(interactable) (await: reglas → panel de destino → trayecto) · destinations_for(interactable)
##   refusal_for(interactable) · travel_to(interactable, destino, prisa) (await) · is_busy()
##   teleport_to_room(sala, celdas := (-1,-1)) · teleport(planta, punto) · refresh_camera()
##   static kind_of(interactable) · card_opens_floor(planta) · travel_minutes(tipo, plantas, prisa, hora_punta)
## Destino = {floor, room_id, transit_id, label, allowed, clearance}; el panel lo elige el jugador.
## REGLAS (balance viaje.*):
##  · ASCENSOR: lector de tarjeta por planta (§5.2): solo las plantas que el mapa pinta en verde
##    (MapView.floor_access = permitido); el resto salen con candado y la acreditación que piden y
##    pulsarlas pita en rojo (card_denied). Cada viaje queda en el registro (Security.log_card_access
##    → card_reader_logged) y la cámara de la cabina graba al entrar (SecurityCamera). Campana al
##    llegar (AudioDirector). Rápido: minutos_base + minutos_por_planta × plantas.
##  · ESCALERA PRINCIPAL: sin lector; cámara en el rellano; en las franjas busy_bands de su sala
##    (entrada y salida) va llena: × factor_hora_punta.
##  · ESCALERA DE SERVICIO: sin cámara ni registro, lenta. Coincidir con alguien
##    (prob_encuentro_por_planta × plantas, tope prob_encuentro_max, en franjas_encuentro, salvo con
##    disfraces_justificados) = player_seen_partially(testigo, certeza_encuentro) + aviso.
##  · MONTACARGAS: solo sus paradas; exige la acreditación de su sala, un acceso especial suyo o
##    una de sus llaves; ruidoso (noise_emitted "freight_elevator" en origen y destino con el
##    noise_radius del panel). Único medio con un cuerpo a rastras u objetos voluminosos
##    (InventoryRules.is_bulky): ascensor, escaleras, conductos y cornisas lo rechazan.
##  · CONDUCTOS: entrar exige un aseo (entrada ilegítima §5.3), acceso especial de mantenimiento, su
##    uniforme o la llave de conductos. Colarse es un acto visible (begin_act "trespass"). Muy
##    lentos; «deprisa» = × factor_prisa con ruido (radio_ruido_prisa) al entrar y al salir.
##    Destino: cualquier trampilla de otra sala (lista por planta y sala).
##  · CORNISAS (roof_ledge): P19 ↔ P20 ↔ azotea según leads_to; minutos fijos; acto visible.
##  · SALIDAS (exit): destino único, sin panel. Por el control (control_salida.salas) hacia
##    control_salida.planta, si Security.can_search_player() el vigilante registra antes de salir
##    (InventoryRules.perform_body_search; el resultado se avisa).
##  · TRAYECTO CASA ↔ TRABAJO (§4.2, viaje.trayecto.*): la salida de recepción (puertas_edificio) a la
##    calle ofrece «Volver a casa (N min)», «Salir a la calle» o cancelar; en el piso, junto a su puerta,
##    WorldBridges pone el interactivo COMMUTE_TYPE («Ir al trabajo», use_commute). El trayecto cobra
##    HomeCycle.commute() (hogar.minutos_trayecto_casa) y deja al jugador dentro de recepción junto a
##    su puerta a la calle, o dentro del piso junto a la suya (home_door_point). Andar por la calle
##    no cobra nada más: el paseo ya es el tiempo del trayecto.
##  · CIERRE (ClosingTime): si durante un trayecto dan las 19:00 con el jugador dentro, tras avanzar el
##    reloj se llama a ClosingTime.resolve_during_travel(): si el destino está dentro, sale a la calle.
##  · place_outside_building(fundido): la calle ante la puerta de recepción (desalojo del cierre).
## Nunca emite floor_changed ni room_entered (FloorStreamer los emite al cargar y al pisar la sala).
## load_floor se llama tras un await (nunca dentro de una señal de física).

signal travel_started(kind: String, from_floor: int, to_floor: int)
signal travel_finished(kind: String, floor_number: int, room_id: String)

const GROUP := "floor_travel"
const KIND_LEDGE := "ledge"
const TYPE_KINDS: Dictionary = {
	"elevator_panel": FloorLayout.TRANSIT_ELEVATOR, "stairs_door": FloorLayout.TRANSIT_STAIRS,
	"service_stairs_door": FloorLayout.TRANSIT_SERVICE_STAIRS, "freight_panel": FloorLayout.TRANSIT_FREIGHT,
	"vent_hatch": FloorLayout.TRANSIT_VENT, "roof_ledge": KIND_LEDGE, "exit": FloorLayout.TRANSIT_EXIT,
}
## Tipo de trayecto → sección de balance viaje.<sección>.
const KIND_SECTIONS: Dictionary = {
	FloorLayout.TRANSIT_ELEVATOR: "ascensor", FloorLayout.TRANSIT_STAIRS: "escalera",
	FloorLayout.TRANSIT_SERVICE_STAIRS: "escalera_servicio", FloorLayout.TRANSIT_FREIGHT: "montacargas",
	FloorLayout.TRANSIT_VENT: "conducto", KIND_LEDGE: "cornisa", FloorLayout.TRANSIT_EXIT: "salida",
}
## Icono (UITheme.draw_icon) del fundido de cada trayecto.
const KIND_ICONS: Dictionary = {
	FloorLayout.TRANSIT_ELEVATOR: "elevator", FloorLayout.TRANSIT_STAIRS: "stairs",
	FloorLayout.TRANSIT_SERVICE_STAIRS: "stairs", FloorLayout.TRANSIT_FREIGHT: "box",
	FloorLayout.TRANSIT_VENT: "sneak", KIND_LEDGE: "crouch", FloorLayout.TRANSIT_EXIT: "door",
}
## Trayectos que admiten cuerpos u objetos voluminosos.
const BULK_KINDS: Array[String] = [FloorLayout.TRANSIT_FREIGHT, FloorLayout.TRANSIT_EXIT]
## Trayectos que son un acto visible (colarse por un conducto, salir por una ventana).
const ACT_KINDS: Array[String] = [FloorLayout.TRANSIT_VENT, KIND_LEDGE]
## Paneles en rejilla de plantas; el resto (conductos, cornisas) en lista de salas.
const GRID_KINDS: Array[String] = [FloorLayout.TRANSIT_ELEVATOR, FloorLayout.TRANSIT_STAIRS,
	FloorLayout.TRANSIT_SERVICE_STAIRS, FloorLayout.TRANSIT_FREIGHT]
const LEDGE_TYPE := "roof_ledge"
## Puerta «ir al trabajo» del piso (la crea WorldBridges al cargar la planta exterior).
const COMMUTE_TYPE := "commute_door"
const K_ZONE := "zone"
const ACT_CRIME := "trespass"
const PLAYER_CARD := "player"
const CAMERA_NODE := "Camera"
const NOISE_FREIGHT := "freight_elevator"
const NOISE_VENT := "vent_crawl"
const SFX_DENIED := "card_denied"
const K_TRANSIT := "transit"
const K_TARGETS := "targets"
const K_TARGET_ROOM := "target_room"
const K_LEADS_TO := "leads_to"
const K_NOISE := "noise_radius"
const K_BUSY := "busy_bands"
const PACE_CAREFUL := 0
const PACE_HURRY := 1
const B_PREFIX := "viaje."
const B_MIN_BASE := ".minutos_base"
const B_MIN_FLOOR := ".minutos_por_planta"
const B_RUSH := "viaje.escalera.factor_hora_punta"
const B_HURRY := "viaje.conducto.factor_prisa"
const B_VENT_NOISE := "viaje.conducto.radio_ruido_prisa"
const B_VENT_ACT := "viaje.conducto.segundos_acto"
const B_VENT_TOILETS := "viaje.conducto.patron_aseos"
const B_VENT_ACCESS := "viaje.conducto.accesos_especiales"
const B_VENT_UNIFORMS := "viaje.conducto.disfraces"
const B_VENT_KEYS := "viaje.conducto.llaves"
const B_LEDGE_ACT := "viaje.cornisa.segundos_acto"
const B_FREIGHT_ROOM := "viaje.montacargas.sala"
const B_FREIGHT_KEYS := "viaje.montacargas.llaves"
const B_FREIGHT_NOISE := "viaje.montacargas.radio_ruido"
const B_SERVICE := "viaje.escalera_servicio."
const B_CHECK_ROOMS := "viaje.control_salida.salas"
const B_CHECK_FLOOR := "viaje.control_salida.planta"
const B_FACTORY := "mundo.planta_fabrica"
const B_RNG_SALT := "viaje.semilla_encuentros"
const B_STREET := "viaje.trayecto.sala_calle"
const B_ENTRANCE := "viaje.trayecto.entrada_edificio"
const B_BUILDING_DOORS := "viaje.trayecto.puertas_edificio"
const B_HOME := "hogar.sala_domicilio"
const B_COMMUTE := "hogar.minutos_trayecto_casa"
const B_EXTERIOR := "mundo.planta_exterior"
const K_COMMUTE := "commute"
const ZONE_WORK := "work"
const ZONE_HOME := "home"
const COMMUTE_KIND := "commute"
const COMMUTE_ICON := "door"
const COMMUTE_GO := 0
const COMMUTE_STREET := 1
## Dueño del bloqueo de entrada del jugador durante un trayecto (Player.set_input_locked).
const LOCK_OWNER := "floor_travel"

## Pruebas y QA: sin fundidos ni esperas reales.
var instant: bool = false
var _streamer: FloorStreamer = null
var _player: Node2D = null
var _overlay: TravelOverlay = null
var _panel: FloorSelectPanel = null
var _busy: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_overlay = TravelOverlay.new()
	_overlay.name = "TravelOverlay"
	add_child(_overlay)
	_reseed()
	EventBus.run_started.connect(func(_seed: int) -> void: _reseed())
	EventBus.run_loaded.connect(func(_day: int) -> void: _reseed())


## Semilla de la partida (nueva o cargada) y la jornada: una partida continuada no repite encuentros.
func _reseed() -> void:
	_rng.seed = hash([GameClock.get_run_seed(), GameClock.get_day(), Database.get_balance_int(B_RNG_SALT)])


func setup(streamer: FloorStreamer, player: Node2D) -> void:
	_streamer = streamer
	_player = player


static func find(tree: SceneTree) -> FloorTravel:
	return tree.get_first_node_in_group(GROUP) as FloorTravel if tree != null else null


func is_busy() -> bool:
	return _busy


func get_panel() -> FloorSelectPanel:
	return _panel if _panel != null and is_instance_valid(_panel) else null


# ─── Contrato de módulo (InteractionRouter) ───────────────────

static func handled_types() -> Array[String]:
	var out: Array[String] = [COMMUTE_TYPE]
	for interact_type: String in TYPE_KINDS:
		out.append(interact_type)
	return out


static func interact(interactable: Interactable, _player_node: Node, ctx: Dictionary) -> void:
	var travel: FloorTravel = find(interactable.get_tree()) if interactable.is_inside_tree() else null
	if travel == null:
		var ui: UIRoot = ctx.get("ui_root") as UIRoot
		if ui != null:
			ui.toast("TRAVEL_UNAVAILABLE", [], ToastStack.KIND_WARN)
		return
	if interactable.interact_type == COMMUTE_TYPE:
		await travel.use_commute(str(interactable.data.get(K_ZONE, ZONE_WORK)))
		return
	await travel.use(interactable)


static func kind_of(interactable: Interactable) -> String:
	return str(TYPE_KINDS.get(interactable.interact_type, ""))


# ─── Uso completo ─────────────────────────────────────────────

## Reglas → elección de destino → trayecto. No hace nada si ya hay un trayecto en curso.
func use(item: Interactable) -> void:
	if _busy or item == null or _streamer == null or _player == null:
		return
	var refusal: Dictionary = refusal_for(item)
	if not refusal.is_empty():
		_refuse(str(refusal["key"]), refusal.get("args", []))
		return
	var choice: Dictionary = await choose_destination(item)
	if choice.is_empty():
		return
	await travel_to(item, choice, bool(choice.get("hurry", false)))


## Motivo por el que no se puede usar ahora ({} = se puede): {key, args}.
func refusal_for(item: Interactable) -> Dictionary:
	var kind: String = kind_of(item)
	if not BULK_KINDS.has(kind) and _carrying_bulk():
		return {"key": "TRAVEL_REFUSE_BULKY", "args": []}
	if kind == FloorLayout.TRANSIT_FREIGHT and not freight_allowed():
		return {"key": "TRAVEL_REFUSE_FREIGHT", "args": [freight_clearance()]}
	if kind == FloorLayout.TRANSIT_VENT and not can_enter_vent(item.room_id):
		return {"key": "TRAVEL_REFUSE_VENT", "args": []}
	return {}


## Panel de destino (y ritmo en los conductos). {} = cancelado.
func choose_destination(item: Interactable) -> Dictionary:
	var kind: String = kind_of(item)
	var options: Array[Dictionary] = destinations_for(item)
	if options.is_empty():
		_refuse("TRAVEL_NO_DESTINATION", [])
		return {}
	if kind == FloorLayout.TRANSIT_EXIT:
		var zone: String = commute_zone_for(item, options[0])
		return options[0] if zone.is_empty() else await _pick_commute(options[0], zone)
	var picked: Dictionary = await _pick(item, kind, options)
	if picked.is_empty() or kind != FloorLayout.TRANSIT_VENT:
		return picked
	return await _pick_pace(picked)


func _pick(item: Interactable, kind: String, options: Array[Dictionary]) -> Dictionary:
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui == null:
		return {}
	_panel = FloorSelectPanel.new()
	_panel.setup(_panel_title(item, kind), _panel_hint(kind), options, GRID_KINDS.has(kind), _preferred_index(options))
	ui.open_modal(_panel, false)
	var picked: Dictionary = {}
	while picked.is_empty() and is_instance_valid(_panel) and _panel.is_inside_tree():
		var index: int = await _panel.chosen
		if index < 0 or index >= options.size():
			break
		if bool(options[index]["allowed"]):
			picked = options[index]
		else:
			_deny_card(options[index])
			_panel.flash_denied(index)
	if is_instance_valid(_panel):
		ui.close_modal_control(_panel)
	_panel = null
	return picked


## Botón con el foco al abrir: la planta del despacho propio si se puede ir; si no, la permitida
## más cercana a la actual.
func _preferred_index(options: Array[Dictionary]) -> int:
	var occupation: OccupationData = PlayerState.get_occupation()
	var office: RoomData = Database.get_room(occupation.office_room) if occupation != null else null
	var here: int = _streamer.get_current_floor()
	var best: int = -1
	var best_d: int = 1 << 20
	for i: int in options.size():
		if not bool(options[i]["allowed"]):
			continue
		var f: int = int(options[i]["floor"])
		if office != null and f == office.floor:
			return i
		if floor_distance(f, here) < best_d:
			best_d = floor_distance(f, here)
			best = i
	return best


func _pick_pace(dest: Dictionary) -> Dictionary:
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui == null:
		return dest
	var floors: int = floor_distance(_streamer.get_current_floor(), int(dest["floor"]))
	var careful: int = roundi(travel_minutes(FloorLayout.TRANSIT_VENT, floors))
	var hurry: int = roundi(travel_minutes(FloorLayout.TRANSIT_VENT, floors, true))
	var options: Array = [{"text_key": "TRAVEL_VENT_CAREFUL", "args": [careful]},
			{"text_key": "TRAVEL_VENT_HURRY", "args": [hurry]}, "UI_CANCEL"]
	var index: int = await ui.show_dialog("TRAVEL_VENT_PACE_TITLE", "TRAVEL_VENT_PACE_BODY", options, [], false)
	if index != PACE_CAREFUL and index != PACE_HURRY:
		return {}
	return dest.merged({"hurry": index == PACE_HURRY}, true)


## Puerta del piso «ir al trabajo» (o «volver a casa» si algún día hay otra): confirmación y trayecto.
func use_commute(zone: String) -> void:
	if _busy or _streamer == null or _player == null:
		return
	if _carrying_bulk():
		_refuse("TRAVEL_REFUSE_BULKY", [])
		return
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui != null and not instant:
		var suffix: String = zone.to_upper()
		var options: Array = [{"text_key": "TRAVEL_COMMUTE_GO_" + suffix, "args": [Database.get_balance_int(B_COMMUTE)],
				"icon": COMMUTE_ICON}, "UI_CANCEL"]
		if await ui.show_dialog("TRAVEL_COMMUTE_TITLE_" + suffix, "TRAVEL_COMMUTE_BODY_DOOR", options, [], false) != COMMUTE_GO:
			return
	_busy = true
	await _ride_commute(zone)
	_busy = false
	travel_finished.emit(COMMUTE_KIND, _streamer.get_current_floor(), _streamer.get_room_at(_player.global_position))


## Salida con trayecto: "work" (del piso a la calle), "home" (de recepción a la calle) o "".
static func commute_zone_for(item: Interactable, dest: Dictionary) -> String:
	if str(dest.get("room_id", "")) != str(Database.get_balance(B_STREET)):
		return ""
	var base: String = DatabaseSystem.get_room_base_id(item.room_id)
	if base == str(Database.get_balance(B_HOME)):
		return ZONE_WORK
	if (Database.get_balance(B_BUILDING_DOORS) as Array).has(base):
		return ZONE_HOME
	return ""


## Trayecto (ir al trabajo / volver a casa), salir a la calle o cancelar ({}).
func _pick_commute(dest: Dictionary, zone: String) -> Dictionary:
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui == null:
		return dest
	var suffix: String = zone.to_upper()
	var options: Array = [{"text_key": "TRAVEL_COMMUTE_GO_" + suffix, "args": [Database.get_balance_int(B_COMMUTE)],
			"icon": COMMUTE_ICON}, "TRAVEL_COMMUTE_STREET", "UI_CANCEL"]
	var index: int = await ui.show_dialog("TRAVEL_COMMUTE_TITLE_" + suffix, "TRAVEL_COMMUTE_BODY", options, [], false)
	if index == COMMUTE_GO:
		return dest.merged({K_COMMUTE: zone}, true)
	return dest if index == COMMUTE_STREET else {}


# ─── Destinos ─────────────────────────────────────────────────

## Destinos ofrecidos por el interactivo (orden de presentación: de arriba abajo).
func destinations_for(item: Interactable) -> Array[Dictionary]:
	var kind: String = kind_of(item)
	match kind:
		FloorLayout.TRANSIT_VENT:
			return _vent_destinations(item)
		KIND_LEDGE:
			return _ledge_destinations(item)
		FloorLayout.TRANSIT_EXIT:
			return _exit_destinations(item)
	return _floor_destinations(item, kind)


func _floor_destinations(item: Interactable, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx: Dictionary = MapView.player_access_context()
	for f: int in _targets_of(item):
		var allowed: bool = kind != FloorLayout.TRANSIT_ELEVATOR \
				or MapView.floor_access(f, ctx) == MapView.ACCESS_ALLOWED
		out.append(make_destination(f, "", "", MapView.floor_label_short(f), allowed, required_clearance(f)))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["floor"]) > int(b["floor"]))
	return out


func _vent_destinations(item: Interactable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: RoomData in Database.get_all_rooms():
		if room.is_transversal():
			continue
		for entry: Dictionary in room.interactables:
			if str(entry["type"]) != item.interact_type or str(entry["id"]) == item.interact_id:
				continue
			out.append(make_destination(room.floor, room.id, str(entry["id"]), _room_label(room), true, 0))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["floor"]) > int(b["floor"]) or (int(a["floor"]) == int(b["floor"]) and str(a["label"]) < str(b["label"])))
	return out


func _ledge_destinations(item: Interactable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value: Variant in item.data.get(K_LEADS_TO, []):
		var room: RoomData = Database.get_room(str(value))
		if room != null:
			out.append(make_destination(room.floor, room.id, "", _room_label(room), true, 0))
	return out


func _exit_destinations(item: Interactable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var targets: Array[int] = _targets_of(item)
	if targets.is_empty():
		return out
	var target_room: String = str(item.data.get(K_TARGET_ROOM, item.data.get(K_TRANSIT, {}).get(K_TARGET_ROOM, "")))
	var room: RoomData = Database.get_room(target_room)
	var label: String = _room_label(room) if room != null else MapView.floor_name(targets[0])
	out.append(make_destination(targets[0], target_room, "", label, true, 0))
	return out


static func make_destination(floor_number: int, room_id: String, transit_id: String, label: String,
		allowed: bool, clearance: int) -> Dictionary:
	return {"floor": floor_number, "room_id": room_id, "transit_id": transit_id, "label": label,
			"allowed": allowed, "clearance": clearance}


func _targets_of(item: Interactable) -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = item.data.get(K_TRANSIT, {}).get(K_TARGETS, item.data.get(K_TARGETS, []))
	for value: Variant in raw:
		out.append(int(value))
	return out


static func _room_label(room: RoomData) -> String:
	return "%s · %s" % [MapView.floor_label_short(room.floor), TranslationServer.translate(room.name_key)]


# ─── Reglas ───────────────────────────────────────────────────

## §5.2: el lector del ascensor abre las plantas que el mapa da como permitidas.
static func card_opens_floor(floor_number: int) -> bool:
	return MapView.floor_access(floor_number, MapView.player_access_context()) == MapView.ACCESS_ALLOWED


## Acreditación mínima que abre alguna sala propia de la planta (para el candado del panel).
static func required_clearance(floor_number: int) -> int:
	var best: int = -1
	for room: RoomData in MapView.floor_rooms(floor_number):
		if best < 0 or room.clearance_required < best:
			best = room.clearance_required
	return maxi(best, 0)


static func floor_distance(a: int, b: int) -> int:
	var factory: int = Database.get_balance_int(B_FACTORY)
	if a >= factory or b >= factory:
		return 1
	return absi(a - b)


## Minutos de juego del trayecto (balance viaje.<sección>).
static func travel_minutes(kind: String, floors: int, hurry: bool = false, rush: bool = false) -> float:
	var section: String = B_PREFIX + str(KIND_SECTIONS.get(kind, ""))
	var minutes: float = Database.get_balance_float(section + B_MIN_BASE) \
			+ Database.get_balance_float(section + B_MIN_FLOOR) * maxi(floors, 1)
	if hurry:
		minutes *= Database.get_balance_float(B_HURRY)
	if rush:
		minutes *= Database.get_balance_float(B_RUSH)
	return minutes


func freight_allowed() -> bool:
	var room: RoomData = Database.get_room(str(Database.get_balance(B_FREIGHT_ROOM)))
	if room == null or PlayerState.get_clearance() >= room.clearance_required:
		return true
	var occupation: OccupationData = PlayerState.get_occupation()
	for tag: String in room.special_access:
		if occupation != null and occupation.special_access.has(tag):
			return true
	return _carries_any(Database.get_balance(B_FREIGHT_KEYS))


func freight_clearance() -> int:
	var room: RoomData = Database.get_room(str(Database.get_balance(B_FREIGHT_ROOM)))
	return room.clearance_required if room != null else 0


## §5.3: por un aseo (entrada ilegítima), con acceso de mantenimiento, su uniforme o su llave.
func can_enter_vent(room_id: String) -> bool:
	if DatabaseSystem.get_room_base_id(room_id).contains(str(Database.get_balance(B_VENT_TOILETS))):
		return true
	var occupation: OccupationData = PlayerState.get_occupation()
	for tag: Variant in Database.get_balance(B_VENT_ACCESS):
		if occupation != null and occupation.special_access.has(str(tag)):
			return true
	if (Database.get_balance(B_VENT_UNIFORMS) as Array).has(PlayerState.get_disguise()):
		return true
	return _carries_any(Database.get_balance(B_VENT_KEYS))


func _carrying_bulk() -> bool:
	if _player != null and _player.has_method("is_dragging") and bool(_player.call("is_dragging")):
		return true
	for item: ItemData in PlayerState.get_inventory():
		if InventoryRules.is_bulky(item):
			return true
	return false


static func _carries_any(ids: Variant) -> bool:
	if not ids is Array:
		return false
	for value: Variant in ids:
		if PlayerState.is_carrying(str(value)):
			return true
	return false


func _is_rush(item: Interactable, kind: String) -> bool:
	if kind != FloorLayout.TRANSIT_STAIRS:
		return false
	var room: RoomData = Database.get_room(item.room_id)
	return room != null and (room.extra.get(K_BUSY, []) as Array).has(GameClock.get_current_band())


# ─── Trayecto ─────────────────────────────────────────────────

## Ejecuta el trayecto hasta `dest` (acto visible, registros, fundido, reloj, llegada, efectos). El
## interactivo se libera al cambiar de planta: todo lo que hace falta se copia antes (source_of).
## dest[K_COMMUTE] ("work"/"home"): trayecto casa ↔ trabajo en lugar de salir a la calle.
func travel_to(item: Interactable, dest: Dictionary, hurry: bool = false) -> void:
	if _busy or item == null or not is_instance_valid(item):
		return
	if not bool(dest.get("allowed", true)):
		_deny_card(dest)
		return
	_busy = true
	var src: Dictionary = source_of(item)
	var ready_to_go: bool = await _enter_act(str(src["kind"]))
	if ready_to_go:
		ready_to_go = await _checkpoint(src, dest)
	if not ready_to_go:
		_busy = false
		return
	if dest.has(K_COMMUTE):
		await _ride_commute(str(dest[K_COMMUTE]))
	else:
		await _ride(src, dest, hurry)
	_busy = false
	travel_finished.emit(str(src["kind"]), _streamer.get_current_floor(), _streamer.get_room_at(_player.global_position))


func _ride(src: Dictionary, dest: Dictionary, hurry: bool) -> void:
	var kind: String = str(src["kind"])
	var from_floor: int = _streamer.get_current_floor()
	var minutes: float = travel_minutes(kind, floor_distance(from_floor, int(dest["floor"])), hurry, bool(src["rush"]))
	_set_locked(true)
	_depart(src, dest, hurry)
	travel_started.emit(kind, from_floor, int(dest["floor"]))
	await _overlay.play_in(str(KIND_ICONS.get(kind, "door")), from_floor, int(dest["floor"]),
			_caption(kind, dest, minutes), GRID_KINDS.has(kind), instant)
	GameClock.advance_minutes(minutes)
	if not _closing_intercepts(str(dest.get("room_id", "")), int(dest["floor"])):
		_arrive(src, dest)
		_after_arrival(src, dest, hurry, from_floor)
	await _overlay.play_out(instant)
	_set_locked(false)


## Trayecto casa ↔ trabajo (§4.2): fundido, HomeCycle.commute() y llegada ante la puerta de destino.
func _ride_commute(zone: String) -> void:
	var from_floor: int = _streamer.get_current_floor()
	var to_room: String = str(Database.get_balance(B_ENTRANCE if zone == ZONE_WORK else B_HOME))
	var room: RoomData = Database.get_room(to_room)
	var to_floor: int = room.floor if room != null else from_floor
	var minutes: int = Database.get_balance_int(B_COMMUTE)
	_set_locked(true)
	travel_started.emit(COMMUTE_KIND, from_floor, to_floor)
	await _overlay.play_in(COMMUTE_ICON, from_floor, to_floor,
			UITheme.trf("TRAVEL_CAPTION_COMMUTE_" + zone.to_upper(), [minutes]), false, instant)
	var home: HomeCycle = get_tree().get_first_node_in_group(HomeCycle.GROUP) as HomeCycle
	if home != null:
		minutes = home.commute()
	else:
		GameClock.advance_minutes(float(minutes))
	if not _closing_intercepts(to_room, to_floor):
		_ensure_floor(to_floor)
		_place(home_door_point() if zone == ZONE_HOME else _exit_point(str(Database.get_balance(B_STREET)), to_room))
	await _overlay.play_out(instant)
	_set_locked(false)
	_toast("WORLD_COMMUTE", [minutes], ToastStack.KIND_INFO)


## El cierre de las 19:00 cayó durante el trayecto: ClosingTime decide si el jugador sale fuera.
func _closing_intercepts(dest_room: String, dest_floor: int) -> bool:
	var closing: ClosingTime = ClosingTime.find(get_tree()) if is_inside_tree() else null
	return closing != null and closing.resolve_during_travel(dest_room, dest_floor)


## Copia de lo que el trayecto necesita del interactivo de origen: {kind, room_id, interact_id,
## noise (montacargas), rush (escalera en hora punta)}.
func source_of(item: Interactable) -> Dictionary:
	var kind: String = kind_of(item)
	return {"kind": kind, "room_id": item.room_id, "interact_id": item.interact_id,
			"noise": float(item.data.get(K_NOISE, Database.get_balance_float(B_FREIGHT_NOISE))),
			"rush": _is_rush(item, kind)}


## Cornisas y conductos: acto visible de unos segundos (moverse lo cancela).
func _enter_act(kind: String) -> bool:
	if not ACT_KINDS.has(kind) or not _player.has_method("begin_act") or instant:
		return true
	var seconds: float = Database.get_balance_float(B_VENT_ACT if kind == FloorLayout.TRANSIT_VENT else B_LEDGE_ACT)
	_player.call("begin_act", ACT_CRIME, seconds)
	var result: Array = await _player.act_finished
	if result.size() > 1 and bool(result[1]):
		return true
	_toast("TRAVEL_INTERRUPTED", [], ToastStack.KIND_WARN)
	return false


## Control de salida (§11.3): registro corporal si Security lo permite. false = la partida acabó.
func _checkpoint(src: Dictionary, dest: Dictionary) -> bool:
	if str(src["kind"]) != FloorLayout.TRANSIT_EXIT or int(dest["floor"]) != Database.get_balance_int(B_CHECK_FLOOR):
		return true
	var rooms: Array = Database.get_balance(B_CHECK_ROOMS)
	if not rooms.has(DatabaseSystem.get_room_base_id(str(src["room_id"]))) or not Security.can_search_player():
		return true
	var ui: UIRoot = UIRoot.find(get_tree())
	if ui != null and not instant:
		await ui.show_dialog("TRAVEL_SEARCH_TITLE", "TRAVEL_SEARCH_BODY", ["TRAVEL_SEARCH_OK"], [], true, false)
	var result: Dictionary = InventoryRules.perform_body_search(Security.get_effective_suspicion())
	var found: int = int(result.get("found_hot_items", 0))
	if found > 0:
		_toast("TRAVEL_SEARCH_FOUND", [found], ToastStack.KIND_BAD)
	else:
		_toast("TRAVEL_SEARCH_CLEAN", [], ToastStack.KIND_GOOD)
	return not SaveSystem.is_run_over()


func _depart(src: Dictionary, dest: Dictionary, hurry: bool) -> void:
	var here: Vector2 = _player.global_position
	match str(src["kind"]):
		FloorLayout.TRANSIT_ELEVATOR:
			var base: String = DatabaseSystem.get_room_base_id(str(src["room_id"]))
			var cabin: String = DatabaseSystem.make_room_instance_id(base, int(dest["floor"]))
			Security.log_card_access(str(src["interact_id"]), PLAYER_CARD, GameClock.get_day(), GameClock.get_hour(), cabin)
		FloorLayout.TRANSIT_FREIGHT:
			EventBus.noise_emitted.emit(here, float(src["noise"]), NOISE_FREIGHT)
		FloorLayout.TRANSIT_VENT:
			if hurry:
				EventBus.noise_emitted.emit(here, Database.get_balance_float(B_VENT_NOISE), NOISE_VENT)


func _arrive(src: Dictionary, dest: Dictionary) -> void:
	_ensure_floor(int(dest["floor"]))
	_place(_arrival_point(src, dest))


func _arrival_point(src: Dictionary, dest: Dictionary) -> Vector2:
	var point: Vector2 = Vector2.ZERO
	var transit_id: String = str(dest.get("transit_id", ""))
	var room_id: String = str(dest.get("room_id", ""))
	if not transit_id.is_empty():
		point = _streamer.get_transit_point(transit_id)
	elif str(src["kind"]) == KIND_LEDGE:
		point = _ledge_point(room_id)
	elif str(src["kind"]) == FloorLayout.TRANSIT_EXIT:
		point = _exit_point(str(src["room_id"]), room_id)
	else:
		point = _streamer.get_arrival_point(str(src["room_id"]), str(src["kind"]))
	if point == Vector2.ZERO and not room_id.is_empty():
		point = _streamer.get_spawn_point(room_id)
	return point


## La puerta de `room_id` que da a la sala de origen (la calle tiene varias puertas al edificio).
func _exit_point(source_room: String, room_id: String) -> Vector2:
	for t: Dictionary in _streamer.get_plan().get("transit", []):
		if t["kind"] == FloorLayout.TRANSIT_EXIT and t["room_id"] == room_id and t["target_room"] == source_room:
			return _streamer.cell_to_world(t["cell"])
	return _streamer.get_arrival_point(source_room, FloorLayout.TRANSIT_EXIT)


func _ledge_point(room_id: String) -> Vector2:
	for node: Interactable in _streamer.get_interactables_in_room(room_id):
		if node.interact_type == LEDGE_TYPE:
			return node.global_position
	return Vector2.ZERO


func _after_arrival(src: Dictionary, dest: Dictionary, hurry: bool, from_floor: int) -> void:
	var here: Vector2 = _player.global_position
	match str(src["kind"]):
		FloorLayout.TRANSIT_FREIGHT:
			EventBus.noise_emitted.emit(here, float(src["noise"]), NOISE_FREIGHT)
		FloorLayout.TRANSIT_VENT:
			if hurry:
				EventBus.noise_emitted.emit(here, Database.get_balance_float(B_VENT_NOISE), NOISE_VENT)
		FloorLayout.TRANSIT_SERVICE_STAIRS:
			_roll_service_encounter(from_floor, int(dest["floor"]))


# ─── Escalera de servicio: encuentros ─────────────────────────

## §5.4: «coincidir con alguien genera sospecha». Devuelve el id del testigo ("" = nadie).
func _roll_service_encounter(from_floor: int, to_floor: int) -> String:
	if (Database.get_balance(B_SERVICE + "disfraces_justificados") as Array).has(PlayerState.get_disguise()):
		return ""
	if not (Database.get_balance(B_SERVICE + "franjas_encuentro") as Array).has(GameClock.get_current_band()):
		return ""
	var floors: int = floor_distance(from_floor, to_floor)
	var chance: float = minf(Database.get_balance_float(B_SERVICE + "prob_encuentro_por_planta") * floors,
			Database.get_balance_float(B_SERVICE + "prob_encuentro_max"))
	if _rng.randf() >= chance:
		return ""
	var witness: NPCRuntime = _pick_witness(from_floor, to_floor)
	if witness == null:
		return ""
	var where: String = DatabaseSystem.make_room_instance_id(FloorLayout.TRANSIT_SERVICE_STAIRS, to_floor)
	EventBus.player_seen_partially.emit(witness.id, Database.get_balance_float(B_SERVICE + "certeza_encuentro"), where)
	_toast("TRAVEL_SEEN_SERVICE_STAIRS", [witness.name], ToastStack.KIND_WARN)
	return witness.id


func _pick_witness(from_floor: int, to_floor: int) -> NPCRuntime:
	var pool: Array[NPCRuntime] = []
	for f: int in [from_floor, to_floor]:
		for npc: NPCRuntime in NPCDirector.get_npcs_on_floor(f):
			if npc.alive and not pool.has(npc):
				pool.append(npc)
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


# ─── Colocación ───────────────────────────────────────────────

## Lleva al jugador a una sala (celdas desde su esquina superior izquierda; negativas = su punto
## de aparición). Carga la planta si hace falta. false si la sala no existe.
func teleport_to_room(room_id: String, cells: Vector2 = Vector2(-1, -1)) -> bool:
	var room: RoomData = Database.get_room(room_id)
	if room == null or _streamer == null:
		return false
	_ensure_floor(room.floor)
	var rect: Rect2 = _streamer.get_room_rect_px(room_id)
	if rect.size == Vector2.ZERO:
		return false
	var point: Vector2 = _streamer.get_spawn_point(room_id)
	if cells.x >= 0.0 and cells.y >= 0.0:
		point = rect.position + cells * RoomBuilder.cell_px()
	_place(point)
	return true


func teleport(floor_number: int, point: Vector2) -> void:
	_ensure_floor(floor_number)
	_place(point)


## Dentro del piso, junto a su puerta a la calle (llegada del trayecto, puerta «ir al trabajo»). La
## planta exterior debe estar cargada.
func home_door_point() -> Vector2:
	var home: String = str(Database.get_balance(B_HOME))
	var door: Dictionary = _streamer.get_door_between(home, str(Database.get_balance(B_STREET)))
	if door.is_empty():
		return _streamer.get_spawn_point(home)
	var rect: Rect2 = _streamer.get_room_rect_px(home)
	var cell: Vector2i = door["cell"]
	var normal: Vector2i = Vector2i(1, 0) if bool(door["vertical"]) else Vector2i(0, 1)
	var inside: Vector2 = _streamer.cell_to_world(cell)
	if not rect.has_point(inside):
		inside = _streamer.cell_to_world(cell - normal)
	return inside + (rect.get_center() - inside).normalized() * RoomBuilder.cell_px()


## La calle, ante la puerta de recepción (desalojo del cierre). `fade`: sale de negro poco a poco.
func place_outside_building(fade: bool = false) -> void:
	var street: String = str(Database.get_balance(B_STREET))
	_ensure_floor(Database.get_balance_int(B_EXTERIOR))
	_place(_exit_point(str(Database.get_balance(B_ENTRANCE)), street))
	if fade and not instant:
		_fade_from_black()


func _fade_from_black() -> void:
	var here: int = _streamer.get_current_floor()
	await _overlay.play_in(COMMUTE_ICON, here, here, "", false, true)
	await _overlay.play_out(false)


func _ensure_floor(floor_number: int) -> void:
	if _streamer.get_plan().is_empty() or _streamer.get_current_floor() != floor_number:
		_streamer.load_floor(floor_number)


func _place(point: Vector2) -> void:
	var safe: Vector2 = _streamer.nearest_walkable_point(point)
	_player.global_position = safe if safe != Vector2.INF else point
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO
	_player.reset_physics_interpolation()
	refresh_camera()


## Límites de la planta y encuadre inmediato (tras cargar planta o teletransportar).
func refresh_camera() -> void:
	var cam: PlayerCamera = _player.get_node_or_null(CAMERA_NODE) as PlayerCamera if _player != null else null
	if cam == null or _streamer == null:
		return
	cam.set_bounds(_streamer.get_floor_rect_px())
	cam.snap_to_target()


func _set_locked(locked: bool) -> void:
	if _player != null and _player.has_method("set_input_locked"):
		_player.call("set_input_locked", locked, LOCK_OWNER)


# ─── Avisos ───────────────────────────────────────────────────

func _panel_title(item: Interactable, kind: String) -> String:
	if kind == FloorLayout.TRANSIT_ELEVATOR:
		var room: RoomData = Database.get_room(item.room_id)
		return TranslationServer.translate(room.name_key) if room != null else ""
	return TranslationServer.translate("TRAVEL_TITLE_" + kind.to_upper())


func _panel_hint(kind: String) -> String:
	return TranslationServer.translate("TRAVEL_HINT_" + kind.to_upper())


func _caption(kind: String, dest: Dictionary, minutes: float) -> String:
	var where: String = str(dest.get("label", "")) if not GRID_KINDS.has(kind) else MapView.floor_name(int(dest["floor"]))
	return UITheme.trf("TRAVEL_CAPTION_" + kind.to_upper(), [where, roundi(minutes)])


func _deny_card(dest: Dictionary) -> void:
	_play_sfx(SFX_DENIED, _player.global_position if _player != null else AudioDirector.NO_POSITION)
	_toast("TRAVEL_CARD_DENIED", [MapView.floor_name(int(dest["floor"])), int(dest.get("clearance", 0))], ToastStack.KIND_BAD)


func _refuse(key: String, args: Array) -> void:
	_play_sfx(SFX_DENIED, _player.global_position if _player != null else AudioDirector.NO_POSITION)
	_toast(key, args, ToastStack.KIND_WARN)


func _toast(key: String, args: Array, kind: String) -> void:
	var ui: UIRoot = UIRoot.find(get_tree()) if is_inside_tree() else null
	if ui != null:
		ui.toast(key, args, kind)


func _play_sfx(id: String, pos: Vector2) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree()) if is_inside_tree() else null
	if audio != null:
		audio.play_sfx(id, pos)


# ═══ Panel de destino ══════════════════════════════════════════

## Botonera de plantas (rejilla, como la de un ascensor) o lista de salas (conductos, cornisas).
## Emite chosen(índice) al pulsar un destino (también los bloqueados: FloorTravel decide y pita) y
## chosen(-1) al cancelar. UIRoot la cierra con Esc (request_close) o close_modal (cancel).
class FloorSelectPanel extends PanelContainer:
	signal chosen(index: int)

	const GRID_COLUMNS := 4
	const LIST_COLUMNS := 1
	const BUTTON_EMS := Vector2(3.4, 2.1)
	const LIST_EMS := 17.0
	const MAX_HEIGHT_RATIO := 0.45
	const FLASH_SECONDS := 0.45

	var _buttons: Array[Button] = []
	var _locked: Array[bool] = []
	var _options: Array[Dictionary] = []
	var _grid_mode: bool = true
	var _focus_index: int = -1
	var _title: Label
	var _hint: Label
	var _scroll: ScrollContainer
	var _grid: GridContainer

	func _init() -> void:
		name = "FloorSelectPanel"
		theme_type_variation = UITheme.V_MODAL
		var column: VBoxContainer = VBoxContainer.new()
		add_child(column)
		_title = Label.new()
		_title.theme_type_variation = UITheme.V_TITLE
		column.add_child(_title)
		_hint = Label.new()
		_hint.theme_type_variation = UITheme.V_SMALL
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(_hint)
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(_scroll)
		_grid = GridContainer.new()
		_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(_grid)
		var cancel_button: Button = Button.new()
		cancel_button.text = TranslationServer.translate("UI_CANCEL")
		cancel_button.pressed.connect(cancel)
		column.add_child(cancel_button)

	func setup(title_text: String, hint_text: String, options: Array[Dictionary], grid_mode: bool,
			focus_index: int = -1) -> void:
		_options = options
		_grid_mode = grid_mode
		_focus_index = focus_index
		_title.text = title_text
		_hint.text = hint_text
		_hint.visible = not hint_text.is_empty()
		_grid.columns = GRID_COLUMNS if grid_mode else LIST_COLUMNS
		for i: int in options.size():
			_add_button(i, options[i])

	func _ready() -> void:
		UITheme.center_fitted(self)
		_fit.call_deferred()
		_focus_first.call_deferred()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED and _grid != null:
			_fit()

	func _add_button(index: int, option: Dictionary) -> void:
		var button: Button = Button.new()
		var locked: bool = not bool(option["allowed"])
		button.text = str(option["label"])
		if locked:
			button.text += "\n" + UITheme.trf("TRAVEL_LOCKED_FMT", [int(option["clearance"])])
			button.modulate = UITheme.color("muted")
			button.tooltip_text = TranslationServer.translate("TRAVEL_LOCKED_TIP")
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if _grid_mode else HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(choose.bind(index))
		_grid.add_child(button)
		_buttons.append(button)
		_locked.append(locked)

	func _fit() -> void:
		var em: float = float(get_theme_constant("base", UITheme.HUD_TYPE))
		for button: Button in _buttons:
			button.custom_minimum_size = BUTTON_EMS * em if _grid_mode else Vector2(LIST_EMS * em, BUTTON_EMS.y * em * 0.7)
		var rows: int = ceili(float(_buttons.size()) / float(_grid.columns))
		var button_h: float = em
		for button: Button in _buttons:
			button_h = maxf(button_h, maxf(button.custom_minimum_size.y, button.get_combined_minimum_size().y))
		var gap: float = float(_grid.get_theme_constant("v_separation"))
		var content_h: float = button_h * rows + gap * maxi(rows - 1, 0)
		var max_h: float = get_viewport_rect().size.y * MAX_HEIGHT_RATIO if is_inside_tree() else content_h
		_scroll.custom_minimum_size = Vector2(_grid.get_combined_minimum_size().x, minf(content_h, max_h))

	func _focus_first() -> void:
		if _focus_index >= 0 and _focus_index < _buttons.size() and _buttons[_focus_index].is_inside_tree():
			_buttons[_focus_index].grab_focus()
			return
		for i: int in _buttons.size():
			if not _locked[i] and _buttons[i].is_inside_tree():
				_buttons[i].grab_focus()
				return

	func is_locked(index: int) -> bool:
		return index >= 0 and index < _locked.size() and _locked[index]

	## Elige un destino (también desde el escenario de QA).
	func choose(index: int) -> void:
		chosen.emit(index)

	## Índice del destino de una planta (-1 si no está).
	func index_of_floor(floor_number: int) -> int:
		for i: int in _options.size():
			if int(_options[i]["floor"]) == floor_number:
				return i
		return -1

	func get_option_count() -> int:
		return _options.size()

	func cancel() -> void:
		chosen.emit(-1)

	func request_close() -> void:
		cancel()

	## Pitido rojo en un destino bloqueado: el botón parpadea en color de peligro.
	func flash_denied(index: int) -> void:
		if index < 0 or index >= _buttons.size():
			return
		var button: Button = _buttons[index]
		var tween: Tween = create_tween()
		tween.tween_property(button, "modulate", UITheme.color("danger"), FLASH_SECONDS * 0.5)
		tween.tween_property(button, "modulate", UITheme.color("muted"), FLASH_SECONDS * 0.5)


# ═══ Fundido del trayecto ══════════════════════════════════════

## Capa bajo la interfaz (el HUD sigue visible: el reloj salta con el coste del trayecto): fundido
## a negro con el indicador de planta del destino contando plantas en el color de su banda.
class TravelOverlay extends CanvasLayer:
	const LAYER_BELOW_UI := 9
	const B_FADE := "viaje.presentacion.fundido_segundos"
	const B_RIDE := "viaje.presentacion.recorrido_segundos"
	const B_PER_FLOOR := "viaje.presentacion.recorrido_por_planta_segundos"
	const B_RIDE_MAX := "viaje.presentacion.recorrido_max_segundos"
	const DISPLAY_EMS := 4.2
	const ICON_SCALE := 2.4
	const ARROW_UP := "▲"
	const ARROW_DOWN := "▼"

	var _shade: ColorRect
	var _box: VBoxContainer
	var _icon: UITheme.IconView
	var _display: Label
	var _caption: Label
	var _shown_floor: int = 0

	func _init() -> void:
		layer = LAYER_BELOW_UI
		visible = false
		var root: Control = Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.theme = UITheme.build(UITheme.current_text_size, UITheme.current_high_contrast)
		add_child(root)
		_shade = ColorRect.new()
		_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shade.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(_shade)
		_box = VBoxContainer.new()
		_box.alignment = BoxContainer.ALIGNMENT_CENTER
		_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(_box)
		_build_content()

	func _build_content() -> void:
		_icon = UITheme.IconView.new("elevator", "paper", ICON_SCALE)
		_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box.add_child(_icon)
		_display = Label.new()
		_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_display.add_theme_font_override("font", UITheme.font(UITheme.FONT_MONO))
		_box.add_child(_display)
		_caption = Label.new()
		_caption.theme_type_variation = UITheme.V_HEADING
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(_caption)

	## Fundido de entrada; con `counting` el indicador recorre las plantas (ascensor, escaleras).
	func play_in(icon: String, from_floor: int, to_floor: int, caption: String, counting: bool, skip: bool) -> void:
		_shade.color = UITheme.color("ink")
		_icon.set_icon(icon)
		_display.add_theme_color_override("font_color", UITheme.band_accent_for_floor(to_floor))
		_display.add_theme_font_size_override("font_size", roundi(UITheme.base_font_size(UITheme.current_text_size) * DISPLAY_EMS))
		_display.visible = counting
		_caption.text = caption
		_shown_floor = from_floor
		_set_display(from_floor, to_floor)
		visible = true
		if skip:
			_shade.modulate.a = 1.0
			_box.modulate.a = 1.0
			return
		await _fade(1.0)
		await _count(from_floor, to_floor if counting else from_floor)

	func play_out(skip: bool) -> void:
		if not skip:
			await _fade(0.0)
		visible = false

	func _fade(target: float) -> void:
		var tween: Tween = create_tween().set_parallel(true)
		var seconds: float = Database.get_balance_float(B_FADE)
		tween.tween_property(_shade, "modulate:a", target, seconds).from(1.0 - target)
		tween.tween_property(_box, "modulate:a", target, seconds).from(1.0 - target)
		await tween.finished

	func _count(from_floor: int, to_floor: int) -> void:
		var steps: int = FloorTravel.floor_distance(from_floor, to_floor)
		var seconds: float = minf(Database.get_balance_float(B_RIDE) + Database.get_balance_float(B_PER_FLOOR) * steps,
				Database.get_balance_float(B_RIDE_MAX))
		var tween: Tween = create_tween()
		tween.tween_method(func(t: float) -> void: _set_display(roundi(lerpf(from_floor, to_floor, t)), to_floor), 0.0, 1.0, seconds)
		await tween.finished

	func _set_display(shown: int, to_floor: int) -> void:
		var factory: int = Database.get_balance_int(FloorTravel.B_FACTORY)
		if to_floor >= factory:
			shown = to_floor
		var arrow: String = ARROW_UP if to_floor > _shown_floor else ARROW_DOWN
		_display.text = ("%s %s" % [arrow, MapView.floor_label_short(shown)]) if shown != to_floor \
				else MapView.floor_label_short(shown)
