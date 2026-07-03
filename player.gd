extends CharacterBody3D

## Movement tuning
@export var speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 5.0   # was 4.5
@export var acceleration: float = 12.0

@export var gravityMultiplier: float = 1.3

## Mouse look
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

## Field-of-view kick while sprinting
@export var fov_default: float = 75.0
@export var fov_sprint: float = 90.0
@export var fov_lerp_speed: float = 8.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model: Node3D = $Model

@onready var gun_anim = $CameraPivot/Camera3D/Gun/AnimationPlayer
@onready var gun_barrel = $CameraPivot/Camera3D/Gun/RayCast3D

var bullet = load("res://bullet.tscn")
var instance

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var is_local: bool = is_multiplayer_authority()
	# Only the local player drives the camera and grabs the mouse.
	camera.current = is_local
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.fov = fov_default
		# We're authoritative over our own position, so the spawn point must be
		# applied here. The host is both server and authority, so it sets its
		# point directly; a remote client asks the server over RPC.
		var spawner: Node = get_tree().get_first_node_in_group("player_spawner")
		if spawner:
			if multiplayer.is_server():
				position = spawner._spawn_point(name.to_int())
				velocity = Vector3.ZERO
			else:
				spawner.request_spawn_point.rpc_id(1)
	# Show the body for everyone EXCEPT ourselves, so we stay first-person
	# but remain visible to other players.
	model.visible = not is_local


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the whole body; pitch only tilts the head/camera.
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

	# Release / recapture the mouse with Escape.
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Gravity
	if not is_on_floor():
		velocity += gravityMultiplier * get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity  
	
	# Shooting
	if Input.is_action_pressed("shoot"):
		if !gun_anim.is_playing():
			gun_anim.play("Shoot")
			instance = bullet.instantiate()
			instance.position = gun_barrel.global_position
			instance.transform.basis = gun_barrel.global_transform.basis
			get_parent().add_child(instance)

	# Move relative to where the body is facing.
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var is_sprinting: bool = Input.is_action_pressed("sprint") and direction.length() > 0.1
	var current_speed: float = sprint_speed if is_sprinting else speed
	var target_velocity: Vector3 = direction * current_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta * current_speed)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta * current_speed)

	# Smoothly widen the FOV while sprinting for a sense of speed.
	var target_fov: float = fov_sprint if is_sprinting else fov_default
	camera.fov = lerp(camera.fov, target_fov, fov_lerp_speed * delta)

	move_and_slide()
