class_name FoliagePlacementEvents
extends RefCounted

## The seam between "something was put down" and "grass under it goes away".
##
## Grass never talks to the placement code, and placement never talks to grass.
## Whatever places objects emits here; GrassLayer listens. Networking is
## deliberately not decided yet, and this is where it will attach: a remote
## placement arrives, is emitted into the same bus, and every client carves its
## own locally generated grass. No grass data crosses the wire -- only the
## event, which is already the same size whether or not the location has grass.
##
## An object id is the unit of carving. Re-emitting `placed` for an id that is
## already down is a move: the old footprint is released and the new one
## carved in a single rebuild.

signal placed(object_id: StringName, footprints: Array[GrassCarver])
signal removed(object_id: StringName)


func place(object_id: StringName, footprints: Array[GrassCarver]) -> void:
	placed.emit(object_id, footprints)


func remove(object_id: StringName) -> void:
	removed.emit(object_id)
