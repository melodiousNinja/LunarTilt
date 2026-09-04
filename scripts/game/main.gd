extends Node3D
## Lunar Tilt - main gameplay scene (V3).
##
## Drag-back SLINGSHOT: grab the ball and pull DOWN-screen (toward the tray)
## to charge; release to launch it up the 4.99-degree slope. While aiming you
## see a dotted ShotMath trajectory + a landing marker, plus a power meter.
## Scoring uses the physical world's settle-detection (a ball that settles in
## a pocket is caught; a fast ball skims past). The sport's Returned-Ball rule
## is honoured: a ball that rolls back down lands in the tray and returns to
## the shooter's rack so the turn continues.

const WorldScript := preload("res://scripts/game/table_world.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")

var world: TableWorld
var cam: Camera3D

# Match state (scene-side; MatchController drives the AI / rules tests)
var active_color := "red"
var hand_counts := {"red": 12, "black": 12}
var scores := {"red": 0, "black": 0}
var active_ball: SCBBall = null
var pending_resolve := false
var _resolve_elapsed := 0.0
const _RESOLVE_DELAY :=(9.0 * 0.5)

# Slingshot input
var aiming := false
var aim_start := Vector2.ZERO
var guide_node: Node3D
var power_bar: ProgressBar

# HUD
var label_red: Label
var label_black: Label
var label_turn: Label
var label_msg: Label
var hud_root: Control

# Camera + broadcast juice
const CAM_FOV := 62.0
const LOOK_TARGET := Vector3(0.0, 0.02, 0.98)
var _camera_base_fov := CAM_FOV
var _vignette: ColorRect
var _msg_tween: Tween = null
var _fov_punch := 0.0

## Slingshot conversion: screen px of pull -> m/s of launch velocity.
const SLING_K := 0.0035
const MIN_POWER := 0.8
const GUTTER_POWER_LIMIT := 3.3


func _ready() -> void:
	world = WorldScript.new()
	world.name = "TableWorld"
	add_child(world)
	world.ball_scored.connect(_on_ball_scored)
	world.ball_guttered.connect(_on_ball_guttered)
	world.ball_returned.connect(_on_ball_returned)
	world.ball_displaced.connect(_on_ball_displaced)
	world.ball_grouped.connect(_on_ball_grouped)
	_build_env()
	_build_lights()
	_build_camera()
	_build_guide()
	_build_hud()
	for i in world.BALLS_PER_COLOR:
		world.spawn_hand_ball("red")
		world.spawn_hand_ball("black")
	_give_active_ball()
	print("SCB_MAIN_VERSION=v6-feel-20260904 SLING_K=%s serve=%s" % [
		SLING_K, (active_ball.position if active_ball != null else Vector3.INF)])


func _unhandled_input(event: InputEvent) -> void:
	var on_mobile := OS.has_feature("mobile")
	if on_mobile and event is InputEventScreenTouch:
		if event.pressed and not aiming and active_ball != null:
			if _near_ball(event.position):
				_start_aim(event.position)
			else:
				_repositioning = true
				_slide_marker(event.position)
		elif aiming and not event.pressed:
			_release_shot(event.position)
		elif _repositioning and not event.pressed:
			_repositioning = false
	elif on_mobile and event is InputEventScreenDrag:
		if aiming:
			_update_guide(event.position)
		elif _repositioning:
			_slide_marker(event.position)
	elif not on_mobile and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not aiming and active_ball != null:
			if _near_ball(event.position):
				_start_aim(event.position)
			else:
				_repositioning = true
				_slide_marker(event.position)
		elif aiming:
			_release_shot(event.position)
		elif _repositioning:
			_repositioning = false
	elif not on_mobile and event is InputEventMouseMotion:
		if aiming:
			_update_guide(event.position)
		elif _repositioning:
			_slide_marker(event.position)


func _start_aim(pos: Vector2) -> void:
	aiming = true
	aim_start = pos
	_update_power_meter(0.0)
	print("SCB aim_start=%s ball=%s sleeping=%s" % [pos, active_ball != null,
		active_ball != null and active_ball.sleeping])


func _release_shot(screen_pos: Vector2) -> void:
	if not aiming:
		return
	aiming = false
	guide_node.visible = false
	power_bar.visible = false
	if active_ball == null:
		print("SCB release: NO ACTIVE BALL - abort")
		return
	var pull := aim_start - screen_pos
	var len := pull.length()
	if len < 14.0:
		_msg("Too soft - pull the ball further back")
		print("SCB release TOO SOFT len=%.1f" % len)
		return
	active_ball.is_active = false
	_resolve_elapsed = 0.0
	var power := clampf(len * SLING_K, MIN_POWER, GUTTER_POWER_LIMIT)
	# Ball ALWAYS launches up-table (+Z). Drag distance = power; horizontal
	# drag = aim angle. Pull down OR flick up both fire up the slope.
	var lateral := clampf(pull.x / maxf(len, 0.001), -0.85, 0.85)
	var angle := asin(lateral)
	var dir := Vector3(sin(angle), 0.0, cos(angle)).normalized()
	# LIVE-PROVEN (2026-09 device): the served ball is a FROZEN MARKER (a live
	# ball creeps back down the slope while the player aims and falls into the
	# void). The shot replaces the marker with a FRESH live ball at the exact
	# same transform, velocity on its first frame - the pattern test A proves.
	print("SCB release len=%.0f power=%.2f angle=%.2f marker=%s" % [
		len, power, angle, active_ball.freeze])
	var launched := world.launch_hand_ball(active_ball, dir * power)
	if launched == null:
		print("SCB LAUNCH FAILED - marker invalid")
		active_ball = null
		return
	active_ball = launched
	print("SCB LAUNCH v=%s pos=%s" % [active_ball.linear_velocity, active_ball.position])
	pending_resolve = true
	_fov_punch = 0.8


func _update_guide(screen_pos: Vector2) -> void:
	if not aiming or active_ball == null:
		return
	var pull := aim_start - screen_pos
	var len := pull.length()
	if len < 8.0:
		return
	var power := clampf(len * SLING_K, MIN_POWER, GUTTER_POWER_LIMIT)
	_update_power_meter(power)
	# Same launch math as _release_shot: direction toward the target.
	var lateral := clampf(pull.x / maxf(len, 0.001), -0.85, 0.85)
	var angle := asin(lateral)
	_draw_trajectory(active_ball.position, angle, power)


# ------------------------------------------------- slide-to-reposition (v6) --
## 2026-09 live feedback: players could not move the ball left/right before
## shooting. Now a touch-drag that starts OFF the ball slides the served
## marker along the launch line; a touch ON the ball starts the slingshot aim.
var _repositioning := false
const _BALL_GRAB_PX := 150.0


## Slide-to-aim (live feedback): touching the felt instead of the ball slides
## the serve marker left/right along the launch line, so the player sets the
## shot origin before pulling back. Clamped to the felt width (±0.52).
func _slide_marker(screen_pos: Vector2) -> void:
	if active_ball == null or not is_instance_valid(active_ball) or cam == null:
		return
	var pl := Plane(Vector3.UP, active_ball.position)
	var hit = pl.intersects_ray(cam.project_ray_origin(screen_pos),
		cam.project_ray_normal(screen_pos))
	if hit != null:
		var p: Vector3 = hit
		var nx := clampf(p.x, -0.52, 0.52)
		active_ball.position = Vector3(nx,
			world.ball_rest_y(nx, world.LAUNCH_Z), world.LAUNCH_Z)
		print("SCB slide marker x=%.2f" % nx)


func _near_ball(screen_pos: Vector2) -> bool:
	if active_ball == null or cam == null:
		return false
	if not is_instance_valid(active_ball):
		return false
	return screen_pos.distance_to(cam.unproject_position(active_ball.position)) <= _BALL_GRAB_PX


## Safe sound hook: the Sfx autoload is absent in headless test runs, so every
## caller goes through this guard instead of dereferencing /root/Sfx directly.
func _sfx(name: String, pitch := 1.0) -> void:
	var snd := get_node_or_null("/root/Sfx")
	if snd != null:
		snd.play(name, pitch)


func _draw_trajectory(start: Vector3, angle: float, power: float) -> void:
	for child in guide_node.get_children():
		child.queue_free()
	var z := clampf(ShotMath.landing_z(power, angle), ShotMath.PLAY_LINE_Z, ShotMath.FAR_GUTTER_Z)
	var x := ShotMath.lateral_drift(power, angle)
	x = clampf(x, -0.42, 0.42)
	var land := Vector3(x, world.surface_y_at(x, z) + 0.004, z)
	# 2026-09 live feedback: players want a SMALL aim line, not a full-path
	# arc. Three subtle segments straight out of the ball show direction; the
	# landing ring keeps showing where the shot settles.
	var dir := Vector3(sin(angle), 0.0, cos(angle)).normalized()
	const LINE_LEN := 0.24
	const SEG := 3
	var prev: Vector3 = start
	for i in range(1, SEG + 1):
		var p := start + dir * (LINE_LEN * float(i) / float(SEG))
		p.y = world.surface_y_at(p.x, p.z) + 0.004
		_add_guide_segment(prev, p)
		prev = p
	_add_landing_marker(land)


func _add_guide_segment(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.55, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	guide_node.add_child(mi)


func _add_landing_marker(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.042
	sm.height = 0.022
	sm.radial_segments = 20
	sm.rings = 8
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.15, 0.92)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 2.2
	mi.material_override = mat
	mi.position = pos
	guide_node.add_child(mi)


# ------------------------------------------------------------ shot outcome --

func _on_ball_scored(ball: SCBBall, band: int, keep_shooting: bool) -> void:
	var pts: int = [1, 2, 5][clampi(band, 0, 2)]
	print("SCB SCORED color=%s band=%d pts=%d keep=%s" % [
		ball.color, band, pts, keep_shooting])
	scores[ball.color] = int(scores[ball.color]) + pts
	_sfx("score")
	_update_hud()
	_score_juice(ball.position, pts)
	pending_resolve = false
	if keep_shooting and ball.color == active_color:
		_msg("+%d  GROUP! keep shooting" % pts)
		_give_active_ball()
	else:
		_msg("+%d  %s claims a pocket" % [pts, _color_name(ball.color)])
		_pass_turn()


## Official grouping: a grouped ball was knocked back to its owner's rack.
func _on_ball_displaced(ball: SCBBall) -> void:
	print("SCB DISPLACED color=%s" % ball.color)
	_sfx("pop", 1.2)
	hand_counts[ball.color] = int(hand_counts[ball.color]) + 1
	_update_hud()


## Official grouping: the shot ball could not claim a pocket and now walls
## one instead - it stays on the table as an obstacle, turn passes.
func _on_ball_grouped(ball: SCBBall) -> void:
	print("SCB GROUPED color=%s" % ball.color)
	_msg("%s ball walls a pocket - turn passes" % _color_name(ball.color))
	_sfx("block")
	pending_resolve = false
	_pass_turn()


func _on_ball_guttered(_ball: SCBBall) -> void:
	print("SCB GUTTERED")
	_msg("%s lost the ball down the gutter" % _color_name(active_color))
	_sfx("gutter")
	_gutter_juice()
	pending_resolve = false
	_pass_turn()


func _on_ball_returned(ball: SCBBall) -> void:
	print("SCB RETURNED color=%s" % ball.color)
	## Real-sport rule: the ball rolls back into the tray and is handed back
	## to the shooter, so the turn is NOT spent.
	world.reinsert_hand_ball(ball)
	_sfx("thud", 0.9)
	hand_counts[ball.color] = int(hand_counts[ball.color]) + 1
	pending_resolve = false
	_msg("%s ball back in hand" % _color_name(ball.color))
	_update_hud()
	if ball.color == active_color:
		_give_active_ball()


func _pass_turn() -> void:
	active_color = "black" if active_color == "red" else "red"
	_finish_shot()
	_give_active_ball()


func _finish_shot() -> void:
	if active_ball != null:
		active_ball.is_active = false
		active_ball.freeze = true
		active_ball = null
	pending_resolve = false
	_resolve_elapsed = 0.0
	_update_hud()


func _give_active_ball() -> void:
	if hand_counts[active_color] <= 0:
		active_color = "black" if active_color == "red" else "red"
	if hand_counts[active_color] <= 0:
		_match_over()
		return
	hand_counts[active_color] -= 1
	active_ball = world.take_hand_ball(active_color)
	if active_ball == null:
		_msg("No ball in rack")
		return
	active_ball.is_active = true
	_update_hud()


## Board as the RulesEngine expects it: [[pos0 slots], [pos1], [pos2]].
func _current_board() -> Array:
	var board := [[], [], []]
	for sd in world.slots:
		board[int(sd["band"])].append(sd["color"])
	return board


func _match_over() -> void:
	pending_resolve = false
	var res := RulesEngine.score_board(_current_board())
	scores["red"] = int(res["per_color"]["red"])
	scores["black"] = int(res["per_color"]["black"])
	_update_hud()
	var winner := "Draw"
	if scores["red"] > scores["black"]:
		winner = "Red"
	elif scores["black"] > scores["red"]:
		winner = "Black"
	_msg("GAME OVER  |  %s wins!" % winner)
	_flash(Color(1.0, 0.9, 0.5), 0.3)
	_fov_punch = 2.5


func _color_name(c: String) -> String:
	return "Red" if c == "red" else "Black"


# --------------------------------------------------------------- capture --

## Capture mode: `-- --capture` (non-headless) renders {n} frames, saves a
## screenshot to res://artifacts/frame_capture.png, then quits. Visual
## regression gate since headless runs never render a frame.
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
	if pending_resolve:
		_resolve_elapsed += delta
		# Flight telemetry: every ~0.5 s dump the live ball state to logcat so
		# on-device shot behavior is directly observable.
		if int(_resolve_elapsed * 2.0) != int((_resolve_elapsed - delta) * 2.0):
			var b: SCBBall = null
			if not world.live_balls.is_empty():
				b = world.live_balls.back() as SCBBall
			if b != null and is_instance_valid(b):
				print("SCB flight t=%.1f pos=%s v=%.2f sleeping=%s" % [_resolve_elapsed,
					(b as SCBBall).position, (b as SCBBall).linear_velocity.length(),
					(b as SCBBall).sleeping])
		if _resolve_elapsed >= _RESOLVE_DELAY:
			_resolve_elapsed = 0.0
			pending_resolve = false
			world.flush_live()
			_msg("Shot resolved - turn settles")


# ---------------------------------------------------------------- visuals --

func _build_env() -> void:
	var env_n := WorldEnvironment.new()
	env_n.name = "Environment"
	var wenv := Environment.new()
	wenv.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	# Broadcast-night stage: deep navy-black with a faint cool horizon glow so
	# the lit table is the only bright thing in frame (modern show look).
	psky.sky_top_color = Color(0.016, 0.018, 0.028)
	psky.sky_horizon_color = Color(0.10, 0.095, 0.105)
	psky.ground_bottom_color = Color(0.008, 0.008, 0.012)
	psky.ground_horizon_color = Color(0.075, 0.07, 0.08)
	sky.sky_material = psky
	wenv.sky = sky
	wenv.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	wenv.ambient_light_energy = 1.0
	wenv.ambient_light_color = Color(0.92, 0.95, 1.0)
	env_n.environment = wenv
	add_child(env_n)
	wenv.tonemap_mode = Environment.TONE_MAPPER_ACES
	wenv.tonemap_white = 6.0
	wenv.glow_enabled = true
	wenv.glow_intensity = 0.55
	wenv.glow_bloom = 0.12
	wenv.glow_hdr_threshold = 0.85
	# Light colour grade: a touch more contrast + saturation reads "modern
	# broadcast" instantly on mobile OLEDs.
	wenv.adjustment_enabled = true
	wenv.adjustment_contrast = 1.06
	wenv.adjustment_saturation = 1.12
	var floor := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(14.0, 14.0)
	floor.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.020, 0.022, 0.026)
	# Polished stage floor: picks up the table lights as soft reflections.
	fmat.roughness = 0.45
	fmat.metallic = 0.2
	floor.material_override = fmat
	floor.position = Vector3(0.0, -0.21, 1.0)
	add_child(floor)
	# One static reflection probe over the table - this is what makes the
	# marble, brass and lacquered balls look expensive.
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0.0, 0.7, 1.2)
	probe.size = Vector3(4.0, 2.2, 6.0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	add_child(probe)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 2.4
	sun.rotation_degrees = Vector3(-58.0, 24.0, 0.0)
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(1.25, 0.7, -0.55)
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.light_energy = 0.7
	fill.omni_range = 6.0
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.name = "RimLight"
	rim.position = Vector3(0.0, 0.45, 2.5)
	rim.light_color = Color(1.0, 0.92, 0.8)
	rim.light_energy = 0.55
	rim.omni_range = 3.2
	add_child(rim)


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


func _build_guide() -> void:
	guide_node = Node3D.new()
	guide_node.name = "Guide"
	guide_node.visible = false
	add_child(guide_node)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Safe-area insets (live feedback: the top-left score pill was cut off by
	# the camera notch on a 1080x2400 device). Physical safe-area pixels are
	# converted into the stretched HUD coordinate space; a 28 design-px floor
	# guards devices that report no cutout insets.
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var vp_size := hud_root.get_viewport_rect().size
	var kx := vp_size.x / maxf(float(win.x), 1.0)
	var ky := vp_size.y / maxf(float(win.y), 1.0)
	hud_root.offset_left = float(sa.position.x) * kx
	hud_root.offset_top = maxf(float(sa.position.y) * ky, 28.0)
	hud_root.offset_right = -float(win.x - sa.end.x) * kx
	hud_root.offset_bottom = -float(win.y - sa.end.y) * ky
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
	label_black.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label_black.size = Vector2(120, 44)

	label_turn = _add_label("Turn: Red", Color.WHITE, Vector2(-130, 16), pill)
	label_turn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label_turn.position = Vector2(-130, 16)
	label_turn.size = Vector2(260, 44)

	label_msg = _add_label("Pull the ball down and release to shoot", Color(1.0, 0.95, 0.75), Vector2(-300, 118), null)
	label_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label_msg.position = Vector2(-300, 118)
	label_msg.size = Vector2(600, 0)
	label_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_update_power_meter_label()
	hud_root.add_child(power_bar)

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


func _update_power_meter(power: float) -> void:
	if power_bar == null:
		return
	power_bar.visible = true
	power_bar.value = clampf(power, 0.0, GUTTER_POWER_LIMIT) / GUTTER_POWER_LIMIT * 100.0


func _build_power_meter() -> void:
	power_bar = ProgressBar.new()
	power_bar.name = "PowerBar"
	power_bar.show_percentage = false
	power_bar.min_value = 0.0
	power_bar.max_value = 100.0
	power_bar.value = 0.0
	power_bar.custom_minimum_size = Vector2(320, 20)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.02, 0.03, 0.72)
	bg.set_corner_radius_all(10)
	bg.set_border_width_all(2)
	bg.border_color = Color(0.9, 0.82, 0.45, 0.6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.96, 0.30, 0.12)
	fill.set_corner_radius_all(10)
	power_bar.add_theme_stylebox_override("background", bg)
	power_bar.add_theme_stylebox_override("fill", fill)
	power_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	power_bar.position = Vector2(-180, -76)
	power_bar.size = Vector2(360, 20)
	power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_bar.visible = false


func _update_power_meter_label() -> void:
	_build_power_meter()


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
		var l := Label.new()
		l.text = "+%d" % pts
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
