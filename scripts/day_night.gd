extends Node3D
## DayNight — смена суток: солнце/луна (DirectionalLight3D), процедурное небо
## (ProceduralSkyMaterial), оболочка звёзд и луны на ночь, туман, экспозиция.
## Старт игры — 22:00 (ночь, хоррор-атмосфера).

var sun: DirectionalLight3D
var env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var environment: Environment
var star_shell: MeshInstance3D
var moon_quad: MeshInstance3D
var follow_target: Node3D = null

# Палитры: час -> (цвет верха неба, цвет горизонта, энергия света, цвет света)
const PALETTE: Array = [
	[0.0, Color(0.008, 0.01, 0.05), Color(0.03, 0.03, 0.09), 0.22, Color(0.55, 0.65, 1.0)], # полночь (луна)
	[5.0, Color(0.01, 0.015, 0.06), Color(0.05, 0.04, 0.1), 0.22, Color(0.55, 0.65, 1.0)],
	[6.5, Color(0.15, 0.2, 0.4), Color(0.85, 0.45, 0.25), 0.7, Color(1.0, 0.6, 0.35)], # рассвет
	[9.0, Color(0.25, 0.45, 0.85), Color(0.65, 0.75, 0.9), 1.25, Color(1.0, 0.95, 0.85)],
	[13.0, Color(0.2, 0.42, 0.9), Color(0.6, 0.72, 0.9), 1.35, Color(1.0, 0.98, 0.92)], # день
	[17.5, Color(0.22, 0.35, 0.7), Color(0.7, 0.6, 0.55), 1.05, Color(1.0, 0.9, 0.75)],
	[19.5, Color(0.1, 0.1, 0.3), Color(0.9, 0.4, 0.2), 0.55, Color(1.0, 0.5, 0.3)], # закат
	[21.0, Color(0.012, 0.015, 0.07), Color(0.06, 0.05, 0.13), 0.24, Color(0.55, 0.65, 1.0)],
	[24.0, Color(0.008, 0.01, 0.05), Color(0.03, 0.03, 0.09), 0.22, Color(0.55, 0.65, 1.0)],
]

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.12
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0012
	environment.fog_sky_affect = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	environment.glow_strength = 0.7
	env = WorldEnvironment.new()
	env.environment = environment
	add_child(env)
	# Звёздная оболочка (видна ночью) и луна следуют за игроком
	star_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 4000.0
	sphere.height = 8000.0
	sphere.radial_segments = 32
	sphere.rings = 16
	star_shell.mesh = sphere
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_FRONT # рисуем внутреннюю сторону
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var stars_tex: Texture2D = GameMaterials.tex("sky_stars")
	if stars_tex != null:
		sm.albedo_texture = stars_tex
	star_shell.material_override = sm
	star_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star_shell)
	moon_quad = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(340, 340)
	moon_quad.mesh = quad
	moon_quad.material_override = GameMaterials.sprite_mat("moon")
	moon_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon_quad)
	_update_sky(GameState.hour_float())

func _process(_delta: float) -> void:
	_update_sky(GameState.hour_float())
	if follow_target != null:
		var p: Vector3 = follow_target.global_position
		star_shell.global_position = p
		var moon_dir: Vector3 = (Basis(Vector3.RIGHT, deg_to_rad(-38.0)) * Vector3(0.35, 0.75, -0.55)).normalized()
		moon_quad.global_position = p + moon_dir * 3600.0
		moon_quad.look_at(p, Vector3.UP)

func _palette_at(hour: float) -> Array:
	for i: int in PALETTE.size() - 1:
		var a: Array = PALETTE[i]
		var b: Array = PALETTE[i + 1]
		if hour >= float(a[0]) and hour <= float(b[0]):
			var t: float = (hour - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return [
				(a[1] as Color).lerp(b[1] as Color, t),
				(a[2] as Color).lerp(b[2] as Color, t),
				lerpf(float(a[3]), float(b[3]), t),
				(a[4] as Color).lerp(b[4] as Color, t),
			]
	return [PALETTE[0][1], PALETTE[0][2], PALETTE[0][3], PALETTE[0][4]]

func _update_sky(hour: float) -> void:
	var pal: Array = _palette_at(hour)
	var top: Color = pal[0]
	var horizon: Color = pal[1]
	var energy: float = pal[2]
	var light_col: Color = pal[3]
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky_mat.ground_horizon_color = horizon.darkened(0.4)
	sky_mat.energy_multiplier = 1.0
	# Солнце днём идёт по дуге; ночью тот же источник — луна (высокий холодный угол)
	var is_day: bool = hour > 5.8 and hour < 19.8
	if is_day:
		var day_t: float = (hour - 6.0) / 13.0
		var elev: float = lerpf(-4.0, 62.0, sin(day_t * PI))
		var azim: float = lerpf(-95.0, 95.0, day_t)
		sun.rotation_degrees = Vector3(-elev, azim, 0)
	else:
		sun.rotation_degrees = Vector3(-52.0, -35.0, 0)
	sun.light_energy = energy
	sun.light_color = light_col
	environment.fog_light_color = horizon
	environment.fog_density = 0.0007 if is_day else 0.0016
	environment.tonemap_exposure = 1.05 if is_day else 0.9
	var star_alpha: float = clampf(1.2 - energy, 0.0, 1.0)
	(star_shell.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, star_alpha)
	star_shell.visible = star_alpha > 0.03
	moon_quad.visible = not is_day
