class_name TableWorld
extends Node3D

## TableWorld V3 - builds and owns the entire Star Cluster Ball table.
##
## Phase-1 changes that fixed "buggy, unplayable, clunky":
##   * REAL POCKETS. Each Astrolabe position is a star-edged recessed trough
##     cut into the felt - horizontal well floor, tall wood back-stop, pointed
##     star teeth on the front lip that HOOK the ball and hold it. Gone are the
##     flat emissive rectangles the ball could just sit on top of.
##   * SETTLE-BASED CAPTURE. Capture no longer fires at the instant a pocket is
##     entered (which missed balls that arrived fast and THEN settled). A ball
##     is captured only when it comes to rest inside a pocket area, every
##     physics frame. No more phantom scores / "ball sits in pocket doing
##     nothing".
##   * BIGGER BALLS. SCBBall.RADIUS_M = 0.030 (60 mm) so the ball is readable
##     on a phone. Rack channels, tray, and pockets sized for it.
##   * Returned-ball rule: balls that roll back off the player end land in the
##     front tray and are returned to the shooter's rack.

signal ball_scored(ball: SCBBall, band: int, keep_shooting: bool)
signal ball_guttered(ball: SCBBall)
signal ball_returned(ball: SCBBall)
signal ball_displaced(ball: SCBBall)
signal ball_grouped(ball: SCBBall)

const TABLE_LEN := 2.9      # Z axis (player end at Z=0, far end at Z=2.9)
const TABLE_WID := 1.2      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_T := 0.04
## Full height of the rail backstops (physics bodies).
const RAIL_H_TOTAL := 0.30
## World Y of the top face of the side rails (hand-ball racks rest on these).
const RAIL_TOP_Y := -0.03 + RAIL_H_TOTAL * 0.5

const SLOTS_PER_POS := 7
const POS_Z := [0.75, 1.45, 2.15]     # astrolabe medallion centres (near..far)
const MEDAL_R := 0.155                # brass ring radius of one medallion
const CLUSTER_R := 0.096              # hex-flower ring radius (socket centres)
const SOCKET_R := 0.037               # socket cup radius (ball r=0.030 - the cup must be BIGGER so the ball sits visibly in the groove)
const POCKET_X_HALF := 0.60             # playable half-width the bands span
const PLAY_LINE_Z := 0.35
const LAUNCH_Z := 0.22                # ball spawn behind the play line

const BALLS_PER_COLOR := 12

# --- Hand-ball racks (visual side channels, player end) ---
const RACK_X_CENTER := 0.72        # channel center X per side (on the rail tops)
const RACK_W := 0.30               # channel width (X)
const RACK_D := 0.60               # channel depth (Z)
const RACK_Z_START := 0.02
const RACK_PITCH := 0.048          # (60 mm ball + 12 mm gap)

## A ball that has slowed below this while inside a scoring pocket is caught.
const SLOT_CAPTURE_SPEED := 0.35
## Physics frames a ball must linger near-rest before the pocket claims it.
const SETTLE_FRAMES := 3
## True-rest thresholds (2026-09 live feedback): a ball decelerating up the
## slope hovers near zero speed at its arc apex for ~0.8 s; the old blanket
## "slow for 3 frames = settled" resolved it MID-FLIGHT, which is why balls
## vanished and never rolled back. Now only decisive zones (socket / tray /
## gutter) settle in SETTLE_FRAMES; the open felt demands TRUE rest so the
## full up-and-back path plays out and stopped balls persist as obstacles.
const FELT_REST_SPEED := 0.06
const FELT_SETTLE_FRAMES := 24

var board: StaticBody3D
var slots: Array = []        # [{ band:int, area:Area3D, color:String }]
var gutter: Area3D
var _tray_zone: Area3D
var _tray_floor: StaticBody3D
var hand_balls: Dictionary = {"red": [], "black": []}    # frozen in-rack balls

## Live balls the settle-detector tracks (main registers each launched ball).
var live_balls: Array = []
var _tracked: Array = []     # [{ball, frames}] settle-state per live ball
var _any_moving := false     # true if any tracked ball was moving last frame


## World-space height of the board's top surface at (x, z).
## Exact geometry: the box center sits at y=-BOARD_THICK/2, z=TABLE_LEN/2,
## rotated -TILT_DEG around X.
static func surface_y_static(_x: float, z: float) -> float:
	var h: float = BOARD_THICK * 0.5
	var th: float = deg_to_rad(TILT_DEG)
	var cos_t := cos(th)
	var sin_t := sin(th)
	var yp: float = h * (cos_t - 1.0)
	var zp: float = TABLE_LEN * 0.5 - h * sin_t
	return yp + tan(th) * (z - zp)


func surface_y_at(x: float, z: float) -> float:
	return surface_y_static(x, z)


func ball_rest_y(x: float, z: float) -> float:
	return surface_y_static(x, z) + SCBBall.RADIUS_M + 0.002


# ------------------------------------------------------------- pure layout --

static func rack_x(color: String) -> float:
	return -RACK_X_CENTER if color == "red" else RACK_X_CENTER


static func _rack_floor_y(_x: float) -> float:
	return RAIL_TOP_Y + 0.004


## World position of rack ball #index for a color. Pure math so unit tests can
## verify spacing without constructing a physics scene.
static func rack_spot(color: String, index: int) -> Vector3:
	var x := rack_x(color)
	var z := RACK_Z_START + index * RACK_PITCH
	return Vector3(x, _rack_floor_y(x) + SCBBall.RADIUS_M, z)


## X center of slot lane `si` (shared across all three bands). Regression guard:
## v3 briefly spaced lanes 0.42 m apart - half the plates hung off the board.
## World position of socket `si` (0 = centre, 1..6 = hex ring) of position
## `bi`. XZ only - callers add the tilted surface height.
static func socket_pos(bi: int, si: int) -> Vector3:
	var cz: float = POS_Z[clampi(bi, 0, POS_Z.size() - 1)]
	if si <= 0:
		return Vector3(0.0, 0.0, cz)
	var ang := (60.0 * float(si - 1) + 90.0) * PI / 180.0
	return Vector3(cos(ang) * CLUSTER_R, 0.0, cz + sin(ang) * CLUSTER_R)


## 8 corners of the visual frame we care about (racks + tray + table + gutter).
static func frame_points() -> Array:
	var pts: Array = []
	# v6 (2026-09 live feedback "table is so small"): frame the BOARD, not the
	# board + side racks. The racks sit on the rail tops off the play area;
	# including them ate ~40% of the portrait width. x half-extent is now the
	# playable width + rails (0.60 + 0.10), z spans tray to past the far rail.
	for x in [-0.70, 0.70]:
		for z in [-0.26, 2.55]:
			for y in [-0.06, 0.16]:
				pts.append(Vector3(x, y, z))
	return pts
## Walnut frame material: procedural Simplex noise baked once as a wood-grain
## albedo (no asset files needed, stays small for mobile).
func _wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Deep walnut; the grain texture (greyscale noise) modulates it.
	mat.albedo_color = Color(0.20, 0.115, 0.065)
	mat.roughness = 0.38
	mat.metallic = 0.0
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.7
	mat.clearcoat_roughness = 0.22
	var grain := NoiseTexture2D.new()
	var ns := FastNoiseLite.new()
	ns.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ns.frequency = 2.6
	ns.seed = 1337
	grain.noise = ns
	grain.width = 256
	grain.height = 256
	mat.albedo_texture = grain
	return mat


## Factory-spec playing surface: polished white marble with wandering
## grey-blue veins (the real YoTyan table is marble). Procedural shader, so
## it stays crisp at any resolution and needs no texture assets.
func _surface_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/marble.gdshader")
	# Modern broadcast palette: deep slate body with teal veining (player and
	# ball colours pop against it; brass lines read as inlays).
	mat.set_shader_parameter("vein_scale", 4.0)
	# Satin stone, not mirror: at the camera's grazing angle a low-roughness
	# surface Fresnel-reflects the bright sky and washes the body out to white.
	mat.set_shader_parameter("body_col", Color(0.16, 0.20, 0.22))
	mat.set_shader_parameter("vein_col", Color(0.13, 0.40, 0.38))
	mat.set_shader_parameter("rough_min", 0.34)
	mat.set_shader_parameter("rough_max", 0.55)
	return mat


## Short turned pedestal leg under the table (visual only).
func _leg(vx: float, vz: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.05
	cm.height = 0.155
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.20, 0.12)
	mat.roughness = 0.55
	mi.mesh = cm
	mi.material_override = mat
	var top_y := surface_y_at(vx, vz) - 0.055
	mi.position = Vector3(vx, top_y - 0.0775, vz)
	return mi


## Visible rail cap laid on top of each side rail (visual shelf for the racks).
func _rail_cap(side: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.008, TABLE_LEN)
	mi.mesh = bm
	mi.material_override = _wood_material()
	mi.position = Vector3(side * (TABLE_WID / 2.0 + RAIL_T / 2.0), RAIL_TOP_Y + 0.004, TABLE_LEN / 2.0)
	return mi


func _ready() -> void:
	build()
func build() -> void:
	var wood_mat := _wood_material()
	var surface_mat := _surface_material()

	# --- Board physics (4.99 deg tilt: +Z end raised) ---
	board = StaticBody3D.new()
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	bs.shape = box
	board.add_child(bs)
	board.position = Vector3(0.0, -BOARD_THICK * 0.5, TABLE_LEN * 0.5)
	board.rotation.x = -deg_to_rad(TILT_DEG)
	board.collision_layer = 1
	board.collision_mask = 2
	add_child(board)

	var body_mesh := MeshInstance3D.new()
	var body_bm := BoxMesh.new()
	body_bm.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	body_mesh.mesh = body_bm
	body_mesh.material_override = wood_mat
	body_mesh.position = board.position
	body_mesh.rotation.x = board.rotation.x
	add_child(body_mesh)

	# --- Felt playing surface ---
	var felt_mesh := MeshInstance3D.new()
	var felt_bm := BoxMesh.new()
	felt_bm.size = Vector3(TABLE_WID, 0.006, TABLE_LEN)
	felt_mesh.mesh = felt_bm
	felt_mesh.material_override = surface_mat
	var felt_center := surface_y_at(0.0, TABLE_LEN * 0.5) + 0.0035
	felt_mesh.position = Vector3(0.0, felt_center, TABLE_LEN * 0.5)
	felt_mesh.rotation.x = board.rotation.x
	add_child(felt_mesh)

	# --- Guard lines (factory look): brass boundary inlays along both side
	# rails plus a white foul line at the shooting end, laid ON the marble ---
	var brass_inlay := StandardMaterial3D.new()
	brass_inlay.albedo_color = Color(0.72, 0.58, 0.28)
	brass_inlay.metallic = 0.9
	brass_inlay.roughness = 0.28
	var white_inlay := StandardMaterial3D.new()
	white_inlay.albedo_color = Color(0.93, 0.91, 0.86)
	white_inlay.roughness = 0.5
	for side in [-1.0, 1.0]:
		var gl := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.012, 0.0025, TABLE_LEN - 0.12)
		gl.mesh = gm
		gl.material_override = brass_inlay
		var gz := (TABLE_LEN - 0.12) * 0.5 + 0.06
		gl.position = Vector3(side * (TABLE_WID / 2.0 - 0.024),
			surface_y_at(0.0, gz) + 0.0045, gz)
		gl.rotation.x = board.rotation.x
		add_child(gl)
	var foul := MeshInstance3D.new()
	var fm2 := BoxMesh.new()
	fm2.size = Vector3(TABLE_WID - 0.10, 0.0025, 0.016)
	foul.mesh = fm2
	foul.material_override = white_inlay
	var fz := 0.45
	foul.position = Vector3(0.0, surface_y_at(0.0, fz) + 0.0045, fz)
	foul.rotation.x = board.rotation.x
	add_child(foul)

	for lx in [-0.46, 0.46]:
		for lz in [0.32, 0.95, 1.88]:
			add_child(_leg(lx, lz))

	# --- Rails (tall backstops + wood visuals) ---
	var rails := [
		{"size": Vector3(RAIL_T, RAIL_H_TOTAL, TABLE_LEN), "pos": Vector3(-TABLE_WID / 2.0 - RAIL_T / 2.0, -0.03, TABLE_LEN / 2.0)},
		{"size": Vector3(RAIL_T, RAIL_H_TOTAL, TABLE_LEN), "pos": Vector3(TABLE_WID / 2.0 + RAIL_T / 2.0, -0.03, TABLE_LEN / 2.0)},
		{"size": Vector3(TABLE_WID + RAIL_T * 2.0, RAIL_H_TOTAL, RAIL_T), "pos": Vector3(0.0, -0.03, TABLE_LEN + RAIL_T / 2.0)},
	]
	for r in rails:
		var st := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = r.size
		cs.shape = rb
		st.add_child(cs)
		st.position = r.pos
		st.collision_layer = 1
		st.collision_mask = 2
		add_child(st)
		var rail_mesh := MeshInstance3D.new()
		var rail_bm := BoxMesh.new()
		rail_bm.size = r.size
		rail_mesh.mesh = rail_bm
		rail_mesh.material_override = wood_mat
		rail_mesh.position = r.pos
		add_child(rail_mesh)

	# --- Rail caps (shelves that carry the hand-ball racks) ---
	add_child(_rail_cap(-1.0))
	add_child(_rail_cap(1.0))

	# --- Front tray (the Returned-Ball rule needs a place to land!) ---
	# LIVE-PROVEN (2026-09 device + bisect): _tray_zone/_tray_floor were
	# declared but NEVER built, so every ball that rolled back off the player
	# end free-fell into the void. The served ball also creeps back down the
	# slope while the player aims and vanishes the same way - the "invisible
	# ball" report. The tray gives returned balls a physical home.
	_build_tray()

	# --- Scoring sockets: three brass astrolabe medallions (THE factory look) ---
	_build_astrolabes()
	_build_guardlines()
const POS_GLOW := [Color(0.93, 0.75, 0.22), Color(0.82, 0.85, 0.92), Color(0.78, 0.25, 0.22)]
const CLAIM_GLOW := {"red": Color(0.95, 0.25, 0.18), "black": Color(0.55, 0.58, 0.65)}


func _brass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.58, 0.28)
	mat.metallic = 0.95
	mat.roughness = 0.28
	return mat


## THE factory board: three brass astrolabe medallions down the centreline,
## each a circular machine holding 7 real socket cups in a hex-flower cluster
## (1 centre + 6 around). Capture stays the proven speed-gated Area3D; cups
## are visual recesses that claimed balls snap into.
func _build_astrolabes() -> void:
	var brass := _brass_material()
	for bi in range(POS_Z.size()):
		var cz: float = POS_Z[bi]
		var sy: float = surface_y_at(0.0, cz)
		# Recessed dark disc - the machine's face plate.
		var face := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = MEDAL_R - 0.012
		fm.bottom_radius = MEDAL_R - 0.012
		fm.height = 0.006
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_color = Color(0.09, 0.09, 0.105)
		face_mat.metallic = 0.35
		face_mat.roughness = 0.55
		face.mesh = fm
		face.material_override = face_mat
		face.position = Vector3(0.0, sy - 0.002, cz)
		add_child(face)
		# Brass ring frame.
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = MEDAL_R - 0.016
		rm.outer_radius = MEDAL_R
		ring.mesh = rm
		ring.material_override = brass
		ring.position = Vector3(0.0, sy + 0.002, cz)
		add_child(ring)
		# Point value etched on the table in front of the medallion.
		var lbl := Label3D.new()
		lbl.text = ["1", "2", "5"][bi]
		lbl.modulate = POS_GLOW[bi]
		lbl.font_size = 96
		lbl.pixel_size = 0.0006
		lbl.outline_size = 0
		lbl.rotation_degrees = Vector3(-84.0, 0.0, 0.0)
		lbl.position = Vector3(0.0, sy + 0.004, cz - MEDAL_R - 0.035)
		add_child(lbl)
		for si in range(SLOTS_PER_POS):
			var sp := socket_pos(bi, si)
			# Capture area (speed-gated settle logic picks this up).
			var area := Area3D.new()
			var cs := CollisionShape3D.new()
			var sb := SphereShape3D.new()
			sb.radius = SOCKET_R + 0.014
			cs.shape = sb
			area.add_child(cs)
			area.position = Vector3(sp.x, sy + 0.012, sp.z)
			area.collision_layer = 0
			area.collision_mask = 2
			area.monitoring = true
			add_child(area)
			# The socket cup: a REAL recessed groove - dark bowl sunk below the
			# marble with a brass rim, so a captured ball visibly sits IN it.
			var cup := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = SOCKET_R
			cm.bottom_radius = SOCKET_R * 0.72
			cm.height = 0.010
			var cup_mat := StandardMaterial3D.new()
			cup_mat.albedo_color = Color(0.05, 0.05, 0.06)
			cup_mat.metallic = 0.5
			cup_mat.roughness = 0.4
			cup.mesh = cm
			cup.material_override = cup_mat
			cup.position = Vector3(sp.x, sy - 0.007, sp.z)  # top 2 mm BELOW marble = a true recess
			add_child(cup)
			var rim := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = SOCKET_R - 0.004
			tm.outer_radius = SOCKET_R + 0.006
			rim.mesh = tm
			rim.material_override = brass
			rim.position = Vector3(sp.x, sy - 0.0045, sp.z)  # torus top flush with the marble (inlaid ring, no proud lip)
			add_child(rim)
			slots.append({"band": bi, "col": si, "area": area, "color": "",
				"cup": cup_mat})


## Brass guardline inlays up both edges of the playfield (the factory table's
## etched border lines). Segmented so each piece hugs the 5-degree tilt.
func _build_guardlines() -> void:
	var brass := _brass_material()
	var y_far := surface_y_at(0.0, TABLE_LEN)
	var y_near := surface_y_at(0.0, 0.0)
	var slope := atan2(y_far - y_near, TABLE_LEN)
	var segs := 8
	var seg_len := (TABLE_LEN - 0.20) / float(segs)
	for side in [-1.0, 1.0]:
		var x_edge: float = side * (TABLE_WID / 2.0 - 0.035)
		for i in range(segs):
			var z_mid := 0.10 + seg_len * (float(i) + 0.5)
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.010, 0.0025, seg_len)
			seg.mesh = bm
			seg.material_override = brass
			seg.position = Vector3(x_edge, surface_y_at(x_edge, z_mid) + 0.002, z_mid)
			seg.rotation.x = -slope
			add_child(seg)
## The player-end tray: returned balls land here and are re-racked.
## Floor top at y=-0.13 (the height test A's comment always assumed), walls
## on all open sides so a returned ball rests instead of escaping.
func _build_tray() -> void:
	var wood_mat := _wood_material()
	var bodies := [
		# floor: x -0.64..0.64, top at -0.13, z -0.26..0.0
		{"size": Vector3(1.28, 0.04, 0.26), "pos": Vector3(0.0, -0.15, -0.13)},
		# front wall (player side)
		{"size": Vector3(1.28, 0.12, 0.04), "pos": Vector3(0.0, -0.09, -0.24)},
		# side walls
		{"size": Vector3(0.04, 0.12, 0.26), "pos": Vector3(-0.62, -0.09, -0.13)},
		{"size": Vector3(0.04, 0.12, 0.26), "pos": Vector3(0.62, -0.09, -0.13)},
	]
	for r in bodies:
		var st := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = r.size
		cs.shape = rb
		st.add_child(cs)
		st.position = r.pos
		st.collision_layer = 1
		st.collision_mask = 2
		add_child(st)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = r.size
		mi.mesh = bm
		mi.material_override = wood_mat
		mi.position = r.pos
		add_child(mi)
	# Return-detection zone hovering over the tray floor.
	_tray_zone = Area3D.new()
	var zs := CollisionShape3D.new()
	var zb := BoxShape3D.new()
	zb.size = Vector3(1.2, 0.10, 0.22)
	zs.shape = zb
	_tray_zone.add_child(zs)
	_tray_zone.position = Vector3(0.0, -0.10, -0.13)
	_tray_zone.collision_layer = 0
	_tray_zone.collision_mask = 2
	_tray_zone.monitoring = true
	add_child(_tray_zone)
	# Deep GUTTER (official rule: a ball that overshoots the last astrolabe is
	# lost). SESSION-PROVEN (2026-09-05, 29-shot live session): balls reached
	# z=3.09 past the far rail but the gutter was never built (the var stayed
	# null) so zero shots ever guttered - they all came back as returned.
	# Full-width catch volume: z 2.50..3.45, y -0.40..+0.32 (catches rolling
	# AND flying balls that clear the deep end).
	gutter = Area3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(1.34, 0.72, 0.95)
	gs.shape = gb
	gutter.add_child(gs)
	gutter.position = Vector3(0.0, -0.04, 2.975)
	gutter.collision_layer = 0
	gutter.collision_mask = 2
	gutter.monitoring = true
	add_child(gutter)


func _physics_process(_delta: float) -> void:
	if _tracked.size() == 0:
		return
	_any_moving = false
	var still: Array = []
	for t in _tracked:
		var b: Variant = t.get("ball")
		if b == null or not is_instance_valid(b):
			continue
		var bb := b as SCBBall
		if bb.freeze:
			continue
		# Deep-zone rule: anything past the last astrolabe (z > 2.5) is in the
		# gutter - resolve IMMEDIATELY so overpowered shots are claimed as
		# lost, not returned (the gutter area overlap in _resolve_ball rates it).
		if bb.position.z > 2.5:
			_resolve_ball(t)
			continue
		# Out-of-world guard: a ball that escaped the board (tunneled, knocked
		# over a rail) resolves INSTANTLY as a returned ball instead of hanging
		# the shot until the flush delay.
		if bb.position.y < -0.5 or absf(bb.position.x) > 3.0 or bb.position.z > 3.5:
			_resolve_ball(t)
			continue
		var spd := bb.linear_velocity.length()
		if spd > (0.03):
			_any_moving = true
		# Socket funnel: inside a cup, a gentle centre-pull + damping dips the
		# ball into the groove so slow balls visibly get CAUGHT by the pocket.
		# Speed-gated: a ball faster than the capture speed skims the groove
		# untouched - the funnel must never bend a fast shot's path.
		var near := _socket_overlapping(bb)
		if not near.is_empty() and spd <= SLOT_CAPTURE_SPEED:
			var center: Vector3 = (near["area"] as Area3D).global_position
			var to_c := center - bb.global_position
			to_c.y = 0.0
			if to_c.length() > 0.001:
				bb.apply_central_force(to_c.normalized() * bb.mass * 1.6)
			bb.linear_velocity *= 0.985
		# Zone-aware settle (see FELT_REST_SPEED above): decisive zones settle
		# fast; open felt requires true rest so roll-backs finish their arc.
		if spd > FELT_REST_SPEED:
			t["frames"] = 0
			t["anchor"] = bb.position
			still.append(t)
			continue
		t["frames"] = int(t["frames"]) + 1
		if t.get("anchor") == null:
			t["anchor"] = bb.position
		# OPEN FELT: the sport's path rule - a ball that fails to reach a
		# groove keeps its FULL arc: it rolls back down to the player's tray.
		# We never freeze a ball mid-board. If the engine's static friction
		# pins it on the slope (mu > tan 5 deg), nudge it down-slope; only a
		# ball still pinned after 3 nudges is resolved (as a returned ball).
		if _socket_overlapping(bb).is_empty() \
				and not (_tray_zone != null and _tray_zone.overlaps_body(b)) \
				and not (gutter != null and gutter.overlaps_body(b)):
			var anchor: Variant = t.get("anchor")
			var pinned := anchor != null \
					and (bb.position - (anchor as Vector3)).length() <= 0.004
			if not pinned:
				t["frames"] = 0
				t["anchor"] = bb.position
				t["nudges"] = 0
				still.append(t)
				continue
			t["nudges"] = int(t.get("nudges", 0)) + 1
			if int(t["nudges"]) <= 3:
				bb.sleeping = false
				bb.apply_central_impulse(Vector3(0.0, 0.0, -0.4) * bb.mass)
				t["frames"] = 0
				t["anchor"] = bb.position
				still.append(t)
				continue
			_resolve_ball(t)
			continue
		if int(t["frames"]) >= SETTLE_FRAMES:
			_resolve_ball(t)
			continue
		still.append(t)
	_tracked = still


func _inside_slot_area(b: SCBBall) -> bool:
	for sd in slots:
		if (sd["area"] as Area3D).overlaps_body(b):
			return true
	return false


## Force-resolve every tracked ball right now(((safety: main calls this when a shot
## stalls without emitting outcome signals,and every trailing ball needs a terminal
## state so the turn can pass. Balls resting in a slot score; anything else
## is treated as a returned ball per the sport's rule.
func flush_live() -> void:
	var pending: Array = _tracked.duplicate()
	for t in pending:
		_resolve_ball(t)
## Resolve a settled ball with the OFFICIAL outcome precedence:
##   1. Gutter            -> lost, turn passes.
##   2. Tray (rolled back)-> Returned-Ball rule, back to the rack, free shot.
##   3. Socket            -> official GROUPING rules via RulesEngine:
##        claim empty socket  -> ball STAYS as a blocker, scored, turn passes
##        adjacent own ball   -> that ball returns to its rack (displacement),
##                               shooter KEEPS shooting
##        walled by opponent  -> ball rests as a grouping wall, turn passes
##   4. Open felt         -> Returned-Ball rule (never-scored balls roll back).
## Every branch gives the ball a terminal state, so a turn can never hang.
func _resolve_ball(t: Dictionary) -> void:
	var b: Variant = t.get("ball")
	if b == null or not is_instance_valid(b) or (b as SCBBall).freeze:
		return
	var bb: SCBBall = b as SCBBall
	var is_returned := _tray_zone != null and _tray_zone.overlaps_body(b)
	var is_guttered := gutter != null and gutter.overlaps_body(b)
	if is_guttered:
		_freeze_in_place(bb)
		ball_guttered.emit(bb)
		return
	if is_returned:
		reinsert_hand_ball(bb)
		ball_returned.emit(bb)
		return
	var sd := _socket_overlapping(b)
	if not sd.is_empty():
		var occ := _occupancy(int(sd["band"]))
		var dec := RulesEngine.resolve_socket(occ, int(sd["col"]), bb.color)
		var action := String(dec["action"])
		if action == "block":
			# No empty socket and no same-colour neighbour: the ball rests
			# against the occupied pocket as a grouping wall. Turn passes.
			_freeze_in_place(bb)
			ball_grouped.emit(bb)
			return
		if action == "displace":
			var nb := _take_socket_ball(int(sd["band"]), int(dec["displace_col"]))
			if nb != null:
				reinsert_hand_ball(nb)
				ball_displaced.emit(nb)
		_claim_socket(sd, bb)
		ball_scored.emit(bb, int(sd["band"]), bool(dec["keep_shooting"]))
		return
	# Open felt: the ball STAYS on the table as a live obstacle (2026-09 live
	# feedback: resolving it back to the rack made balls vanish mid-board and
	# left the table empty - players expect the full up-and-back path to
	# persist and later shots to clash with resting balls).
	_freeze_in_place(bb)
	ball_grouped.emit(bb)  # main plays the block sound (single SFX source)


## Safe sound hook: the Sfx autoload is absent in headless test runs, so
## resolve it lazily instead of by global identifier (keeps tests parseable).
func _sfx(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	var snd := get_node_or_null("/root/Sfx")
	if snd != null:
		snd.play(name, pitch, vol_db)


## ---- official socket ownership / grouping helpers (2026-09 rules pass) ----

## "band:col" -> the SCBBall currently claiming that socket.
var socket_balls := {}

func _socket_overlapping(b: SCBBall) -> Dictionary:
	for sd in slots:
		if (sd["area"] as Area3D).overlaps_body(b):
			return sd
	return {}

func _socket_at(band: int, col: int) -> Dictionary:
	for sd in slots:
		if int(sd["band"]) == band and int(sd["col"]) == col:
			return sd
	return {}

## Occupancy of one position's 7 sockets, in column order (creation order).
func _occupancy(band: int) -> Array:
	var occ: Array = []
	for sd in slots:
		if int(sd["band"]) == band:
			occ.append(String(sd["color"]))
	return occ

func _socket_key(band: int, col: int) -> String:
	return "%d:%d" % [band, col]

## Removes the ball claiming a socket (returns it; caller re-racks it) and
## frees the socket for a new claim.
func _take_socket_ball(band: int, col: int) -> SCBBall:
	var key := _socket_key(band, col)
	var ball_v: Variant = socket_balls.get(key)
	socket_balls.erase(key)
	if ball_v != null and is_instance_valid(ball_v):
		var sd := _socket_at(band, col)
		if not sd.is_empty():
			sd["color"] = ""
			_recolor_plate(sd, "")
		return ball_v as SCBBall
	return null

## A claimed socket: the ball freezes IN the pocket as a permanent blocker
## and the socket glows in the owner's colour.
func _claim_socket(sd: Dictionary, b: SCBBall) -> void:
	sd["color"] = b.color
	_recolor_plate(sd, b.color)
	socket_balls[_socket_key(int(sd["band"]), int(sd["col"]))] = b
	# Snap the ball visually INTO its cup (half-sunk like a pocketed ball).
	var sp := socket_pos(int(sd["band"]), int(sd["col"]))
	var sy := surface_y_at(sp.x, sp.z)
	b.position = Vector3(sp.x, sy + SCBBall.RADIUS_M * 0.55, sp.z)
	_freeze_in_place(b)

func _freeze_in_place(b: SCBBall) -> void:
	b.freeze = true
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	# KEEP collision layers (2026-09 live feedback: frozen balls were ghosts -
	# live shots flew straight through every claimed ball). A frozen body is
	# static; layer 2 / mask 3 keeps it a solid, hittable obstacle so later
	# shots clack into it, knock it around, and the board reads as a real game.
	b.collision_layer = 2
	b.collision_mask = 3

func _recolor_plate(sd: Dictionary, color: String) -> void:
	var mat_v: Variant = sd.get("cup")
	if mat_v == null or not (mat_v is StandardMaterial3D):
		return
	var m := mat_v as StandardMaterial3D
	if color == "":
		m.albedo_color = Color(0.05, 0.05, 0.06)
		m.emission_enabled = false
	else:
		m.albedo_color = CLAIM_GLOW[color] * 0.55
		m.emission_enabled = true
		m.emission = CLAIM_GLOW[color]
		m.emission_energy_multiplier = 0.9


## Track a freshly-launched ball so the settle-detector resolves it.
func track_live(b: SCBBall) -> void:
	if b != null and not _tracked.has(b):
		live_balls.append(b)
		_tracked.append({"ball": b, "frames": 0})


## True while any tracked (live) ball is still moving. main waits for this
## before resolving a shot.
func any_moving() -> bool:
	return _any_moving


func lane_at(band: int) -> int:
	return SLOTS_PER_POS


func slot_at(index: int) -> Dictionary:
	return slots[index]


func _slot_area_index(a: Area3D) -> int:
	for i in range(slots.size()):
		if slots[i]["area"] == a:
			return i
	return -1


func spawn_hand_ball(color: String) -> SCBBall:
	var b := SCBBall.create(color)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	var n: int = int((hand_balls[color] as Array).size())
	b.position = rack_spot(color, n)
	add_child(b)
	hand_balls[color].append(b)
	return b


## Re-racks a ball that rolled back into the tray (Returned-Ball rule).
func reinsert_hand_ball(b: SCBBall) -> void:
	if not is_instance_valid(b):
		return
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	var arr: Array = hand_balls[b.color]
	if not arr.has(b):
		arr.append(b)
	b.position = rack_spot(b.color, arr.size() - 1)
	b.rotation = Vector3.ZERO


## Serve lane alternation (2026-09 live feedback / duel feel): each serve
## flips side, so the player shoots from the bottom-left lane, then the
## bottom-right, alternating like the real sport's lane rule.
var serve_side := 1.0

## Serves an in-hand ball as a FROZEN MARKER at the launch point.
## LIVE-PROVEN (2026-09 device telemetry + headless bisect): a LIVE ball at
## the launch spot creeps back down the 5-degree slope while the player aims,
## rolls off the board's front edge (there was no tray), and free-falls into
## the void - the "invisible ball" that every shot then fired at (y -15 m and
## -92 m at release). The marker cannot move; launch_hand_ball turns it into
## a fresh live ball at the exact same transform at release time.
func take_hand_ball(color: String) -> SCBBall:
	if hand_balls[color].is_empty():
		return null
	var pooled: SCBBall = hand_balls[color].pop_back()
	if pooled != null and is_instance_valid(pooled):
		pooled.queue_free()
	var b := SCBBall.create(color)
	b.freeze = true          # display marker - cannot creep, cannot fall
	b.collision_layer = 0
	b.collision_mask = 0
	# TRANSFORM BEFORE add_child (Jolt must register it at the launch spot).
	serve_side = -serve_side
	var sx := 0.40 * serve_side
	b.position = Vector3(sx, ball_rest_y(sx, LAUNCH_Z), LAUNCH_Z)
	b.rotation = Vector3.ZERO
	add_child(b)
	print("SCB serve %s marker side=%.1f at %s" % [color, serve_side, b.position])
	return b


## Fires the shot: replaces the frozen marker with a FRESH live ball at the
## same transform and gives it its velocity on the very first frame (the
## pattern test A proves safe). Returns the live ball, already tracked by
## the settle-detector. A fresh body never carries stale physics state.
func launch_hand_ball(marker: SCBBall, velocity: Vector3) -> SCBBall:
	if marker == null or not is_instance_valid(marker):
		return null
	var pos: Vector3 = marker.position
	var ball_color: String = marker.color
	marker.queue_free()
	var b := SCBBall.create(ball_color)
	b.position = pos
	add_child(b)
	b.linear_velocity = velocity
	b.angular_velocity = Vector3.ZERO
	track_live(b)
	print("SCB launch fresh at %s v=%s" % [pos, velocity])
	return b
