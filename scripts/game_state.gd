extends Node
## GameState (autoload) — настройки мира из стартового меню, игровое время,
## ссылки на игрока/замок, воскрешение Юмика (3 с, радиус 10 м), сон/эйфория.

signal clock_changed(hour_float: float)
signal player_died(at_position: Vector3)
signal player_respawned

# --- Настройки из стартового меню ---
var world_seed: int = 1337
var world_size_km: float = 1.0 # 1x1, 10x10 или 50x50 км

# --- Время: старт 22:00. 1 реальная секунда = 1 игровая минута ---
var game_minutes: float = 22.0 * 60.0
var time_scale: float = 60.0 # игровых секунд за реальную секунду
var day_count: int = 1

# --- Ссылки на ключевые ноды (выставляются Main) ---
var player: YumikPlayer = null
var castle: CastleNZTB = null
var world: WorldGenerator = null

# --- Сон от эйфории (няшинг) ---
var sleeping: bool = false
var sleep_skip_requested: bool = false

var _clock_emit_acc: float = 0.0
var _death_pos: Vector3 = Vector3.ZERO
var _respawn_timer: float = -1.0

func _process(delta: float) -> void:
	game_minutes += delta * time_scale / 60.0
	if game_minutes >= 1440.0:
		game_minutes -= 1440.0
		day_count += 1
	_clock_emit_acc += delta
	if _clock_emit_acc > 0.25:
		_clock_emit_acc = 0.0
		clock_changed.emit(hour_float())
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_do_respawn()

func hour_float() -> float:
	return fmod(game_minutes, 1440.0) / 60.0

func clock_string() -> String:
	var total: int = int(game_minutes) % 1440
	return "%02d:%02d" % [total / 60, total % 60]

func is_night() -> bool:
	var h: float = hour_float()
	return h < 5.5 or h > 19.0

func advance_game_minutes(minutes: float) -> void:
	game_minutes += minutes
	while game_minutes >= 1440.0:
		game_minutes -= 1440.0
		day_count += 1

## Юмик погиб: воскрешение через 3 секунды в радиусе 10 м от места гибели.
func kill_player(at_position: Vector3) -> void:
	_death_pos = at_position
	_respawn_timer = 3.0
	player_died.emit(at_position)

func _do_respawn() -> void:
	if player == null:
		return
	# Случайная точка кольца 5–10 м от места гибели (страха нет — он просто возвращается)
	var ang: float = randf() * TAU
	var dist: float = randf_range(5.0, 10.0)
	var target: Vector3 = _death_pos + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
	if world != null:
		target.y = maxf(world.get_height_at(target.x, target.z) + 1.2, _death_pos.y)
	else:
		target.y = _death_pos.y + 1.0
	player.respawn_at(target)
	player_respawned.emit()
