extends CanvasLayer
## Fades between scenes (autoload: LGScenes).

signal scene_changed(scene: Node)

const FADE_TIME := 0.25

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Replaces the current scene. `setup` (optional) is called with the new
## scene's root before it enters the tree, so callers can pass data in.
func change_scene(path_or_packed: Variant, setup := Callable()) -> void:
	if _busy:
		await scene_changed
	_busy = true
	var packed: PackedScene = path_or_packed if path_or_packed is PackedScene else load(path_or_packed)
	await _fade(1.0)
	var tree := get_tree()
	var node := packed.instantiate()
	if setup.is_valid():
		setup.call(node)
	var old := tree.current_scene
	if old:
		old.queue_free()
		await old.tree_exited
	tree.root.add_child(node)
	tree.current_scene = node
	await _fade(0.0)
	_busy = false
	scene_changed.emit(node)


func _fade(target: float) -> void:
	if DisplayServer.get_name() == "headless":
		_rect.color.a = target
		await get_tree().process_frame
		return
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP if target > 0.0 else Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", target, FADE_TIME)
	await tween.finished
