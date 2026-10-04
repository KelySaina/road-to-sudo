class_name InteractiveOverlays
extends Node
## Hosts the full-screen interactive-program overlays — the nano editor, the
## less/tail pager, and the su password prompt — on a CanvasLayer above
## everything else, and wires them to the EventBus signals Game emits.
##
## Both the campaign/practice play screen and the 2D adventure world install this,
## so interactive programs (nano, less, tail -f, su) work the same wherever the
## player runs them. It is a Node (added as a child of the host) so its EventBus
## connections and overlay nodes are torn down with the host scene automatically.
## The host passes a `focus_cb` that returns input focus to its own terminal when
## an overlay closes, and listens to `editor_closed` to echo a save confirmation.

signal editor_closed(saved: bool)

var editor: Control
var pager: Control
var prompt: Control
var _focus: Callable


## Add this to `parent` and build the overlays. `focus_cb` (if valid) is called
## whenever an overlay hands control back.
func install(parent: Node, focus_cb: Callable = Callable()) -> void:
	_focus = focus_cb
	parent.add_child(self)
	# Above the toast layer (CanvasLayer 10) and the adventure overlay (layer 5),
	# so a stray achievement toast can't draw over an open editor or prompt.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	editor = preload("res://scripts/ui/editor.gd").new()
	layer.add_child(editor)
	editor.closed.connect(_on_editor_closed)
	EventBus.editor_requested.connect(func(data: Dictionary): editor.open(data))

	pager = preload("res://scripts/ui/pager.gd").new()
	layer.add_child(pager)
	pager.closed.connect(_refocus)
	EventBus.viewer_requested.connect(_on_viewer_requested)

	prompt = preload("res://scripts/ui/prompt.gd").new()
	layer.add_child(prompt)
	prompt.answered.connect(func(text: String): Game.resolve_prompt(text, false); _refocus())
	prompt.cancelled.connect(func(): Game.resolve_prompt("", true); _refocus())
	EventBus.prompt_requested.connect(func(data: Dictionary): prompt.ask(str(data.get("label", "Password: "))))


## True while any overlay is on screen — hosts guard their own input on this so
## their world/terminal shortcuts don't fire underneath an open program.
func any_visible() -> bool:
	return (editor != null and editor.visible) \
		or (pager != null and pager.visible) \
		or (prompt != null and prompt.visible)


func _refocus() -> void:
	if _focus.is_valid():
		_focus.call()


func _on_editor_closed(saved: bool) -> void:
	_refocus()
	editor_closed.emit(saved)


func _on_viewer_requested(data: Dictionary) -> void:
	if str(data.get("mode", "page")) == "follow":
		pager.follow(str(data.get("title", "")), str(data.get("content", "")), str(data.get("kind", "sys")))
	else:
		pager.page(str(data.get("title", "")), str(data.get("content", "")))
