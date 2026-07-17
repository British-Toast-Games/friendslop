extends Node3D

class_name DamageNumberSpawner

@export var font: Font
@export var font_size := 48
@export var color := Color.RED

func spawn_label(number: int, hit_position: Vector3) -> void:
	var label := Label3D.new()

	label.text = str(number)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = font
	label.font_size = font_size
	label.modulate = color

	# Spawn slightly above the hit point
	label.global_position = hit_position + Vector3.UP * 0.35

	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)

	# Float upward
	tween.tween_property(label, "position:y", label.position.y + 1.6,0.8)

	# Fade away
	tween.tween_property(label, "modulate:a", 0.0, 0.8)

	tween.finished.connect(label.queue_free)
