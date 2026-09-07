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
	_expect(String(d["action"]) == "claim",
		"v13 linear slits: col 0 only touches col 1 (empty) -> plain claim")
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

	# --- B. 15 discrete groove slits exist (v13 fan layout 7/5/3) ---
	var world: TableWorld = WorldScript.new()
	root.add_child(world)
	for i in 30:
		await physics_frame
	_expect(world.slots.size() == 15, "15 slits built (got %d)" % world.slots.size())
	var cols_ok := true
	var band_counts := {"0": 0, "1": 0, "2": 0}
	for sd in world.slots:
		band_counts[str(int(sd["band"]))] = int(band_counts[str(int(sd["band"]))]) + 1
		if not sd.has("col") or int(sd["col"]) < 0 or int(sd["col"]) >= TableWorld.FAN_GAPS[int(sd["band"])]:
			cols_ok = false
	_expect(cols_ok, "every slit carries a valid column index for its fan")
	_expect(int(band_counts["0"]) == 7 and int(band_counts["1"]) == 5 and int(band_counts["2"]) == 3,
		"fan slits 7/5/3 (got %s)" % str(band_counts))

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
	# Clean up after ourselves: section C claimed slot 1:3, so release that
	# claim before section D reuses the same slot - otherwise D's incoming
	# ball correctly sees a BOOKED gap and blocks instead of scoring.
	world._take_socket_ball(1, 3)
	for i in 5:
		await physics_frame

	# --- D. booked gaps are PERMANENT (v14 user rule): an incoming ball
	# claims an empty gap and never touches a booked neighbour ---
	world.spawn_hand_ball("red")
	var rack_before: int = (world.hand_balls["red"] as Array).size()
	var n := SCBBall.create("red")
	root.add_child(n)
	var sp2: Vector3 = world.socket_pos(1, 2)
	n.position = Vector3(sp2.x, world.ball_rest_y(sp2.x, sp2.z), sp2.z)
	world._claim_socket(world.slots[9], n)   # band 1, col 2 booked
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
	_expect(inc.freeze, "incoming ball claims the empty gap")
	_expect(String(world.slots[9]["color"]) == "red",
		"booked neighbour gap is untouched (no magical replacement)")
	_expect(String(world.slots[10]["color"]) == "red",
		"incoming ball owns the new gap")
	var rack_after: int = (world.hand_balls["red"] as Array).size()
	_expect(rack_after == rack_before,
		"no displacement: the booked ball stays on the table")
	_expect(not keep[0], "claims pass the turn (no keep-shooting)")
	_expect(scored_band[0] == 1, "claim scored in position 2")
	# D2: an incoming ball into an OCCUPIED gap can never recapture it.
	var occ_ball := SCBBall.create("black")
	root.add_child(occ_ball)
	occ_ball.position = Vector3(sp2.x, world.ball_rest_y(sp2.x, sp2.z) + 0.02, sp2.z)
	occ_ball.linear_velocity = Vector3.ZERO
	var grouped_flag := [false]
	world.ball_grouped.connect(func(_b: SCBBall) -> void: grouped_flag[0] = true)
	world.track_live(occ_ball)
	for i in 60:
		await physics_frame
	_expect(occ_ball.freeze and grouped_flag[0],
		"ball settling on a booked gap is blocked (turn passes, no score)")
	_expect(String(world.slots[9]["color"]) == "red",
		"the booked gap still belongs to red")
	occ_ball.queue_free()
	for i in 5:
		await physics_frame

	print("GROUPING_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("GROUPING_TEST FAILURES: %d" % _failures)
		quit(1)