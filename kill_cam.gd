extends Node3D

@onready var camera = $Camera3D
@onready var animation = $AnimationPlayer
@onready var deathText = $killInfo/Label

var target: Node3D
signal finished


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	animation.animation_finished.connect(_on_animation_player_animation_finished)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if target:
		global_position = target.global_position

func start(target_player: Node3D):
	target = target_player
	visible = true
	camera.current = true
	animation.play("killCam")
	deathText.text = "Killed by %s" % target_player

func _on_animation_player_animation_finished(anim_name):
	print("Animation finished!")
	camera.current = false
	visible = false
	emit_signal("finished")
	deathText.text = ""
