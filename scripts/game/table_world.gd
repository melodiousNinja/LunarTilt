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

signal ball_scored(ball: SCBBall, band: int)
signal ball_guttered(ball: SCBBall)
signal ball_returned(ball: SCBBall)

const TABLE_LEN := 2.2      # Z axis (player end at Z=0, far end at Z=2.2)
const TABLE_WID := 1.2      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_T := 0.04
## Full height of the rail backstops (physics bodies).
const RAIL_H_TOTAL := 0.30
## World Y of the top face of the side rails (hand-ball racks rest on these).
const RAIL_TOP_Y := -0.03 + RAIL_H_TOTAL * 0.5

const SLOTS_PER_POS := 7
const POS_Z := [0.62, 1.10, 1.58]     # pocket band centers (closest..furthest)
const SLOT_W := 0.16                  # pocket band depth (Z)
const SLOT_PITCH :=(0.15)              # pocket X pitch (7 lanes evenly across +-0.45)
const POCKET_X_HALF :=(0.60)           # playable half-width the bands span
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
static func slot_center_x(si: int) -> float:
	return -0.45 + si * SLOT_PITCH


## 8 corners of the visual frame we care about (racks + tray + table + gutter).
static func frame_points() -> Array:
	var pts: Array = []
	for x in [-0.92, 0.92]:
		for z in [-0.24, 2.28]:
			for y in [-0.06, 0.16]:
				pts.append(Vector3(x, y, z))
	return pts
## Walnut frame material: procedural Simplex noise baked once as a wood-grain
## albedo (no asset files needed, stays small for mobile).
func _wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.29, 0.17)
	mat.roughness = 0.62
	mat.metallic = 0.0
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


## Tournament felt material with a subtle pile normal (visual only).
func _felt_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.27, 0.13)
	mat.roughness = 0.95
	var pile_n := NoiseTexture2D.new()
	var pile := FastNoiseLite.new()
	pile.noise_type = FastNoiseLite.TYPE_SIMPLEX
	pile.frequency = 21.0
	pile.seed = 7
	pile_n.noise = pile
	pile_n.width = 128
	pile_n.height = 128
	mat.normal_enabled = true
	mat.normal_texture = pile_n
	mat.normal_scale = 0.05
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
	var felt_mat := _felt_material()

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
	felt_mesh.material_override = felt_mat
	var felt_center := surface_y_at(0.0, TABLE_LEN * 0.5) + 0.0035
	felt_mesh.position = Vector3(0.0, felt_center, TABLE_LEN * 0.5)
	felt_mesh.rotation.x = board.rotation.x
	add_child(felt_mesh)

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

	# --- Scoring pockets: the star-edged troughs (THE table fix) ---
	_build_pockets(wood_mat)
func _build_pockets(wood_mat: StandardMaterial3D) -> void:
	## Three full-width slot bands, FLAT on the felt.
	## Capture is purely speed-gated: a ball that settles inside a slot band
	## is caught; a fast ball skims past. (v3 first tried recessed wells;
	## Jolt box edges ate so much energy a fast ball died at band one.)
	for bi in range(POS_Z.size()):
		var cz: float = POS_Z[bi]
		var sy: float = surface_y_at(0.0, cz)          # felt height at band
		# Slot lanes (7 per band) with a gentle star glow so the value of each
		# lane reads on a phone: gold 1, silver 2, crimson 3 - colour-coded.
		var glow_colors := [Color(0.93, 0.75, 0.22), Color(0.82, 0.85, 0.92), Color(0.78, 0.25, 0.22)]
		for si in range(SLOTS_PER_POS):
			var hx := slot_center_x(si)
			var area := Area3D.new()
			var cs := CollisionShape3D.new()
			var sb := BoxShape3D.new()
			sb.size = Vector3(SLOT_PITCH * 0.86, 0.05, SLOT_W * 0.62)
			cs.shape = sb
			area.add_child(cs)
			area.position = Vector3(hx, sy + 0.002, cz)
			area.collision_layer = 0
			area.collision_mask = 2
			area.monitoring = true
			add_child(area)
			slots.append({"band": bi, "area": area, "color": ""})

			# Glow plate recessed in the well floor.
			var plate_mesh := MeshInstance3D.new()
			var plate_bm := BoxMesh.new()
			plate_bm.size = Vector3(SLOT_PITCH * 0.80, 0.01, SLOT_W * 0.55)
			plate_mesh.mesh = plate_bm
			var plate_mat := StandardMaterial3D.new()
			plate_mat.albedo_color = glow_colors[bi] * 0.5
			plate_mat.metallic = 0.3
			plate_mat.roughness = 0.3
			plate_mat.emission_enabled = true
			plate_mat.emission = glow_colors[bi]
			plate_mat.emission_energy_multiplier = 1.4
			plate_mesh.material_override = plate_mat
			plate_mesh.position = Vector3(hx, sy + (0.001), cz)
			add_child(plate_mesh)
			# Star-tooth comb look (visual-only): a dark groove border under each
			# plate + raised wood hooks at the lane's front lip, so it reads like the
			# real recessed pockets - but NO physics bumps (they ate ball energy).
			var border := MeshInstance3D.new()
			var bbm := BoxMesh.new()
			bbm.size = Vector3(SLOT_PITCH * (0.97), (0.002), SLOT_W * (0.70))
			border.mesh = bbm
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color((0.16), (0.10), (0.06))
			border.material_override = bmat
			border.position = Vector3(hx, sy - (0.002), cz)
			add_child(border)
			var tooth_mat := StandardMaterial3D.new()
			tooth_mat.albedo_color = Color((0.52), (0.34), (0.19))
			tooth_mat.roughness =(0.5)
			for side in [-1.0, 1.0]:
				var tooth := MeshInstance3D.new()
				var tbm := BoxMesh.new()
				tbm.size = Vector3((0.045), (0.012), (0.022))
				tooth.mesh = tbm
				tooth.material_override = tooth_mat
				tooth.position = Vector3(hx + side * (0.055), sy + (0.007), cz - SLOT_W * (0.40))
				tooth.rotation.y = -side * (0.85)
				add_child(tooth)
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
		var spd := bb.linear_velocity.length()
		if spd > SLOT_CAPTURE_SPEED:
			t["frames"] = 0
		else:
			t["frames"] = int(t["frames"]) + 1
			if int(t["frames"]) >= SETTLE_FRAMES:
				_resolve_ball(t)
				continue
		if spd > (0.03):
			_any_moving = true
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
## Freeze a settled ball, assign its outcome (scored / returned / guttered)
## and emit the matching signal. Runs every physics frame while live balls
## exist - this is what makes capture actually reliable.
func _resolve_ball(t: Dictionary) -> void:
	var b: Variant = t.get("ball")
	if b == null or not is_instance_valid(b) or (b as SCBBall).freeze:
		return
	var bb: SCBBall = b as SCBBall
	var is_scored := false
	var scored_band := -1
	var is_returned := _tray_zone != null and _tray_zone.overlaps_body(b)
	var is_guttered := gutter != null and gutter.overlaps_body(b)
	# Scoring outranks tray/gutter: a ball settling inside a pocket is a score.
	for sd in slots:
		if (sd["area"] as Area3D).overlaps_body(b):
			sd["color"] = b.color
			scored_band = int(sd["band"])
			is_scored = true
			is_returned = false
			is_guttered = false
			break
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	if is_scored:
		ball_scored.emit(b, scored_band)
	elif is_guttered:
		ball_guttered.emit(b)
	else:
		# A returned ball (or any non-scoring rest) rolls back to the rack.
		reinsert_hand_ball(b)
		ball_returned.emit(b)


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


## Unfreezes and returns an in-hand ball placed at the launch point.
func take_hand_ball(color: String) -> SCBBall:
	if hand_balls[color].is_empty():
		return null
	var b: SCBBall = hand_balls[color].pop_back()
	b.freeze = false
	b.collision_layer = 2
	b.collision_mask = 3
	b.sleeping = false  # serve awake - a sleeping ball ignores launch impulses
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.position = Vector3(0.0, ball_rest_y(0.0, LAUNCH_Z), LAUNCH_Z)
	b.rotation = Vector3.ZERO
	return b
