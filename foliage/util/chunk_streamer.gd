class_name ChunkStreamer
extends RefCounted

## Keeps a set of chunks alive, building them on WorkerThreadPool and handing
## the results to the main thread a few at a time. Shared by grass, trees and
## ground, which differ only in what a chunk is.
##
## The owner says WHICH chunks it wants (set_wanted), each with a variant --
## e.g. a ground chunk's detail level -- and supplies a job and two callables:
##
##   job.run(coord, variant) -> result   WORKER THREAD. Pure data only: no
##                                       nodes, no RenderingServer, no
##                                       state another thread writes. The job
##                                       is an object holding a snapshot of
##                                       the settings it builds with.
##   commit(coord, variant, result)      MAIN THREAD. Turns the result into
##                                       nodes, replacing any existing ones.
##   release(coord)                      MAIN THREAD. Frees a chunk.
##
## update() runs once a frame: it frees chunks no longer wanted, commits
## finished builds within `budget_usec`, and submits new builds nearest-first,
## at most `max_in_flight` at a time. flush() does all of that to completion,
## blocking -- for first builds, settings changes and tests.
##
## A chunk stays visible while its replacement builds (invalidate() and variant
## changes both work this way), so a quality change or a detail-level switch
## never leaves a hole.

## An object with run(coord, variant). Held here, and bound into every task,
## as a strong reference: a Callable alone does not keep a RefCounted alive,
## and a job replaced on rebuild must survive until its in-flight tasks end.
var job: RefCounted
var commit: Callable
var release: Callable

## Main-thread time allowed per update() for committing finished chunks.
var budget_usec: int = 3000
var max_in_flight: int = 8

var _wanted: Dictionary = {}       ## Vector2i -> variant
var _order: Array = []             ## wanted coords, highest priority first
var _live: Dictionary = {}         ## Vector2i -> variant it was built with
var _in_flight: Dictionary = {}    ## Vector2i -> [task id, variant, generation]
var _finished: Array = []          ## [coord, variant, generation, result]
var _mutex := Mutex.new()
var _generation: int = 0
## In-flight coords whose results are stale (invalidate_area()).
var _stale_flight: Dictionary = {}

## Stale-build marker: a live chunk with this variant needs rebuilding.
const STALE := -2147483648


## `wanted` maps coord -> variant; `order` lists the same coords by priority.
func set_wanted(wanted: Dictionary, order: Array) -> void:
	_wanted = wanted
	_order = order


## Wanted set: every chunk whose square comes within `radius` of `centre`
## (XZ), all with variant 0, nearest first. Returns [wanted, order].
static func disc(centre: Vector3, chunk_size: float, radius: float) -> Array:
	var wanted := {}
	var reach := int(ceil(radius / chunk_size)) + 1
	var middle := Vector2i(floori(centre.x / chunk_size), floori(centre.z / chunk_size))
	var here := Vector2(centre.x, centre.z)
	var ranked: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := middle + Vector2i(dx, dz)
			var d := distance_to_chunk(here, coord, chunk_size)
			if d <= radius:
				wanted[coord] = 0
				ranked.append([d, coord])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	return [wanted, ranked.map(func(r): return r[1])]


## Wanted set: a fixed square of (2 * radius + 1)^2 chunks round the origin,
## variant 0. The pre-streaming behaviour, kept for tests that need a stable,
## camera-independent set of chunks.
static func square(radius: int) -> Array:
	var wanted := {}
	var ranked: Array = []
	for cz in range(-radius, radius + 1):
		for cx in range(-radius, radius + 1):
			var coord := Vector2i(cx, cz)
			wanted[coord] = 0
			ranked.append([Vector2(cx, cz).length(), coord])
	ranked.sort_custom(func(a, b): return a[0] < b[0])
	return [wanted, ranked.map(func(r): return r[1])]


## Horizontal distance from a point to the nearest point of a chunk's square.
static func distance_to_chunk(point: Vector2, coord: Vector2i, chunk_size: float) -> float:
	var low := Vector2(coord) * chunk_size
	var nearest := point.clamp(low, low + Vector2(chunk_size, chunk_size))
	return point.distance_to(nearest)


func update() -> void:
	for coord in _live.keys():
		if not _wanted.has(coord):
			release.call(coord)
			_live.erase(coord)
	_harvest(budget_usec)
	_submit(max_in_flight)


## Builds everything wanted, blocking until done.
func flush() -> void:
	for coord in _live.keys():
		if not _wanted.has(coord):
			release.call(coord)
			_live.erase(coord)
	while true:
		_submit(1 << 30)
		if _in_flight.is_empty():
			break
		# Waited here and dropped from _in_flight, so _harvest does not wait on
		# the same task twice (Godot reports that as an error).
		for coord in _in_flight.keys():
			WorkerThreadPool.wait_for_task_completion(_in_flight[coord][0])
		_in_flight.clear()
		_harvest(-1)


## Builds one particular wanted chunk now. Staged location startup uses this
## for the ground and physics chunk under the arrival point, while every other
## wanted chunk remains in the normal streaming queue.
func flush_coord(coord: Vector2i) -> void:
	if not _wanted.has(coord) or not _needs(coord):
		return
	if not _in_flight.has(coord):
		var variant: int = _wanted[coord]
		var task := WorkerThreadPool.add_task(_run.bind(job, coord, variant, _generation))
		_in_flight[coord] = [task, variant, _generation]
	WorkerThreadPool.wait_for_task_completion(_in_flight[coord][0])
	# As in flush(), remove a task we explicitly waited for before harvesting;
	# Godot rejects waiting on the same worker task twice.
	_in_flight.erase(coord)
	_harvest(-1)


## Marks every chunk for rebuilding (settings changed). Old chunks stay up
## until their replacements commit; in-flight builds are discarded.
func invalidate() -> void:
	_generation += 1
	for coord in _live.keys():
		_live[coord] = STALE


## Marks the chunks overlapping `area` (world XZ) for rebuilding, keeping
## them visible until their replacements commit; in-flight builds there are
## discarded. Painted zones (Location Studio S4) use it. Returns live chunks
## marked.
func invalidate_area(area: Rect2, chunk_size: float) -> int:
	var marked := 0
	for coord: Vector2i in _live.keys():
		if Rect2(Vector2(coord) * chunk_size, Vector2.ONE * chunk_size).intersects(area):
			_live[coord] = STALE
			marked += 1
	for coord: Vector2i in _in_flight.keys():
		if Rect2(Vector2(coord) * chunk_size, Vector2.ONE * chunk_size).intersects(area):
			_stale_flight[coord] = true
	return marked


## Frees everything, waiting for in-flight builds first so no worker is left
## writing into a result nobody will read.
func clear() -> void:
	for coord in _in_flight.keys():
		WorkerThreadPool.wait_for_task_completion(_in_flight[coord][0])
	_in_flight.clear()
	_mutex.lock()
	_finished.clear()
	_mutex.unlock()
	for coord in _live.keys():
		release.call(coord)
	_live.clear()


func is_live(coord: Vector2i) -> bool:
	return _live.has(coord)


func live_count() -> int:
	return _live.size()


## Chunks wanted but not yet committed at their wanted variant.
func pending_count() -> int:
	var n := 0
	for coord in _wanted:
		if _needs(coord):
			n += 1
	return n


func _needs(coord: Vector2i) -> bool:
	return not _live.has(coord) or _live[coord] != _wanted[coord]


func _submit(limit: int) -> void:
	for coord in _order:
		if _in_flight.size() >= limit:
			return
		if _in_flight.has(coord) or not _needs(coord):
			continue
		var variant: int = _wanted[coord]
		# The task gets its own reference to the job: the owner swaps `job`
		# on a settings change, and a worker must not read the member while
		# the main thread writes it.
		var task := WorkerThreadPool.add_task(_run.bind(job, coord, variant, _generation))
		_in_flight[coord] = [task, variant, _generation]


func _run(task_job: RefCounted, coord: Vector2i, variant: int, generation: int) -> void:
	var result: Variant = task_job.run(coord, variant)
	_mutex.lock()
	_finished.append([coord, variant, generation, result])
	_mutex.unlock()


## Commits finished builds until `budget` microseconds pass (-1: no limit).
func _harvest(budget: int) -> void:
	var started := Time.get_ticks_usec()
	while true:
		_mutex.lock()
		var item: Array = _finished.pop_front() if not _finished.is_empty() else []
		_mutex.unlock()
		if item.is_empty():
			return
		var coord: Vector2i = item[0]
		var variant: int = item[1]
		var generation: int = item[2]
		if _in_flight.has(coord):
			# The task has finished; this releases its pool slot.
			WorkerThreadPool.wait_for_task_completion(_in_flight[coord][0])
			_in_flight.erase(coord)
		var current: bool = generation == _generation and _wanted.has(coord) and _wanted[coord] == variant and not _stale_flight.has(coord)
		_stale_flight.erase(coord)
		if current:
			commit.call(coord, variant, item[3])
			_live[coord] = variant
		if budget >= 0 and Time.get_ticks_usec() - started > budget:
			return
