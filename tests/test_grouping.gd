extends SceneTree
## OFFICIAL GROUPING rule tests (pure decision table + live physics).
##   - claim an empty socket: ball STAYS as a blocker, scored, turn passes
##   - land adjacent to an own ball: the neighbour returns to its rack
##     (displacement) and the shooter KEEPS shooting
##   - pocket walled by the other colour, no own neighbour: the ball rests as
##     a grouping wall, no score, turn passes
## Run: godot --headless --path . --script res://tests/test_grouping.gd

const WorldScript := preload("res://scripts/game/table_world.gd")

var _failures := 0
var _total := 0


func _initialize() -> void:
	_run()


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)


func _run() -> void:
	# --- A. pure decision table (RulesEngine.resolve_socket) ---
	var occ: Array = ["", "", "red", "", "black", "", ""]
	var d := RulesEngine.resolve_socket(occ, 0, "red")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 2
		and bool(d["keep_shooting"]),
		"centre socket touches the whole ring: own ball at col 2 is displaced")
	d = RulesEngine.resolve_socket(occ, 2, "red")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 2,
		"landing on an own ball displaces it and keeps the turn")
	d = RulesEngine.resolve_socket(occ, 3, "red")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 2
		and bool(d["keep_shooting"]),
		"adjacent own ball (left) is displaced, shooter keeps shooting")
	d = RulesEngine.resolve_socket(occ, 2, "black")
	_expect(String(d["action"]) == "block",
		"enemy-occupied socket with no own neighbour -> block")
	occ = ["", "black", "red", "black", ""]
	d = RulesEngine.resolve_socket(occ, 2, "red")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 2
		and bool(d["keep_shooting"]),
		"landing on an own ball flanked by enemies still regroups (wall guards enemies only)")
	occ = ["", "", "red", "", "black", "", ""]  # restore the 7-socket row
	d = RulesEngine.resolve_socket(occ, 1, "red")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 2
		and bool(d["keep_shooting"]),
		"adjacent own ball on the right is displaced")
	d = RulesEngine.resolve_socket(occ, 5, "black")
	_expect(String(d["action"]) == "displace" and int(d["displace_col"]) == 4
		and bool(d["keep_shooting"]),
		"black grouping black keeps shooting")
	d = RulesEngine.resolve_socket(occ, 6, "red")
	_expect(String(d["action"]) == "claim",
		"empty socket next to the other colour -> plain claim")
	d = RulesEngine.resolve_socket(occ, -1, "red")
	_expect(String(d["action"]) == "block", "out-of-range column -> block")

	# --- B. 21 discrete sockets exist (official astrolabe layout) ---
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame
	_expect(world.slots.size() == 21, "21 sockets built (got %d)" % world.slots.size())
	var cols_ok := true
	for sd in world.slots:
		if not sd.has("col") or int(sd["col"]) < 0 or int(sd["col"]) > 6:
			cols_ok = false
	_expect(cols_ok, "every socket carries a column index 0..6")

	# --- C. live claim: a settling ball claims an empty socket ---
	var b := SCBBall.create("red")
	root.add_child(b)
	var sp: Vector3 = world.socket_pos(1, 3)
	b.position = Vector3(sp.x, world.ball_rest_y(sp.x, sp.z), sp.z)
	world.track_live(b)
	for i in 60:
		await physics_frame
	_expect(b.freeze, "settling ball is claimed by the empty socket")
	_expect(String(world.slots[10]["color"]) == "red",
		"socket 1:3 records the claim")
	_expect(world.socket_balls.has("1:3"), "socket registry holds the claim")
	b.queue_free()
	for i in 5:
		await physics_frame

	# --- D. live grouping: land next to an own ball -> neighbour re-racked ---
	world.spawn_hand_ball("red")
	var rack_before: int = (world.hand_balls["red"] as Array).size()
	var n := SCBBall.create("red")
	root.add_child(n)
	var sp2: Vector3 = world.socket_pos(1, 2)
	n.position = Vector3(sp2.x, world.ball_rest_y(sp2.x, sp2.z), sp2.z)
	world._claim_socket(world.slots[9], n)   # band 1, col 2 claimed
	var inc := SCBBall.create("red")
	root.add_child(inc)
	var sp3: Vector3 = world.socket_pos(1, 3)
	inc.position = Vector3(sp3.x, world.ball_rest_y(sp3.x, sp3.z), sp3.z)
	inc.linear_velocity = Vector3.ZERO
	var keep := [false]
	var scored_band := [-1]
	world.ball_scored.connect(func(ball: SCBBall, band: int, ks: bool) -> void:
		scored_band[0] = band
		keep[0] = ks)
	world.track_live(inc)
	for i in 60:
		await physics_frame
	_expect(inc.freeze, "incoming ball claims the adjacent socket")
	_expect(String(world.slots[9]["color"]) == "",
		"displaced neighbour's socket is freed")
	_expect(String(world.slots[10]["color"]) == "red",
		"incoming ball owns the new socket")
	var rack_after: int = (world.hand_balls["red"] as Array).size()
	_expect(rack_after == rack_before + 1,
		"displaced ball returned to the rack (%d -> %d)" % [rack_before, rack_after])
	_expect(keep[0], "grouping keeps the shooter's turn")
	_expect(scored_band[0] == 1, "claim scored in position 2")

	print("GROUPING_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("GROUPING_TEST FAILURES: %d" % _failures)
		quit(1)