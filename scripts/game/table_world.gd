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

	# --- Front tray (the Returned-Ball rule needs a place to land!) ---
	# LIVE-PROVEN (2026-09 device + bisect): _tray_zone/_tray_floor were
	# declared but NEVER built, so every ball that rolled back off the player
	# end free-fell into the void. The served ball also creeps back down the
	# slope while the player aims and vanishes the same way - the "invisible
	# ball" report. The tray gives returned balls a physical home.
	_build_tray()

	# --- Scoring pockets: the star-edged troughs (THE table fix) ---
	_build_pockets(wood_mat)
const POS_GLOW := [Color(0.93, 0.75, 0.22), Color(0.82, 0.85, 0.92), Color(0.78, 0.25, 0.22)]
const CLAIM_GLOW := {"red": Color(0.95, 0.25, 0.18), "black": Color(0.55, 0.58, 0.65)}


func _build_pockets(_wood_mat: StandardMaterial3D) -> void:
	## The official ASTROLABE look: 21 discrete socket pockets (7 per
	## position), each with a dark comb separator on its edges and hooked
	## teeth at the front lip - the classic Star Cluster Ball table.
	## Physics stays FLAT (v3 proved Jolt box edges eat ball energy): capture
	## is purely the speed-gated Area3D per socket. Each socket keeps its own
	## emissive plate material so a claim recolours it to the owner's ball.
	for bi in range(POS_Z.size()):
		var cz: float = POS_Z[bi]
		var sy: float = surface_y_at(0.0, cz)          # felt height at band
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
			slots.append({"band": bi, "col": si, "area": area, "color": ""})

			# Emissive socket plate - recolours when a ball claims it.
			var plate_mesh := MeshInstance3D.new()
			var plate_bm := BoxMesh.new()
			plate_bm.size = Vector3(SLOT_PITCH * 0.80, 0.01, SLOT_W * 0.55)
			plate_mesh.mesh = plate_bm
			var plate_mat := StandardMaterial3D.new()
			plate_mat.albedo_color = POS_GLOW[bi] * 0.5
			plate_mat.metallic = 0.3
			plate_mat.roughness = 0.3
			plate_mat.emission_enabled = true
			plate_mat.emission = POS_GLOW[bi]
			plate_mat.emission_energy_multiplier = 1.4
			plate_mesh.material_override = plate_mat
			plate_mesh.position = Vector3(hx, sy + 0.001, cz)
			add_child(plate_mesh)

			# Dark wood comb separator on each socket's left edge (the last
			# socket also gets a right edge, so neighbouring sockets never
			# double-draw the same wall) - the classic pocket "hooks".
			var sep_mat := StandardMaterial3D.new()
			sep_mat.albedo_color = Color(0.16, 0.10, 0.06)
			sep_mat.roughness = 0.7
			for side in [-1.0, 1.0]:
				if side < 0.0 or si == SLOTS_PER_POS - 1:
					var sep := MeshInstance3D.new()
					var sm := BoxMesh.new()
					sm.size = Vector3(0.014, 0.016, SLOT_W * 0.72)
					sep.mesh = sm
					sep.material_override = sep_mat
					sep.position = Vector3(hx + side * SLOT_PITCH * 0.5,
						sy + 0.006, cz)
					add_child(sep)

			# Hooked teeth at the pocket's front lip (visual only).
			var tooth_mat := StandardMaterial3D.new()
			tooth_mat.albedo_color = Color(0.52, 0.34, 0.19)
			tooth_mat.roughness = 0.5
			for side in [-1.0, 1.0]:
				var tooth := MeshInstance3D.new()
				var tbm := BoxMesh.new()
				tbm.size = Vector3(0.045, 0.012, 0.022)
				tooth.mesh = tbm
				tooth.material_override = tooth_mat
				tooth.position = Vector3(hx + side * 0.055, sy + 0.007,
					cz - SLOT_W * 0.40)
				tooth.rotation.y = -side * 0.85
				add_child(tooth)
			slots[slots.size() - 1]["plate"] = plate_mat
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
		# Out-of-world guard: a ball that escaped the board (tunneled, knocked
		# over a rail) resolves INSTANTLY as a returned ball instead of hanging
		# the shot until the flush delay.
		if bb.position.y < -0.5 or absf(bb.position.x) > 3.0 or bb.position.z > 3.5:
			_resolve_ball(t)
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
	reinsert_hand_ball(bb)
	ball_returned.emit(bb)


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
	_freeze_in_place(b)

func _freeze_in_place(b: SCBBall) -> void:
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO

func _recolor_plate(sd: Dictionary, color: String) -> void:
	var mat_v: Variant = sd.get("plate")
	if mat_v == null or not (mat_v is StandardMaterial3D):
		return
	var m := mat_v as StandardMaterial3D
	if color == "":
		m.emission = POS_GLOW[clampi(int(sd["band"]), 0, POS_GLOW.size() - 1)]
		m.emission_energy_multiplier = 1.4
	else:
		m.emission = CLAIM_GLOW[color]
		m.emission_energy_multiplier = 2.2


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
	b.position = Vector3(0.0, ball_rest_y(0.0, LAUNCH_Z), LAUNCH_Z)
	b.rotation = Vector3.ZERO
	add_child(b)
	print("SCB serve %s marker at %s" % [color, b.position])
	return b


## Fires the shot: replaces the frozen marker with a FRESH live ball at the
## same transform and gives it its velocity on the very first frame (the
## pattern test A proves safe). Returns the live ball, already tracked by
## the settle-detector. A fresh body never carries stale physics state.
func launch_hand_ball(marker: SCBBall, velocity: Vector3) -> SCBBall:
	if marker == null or not is_instance_valid(marker):
		return null
	var pos: Vector3 = marker.position
	marker.queue_free()
	var b := SCBBall.create(marker.color)
	b.position = pos
	add_child(b)
	b.linear_velocity = velocity
	b.angular_velocity = Vector3.ZERO
	track_live(b)
	print("SCB launch fresh at %s v=%s" % [pos, velocity])
	return b
