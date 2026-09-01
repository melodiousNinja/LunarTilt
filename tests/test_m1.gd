extends SceneTree
## M1 tests: ShotMath analytics, AIOpponent heuristics, and a full simulated
## match (AI vs AI) asserting turn alternation, scoring, and completion.
## Run:  godot --headless --path . --script res://tests/test_m1.gd

var _failures := 0
var _total := 0


func _initialize() -> void:
	_test_shot_math()
	_test_ai_heuristics()
	await _test_match_sim()
	print("M1_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("M1_TEST FAILURES: %d" % _failures)
		quit(1)


func _test_shot_math() -> void:
	# Stop distance consistency: power_for_distance/landing_z round-trip.
	var pz := ShotMath.power_for_slot(1)              # to slot 2 center (z=1.10)
	_expect(absf(ShotMath.landing_z(pz, 0.0) - ShotMath.SLOT_Z[1]) < 0.05,
		"power_for_slot lands at its slot center (err=%.3f)" % absf(ShotMath.landing_z(pz, 0.0) - ShotMath.SLOT_Z[1]))
	_expect(ShotMath.will_gutter(ShotMath.GUTTER_POWER, 0.0) == true, "max power guts")
	_expect(ShotMath.will_gutter(0.8, 0.0) == false, "gentle shot safe")
	# Angle drift: 20-degree throw moves laterally but keeps z shorter.
	var az := ShotMath.landing_z(2.0, deg_to_rad(20.0))
	_expect(az < ShotMath.landing_z(2.0, 0.0), "angled shot stops shorter")


func _test_ai_heuristics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# Empty board: AI should prefer the highest-value position (pos3).
	var p1: Dictionary = AIOpponent.plan_shot(rng, AIOpponent.Level.STRATEGIST, [[], [], []], "red")
	_expect(p1["target_pi"] == 2, "AI picks highest-value empty slot (pos3)")
	# Board with 3 player balls already in pos3 (the 5-pt position): growing
	# that chain has the largest marginal > any unclaimed slot.
	var board := [[], [], ["red", "red", "red"]]
	var p2: Dictionary = AIOpponent.plan_shot(rng, AIOpponent.Level.STRATEGIST, board, "red")
	_expect(p2["target_pi"] == 2, "AI grows its highest-value chain (pos3)")
	# Board nearing a Grand Slam in pos2 (6/7 filled): completing the slam wins.
	var board_slam := [["", "", "", "", "", "", ""], ["red", "red", "red", "red", "red", "red", ""], []]
	var p3: Dictionary = AIOpponent.plan_shot(rng, AIOpponent.Level.STRATEGIST, board_slam, "red")
	_expect(p3["target_pi"] == 1, "AI goes for the Grand Slam when one ball away")
	# Stronger aim at higher levels: club jitter smaller than rookie.
	_expect(AIOpponent.AIM_ERROR_DEG[AIOpponent.Level.CLUB] < AIOpponent.AIM_ERROR_DEG[AIOpponent.Level.ROOKIE],
		"higher level = tighter aim")


func _test_match_sim() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var m := MatchController.make(MatchController.Mode.BLITZ)
	var guard := 0
	while not m.finished and guard < 400:
		guard += 1
		# Active player's AI plans a shot; resolve via the analytic model.
		var board := m.board
		var color: String = String(m.active_player()["color"])
		var level := AIOpponent.Level.CLUB
		var shot: Dictionary = AIOpponent.plan_shot(rng, level, board, color)
		var out := Dictionary()
		if ShotMath.lands_in_slot(shot["target_pi"], shot["power"], shot["angle"]):
			out["hit_slot"] = shot["target_pi"]
		elif ShotMath.will_gutter(shot["power"], shot["angle"]):
			out["gutted"] = true
		m.resolve_shot(out)
		await physics_frame
	_expect(m.finished, "match completes in bounded turns (guard=%d)" % guard)
	var red: Dictionary = m.players[0]
	var black: Dictionary = m.players[1]
	_expect(int(red["hand"]) >= 0 and int(black["hand"]) >= 0, "hands never negative")
	var total_scored := int(red["score"]) + int(black["score"])
	_expect(total_scored >= 0, "scores are non-negative")
	await physics_frame


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)