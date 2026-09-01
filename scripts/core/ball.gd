class_name SCBBall
extends RigidBody3D

## Phenolic resin tournament ball (45 g, 40 mm diameter as spec'd by YoTyan).
## Free bodies that rest ON the tilted board: gravity's tangential component
## decelerates them up the 4.99-degree slope (real behavior), and static
## friction (0.49 >> tan(4.99 deg) ~ 0.087) holds resting balls in place.
## Constants tuned by tests/test_physics.gd; see docs/PHYSICS_SPEC.md.

const RADIUS_M := 0.02
const MASS_KG := 0.045
const ROLL_DAMP := 0.05  # smooth phenolic roll; resistance comes from the
# 5-degree slope's gravity component, not artificial braking


var color: String = "red"


func _ready() -> void:
	# Everything is configured in create() before entering the tree.
	# IMPORTANT: never rebuild physics properties after the body is inside the
	# physics space (Jolt re-registers the body, and if it is a hair's width
	# inside the board it tunnels straight through).
	pass


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
		mat.albedo_color = Color(0.85, 0.12, 0.08)
	else:
		mat.albedo_color = Color(0.10, 0.10, 0.10)
	mat.roughness = 0.25       # gloss: lacquered phenolic
	mat.metallic = 0.0
	mesh.mesh = sm
	mesh.material_override = mat
	add_child(mesh)


func set_mass_properties() -> void:
	mass = MASS_KG
	collision_layer = 2
	collision_mask = 3
	contact_monitor = true
	max_contacts_reported = 8
	# CCD is DISABLED: with the 60 Hz fixed step our max shot (3.4 m/s) moves
	# only 5.7 cm per frame - far below the 2.2 m board - and Jolt's CCD sweep
	# from a freshly-added body produced spawn artifacts that pushed balls
	# through the board. Re-enable later only if a tunneling case appears.
	continuous_cd = false
	angular_damp = ROLL_DAMP
	linear_damp = 0.02
	# Godot 4: bounce/friction live on a PhysicsMaterial, not the body.
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.49
	physics_material_override = pm


static func create(color_name: String) -> SCBBall:
	var b := SCBBall.new()
	b.color = color_name
	b.configure_material()    # shape + visuals BEFORE tree entry
	b.set_mass_properties()   # all physics properties BEFORE tree entry
	return b