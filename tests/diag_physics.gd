extends SceneTree
## Temporary diagnostic for the physics shot test.
const WorldScript := preload("res://scripts/game/table_world.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame

	# Probe clear of any slot area (z=0.45 is before Pos1 band at 0.50+).
	var probe := SCBBall.create("black")
	root.add_child(probe)
	probe.position = Vector3(0.0, world.ball_rest_y(0.0, 0.45), 0.45)
	probe.linear_velocity = Vector3.ZERO
	probe.angular_velocity = Vector3.ZERO
	for i in 80:
		await physics_frame
	print("PROBE pos=(%.3f,%.4f,%.3f) vel=%s" % [probe.position.x, probe.position.y, probe.position.z,
		Vector3(probe.linear_velocity.x, probe.linear_velocity.y, probe.linear_velocity.z)])
	probe.queue_free()
	for i in 5:
		await physics_frame

	var ball := SCBBall.create("red")
	root.add_child(ball)
	var start_z := 0.35
	ball.position = Vector3(0.0, world.ball_rest_y(0.0, start_z), start_z)
	print("SPAWN pos=%s surface_top=%.4f" % [ball.position, world.surface_y_at(0.0, 0.35)])
	ball.linear_velocity = Vector3(0.0, 0.0, 2.0)
	ball.angular_velocity = Vector3.ZERO
	for i in 120:
		await physics_frame
		if i % 6 == 0 or i < 6:
			print("f=%d pos=(%.3f,%.4f,%.3f) vel=(%.3f,%.3f,%.3f) spd=%.3f cont=%d sleeping=%s" % [i,
				ball.position.x, ball.position.y, ball.position.z,
				ball.linear_velocity.x, ball.linear_velocity.y, ball.linear_velocity.z,
				ball.linear_velocity.length(), ball.get_contact_count(), ball.sleeping])
	quit(0)


func _build_body(pmat: bool, ccd: bool, contacts: bool, damp: bool, layer: int, mask: int) -> RigidBody3D:
	var ball := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := SphereShape3D.new()
	shp.radius = 0.02
	cs.shape = shp
	ball.add_child(cs)
	ball.mass = 0.045
	ball.collision_layer = layer
	ball.collision_mask = mask
	if pmat:
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.55
		pm.friction = 0.49
		ball.physics_material_override = pm
	if ccd:
		ball.continuous_cd = true
	if contacts:
		ball.contact_monitor = true
		ball.max_contacts_reported = 8
	if damp:
		ball.angular_damp = 1.1
		ball.linear_damp = 0.02
	return ball


func _rest_test(name: String, ball: RigidBody3D) -> void:
	root.add_child(ball)
	ball.position = Vector3(0.0, 0.25, 1.10)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	for i in 60:
		await physics_frame
	var contacts := 0
	if ball.has_method("get_contact_count"):
		contacts = ball.get_contact_count()
	print("REST %-16s y=%.4f z=%.3f vel=%s contacts=%d" % [name, ball.position.y, ball.position.z,
		Vector3(ball.linear_velocity.x, ball.linear_velocity.y, ball.linear_velocity.z), contacts])
	ball.queue_free()
	for i in 5:
		await physics_frame


func _make_vanilla() -> RigidBody3D:
	var ball := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var shp := SphereShape3D.new()
	shp.radius = 0.02
	cs.shape = shp
	ball.add_child(cs)
	ball.mass = 0.045
	return ball


func _make_scb_with(color: String, layer: int, mask: int) -> SCBBall:
	var b := SCBBall.create(color)
	b.collision_layer = layer
	b.collision_mask = mask
	return b


func _drop_variant(name: String, ball: RigidBody3D) -> void:
	root.add_child(ball)
	ball.position = Vector3(0.0, 0.25, 1.10)
	ball.linear_velocity = Vector3.ZERO
	for i in 60:
		await physics_frame
	print("RESULT %s y=%.4f (board top ~ -0.0335 at this z)" % [name, ball.position.y])
	ball.queue_free()
	for i in 5:
		await physics_frame