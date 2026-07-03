extends MultiplayerSpawner

@export var network_player: PackedScene

## Spread spawn points around a small circle so players never stack on top
## of one another (overlapping capsules fight the physics and look duplicated).
const SPAWN_RADIUS: float = 3.0
const SPAWN_SLOTS: int = 8

var _spawn_count: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(spawn_player)

func spawn_player(id: int) -> void:
	if !multiplayer.is_server(): return

	var player: Node = network_player.instantiate()
	player.name = str(id)
	# Set the position before adding to the tree so it rides along in the
	# spawn state (position has spawn = true in the replication config).
	player.position = _next_spawn_point()

	get_node(spawn_path).call_deferred("add_child", player)

func _next_spawn_point() -> Vector3:
	var angle: float = _spawn_count * TAU / SPAWN_SLOTS
	_spawn_count += 1
	# Lift slightly off the ground so they settle cleanly rather than
	# starting interpenetrated with the floor.
	return Vector3(cos(angle) * SPAWN_RADIUS, 0.5, sin(angle) * SPAWN_RADIUS)
