class_name SiteBuildQueue
extends RefCounted

## Progressive construction for a geographic site (LocationSiteLayer): each
## piece's data is built on WorkerThreadPool, nearest `origin` first, and its
## nodes are committed on the main thread within `budget_usec` per update().
## A commit may add further pieces, or main-thread steps (then()), e.g. the
## roadside plan queues each road's pavement and every furniture placement.
##
##   build()          WORKER THREAD. Pure data from bound arguments: no nodes,
##                    no RenderingServer, nothing another thread writes.
##   commit(result)   MAIN THREAD. Turns the result into nodes.

## Main-thread time allowed per update() for commits and steps.
var budget_usec: int = 4000
var max_in_flight: int = 32
## World XZ that pieces are ordered from (the arrival point).
var origin := Vector2.ZERO

var _waiting: Array = []          ## [distance squared, build, commit]
var _sorted := true
var _in_flight: Dictionary = {}   ## task id -> true
var _finished: Array = []         ## [commit, result]
var _steps: Array[Callable] = []
var _mutex := Mutex.new()
var _cancelled := false


func add(position: Vector2, build: Callable, commit: Callable) -> void:
	_waiting.append([position.distance_squared_to(origin), build, commit])
	_sorted = false


## Ordered by the polyline's nearest vertex (roads, pavements).
func add_along(points: Array, build: Callable, commit: Callable) -> void:
	var nearest := INF
	for p in points:
		nearest = minf(nearest, Vector2(p[0], p[1]).distance_squared_to(origin))
	_waiting.append([nearest, build, commit])
	_sorted = false


## A main-thread step, run within the budget after finished pieces.
func then(step: Callable) -> void:
	_steps.append(step)


## Pieces and steps not yet committed.
func pending() -> int:
	_mutex.lock()
	var finished := _finished.size()
	_mutex.unlock()
	return _waiting.size() + _in_flight.size() + finished + _steps.size()


func update() -> void:
	_reap()
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < budget_usec and _step():
		pass
	_submit()


## Builds and commits everything, blocking (captures, edits on a part-built site).
func flush() -> void:
	while pending() > 0:
		_submit()
		for task in _in_flight.keys():
			WorkerThreadPool.wait_for_task_completion(task)
		_in_flight.clear()
		while _step():
			pass


## Drops everything not yet built. Waits only for pieces already running.
func cancel() -> void:
	_cancelled = true
	_waiting.clear()
	_steps.clear()
	for task in _in_flight.keys():
		WorkerThreadPool.wait_for_task_completion(task)
	_in_flight.clear()
	_mutex.lock()
	_finished.clear()
	_mutex.unlock()


## One unit of main-thread work: a finished piece's commit, else a step.
func _step() -> bool:
	_mutex.lock()
	var item: Array = _finished.pop_front() if not _finished.is_empty() else []
	_mutex.unlock()
	if not item.is_empty():
		(item[0] as Callable).call(item[1])
		return true
	if not _steps.is_empty():
		_steps.pop_front().call()
		return true
	return false


func _submit() -> void:
	if _cancelled:
		return
	if not _sorted:
		# Farthest first, so the nearest piece pops off the back.
		_waiting.sort_custom(func(a, b): return a[0] > b[0])
		_sorted = true
	while _in_flight.size() < max_in_flight and not _waiting.is_empty():
		var piece: Array = _waiting.pop_back()
		_in_flight[WorkerThreadPool.add_task(_run.bind(piece[1], piece[2]))] = true


## Releases the pool slots of finished tasks (each must be waited on once).
func _reap() -> void:
	for task in _in_flight.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_in_flight.erase(task)


func _run(build: Callable, commit: Callable) -> void:
	if _cancelled:
		return
	var result: Variant = build.call()
	_mutex.lock()
	_finished.append([commit, result])
	_mutex.unlock()
