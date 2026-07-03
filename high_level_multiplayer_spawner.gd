extends MultiplayerSpawner

@export var network_player: PackedScene

## Spread spawn points around a small circle so players never stack on top of
## one another (overlapping capsules fight the physics and look duplicated).
const SPAWN_RADIUS: float = 3.0
const SPAWN_SLOTS: int = 8

# peer id -> spawn slot index, assigned by the server as peers connect.
var _spawn_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("player_spawner")
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(despawn_player)

func spawn_player(id: int) -> void:
	if !multiplayer.is_server(): return

	_assign_slot(id)

	var player: Node = network_player.instantiate()
	player.name = str(id)
	get_node(spawn_path).call_deferred("add_child", player)

func despawn_player(id: int) -> void:
	if !multiplayer.is_server(): return

	# Freeing the node on the server auto-replicates the removal to all clients.
	var player: Node = get_node(spawn_path).get_node_or_null(str(id))
	if player:
		player.queue_free()
	# Release the slot so a future player can reuse this spawn point.
	_spawn_slots.erase(id)

## Assign the lowest free spawn slot to a peer (reusing slots freed on disconnect).
func _assign_slot(id: int) -> int:
	if _spawn_slots.has(id):
		return _spawn_slots[id]
	var used: Dictionary = {}
	for s in _spawn_slots.values():
		used[s] = true
	var slot: int = 0
	while used.has(slot):
		slot += 1
	_spawn_slots[id] = slot
	return slot

func _spawn_point(id: int) -> Vector3:
	var slot: int = _spawn_slots.get(id, 0)
	var angle: float = slot * TAU / SPAWN_SLOTS
	# Lifted slightly off the ground so players settle cleanly.
	return Vector3(cos(angle) * SPAWN_RADIUS, 0.5, sin(angle) * SPAWN_RADIUS)

## Called by a freshly-spawned client (see player.gd) that is authoritative over
## its own position, so the spawn point has to be applied on that client.
@rpc("any_peer", "call_remote", "reliable")
func request_spawn_point() -> void:
	if not multiplayer.is_server(): return
	var requester: int = multiplayer.get_remote_sender_id()
	_assign_slot(requester)
	receive_spawn_point.rpc_id(requester, _spawn_point(requester))

@rpc("authority", "call_remote", "reliable")
func receive_spawn_point(point: Vector3) -> void:
	var me: int = multiplayer.get_unique_id()
	var player: Node = get_node(spawn_path).get_node_or_null(str(me))
	if player:
		player.position = point
		player.velocity = Vector3.ZERO
