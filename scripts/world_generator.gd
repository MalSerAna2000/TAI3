extends Node3D
## WorldGenerator — процедурный открытый мир: чанки 256 м, FastNoiseLite,
## три НЕпересекающиеся зоны (Равнины / Водоёмы / Горы) с плавными переходами
## высоты (коллизия HeightMapShape3D — одна на чанк, без пересечений коллизий).
## Генерация данных — в WorkerThreadPool, меши собираются в главном потоке.
## Стриминг вокруг игрока + скаттер (MultiMesh: сосны, мёртвые деревья, камни).

const CHUNK: float = 256.0
const RES: int = 33 # вершин на сторону чанка (шаг 8 м)
const WATER_Y: float = 0.0

var world_size_m: float = 1000.0
var view_distance: float = 2500.0

var _chunks: Dictionary = {} # Vector2i -> {root, mesh_instance, collision, scatter}
var _pending_tasks: Dictionary = {} # task_id -> Vector2i
var _ready_data: Dictionary = {} # Vector2i -> Dictionary с массивами (из воркера)
var _player: Node3D = null
var _last_chunk: Vector2i = Vector2i(99999, 99999)
var _terrain_material: ShaderMaterial = null
var _mutex := Mutex.new()

func setup(player_node: Node3D) -> void:
	_player = player_node
	world_size_m = GameState.world_size_km * 1000.0
	view_distance = minf(3000.0, world_size_m * 0.75 + 600.0)
	_terrain_material = _make_terrain_material()
	# Синхронно строим чанки 3x3 вокруг спавна, чтобы земля уже была под ногами
	# игрока и замка в первом же физическом кадре (остальные догружает стриминг).
	var pc: Vector2i = _chunk_of(player_node.global_position)
	for cx: int in range(pc.x - 1, pc.x + 2):
		for cz: int in range(pc.y - 1, pc.y + 2):
			_build_chunk_data(Vector2i(cx, cz))
	_build_ready_chunks(9)
	_last_chunk = pc
	_update_streaming(true)

func _process(_delta: float) -> void:
	_poll_tasks()
	_build_ready_chunks(2)
	if _player != null:
		var pc: Vector2i = _chunk_of(_player.global_position)
		if pc != _last_chunk:
			_last_chunk = pc
			_update_streaming(false)

# ---------------------------------------------------------------- высоты ---
## Чистая функция высоты: одинаковый результат в любом потоке по (x, z, seed).
static func sample_height(x: float, z: float, world_seed: int, size_m: float) -> float:
	var zone_noise := FastNoiseLite.new()
	zone_noise.seed = world_seed + 11
	zone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zone_noise.frequency = 0.55 / maxf(size_m, 1000.0)
	zone_noise.fractal_octaves = 2
	var plains_noise := FastNoiseLite.new()
	plains_noise.seed = world_seed + 101
	plains_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	plains_noise.frequency = 0.004
	plains_noise.fractal_octaves = 4
	var mount_noise := FastNoiseLite.new()
	mount_noise.seed = world_seed + 202
	mount_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mount_noise.frequency = 0.0016
	mount_noise.fractal_octaves = 4
	return _height_with_noises(x, z, zone_noise, plains_noise, mount_noise, size_m)

static func _height_with_noises(x: float, z: float, zn: FastNoiseLite, pn: FastNoiseLite,
		mn: FastNoiseLite, size_m: float) -> float:
	var zone: float = zn.get_noise_2d(x, z)
	# Веса зон: непересекающиеся области, плавные берега/подножия
	var w_water: float = smoothstep(-0.12, -0.38, zone) # zone < -0.38 → водоёмы
	var w_mount: float = smoothstep(0.22, 0.5, zone) # zone > 0.5 → горы
	var plains_h: float = 7.0 + pn.get_noise_2d(x, z) * 4.5 + pn.get_noise_2d(x * 0.05, z * 0.05) * 0.5
	var bed_h: float = -5.0 + pn.get_noise_2d(x * 0.8 + 500.0, z * 0.8) * 1.5
	var ridge: float = 1.0 - absf(mn.get_noise_2d(x, z))
	var mount_h: float = 14.0 + pow(ridge, 2.0) * 230.0 + mn.get_noise_2d(x * 3.0, z * 3.0) * 6.0
	var h: float = plains_h
	h = lerpf(h, bed_h, w_water)
	h = lerpf(h, mount_h, w_mount)
	# Стартовая долина у начала координат: ровная равнина (замок + спавн игрока)
	var d_center: float = Vector2(x, z).length()
	var flat_k: float = smoothstep(70.0, 130.0, d_center)
	h = lerpf(7.0, h, flat_k)
	# Горный вал по границе мира — естественная стена
	var half_size: float = size_m * 0.5
	var edge: float = maxf(absf(x), absf(z)) / half_size
	if edge > 0.9:
		h += (edge - 0.9) * 1600.0
	return h

func get_height_at(x: float, z: float) -> float:
	return sample_height(x, z, GameState.world_seed, world_size_m)

## Зона в точке: 0 равнины, 1 водоёмы, 2 горы.
func get_zone_at(x: float, z: float) -> int:
	var zn := FastNoiseLite.new()
	zn.seed = GameState.world_seed + 11
	zn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zn.frequency = 0.55 / maxf(world_size_m, 1000.0)
	zn.fractal_octaves = 2
	var v: float = zn.get_noise_2d(x, z)
	if Vector2(x, z).length() < 130.0:
		return 0
	if v < -0.25:
		return 1
	if v > 0.36:
		return 2
	return 0

# -------------------------------------------------------------- стриминг ---
func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))

func _update_streaming(_force: bool) -> void:
	if _player == null:
		return
	var pc: Vector2i = _chunk_of(_player.global_position)
	var radius: int = int(ceil(view_distance / CHUNK))
	var half_chunks: int = int(ceil(world_size_m * 0.5 / CHUNK))
	# Запрос недостающих чанков
	for cx: int in range(pc.x - radius, pc.x + radius + 1):
		for cz: int in range(pc.y - radius, pc.y + radius + 1):
			if maxi(absi(cx), absi(cz)) > half_chunks:
				continue
			var key := Vector2i(cx, cz)
			var center := Vector3((cx + 0.5) * CHUNK, 0, (cz + 0.5) * CHUNK)
			if center.distance_to(_player.global_position) > view_distance + CHUNK:
				continue
			if _chunks.has(key) or _ready_data.has(key) or _is_task_pending(key):
				continue
			var task_id: int = WorkerThreadPool.add_task(Callable(self, "_build_chunk_data").bind(key), false, "chunk")
			_pending_tasks[task_id] = key
	# Выгрузка дальних + отключение коллизий у неближних
	var remove_keys: Array = []
	for key: Variant in _chunks.keys():
		var c := key as Vector2i
		var center := Vector3((c.x + 0.5) * CHUNK, 0, (c.y + 0.5) * CHUNK)
		var dist: float = center.distance_to(_player.global_position)
		if dist > view_distance + CHUNK * 2.0:
			remove_keys.append(key)
		else:
			var info: Dictionary = _chunks[key]
			var col := info["collision"] as CollisionShape3D
			if col != null:
				# Коллизия активна только в радиусе ~2 чанков (LOD физики)
				col.disabled = dist > CHUNK * 2.2
	for k: Variant in remove_keys:
		var info: Dictionary = _chunks[k]
		(info["root"] as Node).queue_free()
		_chunks.erase(k)

func _is_task_pending(key: Vector2i) -> bool:
	return _pending_tasks.values().has(key)

func _poll_tasks() -> void:
	var done: Array = []
	for task_id: Variant in _pending_tasks.keys():
		if WorkerThreadPool.is_task_completed(int(task_id)):
			WorkerThreadPool.wait_for_task_completion(int(task_id))
			done.append(task_id)
	for t: Variant in done:
		_pending_tasks.erase(t)

## Воркер: только массивы данных, никаких нод/ресурсов сцены.
func _build_chunk_data(key: Vector2i) -> void:
	var seed_v: int = GameState.world_seed
	var size_m: float = world_size_m
	var zn := FastNoiseLite.new()
	zn.seed = seed_v + 11
	zn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zn.frequency = 0.55 / maxf(size_m, 1000.0)
	zn.fractal_octaves = 2
	var pn := FastNoiseLite.new()
	pn.seed = seed_v + 101
	pn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pn.frequency = 0.004
	pn.fractal_octaves = 4
	var mn := FastNoiseLite.new()
	mn.seed = seed_v + 202
	mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mn.frequency = 0.0016
	mn.fractal_octaves = 4
	var ox: float = key.x * CHUNK
	var oz: float = key.y * CHUNK
	var step: float = CHUNK / float(RES - 1)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(RES * RES)
	for j: int in RES:
		for i: int in RES:
			heights[j * RES + i] = _height_with_noises(ox + i * step, oz + j * step, zn, pn, mn, size_m)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize(RES * RES)
	normals.resize(RES * RES)
	uvs.resize(RES * RES)
	colors.resize(RES * RES)
	for j: int in RES:
		for i: int in RES:
			var idx: int = j * RES + i
			var h: float = heights[idx]
			var hx: float = heights[j * RES + mini(i + 1, RES - 1)] - heights[j * RES + maxi(i - 1, 0)]
			var hz: float = heights[mini(j + 1, RES - 1) * RES + i] - heights[maxi(j - 1, 0) * RES + i]
			var n: Vector3 = Vector3(-hx, 2.0 * step, -hz).normalized()
			verts[idx] = Vector3(i * step, h, j * step)
			normals[idx] = n
			uvs[idx] = Vector2((ox + i * step) / 8.0, (oz + j * step) / 8.0)
			# COLOR = веса текстур для terrain.gdshader: R трава, G камень, B песок
			var slope: float = 1.0 - n.y
			var w_rock: float = clampf(slope * 3.2, 0.0, 1.0)
			if h > 90.0:
				w_rock = maxf(w_rock, 0.65)
			var w_sand: float = clampf(1.0 - absf(h - 0.4) / 2.2, 0.0, 1.0) * (1.0 - w_rock)
			var w_grass: float = clampf(1.0 - w_rock - w_sand, 0.0, 1.0)
			colors[idx] = Color(w_grass, w_rock, w_sand)
	var indices := PackedInt32Array()
	for j: int in RES - 1:
		for i: int in RES - 1:
			var a: int = j * RES + i
			var b: int = a + 1
			var c: int = a + RES
			var d: int = c + 1
			indices.append_array([a, c, b, b, c, d])
	var data: Dictionary = {
		"heights": heights, "verts": verts, "normals": normals,
		"uvs": uvs, "colors": colors, "indices": indices,
	}
	_mutex.lock()
	_ready_data[key] = data
	_mutex.unlock()

func _build_ready_chunks(max_per_frame: int) -> void:
	_mutex.lock()
	var keys: Array = _ready_data.keys()
	_mutex.unlock()
	var built: int = 0
	for key: Variant in keys:
		if built >= max_per_frame:
			break
		_mutex.lock()
		var data: Dictionary = _ready_data[key]
		_ready_data.erase(key)
		_mutex.unlock()
		_spawn_chunk(key as Vector2i, data)
		built += 1

func _spawn_chunk(key: Vector2i, data: Dictionary) -> void:
	if _chunks.has(key):
		return
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	root.position = Vector3(key.x * CHUNK, 0, key.y * CHUNK)
	add_child(root)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _terrain_material
	mi.visibility_range_end = view_distance + CHUNK
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	# Коллизия: HeightMapShape3D (Jolt), одна на чанк — зоны не пересекаются
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("terrain")
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	shape.map_data = data["heights"]
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var step: float = CHUNK / float(RES - 1)
	cs.position = Vector3(CHUNK * 0.5, 0, CHUNK * 0.5)
	cs.scale = Vector3(step, 1.0, step)
	body.add_child(cs)
	root.add_child(body)
	_spawn_scatter(key, root)
	_chunks[key] = {"root": root, "collision": cs}

## Скаттер MultiMesh: сосны на равнинах, камни в горах, мёртвые деревья редко.
func _spawn_scatter(key: Vector2i, root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3(key.x, GameState.world_seed, key.y))
	var ox: float = key.x * CHUNK
	var oz: float = key.y * CHUNK
	var pine_xf: Array[Transform3D] = []
	var rock_xf: Array[Transform3D] = []
	var dead_xf: Array[Transform3D] = []
	for i: int in 46:
		var lx: float = rng.randf() * CHUNK
		var lz: float = rng.randf() * CHUNK
		var wx: float = ox + lx
		var wz: float = oz + lz
		if Vector2(wx, wz).length() < 95.0:
			continue # стартовая поляна у замка чистая
		var h: float = get_height_at(wx, wz)
		if h < 0.8:
			continue
		var zone: int = get_zone_at(wx, wz)
		var s: float = rng.randf_range(0.8, 1.5)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(lx, h - 0.15, lz))
		if zone == 2:
			rock_xf.append(xf)
		elif zone == 0:
			if rng.randf() < 0.06:
				dead_xf.append(xf)
			else:
				pine_xf.append(xf)
	_add_multimesh(root, MeshBuilder.pine_tree_mesh(), pine_xf)
	_add_multimesh(root, MeshBuilder.rock_mesh(), rock_xf)
	_add_multimesh(root, MeshBuilder.dead_tree_mesh(), dead_xf)

func _add_multimesh(root: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = 1400.0 # LOD: мелкий скаттер не рисуем издалека
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mmi)

func _make_terrain_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D snow_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_tex : repeat_enable, filter_linear_mipmap;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec3 g = texture(grass_tex, UV).rgb;
	vec3 r = texture(rock_tex, UV).rgb;
	vec3 s = texture(sand_tex, UV).rgb;
	vec3 alb = g * COLOR.r + r * COLOR.g + s * COLOR.b;
	float snow_k = smoothstep(140.0, 200.0, world_y) * (0.4 + 0.6 * COLOR.g);
	alb = mix(alb, texture(snow_tex, UV).rgb, snow_k);
	ALBEDO = alb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
"""
	sm.shader = shader
	sm.set_shader_parameter("grass_tex", GameMaterials.tex("grass_albedo"))
	sm.set_shader_parameter("rock_tex", GameMaterials.tex("rock_albedo"))
	sm.set_shader_parameter("sand_tex", GameMaterials.tex("sand_albedo"))
	sm.set_shader_parameter("snow_tex", GameMaterials.tex("snow_albedo"))
	sm.set_shader_parameter("normal_tex", GameMaterials.tex("grass_normal"))
	return sm
