extends RigidBody3D
## Одна кость ragdoll'а Юмика. Отскок от надувных поверхностей замка
## (тип поверхности — по индексу шейпа AeroBody3D), звуки контактов ПВХ,
## смертельные удары о твёрдую землю.

var player_ref: Node = null
var part_name: String = ""
var _sfx_cooldown: float = 0.0

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("ragdoll")
	add_to_group("suction_affected")
	collision_layer = 32 # слой 6 «Ragdoll»
	collision_mask = 1 | 4 | 16 # мир, замок, верёвки (не сам с собой по слою игрока)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.15
	physics_material_override = pm

func _process(delta: float) -> void:
	_sfx_cooldown = maxf(0.0, _sfx_cooldown - delta)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if freeze:
		return
	var count: int = state.get_contact_count()
	for i: int in count:
		var collider: Object = state.get_contact_collider_object(i)
		if collider == null:
			continue
		var impact_speed: float = state.get_contact_collider_velocity_at_position(i).distance_to(linear_velocity)
		var local_pos: Vector3 = state.get_contact_local_position(i)
		var contact_world: Vector3 = global_transform * local_pos
		var push_dir: Vector3 = (global_position - contact_world + Vector3.UP * 0.35).normalized()
		var node := collider as Node
		# Замок: упругий отскок в зависимости от поверхности шейпа
		if node != null and node.is_in_group("castle") and node.has_method("get_surface_type"):
			var shape_idx: int = state.get_contact_collider_shape(i)
			var surface: String = str(node.call("get_surface_type", shape_idx))
			if impact_speed > 1.6:
				var keep: float = 0.0
				if surface == "very_bouncy":
					keep = 1.0 # высота отскока не падает
				elif surface == "bouncy" or surface == "throne":
					keep = 0.62
				if keep > 0.0:
					var impulse: Vector3 = push_dir * impact_speed * keep * mass
					apply_impulse(impulse, local_pos)
					if _sfx_cooldown <= 0.0:
						_sfx_cooldown = 0.14
						AudioManager.play_sfx("boing_" + str(randi() % 3 + 1), -12.0, randf_range(0.9, 1.1))
			elif impact_speed > 0.7 and _sfx_cooldown <= 0.0:
				_sfx_cooldown = 0.2
				AudioManager.play_sfx("pvc_squeak_" + str(randi() % 4 + 1), -16.0, randf_range(0.9, 1.2))
		# Твёрдая земля: очень сильный удар головой/туловищем смертелен
		elif node != null and node.is_in_group("terrain"):
			if impact_speed > 19.0 and (part_name == "head" or part_name == "chest"):
				if player_ref != null and player_ref.has_method("die"):
					player_ref.call("die")
