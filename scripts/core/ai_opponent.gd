class_name AIOpponent
extends RefCounted
## Shot planner for the AI opponent. Uses the analytic ShotMath model + the
## real scoring rules (prefers chaining into positions it already owns, going
## for Grand Slams, avoiding the gutter). Difficulty scales only the aim
## error, never the physics - "no pay-to-win AI".

enum Level { ROOKIE, CLUB, STRATEGIST }

## Per-level aim error (degrees of angle spread + power spread throw).
const AIM_ERROR_DEG := {
	Level.ROOKIE: 14.0,
	Level.CLUB: 7.0,
	Level.STRATEGIST: 2.2,
}
const POWER_ERROR := {
	Level.ROOKIE: 0.35,
	Level.CLUB: 0.18,
	Level.STRATEGIST: 0.06,
}

## board: [[slots_p0], [slots_p1], [slots_p2]], each slot "red"/"black"/"".
## Returns a shot { power, angle, target_pi } aimed at the current best move.
static func plan_shot(rng: RandomNumberGenerator, level: Level, board: Array, my_color: String) -> Dictionary:
	var best_pi := -1
	var best_weight := -1.0
	for pi in range(3):
		var w := _position_weight(pi, board, my_color)
		if w > best_weight:
			best_weight = w
			best_pi = pi
	if best_pi < 0:
		# No colour balls anywhere: play a safe mid shot.
		best_pi = 1

	var power := ShotMath.power_for_slot(best_pi)
	power += rng.randf_range(-POWER_ERROR[level], POWER_ERROR[level])
	power = clampf(power, 0.8, ShotMath.GUTTER_POWER - 0.25)
	var angle := deg_to_rad(rng.randf_range(-AIM_ERROR_DEG[level], AIM_ERROR_DEG[level]))
	return {"power": power, "angle": angle, "target_pi": best_pi}


## Marginal value of shooting at slot band pi: the exact RulesEngine score
## delta of adding one of our balls into the first empty slot of that position
## (chain + grand-slam aware, uses the same engine the game scores with).
static func _position_weight(pi: int, board: Array, my_color: String) -> float:
	var trial := board.duplicate(true)
	var pos := _normalize_position(pi, trial[pi])
	var placed := false
	for i in range(pos.size()):
		if pos[i] == "":
			pos[i] = my_color
			placed = true
			break
	if not placed:
		return -100.0  # position is full: never worth aiming here
	trial[pi] = pos
	var before: int = int(RulesEngine.score_board(board)["per_color"][my_color])
	var after: int = int(RulesEngine.score_board(trial)["per_color"][my_color])
	return float(after - before)


## Accepts both sparse ([ "red", "black" ]) and full position arrays and
## returns the full form padded to that fan's OFFICIAL slit count (7/5/3) -
## v13: every fan has its own width, so a pos3 row is 3 slits, not 7.
static func _normalize_position(pi: int, p: Array) -> Array:
	var out := []
	for s in p:
		out.append(s)
	while out.size() < RulesEngine.POSITION_SLOTS[clampi(pi, 0, 2)]:
		out.append("")
	return out