extends CharacterBody3D
## Юмик: 25 лет, 190 см, 80 кг. Короткие чёрные волосы до плеч, голубые глаза,
## белая пижама и голубые джинсы (или розовое платье горничной из шкафа замка).
## CharacterBody3D + процедурный визуал + сменный ragdoll (RigidBody3D-кости).
## Прыжки: земля 35 см / на НЗТБНЗ 350 см; в беге «припрыжка» 45/450 см;
## пост-прыжки 50% → 25% → 10%; на «очень прыгучих» частях высота не падает.

enum Mode { NORMAL, CRAWL, LYING, CLIMB, RAGDOLL, CAPTURED, SLEEP, THRONE, DEAD }

const HEIGHT_M: float = 1.9
const MASS_KG: float = 80.0
const WALK_SPEED: float = 1.7
const RUN_SPEED: float = 5.6
const CRAWL_SPEED: float = 1.3

var mode: int = Mode.NORMAL
var maid_outfit: bool = false
var hem_up: bool = false
var weakened: bool = false
var squeezing: bool = false # «Тискать» — крепкая хватка при лазании

var _move_input: Vector2 = Vector2.ZERO
var _input_running: bool = false
var _prev_input: Vector2 = Vector2.ZERO

var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.32
var _cam_pivot: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _cutscene_orbit: bool = false
var _cutscene_target: Node3D = null

var _model: Node3D
var _body_root: Node3D
var _chest_pivot: Node3D
var _head_pivot: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _chest_mesh: MeshInstance3D
var _dress_group: Node3D
var _dress_normal: MeshInstance3D
var _dress_raised: MeshInstance3D
var _headband: MeshInstance3D
var _leg_meshes: Array[MeshInstance3D] = []
var _foot_meshes: Array[MeshInstance3D] = []
var _walk_phase: float = 0.0
var _facing_yaw: float = 0.0
var _squash_k: float = 0.0
var _land_squash: float = 0.0
var _hug_timer: float = 0.0
var _flashlight: SpotLight3D

var _collision: CollisionShape3D
var _surface: String = "ground" # ground | bouncy | very_bouncy | throne | rope | water
var _floor_body: Object = null
var _air_time: float = 0.0
var _prev_vy: float = 0.0
var _bounce_origin_h: float = 0.0
var _bounce_step: int = 0
var _bounce_active: bool = false
var _pending_prone: bool = false
var _lie_prone: bool = false
var _getup_timer: float = 0.0
var _step_acc: float = 0.0
var _in_water: bool = false

# Лазание
var _climb_body: Object = null
var _climb_normal: Vector3 = Vector3.BACK
var _climb_slip_vel: float = 0.0
var _climb_rope_seg: RigidBody3D = null
var _rope_switch_timer: float = 0.0
var _god_touch_cooldown: float = 0.0

# Платформа-замок: следование за движением RigidBody под ногами
var _last_castle_xf: Transform3D = Transform3D.IDENTITY
var _on_castle: bool = false

# Ragdoll
var _ragdoll_parts: Dictionary = {} # имя -> RigidBody3D (ragdoll_part.gd)
var _ragdoll_joints: Array[Joint3D] = []
var _hold_joints: Array[Joint3D] = []
var hold_on: bool = false # «Не отпускай меня»
var _ragdoll_still_time: float = 0.0
var _throne_pin: Joint3D = null
var _capture_castle = null # замок (без жёсткой типизации: нет циклических ссылок классов)

const RagdollPartScript: GDScript = preload("res://scripts/ragdoll_part.gd")

# ------------------------------------------------------------------ стройка
func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 16
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	_collision = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = HEIGHT_M
	_collision.shape = cap
	_collision.position = Vector3(0, HEIGHT_M * 0.5, 0)
	add_child(_collision)
	_build_model()
	_build_camera()
	call_deferred("_build_ragdoll")
	# Фонарь Юмика — ночь, хоррор (включается сам в темноте сцены через Main)
	_flashlight = SpotLight3D.new()
	_flashlight.spot_range = 38.0
	_flashlight.spot_angle = 32.0
	_flashlight.light_energy = 2.2
	_flashlight.position = Vector3(0.25, 1.65, 0)
	add_child(_flashlight)

func _mat_skin() -> Material:
	return GameMaterials.plain(Color(0.98, 0.8, 0.68), 0.6)

func _limb(parent: Node3D, pos: Vector3, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "YumikModel"
	add_child(_model)
	_body_root = Node3D.new()
	_body_root.position = Vector3(0, 0.95, 0) # центр тела (для поз лёжа)
	_model.add_child(_body_root)
	var skin: Material = _mat_skin()
	var pajama: Material = GameMaterials.cotton_white()
	var jeans: Material = GameMaterials.denim()
	# Таз (джинсы)
	_limb(_body_root, Vector3.ZERO, MeshBuilder.rounded_box(Vector3(0.4, 0.26, 0.26), 0.1), jeans)
	# Грудь (белая пижама)
	_chest_pivot = Node3D.new()
	_chest_pivot.position = Vector3(0, 0.14, 0)
	_body_root.add_child(_chest_pivot)
	_chest_mesh = _limb(_chest_pivot, Vector3(0, 0.3, 0), MeshBuilder.capsule(0.21, 0.72), pajama)
	_chest_mesh.scale = Vector3(1.15, 1.0, 0.8)
	# Голова: кожа, чёрные волосы до плеч, голубые глаза
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0, 0.62, 0)
	_chest_pivot.add_child(_head_pivot)
	_limb(_head_pivot, Vector3(0, 0.13, 0), MeshBuilder.ellipsoid(0.14, Vector3.ONE), skin)
	var hair_cap := _limb(_head_pivot, Vector3(0, 0.17, -0.02), MeshBuilder.ellipsoid(0.15, Vector3.ONE), GameMaterials.hair_black())
	hair_cap.scale = Vector3(1.05, 0.95, 1.05)
	# Волосы сзади до плеч
	_limb(_head_pivot, Vector3(0, -0.05, -0.09), MeshBuilder.rounded_box(Vector3(0.27, 0.42, 0.1), 0.05), GameMaterials.hair_black())
	var eye_mat: Material = GameMaterials.emission(Color(0.35, 0.65, 1.0), 0.7)
	for sx: float in [-0.055, 0.055]:
		var eye := _limb(_head_pivot, Vector3(sx, 0.13, 0.125), MeshBuilder.ellipsoid(0.021, Vector3.ONE), eye_mat)
		eye.scale = Vector3(1.0, 1.5, 0.5)
	_headband = _limb(_head_pivot, Vector3(0, 0.26, 0.02), MeshBuilder.cylinder(0.145, 0.145, 0.045, 14), GameMaterials.lace_white())
	_headband.visible = false
	# Руки
	_shoulder_l = _make_arm(-1.0, pajama, skin, true)
	_shoulder_r = _make_arm(1.0, pajama, skin, false)
	# Ноги
	_hip_l = _make_leg(-1.0, jeans, true)
	_hip_r = _make_leg(1.0, jeans, false)
	# Платье горничной (скрыто до шкафа): розовый шёлк, рюши, подол до пяток
	_dress_group = Node3D.new()
	_body_root.add_child(_dress_group)
	var pink: Material = GameMaterials.silk(Color(1.0, 0.62, 0.72), "silk_pink_albedo")
	_dress_normal = MeshInstance3D.new()
	_dress_normal.mesh = MeshBuilder.skirt_mesh(0.24, 0.58, 1.55)
	_dress_normal.material_override = pink
	_dress_normal.position = Vector3(0, -0.55, 0)
	_dress_group.add_child(_dress_normal)
	var apron := MeshInstance3D.new()
	apron.mesh = MeshBuilder.box(Vector3(0.34, 0.7, 0.04))
	apron.material_override = GameMaterials.lace_white()
	apron.position = Vector3(0, -0.35, 0.3)
	apron.rotation_degrees.x = -10
	_dress_group.add_child(apron)
	var ruffle := MeshInstance3D.new()
	ruffle.mesh = MeshBuilder.cylinder(0.6, 0.66, 0.14, 20)
	ruffle.material_override = GameMaterials.lace_white()
	ruffle.position = Vector3(0, -1.28, 0)
	_dress_group.add_child(ruffle)
	# Задраный подол («парус»)
	_dress_raised = MeshInstance3D.new()
	_dress_raised.mesh = MeshBuilder.skirt_mesh(0.85, 0.3, 1.1)
	_dress_raised.material_override = pink
	_dress_raised.position = Vector3(0, 0.25, 0)
	_dress_raised.visible = false
	_dress_group.add_child(_dress_raised)
	_dress_group.visible = false

func _make_arm(side: float, sleeve_mat: Material, skin: Material, is_left: bool) -> Node3D:
	var sh := Node3D.new()
	sh.position = Vector3(side * 0.27, 0.52, 0)
	_chest_pivot.add_child(sh)
	_limb(sh, Vector3(0, -0.16, 0), MeshBuilder.capsule(0.065, 0.42), sleeve_mat)
	var el := Node3D.new()
	el.position = Vector3(0, -0.34, 0)
	sh.add_child(el)
	_limb(el, Vector3(0, -0.15, 0), MeshBuilder.capsule(0.055, 0.4), skin)
	_limb(el, Vector3(0, -0.36, 0), MeshBuilder.ellipsoid(0.055, Vector3.ONE), skin)
	if is_left:
		_elbow_l = el
	else:
		_elbow_r = el
	return sh

func _make_leg(side: float, leg_mat: Material, is_left: bool) -> Node3D:
	var hip := Node3D.new()
	hip.position = Vector3(side * 0.11, -0.08, 0)
	_body_root.add_child(hip)
	var thigh := _limb(hip, Vector3(0, -0.24, 0), MeshBuilder.capsule(0.085, 0.55), leg_mat)
	_leg_meshes.append(thigh)
	var knee := Node3D.new()
	knee.position = Vector3(0, -0.48, 0)
	hip.add_child(knee)
	var shin := _limb(knee, Vector3(0, -0.22, 0), MeshBuilder.capsule(0.07, 0.52), leg_mat)
	_leg_meshes.append(shin)
	var foot := _limb(knee, Vector3(0, -0.47, 0.05), MeshBuilder.box(Vector3(0.1, 0.06, 0.26)),
		GameMaterials.plain(Color(0.15, 0.12, 0.1), 0.6))
	_foot_meshes.append(foot)
	if is_left:
		_knee_l = knee
	else:
		_knee_r = knee
	return hip

func _build_camera() -> void:
	_cam_pivot = Node3D.new()
	_cam_pivot.name = "CameraPivot"
	_cam_pivot.top_level = true
	add_child(_cam_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = 5.5
	_spring.margin = 0.35
	_spring.collision_mask = 1 | 4
	_cam_pivot.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 9000.0
	camera.current = true
	_spring.add_child(camera)
	var listener := AudioListener3D.new()
	camera.add_child(listener)

# ----------------------------------------------------------------- ragdoll -
func _ragdoll_body(pname: String, mass_kg: float, shape: Shape3D, mesh: Mesh, mat: Material, sail: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.set_script(RagdollPartScript)
	b.mass = mass_kg
	b.name = "Rag_" + pname
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	b.freeze = true
	b.visible = false
	get_parent().add_child(b)
	b.set("player_ref", self)
	b.set("part_name", pname)
	WindManager.register_sail_body(b, sail)
	_ragdoll_parts[pname] = b
	return b

func _capsule_shape(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s

func _build_ragdoll() -> void:
	if get_parent() == null:
		return
	var skin: Material = _mat_skin()
	var pajama: Material = GameMaterials.cotton_white()
	var jeans: Material = GameMaterials.denim()
	_ragdoll_body("pelvis", 12, _capsule_shape(0.19, 0.45), MeshBuilder.rounded_box(Vector3(0.4, 0.28, 0.27), 0.1), jeans, 0.30)
	_ragdoll_body("chest", 22, _capsule_shape(0.22, 0.7), MeshBuilder.capsule(0.21, 0.72), pajama, 0.45)
	_ragdoll_body("head", 6, _capsule_shape(0.14, 0.34), MeshBuilder.ellipsoid(0.14, Vector3.ONE), skin, 0.10)
	for side_name: String in ["l", "r"]:
		_ragdoll_body("upper_arm_" + side_name, 3, _capsule_shape(0.065, 0.42), MeshBuilder.capsule(0.065, 0.42), pajama, 0.07)
		_ragdoll_body("fore_arm_" + side_name, 2.5, _capsule_shape(0.055, 0.42), MeshBuilder.capsule(0.055, 0.4), skin, 0.06)
		_ragdoll_body("thigh_" + side_name, 9, _capsule_shape(0.085, 0.55), MeshBuilder.capsule(0.085, 0.55), jeans, 0.12)
		_ragdoll_body("shin_" + side_name, 5.5, _capsule_shape(0.07, 0.52), MeshBuilder.capsule(0.07, 0.52), jeans, 0.09)
	# Юбка на тазе ragdoll'а (видимость по наряду)
	var pelvis := _ragdoll_parts["pelvis"] as RigidBody3D
	var skirt := MeshInstance3D.new()
	skirt.name = "RagSkirt"
	skirt.mesh = MeshBuilder.skirt_mesh(0.24, 0.55, 1.3)
	skirt.material_override = GameMaterials.silk(Color(1.0, 0.62, 0.72), "silk_pink_albedo")
	skirt.position = Vector3(0, -0.55, 0)
	skirt.visible = false
	pelvis.add_child(skirt)
	# Суставы создадим при первой активации, когда тела расставлены по позе.

func _ragdoll_place() -> void:
	# Расставляем кости по текущим глобальным позам визуальных пивотов
	var root_xf: Transform3D = _body_root.global_transform
	var place: Dictionary = {
		"pelvis": root_xf,
		"chest": _chest_pivot.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)),
		"head": _head_pivot.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0)),
		"upper_arm_l": _shoulder_l.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.16, 0)),
		"fore_arm_l": _elbow_l.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.15, 0)),
		"upper_arm_r": _shoulder_r.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.16, 0)),
		"fore_arm_r": _elbow_r.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.15, 0)),
		"thigh_l": _hip_l.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.24, 0)),
		"shin_l": _knee_l.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.22, 0)),
		"thigh_r": _hip_r.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.24, 0)),
		"shin_r": _knee_r.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.22, 0)),
	}
	for pname: String in place.keys():
		var b := _ragdoll_parts[pname] as RigidBody3D
		b.global_transform = place[pname]
		b.linear_velocity = velocity
		b.angular_velocity = Vector3.ZERO

func _ragdoll_connect(a: String, b: String, at: Vector3, swing: float, twist: float) -> void:
	var joint := ConeTwistJoint3D.new()
	get_parent().add_child(joint)
	joint.global_position = at
	joint.node_a = joint.get_path_to(_ragdoll_parts[a] as Node)
	joint.node_b = joint.get_path_to(_ragdoll_parts[b] as Node)
	joint.swing_span = swing
	joint.twist_span = twist
	joint.softness = 0.7
	joint.relaxation = 0.9
	_ragdoll_joints.append(joint)

func _ragdoll_build_joints() -> void:
	for j: Joint3D in _ragdoll_joints:
		j.queue_free()
	_ragdoll_joints.clear()
	var p := func(n: String, off: Vector3) -> Vector3:
		return (_ragdoll_parts[n] as RigidBody3D).global_transform * off
	_ragdoll_connect("pelvis", "chest", p.call("pelvis", Vector3(0, 0.18, 0)), 0.5, 0.4)
	_ragdoll_connect("chest", "head", p.call("chest", Vector3(0, 0.38, 0)), 0.6, 0.5)
	for s: String in ["l", "r"]:
		_ragdoll_connect("chest", "upper_arm_" + s, p.call("upper_arm_" + s, Vector3(0, 0.2, 0)), 1.6, 0.8)
		_ragdoll_connect("upper_arm_" + s, "fore_arm_" + s, p.call("fore_arm_" + s, Vector3(0, 0.2, 0)), 1.4, 0.4)
		_ragdoll_connect("pelvis", "thigh_" + s, p.call("thigh_" + s, Vector3(0, 0.26, 0)), 1.2, 0.5)
		_ragdoll_connect("thigh_" + s, "shin_" + s, p.call("shin_" + s, Vector3(0, 0.25, 0)), 1.5, 0.3)

func enter_ragdoll() -> void:
	if mode == Mode.RAGDOLL or mode == Mode.THRONE or _ragdoll_parts.is_empty():
		return
	mode = Mode.RAGDOLL
	_ragdoll_place()
	_ragdoll_build_joints()
	for b: Variant in _ragdoll_parts.values():
		var rb := b as RigidBody3D
		rb.freeze = false
		rb.visible = true
	_model.visible = false
	_collision.disabled = true
	_ragdoll_still_time = 0.0
	_update_sail_areas()

func exit_ragdoll(stand_pos: Vector3) -> void:
	_clear_hold_joints()
	if _throne_pin != null:
		_throne_pin.queue_free()
		_throne_pin = null
	for b: Variant in _ragdoll_parts.values():
		var rb := b as RigidBody3D
		rb.freeze = true
		rb.visible = false
		rb.linear_velocity = Vector3.ZERO
	_model.visible = true
	_collision.disabled = false
	global_position = stand_pos
	velocity = Vector3.ZERO
	_air_time = 0.0
	_bounce_active = false
	if mode != Mode.DEAD:
		mode = Mode.NORMAL

func ragdoll_center() -> Vector3:
	if _ragdoll_parts.has("pelvis"):
		return (_ragdoll_parts["pelvis"] as RigidBody3D).global_position
	return global_position + Vector3.UP

func ragdoll_speed() -> float:
	if _ragdoll_parts.has("pelvis"):
		return (_ragdoll_parts["pelvis"] as RigidBody3D).linear_velocity.length()
	return 0.0

func _update_sail_areas() -> void:
	# Задраный подол = парус: ветер несёт Юмика заметно сильнее
	if _ragdoll_parts.has("pelvis"):
		WindManager.set_sail_area(_ragdoll_parts["pelvis"] as RigidBody3D, 2.1 if (maid_outfit and hem_up) else 0.30)
	if _ragdoll_parts.has("chest"):
		WindManager.set_sail_area(_ragdoll_parts["chest"] as RigidBody3D, 0.9 if (maid_outfit and hem_up) else 0.45)

# ------------------------------------------------------------------ ввод ---
func set_move_input(v: Vector2, running: bool) -> void:
	_prev_input = _move_input
	_move_input = v
	_input_running = running
	# В няшинге дёрганье джойстика = вырывание
	if mode == Mode.CAPTURED and _capture_castle != null:
		var wiggle: float = (v - _prev_input).length()
		if wiggle > 0.06 or v.length() > 0.85:
			_capture_castle.on_player_struggle(wiggle * 2.2 + (0.12 if v.length() > 0.85 else 0.0))

func add_camera_delta(d: Vector2) -> void:
	_cam_yaw -= d.x * 0.0042
	_cam_pitch = clampf(_cam_pitch + d.y * 0.0034, -0.25, 1.25)

func is_running_now() -> bool:
	return _input_running and _move_input.length() > 0.55 and mode == Mode.NORMAL

func press_jump() -> void:
	match mode:
		Mode.NORMAL, Mode.CRAWL:
			if _in_water:
				velocity.y = 3.2
				return
			if not is_on_floor():
				return
			var bouncy: bool = _surface == "bouncy" or _surface == "very_bouncy" or _surface == "throne"
			var run_leap: bool = velocity.slide(Vector3.UP).length() > 3.4
			var h: float
			if run_leap:
				h = 4.5 if bouncy else 0.45 # «припрыжка» в беге
				_pending_prone = true
				var fwd: Vector3 = -Basis(Vector3.UP, _facing_yaw).z
				velocity.x += fwd.x * 2.0
				velocity.z += fwd.z * 2.0
			else:
				h = 3.5 if bouncy else 0.35
			_bounce_origin_h = h
			_bounce_step = 0
			_bounce_active = true
			velocity.y = sqrt(2.0 * _gravity() * h)
			_land_squash = -0.6
			if bouncy:
				AudioManager.play_sfx("boing_" + str(randi() % 3 + 1), -8.0)
			if mode == Mode.CRAWL:
				mode = Mode.NORMAL
		Mode.LYING:
			mode = Mode.NORMAL
		Mode.CLIMB:
			# Прыжок от стены
			mode = Mode.NORMAL
			squeezing = false
			velocity = _climb_normal * 3.2 + Vector3.UP * 3.4
			_bounce_active = false
		Mode.RAGDOLL:
			_try_stand_from_ragdoll()
		Mode.THRONE:
			exit_throne()

func toggle_lie() -> void:
	if mode == Mode.LYING:
		mode = Mode.NORMAL
	elif mode == Mode.NORMAL or mode == Mode.CRAWL:
		mode = Mode.LYING
		# Джойстик вперёд — на живот, иначе на спину
		_lie_prone = _move_input.y < -0.35
		velocity.x = 0
		velocity.z = 0

func toggle_crawl() -> void:
	if mode == Mode.CRAWL:
		mode = Mode.NORMAL
	elif mode == Mode.NORMAL or mode == Mode.LYING:
		mode = Mode.CRAWL

func toggle_climb() -> void:
	if mode == Mode.CLIMB:
		mode = Mode.NORMAL
		squeezing = false
		return
	if mode != Mode.NORMAL and mode != Mode.CRAWL:
		return
	if _try_start_climb(false):
		mode = Mode.CLIMB

func press_squeeze() -> void:
	if mode == Mode.CAPTURED and _capture_castle != null:
		_capture_castle.on_player_hug_back() # тискать в ответ
		_hug_timer = 1.2
		return
	if mode == Mode.CLIMB:
		squeezing = not squeezing
		if squeezing:
			_climb_slip_vel = 0.0
			_touch_god_if_close(true)
		return
	if mode == Mode.NORMAL or mode == Mode.CRAWL:
		if _try_start_climb(true):
			mode = Mode.CLIMB
			squeezing = true
			_touch_god_if_close(true)

func toggle_hem() -> void:
	if not maid_outfit:
		return
	hem_up = not hem_up
	_dress_normal.visible = not hem_up
	_dress_raised.visible = hem_up
	_update_sail_areas()
	if hem_up:
		AudioManager.play_sfx("pvc_squeak_2", -14.0)

func toggle_hold_on() -> void:
	if hold_on:
		hold_on = false
		_clear_hold_joints()
		return
	# «Не отпускай меня»: работает, пока Юмик держится (лазание/тисканье)
	if mode != Mode.CLIMB or _climb_body == null:
		return
	var body_node := _climb_body as Node
	var grab_points: Array[Vector3] = [
		_elbow_l.global_transform * Vector3(0, -0.36, 0),
		_elbow_r.global_transform * Vector3(0, -0.36, 0),
	]
	hold_on = true
	enter_ragdoll()
	if body_node == null:
		return
	for i: int in 2:
		var hand := _ragdoll_parts["fore_arm_" + ("l" if i == 0 else "r")] as RigidBody3D
		var joint := PinJoint3D.new()
		get_parent().add_child(joint)
		joint.global_position = grab_points[i]
		joint.node_a = joint.get_path_to(hand)
		joint.node_b = joint.get_path_to(body_node)
		_hold_joints.append(joint)
	AudioManager.play_sfx("chime_magic", -10.0)

func _clear_hold_joints() -> void:
	for j: Joint3D in _hold_joints:
		j.queue_free()
	_hold_joints.clear()
	hold_on = false

func try_toggle_outfit() -> void:
	var castle = GameState.castle
	if castle == null or not castle.has_method("is_near_wardrobe"):
		return
	if not castle.is_near_wardrobe(global_position):
		return
	maid_outfit = not maid_outfit
	hem_up = false
	_dress_normal.visible = true
	_dress_raised.visible = false
	_apply_outfit()
	AudioManager.play_sfx("chime_magic", -6.0)

func _apply_outfit() -> void:
	_dress_group.visible = maid_outfit
	_headband.visible = maid_outfit
	_chest_mesh.material_override = GameMaterials.silk(Color(1.0, 0.62, 0.72), "silk_pink_albedo") if maid_outfit else GameMaterials.cotton_white()
	var leg_mat: Material = GameMaterials.silk(Color(0.55, 0.75, 1.0), "silk_blue_albedo") if maid_outfit else GameMaterials.denim()
	for lm: MeshInstance3D in _leg_meshes:
		lm.material_override = leg_mat
	var foot_mat: Material = GameMaterials.plain(Color(0.98, 0.98, 1.0), 0.25) if maid_outfit else GameMaterials.plain(Color(0.15, 0.12, 0.1), 0.6)
	for fm: MeshInstance3D in _foot_meshes:
		fm.material_override = foot_mat
	if _ragdoll_parts.has("pelvis"):
		var skirt := (_ragdoll_parts["pelvis"] as RigidBody3D).get_node_or_null("RagSkirt") as MeshInstance3D
		if skirt != null:
			skirt.visible = maid_outfit
	_update_sail_areas()

# -------------------------------------------------------------- захват -----
func enter_captured(castle) -> void:
	_capture_castle = castle
	if mode == Mode.RAGDOLL or mode == Mode.THRONE:
		exit_ragdoll(global_position)
	mode = Mode.CAPTURED
	_collision.disabled = true
	velocity = Vector3.ZERO

func exit_captured(by_escape: bool) -> void:
	_cutscene_orbit = false
	_collision.disabled = false
	mode = Mode.LYING
	_lie_prone = false
	_getup_timer = 1.4 if not by_escape else 0.5
	if by_escape:
		velocity = Vector3.UP * 4.5 + Basis(Vector3.UP, _cam_yaw) * Vector3(0, 0, 3.5)
		mode = Mode.NORMAL
	_capture_castle = null
	set_squash(0.0)

func enter_sleep_cutscene(castle) -> void:
	_capture_castle = castle
	mode = Mode.SLEEP
	_collision.disabled = true
	_cutscene_orbit = true
	_cutscene_target = castle as Node3D

func set_weakened(v: bool) -> void:
	weakened = v

func set_squash(k: float) -> void:
	_squash_k = clampf(k, 0.0, 1.0)

func die() -> void:
	if mode == Mode.DEAD:
		return
	var at: Vector3 = global_position
	if mode == Mode.THRONE:
		exit_throne()
	if _ragdoll_parts.is_empty():
		mode = Mode.DEAD
	elif (_ragdoll_parts["pelvis"] as RigidBody3D).visible:
		at = ragdoll_center()
		mode = Mode.DEAD
	else:
		enter_ragdoll() # тело падает ragdoll'ом на месте гибели
		mode = Mode.DEAD
	GameState.kill_player(at)

func respawn_at(pos: Vector3) -> void:
	weakened = false
	exit_ragdoll(pos)
	mode = Mode.NORMAL

func teleport_to(pos: Vector3) -> void:
	if mode == Mode.RAGDOLL or mode == Mode.THRONE or mode == Mode.DEAD:
		exit_ragdoll(pos)
	global_position = pos
	velocity = Vector3.ZERO
	mode = Mode.NORMAL

# ------------------------------------------------------------------- трон --
func enter_throne(castle: Node3D) -> void:
	if mode == Mode.THRONE:
		return
	enter_ragdoll()
	mode = Mode.THRONE
	var seat: Transform3D = castle.call("throne_seat_global")
	var pelvis := _ragdoll_parts["pelvis"] as RigidBody3D
	pelvis.global_transform = seat
	_throne_pin = PinJoint3D.new()
	get_parent().add_child(_throne_pin)
	_throne_pin.global_position = seat.origin
	_throne_pin.node_a = _throne_pin.get_path_to(pelvis)
	_throne_pin.node_b = _throne_pin.get_path_to(castle)
	castle.call("begin_throne_squeeze")

func exit_throne() -> void:
	if GameState.castle != null and GameState.castle.has_method("end_throne_squeeze"):
		GameState.castle.call("end_throne_squeeze")
	if _throne_pin != null:
		_throne_pin.queue_free()
		_throne_pin = null
	mode = Mode.RAGDOLL
	if _ragdoll_parts.has("pelvis"):
		(_ragdoll_parts["pelvis"] as RigidBody3D).apply_central_impulse(Vector3.UP * 260.0)

# ----------------------------------------------------------------- физика --
func _gravity() -> float:
	return get_gravity().length()

func _try_start_climb(_want_squeeze: bool) -> bool:
	var hit: Dictionary = _climb_raycast()
	if hit.is_empty():
		return false
	_climb_body = hit["collider"]
	_climb_normal = hit["normal"]
	_climb_slip_vel = 0.0
	var col_node := _climb_body as Node
	_climb_rope_seg = (_climb_body as RigidBody3D) if (col_node != null and col_node.is_in_group("rope")) else null
	return true

func _climb_raycast() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 1.3
	var facing: Vector3 = -Basis(Vector3.UP, _facing_yaw).z
	var to: Vector3 = from + facing * 1.35
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)

func _touch_god_if_close(force: bool) -> void:
	var castle = GameState.castle
	if castle == null or not castle.has_method("god_global_pos"):
		return
	if global_position.distance_to(castle.god_global_pos()) < 5.0:
		if force or _god_touch_cooldown <= 0.0:
			_god_touch_cooldown = 1.2
			castle.on_god_touched()

func _try_stand_from_ragdoll() -> void:
	if hold_on:
		return
	if ragdoll_speed() < 2.2:
		var pos: Vector3 = ragdoll_center()
		exit_ragdoll(pos + Vector3.UP * 0.2)

func _physics_process(delta: float) -> void:
	_god_touch_cooldown = maxf(0.0, _god_touch_cooldown - delta)
	_hug_timer = maxf(0.0, _hug_timer - delta)
	# Следование за замком-платформой
	_follow_castle_platform()
	match mode:
		Mode.NORMAL, Mode.CRAWL, Mode.LYING:
			_move_ground(delta)
		Mode.CLIMB:
			_move_climb(delta)
		Mode.CAPTURED, Mode.SLEEP:
			if _capture_castle != null and _capture_castle.has_method("capture_global_transform"):
				global_transform = _capture_castle.capture_global_transform()
				velocity = Vector3.ZERO
		Mode.RAGDOLL, Mode.THRONE, Mode.DEAD:
			if mode == Mode.RAGDOLL and not hold_on:
				if ragdoll_speed() < 0.7:
					_ragdoll_still_time += delta
					if _ragdoll_still_time > 0.9:
						_try_stand_from_ragdoll()
				else:
					_ragdoll_still_time = 0.0
			# Синхронизируем позицию CharacterBody с тазом (HUD/камера/спавн)
			if not _ragdoll_parts.is_empty():
				global_position = ragdoll_center() - Vector3.UP * 0.9
	if _getup_timer > 0.0 and mode == Mode.LYING:
		_getup_timer -= delta
		if _getup_timer <= 0.0:
			mode = Mode.NORMAL

func _follow_castle_platform() -> void:
	var castle = GameState.castle
	if castle == null:
		return
	var castle3d := castle as Node3D
	var now_xf: Transform3D = castle3d.global_transform
	var riding: bool = _on_castle and (mode == Mode.NORMAL or mode == Mode.CRAWL or mode == Mode.LYING or mode == Mode.CLIMB)
	if riding:
		var delta_xf: Transform3D = now_xf * _last_castle_xf.affine_inverse()
		global_position = delta_xf * global_position
		velocity = delta_xf.basis * velocity
	_last_castle_xf = now_xf

func _move_ground(delta: float) -> void:
	var g: float = _gravity()
	_prev_vy = velocity.y
	# Вода: плавание у поверхности y=0
	var was_in_water: bool = _in_water
	_in_water = global_position.y < 0.15
	if _in_water and not was_in_water:
		AudioManager.play_sfx("splash", -8.0)
		_bounce_active = false
	# Желаемое направление из джойстика (камера-относительно)
	var wish: Vector3 = Vector3.ZERO
	var speed_mul: float = 0.35 if weakened else 1.0
	if mode != Mode.LYING and _move_input.length() > 0.08:
		var cam_basis := Basis(Vector3.UP, _cam_yaw)
		wish = (cam_basis * Vector3(_move_input.x, 0, _move_input.y)).normalized()
		var mag: float = clampf(_move_input.length(), 0.0, 1.0)
		var base_speed: float = CRAWL_SPEED if mode == Mode.CRAWL else (RUN_SPEED if _input_running else WALK_SPEED)
		wish *= base_speed * mag * speed_mul
		_facing_yaw = atan2(-wish.x, -wish.z)
	if _in_water:
		wish *= 0.45
		velocity.y = lerpf(velocity.y, clampf((0.05 - global_position.y) * 3.0, -1.2, 2.2), delta * 5.0)
	else:
		velocity.y -= g * delta
	# Внешние течения: всасывание, порывы в зале, циклон, ветер в подол
	var external: Vector3 = Vector3.ZERO
	var castle = GameState.castle
	if castle != null and castle.has_method("suction_velocity_at"):
		external += castle.suction_velocity_at(global_position + Vector3.UP)
		external += castle.interior_gust_velocity()
	var cyclone = get_tree().get_first_node_in_group("cyclone")
	if cyclone != null and cyclone.has_method("wind_velocity_at"):
		external += cyclone.wind_velocity_at(global_position + Vector3.UP)
	var wind: Vector3 = WindManager.wind_vector()
	if maid_outfit and hem_up:
		external += wind * 0.55 # подол-парус тянет за ветром
		if wind.length() > 14.0 and not is_on_floor():
			external.y += (wind.length() - 14.0) * 0.35
	elif wind.length() > 16.0:
		external += wind * 0.16 # ураган мешает идти
	var accel: float = 14.0 if is_on_floor() else 2.2
	velocity.x = lerpf(velocity.x, wish.x + external.x, clampf(accel * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, wish.z + external.z, clampf(accel * delta, 0.0, 1.0))
	if external.y > 0.5 and not _in_water:
		velocity.y = lerpf(velocity.y, external.y, delta * 2.5)
	var was_on_floor: bool = is_on_floor()
	move_and_slide()
	_update_floor_surface()
	# Воздух: дольше 1 с без опоры — ragdoll (но не во время осознанных
	# прыжков/пост-прыжков, иначе батут-цепочки были бы невозможны)
	if is_on_floor() or _in_water:
		_air_time = 0.0
	else:
		_air_time += delta
		if _air_time > 1.0 and not _bounce_active and velocity.y < 1.0:
			enter_ragdoll()
			return
	# Приземление
	if is_on_floor() and not was_on_floor:
		_on_landed(-_prev_vy)
	# Шаги
	var h_speed: float = velocity.slide(Vector3.UP).length()
	if is_on_floor() and h_speed > 0.4 and mode != Mode.LYING:
		_step_acc += h_speed * delta
		_walk_phase += delta * h_speed * 2.1
		if _step_acc > 2.2:
			_step_acc = 0.0
			if _surface == "bouncy" or _surface == "very_bouncy":
				AudioManager.play_sfx("pvc_squeak_" + str(randi() % 4 + 1), -18.0)
			else:
				AudioManager.play_sfx("step_soft_" + str(randi() % 2 + 1), -14.0)
	# Сидение на троне: приземление на сиденье трона внутри замка
	if _surface == "throne" and is_on_floor() and h_speed < 1.2:
		var lp: Vector3 = (GameState.castle as Node3D).to_local(global_position) if GameState.castle != null else Vector3.ZERO
		if lp.z < -11.5 and absf(lp.x) < 1.6:
			enter_throne(GameState.castle as Node3D)
	# Упал в бездну (сбой чанка) — смерть и воскрешение
	if global_position.y < -80.0:
		die()

func _update_floor_surface() -> void:
	_on_castle = false
	if not is_on_floor():
		_surface = "air"
		_floor_body = null
		return
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		if col.get_normal().y < 0.55:
			continue
		var collider: Object = col.get_collider()
		_floor_body = collider
		var node := collider as Node
		if node != null and node.is_in_group("castle"):
			_on_castle = true
			_surface = (node as Node).call("get_surface_type", col.get_collider_shape_index())
		elif node != null and node.is_in_group("rope"):
			_surface = "rope"
		else:
			_surface = "ground"
		return

func _on_landed(impact: float) -> void:
	var g: float = _gravity()
	_land_squash = clampf(impact * 0.05, 0.1, 0.7)
	var bouncy: bool = _surface == "bouncy" or _surface == "throne"
	if _surface == "very_bouncy" or bouncy:
		var h_eq: float = (impact * impact) / (2.0 * g)
		var next_h: float = 0.0
		if _surface == "very_bouncy":
			# «Очень прыгучий»: высота отскока не падает
			if h_eq > 0.25:
				next_h = h_eq
				_bounce_active = true
				_bounce_origin_h = h_eq
		elif _bounce_active:
			var factors: Array[float] = [0.5, 0.25, 0.1]
			if _bounce_step < factors.size():
				next_h = _bounce_origin_h * factors[_bounce_step]
				_bounce_step += 1
			else:
				_bounce_active = false
		elif h_eq > 0.5:
			_bounce_origin_h = h_eq
			_bounce_step = 1
			_bounce_active = true
			next_h = h_eq * 0.5
		if next_h > 0.12:
			velocity.y = sqrt(2.0 * g * next_h)
			AudioManager.play_sfx("boing_" + str(randi() % 3 + 1), -9.0)
			return
		# Цепочка закончилась
		_bounce_active = false
		if _pending_prone:
			_pending_prone = false
			mode = Mode.LYING
			_lie_prone = true
			_getup_timer = 0.8
		AudioManager.play_sfx("pvc_squeak_" + str(randi() % 4 + 1), -12.0)
		return
	# Твёрдая земля
	_bounce_active = false
	if _in_water:
		return
	if impact > 19.0:
		die()
		return
	if impact > 10.5:
		enter_ragdoll() # жёсткое падение — кувырок ragdoll'ом
		return
	if _pending_prone:
		_pending_prone = false
		mode = Mode.LYING
		_lie_prone = true
		_getup_timer = 0.8

func _move_climb(delta: float) -> void:
	if _climb_rope_seg != null and is_instance_valid(_climb_rope_seg):
		_move_climb_rope(delta)
		return
	var hit: Dictionary = _climb_raycast()
	if hit.is_empty():
		mode = Mode.NORMAL
		squeezing = false
		return
	_climb_body = hit["collider"]
	_climb_normal = hit["normal"]
	var col_node := _climb_body as Node
	if col_node != null and col_node.is_in_group("rope"):
		_climb_rope_seg = _climb_body as RigidBody3D
		return
	_on_castle = col_node != null and col_node.is_in_group("castle")
	# Скользкость поверхности: ПВХ скользит сильнее камня
	var slip: float = 0.25
	var surface: String = "ground"
	if _on_castle:
		surface = col_node.call("get_surface_type", int(hit.get("shape", 0)))
		slip = 0.92 if surface == "very_bouncy" else 0.75
	if squeezing:
		slip *= 0.12
	var n: Vector3 = _climb_normal
	var up_t: Vector3 = (Vector3.UP - n * Vector3.UP.dot(n)).normalized()
	var right_t: Vector3 = n.cross(up_t).normalized()
	# Соскальзывание под гравитацией вдоль поверхности
	var slope_pull: float = _gravity() * clampf(1.0 - n.y, 0.0, 1.0) * slip
	_climb_slip_vel = clampf(_climb_slip_vel + slope_pull * delta, 0.0, 4.0)
	if _move_input.y < -0.1:
		_climb_slip_vel = maxf(0.0, _climb_slip_vel - delta * 9.0) # лезем вверх — держимся
	var climb_speed: float = 0.95 if squeezing else 1.45
	var wish: Vector3 = up_t * (-_move_input.y * climb_speed - _climb_slip_vel) + right_t * (_move_input.x * climb_speed)
	# Хватка против ветра и инерции поверхности
	var wind_f: float = 0.5 * 1.225 * pow(WindManager.wind_vector().length(), 2.0) * 0.7
	var grip: float = 2600.0 if squeezing else 950.0
	var surface_pull: float = 0.0
	if _climb_body is RigidBody3D:
		surface_pull = (_climb_body as RigidBody3D).angular_velocity.length() * 420.0
	if wind_f + surface_pull > grip and randf() < delta * 2.0:
		# Сорвало!
		mode = Mode.NORMAL
		squeezing = false
		velocity = n * 2.5 + WindManager.wind_vector() * 0.5
		enter_ragdoll()
		return
	# Прижимаемся к поверхности и движемся вдоль неё
	var anchor: Vector3 = hit["position"] + n * 0.42
	var to_anchor: Vector3 = (anchor - (global_position + Vector3.UP * 1.05))
	velocity = wish + to_anchor / maxf(delta, 0.001) * 0.5
	velocity = velocity.limit_length(7.0)
	_facing_yaw = atan2(n.x, n.z)
	move_and_slide()
	_walk_phase += delta * (3.0 if _move_input.length() > 0.1 else 0.6)
	_touch_god_if_close(false)

func _move_climb_rope(delta: float) -> void:
	var seg: RigidBody3D = _climb_rope_seg
	if seg == null or not is_instance_valid(seg):
		mode = Mode.NORMAL
		return
	# Вертикальный ввод двигает хват вверх/вниз по цепочке сегментов
	_rope_switch_timer = maxf(0.0, _rope_switch_timer - delta)
	var castle = GameState.castle
	if castle != null and absf(_move_input.y) > 0.55 and _rope_switch_timer <= 0.0:
		_rope_switch_timer = 0.38
		var idx: int = int(seg.get_meta("rope_index", 0))
		var want: int = idx - 1 if _move_input.y < 0.0 else idx + 1
		for rope: Variant in (castle.get("ropes") as Array):
			var arr := rope as Array
			if arr.has(seg) and want >= 0 and want < arr.size():
				_climb_rope_seg = arr[want] as RigidBody3D
				break
	var anchor: Vector3 = seg.global_position
	var target: Vector3 = anchor - Vector3.UP * 1.15 + Basis(Vector3.UP, _cam_yaw) * Vector3(0, 0, 0.35)
	velocity = (target - global_position) / maxf(delta, 0.001) * 0.55
	velocity = velocity.limit_length(9.0)
	_facing_yaw = atan2(-(anchor.x - global_position.x), -(anchor.z - global_position.z))
	move_and_slide()
	_walk_phase += delta * 2.4
	if randf() < delta * 0.4:
		AudioManager.play_sfx("rope_creak", -18.0, randf_range(0.9, 1.1))

# -------------------------------------------------------------- анимация ---
func _process(delta: float) -> void:
	_update_camera(delta)
	if _model.visible:
		_animate(delta)

func _animate(delta: float) -> void:
	_land_squash = move_toward(_land_squash, 0.0, delta * 3.2)
	var squash: float = clampf(_land_squash + _squash_k * 0.35, -0.6, 0.8)
	_model.scale = Vector3(1.0 + squash * 0.25, 1.0 - squash * 0.3, 1.0 + squash * 0.25)
	_model.rotation.y = lerp_angle(_model.rotation.y, _facing_yaw, clampf(delta * 12.0, 0.0, 1.0))
	var swing: float = sin(_walk_phase)
	var h_speed: float = velocity.slide(Vector3.UP).length()
	var moving: bool = h_speed > 0.35 and (mode == Mode.NORMAL or mode == Mode.CRAWL)
	# Базовые целевые позы пивотов по режиму
	var body_rot := Vector3.ZERO
	var body_y: float = 0.95
	var sh_l := Vector3.ZERO
	var sh_r := Vector3.ZERO
	var el_l := Vector3(-0.25, 0, 0)
	var el_r := Vector3(-0.25, 0, 0)
	var hip_l := Vector3.ZERO
	var hip_r := Vector3.ZERO
	var knee_l := Vector3.ZERO
	var knee_r := Vector3.ZERO
	match mode:
		Mode.NORMAL:
			if moving:
				var amp: float = 0.65 if h_speed > 3.0 else 0.4
				sh_l.x = swing * amp
				sh_r.x = -swing * amp
				hip_l.x = -swing * amp
				hip_r.x = swing * amp
				knee_l.x = maxf(-cos(_walk_phase), 0.0) * 0.7
				knee_r.x = maxf(cos(_walk_phase), 0.0) * 0.7
				el_l.x = -0.3 - maxf(swing, 0.0) * 0.5
				el_r.x = -0.3 - maxf(-swing, 0.0) * 0.5
				body_y += absf(cos(_walk_phase)) * 0.04
			elif not is_on_floor():
				sh_l = Vector3(-0.7, 0, 0.85) # руки в стороны в полёте
				sh_r = Vector3(-0.7, 0, -0.85)
				hip_l.x = 0.25
				hip_r.x = -0.15
				knee_l.x = 0.4
				knee_r.x = 0.2
		Mode.CRAWL: # четвереньки
			body_rot.x = 1.15
			body_y = 0.52
			sh_l.x = -1.35 + swing * 0.5
			sh_r.x = -1.35 - swing * 0.5
			hip_l.x = 1.25 - swing * 0.45
			hip_r.x = 1.25 + swing * 0.45
			knee_l.x = 1.5
			knee_r.x = 1.5
		Mode.LYING:
			body_rot.x = -1.5 if not _lie_prone else 1.5
			body_y = 0.22
			sh_l = Vector3(0.2, 0, 0.5)
			sh_r = Vector3(0.2, 0, -0.5)
			hip_l.x = 0.08
			hip_r.x = -0.06
		Mode.CLIMB:
			body_rot.x = 0.25
			if squeezing:
				var pulse: float = 0.5 + 0.5 * sin(_walk_phase * 2.2)
				sh_l = Vector3(-2.4, 0, 0.55 + pulse * 0.3)
				sh_r = Vector3(-2.4, 0, -0.55 - pulse * 0.3)
				el_l.x = -0.5 - pulse * 0.6
				el_r.x = -0.5 - pulse * 0.6
				hip_l = Vector3(0.7, 0, 0.4 + pulse * 0.15)
				hip_r = Vector3(0.7, 0, -0.4 - pulse * 0.15)
				knee_l.x = 1.1
				knee_r.x = 1.1
			else:
				sh_l.x = -2.6 + swing * 0.45
				sh_r.x = -2.6 - swing * 0.45
				el_l.x = -0.35
				el_r.x = -0.35
				hip_l.x = 0.55 - swing * 0.35
				hip_r.x = 0.55 + swing * 0.35
				knee_l.x = 0.9
				knee_r.x = 0.9
		Mode.CAPTURED, Mode.SLEEP:
			body_rot.x = -1.5
			body_y = 0.22
			var struggle: float = _move_input.length()
			var wiggle: float = sin(Time.get_ticks_msec() * 0.02) * struggle * 0.7
			if _hug_timer > 0.0 or mode == Mode.SLEEP:
				sh_l = Vector3(-1.9, 0, 0.4) # обнимает в ответ
				sh_r = Vector3(-1.9, 0, -0.4)
				el_l.x = -0.7
				el_r.x = -0.7
			else:
				sh_l = Vector3(wiggle, 0, 0.65)
				sh_r = Vector3(-wiggle, 0, -0.65)
			hip_l.x = wiggle * 0.6
			hip_r.x = -wiggle * 0.6
			knee_l.x = 0.25 + absf(wiggle) * 0.4
			knee_r.x = 0.25
	var k: float = clampf(delta * 11.0, 0.0, 1.0)
	_body_root.rotation = _body_root.rotation.lerp(body_rot, k)
	_body_root.position.y = lerpf(_body_root.position.y, body_y, k)
	_shoulder_l.rotation = _shoulder_l.rotation.lerp(sh_l, k)
	_shoulder_r.rotation = _shoulder_r.rotation.lerp(sh_r, k)
	_elbow_l.rotation = _elbow_l.rotation.lerp(el_l, k)
	_elbow_r.rotation = _elbow_r.rotation.lerp(el_r, k)
	_hip_l.rotation = _hip_l.rotation.lerp(hip_l, k)
	_hip_r.rotation = _hip_r.rotation.lerp(hip_r, k)
	_knee_l.rotation = _knee_l.rotation.lerp(knee_l, k)
	_knee_r.rotation = _knee_r.rotation.lerp(knee_r, k)
	# Задраный подол болтается на ветру
	if maid_outfit and hem_up:
		_dress_raised.rotation.z = sin(Time.get_ticks_msec() * 0.006) * clampf(WindManager.wind_speed_ms() * 0.02, 0.03, 0.4)
	# Фонарь смотрит туда же, куда камера
	_flashlight.rotation = Vector3(-_cam_pitch + 0.32, wrapf(_cam_yaw - _facing_yaw, -PI, PI) * 0.6, 0)

func _update_camera(delta: float) -> void:
	var target: Vector3 = global_position + Vector3.UP * 1.55
	var dist: float = 5.5
	if mode == Mode.RAGDOLL or mode == Mode.THRONE or mode == Mode.DEAD:
		target = ragdoll_center()
	if _cutscene_orbit and _cutscene_target != null:
		# Сон: медленная орбита вокруг Бога и спящего Юмика
		_cam_yaw += delta * 0.14
		_cam_pitch = lerpf(_cam_pitch, 0.42, delta)
		target = (_cutscene_target as Node3D).to_global(Vector3(0, 3.6, 0.5))
		dist = 8.5
	elif mode == Mode.CAPTURED and _capture_castle != null:
		target = global_position + Vector3.UP * 0.8
		dist = 4.2
	_spring.spring_length = lerpf(_spring.spring_length, dist, delta * 3.0)
	_cam_pivot.global_position = _cam_pivot.global_position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
	_cam_pivot.rotation = Vector3(-_cam_pitch, _cam_yaw, 0)

## Точка спавна камеры за спиной: смотрим на замок (-Z от игрока на юг).
func setup_spawn(pos: Vector3, face_yaw: float) -> void:
	global_position = pos
	_facing_yaw = face_yaw
	_cam_yaw = face_yaw
	_cam_pitch = 0.28
	_model.rotation.y = face_yaw
	_cam_pivot.global_position = pos + Vector3.UP * 1.55
	_cam_pivot.rotation = Vector3(-_cam_pitch, _cam_yaw, 0)

func set_flashlight(on: bool) -> void:
	_flashlight.visible = on
