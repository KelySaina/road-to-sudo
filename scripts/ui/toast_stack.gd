extends VBoxContainer
## Toasts for achievements and rank-ups, shown one at a time so they never
## bury the objective panel. Queued ones wait their turn.

const TOAST := preload("res://scenes/ui/toast.tscn")

var _queue: Array = []


func _ready() -> void:
	EventBus.achievement_unlocked.connect(func(a: Dictionary):
		push("ACHIEVEMENT UNLOCKED", a.title, a.description, a.get("icon", "★"), UiTheme.VIOLET))
	EventBus.rank_up.connect(func(r: Dictionary):
		push("RANK UP", r.name, r.get("blurb", ""), "▲", UiTheme.ACCENT))


func push(kicker: String, title: String, body: String, icon: String, color: Color) -> void:
	_queue.append([kicker, title, body, icon, color])
	if get_child_count() == 0:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		return
	var item: Array = _queue.pop_front()
	var t := TOAST.instantiate()
	add_child(t)
	t.setup(item[0], item[1], item[2], item[3], item[4])
	t.tree_exited.connect(_show_next, CONNECT_DEFERRED)
