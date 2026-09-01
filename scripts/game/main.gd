extends Node3D
## Lunar Tilt - main gameplay scene.

const WorldScript := preload("res://scripts/game/table_world.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")

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

# Camera framing (v2 aspect-aware rig)
const CAM_FOV := 62.0
const LOOK_TARGET := Vector3(0.0, 0.02, 0.98)
var _camera_base_fov := CAM_FOV

# Broadcast juice state
var _vignette: ColorRect
var _msg_tween: Tween = null
var _fov_punch := 0.0


func _ready() -> void:
	world = WorldScript.new()
	world.name = "TableWorld"
	add_child(world)
	world.ball_captured.connect(_on_ball_captured)
	world.ball_guttered.connect(_on_ball_guttered)
	world.ball_returned.connect(_on_ball_returned)
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
	if _fov_punch > 0.0:
		_fov_punch = maxf(0.0, _fov_punch - delta * 6.0)
		if cam != null:
			cam.fov = _camera_base_fov + _fov_punch
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


func _on_ball_returned(ball: SCBBall) -> void:
	## Real-sport rule: a ball that rolls back off the player end returns to the
	## shooter's rack instead of vanishing. Restore the hand count and, if it is
	## the active color's ball, immediately hand it back for another flick.
	world.reinsert_hand_ball(ball)
	hand_counts[ball.color] += 1
	pending_resolve = false
	_resolve_timer = 0.0
	_msg("%s ball back in hand" % _color_name(ball.color))
	_update_hud()
	if ball.color == active_color:
		_give_active_ball()


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
	psky.sky_horizon_color = Color(0.50, 0.44, 0.40)
	psky.ground_bottom_color = Color(0.07, 0.07, 0.09)
	psky.ground_horizon_color = Color(0.44, 0.38, 0.33)
	sky.sky_material = psky
	wenv.sky = sky
	wenv.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	wenv.ambient_light_energy = 1.15
	wenv.ambient_light_color = Color(1.0, 0.95, 0.88)
	env_n.environment = wenv
	add_child(env_n)
	# Broadcast-grade post + stage floor (v2): ACES tonemap, subtle glow,
	# and a dark floor so the table reads as furniture on a set, not void.
	wenv.tonemap_mode = Environment.TONE_MAPPER_ACES
	wenv.glow_enabled = true
	wenv.glow_intensity = 0.30
	wenv.glow_bloom = 0.08
	wenv.glow_hdr_threshold = 0.9
	var floor := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(14.0, 14.0)
	floor.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.020, 0.022, 0.026)
	fmat.roughness = 0.98
	floor.material_override = fmat
	floor.position = Vector3(0.0, -0.21, 1.0)
	add_child(floor)


## Key light simulating a studio fixture above the table + a cool fill to
## lift shadowed ball faces (foundation for the room-lighting cosmetics).
func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 2.1
	sun.rotation_degrees = Vector3(-58.0, 24.0, 0.0)
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(1.25, 0.7, -0.55)
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.light_energy = 0.55
	fill.omni_range = 6.0
	add_child(fill)
	# Rim light behind the far end - lifts the oak edge off the dark backdrop.
	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.position = Vector3(0.0, 0.45, 2.5)
	rim.light_color = Color(1.0, 0.92, 0.8)
	rim.light_energy = 0.55
	rim.omni_range = 3.2
	add_child(rim)


## Camera frames the whole slope like the broadcast edit: positioned in front
## of the player end and looking at the table center (yaw/pitch derived from
## the look_target, so it can never aim away from the board again).
func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.near = 0.05
	cam.far = 60.0
	add_child(cam)
	_reframe_camera()


## Aspect-aware framing (v2): binary-search the closest camera distance so the
## whole frame (racks + tray + table + gutter) fits the device aspect exactly.
func _reframe_camera() -> void:
	if cam == null:
		return
	var vp := get_viewport()
	var vr := vp.get_visible_rect().size
	var aspect := float(vr.x) / maxf(vr.y, 1.0)
	_camera_base_fov = CAM_FOV
	var pitch := CameraRigScript.pitch_for_aspect(aspect)
	var pts: Array = TableWorld.frame_points()
	var dist := CameraRigScript.fit_distance(pts, CAM_FOV, aspect, pitch, LOOK_TARGET)
	cam.position = CameraRigScript.cam_pos(pitch, dist, LOOK_TARGET)
	cam.look_at(LOOK_TARGET, Vector3.UP)
	cam.fov = _camera_base_fov
	print("CAM aspect=", aspect, " pitch=", pitch, " dist=", dist)


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

	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.02, 0.02, 0.03, 0.66)
	pill.set_corner_radius_all(14)
	pill.content_margin_left = 14
	pill.content_margin_right = 14
	pill.content_margin_top = 7
	pill.content_margin_bottom = 7

	label_red = _add_label("Red 0", Color(1.0, 0.45, 0.35), Vector2(14, 16), pill)
	label_red.set_anchors_preset(Control.PRESET_TOP_LEFT)

	label_black = _add_label("Black 0", Color(0.85, 0.90, 1.0), Vector2(-150, 16), pill)
	# Right-aligned via the TOP_RIGHT anchor; position.x is measured from right edge.
	label_black.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label_black.size = Vector2(120, 44)

	label_turn = _add_label("Turn: Red", Color.WHITE, Vector2(-130, 16), pill)
	label_turn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label_turn.position = Vector2(-130, 16)
	label_turn.size = Vector2(260, 44)

	label_msg = _add_label("Aim: drag from the ball, release to flick", Color(1.0, 0.95, 0.75), Vector2(-300, 118), null)
	label_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label_msg.position = Vector2(-300, 118)
	label_msg.size = Vector2(600, 0)
	label_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(1.0, 0.1, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_vignette)
	_update_hud()


func _add_label(text: String, color: Color, pos: Vector2, style: StyleBoxFlat) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 26)
	if style != null:
		l.add_theme_stylebox_override("normal", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_root.add_child(l)
	return l


func _update_hud() -> void:
	if not is_inside_tree():
		return
	label_red.text = "Red  %d" % scores["red"]
	label_black.text = "Black  %d" % scores["black"]
	label_turn.text = "Turn: %s  |  In hand: %d" % [_color_name(active_color), hand_counts[active_color]]
	label_turn.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if active_color == "red" else Color(0.85, 0.9, 1.0))


func _msg(t: String) -> void:
	if label_msg == null:
		return
	label_msg.text = t
	label_msg.modulate.a = 1.0
	if _msg_tween != null:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.6)
	_msg_tween.tween_property(label_msg, "modulate:a", 0.45, 0.5)


# ------------------------------------------------------------- broadcast juice --

func _score_juice(world_pos: Vector3, pts: int) -> void:
	_fov_punch = 2.2
	_flash(Color(1.0, 0.95, 0.85), 0.14)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(15)
	if world_pos != Vector3.ZERO and cam != null:
		var sp := cam.unproject_position(world_pos)
		var t := ("+%d" % pts)
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 44)
		l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.position = sp
		l.size = Vector2(120, 50)
		hud_root.add_child(l)
		var tw := create_tween()
		tw.tween_property(l, "position:y", sp.y - 72.0, 0.8).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
		tw.finished.connect(l.queue_free)


func _gutter_juice() -> void:
	_fov_punch = 1.5
	_flash(Color(1.0, 0.08, 0.05), 0.22)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(45)


func _flash(v: Color, a: float) -> void:
	if _vignette == null:
		return
	_vignette.color = Color(v.r, v.g, v.b, a)
	var tw := create_tween()
	tw.tween_property(_vignette, "color:a", 0.0, 0.45)