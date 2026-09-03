class_name MatchController
extends RefCounted
## Turn/match state machine for Lunar Tilt. Pure logic - no rendering, no
## physics engine. The scene feeds real shot outcomes into `resolve_shot` and
## listens on signals; this type fully owns the rules, scores, and turn order.

signal state_changed(state: Dictionary)
signal match_ended(result: Dictionary)

enum Mode { BLITZ, CLASSIC }

const BALLS_PER_PLAYER_BLITZ := 8
const BALLS_PER_PLAYER_CLASSIC := 12
const SLOT_POINTS := [1, 2, 5]

var mode := Mode.BLITZ
var players := []          # [{color, hand, score}]
var turn := 0              # index into players
var board := []            # [ [7 slots] x3 ]
var finished := false
var winner := ""           # "red" / "black" / "draw" once finished


static func make(mode: Mode) -> MatchController:
	var m := MatchController.new()
	m.mode = mode
	m.players = [
		{"color": "red", "hand": BALLS_PER_PLAYER_BLITZ if mode == Mode.BLITZ else BALLS_PER_PLAYER_CLASSIC, "score": 0},
		{"color": "black", "hand": BALLS_PER_PLAYER_BLITZ if mode == Mode.BLITZ else BALLS_PER_PLAYER_CLASSIC, "score": 0},
	]
	m.turn = 0
	m.board = [[], [], []]
	for pi in range(3):
		for _i in range(7):
			m.board[pi].append("")
	m.finished = false
	m.winner = ""
	return m


func active_player() -> Dictionary:
	return players[turn]


func other_player() -> Dictionary:
	return players[(turn + 1) % players.size()]


## Consume a shot's outcome.
## out = { hit_slot: int (-1 none), gutted: bool,
##         scored_for: String (defaults to active color; for knockout-in) }
func resolve_shot(out: Dictionary) -> Dictionary:
	if finished:
		return _snapshot()
	var p: Dictionary = players[turn]
	var hit := int(out.get("hit_slot", -1))
	var is_slot := hit >= 0
	var scored_for: String = out.get("scored_for", p["color"])
	var gutter := bool(out.get("gutted", false))

	if is_slot:
		var pi := clampi(hit, 0, 2)
		_claim_slot(pi, scored_for)
		for player in players:
			if player["color"] == scored_for:
				player["score"] = int(player["score"]) + SLOT_POINTS[pi]
				break
		# The shot ball is spent either way - it stays in the slot.
		p["hand"] = int(p["hand"]) - 1
		# Keep the turn when the SHOOTER scored; a knockout-in passes it.
		if scored_for != p["color"]:
			turn = (turn + 1) % players.size()
	else:
		# Miss / returned ball / gutter: ball is spent, turn passes.
		p["hand"] = int(p["hand"]) - 1
		turn = (turn + 1) % players.size()

	if int(p["hand"]) <= 0:
		finished = true
		_calc_final()
		_compute_winner()
		match_ended.emit(_snapshot())
		return _snapshot()

	state_changed.emit(_snapshot())
	return _snapshot()


## Claim the first empty slot of position `pi` for `color`.
func _claim_slot(pi: int, color: String) -> void:
	for i in range(board[pi].size()):
		if board[pi][i] == "":
			board[pi][i] = color
			return


## Final scoring: aggregate chain + Grand Slam bonuses via the official engine.
func _calc_final() -> void:
	for p in players:
		var res := RulesEngine.score_board(board)
		p["score"] = int(res["per_color"][p["color"]])


func _compute_winner() -> void:
	var red := int(players[0]["score"])
	var black := int(players[1]["score"])
	if red > black:
		winner = "red"
	elif black > red:
		winner = "black"
	else:
		winner = "draw"


func _snapshot() -> Dictionary:
	return {
		"turn": turn,
		"players": players.duplicate(true),
		"board": board.duplicate(true),
		"finished": finished,
		"winner": winner,
		"mode": mode,
	}