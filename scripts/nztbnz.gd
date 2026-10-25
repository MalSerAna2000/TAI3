extends AeroBody3D
class_name CastleNZTB
## НЗТБНЗ — Надувной Замок Темного Бога Надувных Замков (33×33×33 м, ПВХ 0.35 мм,
## камеры 2 м, готика, тёмно-красный). Одно тело AeroBody3D (Jolt + Aerodynamic
## Physics): все стены/крылья/башни/тело Бога — CollisionShape3D этого тела,
## тип поверхности по индексу шейпа ("bouncy" / "very_bouncy" / "pvc" / "throne").
## Состояния меняются каждые 60 игровых минут: Обычное / Всасывание / Летающее.
## ТБНЗ внутри — и есть сам замок: ног нет, туловище переходит в надувной пол.

signal state_changed(state_name: String)
signal gate_changed(is_open: bool)
signal nyashing_started
signal nyashing_ended
signal sleep_started
signal sleep_finished
signal player_inside_changed(inside: bool)
signal toast(text: String)

enum CastleState { NORMAL, SUCTION, FLYING }
const STATE_NAMES: Array[String] = ["Обычное", "Всасывание", "Летающее"]

const FLOOR_TOP_Y: float = 2.0 # верх надувного пола в локальной СК замка
const HALL_HALF: float = 14.4 # внутренняя граница зала
const CAPTURE_LOCAL: Vector3 = Vector3(0, FLOOR_TOP_Y + 0.45, 3.2) # точка няшинга перед Богом

var state: int = CastleState.NORMAL
var _state_timer_min: float = 0.0 # игровых минут в текущем состоянии

# --- Реестр частей ---
var _shape_surfaces: Array[String] = [] # индекс шейпа -> тип поверхности
var _wings: Array[Dictionary] = [] # большие крылья замка (З/С/В)
var _god_wings: Array[Dictionary] = []
var _throne_wings: Array[Dictionary] = []
var _soft_parts: Array[Dictionary] = [] # пружинные мягкие части (волосы/ушки)
var _god_shapes: Array[Dictionary] = [] # шейпы Бога: {cs, base_pos}
var _god_visual: Node3D
var _god_head: Node3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _mouth: MeshInstance3D
var _blush_l: MeshInstance3D
var _blush_r: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _god_bob_amp: float = 0.05
var _god_bob_phase: float = 0.0
var _emotion_timer: float = 0.0
var _blink_timer: float = 3.0
var _current_eyes: String = "eye_red_open"

var _gate_shape: CollisionShape3D
var _door_l: MeshInstance3D
var _door_r: MeshInstance3D
var gate_open: bool = true
var _gate_amount: float = 1.0 # 1 = врата открыты
var _gate_locked: bool = false
var _player_inside: bool = false
var _grounded_time: float = 0.0
var _contact_count: int = 0

var _flap_phase: float = 0.0
var _fly_heading: float = 0.0
var _fly_target_alt: float = 90.0

var ropes: Array = [] # массив массивов сегментов RigidBody3D

var _wardrobe_door: MeshInstance3D
var _wardrobe_open: float = 0.0
var throne_active: bool = false
var _throne_phase: float = 0.0

# --- Няшинг / сон ---
var nyashing_active: bool = false
var _nyash_progress_min: float = 0.0
var _nyash_escape: float = 0.0
var _nyash_hug_pause_min: float = 0.0
var _nyash_struggle_recent: float = 0.0
var _weakened: bool = false
var _squeak_timer: float = 0.0
var _hearts: CPUParticles3D
var _sleep_active: bool = false
var _sleep_t: float = 0.0
const SLEEP_REAL_SECONDS: float = 16.0

var _flap_audio: AudioStreamPlayer3D
var _suction_audio: AudioStreamPlayer3D
var _thud_cooldown: float = 0.0
var _interior_light: OmniLight3D
var _heart_light: OmniLight3D

# ------------------------------------------------------------------ стройка
func _ready() -> void:
	super._ready()
	add_to_group("castle")
	mass = 1400.0
	can_sleep = false
	continuous_cd = RigidBody3D.CCD_MODE_CAST_SHAPE
	linear_damp = 0.12
	angular_damp = 0.4
	contact_monitor = true
	max_contacts_reported = 8
	var pm := PhysicsMaterial.new()
	pm.friction = 0.45
	pm.bounce = 0.55
	physics_material_override = pm
	collision_layer = 4 | 16384 # слой 3 «Castle» + слой 15 «Atmosphere Areas» плагина
	collision_mask = 1 | 2 | 16 | 32 # мир, игрок, верёвки, ragdoll
	_build_structure()
	_build_god()
	_build_throne_and_wardrobe()
	_build_aero_surfaces()
	_build_lights_audio()
	# Верёвки строим после входа в дерево и выстановки глобального трансфорома
	call_deferred("_build_ropes")
	body_entered.connect(_on_body_entered)
	_set_gate(true, true)
	set_state(CastleState.NORMAL, true)

func _add_collision(shape: Shape3D, xf: Transform3D, surface: String) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	add_child(cs)
	_shape_surfaces.append(surface)
	return cs

func _add_part(mesh: Mesh, mat: Material, shape: Shape3D, xf: Transform3D, surface: String) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.transform = xf
	mi.visibility_range_end = 4000.0 # LOD по дальности
	add_child(mi)
	var cs: CollisionShape3D = null
	if shape != null:
		cs = _add_collision(shape, xf, surface)
	return {"mi": mi, "cs": cs, "base_xf": xf, "surface": surface}

func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s

func _build_structure() -> void:
	var pvc: Material = GameMaterials.pvc_darkred()
	var pvc_trim: Material = GameMaterials.lace_darkred()
	# Пол: надувная камера 33×2×33
	_add_part(MeshBuilder.rounded_box(Vector3(33, 2, 33), 0.9), pvc,
		_box_shape(Vector3(33, 2, 33)), Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "bouncy")
	# Холм пола вокруг Бога (его нижняя часть — сам пол)
	_add_part(MeshBuilder.ellipsoid(0.5, Vector3.ONE), pvc, null,
		Transform3D(Basis.from_scale(Vector3(7.5, 1.1, 7.5)), Vector3(0, FLOOR_TOP_Y, -2)), "bouncy")
	# Северная стена (целая), южная — с проёмом врат 3×7
	_add_part(MeshBuilder.rounded_box(Vector3(33, 29, 2), 0.9), pvc,
		_box_shape(Vector3(33, 29, 2)), Transform3D(Basis.IDENTITY, Vector3(0, 16.5, -15.5)), "bouncy")
	_add_part(MeshBuilder.rounded_box(Vector3(15, 7, 2), 0.9), pvc,
		_box_shape(Vector3(15, 7, 2)), Transform3D(Basis.IDENTITY, Vector3(-9, 5.5, 15.5)), "bouncy")
	_add_part(MeshBuilder.rounded_box(Vector3(15, 7, 2), 0.9), pvc,
		_box_shape(Vector3(15, 7, 2)), Transform3D(Basis.IDENTITY, Vector3(9, 5.5, 15.5)), "bouncy")
	_add_part(MeshBuilder.rounded_box(Vector3(33, 22, 2), 0.9), pvc,
		_box_shape(Vector3(33, 22, 2)), Transform3D(Basis.IDENTITY, Vector3(0, 20, 15.5)), "bouncy")
	# Западная и восточная стены
	_add_part(MeshBuilder.rounded_box(Vector3(2, 29, 29), 0.9), pvc,
		_box_shape(Vector3(2, 29, 29)), Transform3D(Basis.IDENTITY, Vector3(-15.5, 16.5, 0)), "bouncy")
	_add_part(MeshBuilder.rounded_box(Vector3(2, 29, 29), 0.9), pvc,
		_box_shape(Vector3(2, 29, 29)), Transform3D(Basis.IDENTITY, Vector3(15.5, 16.5, 0)), "bouncy")
	# Крыша
	_add_part(MeshBuilder.rounded_box(Vector3(33, 2, 33), 0.9), pvc,
		_box_shape(Vector3(33, 2, 33)), Transform3D(Basis.IDENTITY, Vector3(0, 32, 0)), "bouncy")
	# Готический декор: карниз-«кружево» по верху стен и арка врат
	_add_part(MeshBuilder.box(Vector3(34, 1.2, 34)), pvc_trim, null,
		Transform3D(Basis.IDENTITY, Vector3(0, 30.6, 0)), "pvc")
	_add_part(MeshBuilder.rounded_box(Vector3(4.6, 1.2, 2.6), 0.5), pvc_trim, null,
		Transform3D(Basis.IDENTITY, Vector3(0, 9.4, 15.5)), "pvc")
	# Врата: коллизия-проём + две створки (уезжают в стены)
	_gate_shape = _add_collision(_box_shape(Vector3(3, 7, 1.6)),
		Transform3D(Basis.IDENTITY, Vector3(0, 5.5, 15.5)), "bouncy")
	var door_mesh: Mesh = MeshBuilder.rounded_box(Vector3(1.5, 7, 1.0), 0.45)
	_door_l = MeshInstance3D.new()
	_door_l.mesh = door_mesh
	_door_l.material_override = pvc_trim
	_door_l.position = Vector3(-0.75, 5.5, 15.5)
	add_child(_door_l)
	_door_r = MeshInstance3D.new()
	_door_r.mesh = door_mesh
	_door_r.material_override = pvc_trim
	_door_r.position = Vector3(0.75, 5.5, 15.5)
	add_child(_door_r)
	# 4 угловые башни 5×50 м + шпили
	var tower_shape := CylinderShape3D.new()
	tower_shape.radius = 2.5
	tower_shape.height = 50.0
	for sx: float in [-16.5, 16.5]:
		for sz: float in [-16.5, 16.5]:
			_add_part(MeshBuilder.cylinder(2.5, 2.9, 50.0, 14), pvc, tower_shape,
				Transform3D(Basis.IDENTITY, Vector3(sx, 25, sz)), "bouncy")
			_add_part(MeshBuilder.cone(3.2, 8.0, 14), pvc_trim, null,
				Transform3D(Basis.IDENTITY, Vector3(sx, 54, sz)), "pvc")
	# Три больших крыла замка: Запад, Север, Восток; полуразмах 33 м.
	# Самые мягкие/скользкие/прыгучие части: surface = very_bouncy.
	_make_big_wing(Vector3(16.5, 20, 0), 0.0) # Восток (+X)
	_make_big_wing(Vector3(-16.5, 20, 0), PI) # Запад (-X)
	_make_big_wing(Vector3(0, 20, -16.5), PI * 0.5) # Север (-Z)

func _make_big_wing(pivot: Vector3, yaw: float) -> void:
	var mesh: Mesh = MeshBuilder.wing_mesh(33.0, 8.0, 1.6)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = GameMaterials.pvc_darkred()
	mi.visibility_range_end = 4000.0
	add_child(mi)
	var shape := _box_shape(Vector3(33, 5.5, 1.6))
	var cs: CollisionShape3D = _add_collision(shape, Transform3D.IDENTITY, "very_bouncy")
	var base_basis := Basis(Vector3.UP, yaw)
	var wing: Dictionary = {
		"mi": mi, "cs": cs, "pivot": pivot, "basis": base_basis,
		"shape_offset": Transform3D(Basis.IDENTITY, Vector3(16.5, 1.2, 0)),
	}
	_wings.append(wing)
	_update_wing(wing, 0.0)

## Поворот крыла вокруг продольной к замку оси (взмах вверх/вниз).
func _update_wing(wing: Dictionary, flap_angle: float) -> void:
	var tilt: float = float(wing.get("tilt", -1.05))
	var basis: Basis = (wing["basis"] as Basis) * Basis(Vector3.BACK, flap_angle) * Basis(Vector3.RIGHT, tilt)
	var xf := Transform3D(basis, wing["pivot"] as Vector3)
	(wing["mi"] as MeshInstance3D).transform = xf
	(wing["cs"] as CollisionShape3D).transform = xf * (wing["shape_offset"] as Transform3D)

# --------------------------------------------------------------------- Бог
func _build_god() -> void:
	_god_visual = Node3D.new()
	_god_visual.name = "TB NZ"
	_god_visual.position = Vector3(0, FLOOR_TOP_Y, -2)
	add_child(_god_visual)
	var dress: Material = GameMaterials.lace_darkred()
	var pvc_red: Material = GameMaterials.pvc_darkred()
	var white: Material = GameMaterials.pvc_white()
	var hair: Material = GameMaterials.hair_white()
	var skin: Material = GameMaterials.plain(Color(1.0, 0.87, 0.78), 0.5)
	# Юбка платья горничной Бога без подола — переходит в пол замка
	var skirt := MeshInstance3D.new()
	skirt.mesh = MeshBuilder.skirt_mesh(0.85, 3.4, 1.5)
	skirt.material_override = dress
	skirt.position = Vector3(0, 0.75, 0)
	_god_visual.add_child(skirt)
	var skirt_shape := CylinderShape3D.new()
	skirt_shape.radius = 2.6
	skirt_shape.height = 1.5
	_register_god_shape(skirt_shape, Vector3(0, FLOOR_TOP_Y + 0.75, -2))
	# Торс (надувной, мягкий)
	var torso := MeshInstance3D.new()
	torso.mesh = MeshBuilder.ellipsoid(0.5, Vector3.ONE)
	torso.material_override = dress
	torso.transform = Transform3D(Basis.from_scale(Vector3(1.7, 2.0, 1.15)), Vector3(0, 1.65, 0))
	_god_visual.add_child(torso)
	var chest_shape := SphereShape3D.new()
	chest_shape.radius = 0.8
	_register_god_shape(chest_shape, Vector3(0, FLOOR_TOP_Y + 1.65, -2))
	# Фартук и воротник из белого кружева
	var apron := MeshInstance3D.new()
	apron.mesh = MeshBuilder.box(Vector3(0.95, 1.1, 0.08))
	apron.material_override = GameMaterials.lace_white()
	apron.position = Vector3(0, 1.45, 0.52)
	apron.rotation_degrees.x = -8
	_god_visual.add_child(apron)
	var collar := MeshInstance3D.new()
	collar.mesh = MeshBuilder.cylinder(0.42, 0.55, 0.22, 16)
	collar.material_override = GameMaterials.lace_white()
	collar.position = Vector3(0, 2.28, 0)
	_god_visual.add_child(collar)
	# Голова (пивот для наклонов и лица), радиус 0.5, центр на 2.62 м над полом
	_god_head = Node3D.new()
	_god_head.position = Vector3(0, 2.62, 0)
	_god_visual.add_child(_god_head)
	var head := MeshInstance3D.new()
	head.mesh = MeshBuilder.ellipsoid(0.5, Vector3.ONE)
	head.material_override = skin
	head.scale = Vector3(1.0, 1.08, 0.95)
	_god_head.add_child(head)
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.5
	_register_god_shape(head_shape, Vector3(0, FLOOR_TOP_Y + 2.62, -2))
	# Лицо: глаза/рот/румянец — спрайтовые квады со сменными текстурами эмоций
	_eye_l = _face_quad(Vector3(-0.2, 0.05, 0.46), Vector2(0.21, 0.27))
	_eye_r = _face_quad(Vector3(0.2, 0.05, 0.46), Vector2(0.21, 0.27))
	_mouth = _face_quad(Vector3(0, -0.22, 0.47), Vector2(0.2, 0.13))
	_blush_l = _face_quad(Vector3(-0.33, -0.1, 0.4), Vector2(0.18, 0.1))
	_blush_r = _face_quad(Vector3(0.33, -0.1, 0.4), Vector2(0.18, 0.1))
	_eye_r.scale.x = -1.0 # зеркальный второй глаз из той же текстуры
	set_emotion("eye_red_open", "mouth_smile", 0.0)
	_blush_l.material_override = GameMaterials.sprite_mat("blush")
	_blush_r.material_override = GameMaterials.sprite_mat("blush")
	_blush_l.visible = false
	_blush_r.visible = false
	# Надувные белые волосы до пояса: чёлка, боковые пряди, задний каскад.
	# Волосы/ушки/крылья Бога — very_bouncy (самые прыгучие).
	var bangs := MeshInstance3D.new()
	bangs.mesh = MeshBuilder.ellipsoid(0.52, Vector3.ONE)
	bangs.material_override = hair
	bangs.transform = Transform3D(Basis.from_scale(Vector3(1.05, 0.75, 1.0)), Vector3(0, 0.22, 0.1))
	_god_head.add_child(bangs)
	_make_soft_part(_god_visual, MeshBuilder.capsule(0.16, 1.6), hair,
		Vector3(-0.52, 2.45, 0.12), Vector3(0, 0, 0.12))
	_make_soft_part(_god_visual, MeshBuilder.capsule(0.16, 1.6), hair,
		Vector3(0.52, 2.45, 0.12), Vector3(0, 0, -0.12))
	# Задний каскад волос — большая прыгучая «подушка»
	var back_hair := MeshInstance3D.new()
	back_hair.mesh = MeshBuilder.ellipsoid(0.5, Vector3.ONE)
	back_hair.material_override = hair
	back_hair.transform = Transform3D(Basis.from_scale(Vector3(1.25, 2.6, 0.62)), Vector3(0, 2.1, -0.42))
	_god_visual.add_child(back_hair)
	var back_shape := _box_shape(Vector3(1.25, 2.4, 0.6))
	_register_god_shape(back_shape, Vector3(0, FLOOR_TOP_Y + 2.1, -2.42), "very_bouncy")
	# Ушки кицунэмими ~0.4 м
	_make_soft_part(_god_head, MeshBuilder.cone(0.17, 0.42, 10), hair,
		Vector3(-0.3, 0.55, 0), Vector3(0, 0, 0.28), true)
	_make_soft_part(_god_head, MeshBuilder.cone(0.17, 0.42, 10), hair,
		Vector3(0.3, 0.55, 0), Vector3(0, 0, -0.28), true)
	var ear_shape := SphereShape3D.new()
	ear_shape.radius = 0.22
	_register_god_shape(ear_shape, Vector3(-0.3, FLOOR_TOP_Y + 3.15, -2), "very_bouncy")
	_register_god_shape(ear_shape, Vector3(0.3, FLOOR_TOP_Y + 3.15, -2), "very_bouncy")
	# Ободок горничной с кружевом
	var band := MeshInstance3D.new()
	band.mesh = MeshBuilder.cylinder(0.46, 0.46, 0.1, 18)
	band.material_override = GameMaterials.lace_white()
	band.position = Vector3(0, 0.42, 0)
	band.rotation_degrees.x = 14
	_god_head.add_child(band)
	# Руки (пивоты в плечах; визуал: рукава-фонарики + рука)
	_arm_l = _make_god_arm(-1.0, dress, skin)
	_arm_r = _make_god_arm(1.0, dress, skin)
	# Крылья Бога: размах 12 м (по 6 м), тёмно-красные, very_bouncy
	_make_god_wing(-1.0)
	_make_god_wing(1.0)
	# Сердечки няшинга
	_hearts = CPUParticles3D.new()
	_hearts.amount = 42
	_hearts.lifetime = 2.2
	_hearts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_hearts.emission_sphere_radius = 2.5
	_hearts.direction = Vector3.UP
	_hearts.spread = 32.0
	_hearts.initial_velocity_min = 0.7
	_hearts.initial_velocity_max = 1.6
	_hearts.scale_amount_min = 0.22
	_hearts.scale_amount_max = 0.42
	var heart_quad := QuadMesh.new()
	heart_quad.size = Vector2(0.5, 0.5)
	heart_quad.orientation = PlaneMesh.FACE_Z
	var hm: StandardMaterial3D = GameMaterials.sprite_mat("heart").duplicate() as StandardMaterial3D
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	heart_quad.material = hm
	_hearts.mesh = heart_quad
	_hearts.position = Vector3(0, 2.6, 1.2)
	_hearts.emitting = false
	_god_visual.add_child(_hearts)

func _register_god_shape(shape: Shape3D, pos: Vector3, surface: String = "bouncy") -> void:
	var cs: CollisionShape3D = _add_collision(shape, Transform3D(Basis.IDENTITY, pos), surface)
	_god_shapes.append({"cs": cs, "base_pos": pos})

func _face_quad(pos: Vector3, size: Vector2) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	q.mesh = quad
	q.position = pos
	_god_head.add_child(q)
	return q

func _make_soft_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rest_rot: Vector3, is_ear: bool = false) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation = rest_rot
	parent.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if is_ear:
		mi.position = Vector3(0, 0.16, 0)
	else:
		mi.position = Vector3(0, -0.7, 0)
	pivot.add_child(mi)
	_soft_parts.append({
		"pivot": pivot, "rest": rest_rot, "vel": Vector3.ZERO,
		"ang": Vector3.ZERO, "stiff": 42.0 if is_ear else 18.0,
		"damp": 5.5 if is_ear else 3.2, "ear": is_ear,
	})

func _make_god_arm(side: float, dress: Material, skin: Material) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.78, 2.15, 0.05)
	_god_visual.add_child(shoulder)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = MeshBuilder.ellipsoid(0.3, Vector3.ONE)
	sleeve.material_override = dress
	sleeve.position = Vector3(side * 0.1, -0.1, 0)
	shoulder.add_child(sleeve)
	var arm := MeshInstance3D.new()
	arm.mesh = MeshBuilder.capsule(0.13, 1.35)
	arm.material_override = skin
	arm.position = Vector3(side * 0.16, -0.75, 0)
	shoulder.add_child(arm)
	var hand := MeshInstance3D.new()
	hand.mesh = MeshBuilder.ellipsoid(0.16, Vector3.ONE)
	hand.material_override = skin
	hand.position = Vector3(side * 0.16, -1.45, 0)
	shoulder.add_child(hand)
	shoulder.rotation = Vector3(0.15, 0, side * 0.35)
	return shoulder

func _make_god_wing(side: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.wing_mesh(6.0, 2.2, 0.55)
	mi.material_override = GameMaterials.pvc_darkred()
	add_child(mi)
	var cs: CollisionShape3D = _add_collision(_box_shape(Vector3(6, 1.7, 0.55)),
		Transform3D.IDENTITY, "very_bouncy")
	var basis := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
	var wing: Dictionary = {
		"mi": mi, "cs": cs, "pivot": Vector3(side * 0.6, FLOOR_TOP_Y + 2.15, -2.55),
		"basis": basis, "shape_offset": Transform3D(Basis.IDENTITY, Vector3(3, 0.4, 0)),
		"side": side,
	}
	_god_wings.append(wing)
	_update_wing(wing, -0.25)

# ------------------------------------------------------- трон и шкаф -------
func _build_throne_and_wardrobe() -> void:
	var pvc_trim: Material = GameMaterials.lace_darkred()
	# Трон 2.5×2.5×5 у северной стены (позади Бога)
	_add_part(MeshBuilder.rounded_box(Vector3(2.5, 1.1, 2.5), 0.45), pvc_trim,
		_box_shape(Vector3(2.5, 1.1, 2.5)), Transform3D(Basis.IDENTITY, Vector3(0, 2.55, -13.2)), "throne")
	_add_part(MeshBuilder.rounded_box(Vector3(2.5, 5.0, 0.9), 0.4), pvc_trim,
		_box_shape(Vector3(2.5, 5.0, 0.9)), Transform3D(Basis.IDENTITY, Vector3(0, 4.5, -14.5)), "throne")
	# Три пары крыльев трона (общий размах 7 м) — тискают сидящего; very_bouncy
	for i: int in 3:
		var y: float = 3.6 + float(i) * 1.35
		for side: float in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = MeshBuilder.wing_mesh(3.5, 1.2, 0.4)
			mi.material_override = GameMaterials.pvc_darkred()
			add_child(mi)
			var cs: CollisionShape3D = _add_collision(_box_shape(Vector3(3.5, 0.9, 0.4)),
				Transform3D.IDENTITY, "very_bouncy")
			var basis := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
			var wing: Dictionary = {
				"mi": mi, "cs": cs, "pivot": Vector3(side * 1.1, y, -14.2),
				"basis": basis, "shape_offset": Transform3D(Basis.IDENTITY, Vector3(1.75, 0.2, 0)),
				"side": side, "row": i,
			}
			_throne_wings.append(wing)
			_update_wing(wing, -0.15)
	# Надувной шкаф 3×3×3 слева от врат; внутри — розовое платье горничной
	_add_part(MeshBuilder.rounded_box(Vector3(3, 3, 1.1), 0.4), GameMaterials.pvc_pink(),
		_box_shape(Vector3(3, 3, 1.1)), Transform3D(Basis.IDENTITY, Vector3(-12.5, 3.5, 14.2)), "bouncy")
	_wardrobe_door = MeshInstance3D.new()
	_wardrobe_door.mesh = MeshBuilder.rounded_box(Vector3(2.7, 2.7, 0.25), 0.12)
	_wardrobe_door.material_override = GameMaterials.pvc_pink()
	_wardrobe_door.position = Vector3(-12.5, 3.5, 13.55)
	add_child(_wardrobe_door)
	# Платье на вешалке внутри шкафа (видно при открытой дверце)
	var dress_item := MeshInstance3D.new()
	dress_item.mesh = MeshBuilder.skirt_mesh(0.22, 0.62, 1.7)
	dress_item.material_override = GameMaterials.silk(Color(1.0, 0.62, 0.72), "silk_pink_albedo")
	dress_item.position = Vector3(-12.5, 3.3, 13.9)
	add_child(dress_item)
	var stockings := MeshInstance3D.new()
	stockings.mesh = MeshBuilder.box(Vector3(0.5, 0.12, 0.4))
	stockings.material_override = GameMaterials.silk(Color(0.55, 0.75, 1.0), "silk_blue_albedo")
	stockings.position = Vector3(-11.8, 2.35, 13.9)
	add_child(stockings)
	var heels := MeshInstance3D.new()
	heels.mesh = MeshBuilder.box(Vector3(0.55, 0.18, 0.3))
	heels.material_override = GameMaterials.plain(Color(0.98, 0.98, 1.0), 0.25)
	heels.position = Vector3(-13.2, 2.3, 13.9)
	add_child(heels)

# ---------------------------------------------------------- аэродинамика ---
func _build_aero_surfaces() -> void:
	# Крылья замка — главные аэродинамические поверхности
	for wing: Dictionary in _wings:
		var surf := AeroSurface3D.new()
		var cfg := AeroSurfaceConfig.new()
		cfg.chord = 8.0
		cfg.span = 33.0
		cfg.area = 264.0
		cfg.aspect_ratio = 4.1
		surf.wing_config = cfg
		var basis: Basis = wing["basis"]
		surf.transform = Transform3D(basis, (wing["pivot"] as Vector3) + basis * Vector3(16.5, 0, 0))
		add_child(surf)
	# Лобовые поверхности стен (парусность корпуса 33×33)
	var wall_spots: Array = [
		[Vector3(0, 16, 16.5), Basis(Vector3.RIGHT, PI * 0.5)],
		[Vector3(0, 16, -16.5), Basis(Vector3.RIGHT, -PI * 0.5)],
		[Vector3(16.5, 16, 0), Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)],
		[Vector3(-16.5, 16, 0), Basis(Vector3.BACK, -PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)],
	]
	for spot: Array in wall_spots:
		var surf := AeroSurface3D.new()
		var cfg := AeroSurfaceConfig.new()
		cfg.chord = 26.0
		cfg.span = 33.0
		cfg.area = 700.0
		cfg.aspect_ratio = 1.4
		surf.wing_config = cfg
		surf.transform = Transform3D(spot[1] as Basis, spot[0] as Vector3)
		add_child(surf)
	# Крылья Бога (влияют на колыхание внутри при полёте замка)
	for wing: Dictionary in _god_wings:
		var surf := AeroSurface3D.new()
		var cfg := AeroSurfaceConfig.new()
		cfg.chord = 2.2
		cfg.span = 6.0
		cfg.area = 13.2
		cfg.aspect_ratio = 2.7
		surf.wing_config = cfg
		var basis: Basis = wing["basis"]
		surf.transform = Transform3D(basis, (wing["pivot"] as Vector3) + basis * Vector3(3, 0, 0))
		add_child(surf)

func _build_lights_audio() -> void:
	_interior_light = OmniLight3D.new()
	_interior_light.light_color = Color(1.0, 0.25, 0.2)
	_interior_light.light_energy = 1.4
	_interior_light.omni_range = 30.0
	_interior_light.omni_attenuation = 0.7
	_interior_light.position = Vector3(0, 14, 0)
	add_child(_interior_light)
	_heart_light = OmniLight3D.new()
	_heart_light.light_color = Color(1.0, 0.45, 0.6)
	_heart_light.light_energy = 0.0
	_heart_light.omni_range = 12.0
	_heart_light.position = Vector3(0, 6, 0)
	add_child(_heart_light)
	_flap_audio = AudioStreamPlayer3D.new()
	_flap_audio.bus = "SFX"
	_flap_audio.max_distance = 400.0
	_flap_audio.stream = AudioManager.get_stream("wing_flap_loop")
	add_child(_flap_audio)
	_suction_audio = AudioStreamPlayer3D.new()
	_suction_audio.bus = "SFX"
	_suction_audio.max_distance = 500.0
	_suction_audio.stream = AudioManager.get_stream("suction_roar")
	add_child(_suction_audio)

# ---------------------------------------------------------------- верёвки --
## 4 пеньковые верёвки по 75 м с вершин башен: цепочки из 15 сегментов
## RigidBody3D + PinJoint3D. Обычная (не надувная) физика.
func _build_ropes() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var seg_shape := CapsuleShape3D.new()
	seg_shape.radius = 0.09
	seg_shape.height = 5.0
	var seg_len: float = 5.0
	var count: int = 15
	for sx: float in [-16.5, 16.5]:
		for sz: float in [-16.5, 16.5]:
			var anchor_global: Vector3 = to_global(Vector3(sx, 49.0, sz))
			var segments: Array[RigidBody3D] = []
			var prev: PhysicsBody3D = self
			var joint_pos: Vector3 = anchor_global
			for i: int in count:
				var seg := RigidBody3D.new()
				seg.mass = 2.2
				seg.collision_layer = 16 # слой 5 «Ropes»
				seg.collision_mask = 1 | 2 | 4 | 32
				seg.add_to_group("rope")
				seg.set_meta("rope_index", i)
				var cs := CollisionShape3D.new()
				cs.shape = seg_shape
				seg.add_child(cs)
				var mi := MeshInstance3D.new()
				mi.mesh = MeshBuilder.cylinder(0.07, 0.07, seg_len, 6)
				mi.material_override = GameMaterials.rope_hemp()
				seg.add_child(mi)
				parent.add_child(seg)
				seg.global_position = anchor_global + Vector3(0, -seg_len * (float(i) + 0.5), 0)
				var joint := PinJoint3D.new()
				parent.add_child(joint)
				joint.global_position = joint_pos
				joint.node_a = joint.get_path_to(prev)
				joint.node_b = joint.get_path_to(seg)
				joint_pos = seg.global_position + Vector3(0, -seg_len * 0.5, 0)
				prev = seg
				segments.append(seg)
			ropes.append(segments)

# ------------------------------------------------------------- публичное API
func get_surface_type(shape_idx: int) -> String:
	if shape_idx >= 0 and shape_idx < _shape_surfaces.size():
		return _shape_surfaces[shape_idx]
	return "bouncy"

func get_state_name() -> String:
	return STATE_NAMES[state]

func player_local_pos() -> Vector3:
	if GameState.player == null:
		return Vector3(0, -999, 0)
	return to_local(GameState.player.global_position)

func is_player_inside() -> bool:
	return _player_inside

func god_global_pos() -> Vector3:
	return to_global(Vector3(0, FLOOR_TOP_Y + 2.0, -2))

func gate_global_pos() -> Vector3:
	return to_global(Vector3(0, 5.5, 15.5))

func capture_global_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(Vector3.UP, PI), CAPTURE_LOCAL)

func throne_seat_global() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 3.35, -13.1))

func wardrobe_global_pos() -> Vector3:
	return to_global(Vector3(-12.5, 3.5, 13.6))

func is_near_wardrobe(world_pos: Vector3) -> bool:
	return world_pos.distance_to(wardrobe_global_pos()) < 3.4

## Поле всасывания для CharacterBody3D игрока: скорость потока (м/с).
func suction_velocity_at(world_pos: Vector3) -> Vector3:
	if state != CastleState.SUCTION or not gate_open:
		return Vector3.ZERO
	var gate: Vector3 = gate_global_pos()
	var inside_target: Vector3 = to_global(Vector3(0, FLOOR_TOP_Y + 1.0, 6.0))
	var dist: float = world_pos.distance_to(gate)
	if dist > 75.0:
		return Vector3.ZERO
	var target: Vector3 = gate if to_local(world_pos).z > 13.0 else inside_target
	var dir: Vector3 = (target - world_pos).normalized()
	var strength: float = 34.0 / (1.0 + dist * 0.045) # эффект Вентури: сильнее у врат
	return dir * strength

## Порывы ветра в зале, когда Бог машет крыльями в летающем состоянии.
func interior_gust_velocity() -> Vector3:
	if state != CastleState.FLYING or not _player_inside:
		return Vector3.ZERO
	var pulse: float = maxf(sin(_flap_phase * 1.7), 0.0)
	var local: Vector3 = Vector3(sin(_flap_phase * 0.9) * 3.0, -1.5, 5.5) * pulse
	return global_transform.basis * local

func set_emotion(eyes: String, mouth: String, duration: float = 3.0) -> void:
	_current_eyes = eyes
	_eye_l.material_override = GameMaterials.sprite_mat(eyes)
	_eye_r.material_override = GameMaterials.sprite_mat(eyes)
	_mouth.material_override = GameMaterials.sprite_mat(mouth)
	_emotion_timer = duration

## Игрок тискает/лазает по Богу: эмоция >_< и вздрагивание волос/ушек.
func on_god_touched() -> void:
	set_emotion("eye_happy", "mouth_cat", 2.5)
	_blush_l.visible = true
	_blush_r.visible = true
	for sp: Dictionary in _soft_parts:
		sp["vel"] = (sp["vel"] as Vector3) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	AudioManager.play_sfx_3d("pvc_squeak_" + str(randi() % 4 + 1), god_global_pos(), -6.0, 60.0)

func on_player_struggle(intensity: float) -> void:
	if not nyashing_active:
		return
	_nyash_struggle_recent = 1.0
	var k: float = 0.35 if _weakened else 1.0
	_nyash_escape += intensity * k

func on_player_hug_back() -> void:
	if not nyashing_active:
		return
	_nyash_hug_pause_min = 2.0
	_nyash_progress_min = maxf(0.0, _nyash_progress_min - 1.5)
	set_emotion("eye_happy", "mouth_cat", 3.0)

func begin_throne_squeeze() -> void:
	throne_active = true
	set_emotion("eye_happy", "mouth_open", 3.0)
	toast.emit("Крылья трона начинают тискать Юмика…")

func end_throne_squeeze() -> void:
	throne_active = false

func skip_sleep() -> void:
	if _sleep_active:
		_sleep_t = SLEEP_REAL_SECONDS

# -------------------------------------------------------------- состояния ---
func set_state(new_state: int, silent: bool = false) -> void:
	state = new_state
	_state_timer_min = 0.0
	match state:
		CastleState.NORMAL:
			if _suction_audio.playing:
				_suction_audio.stop()
			if _flap_audio.playing:
				_flap_audio.stop()
			AudioManager.play_music("music_dark_ambient", -12.0)
		CastleState.SUCTION:
			_set_gate(true)
			if _suction_audio.stream != null:
				_suction_audio.play()
			set_emotion("eye_red_open", "mouth_open", 4.0)
			toast.emit("НЗТБНЗ открыл врата и начал всасывать воздух!")
		CastleState.FLYING:
			_fly_target_alt = randf_range(70.0, 140.0)
			_fly_heading = randf() * TAU
			if _flap_audio.stream != null:
				_flap_audio.play()
			set_emotion("eye_happy", "mouth_cat", 4.0)
			AudioManager.play_music("music_fly", -12.0)
			toast.emit("НЗТБНЗ взмахнул крыльями и взлетел!")
	if not silent:
		state_changed.emit(get_state_name())

func force_state_by_name(state_name: String) -> void:
	var idx: int = STATE_NAMES.find(state_name)
	if idx >= 0:
		set_state(idx)

func _set_gate(open: bool, instant: bool = false) -> void:
	if open == gate_open and not instant:
		return
	gate_open = open
	_gate_locked = not open
	if _gate_shape != null:
		_gate_shape.disabled = open
	if instant:
		_gate_amount = 1.0 if open else 0.0
	gate_changed.emit(open)
	AudioManager.play_sfx_3d("gate_hiss", gate_global_pos(), -4.0, 120.0)

# ------------------------------------------------------------------ цикл ---
func _integrate_forces(body_state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(body_state)
	_contact_count = body_state.get_contact_count()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_thud_cooldown = maxf(0.0, _thud_cooldown - delta)
	_apply_wind_assist()
	match state:
		CastleState.SUCTION:
			_apply_suction(delta)
		CastleState.FLYING:
			_apply_flight(delta)
	_update_soft_parts(delta)
	if _contact_count > 0 and linear_velocity.length() < 1.2:
		_grounded_time += delta
	else:
		_grounded_time = 0.0

## Парусная сила ветра на корпус (дополняет AeroSurface3D): сильный ветер
## несёт замок по земле, переворачивает и поднимает в воздух.
func _apply_wind_assist() -> void:
	var wind: Vector3 = WindManager.wind_vector()
	var v_rel: Vector3 = wind - linear_velocity
	var speed: float = v_rel.length()
	if speed < 0.4:
		return
	var force: Vector3 = v_rel.normalized() * (0.5 * 1.225 * speed * speed * 0.95 * 650.0)
	var pressure_offset: Vector3 = global_transform.basis * Vector3(0, 9, 0)
	apply_force(force, pressure_offset)

func _apply_suction(_delta: float) -> void:
	var gate: Vector3 = gate_global_pos()
	var inside_target: Vector3 = to_global(Vector3(0, FLOOR_TOP_Y + 1.0, 4.0))
	for node: Node in get_tree().get_nodes_in_group("suction_affected"):
		var rb := node as RigidBody3D
		if rb == null or rb == self:
			continue
		var dist: float = rb.global_position.distance_to(gate)
		if dist > 75.0:
			continue
		var target: Vector3 = gate if to_local(rb.global_position).z > 13.0 else inside_target
		var dir: Vector3 = (target - rb.global_position).normalized()
		var strength: float = 2600.0 / (1.0 + dist * 0.05)
		rb.apply_central_force(dir * strength * rb.mass * 0.06)
	# Отдача: поток внутрь толкает сам замок в противоположную сторону
	var back: Vector3 = global_transform.basis * Vector3(0, 0.15, 1.0)
	apply_force(back.normalized() * mass * 3.2, global_transform.basis * Vector3(0, 4, 14))

func _apply_flight(delta: float) -> void:
	_flap_phase += delta * 4.6
	var ground_h: float = 0.0
	if GameState.world != null and GameState.world.has_method("get_height_at"):
		ground_h = GameState.world.get_height_at(global_position.x, global_position.z)
	var alt: float = global_position.y - ground_h
	var target_vy: float = clampf((_fly_target_alt - alt) * 0.35, -7.0, 9.0)
	var lift_k: float = 0.75 + 0.45 * maxf(sin(_flap_phase), 0.0) # подъём на взмахе вниз
	var lift: float = mass * (9.8 + (target_vy - linear_velocity.y) * 1.6) * lift_k
	apply_central_force(Vector3.UP * lift)
	# Медленный дрейф и озорное кружение/раскачивание
	_fly_heading += delta * 0.05 * sin(_flap_phase * 0.23)
	var drift: Vector3 = Vector3(cos(_fly_heading), 0, sin(_fly_heading)) * mass * 0.55
	apply_central_force(drift)
	var wobble: Vector3 = Vector3(sin(_flap_phase * 0.9), 0.35 * sin(_flap_phase * 0.5), cos(_flap_phase * 0.7))
	apply_torque(wobble * mass * 2.6)
	# Самовыравнивание слабое — замок любит кувыркаться
	var up_local: Vector3 = global_transform.basis.y
	var tilt_axis: Vector3 = up_local.cross(Vector3.UP)
	apply_torque(tilt_axis * mass * 1.1)

func _process(delta: float) -> void:
	var game_min_delta: float = delta * GameState.time_scale / 60.0
	# Смена состояния каждые 60 игровых минут
	_state_timer_min += game_min_delta
	if _state_timer_min >= 60.0 and not _sleep_active:
		var next: int = randi() % 3
		if next == state:
			next = (next + 1) % 3
		set_state(next)
	_update_gate(delta)
	_update_player_inside()
	_update_god(delta, game_min_delta)
	_update_wings_visual(delta)
	_update_wardrobe(delta)
	if nyashing_active:
		_update_nyashing(delta, game_min_delta)
	if _sleep_active:
		_update_sleep(delta)
	_check_suction_capture()

func _update_gate(delta: float) -> void:
	# Врата закрываются и блокируются, когда Юмик внутри (кроме всасывания).
	var should_open: bool = gate_open
	if state == CastleState.SUCTION:
		should_open = true
	elif not _player_inside:
		should_open = true
	elif state == CastleState.NORMAL and _grounded_time > 3.0 and not nyashing_active:
		should_open = true # Бог смилостивился: замок спокойно стоит на земле
	elif _player_inside:
		should_open = false
	if should_open != gate_open:
		_set_gate(should_open)
		if not should_open:
			toast.emit("Врата НЗТБНЗ захлопнулись и заблокировались…")
	var target: float = 1.0 if gate_open else 0.0
	_gate_amount = move_toward(_gate_amount, target, delta * 0.8)
	_door_l.position.x = -0.75 - _gate_amount * 2.6
	_door_r.position.x = 0.75 + _gate_amount * 2.6

func _update_player_inside() -> void:
	var lp: Vector3 = player_local_pos()
	var inside: bool = absf(lp.x) < HALL_HALF and absf(lp.z) < HALL_HALF and lp.y > 0.5 and lp.y < 31.0
	if inside != _player_inside:
		_player_inside = inside
		player_inside_changed.emit(inside)

func _update_god(delta: float, _game_min_delta: float) -> void:
	# Дыхание/подпрыгивание Бога: визуал и его шейпы двигаются синхронно
	_god_bob_phase += delta * (3.2 if nyashing_active else 1.4)
	var amp_target: float = 0.16 if nyashing_active else 0.05
	_god_bob_amp = lerpf(_god_bob_amp, amp_target, delta * 2.0)
	var bob: float = sin(_god_bob_phase) * _god_bob_amp
	_god_visual.position.y = FLOOR_TOP_Y + bob
	for gs: Dictionary in _god_shapes:
		var cs := gs["cs"] as CollisionShape3D
		var base := gs["base_pos"] as Vector3
		cs.position = base + Vector3(0, bob, 0)
	# Взгляд на игрока внутри зала
	if _player_inside and GameState.player != null:
		var lp: Vector3 = player_local_pos()
		var to_player: Vector3 = lp - Vector3(0, FLOOR_TOP_Y + 2.62, -2)
		var yaw: float = clampf(atan2(to_player.x, to_player.z), -0.7, 0.7)
		var pitch: float = clampf(-atan2(to_player.y - 2.0, Vector2(to_player.x, to_player.z).length()), -0.35, 0.45)
		_god_head.rotation = _god_head.rotation.lerp(Vector3(pitch, yaw, sin(_god_bob_phase * 0.5) * 0.06), delta * 3.0)
	else:
		_god_head.rotation = _god_head.rotation.lerp(Vector3(0, sin(_god_bob_phase * 0.3) * 0.15, 0), delta * 2.0)
	# Руки: состояния
	var arm_target_l := Vector3(0.15, 0, 0.35)
	var arm_target_r := Vector3(0.15, 0, -0.35)
	if nyashing_active:
		arm_target_l = Vector3(1.15 + sin(_god_bob_phase) * 0.15, 0.3, 0.55)
		arm_target_r = Vector3(1.15 + cos(_god_bob_phase) * 0.15, -0.3, -0.55)
	elif state == CastleState.FLYING:
		arm_target_r = Vector3(2.3, -0.2, -0.5) # озорно прикрывает рот рукой
		arm_target_l = Vector3(0.4, 0.2, 0.9)
	_arm_l.rotation = _arm_l.rotation.lerp(arm_target_l, delta * 4.0)
	_arm_r.rotation = _arm_r.rotation.lerp(arm_target_r, delta * 4.0)
	# Эмоции: возврат к обычной, моргание
	if _emotion_timer > 0.0:
		_emotion_timer -= delta
		if _emotion_timer <= 0.0 and not nyashing_active:
			set_emotion("eye_red_open", "mouth_smile", 0.0)
			_blush_l.visible = false
			_blush_r.visible = false
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.4, 5.0)
		if _current_eyes == "eye_red_open":
			_eye_l.material_override = GameMaterials.sprite_mat("eye_closed")
			_eye_r.material_override = GameMaterials.sprite_mat("eye_closed")
			get_tree().create_timer(0.13).timeout.connect(_unblink)
	# Свет няшинга пульсирует розовым
	_heart_light.light_energy = (1.6 + sin(_god_bob_phase * 2.0) * 0.7) if nyashing_active else 0.0

func _unblink() -> void:
	if _current_eyes == "eye_red_open":
		_eye_l.material_override = GameMaterials.sprite_mat("eye_red_open")
		_eye_r.material_override = GameMaterials.sprite_mat("eye_red_open")

func _update_soft_parts(delta: float) -> void:
	# Мягкая физика волос/ушек: пружина с демпфированием, возмущение от
	# угловой скорости замка и ветра — части колышутся от ветра и касаний.
	var wind_local: Vector3 = global_transform.basis.inverse() * (WindManager.wind_vector() - linear_velocity)
	for sp: Dictionary in _soft_parts:
		var ang := sp["ang"] as Vector3
		var vel := sp["vel"] as Vector3
		var stiff: float = sp["stiff"]
		var damp: float = sp["damp"]
		var drive: Vector3 = Vector3(-angular_velocity.x, 0, -angular_velocity.z) * 1.6
		drive += Vector3(clampf(wind_local.z, -8, 8), 0, clampf(-wind_local.x, -8, 8)) * 0.06
		vel += (-ang * stiff - vel * damp + drive) * delta
		ang += vel * delta
		ang = ang.clamp(Vector3(-0.65, -0.65, -0.65), Vector3(0.65, 0.65, 0.65))
		sp["ang"] = ang
		sp["vel"] = vel
		(sp["pivot"] as Node3D).rotation = (sp["rest"] as Vector3) + ang

func _update_wings_visual(delta: float) -> void:
	var castle_flap: float = 0.0
	if state == CastleState.FLYING:
		castle_flap = sin(_flap_phase) * 0.5
	else:
		# На земле крылья лениво колышутся от ветра
		castle_flap = sin(Time.get_ticks_msec() * 0.0009) * clampf(WindManager.wind_speed_ms() * 0.006, 0.01, 0.16)
	for wing: Dictionary in _wings:
		_update_wing(wing, castle_flap - 0.08)
	var god_flap: float = -0.25
	if state == CastleState.FLYING:
		god_flap = sin(_flap_phase * 1.7) * 0.55 # Бог машет крыльями в зале — порывы!
	elif nyashing_active:
		god_flap = -0.35 + sin(_god_bob_phase) * 0.12
	for wing: Dictionary in _god_wings:
		_update_wing(wing, god_flap)
	# Тронные крылья тискают по циклу, когда на троне сидят
	if throne_active:
		_throne_phase += delta * 2.6
	var throne_angle: float = -0.15
	if throne_active:
		throne_angle = -0.1 - (0.5 + 0.5 * sin(_throne_phase)) * 0.85
	for wing: Dictionary in _throne_wings:
		var row_offset: float = float(wing["row"]) * 0.12
		_update_wing(wing, throne_angle - row_offset)

func _update_wardrobe(delta: float) -> void:
	var near: bool = GameState.player != null and is_near_wardrobe(GameState.player.global_position)
	_wardrobe_open = move_toward(_wardrobe_open, 1.0 if near else 0.0, delta * 2.2)
	_wardrobe_door.position.x = -12.5 - _wardrobe_open * 2.4

# ---------------------------------------------------------------- няшинг ---
func _check_suction_capture() -> void:
	if state != CastleState.SUCTION or nyashing_active or GameState.player == null:
		return
	var lp: Vector3 = player_local_pos()
	# Юмика затянуло в тронный зал к Богу — захват и няшинг
	if absf(lp.x) < 7.0 and lp.z > -6.0 and lp.z < 9.0 and lp.y > FLOOR_TOP_Y - 0.5 and lp.y < 9.0:
		_start_nyashing()

func _start_nyashing() -> void:
	nyashing_active = true
	_nyash_progress_min = 0.0
	_nyash_escape = 0.0
	_weakened = false
	_hearts.emitting = true
	set_emotion("eye_happy", "mouth_cat", 99999.0)
	_blush_l.visible = true
	_blush_r.visible = true
	AudioManager.play_music("music_nyashing", -9.0)
	AudioManager.play_sfx("chime_magic", -4.0)
	if GameState.player != null and GameState.player.has_method("enter_captured"):
		GameState.player.enter_captured(self)
	nyashing_started.emit()
	toast.emit("Темный Бог схватил Юмика! Начинается Няшинг…")

func _end_nyashing(released_by_escape: bool) -> void:
	nyashing_active = false
	_hearts.emitting = false
	AudioManager.play_music("music_dark_ambient", -12.0)
	set_emotion("eye_red_open", "mouth_smile", 0.0)
	_blush_l.visible = false
	_blush_r.visible = false
	if GameState.player != null and GameState.player.has_method("exit_captured"):
		GameState.player.exit_captured(released_by_escape)
	nyashing_ended.emit()

func _update_nyashing(delta: float, game_min_delta: float) -> void:
	_nyash_struggle_recent = maxf(0.0, _nyash_struggle_recent - delta)
	_nyash_hug_pause_min = maxf(0.0, _nyash_hug_pause_min - game_min_delta)
	# Бог подпрыгивает и тискает: скрипы ПВХ в ритме подскоков
	_squeak_timer -= delta
	if _squeak_timer <= 0.0:
		_squeak_timer = randf_range(0.35, 0.8)
		AudioManager.play_sfx("pvc_squeak_" + str(randi() % 4 + 1), -10.0, randf_range(0.9, 1.15))
		if _weakened:
			AudioManager.play_sfx("heartbeat", -13.0, randf_range(1.0, 1.25))
	if GameState.player != null and GameState.player.has_method("set_squash"):
		GameState.player.set_squash(0.5 + 0.5 * sin(_god_bob_phase))
	if _sleep_active:
		return # во сне Бог просто продолжает няшить — прогресс эйфории не идёт
	# Побег вырыванием
	if _nyash_escape >= 10.0:
		toast.emit("Юмик вырвался из объятий!")
		_end_nyashing(true)
		return
	_nyash_escape = maxf(0.0, _nyash_escape - delta * 0.55)
	# Эйфория растёт, только если Юмик не вырывается и не тискает в ответ
	if _nyash_hug_pause_min <= 0.0 and _nyash_struggle_recent <= 0.0:
		_nyash_progress_min += game_min_delta
	else:
		_nyash_progress_min = maxf(0.0, _nyash_progress_min - game_min_delta * 0.35)
	if _nyash_progress_min >= 10.0 and not _weakened:
		_weakened = true
		if GameState.player != null and GameState.player.has_method("set_weakened"):
			GameState.player.set_weakened(true)
		toast.emit("Юмик истощается от эйфории… движения ослабевают")
	if _nyash_progress_min >= 20.0:
		_start_sleep()

func nyash_progress_01() -> float:
	return clampf(_nyash_progress_min / 20.0, 0.0, 1.0)

func _start_sleep() -> void:
	_sleep_active = true
	_sleep_t = 0.0
	GameState.sleeping = true
	GameState.sleep_skip_requested = false
	set_emotion("eye_closed", "mouth_cat", 99999.0)
	if GameState.player != null and GameState.player.has_method("enter_sleep_cutscene"):
		GameState.player.enter_sleep_cutscene(self)
	sleep_started.emit()
	toast.emit("Юмик заснул от эйфории… (8 игровых часов сна)")

func _update_sleep(delta: float) -> void:
	_sleep_t += delta
	if GameState.sleep_skip_requested:
		_sleep_t = SLEEP_REAL_SECONDS
	# 8 игровых часов пролетают за SLEEP_REAL_SECONDS (сон с катсценой няшинга)
	var minutes_per_sec: float = 480.0 / SLEEP_REAL_SECONDS
	GameState.advance_game_minutes(minutes_per_sec * delta)
	if int(_sleep_t * 2.0) % 3 == 0 and randf() < delta * 0.7:
		AudioManager.play_sfx("snore_soft", -14.0, randf_range(0.9, 1.1))
	if _sleep_t >= SLEEP_REAL_SECONDS:
		_finish_sleep()

func _finish_sleep() -> void:
	_sleep_active = false
	GameState.sleeping = false
	_weakened = false
	if GameState.player != null and GameState.player.has_method("set_weakened"):
		GameState.player.set_weakened(false)
	_end_nyashing(false)
	set_emotion("eye_happy", "mouth_smile", 5.0)
	set_state(CastleState.NORMAL)
	sleep_finished.emit()
	toast.emit("Юмик проснулся рядом с Темным Богом, отдохнувший и счастливый")

func _on_body_entered(body: Node) -> void:
	if _thud_cooldown > 0.0:
		return
	if body.is_in_group("terrain") and linear_velocity.length() > 3.0:
		_thud_cooldown = 0.6
		AudioManager.play_sfx_3d("boing_" + str(randi() % 3 + 1), global_position, -2.0, 300.0)
