extends Node
## WindManager (autoload) — глобальный ветер (лорно: шалость Богини Ветра).
## Задаёт ветер в AeroAtmosphere3D (плагин Godot Aerodynamic Physics),
## применяет парусные силы к ragdoll-телам и спавнит «Воровку тропического
## циклона» при урагане. Пресеты из меню отладки; каждый действует 3 минуты.

signal wind_changed(preset_name: String, kmh: float)
signal hurricane_started
signal hurricane_stopped

const PRESETS: Dictionary = {
	"Штиль": 1.0,
	"Слабый ветер": 15.0,
	"Свежий ветер": 35.0,
	"Очень крепкий ветер": 70.0,
	"Ураган": 120.0,
}
const DURATION: float = 180.0 # 3 минуты реального времени

var current_preset: String = "Штиль"
var current_kmh: float = 1.0
var direction: Vector3 = Vector3.RIGHT # куда дует ветер (горизонтально)
var remaining: float = 0.0

var atmosphere = null # AeroAtmosphere3D, регистрируется из Main (тип не жёсткий: автозагрузка не должна зависеть от классов аддона при компиляции)

var _t: float = 0.0
# Тела, на которые ветер давит напрямую (ragdoll Юмика, подол платья и т.п.):
# {RigidBody3D: парусная площадь м^2}
var _sail_bodies: Dictionary = {}

func _ready() -> void:
	randomize_direction()

func randomize_direction() -> void:
	var a: float = randf() * TAU
	direction = Vector3(cos(a), 0.0, sin(a))

func set_wind(preset_name: String) -> void:
	if not PRESETS.has(preset_name):
		return
	var was_hurricane: bool = current_preset == "Ураган"
	current_preset = preset_name
	current_kmh = float(PRESETS[preset_name])
	remaining = DURATION
	randomize_direction()
	wind_changed.emit(current_preset, current_kmh)
	if preset_name == "Ураган" and not was_hurricane:
		hurricane_started.emit()
	elif was_hurricane and preset_name != "Ураган":
		hurricane_stopped.emit()

func wind_speed_ms() -> float:
	return current_kmh / 3.6

## Текущий вектор ветра с порывами (м/с, мировая СК).
func wind_vector() -> Vector3:
	var base: float = wind_speed_ms()
	var gust: float = 0.82 + 0.18 * sin(_t * 0.7) + 0.12 * sin(_t * 2.3 + 1.7)
	gust = clampf(gust, 0.55, 1.3)
	var v: Vector3 = direction * (base * gust)
	if current_kmh >= 70.0:
		# Турбулентные вертикальные порывы при сильном ветре
		v.y = sin(_t * 1.9) * base * 0.08
	return v

func register_sail_body(body: RigidBody3D, sail_area_m2: float) -> void:
	_sail_bodies[body] = sail_area_m2

func unregister_sail_body(body: RigidBody3D) -> void:
	_sail_bodies.erase(body)

func set_sail_area(body: RigidBody3D, sail_area_m2: float) -> void:
	if _sail_bodies.has(body):
		_sail_bodies[body] = sail_area_m2

func _physics_process(delta: float) -> void:
	_t += delta
	if remaining > 0.0:
		remaining -= delta
		if remaining <= 0.0 and current_preset != "Штиль":
			set_wind("Штиль")
	var wv: Vector3 = wind_vector()
	if atmosphere != null and is_instance_valid(atmosphere):
		atmosphere.wind = wv
		atmosphere.override_wind = true
	# Парусные силы для ragdoll и прочих тел: F = 0.5 * rho * |v_rel|^2 * Cd * A
	var dead: Array = []
	for body: Variant in _sail_bodies.keys():
		if not is_instance_valid(body):
			dead.append(body)
			continue
		var rb := body as RigidBody3D
		if rb.freeze or rb.sleeping:
			continue
		var area: float = float(_sail_bodies[body])
		if area <= 0.001:
			continue
		var v_rel: Vector3 = wv - rb.linear_velocity
		var speed: float = v_rel.length()
		if speed < 0.05:
			continue
		var force: Vector3 = v_rel.normalized() * (0.5 * 1.225 * speed * speed * 1.1 * area)
		rb.apply_central_force(force)
	for d: Variant in dead:
		_sail_bodies.erase(d)

func compass_string() -> String:
	var names: Array[String] = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]
	# direction — куда дует; компас показываем «откуда»
	var from: Vector3 = -direction
	var idx: int = int(round(atan2(from.x, -from.z) / (TAU / 8.0))) % 8
	if idx < 0:
		idx += 8
	return names[idx]
