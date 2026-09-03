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

	# --- A. no tunneling: a ball pushed up-slope never drops below the board ---
	var ball := SCBBall.create("red")
	root.add_child(ball)
	var start_z := 0.35
	ball.position = Vector3(0.0, world.ball_rest_y(0.0, start_z), start_z)
	ball.linear_velocity = Vector3(0.0, 0.0, 2.0)
	ball.angular_velocity = Vector3.ZERO
	world.track_live(ball)
	var min_y := ball.position.y
	var max_z := ball.position.z
	# Tray floor top (-0.13) minus ball radius (0.030) minus a small margin; a
	# ball center below this means it tunnelled through the tray floor.
	var min_expected := -0.165
	for i in 420:
		await physics_frame
		min_y = minf(min_y, ball.position.y)
		max_z = maxf(max_z, ball.position.z)
	print("SHOT peak_z=%.3f min_y=%.4f expected_min_y=%.4f speed=%.3f" % [
		max_z, min_y, min_expected, ball.linear_velocity.length()])
	_expect(min_y >= min_expected, "ball never tunnels below the board (min_y %.3f)" % min_y)
	_expect(max_z >= 1.4, "2.0 m/s shot reaches deep zone (peak z >= 1.4, got %.2f)" % max_z)
	_expect(max_z <= 2.4, "shot never clears the far rail (peak z <= 2.4)")
	ball.queue_free()
	for i in 5:
		await physics_frame

	# --- B. a settling ball is captured by a slot band ---
	var settler := SCBBall.create("black")
	root.add_child(settler)
	settler.position = Vector3(-0.2, world.ball_rest_y(0.0, 1.10), 1.10)
	settler.linear_velocity = Vector3.ZERO
	settler.angular_velocity = Vector3.ZERO
	world.track_live(settler)
	for i in 60:
		await physics_frame
	_expect(settler.freeze == true, "near-rest ball is captured by a slot (frozen)")
	_expect(settler.position.z > 0.9 and settler.position.z < 1.3, "capture happens at the slot band")
	settler.queue_free()
	for i in 5:
		await physics_frame

	# --- C. SLEEPING-BALL LAUNCH (live-device regression, 2026-09 seq2) ---
	# A served ball rests on the slope and Jolt puts it to sleep within ~1 s.
	# Assigning linear_velocity on a sleeping body is silently ignored, so
	# every pull-and-release did literally nothing on the phone. main.gd now
	# wakes the ball and applies the shot as an impulse.
	var bug_ball := SCBBall.create("red")
	root.add_child(bug_ball)
	bug_ball.position = Vector3(0.0, world.ball_rest_y(0.0, world.LAUNCH_Z), world.LAUNCH_Z)
	bug_ball.linear_velocity = Vector3.ZERO
	for i in 10:
		await physics_frame
	bug_ball.sleeping = true
	for i in 5:
		await physics_frame
	_expect(bug_ball.sleeping, "served ball can be in the slept state (precondition)")
	var pre_bug := bug_ball.position
	bug_ball.linear_velocity = Vector3(0.0, 0.0, 1.5)  # the OLD broken launch path
	for i in 30:
		await physics_frame
	var drift_bug: float = (bug_ball.position - pre_bug).length()
	print("SLEEP_TEST velocity-only drift=%.4f still_sleeping=%s" % [drift_bug, bug_ball.sleeping])
	# ENGINE TRUTH (4.7.2 + Jolt, measured 2026-09-04): velocity assignment DOES
	# wake and move a slept body in headless physics (drift 0.44 m). We assert
	# that so any future engine regression here is caught; the device-side
	# dead-launch therefore needs on-device logcat evidence, not this theory.
	_expect(drift_bug > 0.3,
		"velocity assignment launches even a sleeping ball on this engine (drift %.4f)" % drift_bug)
	bug_ball.queue_free()
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