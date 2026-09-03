extends SceneTree
## Bisect: at which Z does a freshly-dropped ball tunnel through the board?
## Run: godot --headless --path . --script res://tests/bisect_z.gd

const WorldScript := preload("res://scripts/game/table_world.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame
	print("BISECT board_pos=%s rot=%.4f surface(0.22)=%.4f surface(0.35)=%.4f" % [
		world.board.position, world.board.rotation.x,
		world.surface_y_static(0.0, 0.22), world.surface_y_static(0.0, 0.35)])
	for z in [0.10, 0.22, 0.28, 0.32, 0.35, 0.50, 0.62]:
		var b := SCBBall.create("red")
		b.position = Vector3(0.0, world.ball_rest_y(0.0, z) + 0.008 + SCBBall.RADIUS_M, z)
		root.add_child(b)
		var min_y: float = b.position.y
		for i in 150:
			await physics_frame
			min_y = minf(min_y, b.position.y)
		print("BISECT z=%.2f start_y=%.4f min_y=%.4f end=%s fell=%s" % [
			z, world.ball_rest_y(0.0, z) + 0.038, min_y, b.position, str(min_y < -0.5)])
		b.queue_free()
		for i in 5:
			await physics_frame
	print("BISECT_DONE")
	quit(0)