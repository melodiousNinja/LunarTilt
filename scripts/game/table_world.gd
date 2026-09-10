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

const TABLE_LEN := 4.35     # Z axis (player end at Z=0, far end at Z=4.35)
const TABLE_WID := 1.8      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_T := 0.04
## Full height of the rail backstops (physics bodies).
const RAIL_H_TOTAL := 0.30
## World Y of the top face of the side rails.
const RAIL_TOP_Y := -0.03 + RAIL_H_TOTAL * 0.5
## Gutter/trench geometry, all expressed relative to TABLE_LEN/TABLE_WID so
## the deep-end catch zone always sits just past the far rail regardless of
## table size (kept the exact old offsets: these formulas reproduce the
## original literals 2.7/3.5/2.6/3.4/3.075/2.95/3.48 at TABLE_LEN=2.9).
const GUTTER_ALTITUDE_Z := TABLE_LEN + 0.05
const ESCAPE_Z := TABLE_LEN + 0.6
const GUTTER_CLAMP_MIN_Z := TABLE_LEN - 0.3
const GUTTER_CLAMP_MAX_Z := TABLE_LEN + 0.5
const GUTTER_AREA_Z := TABLE_LEN + 0.45
const TRENCH_Z := TABLE_LEN + 0.05
const TRENCH_BACK_Z := TABLE_LEN + 0.58
const GUTTER_X_HALF := TABLE_WID * 0.5 + 0.05
const GUTTER_FULL_W := TABLE_WID + 0.14

const SLOTS_PER_POS := 7              # deprecated alias (band 0 slit count)
## 2026-09-08 user rule: even more room between fans - gaps widened again
## from 0.75 m to 1.0 m between fan centres, and the table lengthened to
## keep the far fan a healthy 0.55 m clear of the far rail.
const POS_Z := [1.80, 2.80, 3.80]     # astrolabe fan centres
const MEDAL_R := 0.155                # deprecated alias
const CLUSTER_R := 0.096              # deprecated alias
const SOCKET_R := 0.037               # deprecated alias (ball r = 0.030)
## v13 FAN ASTROLABES (2026-09-06 close-up of the real table): each scoring
## position is a raised wooden FAN - solid blades with open GROOVE SLITS
## between them, mouths facing the thrower, standing on pins. A ball that
## rolls into a slit is caught by its walls + back wall (real geometry, no
## funnel); a ball that clips a blade DEFLECTS off the raised edge. Slit
## counts from the close-up: near fan 7 (1 pt), middle 5 "C B A C B" (2 pt),
## far 3 "B A B" (3 pt).
const FAN_GAPS := [7, 5, 3]
const FAN_POINTS := [1, 2, 3]
const FAN_MOUTH := [0.088, 0.092, 0.096]   # one 84 mm ball fills a hook
                                           # snugly (owner rule: the ball
                                           # completely fills the spike gap)
const FAN_BLADE := [0.026, 0.032, 0.042]   # solid wood between slits
const FAN_DEPTH := [0.22, 0.24, 0.26]      # mouth-to-front-wall depth
const FAN_H := 0.016                       # platform height above the marble
## Connector height tiers (2026-09-11 owner rule): the wooden spikes protrude
## ABOVE the crown of a seated ball (ball radius 0.042) so an occupied gap
## physically cannot be re-filled - a new ball clips the protruding spikes
## and bounces off. A tier tallest, then B, C, D at the outer edges.
const PEG_H_TIERS := [0.062, 0.056, 0.050, 0.044]   # all > ball radius 0.042
const PLATE_H := 0.010
const PLATE_NAMES := ["ONE", "TWO", "THREE"]
const POCKET_X_HALF := 0.60             # playable half-width the bands span
const PLAY_LINE_Z := 0.35
const LAUNCH_Z := 0.22                # ball spawn behind the play line

const BALLS_PER_COLOR := 12

# --- Hand-ball ammo (2026-09-08 user rule: stack the spare balls in a
# horizontal row at the bottom of the table, behind the tray, instead of in
# vertical channels beside the table - that freed up the side space used to
# widen the playable board). ---
const AMMO_ROW_Z := -0.38          # Z of the ammo shelf row (behind the tray)
const AMMO_GAP_X := 0.06           # gap from centerline to the first ball
const AMMO_SHELF_TOP_Y := -0.13    # shelf top height (matches the tray floor)
const RACK_PITCH := 0.092          # 84 mm ball + breathing room

## A ball that has slowed below this while inside a scoring pocket is caught.
const SLOT_CAPTURE_SPEED := 0.35
## v12 DECISIVE CUP CAPTURE (2026-09 device session: 8 shots, 0 scores -
## the old funnel pulled with mass*1.6 and damped 1.5%/frame, so a ball
## crossing the 10 cm well zone at 0.4 m/s sailed through in 6 frames).
## A ball inside a well zone slower than this DROPS INTO THE CUP; faster
## balls are hauled by the strong funnel until they drop below it.
const CAPTURE_SPEED := 0.9
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

## +1 for black (right of centerline), -1 for red (left of centerline).
static func rack_side(color: String) -> float:
	return -1.0 if color == "red" else 1.0


static func _rack_floor_y(_x: float) -> float:
	return AMMO_SHELF_TOP_Y + 0.004


## World position of ammo ball #index for a color: a horizontal row behind
## the tray (2026-09-08 user rule), red growing left from the centerline,
## black growing right. Pure math so unit tests can verify spacing without
## constructing a physics scene.
static func rack_spot(color: String, index: int) -> Vector3:
	var side := rack_side(color)
	var x := side * (AMMO_GAP_X + float(index) * RACK_PITCH)
	return Vector3(x, _rack_floor_y(x) + SCBBall.RADIUS_M, AMMO_ROW_Z)


## Width of fan `bi`: (G+1) blades + G slit mouths.
static func fan_width(bi: int) -> float:
	var b := clampi(bi, 0, 2)
	return float(FAN_GAPS[b] + 1) * FAN_BLADE[b] + float(FAN_GAPS[b]) * FAN_MOUTH[b]

## World XZ of groove gap `si` (0 = leftmost) of fan `bi` - the gap centre
## between spike `si` and spike `si+1` on the arc. Callers add surface height.
static func socket_pos(bi: int, si: int) -> Vector3:
	var b := clampi(bi, 0, 2)
	var cz: float = POS_Z[b]
	var g: int = FAN_GAPS[b]
	var col := clampi(si, 0, g - 1)
	var fw := fan_width(b)
	var gx := -fw * 0.5 + (float(col) + 0.5) / float(g) * fw
	return Vector3(gx, 0.0, cz)


## 8 corners of the visual frame we care about (table + ammo shelf + gutter).
static func frame_points() -> Array:
	var pts: Array = []
	# v7 (2026-09-08 user rule: racks moved off the sides onto a horizontal
	# ammo shelf behind the tray, and the board itself got wider/longer).
	# x half-extent is the playable width + rails; z spans the ammo shelf to
	# just past the far fan.
	for x in [-(TABLE_WID * 0.5 + 0.10), TABLE_WID * 0.5 + 0.10]:
		for z in [-0.50, POS_Z[2] + 0.35]:
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


## Selectable table surface skins (2026-09-07 user rule: default look must
## match the real broadcast table - a bright white/cream glossy surface, not
## dark stone). "dark_marble" keeps the earlier broadcast-slate alt look for
## players who want a cosmetic swap later; it is not the default.
const SURFACE_SKINS := {
	"cream": {
		"body": Color(0.93, 0.91, 0.86), "vein": Color(0.82, 0.79, 0.72),
		"rough_min": 0.18, "rough_max": 0.34,
	},
	"dark_marble": {
		"body": Color(0.21, 0.24, 0.27), "vein": Color(0.13, 0.40, 0.38),
		"rough_min": 0.34, "rough_max": 0.55,
	},
}
var surface_skin := "cream"

## Factory-spec playing surface: procedural shader (no texture assets needed)
## so any skin stays crisp at any resolution.
func _surface_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/marble.gdshader")
	var skin: Dictionary = SURFACE_SKINS.get(surface_skin, SURFACE_SKINS["cream"])
	mat.set_shader_parameter("vein_scale", 4.0)
	mat.set_shader_parameter("body_col", skin["body"])
	mat.set_shader_parameter("vein_col", skin["vein"])
	mat.set_shader_parameter("rough_min", skin["rough_min"])
	mat.set_shader_parameter("rough_max", skin["rough_max"])
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

	for lx in [-(TABLE_WID * 0.5 - 0.14), TABLE_WID * 0.5 - 0.14]:
		for lz in [0.45, 2.15, 3.85]:
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

	# --- Front tray (the Returned-Ball rule needs a place to land!) ---
	# LIVE-PROVEN (2026-09 device + bisect): _tray_zone/_tray_floor were
	# declared but NEVER built, so every ball that rolled back off the player
	# end free-fell into the void. The served ball also creeps back down the
	# slope while the player aims and vanishes the same way - the "invisible
	# ball" report. The tray gives returned balls a physical home.
	_build_tray()
	# --- Ammo shelf (2026-09-08 user rule): the spare-ball racks moved off
	# the sides onto a horizontal shelf behind the tray, freeing the side
	# space used above to widen the board.
	_build_ammo_shelf()

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


## Procedural half-disc plank: flat edge at local +Z (the back), arc bulging
## toward local -Z (the bowl mouth facing the thrower).
func _half_disc_mesh(radius: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var y0 := -thick * 0.5
	var y1 := thick * 0.5
	var prev := Vector3(radius, 0, 0)
	for i in range(1, segs + 1):
		var a := PI * float(i) / float(segs)
		var nxt := Vector3(cos(a) * radius, 0, -sin(a) * radius)
		# top face fan
		st.add_vertex(Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y1, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		# bottom face fan (reversed)
		st.add_vertex(Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y0, 0))
		st.add_vertex(prev + Vector3(0, y0, 0))
		# arc rim wall
		st.add_vertex(prev + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y1, 0))
		prev = nxt
	# flat back face (the diameter)
	st.add_vertex(Vector3(-radius, y0, 0))
	st.add_vertex(Vector3(radius, y0, 0))
	st.add_vertex(Vector3(radius, y1, 0))
	st.add_vertex(Vector3(-radius, y0, 0))
	st.add_vertex(Vector3(radius, y1, 0))
	st.add_vertex(Vector3(-radius, y1, 0))
	st.generate_normals()
	return st.commit()


## v15.1 FAN ASTROLABES - corrected per the owner's last-try feedback:
## gap MOUTHS FACE THE TOP (up-slope). A tossed ball lands on or beyond the
## fan, rolls BACK down-slope, and drops into a gap from the top; the gap's
## front wall (toward the thrower) stops it. The plank is tilted to rise
## toward the front, so any ball landing on the fan self-loads toward the
## top mouths. Light maple wood + dark recessed gap channels so the grooves
## READ, and a prominent spike comb flanking every mouth.
func _build_astrolabes() -> void:
	for bi in range(POS_Z.size()):
		var cz: float = POS_Z[bi]
		var g: int = FAN_GAPS[bi]
		var m: float = FAN_MOUTH[bi]
		var depth: float = FAN_DEPTH[bi]
		var half_w := fan_width(bi) * 0.5
		var w := half_w * 2.0
		var sy: float = surface_y_at(0.0, cz)
		# wooden fan hardware (owner 2026-09-11: "the fans and their spikes
		# are made of wood as well") - warm walnut, matching the reference
		var maple := StandardMaterial3D.new()
		maple.albedo_color = Color(0.40, 0.28, 0.16)
		maple.roughness = 0.6
		var oak := StandardMaterial3D.new()
		oak.albedo_color = Color(0.46, 0.32, 0.18)
		oak.roughness = 0.55
		# one physics body per fan, tilted with the board
		var fan := StaticBody3D.new()
		fan.collision_layer = 1
		fan.collision_mask = 2
		fan.position = Vector3(0.0, sy, cz)
		fan.rotation.x = -deg_to_rad(TILT_DEG)
		# --- semi-circular base plank (the bowl) ---
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.36, 0.25, 0.14)
		bmat.roughness = 0.6
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = _half_disc_mesh(half_w, 0.012)
		base_mi.material_override = bmat
		base_mi.position = Vector3(0.0, 0.006, 0.0)
		fan.add_child(base_mi)
		# --- main plank, tilted to rise toward the FRONT so balls landing
		# on it roll BACK toward the top mouths (self-loading) ---
		var plat := CollisionShape3D.new()
		var pshape := BoxShape3D.new()
		pshape.size = Vector3(w, 0.014, depth * 0.95)
		plat.shape = pshape
		plat.position = Vector3(0.0, 0.019, 0.0)
		plat.rotation.x = 0.07
		fan.add_child(plat)
		var pmi := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = pshape.size
		pmi.mesh = pmesh
		pmi.material_override = maple
		pmi.position = plat.position
		pmi.rotation = plat.rotation
		fan.add_child(pmi)
		# --- wooden connectors between the gaps (2026-09-08 close-up reference:
		# these are solid rectangular wood connectors, not round pegs, stepped
		# in height by letter group - the connectors flanking slot A are
		# tallest, then the B pair, then C, then D at the outer edges). ---
		var div_h := 0.012
		var div_t: float = FAN_BLADE[bi] * 0.7
		var center_i := float(g) * 0.5
		for i in range(g + 1):
			var dx := -half_w + float(i) * (w / float(g))
			var tier := int(floor(absf(float(i) - center_i)))
			var peg_h: float = PEG_H_TIERS[clampi(tier, 0, PEG_H_TIERS.size() - 1)]
			# PHYSICS = peg height (2026-09-11 FIX: the collision was only
			# div_h=0.012 while the visible peg was up to 0.045 tall - balls
			# rolled straight THROUGH the visible spikes. Now the collision
			# matches the visible wood so an incoming ball clips the
			# protruding peg and bounces off an occupied/filled gap).
			var dcs := CollisionShape3D.new()
			var dshape := BoxShape3D.new()
			dshape.size = Vector3(div_t, peg_h, depth * 0.8)
			dcs.shape = dshape
			dcs.position = Vector3(dx, 0.024 + peg_h * 0.5, 0.0)
			dcs.rotation.x = 0.07
			fan.add_child(dcs)
			var dmi := MeshInstance3D.new()
			var dmesh := BoxMesh.new()
			dmesh.size = Vector3(div_t, peg_h, depth * 0.8)
			dmi.mesh = dmesh
			dmi.material_override = oak
			dmi.position = dcs.position
			dmi.rotation = dcs.rotation
			fan.add_child(dmi)
		# --- FRONT wall (toward the thrower): stops balls that entered
		# from the top and rolled down the groove ---
		var wcs := CollisionShape3D.new()
		var wshape := BoxShape3D.new()
		wshape.size = Vector3(w, 0.034, 0.014)
		wcs.shape = wshape
		wcs.position = Vector3(0.0, 0.017, -depth * 0.46)
		fan.add_child(wcs)
		var wmesh := MeshInstance3D.new()
		var wbmm := BoxMesh.new()
		wbmm.size = wshape.size
		wmesh.mesh = wbmm
		wmesh.material_override = oak
		wmesh.position = wcs.position
		fan.add_child(wmesh)
		add_child(fan)
		# --- per-gap: capture area over the groove channel + dark claim-glow
		# floor + letter at the TOP mouth ---
		for si in range(g):
			var fx0 := -half_w + (float(si) / float(g)) * w
			var fx1 := -half_w + (float(si + 1) / float(g)) * w
			var gx := (fx0 + fx1) * 0.5
			var gz := depth * 0.14
			var area := Area3D.new()
			var cs := CollisionShape3D.new()
			var sb := BoxShape3D.new()
			sb.size = Vector3(m * 0.9, 0.055, depth * 0.75)
			cs.shape = sb
			area.add_child(cs)
			area.position = Vector3(gx, 0.035, gz)
			area.collision_layer = 0
			area.collision_mask = 2
			area.monitoring = true
			fan.add_child(area)
			# neutral shadowed groove floor - recolors flat (no glow) once claimed
			var cup_mat := StandardMaterial3D.new()
			cup_mat.albedo_color = Color(0.10, 0.10, 0.11)
			cup_mat.roughness = 0.8
			var slit_floor := MeshInstance3D.new()
			var sfm := BoxMesh.new()
			sfm.size = Vector3(m * 0.8, 0.004, depth * 0.55)
			slit_floor.mesh = sfm
			slit_floor.material_override = cup_mat
			slit_floor.position = Vector3(gx, 0.028, gz)
			fan.add_child(slit_floor)
			# letter etched at the TOP mouth (A at the centre, outward B, C..)
			var letter_idx := clampi(int(absf(float(si) - float(g - 1) * 0.5)), 0, 5)
			var llbl := Label3D.new()
			llbl.text = "ABCDEF".substr(letter_idx, 1)
			llbl.modulate = Color(0.82, 0.82, 0.82)
			llbl.font_size = 40
			llbl.pixel_size = 0.0006
			llbl.outline_size = 0
			llbl.rotation_degrees = Vector3(-84.0, 0.0, 0.0)
			llbl.position = Vector3(gx, 0.040, depth * 0.5 + 0.022)
			fan.add_child(llbl)
			slots.append({"band": bi, "col": si, "area": area, "color": "",
				"cup": cup_mat})
		# point value painted on the marble in FRONT of the fan (thrower side)
		var lbl := Label3D.new()
		lbl.text = str(FAN_POINTS[bi])
		lbl.modulate = Color(0.78, 0.16, 0.14)
		lbl.font_size = 110
		lbl.pixel_size = 0.0006
		lbl.outline_size = 0
		lbl.rotation_degrees = Vector3(-84.0, 0.0, 0.0)
		lbl.position = Vector3(0.0, sy + 0.004, cz - depth * 0.5 - 0.034)
		add_child(lbl)


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


## Horizontal ammo shelf (2026-09-08 user rule): the 12 spare balls per color
## sit in a single row each, red growing left of centerline and black
## growing right, on a shelf just behind the tray - replacing the old
## vertical side channels so the board itself can be wider.
func _build_ammo_shelf() -> void:
	var wood_mat := _wood_material()
	var half_w := AMMO_GAP_X + float(BALLS_PER_COLOR - 1) * RACK_PITCH + SCBBall.RADIUS_M + 0.03
	var depth := 0.22
	var bodies := [
		{"size": Vector3(half_w * 2.0, 0.04, depth), "pos": Vector3(0.0, AMMO_SHELF_TOP_Y - 0.02, AMMO_ROW_Z)},
		{"size": Vector3(half_w * 2.0, 0.08, 0.02), "pos": Vector3(0.0, AMMO_SHELF_TOP_Y + 0.02, AMMO_ROW_Z - depth * 0.5)},
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
	# Tall catch volume: overpowered balls cross the gutter line while still
	# AIRBORNE (sweep: y up to 0.66) - the volume must reach up to ~0.85 so
	# the claim fires wherever the ball dies in the channel.
	gb.size = Vector3(GUTTER_FULL_W, 1.30, 0.85)
	gs.shape = gb
	gutter.add_child(gs)
	gutter.position = Vector3(0.0, 0.20, GUTTER_AREA_Z)
	gutter.collision_layer = 0
	gutter.collision_mask = 2
	gutter.monitoring = true
	add_child(gutter)
	# Physical trench under the gutter volume: floor + back wall + side walls.
	# Without a floor, a ball that flew past Jupiter void-fell below the world
	# (y < -0.5) where the escape guard mis-rated it as a RETURNED ball. With
	# the trench, it visibly lands in the channel and is claimed as guttered.
	var trench := [
		{"size": Vector3(GUTTER_FULL_W, 0.04, 1.10), "pos": Vector3(0.0, -0.12, TRENCH_Z)},
		# Low-profile backstop + side walls (2026-09-07 user rule: no tall
		# cabinet at the far end - the real table's far end is just an open
		# studio wall). Height matches the side rails so it reads as a
		# normal cushion, not a piece of furniture. Overpowered balls that
		# clear this low wall airborne are still caught by the escape guard
		# in _physics_process (position-based, independent of wall height).
		{"size": Vector3(GUTTER_FULL_W, 0.32, 0.04), "pos": Vector3(0.0, 0.01, TRENCH_BACK_Z)},
		{"size": Vector3(0.04, 0.32, 1.10), "pos": Vector3(-GUTTER_X_HALF, 0.01, TRENCH_Z)},
		{"size": Vector3(0.04, 0.32, 1.10), "pos": Vector3(GUTTER_X_HALF, 0.01, TRENCH_Z)},
	]
	for r in trench:
		var tb := StaticBody3D.new()
		var tcs := CollisionShape3D.new()
		var tbs := BoxShape3D.new()
		tbs.size = r.size
		tcs.shape = tbs
		tb.add_child(tcs)
		tb.position = r.pos
		tb.collision_layer = 1
		tb.collision_mask = 2
		add_child(tb)
		# VISIBLE trench: the channel used to be colliders-only - an invisible
		# void the ball simply fell into. A dark channel floor + wood walls
		# read as the real game's deep gutter cabinet.
		var tm := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = r.size
		tm.mesh = tbm
		var tmat := StandardMaterial3D.new()
		if (r["pos"] as Vector3).y < -0.05:
			tmat.albedo_color = Color(0.10, 0.11, 0.13)
			tmat.roughness = 0.85
		else:
			tmat.albedo_color = Color(0.30, 0.20, 0.12)
			tmat.roughness = 0.75
		tm.material_override = tmat
		tm.position = r.pos
		add_child(tm)


func _physics_process(_delta: float) -> void:
	# Adopt any live ball that lost its tracker (a ball knocked loose out of
	# a slit by a later shot, for example) so EVERY ball stays watched until
	# it reaches a terminal state - no more orphaned balls stuck mid-board.
	for lb in live_balls:
		if lb == null or not is_instance_valid(lb) or (lb as SCBBall).freeze:
			continue
		var known := false
		for t in _tracked:
			if t.get("ball") == lb:
				known = true
				break
		if not known:
			_tracked.append({"ball": lb, "frames": 0, "anchor": null, "nudges": 0})
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
		# ESCAPE GUARD FIRST: anything beyond the trench, below the
		# world, or way off-line is an overpowered/lost ball - snap it into
		# the channel and claim GUTTERED. This must precede the deep-zone
		# altitude gate, else a flyer past the trench lands in that branch,
		# finds no gutter overlap at its far position, and comes back as a
		# bogus "returned" ball (sweep p=6.4: end=(0, 0.054, 5.26)).
		if bb.position.z > ESCAPE_Z or bb.position.y < -0.5 or absf(bb.position.x) > 3.0:
			bb.position.x = clampf(bb.position.x, -GUTTER_X_HALF + 0.10, GUTTER_X_HALF - 0.10)
			bb.position.z = clampf(bb.position.z, GUTTER_CLAMP_MIN_Z, GUTTER_CLAMP_MAX_Z)
			bb.position.y = -0.10 + SCBBall.RADIUS_M + 0.002
			_freeze_in_place(bb)
			ball_guttered.emit(bb)
			continue
		# Deep-zone rule: anything past the last astrolabe is in the
		# gutter. But an OVERPOWERED ball crosses that line while still AIRBORNE
		# (sweep: y up to 0.66) - resolving it there froze the ball mid-wall.
		# Altitude gate: flying balls keep flying into the trench and are
		# claimed the moment they land (or die) inside the gutter volume.
		if bb.position.z > GUTTER_ALTITUDE_Z:
			if bb.position.y < 0.10 or bb.linear_velocity.length() < 0.05:
				_resolve_ball(t)
			else:
				_any_moving = true
				still.append(t)
			continue
		var spd := bb.linear_velocity.length()
		if spd > (0.03):
			_any_moving = true
		# v13 SLIT CAPTURE: the grooves are real geometry now - walls + back
		# wall catch the ball, wood friction holds it against the slope. No
		# funnel forces. A ball inside a slit area slower than CAPTURE_SPEED
		# is claimed by _resolve_ball (official claim / grouping / block);
		# faster balls skim across the open slits or deflect off the blades.
		if spd < CAPTURE_SPEED and not _socket_overlapping(bb).is_empty():
			_resolve_ball(t)
			continue
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
			if int(t["nudges"]) <= 5:
				# hop + push: break static contact so the ball visibly
				# struggles free and finishes its roll-back to the tray
				bb.sleeping = false
				bb.apply_central_impulse(Vector3(0.0, 0.10, -0.7) * bb.mass)
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
		# Snap INTO the trench channel, not onto the extrapolated felt plane:
		# ball_rest_y() has no knowledge of the trench cut-out, so snapping
		# to it froze balls floating 19 cm above the channel (sweep p=4.4:
		# end y=0.0898). Trench floor top is y=-0.10; rest = floor + radius +
		# lip.
		bb.position.x = clampf(bb.position.x, -GUTTER_X_HALF + 0.10, GUTTER_X_HALF - 0.10)
		bb.position.z = clampf(bb.position.z, GUTTER_CLAMP_MIN_Z, GUTTER_CLAMP_MAX_Z)
		bb.position.y = -0.10 + SCBBall.RADIUS_M + 0.002
		_freeze_in_place(bb)
		ball_guttered.emit(bb)
		return
	if is_returned:
		reinsert_hand_ball(bb)
		ball_returned.emit(bb)
		return
	var sd := _socket_overlapping(b)
	if not sd.is_empty():
		# v14 BOOKED SLOTS ARE PERMANENT (2026-09 user rule): a gap holding
		# a ball can never be recaptured or displaced - later balls simply
		# bounce off the sitting one (it is a solid frozen body) and rest
		# against it as a grouping wall. Only an EMPTY gap can be claimed.
		if String(sd["color"]) != "":
			_freeze_in_place(bb)
			ball_grouped.emit(bb)
			return
		_claim_socket(sd, bb)
		ball_scored.emit(bb, int(sd["band"]), false)
		return
	# Open felt: a 5-degree slope cannot hold a ball - the real sport never
	# lets one rest mid-board (2026-09 user feedback: stuck balls "very
	# annoying"). The settle-detector nudged it 5 times already; resolve it
	# now by the sport's Returned-Ball rule: back to the rack, free shot.
	reinsert_hand_ball(bb)
	ball_returned.emit(bb)


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
	# NO teleport (v14 user rule - nothing "magically" moves): the ball
	# stays exactly where physics settled it and is frozen in its groove.
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
	# v17 REAL-GAME RULE (owner): a claimed groove does NOT change colour -
	# the ball sitting in it is the visual. Keep the recessed floor neutral.
	pass


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
