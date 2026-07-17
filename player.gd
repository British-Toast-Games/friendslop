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

## Health (server-authoritative)
@export var max_health: int = 100
var health: int = 100

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var model: Node3D = $Model

@onready var hud: CanvasLayer = $HUD
@onready var health_bar: ProgressBar = $HUD/HealthBar

@onready var gun_anim = $CameraPivot/Camera3D/Gun/AnimationPlayer
@onready var gun_barrel = $CameraPivot/Camera3D/Gun/RayCast3D

@onready var b_decal = preload("res://bulletHole.tscn")
@onready var muzzle: GPUParticles3D = $CameraPivot/Camera3D/Gun/GPUParticles3D
@onready var cone: GPUParticles3D = $CameraPivot/Camera3D/Gun/GPUParticles3D2
@onready var flash: GPUParticles3D = $CameraPivot/Camera3D/Gun/GPUParticles3D3
@onready var spark: GPUParticles3D = $CameraPivot/Camera3D/Gun/GPUParticles3D4
@onready var bullet: GPUParticles3D = $CameraPivot/Camera3D/Gun/GPUParticles3D5
@onready var hitParticles: GPUParticles3D = $CameraPivot/Camera3D/Gun/HitParticles

@onready var gunshot: AudioStreamPlayer3D = $CameraPivot/Camera3D/Gun/AudioStreamPlayer3D

## var bullet = load("res://bullet.tscn")
## var instance

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var is_local: bool = is_multiplayer_authority()
	# Bullets look for players in this group to decide what they can hit.
	add_to_group("players")

	# Health starts full everywhere; the server drives all later changes.
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	# Only the local player's HUD is shown.
	hud.visible = is_local

	# Only the local player drives the camera and grabs the mouse.
	camera.current = is_local
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.fov = fov_default
		# Render ONLY our own viewmodel on top of the world so it doesn't clip
		# through walls. Other players' guns keep normal depth testing, so they
		# can't be seen through walls. Default white material keeps the plain,
		# untextured look.
		var vm_mat := StandardMaterial3D.new()
		vm_mat.no_depth_test = true
		vm_mat.render_priority = 100
		for gun_mesh in $CameraPivot/Camera3D/Gun.find_children("*", "MeshInstance3D"):
			gun_mesh.material_override = vm_mat
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
			
			muzzle.restart()
			cone.restart()
			flash.restart()
			spark.restart()
			bullet.restart()
			
			muzzle.emitting = true
			cone.emitting = true
			flash.emitting = true
			spark.emitting = true
			bullet.emitting = true
			gunshot.play()
			
			bullet_hitscan()
			## instance = bullet.instantiate()
			## instance.shooter_id = name.to_int()
			## instance.position = gun_barrel.global_position
			## et_parent().add_child(instance)
			# Fire from the barrel but toward where the crosshair points, so the
			# center-screen crosshair is what actually gets hit.
			## instance.look_at(_get_aim_point())

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


## Where the center crosshair is aiming: the first thing a ray straight out of
## the camera hits, or a far point down that ray if nothing is in the way.
func _get_aim_point() -> Vector3:
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]  # never hit our own body
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		return hit.position
	return to


func bullet_hitscan():
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, _get_aim_point())
	query.exclude = [self]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return

	var collider = hit.collider

	# Spawn bullet hole
	if collider:
		var decal = b_decal.instantiate()
		collider.add_child(decal)
		decal.global_position = hit.position
		decal.look_at(hit.position + hit.normal, Vector3.UP)
		
		hitParticles.global_position = hit.position
		hitParticles.restart()
		hitParticles.emitting = true


# --- Health / damage (server-authoritative) --------------------------------

## Called on the server (directly by a host shooter, or via RPC from a client
## shooter) to deal damage to this player.
@rpc("any_peer", "call_remote", "reliable")
func take_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if health <= 0:
		return
	health = max(health - amount, 0)
	_set_health.rpc(health)
	if health <= 0:
		_die()

## Server -> everyone: apply the authoritative health value and refresh the HUD.
@rpc("any_peer", "call_local", "reliable")
func _set_health(value: int) -> void:
	health = value
	if health_bar:
		health_bar.value = health

func _die() -> void:
	# Runs on the server. Reset health and send the owner back to its spawn point
	# (the owner is authoritative over its own position).
	health = max_health
	_set_health.rpc(health)

	var owner_id: int = name.to_int()
	var point: Vector3 = position
	var spawner: Node = get_tree().get_first_node_in_group("player_spawner")
	if spawner:
		point = spawner._spawn_point(owner_id)

	if owner_id == multiplayer.get_unique_id():
		_respawn_at(point)
	else:
		_respawn_at.rpc_id(owner_id, point)

@rpc("any_peer", "call_local", "reliable")
func _respawn_at(point: Vector3) -> void:
	position = point
	velocity = Vector3.ZERO
