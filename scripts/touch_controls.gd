class_name TouchControls
extends Control
## Сенсорный слой на весь экран (под кнопками HUD):
## левая половина — плавающий виртуальный джойстик: в пределах круга шаг,
## за пределами — бег. Правая половина — свайп обзора камерой.
## Мышь поддерживается для отладки на ПК (левая кнопка).

signal move_input(value: Vector2, running: bool)
signal camera_delta(delta_px: Vector2)

const STICK_RADIUS: float = 95.0

var _stick_active: bool = false
var _stick_id: int = -999
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _cam_id: int = -999
var _mouse_id: int = 424242

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP

func _is_left_side(pos: Vector2) -> bool:
	return pos.x < size.x * 0.48

func _begin_touch(id: int, pos: Vector2) -> void:
	if _is_left_side(pos) and not _stick_active:
		_stick_active = true
		_stick_id = id
		_stick_origin = pos
		_stick_pos = pos
		queue_redraw()
	elif not _is_left_side(pos) and _cam_id == -999:
		_cam_id = id

func _drag_touch(id: int, pos: Vector2, relative: Vector2) -> void:
	if _stick_active and id == _stick_id:
		_stick_pos = pos
		var offset: Vector2 = _stick_pos - _stick_origin
		var value: Vector2 = offset / STICK_RADIUS
		if value.length() > 1.0:
			value = value.normalized()
		move_input.emit(value, offset.length() > STICK_RADIUS)
		queue_redraw()
	elif id == _cam_id:
		camera_delta.emit(relative)

func _end_touch(id: int) -> void:
	if _stick_active and id == _stick_id:
		_stick_active = false
		_stick_id = -999
		move_input.emit(Vector2.ZERO, false)
		queue_redraw()
	if id == _cam_id:
		_cam_id = -999

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_begin_touch(t.index, t.position)
		else:
			_end_touch(t.index)
		accept_event()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag_touch(d.index, d.position, d.relative)
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_touch(_mouse_id, mb.position)
			else:
				_end_touch(_mouse_id)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag_touch(_mouse_id, mm.position, mm.relative)

func _draw() -> void:
	if not _stick_active:
		# Призрачная подсказка зоны джойстика
		var hint_pos := Vector2(size.x * 0.16, size.y * 0.72)
		draw_circle(hint_pos, STICK_RADIUS, Color(1, 1, 1, 0.05))
		draw_arc(hint_pos, STICK_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.14), 2.5)
		return
	draw_circle(_stick_origin, STICK_RADIUS, Color(0.1, 0, 0.05, 0.35))
	draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 0.45, 0.5, 0.6), 3.0)
	var knob: Vector2 = _stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS)
	draw_circle(knob, 38.0, Color(0.85, 0.15, 0.2, 0.75))
	draw_arc(knob, 38.0, 0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
