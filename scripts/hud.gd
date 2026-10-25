extends CanvasLayer
## HUD: сенсорное управление (TouchControls), кнопки действий справа,
## «Не отпускай меня» и «Меню отладки» слева сверху, часы/состояние/ветер,
## полоса эйфории няшинга, оверлеи сна и гибели, тосты.

var _player = null
var _castle = null

var _btn_jump: Button
var _btn_lie: Button
var _btn_crawl: Button
var _btn_climb: Button
var _btn_squeeze: Button
var _btn_hem: Button
var _btn_outfit: Button
var _btn_hold: Button
var _btn_debug: Button
var _clock_label: Label
var _state_label: Label
var _wind_label: Label
var _toast_label: Label
var _toast_timer: float = 0.0
var _euphoria_bar: ProgressBar
var _euphoria_box: VBoxContainer
var _sleep_overlay: ColorRect
var _dream_overlay: ColorRect
var _death_overlay: ColorRect
var _death_label: Label
var _weak_overlay: ColorRect
var _debug_panel: PanelContainer
var _debug_info: Label
var _btn_sleep_skip: Button

func _ready() -> void:
	_player = GameState.player
	_castle = GameState.castle
	_build_ui()
	if _castle != null:
		_castle.connect("toast", show_toast)
		_castle.connect("sleep_started", _on_sleep_started)
		_castle.connect("sleep_finished", _on_sleep_finished)
	GameState.player_died.connect(_on_player_died)
	GameState.player_respawned.connect(_on_player_respawned)
	WindManager.wind_changed.connect(_on_wind_changed)

func _style_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(12)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _make_button(text: String, font_size: int = 21) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _style_box(Color(0.08, 0.01, 0.03, 0.72), Color(0.85, 0.3, 0.35, 0.85)))
	b.add_theme_stylebox_override("pressed", _style_box(Color(0.55, 0.08, 0.12, 0.85), Color(1.0, 0.6, 0.65, 1.0)))
	b.add_theme_stylebox_override("hover", _style_box(Color(0.2, 0.03, 0.06, 0.8), Color(0.9, 0.4, 0.45, 0.95)))
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.92))
	b.custom_minimum_size = Vector2(150, 58)
	return b

func _make_label(text: String, font_size: int = 20, col: Color = Color(1, 0.95, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _build_ui() -> void:
	var touch := TouchControls.new()
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(touch)
	touch.move_input.connect(func(v: Vector2, r: bool) -> void:
		if _player != null:
			_player.set_move_input(v, r))
	touch.camera_delta.connect(func(d: Vector2) -> void:
		if _player != null:
			_player.add_camera_delta(d))
	# --- Слева сверху ---
	var top_left := VBoxContainer.new()
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.position = Vector2(12, 12)
	top_left.add_theme_constant_override("separation", 8)
	add_child(top_left)
	_btn_hold = _make_button("🤲 Не отпускай меня")
	_btn_hold.pressed.connect(func() -> void:
		if _player != null:
			_player.toggle_hold_on())
	top_left.add_child(_btn_hold)
	_btn_debug = _make_button("🛠 Меню отладки")
	_btn_debug.pressed.connect(func() -> void:
		_debug_panel.visible = not _debug_panel.visible)
	top_left.add_child(_btn_debug)
	# --- Сверху по центру: статус ---
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_panel.position = Vector2(-190, 8)
	top_panel.custom_minimum_size = Vector2(380, 0)
	top_panel.add_theme_stylebox_override("panel", _style_box(Color(0.05, 0, 0.02, 0.6), Color(0.6, 0.2, 0.25, 0.7)))
	add_child(top_panel)
	var status_box := VBoxContainer.new()
	top_panel.add_child(status_box)
	_clock_label = _make_label("🌙 22:00", 24)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(_clock_label)
	_state_label = _make_label("НЗТБНЗ: Обычное", 18, Color(1.0, 0.75, 0.75))
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(_state_label)
	_wind_label = _make_label("💨 Штиль, 1 км/ч", 18, Color(0.75, 0.85, 1.0))
	_wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(_wind_label)
	# --- Справа: кнопки действий ---
	var right_box := VBoxContainer.new()
	right_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_box.position = Vector2(-205, -235)
	right_box.add_theme_constant_override("separation", 9)
	add_child(right_box)
	_btn_lie = _make_button("🛏 Лечь")
	_btn_lie.pressed.connect(func() -> void: _player.toggle_lie())
	right_box.add_child(_btn_lie)
	_btn_crawl = _make_button("🐾 На четвереньки")
	_btn_crawl.pressed.connect(func() -> void: _player.toggle_crawl())
	right_box.add_child(_btn_crawl)
	_btn_climb = _make_button("🧗 Вскарабкаться")
	_btn_climb.pressed.connect(func() -> void: _player.toggle_climb())
	right_box.add_child(_btn_climb)
	_btn_jump = _make_button("🦘 Прыжок", 25)
	_btn_jump.custom_minimum_size = Vector2(180, 74)
	_btn_jump.pressed.connect(func() -> void: _player.press_jump())
	right_box.add_child(_btn_jump)
	_btn_squeeze = _make_button("🤗 Тискать")
	_btn_squeeze.pressed.connect(func() -> void: _player.press_squeeze())
	right_box.add_child(_btn_squeeze)
	_btn_hem = _make_button("👗 Задрать подол")
	_btn_hem.pressed.connect(func() -> void: _player.toggle_hem())
	_btn_hem.visible = false
	right_box.add_child(_btn_hem)
	_btn_outfit = _make_button("🎀 Платье горничной")
	_btn_outfit.pressed.connect(func() -> void: _player.try_toggle_outfit())
	_btn_outfit.visible = false
	right_box.add_child(_btn_outfit)
	# --- Эйфория няшинга ---
	_euphoria_box = VBoxContainer.new()
	_euphoria_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_euphoria_box.position = Vector2(-240, -110)
	_euphoria_box.custom_minimum_size = Vector2(480, 0)
	add_child(_euphoria_box)
	var euph_label := _make_label("💗 Няшинг! Вырывайся джойстиком или тискай в ответ…", 19, Color(1.0, 0.75, 0.85))
	euph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_euphoria_box.add_child(euph_label)
	_euphoria_bar = ProgressBar.new()
	_euphoria_bar.min_value = 0
	_euphoria_bar.max_value = 100
	_euphoria_bar.value = 0
	_euphoria_bar.custom_minimum_size = Vector2(480, 26)
	_euphoria_bar.add_theme_stylebox_override("background", _style_box(Color(0.1, 0, 0.04, 0.7), Color(1, 0.5, 0.65, 0.8)))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.35, 0.55, 0.92)
	fill.set_corner_radius_all(10)
	_euphoria_bar.add_theme_stylebox_override("fill", fill)
	_euphoria_box.add_child(_euphoria_bar)
	_euphoria_box.visible = false
	# --- Тост по центру ---
	_toast_label = _make_label("", 23, Color(1.0, 0.9, 0.8))
	_toast_label.set_anchors_preset(Control.PRESET_CENTER)
	_toast_label.position = Vector2(-400, -170)
	_toast_label.custom_minimum_size = Vector2(800, 40)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)
	# --- Оверлеи ---
	_weak_overlay = _overlay(Color(1.0, 0.4, 0.55, 0.0))
	_dream_overlay = _overlay(Color(1.0, 0.55, 0.7, 0.0))
	_sleep_overlay = _overlay(Color(0.0, 0.0, 0.02, 0.0))
	var sleep_label := _make_label("💤 Юмик спит в объятиях Темного Бога… Ему снится няшинг", 26, Color(1, 0.85, 0.9))
	sleep_label.set_anchors_preset(Control.PRESET_CENTER)
	sleep_label.position = Vector2(-420, 120)
	sleep_label.custom_minimum_size = Vector2(840, 40)
	sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_overlay.add_child(sleep_label)
	_death_overlay = _overlay(Color(0.25, 0.0, 0.02, 0.0))
	_death_label = _make_label("Юмик погиб… воскрешение через 3 с", 28, Color(1, 0.8, 0.8))
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.position = Vector2(-320, -30)
	_death_label.custom_minimum_size = Vector2(640, 40)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_overlay.add_child(_death_label)
	_build_debug_panel()

func _overlay(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_panel.position = Vector2(12, 150)
	_debug_panel.add_theme_stylebox_override("panel", _style_box(Color(0.04, 0.01, 0.03, 0.92), Color(0.9, 0.35, 0.4, 0.95)))
	_debug_panel.visible = false
	add_child(_debug_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_debug_panel.add_child(box)
	box.add_child(_make_label("🛠 Меню отладки", 22, Color(1, 0.8, 0.7)))
	box.add_child(_make_label("Состояние НЗТБНЗ:", 17, Color(0.9, 0.8, 0.9)))
	var states_row := HBoxContainer.new()
	box.add_child(states_row)
	for sname: String in ["Обычное", "Всасывание", "Летающее"]:
		var b := _make_button(sname, 17)
		b.custom_minimum_size = Vector2(128, 48)
		var captured: String = sname
		b.pressed.connect(func() -> void:
			if _castle != null:
				_castle.force_state_by_name(captured))
		states_row.add_child(b)
	box.add_child(_make_label("Ветер Богини Ветра (3 мин, направление случайно):", 17, Color(0.8, 0.88, 1.0)))
	var wind_names: Array[String] = ["Штиль", "Слабый ветер", "Свежий ветер", "Очень крепкий ветер", "Ураган"]
	var wind_kmh: Array[String] = ["1 км/ч", "15 км/ч", "35 км/ч", "70 км/ч", "120 км/ч 🌀"]
	for i: int in wind_names.size():
		var b := _make_button("💨 " + wind_names[i] + " · " + wind_kmh[i], 17)
		var captured_w: String = wind_names[i]
		b.pressed.connect(func() -> void: WindManager.set_wind(captured_w))
		box.add_child(b)
	var btn_tp := _make_button("🌀 Телепорт к замку", 18)
	btn_tp.pressed.connect(_teleport_to_castle)
	box.add_child(btn_tp)
	_btn_sleep_skip = _make_button("⏩ Пропустить сон", 18)
	_btn_sleep_skip.pressed.connect(func() -> void:
		GameState.sleep_skip_requested = true
		if _castle != null:
			_castle.skip_sleep())
	box.add_child(_btn_sleep_skip)
	var btn_time := _make_button("🕐 Время +1 час", 18)
	btn_time.pressed.connect(func() -> void: GameState.advance_game_minutes(60.0))
	box.add_child(btn_time)
	_debug_info = _make_label("", 15, Color(0.75, 0.8, 0.75))
	box.add_child(_debug_info)
	var btn_close := _make_button("✖ Закрыть", 18)
	btn_close.pressed.connect(func() -> void: _debug_panel.visible = false)
	box.add_child(btn_close)

func _teleport_to_castle() -> void:
	if _castle == null or _player == null:
		return
	var gate: Vector3 = _castle.gate_global_pos()
	var out_dir: Vector3 = (_castle as Node3D).global_transform.basis * Vector3(0, 0, 1)
	var target: Vector3 = gate + out_dir * 9.0
	if GameState.world != null:
		target.y = maxf(target.y, float(GameState.world.call("get_height_at", target.x, target.z)) + 1.0)
	_player.teleport_to(target)
	show_toast("Телепортация к НЗТБНЗ")

func toggle_debug_panel() -> void:
	_debug_panel.visible = not _debug_panel.visible

func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	_toast_timer = 3.6

func _on_wind_changed(preset_name: String, kmh: float) -> void:
	_wind_label.text = "💨 %s, %d км/ч (с %s)" % [preset_name, int(kmh), WindManager.compass_string()]
	if preset_name == "Ураган":
		show_toast("🌀 Ураган! В 250 м появилась Воровка тропического циклона…")

func _on_sleep_started() -> void:
	pass # оверлей анимируется в _process по GameState.sleeping

func _on_sleep_finished() -> void:
	pass

func _on_player_died(_pos: Vector3) -> void:
	pass

func _on_player_respawned() -> void:
	show_toast("Юмик воскрес! Страха перед проклятыми вещами у него нет")

var _death_fade: float = 0.0

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast_label.modulate.a = clampf(_toast_timer / 1.2, 0.0, 1.0)
	# Часы и статус
	var night: bool = GameState.is_night()
	_clock_label.text = ("🌙 " if night else "☀️ ") + GameState.clock_string() + " · день " + str(GameState.day_count)
	if _castle != null:
		_state_label.text = "НЗТБНЗ: " + _castle.get_state_name()
		_euphoria_box.visible = bool(_castle.get("nyashing_active")) and not GameState.sleeping
		if _euphoria_box.visible:
			_euphoria_bar.value = _castle.nyash_progress_01() * 100.0
	# Кнопки по состоянию игрока
	if _player != null:
		var p_mode: int = int(_player.get("mode"))
		_btn_jump.text = "🦘 Припрыжку!" if _player.is_running_now() else ("🧍 Встать" if p_mode == 2 or p_mode == 4 or p_mode == 7 else "🦘 Прыжок")
		_btn_lie.text = "🧍 Встать" if p_mode == 2 else "🛏 Лечь"
		_btn_crawl.text = "🧍 Встать" if p_mode == 1 else "🐾 На четвереньки"
		_btn_climb.text = "⬇ Отцепиться" if p_mode == 3 else "🧗 Вскарабкаться"
		_btn_squeeze.text = "🤗 Тискать крепче!" if bool(_player.get("squeezing")) else "🤗 Тискать"
		_btn_hem.visible = bool(_player.get("maid_outfit"))
		_btn_hem.text = "👗 Опустить подол" if bool(_player.get("hem_up")) else "👗 Задрать подол"
		_btn_outfit.visible = _castle != null and _castle.is_near_wardrobe((_player as Node3D).global_position)
		_btn_outfit.text = "🎀 Снять платье" if bool(_player.get("maid_outfit")) else "🎀 Надеть платье горничной"
		_btn_hold.modulate = Color(1.4, 0.8, 0.85) if bool(_player.get("hold_on")) else Color.WHITE
		_btn_hold.text = "🤲 Не отпускай меня ♥" if bool(_player.get("hold_on")) else "🤲 Не отпускай меня"
		_weak_overlay.color.a = lerpf(_weak_overlay.color.a, 0.16 if bool(_player.get("weakened")) else 0.0, delta * 2.0)
		# Гибель
		var dead: bool = p_mode == 8
		_death_fade = clampf(_death_fade + (delta if dead else -delta * 1.5), 0.0, 1.0)
		_death_overlay.color.a = _death_fade * 0.55
		_death_label.visible = dead
		if _debug_panel.visible:
			var pos: Vector3 = (_player as Node3D).global_position
			_debug_info.text = "FPS: %d · поз. (%.0f, %.0f, %.0f)\nрежим: %d · ветер: %s %.0f км/ч\nост. ветра: %.0f с" % [
				Engine.get_frames_per_second(), pos.x, pos.y, pos.z, p_mode,
				WindManager.current_preset, WindManager.current_kmh, maxf(WindManager.remaining, 0.0)]
	# Сон: затемнение + розовая дымка сна поверх катсцены
	var sleep_target: float = 0.62 if GameState.sleeping else 0.0
	_sleep_overlay.color.a = lerpf(_sleep_overlay.color.a, sleep_target, delta * 1.6)
	_dream_overlay.color.a = lerpf(_dream_overlay.color.a, 0.10 + 0.05 * sin(Time.get_ticks_msec() * 0.001) if GameState.sleeping else 0.0, delta * 1.6)
	_btn_sleep_skip.visible = GameState.sleeping
