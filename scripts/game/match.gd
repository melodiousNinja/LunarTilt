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
	return m


func active_player() -> Dictionary:
	return players[turn]


func other_player() -> Dictionary:
	return players[(turn + 1) % players.size()]


## Consume a shot's outcome. out = { hit_slot: int (-1 none), gutted: bool }
## Returns the new state dictionary. Throws nothing - callers watch signals.
func resolve_shot(out: Dictionary) -> Dictionary:
	if finished:
		return _snapshot()

	var p: Dictionary = players[turn]
	var is_slot := int(out.get("hit_slot", -1)) >= 0
	var gutted := bool(out.get("gutted", false))

	if is_slot:
		var pi := clampi(int(out["hit_slot"]), 0, 2)
		_claim_slot(pi, p.color)
		p["score"] += SLOT_POINTS[pi]
		p["hand"] = int(p["hand"]) - 1
		# Keep the turn: score -> shoot again.
	else:
		# Miss / returned ball / gutter: ball is spent, turn passes.
		if gutted:
			p["hand"] = int(p["hand"]) - 1

	# A player who runs out of balls ends the round.
	if int(p["hand"]) <= 0:
		finished = true
		_calc_final()
		match_ended.emit(_snapshot())
		return _snapshot()

	if not is_slot:
		turn = (turn + 1) % players.size()

	state_changed.emit(_snapshot())
	return _snapshot()


## Claim the first empty slot of position `pi` for `color` (board bookkeeping
## used by the final official aggregate).
func _claim_slot(pi: int, color: String) -> void:
	for i in range(board[pi].size()):
		if board[pi][i] == "":
			board[pi][i] = color
			return


## Final scoring: aggregate chain + Grand Slam bonuses via the official engine.
func _calc_final() -> void:
	for p in players:
		var res := RulesEngine.score_board(board)
		p["score"] = int(res["per_color"][p.color])


func _snapshot() -> Dictionary:
	return {
		"turn": turn,
		"players": players.duplicate(true),
		"board": board.duplicate(true),
		"finished": finished,
		"mode": mode,
	}