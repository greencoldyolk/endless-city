class_name Hud
extends CanvasLayer
## 游戏内 UI：左下心情面板、右上电台开关、重开按钮、右下隐藏测试菜单。
## 双语文案表也住在这里。对 main 的接口：
##   信号 radio_pressed / rain_pressed（main 执行实际逻辑后回调显示方法）
##   set_radio_display(name_key, fm_key) / set_rain_state(on) /
##   update_mood(mood, mood_max, resting) / toggle_ui_hidden()

signal radio_pressed
signal rain_pressed

const SCREEN_W := 1280.0
const SCREEN_H := 720.0

# --- 双语文案（默认中文；右下角隐藏小菜单切换，测试用）---
const TEXTS := {
	"mood": {"zh": "心情", "en": "MOOD"},
	"calm": {"zh": "平静", "en": "Calm"},
	"resting": {"zh": "休息中", "en": "Resting"},
	"low": {"zh": "想坐一会儿", "en": "Need a rest"},
	"down": {"zh": "有些低落", "en": "Feeling low"},
	"radio_off": {"zh": "电台 · 关", "en": "Radio · Off"},
	"radio_hint": {"zh": "轻点打开", "en": "Tap to tune in"},
	"st0": {"zh": "旧电台 · Two Second Signal", "en": "Old Radio · Two Second Signal"},
	"st0fm": {"zh": "91.7 FM · 轻点换台", "en": "91.7 FM · Tap to switch"},
	"st1": {"zh": "旧电台 · Rain Archive", "en": "Old Radio · Rain Archive"},
	"st1fm": {"zh": "88.1 FM · 轻点换台", "en": "88.1 FM · Tap to switch"},
	"menu_lang": {"zh": "English", "en": "ZH"},  # "文"不在字体子集里，用 ZH
	"restart": {"zh": "重开", "en": "Redo"},
	"menu_rain_on": {"zh": "雨 · 开", "en": "Rain · On"},
	"menu_rain_off": {"zh": "雨 · 关", "en": "Rain · Off"},
	# 注意：ui-font 是字体子集，新增中文文案前要确认字形在子集里
	# （"隐藏界面"四个字都不在，会渲染成方块）
	"menu_hide": {"zh": "UI · 关", "en": "Hide UI"},
}

var _lang := "zh"
var _rain_on := true       # 只作菜单文案显示，真实状态在 main
var _ui_hidden := false    # 截图模式：隐藏全部 UI（只留右下角的"·"当回程票）
var _radio_name_key := ""  # 当前台的文案 key（空 = 关），语言切换时重刷用
var _radio_fm_key := ""
var _prev_mood := -1.0     # 检测心情增减触发光条脉冲

var _ui_font: FontFile
var _lbl_mood: Label
var _lbl_mood_title: Label
var _mood_glow: Fx.MoodGlow
var _cloud_icon: TextureRect
var _cloud_base_y := 0.0
var _lbl_station: Label
var _lbl_fm: Label
var _radio_icon: TextureRect
var _mood_panel: Panel
var _radio_panel: Panel
var _menu_panel: Panel
var _btn_lang: Button
var _btn_rain: Button
var _btn_restart: Button
var _btn_hide: Button


func _t(key: String) -> String:
	return TEXTS[key][_lang]


func _ready() -> void:
	_ui_font = load("res://assets/fonts/ui-font.otf")

	# 左下：心情面板（概念图同款：软云贴图 + "心情/状态词" + 辉光条）
	_mood_panel = _make_panel(Vector2(24, SCREEN_H - 112), Vector2(300, 88))
	add_child(_mood_panel)
	_cloud_icon = TextureRect.new()
	_cloud_icon.texture = load("res://assets/ui/mood-cloud.png")
	_cloud_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cloud_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cloud_icon.position = Vector2(16, 17)
	_cloud_icon.size = Vector2(64, 54)
	_cloud_base_y = _cloud_icon.position.y
	_mood_panel.add_child(_cloud_icon)
	_lbl_mood_title = _make_label(_t("mood"), 13, Color(0.72, 0.74, 0.82, 0.6), Vector2(94, 16))
	_mood_panel.add_child(_lbl_mood_title)
	_lbl_mood = _make_label(_t("calm"), 25, Color(0.92, 0.93, 0.97), Vector2(94, 33))
	_lbl_mood.size = Vector2(98, 36)  # 固定框 + 垂直居中：字号缩小时不上浮
	_lbl_mood.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mood_panel.add_child(_lbl_mood)
	_mood_glow = Fx.MoodGlow.new()
	_mood_glow.position = Vector2(196, 25)  # 含 12px 辉光边距，胶囊本体 80x14
	_mood_glow.size = Vector2(104, 38)
	_mood_panel.add_child(_mood_glow)

	# 右上：电台（台标文字 + 收音机图标按钮，点击开关背景音乐）
	_radio_panel = _make_panel(Vector2(SCREEN_W - 352, 14), Vector2(272, 58))
	add_child(_radio_panel)
	_lbl_station = _make_label(_t("radio_off"), 14, Color(0.85, 0.86, 0.92, 0.5), Vector2(16, 9))
	_radio_panel.add_child(_lbl_station)
	_lbl_fm = _make_label(_t("radio_hint"), 12, Color(0.72, 0.74, 0.82, 0.4), Vector2(16, 32))
	_radio_panel.add_child(_lbl_fm)
	_radio_icon = TextureRect.new()
	_radio_icon.texture = load("res://assets/items/radio.png")
	_radio_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radio_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_radio_icon.position = Vector2(216, 9)
	_radio_icon.size = Vector2(42, 40)
	_radio_icon.modulate = Color(1, 1, 1, 0.45)
	_radio_panel.add_child(_radio_icon)
	var radio_btn := Button.new()
	radio_btn.flat = true
	radio_btn.position = Vector2.ZERO
	radio_btn.size = _radio_panel.size
	radio_btn.pressed.connect(func(): radio_pressed.emit())
	_radio_panel.add_child(radio_btn)

	# 重开按钮（键盘 R 同效）。"↺"字形 web 字体里没有会变方块，用文字
	_btn_restart = Button.new()
	_btn_restart.text = _t("restart")
	_btn_restart.flat = true
	_btn_restart.add_theme_font_override("font", _ui_font)
	_btn_restart.add_theme_font_size_override("font_size", 15)
	_btn_restart.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88, 0.5))
	_btn_restart.position = Vector2(SCREEN_W - 72, 22)
	_btn_restart.size = Vector2(56, 40)
	_btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	add_child(_btn_restart)

	# 右下角隐藏测试菜单：一个几乎看不见的"·"，点开语言/雨/截图模式（测试用）
	var dot := Button.new()
	dot.text = "·"
	dot.flat = true
	dot.add_theme_font_size_override("font_size", 34)
	dot.add_theme_color_override("font_color", Color(1, 1, 1, 0.16))
	dot.position = Vector2(SCREEN_W - 48, SCREEN_H - 52)
	dot.size = Vector2(40, 44)
	dot.pressed.connect(func():
		# 截图模式下"·"是唯一的回程票：按一下恢复界面
		if _ui_hidden:
			set_ui_hidden(false)
		else:
			_menu_panel.visible = not _menu_panel.visible)
	add_child(dot)

	_menu_panel = _make_panel(Vector2(SCREEN_W - 186, SCREEN_H - 192), Vector2(150, 132))
	_menu_panel.visible = false
	add_child(_menu_panel)
	_btn_lang = _make_menu_button(_t("menu_lang"), Vector2(10, 8))
	_btn_lang.pressed.connect(func():
		_lang = "en" if _lang == "zh" else "zh"
		_refresh_texts())
	_menu_panel.add_child(_btn_lang)
	_btn_rain = _make_menu_button(_t("menu_rain_on"), Vector2(10, 48))
	_btn_rain.pressed.connect(func(): rain_pressed.emit())
	_menu_panel.add_child(_btn_rain)
	_btn_hide = _make_menu_button(_t("menu_hide"), Vector2(10, 88))
	_btn_hide.pressed.connect(func(): set_ui_hidden(true))
	_menu_panel.add_child(_btn_hide)


func _process(_delta: float) -> void:
	# 云朵慢呼吸：2px 起伏
	_cloud_icon.position.y = _cloud_base_y + 2.0 * sin(Time.get_ticks_msec() / 1000.0 * 1.1)


## 每帧由 main 喂心情状态：数值藏进"词 + 光条"，不给玩家看数字。
## 心情骤增（拾取）光条亮一下，骤减（撞击）暗一口
func update_mood(mood: float, mood_max: float, resting: bool) -> void:
	var pct := mood / mood_max
	_mood_glow.value = pct
	if _prev_mood >= 0.0:
		if mood - _prev_mood > 5.0:
			_mood_glow.pulse = 1.0
		elif _prev_mood - mood > 5.0:
			_mood_glow.pulse = -0.7
	_prev_mood = mood
	var word := _t("calm")
	if resting:
		word = _t("resting")
	elif pct < 0.3:
		word = _t("low")
	elif pct < 0.65:
		word = _t("down")
	if _lbl_mood.text != word:
		_lbl_mood.text = word
		# 心情词可用宽度到光条为止（x=196），"想坐一会儿/Feeling low"这类长词缩字号
		_fit_label(_lbl_mood, 25, 94.0)


## 电台显示：传台名/FM 的文案 key，空串 = 关台
func set_radio_display(name_key: String, fm_key: String) -> void:
	_radio_name_key = name_key
	_radio_fm_key = fm_key
	var active := name_key != ""
	_lbl_station.add_theme_color_override("font_color",
		Color(0.9, 0.91, 0.95, 0.95) if active else Color(0.85, 0.86, 0.92, 0.5))
	_radio_icon.modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.45)
	_refresh_texts()


## 雨的真实状态在 main，这里只同步菜单文案
func set_rain_state(on: bool) -> void:
	_rain_on = on
	_refresh_texts()


## 截图模式：隐藏全部 UI，只留右下角几乎看不见的"·"作为恢复入口（键盘 H 同效）
func set_ui_hidden(hidden: bool) -> void:
	_ui_hidden = hidden
	_mood_panel.visible = not hidden
	_radio_panel.visible = not hidden
	_btn_restart.visible = not hidden
	_menu_panel.visible = false


func toggle_ui_hidden() -> void:
	set_ui_hidden(not _ui_hidden)


## 语言切换后刷新所有静态文案（心情状态词在 update_mood 里每帧对齐，不用管）
func _refresh_texts() -> void:
	_lbl_mood_title.text = _t("mood")
	_btn_lang.text = _t("menu_lang")
	_btn_rain.text = _t("menu_rain_on") if _rain_on else _t("menu_rain_off")
	_btn_hide.text = _t("menu_hide")
	_btn_restart.text = _t("restart")
	if _radio_name_key != "":
		_lbl_station.text = _t(_radio_name_key)
		_lbl_fm.text = _t(_radio_fm_key)
	else:
		_lbl_station.text = _t("radio_off")
		_lbl_fm.text = _t("radio_hint")
	# 台名区可用宽度到收音机图标为止（x=216），长台名自动缩字号
	_fit_label(_lbl_station, 14, 192.0)
	_fit_label(_lbl_fm, 12, 192.0)


func _make_panel(pos: Vector2, panel_size: Vector2) -> Panel:
	# 概念图质感：更深更透的底 + 大圆角 + 6% 白细描边（毛玻璃模糊暂不做）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.52)
	style.set_corner_radius_all(20)
	style.border_color = Color(1, 1, 1, 0.06)
	style.set_border_width_all(1)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.position = pos
	panel.size = panel_size
	return panel


func _make_label(text: String, font_size: int, color: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_override("font", _ui_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_menu_button(text: String, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.position = pos
	btn.size = Vector2(130, 34)
	btn.add_theme_font_override("font", _ui_font)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(0.85, 0.87, 0.93, 0.85))
	return btn


## 按可用宽度收缩字号：文案随语言变长时自动缩小（心情词/电台台名用）
func _fit_label(lbl: Label, base_size: int, max_w: float) -> void:
	var f: Font = lbl.get_theme_font("font")
	var s := base_size
	while s > 10 and f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	lbl.add_theme_font_size_override("font_size", s)
