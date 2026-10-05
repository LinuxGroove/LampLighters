class_name ActionPrompt
extends HBoxContainer
## A button glyph plus a label, e.g. [A] Relight. Follows the last used device.

var action := ""
var text := "":
	set(value):
		text = value
		if _label:
			_label.text = value

var _icon: TextureRect
var _key_label: Label
var _label: Label


static func make(p_action: String, p_text: String, icon_size := 40) -> ActionPrompt:
	var p := ActionPrompt.new()
	p.action = p_action
	p.text = p_text
	p.custom_minimum_size.y = icon_size
	p.set_meta("icon_size", icon_size)
	return p


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var size: int = get_meta("icon_size", 40)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(size, size)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)
	_key_label = Label.new()
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_key_label)
	_label = Label.new()
	_label.text = text
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	var router := get_node_or_null("/root/LGInput")
	if router:
		router.device_changed.connect(func(_f): _refresh())
	_refresh()


func set_action(p_action: String, p_text: String) -> void:
	action = p_action
	text = p_text
	_refresh()


func _refresh() -> void:
	if _icon == null:
		return
	var router := get_node_or_null("/root/LGInput")
	var tex: Texture2D = router.glyph_for_action(action) if router else null
	_icon.texture = tex
	_icon.visible = tex != null
	_key_label.visible = tex == null
	if tex == null and router:
		_key_label.text = "[%s]" % router.label_for_action(action)
