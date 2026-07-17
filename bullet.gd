##NOT CURRENTLY IN USE









extends Node3D

const SPEED = 80

## Who fired this bullet (peer id), so we don't damage ourselves. Set by the
## shooter before the bullet is added to the tree.
var shooter_id: int = 0
@export var damage: int = 20

var _hit_registered: bool = false

@onready var mesh = $MeshInstance3D
@onready var ray = $RayCast3D
@onready var particles = $GPUParticles3D

func _process(delta):
	if _hit_registered:
		return

	position += transform.basis * Vector3(0, 0, -SPEED) * delta

	if ray.is_colliding():
		var collider = ray.get_collider()
		if collider:
			var decal = preload("res://bulletHole.tscn").instantiate()
			collider.add_child(decal)
			decal.global_position = ray.get_collision_point()
			decal.look_at(ray.get_collision_point() + ray.get_collision_normal(), Vector3.UP)
		
		_hit_registered = true

		var target = ray.get_collider()
		if target and target.is_in_group("players") and str(target.name) != str(shooter_id):
			# Route the hit through the server, which owns everyone's health.
			if multiplayer.is_server():
				target.take_damage(damage)
			else:
				target.take_damage.rpc_id(1, damage)

		mesh.visible = false
		particles.emitting = true
		await get_tree().create_timer(1.0).timeout
		queue_free()

func _on_timer_timeout() -> void:
	queue_free()
