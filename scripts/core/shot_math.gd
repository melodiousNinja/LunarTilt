class_name ShotMath
extends RefCounted
## Analytic shot-prediction math for Lunar Tilt.
## Pure functions (no physics engine) that model the calibrated table:
## deceleration up the 4.99-deg slope is g*sin(4.99) ~= 0.85 m/s^2 (verified by
## tests/test_physics.gd). The scene translates live physics results into the
## same landing outcomes; this class drives AI planning + trajectory preview.
## All values in meters / meters-per-second / radians.

## Effective up-slope deceleration (verified: 2.0 m/s stops near z=1.7).
const DECEL := 0.85
const PLAY_LINE_Z := 0.35
const FAR_GUTTER_Z := 2.02

## Slot band center Z (closest..furthest), matching the world geometry.
const SLOT_Z := [0.62, 1.10, 1.58]
## Slot capture half-depth (z): a ball stopping within +/- of center is caught.
const SLOT_HALF_DEPTH := 0.12

## Max reasonable shot power before the ball definitely gutters.
const GUTTER_POWER := 3.4


static func stop_distance(power: float) -> float:
	return (power * power) / (2.0 * DECEL)


static func landing_z(power: float, angle: float) -> float:
	return PLAY_LINE_Z + cos(angle) * stop_distance(power)


static func lateral_drift(power: float, angle: float) -> float:
	return sin(angle) * stop_distance(power)


static func power_for_distance(dz: float) -> float:
	# dz = distance from the play line up-slope.
	return sqrt(maxf(dz, 0.0) * 2.0 * DECEL)


static func power_for_slot(pi: int) -> float:
	return power_for_distance(SLOT_Z[pi] - PLAY_LINE_Z)


## Z range that lands in slot band pi.
static func slot_capture_z_range(pi: int) -> Vector2:
	var cz: float = SLOT_Z[pi]
	return Vector2(cz - SLOT_HALF_DEPTH, cz + SLOT_HALF_DEPTH)


## Does a ball with this power/angle come to rest inside slot band pi,
## minimising rail-wall risk (x drift kept on the playable width)?
static func lands_in_slot(pi: int, power: float, angle: float) -> bool:
	var z := landing_z(power, angle)
	var rng := slot_capture_z_range(pi)
	var x := lateral_drift(power, angle)
	return z >= rng.x and z <= rng.y and absf(x) < 0.46


static func will_gutter(power: float, angle: float) -> bool:
	# The gutter strip starts just past the far astrolabe; a ball whose
	# stopping distance clears the far rail or crosses into the gutter zone.
	return landing_z(power, angle) >= FAR_GUTTER_Z - 0.06