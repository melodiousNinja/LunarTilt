extends SceneTree
## Unit tests for RulesEngine (scoring, chaining, Grand Slam).
## Run:  godot --headless --path . --script res://tests/test_rules.gd

var _failures := 0
var _total := 0


func _initialize() -> void:
	_test_all()
	print("RULES_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("RULES_TEST FAILURES: %d" % _failures)
		quit(1)


func _test_all() -> void:
	# 1. empty board
	_expect(RulesEngine.score_board([[], [], []])["per_color"]["red"] == 0, "empty red 0")
	_expect(RulesEngine.score_board([[], [], []])["per_color"]["black"] == 0, "empty black 0")

	# 2. single ball in position 2
	var b2 := [[], ["red"], []]
	_expect(RulesEngine.score_board(b2)["per_color"]["red"] == 2, "single red pos2 = 2")
	_expect(RulesEngine.score_board(b2)["breakdown"]["red"][1] == 2, "breakdown pos2 = 2")

	# 3. single ball in position 3 = 3 (v13 fan values 1/2/3)
	_expect(RulesEngine.score_board([[], [], ["red"]])["per_color"]["red"] == 3, "single red pos3 = 3")

	# 4. chain of 3 reds in pos1: base 3*1 + chain 1*(3-1) = 5
	var b4 := [["red", "red", "red", "", "", "", ""], [], []]
	_expect(RulesEngine.score_board(b4)["per_color"]["red"] == 5, "chain 3 pos1 = 5")

	# 5. chain of 2 reds in pos3: base 2*3 + chain 3*(2-1) = 9
	var b5 := [[], [], ["red", "red", "", "", "", "", ""]]
	_expect(RulesEngine.score_board(b5)["per_color"]["red"] == 9, "chain 2 pos3 = 9")

	# 6. Grand Slam: full pos1 of reds -> base 7 doubled to 14, + chain 6 = 20
	var b6 := [["red", "red", "red", "red", "red", "red", "red"], [], []]
	var res6 := RulesEngine.score_board(b6)
	_expect(res6["per_color"]["red"] == 20, "grand slam pos1 red = 20")
	_expect(res6["grand_slams"].size() == 1 and res6["grand_slams"][0] == "red", "grand slam flagged")

	# 7. consecutive same-color runs chain; runs broken by other colors do not chain
	var b7 := [["red", "red", "red", "black", "black", "black", "black"], [], []]
	var res7 := RulesEngine.score_board(b7)
	_expect(res7["per_color"]["red"] == 5, "mixed red run of 3 pos1 = 3 base + 2 chain = 5")
	_expect(res7["per_color"]["black"] == 7, "mixed black run of 4 pos1 = 4 base + 3 chain = 7")
	_expect(res7["grand_slams"].is_empty(), "no slam on mixed")

	# 7b. adjacency matters: red-black-red-red = runs [1] and [2], not [3]
	var b7b := [["red", "black", "red", "red", "", "", ""], [], []]
	var res7b := RulesEngine.score_board(b7b)
	_expect(res7b["per_color"]["red"] == 4, "adjacency broken red = 3 base + 1 chain = 4")
	_expect(res7b["per_color"]["black"] == 1, "single black pos1 = 1")

	# 8. case-insensitive slot colors
	var b8 := [["RED", "Red"], [], []]
	_expect(RulesEngine.score_board(b8)["per_color"]["red"] == 3, "case-insensitive red = 3")

	# 9. shot_scored helper
	_expect(RulesEngine.shot_scored(["", "", "red"]) == true, "scored shot detected")
	_expect(RulesEngine.shot_scored(["", "", ""]) == false, "empty shot not scored")

	# 10. both players scoring independently, no cross-contamination
	var b10 := [["red"], ["black"], ["red"]]
	var res10 := RulesEngine.score_board(b10)
	_expect(res10["per_color"]["red"] == 4, "red pos1+pos3 = 1+3 = 4")
	_expect(res10["per_color"]["black"] == 2, "black pos2 = 2")

	# 11. v13 fan sizes: grand slams fill 7 / 5 / 3 slits respectively
	var slam1 := RulesEngine.score_board([["red", "red", "red", "red", "red", "red", "red"], [], []])
	_expect(slam1["per_color"]["red"] == 20, "pos1 slam: 7*1 x2 + chain 6 = 20")
	var slam2 := RulesEngine.score_board([[], ["red", "red", "red", "red", "red"], []])
	_expect(slam2["per_color"]["red"] == 28, "pos2 slam: 5*2 x2 + chain 2*4 = 28")
	var slam3 := RulesEngine.score_board([[], [], ["red", "red", "red"]])
	_expect(slam3["per_color"]["red"] == 24, "pos3 slam: 3*3 x2 + chain 3*2 = 24")


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)