class_name SCBBall
extends RigidBody3D

## Phenolic resin tournament ball. V2 (Phase 1) sizing: 60 mm / 100 g -
## the ball is the star of the show on a phone screen; tests/test_physics.gd
## and docs/PHYSICS_SPEC.md have been updated to match.
## Free bodies that rest ON the tilted board: gravity's tangential component
## decelerates them up the 4.99-degree slope, and static friction
## (0.49 >> tan(4.99 deg) ~ 0.087) holds resting balls in place.

const RADIUS_M := 0.030
const MASS_KG := 0.100
const ROLL_DAMP := 0.05  # smooth phenolic roll; resistance comes from the
# 5-degree slope's gravity component, not artificial braking


var color: String = "red"

var _mesh_instance: MeshInstance3D = null
var _mat: StandardMaterial3D = null

## Broadcast highlight: when true the ball pulses a warm emission so the
## player always knows exactly which ball is in hand.
var is_active := false:
	set(value):
		is_active = value
		_sync_emphasis()


func _ready() -> void:
	# Everything is configured in create() before entering the tree.
	# IMPORTANT: never rebuild physics properties after the body is inside the
	# physics space (Jolt re-registers the body, and if it is a hair's width
	# inside the board it tunnels straight through).
	pass


func _process(_delta: float) -> void:
	if is_active and _mat != null:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		_mat.emission_energy_multiplier = 0.7 + pulse * 1.5


func _sync_emphasis() -> void:
	if _mat == null:
		return
	if is_active:
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.92, 0.5)
	else:
		_mat.emission_enabled = false


func configure_material() -> void:
	# Visual mesh + the REQUIRED collision shape (a RigidBody3D has none
	# implicitly - without this the ball would fall through the table).
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = RADIUS_M
	cs.shape = sp
	add_child(cs)

	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS_M
	sm.height = RADIUS_M * 2.0
	var mat := StandardMaterial3D.new()
	if color == "red":
		mat.albedo_color = Color(0.84, 0.14, 0.09)
	else:
		mat.albedo_color = Color(0.09, 0.09, 0.09)
	# Lacquered phenolic: tight gloss + clearcoat micro-glints + specular sheen.
	mat.roughness = 0.10
	mat.metallic = 0.0
	mat.clearcoat = 0.6
	mat.clearcoat_roughness = 0.08
	mesh.mesh = sm
	mesh.material_override = mat
	add_child(mesh)
	_mesh_instance = mesh
	_mat = mat
	_sync_emphasis()


func set_mass_properties() -> void:
	mass = MASS_KG
	collision_layer = 2
	collision_mask = 3
	contact_monitor = true
	max_contacts_reported = 8
	# CCD is DISABLED: with the 60 Hz fixed step our max shot (3.4 m/s) moves
	# only 5.7 cm per frame - far below the 2.2 m board.
	continuous_cd = false
	angular_damp = ROLL_DAMP
	linear_damp = 0.10
	# Godot 4: bounce/friction live on a PhysicsMaterial, not the body.
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.30
	pm.friction = 0.49
	physics_material_override = pm


static func create(color_name: String) -> SCBBall:
	var b := SCBBall.new()
	b.color = color_name
	b.configure_material()    # shape + visuals BEFORE tree entry
	b.set_mass_properties()   # all physics properties BEFORE tree entry
	return b