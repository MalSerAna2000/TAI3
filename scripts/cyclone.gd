extends Node3D
## Воровка тропического циклона: при «Урагане» в 250 м от Юмика Богиня Ветра
## ради шалости пригоняет тропический циклон и озорно катается на его вершине,
## а циклон следует за ней. Вихрь подхватывает ragdoll, игрока и даже НЗТБНЗ.

var _funnel_outer: MeshInstance3D
var _funnel_inner: MeshInstance3D
var _goddess: Node3D
var _goddess_wings: Array[MeshInstance3D] = []
var _waypoint: Vector3
var _waypoint_timer: float = 0.0
var _life: float = 0.0
var _max_life: float = 185.0
var _thunder_timer: float = 6.0
var _audio: AudioStreamPlayer3D
var _spawn_center: Vector3

const RADIUS: float = 85.0

func _ready() -> void:
	add_to_group("cyclone")
	_spawn_center = global_position
	_pick_waypoint()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.5)
	var tex: Texture2D = GameMaterials.tex("cyclone_smoke")
	if tex != null:
		mat.albedo_texture = tex
	mat.uv1_scale = Vector3(3.0, 2.0, 3.0)
	_funnel_outer = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 55.0
	cyl.bottom_radius = 9.0
	cyl.height = 260.0
	cyl.radial_segments = 24
	cyl.rings = 3
	cyl.cap_top = false
	cyl.cap_bottom = false
	_funnel_outer.mesh = cyl
	_funnel_outer.material_override = mat
	_funnel_outer.position = Vector3(0, 130, 0)
	_funnel_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_funnel_outer)
	_funnel_inner = MeshInstance3D.new()
	var cyl2 := CylinderMesh.new()
	cyl2.top_radius = 30.0
	cyl2.bottom_radius = 5.0
	cyl2.height = 240.0
	cyl2.radial_segments = 18
	cyl2.rings = 2
	cyl2.cap_top = false
	cyl2.cap_bottom = false
	_funnel_inner.mesh = cyl2
	var mat2: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(0.55, 0.6, 0.75, 0.6)
	_funnel_inner.material_override = mat2
	_funnel_inner.position = Vector3(0, 120, 0)
	_funnel_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_funnel_inner)
	# Обломки и листья в вихре
	var debris := CPUParticles3D.new()
	debris.amount = 90
	debris.lifetime = 2.6
	debris.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	debris.emission_ring_radius = 16.0
	debris.emission_ring_inner_radius = 8.0
	debris.emission_ring_height = 30.0
	debris.emission_ring_axis = Vector3.UP
	debris.orbit_velocity_min = 0.7
	debris.orbit_velocity_max = 1.1
	debris.initial_velocity_min = 6.0
	debris.initial_velocity_max = 12.0
	debris.direction = Vector3.UP
	debris.spread = 12.0
	debris.scale_amount_min = 0.3
	debris.scale_amount_max = 0.8
	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.4, 0.12, 0.3)
	debris_mesh.material = GameMaterials.plain(Color(0.25, 0.3, 0.15), 1.0)
	debris.mesh = debris_mesh
	debris.position = Vector3(0, 6, 0)
	add_child(debris)
	_build_goddess()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = AudioManager.get_stream("cyclone_roar")
	_audio.bus = "SFX"
	_audio.max_distance = 900.0
	_audio.volume_db = -4.0
	add_child(_audio)
	if _audio.stream != null:
		_audio.play()
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.75, 1.0)
	light.light_energy = 0.8
	light.omni_range = 120.0
	light.position = Vector3(0, 40, 0)
	add_child(light)

## Маленькая озорная Богиня Ветра на вершине вихря.
func _build_goddess() -> void:
	_goddess = Node3D.new()
	_goddess.position = Vector3(0, 150, 0)
	add_child(_goddess)
	var dress: Material = GameMaterials.silk(Color(0.55, 0.9, 1.0), "silk_blue_albedo")
	var skin: Material = GameMaterials.plain(Color(1.0, 0.88, 0.78), 0.55)
	var skirt := MeshInstance3D.new()
	skirt.mesh = MeshBuilder.skirt_mesh(0.28, 1.1, 1.5)
	skirt.material_override = dress
	skirt.position = Vector3(0, 0.4, 0)
	_goddess.add_child(skirt)
	var torso := MeshInstance3D.new()
	torso.mesh = MeshBuilder.capsule(0.3, 0.9)
	torso.material_override = dress
	torso.position = Vector3(0, 1.35, 0)
	_goddess.add_child(torso)
	var head := MeshInstance3D.new()
	head.mesh = MeshBuilder.ellipsoid(0.34, Vector3.ONE)
	head.material_override = skin
	head.position = Vector3(0, 2.05, 0)
	_goddess.add_child(head)
	var hair := MeshInstance3D.new()
	hair.mesh = MeshBuilder.ellipsoid(0.37, Vector3.ONE)
	hair.material_override = GameMaterials.silk(Color(0.75, 0.95, 1.0), "hair_white_albedo")
	hair.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.35, 1.0)), Vector3(0, 1.95, -0.08))
	_goddess.add_child(hair)
	for side: float in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.mesh = MeshBuilder.wing_mesh(1.6, 0.6, 0.18)
		wing.material_override = GameMaterials.pvc_white()
		wing.position = Vector3(side * 0.25, 1.65, -0.25)
		if side < 0.0:
			wing.rotation.y = PI
		_goddess.add_child(wing)
		_goddess_wings.append(wing)
	var halo := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.44
	halo.mesh = torus
	halo.material_override = GameMaterials.emission(Color(0.8, 0.95, 1.0), 2.0)
	halo.position = Vector3(0, 2.6, 0)
	halo.rotation_degrees.x = 78
	_goddess.add_child(halo)
	_goddess.scale = Vector3.ONE * 2.2 # видна издалека на вершине воронки

func _pick_waypoint() -> void:
	var ang: float = randf() * TAU
	var dist: float = randf_range(40.0, 190.0)
	_waypoint = _spawn_center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	# Иногда шалунья ведёт циклон прямо к Юмику
	if GameState.player != null and randf() < 0.35:
		_waypoint = GameState.player.global_position
	if GameState.world != null:
		_waypoint.y = float(GameState.world.call("get_height_at", _waypoint.x, _waypoint.z))
	_waypoint_timer = randf_range(8.0, 16.0)

## Поле ветра вихря: касательное + внутрь + вверх у ядра.
func wind_velocity_at(world_pos: Vector3) -> Vector3:
	var rel: Vector3 = world_pos - global_position
	rel.y = 0
	var dist: float = rel.length()
	if dist > RADIUS or dist < 0.01:
		return Vector3.ZERO
	var radial: Vector3 = rel / dist
	var tangential: Vector3 = Vector3.UP.cross(radial)
	var falloff: float = 1.0 - dist / RADIUS
	var core: float = clampf(1.0 - dist / 26.0, 0.0, 1.0)
	var v: Vector3 = tangential * (26.0 * falloff + 10.0)
	v += -radial * (9.0 * falloff)
	v.y = 20.0 * core + 3.0 * falloff
	return v

func _physics_process(_delta: float) -> void:
	# Тела в радиусе вихря затягивает и поднимает
	for node: Node in get_tree().get_nodes_in_group("suction_affected"):
		var rb := node as RigidBody3D
		if rb == null:
			continue
		var v: Vector3 = wind_velocity_at(rb.global_position)
		if v.length() > 0.1:
			rb.apply_central_force((v - rb.linear_velocity * 0.6) * rb.mass * 1.4)
	# Замок тоже шатает и крутит (Богиня Ветра довольна шалостью)
	var castle = GameState.castle
	if castle != null:
		var cb := castle as RigidBody3D
		var v2: Vector3 = wind_velocity_at(cb.global_position + Vector3.UP * 12.0)
		if v2.length() > 0.1:
			cb.apply_force(v2 * cb.mass * 0.32, Vector3.UP * 10.0)
			cb.apply_torque(Vector3.UP * cb.mass * 0.55)

func _process(delta: float) -> void:
	_life += delta
	if _life > _max_life or WindManager.current_preset != "Ураган":
		queue_free()
		return
	_funnel_outer.rotation.y += delta * 2.6
	_funnel_inner.rotation.y -= delta * 3.8
	_waypoint_timer -= delta
	if _waypoint_timer <= 0.0 or global_position.distance_to(_waypoint) < 14.0:
		_pick_waypoint()
	var to_wp: Vector3 = _waypoint - global_position
	to_wp.y = 0
	if to_wp.length() > 1.0:
		global_position += to_wp.normalized() * 6.5 * delta
	if GameState.world != null:
		global_position.y = float(GameState.world.call("get_height_at", global_position.x, global_position.z))
	# Богиня кружится и машет крыльями на вершине
	_goddess.rotation.y += delta * 1.6
	_goddess.position.y = 150.0 + sin(_life * 1.3) * 9.0
	for i: int in _goddess_wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		_goddess_wings[i].rotation.z = side * sin(_life * 7.0) * 0.45
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		_thunder_timer = randf_range(5.0, 14.0)
		AudioManager.play_sfx_3d("thunder_" + str(randi() % 2 + 1), global_position + Vector3.UP * 60, -2.0, 1200.0)
