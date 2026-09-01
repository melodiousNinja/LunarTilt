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
	var min_y := ball.position.y
	var min_expected := -0.135  # tray floor top (-0.13) minus ball radius (-0.02) and margin
	for i in 420:
		await physics_frame
		min_y = minf(min_y, ball.position.y)
	print("SHOT final_z=%.3f min_y=%.4f expected_min_y=%.4f speed=%.3f" % [
		ball.position.z, min_y, min_expected, ball.linear_velocity.length()])
	_expect(min_y >= min_expected, "ball never tunnels below the board (min_y %.3f)" % min_y)
	_expect(ball.position.z >= 1.4, "2.0 m/s shot reaches deep zone (z >= 1.4)")
	_expect(ball.position.z <= 2.4, "shot never clears the far rail (z <= 2.4)")
	ball.queue_free()
	for i in 5:
		await physics_frame

	# --- B. a settling ball is captured by a slot band ---
	var settler := SCBBall.create("black")
	root.add_child(settler)
	settler.position = Vector3(-0.2, world.ball_rest_y(0.0, 1.10), 1.10)
	settler.linear_velocity = Vector3.ZERO
	settler.angular_velocity = Vector3.ZERO
	for i in 60:
		await physics_frame
	_expect(settler.freeze == true, "near-rest ball is captured by a slot (frozen)")
	_expect(settler.position.z > 0.9 and settler.position.z < 1.3, "capture happens at the slot band")
	settler.queue_free()
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