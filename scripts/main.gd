extends Node3D
## Main — сборка игры: процедурный мир, НЗТБНЗ (AeroBody3D), Юмик в 50 м от замка,
## AeroAtmosphere3D с глобальным ветром, вода водоёмов, смена суток (старт 22:00),
## HUD, спавн Воровки тропического циклона при урагане, отладочный ввод с ПК.

const CycloneScript: GDScript = preload("res://scripts/cyclone.gd")

var _player: YumikPlayer
var _castle: CastleNZTB
var _world: WorldGenerator
var _atmosphere: AeroAtmosphere3D
var _water: MeshInstance3D
var _hud: GameHUD
var _cyclone: Node3D = null
var _ambience_timer: float = 0.0
var _kb_active: bool = false

func _ready() -> void:
	GameState.game_minutes = 22.0 * 60.0 # старт — 22:00 ночи
	# Небо, солнце/луна, туман
	var day_night := Node3D.new()
	day_night.set_script(preload("res://scripts/day_night.gd"))
	day_night.name = "DayNight"
	add_child(day_night)
	# Процедурный мир
	_world = Node3D.new()
	_world.set_script(preload("res://scripts/world_generator.gd"))
	_world.name = "World"
	add_child(_world)
	GameState.world = _world
	# Замок в начале координат стартовой долины
	var castle_scene := load("res://scenes/nztbnz.tscn") as PackedScene
	_castle = castle_scene.instantiate() as CastleNZTB
	var castle_h: float = _world.call("get_height_at", 0.0, 0.0)
	add_child(_castle)
	_castle.global_position = Vector3(0, castle_h + 0.25, 0)
	GameState.castle = _castle
	# Юмик в 50 м к югу от замка, лицом к нему
	var player_scene := load("res://scenes/player.tscn") as PackedScene
	_player = player_scene.instantiate() as YumikPlayer
	add_child(_player)
	var spawn := Vector3(0, _world.call("get_height_at", 0.0, 50.0) + 0.3, 50.0)
	_player.call("setup_spawn", spawn, 0.0)
	GameState.player = _player
	# Глобальная атмосфера плагина Aerodynamic Physics (ветер)
	_atmosphere = AeroAtmosphere3D.new()
	_atmosphere.name = "GlobalAtmosphere"
	var atmo_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12000, 2400, 12000)
	atmo_shape.shape = box
	_atmosphere.add_child(atmo_shape)
	_atmosphere.collision_layer = 0
	_atmosphere.collision_mask = 4 | 32 # замок и ragdoll
	_atmosphere.monitoring = true
	_atmosphere.density = 1.225
	_atmosphere.override_density = true
	add_child(_atmosphere)
	_atmosphere.global_position = spawn + Vector3(0, 400, 0)
	WindManager.atmosphere = _atmosphere
	# Вода водоёмов: единая плоскость уровня y=0 следует за игроком
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7000, 7000)
	_water.mesh = plane
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader") as Shader
	water_mat.set_shader_parameter("normal_tex", GameMaterials.tex("water_normal"))
	_water.material_override = water_mat
	_water.position = Vector3(0, 0.05, 0)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	# Стриминг чанков вокруг игрока + цели следования
	_world.call("setup", _player)
	day_night.set("follow_target", _player)
	# HUD
	var hud_scene := load("res://scenes/hud.tscn") as PackedScene
	_hud = hud_scene.instantiate() as GameHUD
	add_child(_hud)
	# Циклон Богини Ветра при урагане
	WindManager.hurricane_started.connect(_spawn_cyclone)
	WindManager.hurricane_stopped.connect(_despawn_cyclone)
	# Атмосфера и музыка
	AudioManager.play_music("music_dark_ambient", -12.0)
	AudioManager.update_ambience(true, WindManager.current_kmh)
	_hud.show_toast("22:00. В 50 метрах впереди — Надувной Замок Темного Бога…")

func _spawn_cyclone() -> void:
	if _cyclone != null and is_instance_valid(_cyclone):
		return
	# Воровка тропического циклона появляется в 250 м от Юмика
	var ang: float = randf() * TAU
	var pos: Vector3 = _player.global_position + Vector3(cos(ang) * 250.0, 0, sin(ang) * 250.0)
	pos.y = _world.call("get_height_at", pos.x, pos.z)
	_cyclone = Node3D.new()
	_cyclone.set_script(CycloneScript)
	_cyclone.name = "CycloneThief"
	add_child(_cyclone)
	_cyclone.global_position = pos

func _despawn_cyclone() -> void:
	if _cyclone != null and is_instance_valid(_cyclone):
		_cyclone.queue_free()
	_cyclone = null

func _process(delta: float) -> void:
	if _player == null:
		return
	var p: Vector3 = _player.global_position
	_atmosphere.global_position = Vector3(p.x, 400.0, p.z)
	# Вода следует с привязкой к сетке 64 м, чтобы UV не «плыли»
	_water.global_position = Vector3(floorf(p.x / 64.0) * 64.0, 0.05, floorf(p.z / 64.0) * 64.0)
	_ambience_timer -= delta
	if _ambience_timer <= 0.0:
		_ambience_timer = 2.5
		AudioManager.update_ambience(GameState.is_night(), WindManager.current_kmh)
		var inside: bool = _castle != null and _castle.call("is_player_inside")
		_player.call("set_flashlight", GameState.is_night() or inside)
	_handle_keyboard(delta)

# ------------------------------------------------- отладка с клавиатуры ПК --
# (основное управление — сенсорное; это дублирование для тестов в редакторе)
func _handle_keyboard(_delta: float) -> void:
	var kx: float = 0.0
	var ky: float = 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kx -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kx += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		ky -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		ky += 1.0
	var kb: Vector2 = Vector2(kx, ky)
	var running: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	if kb.length() > 0.01 or _kb_active:
		_player.set_move_input(kb.limit_length(1.0), running)
		_kb_active = kb.length() > 0.01

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_player.add_camera_delta((event as InputEventMouseMotion).relative * 1.6)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.physical_keycode:
			KEY_SPACE:
				_player.press_jump()
			KEY_R:
				_player.toggle_lie()
			KEY_C:
				_player.toggle_crawl()
			KEY_F:
				_player.toggle_climb()
			KEY_E:
				_player.press_squeeze()
			KEY_Q:
				_player.toggle_hold_on()
			KEY_H:
				_player.toggle_hem()
			KEY_G:
				_player.try_toggle_outfit()
			KEY_TAB:
				_hud.toggle_debug_panel()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_1:
				WindManager.set_wind("Штиль")
			KEY_2:
				WindManager.set_wind("Слабый ветер")
			KEY_3:
				WindManager.set_wind("Свежий ветер")
			KEY_4:
				WindManager.set_wind("Очень крепкий ветер")
			KEY_5:
				WindManager.set_wind("Ураган")
