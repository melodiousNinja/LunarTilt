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
## v13: official slit count per fan position (near fan 7, middle 5, far 3).
## A Grand Slam means a position's FULL slit row is one colour - which also
## requires the row to actually be fan-sized (guards against short test rows
## like [["red"]] counting as an instant "slam").
const POSITION_SLOTS := [7, 5, 3]
const POSITION_COLORS := ["red", "black"]

## v13: fan point values from the close-up of the real table - the three
## astrolabes are labelled 1, 2 and 3 (near -> far).
const BASE_POINTS := {
	"red": [1, 2, 3],
	"black": [1, 2, 3],
}
const CHAIN_BONUS := {
	"red": [1, 2, 3],
	"black": [1, 2, 3],
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
			var grand: bool = (n == slots.size() and slots.size() == int(POSITION_SLOTS[pi]))
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


## v13 fan layout: grooves sit side by side on a fan, so adjacency is LINEAR
## - a slit touches only its immediate left/right neighbours. Computed from
## the row size so every fan width (7/5/3 slits) chains correctly.
static func neighbors_for(col: int, n: int) -> Array:
	var out: Array = []
	if col > 0:
		out.append(col - 1)
	if col < n - 1:
		out.append(col + 1)
	return out


## OFFICIAL GROUPING decision for a ball settling on slit `col` of a fan
## whose slits hold `occupancy` ("" / "red" / "black", slit index order).
## Returns { action: "claim"|"displace"|"block",
##                    displace_col: int (-1 none),
##                    keep_shooting: bool }.
##   - EMPTY slit, no same-colour neighbour  -> claim; the ball STAYS on the
##     table as a blocker and the turn passes.
##   - Same-colour ball in an ADJACENT slit (or already in the target) ->
##     that ball returns to its owner's rack (displacement) and the shooter
##     KEEPS shooting.
##   - Slit walled by the other colour with no own neighbour -> the ball
##     rests against it as a grouping wall; no score, turn passes.
static func resolve_socket(occupancy: Array, col: int, color: String) -> Dictionary:
	var n := occupancy.size()
	if col < 0 or col >= n:
		return {"action": "block", "displace_col": -1, "keep_shooting": false}
	for nb in neighbors_for(col, n):
		if String(occupancy[nb]) == color:
			return {"action": "displace", "displace_col": nb, "keep_shooting": true}
	var occ := String(occupancy[col])
	if occ == "":
		return {"action": "claim", "displace_col": -1, "keep_shooting": false}
	if occ == color:
		return {"action": "displace", "displace_col": col, "keep_shooting": true}
	return {"action": "block", "displace_col": -1, "keep_shooting": false}