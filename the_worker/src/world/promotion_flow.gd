# promotion_flow.gd — Flujo de ascensos en la partida (§6.1-§6.3, §14.1): aviso de oferta, aceptar o rechazar con confirmación, trayecto de la torre y mesa nueva; degradaciones.
# PROPIETARIO DE: la última oferta avisada (ids y jornada) y la presentación en curso.
# ESCUCHA: promotion_available, promotion_declined, occupation_changed, run_started, run_loaded.
class_name PromotionFlow
extends Node

## GameRoot lo añade con setup(ui, travel). Company decide (can_player_promote_to / promote_player /
## decline_promotion / demote_player); este nodo solo lo cuenta y lleva al jugador:
##  · promotion_available(ids) → aviso (una vez por jornada y oferta) «hay un ascenso: mira PORTAL
##    (C) o el menú de pausa»; PORTAL ya lista destinos, condiciones y la solicitud confirmada.
##  · open_offer() (menú de pausa, Esc): los destinos disponibles hoy con «Aceptar» / «Rechazar»;
##    ambas piden confirmación explícita (§13.7) antes de Company.promote_player / decline_promotion.
##  · occupation_changed(antiguo, nuevo, motivo) con motivo de PRESENT_REASONS → PromotionScreen
##    (el ascensor recorre el corte de la torre) y, al cerrarla, si el motivo es de MOVE_REASONS y el
##    jugador está en el edificio (zona «work»), se cierra el ordenador y aparece en su despacho
##    nuevo (FloorTravel); fuera del edificio solo se le dice dónde está su sitio nuevo. Degradación:
##    la misma pantalla (DEGRADADO) + aviso rojo; si la sala donde está ya le queda vetada con la
##    acreditación nueva, Seguridad le acompaña a su nueva mesa (si no, se le indica cuál es).
##  · Los cambios de depuración/QA/tutorial ("debug", "qa", "preview", "tutorial") no se escenifican.

signal presented(old_id: String, new_id: String, reason: String)
signal moved_to_desk(room_id: String)

const GROUP := "promotion_flow"
const PRESENT_REASONS: Array[String] = ["promotion", "lateral", "created_post", "demotion", "assigned"]
const MOVE_REASONS: Array[String] = ["promotion", "lateral", "created_post"]
const DEMOTION := "demotion"
const KIND_COMPUTER := "computer"
const SFX_NOTIFY := "ui_notify"

## Pruebas: sin PromotionScreen (se da por vista al instante).
var instant: bool = false
var _ui: UIRoot = null
var _travel: FloorTravel = null
var _offer_key: String = ""
var _presenting: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.promotion_available.connect(_on_promotion_available)
	EventBus.promotion_declined.connect(_on_promotion_declined)
	EventBus.occupation_changed.connect(_on_occupation_changed)
	EventBus.run_started.connect(func(_seed: int) -> void: _offer_key = "")
	EventBus.run_loaded.connect(func(_day: int) -> void: _offer_key = "")


func setup(ui: UIRoot, travel: FloorTravel) -> void:
	_ui = ui
	_travel = travel


static func find(tree: SceneTree) -> PromotionFlow:
	return tree.get_first_node_in_group(GROUP) as PromotionFlow if tree != null else null


## Destinos disponibles hoy (ascensos, saltos y laterales que cumplen las tres condiciones).
func get_offer() -> Array[String]:
	return Company.get_available_promotions()


func is_presenting() -> bool:
	return _presenting


# ─── Oferta ───────────────────────────────────────────────────

func _on_promotion_available(occupation_ids: Array) -> void:
	var key: String = "%d:%s" % [GameClock.get_day(), ",".join(PackedStringArray(occupation_ids))]
	if occupation_ids.is_empty() or key == _offer_key:
		return
	_offer_key = key
	_toast("PROMO_TOAST_AVAILABLE", [_names(occupation_ids)], ToastStack.KIND_GOOD)
	_play(SFX_NOTIFY)


func _on_promotion_declined(occupation_id: String) -> void:
	_toast("PROMO_TOAST_DECLINED", [PromotionScreen.occupation_name(occupation_id)], ToastStack.KIND_INFO)


## Diálogo de oferta: aceptar o rechazar cada destino, con confirmación. true si algo cambió.
func open_offer() -> bool:
	var offer: Array[String] = get_offer()
	if _ui == null:
		return false
	if offer.is_empty():
		_toast("PROMO_TOAST_NONE", [], ToastStack.KIND_INFO)
		return false
	var options: Array = []
	for occupation_id: String in offer:
		var args: Array = [PromotionScreen.occupation_name(occupation_id), PromotionScreen.occupation_rank(occupation_id)]
		options.append({"text_key": "PROMO_OFFER_ACCEPT", "args": args, "icon": "star"})
		options.append({"text_key": "PROMO_OFFER_DECLINE", "args": args})
	options.append("PROMO_OFFER_LATER")
	var index: int = await _ui.show_dialog("PROMO_OFFER_TITLE", "PROMO_OFFER_BODY", options)
	if index < 0 or index >= offer.size() * 2:
		return false
	var target: String = offer[floori(index / 2.0)]
	return await _confirm_and_apply(target, index % 2 == 0)


func _confirm_and_apply(target: String, accept: bool) -> bool:
	var name_text: String = PromotionScreen.occupation_name(target)
	var title: String = "PROMO_CONFIRM_ACCEPT_TITLE" if accept else "PROMO_CONFIRM_DECLINE_TITLE"
	var body: String = "PROMO_CONFIRM_ACCEPT_BODY" if accept else "PROMO_CONFIRM_DECLINE_BODY"
	var yes: Dictionary = {"text_key": "PROMO_CONFIRM_YES" if accept else "PROMO_CONFIRM_DECLINE", "danger": not accept}
	var choice: int = await _ui.show_dialog(title, body, [yes, "UI_CANCEL"], [name_text])
	if choice != 0:
		return false
	if accept:
		return Company.promote_player(target)
	Company.decline_promotion(target)
	return true


# ─── Cambio de puesto ─────────────────────────────────────────

func _on_occupation_changed(old_id: String, new_id: String, reason: String) -> void:
	if not PRESENT_REASONS.has(reason) or old_id.is_empty() or new_id.is_empty():
		return
	_present(old_id, new_id, reason)


func _present(old_id: String, new_id: String, reason: String) -> void:
	_presenting = true
	if reason == DEMOTION:
		_toast("PROMO_TOAST_DEMOTED", [PromotionScreen.occupation_name(new_id)], ToastStack.KIND_BAD)
	if _ui != null and not instant and _should_move(reason):
		_close_computer()
	if _ui != null and not instant:
		var screen: PromotionScreen = PromotionScreen.present(_ui, old_id, new_id, reason)
		await screen.finished
	presented.emit(old_id, new_id, reason)
	if _should_move(reason):
		_move_to_desk(new_id, reason == DEMOTION)
	else:
		_tell_new_desk(new_id)
	_presenting = false


## Se le lleva a la mesa nueva: ascenso/lateral dentro del edificio; degradación si su sala ya le
## está vetada (no se queda de pie en un sitio prohibido).
func _should_move(reason: String) -> bool:
	if WorldBridges.zone_of(PlayerState.get_room()) != WorldBridges.ZONE_WORK:
		return false
	if reason == DEMOTION:
		return BeliefNet.is_room_forbidden_for_player(PlayerState.get_room())
	return MOVE_REASONS.has(reason)


func _tell_new_desk(occupation_id: String) -> void:
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	var room: RoomData = Database.get_room(occupation.office_room) if occupation != null else null
	if room != null and DatabaseSystem.get_room_base_id(PlayerState.get_room()) != room.id:
		_toast("PROMO_TOAST_DESK_IS", [TranslationServer.translate(room.name_key), MapView.floor_name(room.floor)],
				ToastStack.KIND_INFO)


## Aparece en el despacho del puesto nuevo (el ascensor de la pantalla ya hizo el viaje; en una
## degradación, acompañado por Seguridad).
func _move_to_desk(occupation_id: String, escorted: bool = false) -> void:
	var occupation: OccupationData = Database.get_occupation(occupation_id)
	if occupation == null or occupation.office_room.is_empty() or _travel == null:
		return
	if DatabaseSystem.get_room_base_id(PlayerState.get_room()) == occupation.office_room:
		return
	if _travel.teleport_to_room(occupation.office_room):
		var room: RoomData = Database.get_room(occupation.office_room)
		var room_name: String = TranslationServer.translate(room.name_key) if room != null else ""
		if escorted:
			_toast("PROMO_TOAST_ESCORTED", [room_name], ToastStack.KIND_WARN)
		else:
			_toast("PROMO_TOAST_NEW_DESK", [room_name], ToastStack.KIND_GOOD)
		moved_to_desk.emit(occupation.office_room)


func _close_computer() -> void:
	var top: Control = _ui.get_top_modal()
	while top != null and str(top.get_meta(UIRoot.META_KIND, "")) == KIND_COMPUTER:
		_ui.close_modal_control(top)
		top = _ui.get_top_modal()


func _names(occupation_ids: Array) -> String:
	var names: PackedStringArray = []
	for value: Variant in occupation_ids:
		names.append(PromotionScreen.occupation_name(str(value)))
	return ", ".join(names)


func _toast(key: String, args: Array, kind: String) -> void:
	if _ui != null:
		_ui.toast(key, args, kind)


func _play(id: String) -> void:
	var audio: AudioDirector = AudioDirector.find(get_tree()) if is_inside_tree() else null
	if audio != null:
		audio.play_sfx(id)
