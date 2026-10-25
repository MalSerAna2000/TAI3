class_name GameMaterials
## Фабрика PBR-материалов (Mobile renderer). Текстуры — PNG-исходники в
## assets/textures (при экспорте на Android сжимаются в ETC2/ASTC).
## Если текстура не найдена — материал строится от цвета (проект всё равно запустится).

const TEX_DIR: String = "res://assets/textures/"

static var _cache: Dictionary = {}

static func tex(name_no_ext: String) -> Texture2D:
	var path: String = TEX_DIR + name_no_ext + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

static func _pbr(key: String, albedo_name: String, tint: Color, roughness: float,
		uv_scale: Vector3 = Vector3.ONE, triplanar: bool = false) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var alb: Texture2D = tex(albedo_name)
	if alb != null:
		m.albedo_texture = alb
	var nrm: Texture2D = tex(albedo_name.replace("_albedo", "_normal"))
	if nrm != null:
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 0.8
	var rgh: Texture2D = tex(albedo_name.replace("_albedo", "_roughness"))
	if rgh != null:
		m.roughness_texture = rgh
	var ao: Texture2D = tex(albedo_name.replace("_albedo", "_ao"))
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.6
	m.roughness = roughness
	m.metallic = 0.0
	m.uv1_scale = uv_scale
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	_cache[key] = m
	return m

# --- ПВХ надувного замка: тёмно-красный готический, глянцевый ---
static func pvc_darkred() -> StandardMaterial3D:
	return _pbr("pvc_darkred", "pvc_darkred_albedo", Color(0.45, 0.03, 0.05), 0.32, Vector3(0.25, 0.25, 0.25), true)

static func pvc_white() -> StandardMaterial3D:
	return _pbr("pvc_white", "pvc_white_albedo", Color(0.95, 0.93, 0.9), 0.28, Vector3(0.4, 0.4, 0.4), true)

static func pvc_pink() -> StandardMaterial3D:
	return _pbr("pvc_pink", "pvc_pink_albedo", Color(0.95, 0.55, 0.65), 0.3, Vector3(0.5, 0.5, 0.5))

static func lace_darkred() -> StandardMaterial3D:
	return _pbr("lace_darkred", "lace_darkred_albedo", Color(0.5, 0.05, 0.08), 0.55, Vector3(2.0, 2.0, 2.0))

static func lace_white() -> StandardMaterial3D:
	if _cache.has("lace_white"):
		return _cache["lace_white"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.95)
	var t: Texture2D = tex("lace_white_albedo")
	if t != null:
		m.albedo_texture = t
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache["lace_white"] = m
	return m

static func silk(col: Color, tex_name: String) -> StandardMaterial3D:
	var key: String = "silk_" + tex_name
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	var t: Texture2D = tex(tex_name)
	if t != null:
		m.albedo_texture = t
	m.roughness = 0.45
	m.metallic = 0.05
	m.metallic_specular = 0.7
	_cache[key] = m
	return m

static func plain(col: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key: String = "plain_%s_%.2f" % [col.to_html(), roughness]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	_cache[key] = m
	return m

static func unshaded(col: Color) -> StandardMaterial3D:
	var key: String = "unshaded_" + col.to_html()
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	_cache[key] = m
	return m

static func emission(col: Color, energy: float) -> StandardMaterial3D:
	var key: String = "emission_%s_%.1f" % [col.to_html(), energy]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m

static func hair_white() -> StandardMaterial3D:
	return _pbr("hair_white", "hair_white_albedo", Color(0.96, 0.95, 0.98), 0.35, Vector3(1.5, 1.5, 1.5))

static func hair_black() -> StandardMaterial3D:
	return _pbr("hair_black", "hair_black_albedo", Color(0.03, 0.03, 0.04), 0.4, Vector3(1.5, 1.5, 1.5))

static func denim() -> StandardMaterial3D:
	return _pbr("denim", "denim_albedo", Color(0.25, 0.4, 0.7), 0.9, Vector3(2.0, 2.0, 2.0))

static func cotton_white() -> StandardMaterial3D:
	return _pbr("cotton", "cotton_white_albedo", Color(0.95, 0.95, 0.93), 0.95, Vector3(2.0, 2.0, 2.0))

static func rope_hemp() -> StandardMaterial3D:
	return _pbr("rope", "rope_hemp_albedo", Color(0.6, 0.5, 0.35), 1.0, Vector3(1.0, 4.0, 1.0))

static func bark() -> StandardMaterial3D:
	return _pbr("bark", "bark_albedo", Color(0.3, 0.2, 0.12), 1.0, Vector3(1.0, 2.0, 1.0))

static func pine_green() -> StandardMaterial3D:
	return _pbr("pine", "pine_albedo", Color(0.08, 0.25, 0.1), 1.0, Vector3(2.0, 2.0, 2.0))

static func rock_gray() -> StandardMaterial3D:
	return _pbr("rock", "rock_albedo", Color(0.4, 0.4, 0.42), 0.95, Vector3(0.2, 0.2, 0.2), true)

## Спрайтовая текстура (глаза/рот/сердечки) — unshaded с альфой.
static func sprite_mat(tex_name: String) -> StandardMaterial3D:
	var key: String = "sprite_" + tex_name
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var t: Texture2D = tex(tex_name)
	if t != null:
		m.albedo_texture = t
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_cache[key] = m
	return m
