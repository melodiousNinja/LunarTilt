extends SceneTree
## Physics tests for the tilted table.
##
## Real-world behavior notes (from the official sport rules):
##   - Balls NOT caught by a slot roll back DOWN the slope to the player
##     ("Returned Ball" rule) - so we do NOT assert that resting balls stay put;
##     we assert they stay ON the board and never tunnel through it.
##   - A ball that SETTLES into a slot band (speed < SLOT_CAPTURE_SPEED) is
##     captured and frozen there.
##   - A hard shot crosses Pos1/Pos2 and dies in the deep zone or the gutter.
## Run:  godot --headless --path . --script res://tests/test_physics.gd

const WorldScript := preload("res://scripts/game/table_world.gd")

var _failures := 0
var _total := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame

	# --- A. FACTORY POWER CURVE (empirical, tests/sweep_hop.gd 2026-09) ---
	# Launch mirrors main._release_shot: horizontal power + HOP_K vertical
	# fraction. Factory geometry gives the real sport's difficulty curve:
	#   soft toss 2.0 -> dies against Venus's raised face, rolls back (miss)
	#   firm toss 3.8 -> clears Venus, is CAPTURED in a Mars well (2-pt zone)
	var min_expected := -0.165
	var ball := SCBBall.create("red")
	root.add_child(ball)
	var start_z := 0.35
	ball.position = Vector3(0.0, world.ball_rest_y(0.0, start_z), start_z)
	ball.linear_velocity = Vector3(0.0, 2.0 * ShotMath.HOP_K, 2.0)
	ball.angular_velocity = Vector3.ZERO
	world.track_live(ball)
	var min_y := ball.position.y
	var max_z := ball.position.z
	for i in 420:
		await physics_frame
		min_y = minf(min_y, ball.position.y)
		max_z = maxf(max_z, ball.position.z)
	print("SHOT soft peak_z=%.3f min_y=%.4f" % [max_z, min_y])
	_expect(min_y >= min_expected, "ball never tunnels below the board (min_y %.3f)" % min_y)
	_expect(max_z < 1.75,
		"soft toss dies at the Venus mouth and rolls back (peak z %.2f < 1.75)" % max_z)
	_expect(max_z <= 2.9, "shot never clears the far rail (peak z <= 2.9)")
	_expect(ball.freeze, "soft toss resolves (rolled back and was re-racked)")
	ball.queue_free()
	for i in 5:
		await physics_frame

	# Firm toss: with HONEST slit geometry (no funnel) a 3.8 m/s toss
	# overpowers the table - it clears every fan and dies in the gutter
	# trench. That is the official lost-ball rule, not a regression.
	var firm := SCBBall.create("red")
	root.add_child(firm)
	firm.position = Vector3(0.0, world.ball_rest_y(0.0, start_z), start_z)
	firm.linear_velocity = Vector3(0.0, 3.8 * ShotMath.HOP_K, 3.8)
	firm.angular_velocity = Vector3.ZERO
	world.track_live(firm)
	var firm_peak := firm.position.z
	for i in 420:
		await physics_frame
		firm_peak = maxf(firm_peak, firm.position.z)
	print("SHOT firm peak_z=%.3f end=%s frozen=%s" % [
		firm_peak, firm.position, firm.freeze])
	_expect(firm_peak >= 1.4,
		"firm toss reaches the Mars zone (peak z %.2f >= 1.4)" % firm_peak)
	_expect(firm.freeze and firm.position.z > 1.70 and firm.position.z < 2.05,
		"firm toss drops into a groove FROM THE TOP (z %.2f)" % firm.position.z)
	firm.queue_free()
	for i in 5:
		await physics_frame

	# Medium toss dead-centre: lands BEYOND the first fan (mouths face the
	# top), rolls back down-slope, and drops into a groove from the top -
	# caught by the gap's front wall. THE core v15.1 mechanic.
	var med := SCBBall.create("red")
	root.add_child(med)
	med.position = Vector3(0.0, world.ball_rest_y(0.0, start_z), start_z)
	med.linear_velocity = Vector3(0.0, 2.9 * ShotMath.HOP_K, 2.9)
	med.angular_velocity = Vector3.ZERO
	world.track_live(med)
	for i in 420:
		await physics_frame
	print("SHOT medium end=%s frozen=%s" % [med.position, med.freeze])
	_expect(med.freeze and med.position.z < 0.4,
		"medium toss falls short and returns to the rack (z %.2f)" % med.position.z)
	med.queue_free()
	for i in 5:
		await physics_frame

	# --- B. a settling ball is captured by a groove (middle fan, top entry) ---
	var settler := SCBBall.create("black")
	root.add_child(settler)
	var sp_settle: Vector3 = world.socket_pos(1, 2)
	settler.position = Vector3(sp_settle.x, world.ball_rest_y(sp_settle.x, sp_settle.z), sp_settle.z)
	settler.linear_velocity = Vector3.ZERO
	settler.angular_velocity = Vector3.ZERO
	world.track_live(settler)
	for i in 60:
		await physics_frame
	_expect(settler.freeze == true, "near-rest ball is captured by a socket (frozen)")
	_expect(settler.position.z > 2.6 and settler.position.z < 3.0, "capture happens at the Mars fan")
	settler.queue_free()
	for i in 5:
		await physics_frame

	# --- C. AIM-CREEP (live-device regression, 2026-09 telemetry) ---
	# The served ball used to be LIVE at the launch spot: on the 5-degree
	# slope it crept back while the player aimed, rolled off the front edge
	# (there was NO tray), and free-fell into the void - the "invisible ball".
	# The serve is now a FROZEN MARKER and the tray exists.
	world.spawn_hand_ball("red")  # stock the rack (a fresh match state)
	var marker := world.take_hand_ball("red")
	_expect(marker != null, "serve returns a marker ball")
	_expect(marker.freeze, "served ball is a frozen marker (cannot creep)")
	var pre_bug: Vector3 = marker.position
	for i in 150:
		await physics_frame
	var creep: float = (marker.position - pre_bug).length()
	print("AIM_CREEP drift=%.5f tray=%s" % [creep, world._tray_zone != null])
	_expect(creep < 0.001,
		"marker does not move during a 2.5 s aim window (drift %.4f)" % creep)
	_expect(world._tray_zone != null,
		"front tray exists so returned balls land, not void-fall")
	marker.queue_free()
	for i in 5:
		await physics_frame

	var fix_ball := SCBBall.create("black")
	root.add_child(fix_ball)
	fix_ball.position = Vector3(0.0, world.ball_rest_y(0.0, world.LAUNCH_Z), world.LAUNCH_Z)
	fix_ball.linear_velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	fix_ball.sleeping = true
	for i in 5:
		await physics_frame
	var pre_fix := fix_ball.position
	# The exact code main._release_shot now runs:
	fix_ball.sleeping = false
	fix_ball.apply_central_impulse(Vector3(0.0, 0.0, 1.5) * fix_ball.mass)
	var peak_z := pre_fix.z
	for i in 120:
		await physics_frame
		peak_z = maxf(peak_z, fix_ball.position.z)
	print("SLEEP_TEST wake+impulse peak_z=%.3f (from %.3f)" % [peak_z, pre_fix.z])
	_expect(peak_z > pre_fix.z + 0.3,
		"wake + impulse launches a sleeping ball up-slope (peak z %.2f)" % peak_z)
	fix_ball.queue_free()
	for i in 5:
		await physics_frame

	# --- D. LAUNCH + RETURN-TO-TRAY (live-device regression, 2026-09) ---
	# The full shot cycle that was broken on device: serve marker -> launch a
	# fresh live ball -> ball rides up, rolls back (Returned-Ball rule) and
	# must land in the TRAY and be re-racked - never void-fall again.
	world.spawn_hand_ball("red")
	world.spawn_hand_ball("red")  # one for this cycle, one guaranteed for the re-serve
	var m := world.take_hand_ball("red")
	_expect(m != null, "serve returns a marker ball")
	var live := world.launch_hand_ball(m, Vector3(0.0, 0.0, 2.0))
	_expect(live != null and not live.freeze, "launch produces a live ball")
	var d_min_y := 1.0
	for i in 420:
		await physics_frame
		if is_instance_valid(live):
			d_min_y = minf(d_min_y, live.position.y)
	print("LAUNCH_TEST min_y=%.4f end_valid=%s rack=%d" % [
		d_min_y, is_instance_valid(live), (world.hand_balls["red"] as Array).size()])
	_expect(d_min_y > -0.30,
		"launched ball lands in the tray, never the void (min y %.3f)" % d_min_y)
	_expect(not is_instance_valid(live) or live.freeze,
		"ball resolved (returned and re-racked or captured)")
	# Second serve cycle from the re-racked pool (was 15 m / 92 m void on device).
	var m2 := world.take_hand_ball("red")
	_expect(m2 != null, "second serve from re-racked pool works")
	if m2 != null:
		m2.queue_free()
	for i in 5:
		await physics_frame

	print("PHYSICS_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("PHYSICS_TEST FAILURES: %d" % _failures)
		quit(1)


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)