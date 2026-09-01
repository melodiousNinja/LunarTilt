class_name RulesEngine
extends Node

## Pure scoring/business logic for Star Cluster Ball (Lunar Tilt).
## No physics here - fully unit-testable. Autoload singleton "Rules".
##
## Reference rules (star-cluster-ball.com/rules, v1.0):
##   - 3 'Astrolabe' positions, 7 slots each:
##       Position 1 (closest) = 1 point/ball
##       Position 2            = 2 points/ball
##       Position 3 (furthest) = 5 points/ball
##   - Chaining: adjacent same-color balls within one position grant a bonus
##       +1 (P1), +2 (P2), +5 (P3) per additional chained ball.
##   - Grand Slam: fill an entire position (7 slots) with one color -> x2 on
##       that position's total. Combines with chaining.
##
## Colors are plain strings ("red"/"black") so this stays engine-agnostic.

const SLOTS_PER_POSITION := 7
const POSITION_COLORS := ["red", "black"]

const BASE_POINTS := {
	"red": [1, 2, 5],
	"black": [1, 2, 5],
}
const CHAIN_BONUS := {
	"red": [1, 2, 5],
	"black": [1, 2, 5],
}


## board = [[pos0_slots], [pos1_slots], [pos2_slots]]
## each slot string = "red" | "black" | "" (empty).
## Chaining follows the official rule: only consecutive same-color balls within
## one position form a chain (+1/+2/+5 per ball after the first in a run).
## Static so tests and gameplay call it without allocating nodes.
## Returns { per_color: {red, black}, breakdown: {red:[...], black:[...]},
##           grand_slams: [...], chain_counts: {...} }
static func score_board(board: Array) -> Dictionary:
	var result := {
		"per_color": {"red": 0, "black": 0},
		"breakdown": {"red": [0, 0, 0], "black": [0, 0, 0]},
		"grand_slams": [],
		"chain_counts": {"red": 0, "black": 0},
	}
	for pi in range(board.size()):
		var slots: Array = board[pi]
		var counts := _count_colors(slots)
		var extras := _chain_extras(slots)
		for color in POSITION_COLORS:
			var n: int = counts[color]
			if n <= 0:
				continue
			var pts: int = n * int(BASE_POINTS[color][pi])
			var chain_bonus: int = int(CHAIN_BONUS[color][pi]) * int(extras[color])
			var grand := (n == SLOTS_PER_POSITION)
			if grand:
				pts *= 2
				result["grand_slams"].append(color)
			result["chain_counts"][color] += int(extras[color])
			var total: int = pts + chain_bonus
			result["per_color"][color] += total
			result["breakdown"][color][pi] = total
	return result


static func _count_colors(slots: Array) -> Dictionary:
	var counts: Dictionary = {"red": 0, "black": 0}
	for s in slots:
		var c := _slot_color(s)
		if c != "":
			counts[c] = int(counts[c]) + 1
	return counts


static func _slot_color(s: Variant) -> String:
	if s is String:
		var lower := String(s).to_lower()
		if lower == "red":
			return "red"
		if lower == "black":
			return "black"
	return ""


## Sum over consecutive same-color runs of (run_length - 1).
## A run broken by a different color or an empty slot restarts.
static func _chain_extras(slots: Array) -> Dictionary:
	var extra: Dictionary = {"red": 0, "black": 0}
	var run: Dictionary = {"red": 0, "black": 0}
	for s in slots:
		var c := _slot_color(s)
		if c == "":
			run = {"red": 0, "black": 0}
			continue
		run[c] = int(run[c]) + 1
		if int(run[c]) >= 2:
			extra[c] = int(extra[c]) + 1
		run["black" if c == "red" else "red"] = 0
	return extra


## From the live game: a shot whose result occupies a position returns true.
static func shot_scored(shot_slots: Array) -> bool:
	for s in shot_slots:
		if s != "":
			return true
	return false