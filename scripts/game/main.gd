extends Node3D
## Lunar Tilt - main gameplay scene.

const WorldScript := preload("res://scripts/game/table_world.gd")

var world: TableWorld
var cam: Camera3D

# Match state
var active_color := "red"
var hand_counts := {"red": 12, "black": 12}
var scores := {"red": 0, "black": 0}
var active_ball: SCBBall = null
var pending_resolve := false

# Input
var guide_layer: CanvasLayer
var guide_line: Node3D
var dragging := false
var drag_start := Vector2.ZERO

# HUD
var label_red: Label
var label_black: Label
var label_turn: Label
var label_msg: Label
var hud_root: Control


func _ready() -> void:
	world = WorldScript.new()
	world.name = "TableWorld"
	add_child(world)
	world.ball_captured.connect(_on_ball_captured)
	world.ball_guttered.connect(_on_ball_guttered)
	_build_env()
	_build_lights()
	_build_camera()
	_build_guide()
	_build_hud()
	for i in world.BALLS_PER_COLOR:
		world.spawn_hand_ball("red")
		world.spawn_hand_ball("black")
	_give_active_ball()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not dragging and active_ball != null:
			dragging = true
			drag_start = event.position
		elif dragging:
			dragging = false
			guide_line.visible = false
			_launch(event.position)
	elif event is InputEventMouseMotion and dragging:
		_update_guide(event.position)


func _launch(screen_pos: Vector2) -> void:
	if active_ball == null:
		return
	var d := screen_pos - drag_start
	if d.length() < 12.0:
		_msg("Too soft - keep the ball")
		return
	# Flick: dragging down-screen (toward player) launches forward (+Z).
	var vel := Vector3(d.x * 0.0042, 0.0, -d.y * 0.0042)
	vel = vel.normalized() * clampf(d.length() * Settings.power_scale, 0.6, 3.4)
	active_ball.linear_velocity = vel
	active_ball = null
	pending_resolve = true


var _resolve_timer := 0.0
const _RESOLVE_DELAY := 4.5


# Capture mode: `-- --capture` (non-headless) renders {n} frames, saves a
# screenshot to res://artifacts/frame_capture.png, then quits. Used as a
# visual regression gate since headless runs never render a frame.
var capture_mode := "--capture" in OS.get_cmdline_user_args()
var _capture_frames := 0
const _CAPTURE_AFTER := 210


func _process(delta: float) -> void:
	if capture_mode:
		_capture_frames += 1
		if _capture_frames == _CAPTURE_AFTER:
			var img := get_viewport().get_texture().get_image()
			var err := img.save_png("res://artifacts/frame_capture.png")
			print("CAPTURE_SAVE_ERR=", err)
			get_tree().quit()
		return
	if pending_resolve and active_ball == null:
		_resolve_timer += delta
		if _resolve_timer >= _RESOLVE_DELAY:
			_resolve_timer = 0.0
			pending_resolve = false
			_resolve_shot(NOT_SCORED)


## Shot outcome kinds for _resolve_shot.
const NOT_SCORED := 0
const SCORED_SWITCH := 1


func _resolve_shot(kind: int, scored_for := "") -> void:
	if kind == NOT_SCORED:
		_msg("Miss - turn passes")
		_pass_turn()
	else:
		_msg("%s knocks in opponent ball - they score!" % _color_name(active_color))
		scores[scored_for] += 2
		_update_hud()
		_pass_turn()


func _pass_turn() -> void:
	active_color = "black" if active_color == "red" else "red"
	_finish_shot()
	_give_active_ball()


func _finish_shot() -> void:
	if active_ball != null:
		active_ball.freeze = true
		active_ball = null
	pending_resolve = false
	_resolve_timer = 0.0
	_update_hud()


func _give_active_ball() -> void:
	if hand_counts[active_color] <= 0:
		_msg("%s has no balls left" % _color_name(active_color))
		active_color = "black" if active_color == "red" else "red"
	if hand_counts[active_color] <= 0:
		_msg("Match over - highest score wins")
		return
	hand_counts[active_color] -= 1
	active_ball = world.take_hand_ball(active_color)
	if active_ball == null:
		_msg("No ball in tray")
		return
	_update_hud()


func _on_ball_captured(ball: SCBBall, slot_index: int) -> void:
	if ball.color == active_color:
		pending_resolve = false
		_resolve_timer = 0.0
		scores[active_color] += _score_slot(slot_index)
		_update_hud()
		_msg("+%d - keep shooting" % _score_slot(slot_index))
		_give_active_ball()
	else:
		_resolve_shot(SCORED_SWITCH, ball.color)


func _on_ball_guttered(_ball: SCBBall) -> void:
	_msg("Gutter - ball lost, turn passes")
	pending_resolve = false
	_resolve_timer = 0.0
	_pass_turn()


func _score_slot(slot_index: int) -> int:
	var sd: Dictionary = world.slot_at(slot_index)
	return [1, 2, 5][sd["pos"]]


func _color_name(c: String) -> String:
	return "Red" if c == "red" else "Black"


# ---------------------------------------------------------------- visuals

## Broadcast-lounge ambiance: soft dark studio backdrop with warm horizon,
## plus ambient light sourced from the sky so unlit faces still read clearly.
func _build_env() -> void:
	var env_n := WorldEnvironment.new()
	env_n.name = "Environment"
	var wenv := Environment.new()
	wenv.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.10, 0.11, 0.15)
	psky.sky_horizon_color = Color(0.42, 0.36, 0.30)
	psky.ground_bottom_color = Color(0.07, 0.07, 0.09)
	psky.ground_horizon_color = Color(0.34, 0.30, 0.27)
	sky.sky_material = psky
	wenv.sky = sky
	wenv.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	wenv.ambient_light_energy = 0.9
	wenv.ambient_light_color = Color(1.0, 0.95, 0.88)
	env_n.environment = wenv
	add_child(env_n)


## Key light simulating a studio fixture above the table + a cool fill to
## lift shadowed ball faces (foundation for the room-lighting cosmetics).
func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.7
	sun.rotation_degrees = Vector3(-58.0, 24.0, 0.0)
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(1.25, 0.7, -0.55)
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.light_energy = 0.4
	fill.omni_range = 6.0
	add_child(fill)


## Camera frames the whole slope like the broadcast edit: positioned in front
## of the player end and looking at the table center (yaw/pitch derived from
## the look_target, so it can never aim away from the board again).
func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.25, 1.6, -0.95)
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 60.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.02, 1.02), Vector3.UP)


func _build_guide() -> void:
	guide_line = Node3D.new()
	guide_line.name = "Guide"
	guide_line.visible = false
	add_child(guide_line)


func _update_guide(screen_pos: Vector2) -> void:
	guide_line.visible = dragging
	if not dragging or active_ball == null:
		return
	var d := screen_pos - drag_start
	if d.length() < 8.0:
		return
	for child in guide_line.get_children():
		child.queue_free()
	var vel := Vector3(d.x * 0.0042, 0.0, -d.y * 0.0042)
	vel = vel.normalized() * clampf(d.length() * Settings.power_scale, 0.6, 3.4)
	# Analytic stop distance: v^2 / (2 * a), a = g(sin t + mu cos t) ~= 0.97
	var decel := 0.97
	var stop_dist := (vel.length() * vel.length()) / (2.0 * decel)
	var start: Vector3 = active_ball.position
	var stop: Vector3 = start + Vector3(vel.x, 0.0, vel.z).normalized() * minf(stop_dist, 2.4)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(start)
	im.surface_add_vertex(stop)
	im.surface_end()
	var line_mesh := MeshInstance3D.new()
	line_mesh.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mesh.material_override = mat
	guide_line.add_child(line_mesh)
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.03
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(1.0, 0.95, 0.6, 0.9)
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.mesh = sm
	dot.material_override = dmat
	dot.position = stop
	guide_line.add_child(dot)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	label_red = _add_label("Red 0", Color(1, 0.5, 0.4), Vector2(16, 16), style)
	label_black = _add_label("Black 0", Color(0.9, 0.92, 1.0), Vector2(16, 66), style)
	label_turn = _add_label("Turn: Red", Color.WHITE, Vector2(16, 116), style)
	label_msg = _add_label("Aim: drag from the tray ball, then release", Color(1, 0.95, 0.7), Vector2(16, 180), null)
	label_msg.custom_minimum_size = Vector2(560, 0)
	_update_hud()


func _add_label(text: String, color: Color, pos: Vector2, style: StyleBoxFlat) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 26)
	if style != null:
		l.add_theme_stylebox_override("normal", style)
	l.position = pos
	l.size = Vector2(420, 44)
	hud_root.add_child(l)
	return l


func _update_hud() -> void:
	if label_red == null or not is_inside_tree():
		return
	label_red.text = "Red  %d" % scores["red"]
	label_black.text = "Black  %d" % scores["black"]
	label_turn.text = "Turn: %s  |  In hand: %d" % [_color_name(active_color), hand_counts[active_color]]
	label_turn.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if active_color == "red" else Color(0.9, 0.92, 1.0))


func _msg(t: String) -> void:
	if label_msg != null:
		label_msg.text = t
		label_msg.reset_size()