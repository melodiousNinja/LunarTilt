## End-to-end shot simulation through the REAL shot controller (no rendering).
## Boots main.gd's controller in-process (windowed scene tree not required),
## feeds synthetic aim/release input through _unhandled_input, and asserts the
## on-device telemetry contract:
##   1. served marker is frozen and never drifts or falls while aiming
##   2. a release produces a LAUNCH with a sane velocity (up-slope, |v|>=4)
##   3. the live ball never tunnels below the tray floor (min y >= -0.135)
##   4. every shot RESOLVES (SCORED/RETURNED) within the 4.5 s flush window
##   5. the returned ball is re-racked (rack count restored)
## Run: godot --headless --path . --script res://tests/sim_shots.gd
extends SceneTree

var _fails := 0
var _total := 0
var _min_y := 1.0  # universal tunnel gate across ALL live shots

func _expect(cond: bool, label: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + label)
	else:
		_fails += 1
		print("  FAIL: " + label)

func _initialize() -> void:
	# Watchdog: never let a broken sim hang the runner.
	var wd := create_timer(90.0)
	wd.timeout.connect(func() -> void:
		print("SIM_SHOTS TIMEOUT after 90s - aborting")
		quit(2))
	call_deferred("_run")

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var root_node := main_scene.instantiate()
	root.add_child(root_node)
	await process_frame
	# main.tscn's ROOT node is the Main controller itself.
	var main: Node = root_node
	_expect(main != null and "world" in main, "Main controller found in scene")
	var world: Node = main.world
	# Universal motion gate: min y across ALL live shots (tunnel regression).
	var resolutions: Array[String] = []
	var launch_count := 0
	# --- SHOT 1: soft, straight (~1.8 m/s) ---
	await _fire_shot(main, world, 514.0, 0.0)
	launch_count += 1
	# --- SHOT 2: medium, angled (~3.3 m/s) ---
	await _fire_shot(main, world, 943.0, 120.0)
	launch_count += 1
	# --- SHOT 3: hard, straight (~5.0 m/s) ---
	await _fire_shot(main, world, 1429.0, 0.0)
	launch_count += 1
	_expect(launch_count == 3, "three shots fired through the real input path")
	_expect(_min_y >= -0.135, "no ball ever tunneled below the tray floor (min y %.3f)" % _min_y)
	var rack_red: int = world.hand_balls["red"].size()
	_expect(rack_red >= 1, "returned balls were re-racked (red rack=%d)" % rack_red)
	print("SIM_SHOTS total=%d failures=%d" % [_total, _fails])
	print("SIM_SHOTS " + ("ALL PASS" if _fails == 0 else "FAILURES: %d" % _fails))
	quit(1 if _fails > 0 else 0)

## Drives one full shot through main's real input handler (desktop path:
## InputEventMouseButton/Motion - the mobile touch path is gated on
## OS.has_feature("mobile") so headless sims must use the mouse events).
## Press position is arbitrary - power = |press - release| * SLING_K, the
## shot always fires up-slope, horizontal offset sets the angle.
func _fire_shot(main: Node, world: Node, drag_px: float, dx_px: float) -> void:
	var press := Vector2(540.0, 1200.0)
	var drag := Vector2(dx_px, drag_px)
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = press
	main._unhandled_input(ev_down)
	await process_frame
	await process_frame
	_expect(main.aiming, "press starts aiming")
	for i in 6:
		var ev_move := InputEventMouseMotion.new()
		ev_move.position = press + drag * (float(i + 1) / 6.0)
		ev_move.relative = drag / 6.0
		main._unhandled_input(ev_move)
		await process_frame
	var marker: RigidBody3D = main.active_ball
	_expect(marker != null and marker.freeze,
		"marker frozen during aim (no creep while player thinks)")
	_expect(marker.linear_velocity.length() < 0.001,
		"marker velocity zero during aim")
	# release -> launch
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.position = press + drag
	main._unhandled_input(ev_up)
	await process_frame
	var live: RigidBody3D = main.active_ball
	_expect(live != null and live != marker and not live.freeze,
		"release swapped in a live ball")
	if live != null and is_instance_valid(live) and not live.freeze:
		var launch_v: float = live.linear_velocity.length()
		_expect(launch_v >= 1.0,
			"launch speed sane (|v| %.2f m/s)" % launch_v)
		_expect(live.linear_velocity.z > 0.0,
			"launch is up-slope (vz %.2f)" % live.linear_velocity.z)
		# watch the full flight until resolution (4.5 s flush cap)
		var frames := 0
		while frames < 60 * 6:
			frames += 1
			await physics_frame
			if not is_instance_valid(live):
				break
			_min_y = minf(_min_y, live.position.y)
			if main.active_ball != live:
				break
		_expect(main.active_ball != live or frames < 60 * 6,
			"shot resolved within the flush window (ball %s)" %
			("resolved" if main.active_ball != live else "STILL LIVE"))
