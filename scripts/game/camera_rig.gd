class_name CameraRig
extends RefCounted

## Deterministic broadcast-style camera rig (v2).
##
## Frames the whole Star Cluster Ball play area (racks + table + tray depth)
## inside the viewport at ANY aspect ratio. Pure math, so it is fully
## unit-testable (tests/test_v2_layout.gd).
##
## Approach: choose a pitch from the aspect, then binary-search the minimal
## camera distance for which ALL 8 corners of the table's world-frame bounding
## box project inside the vertical AND horizontal FOV half-planes. This
## guarantees the table is never cropped on any device - the exact defect the
## v1 hardcoded pose produced.

const MIN_DIST := 0.6
const MAX_DIST := 16.0
## Frame margin: we target 88% of the available angle so the table never
## touches the screen edges (content breathing room).
const FILL := 0.88


## Pitch for a given aspect (w/h). Portrait (narrow) -> steeper so the deep
## table reads top-to-bottom; wide screens flatten toward the broadcast edit.
static func pitch_for_aspect(aspect: float) -> float:
	var t := clampf((aspect - 0.46) / (1.9 - 0.46), 0.0, 1.0)
	return lerpf(37.0, 22.0, t)


## Camera position for a pitch (deg below horizontal) and distance back from
## the look target, on the -Z side looking up the table (yaw 0).
static func cam_pos(pitch_deg: float, distance: float, look_target: Vector3) -> Vector3:
	var p := deg_to_rad(pitch_deg)
	var forward := Vector3(0.0, -sin(p), cos(p)).normalized()
	return look_target - forward * distance


## Camera basis matching Godot's look_at(look_target, Vector3.UP).
static func cam_basis(look_target: Vector3, cam_pos: Vector3) -> Basis:
	return Basis.looking_at(look_target - cam_pos, Vector3.UP)


## True when every point projects inside the frustum (with FILL margin on the
## smaller axis). Points are world-space corner pairs; aspect = w/h.
static func fits(points: Array, look_target: Vector3, cam_p: Vector3, basis: Basis,
		fov_v: float, aspect: float) -> bool:
	var fov_v_rad := deg_to_rad(fov_v)
	var tan_v := tan(fov_v_rad * 0.5) * FILL
	var tan_h := tan(fov_v_rad * 0.5) * aspect * FILL
	var inv := basis.inverse()
	for pt: Vector3 in points:
		var rel := inv * (pt - cam_p)
		# Camera looks along its local -Z (Basis.looking_at), so depth is -rel.z.
		if rel.z >= -0.02:
			return false
		var depth := -rel.z
		if absf(rel.x) > tan_h * depth or absf(rel.y) > tan_v * depth:
			return false
	return true


## Minimum distance so that all corners are inside both FOV planes. Bisection,
## deterministic to <1%. Returns MAX_DIST if the fit is impossible.
static func fit_distance(points: Array, fov_v: float, aspect: float,
		pitch_deg: float, look_target: Vector3 = Vector3(0.0, 0.02, 0.98)) -> float:
	var lo := MIN_DIST
	var hi := MAX_DIST
	for i in range(40):
		var mid := (lo + hi) * 0.5
		if _fits_at(points, mid, fov_v, aspect, pitch_deg, look_target):
			hi = mid
		else:
			lo = mid
	return hi


static func _fits_at(points: Array, dist: float, fov_v: float, aspect: float,
		pitch_deg: float, look_target: Vector3) -> bool:
	var cp := cam_pos(pitch_deg, dist, look_target)
	var basis := cam_basis(look_target, cp)
	return fits(points, look_target, cp, basis, fov_v, aspect)