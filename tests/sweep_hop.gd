extends SceneTree
## Empirical tuning sweep for the v11 parabolic toss.
## Launches at several powers with the current HOP_K and reports peak z,
## landing behavior, and where the ball ends up, so HOP_K / friction / the
## test assertions get set from real physics, not guesses.

const WorldScript := preload("res://scripts/game/table_world.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame
	for power in [1.2, 2.0, 2.8, 3.2, 3.6, 4.0, 4.4, 5.0, 5.6, 6.4]:
		var ball := SCBBall.create("red")
		root.add_child(ball)
		ball.position = Vector3(0.0, world.ball_rest_y(0.0, 0.35), 0.35)
		ball.linear_velocity = Vector3(0.0, power * ShotMath.HOP_K, power)
		world.track_live(ball)
		var peak_z := ball.position.z
		var min_y := ball.position.y
		var frozen_frame := -1
		for i in 600:
			await physics_frame
			peak_z = maxf(peak_z, ball.position.z)
			min_y = minf(min_y, ball.position.y)
			if frozen_frame < 0 and ball.freeze:
				frozen_frame = i
		print("SWEEP p=%.1f peak_z=%.3f min_y=%.3f end=%s frozen_f=%d" % [
			power, peak_z, min_y, ball.position, frozen_frame])
		ball.queue_free()
		for i in 5:
			await physics_frame
	quit(0)
