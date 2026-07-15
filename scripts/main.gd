extends Node2D
## 世界编排：场景循环、障碍/物品、相机、暖光、心情条 UI、触屏输入。
## 从 pygame 版 scene_map.py + main.py 平移，720p 逻辑分辨率。

const SCREEN_W := 1280.0
const SCREEN_H := 720.0
const SURFACE_FRACTION := 0.68   # 碰撞地面线在屏幕高度的位置（调小=往护栏/画面深处挪）
const SCENE_LOOPS := 6
const CAMERA_SMOOTHING := 5.0

# 这个游戏是用来放空的：障碍平均十秒一个，大部分时间只是跑着看城市
const OBSTACLE_GAP_MIN := 1600
const OBSTACLE_GAP_MAX := 3400
const PICKUP_SPAWN_CHANCE := 0.35  # 悬浮物约三分之一概率出现，扑空是常态、遇见是运气

var world: Node2D
var player: Node2D
var camera_x := 0.0
var world_width := 0.0
var ground_y := SCREEN_H * SURFACE_FRACTION

var obstacles: Array = []  # {rect: Rect2, hit: bool, node: ColorRect}
var pickups: Array = []    # {rect: Rect2, taken: bool, node: Node2D}
var _obstacle_shadows: ObstacleShadows  # spots[i] 与 obstacles[i] 一一对应
var _step_boxes: Array = []  # {rect: Rect2, node, active} 车站前的踏脚箱
var _roof_top := 280.0  # 车站顶棚可行走线（世界 y），从 lights.json 平台标定读取

const STEP_BOX_H := 80.0  # 双层箱。箱顶起跳到顶棚需抬升 ~133px < 满跳 194px

var _baked: Dictionary = {}
var _scene_scale := 1.0
var _scene_w := 0.0

# 两层流云：放大倍率让云朵尺寸和烤死的天错开，相对运动才可读；
# 双速差制造天空自身的纵深。速度慢（px/s），防晕安全
const CLOUD_LAYERS := [
	{"scale": 1.3, "alpha": 0.45, "speed": 24.0},
	{"scale": 1.8, "alpha": 0.32, "speed": 44.0},
]
var _cloud_sprites: Array[Sprite2D] = []

# --- UI（左下心情面板 + 右上电台开关 + 右下隐藏测试菜单）---
var _ui_font: FontFile
var _lbl_mood: Label
var _lbl_mood_title: Label
var _mood_glow: MoodGlow
var _cloud_icon: TextureRect
var _cloud_base_y := 0.0
var _lbl_station: Label
var _lbl_fm: Label
var _radio_icon: TextureRect
var _bgm: AudioStreamPlayer
var _radio_idx := -1  # -1=关，0/1=两个台
var _prev_mood := -1.0  # 检测心情增减触发光条脉冲
var _zoom := 1.0        # 休息演出：<1 时镜头绕玩家拉远
var _was_resting := false
var _ui_hidden := false # 截图模式：隐藏全部 UI（只留右下角的"·"当回程票）
var _ui_layer: CanvasLayer
var _mood_panel: Panel
var _radio_panel: Panel
var _menu_dot: Button

# --- 双语文案（默认中文；右下角隐藏小菜单切换，测试用）---
var _lang := "zh"
var _menu_panel: Panel
var _btn_lang: Button
var _btn_rain: Button
var _btn_restart: Button
var _btn_hide: Button
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
	"menu_lang": {"zh": "English", "en": "中文"},
	"restart": {"zh": "重开", "en": "Redo"},
	"menu_rain_on": {"zh": "雨 · 开", "en": "Rain · On"},
	"menu_rain_off": {"zh": "雨 · 关", "en": "Rain · Off"},
	"menu_hide": {"zh": "隐藏界面", "en": "Hide UI"},
}


func _t(key: String) -> String:
	return TEXTS[key][_lang]

# --- 天气 ---
var _rain: RainLayer
var _rain_on := true  # 美术基准天气是小雨黄昏，默认开；T 键切换
var _dim: CanvasModulate


## 雨丝层（屏幕空间，挂在相机之外）：小雨基调——细、疏、半透明。
## 每滴雨带一个随机景深 d：近的长、快、清楚，远的短而淡，一层节点画出纵深；
## 屏幕上的斜度 = 风 + 相机反向速度，跑起来雨向身后斜，停下来回到风的方向
class RainLayer extends Node2D:
	const COUNT := 90           # 小雨密度：疏一点，雨是氛围不是特效
	const WIND := -55.0         # 雨的横向漂移（px/s，向左，与流云同向）
	const RAIN_COLOR := Color(0.78, 0.82, 0.92)
	var ground := 489.0         # 溅落线（屏幕坐标），main 设置
	var cam_vx := 0.0           # 相机速度，main 每帧写入
	var strength := 0.0         # 0~1 雨量，开关雨时渐变
	var _drops: Array = []      # [x, y, 景深d, 落点偏移]
	var _splashes: Array = []   # [x, y, 年龄]

	func _ready() -> void:
		for i in range(COUNT):
			_drops.append(_spawn(true))

	func _spawn(anywhere: bool) -> Array:
		var d := randf_range(0.35, 1.0)
		# 落点带景深：远的雨（d 小）落在画面深处的路面上，近的雨落得更低，
		# 溅落点才不会排成一条直线
		var land_off := lerpf(-26.0, 18.0, d) + randf_range(-8.0, 8.0)
		var y := randf_range(-720.0, 489.0) if anywhere else randf_range(-90.0, -10.0)
		return [randf_range(-60.0, 1520.0), y, d, land_off]

	func _process(delta: float) -> void:
		var drift := WIND - cam_vx * 0.6
		for drop in _drops:
			var d: float = drop[2]
			drop[0] += drift * d * delta
			drop[1] += lerpf(380.0, 680.0, d) * delta
			if drop[1] > ground + drop[3]:
				# 近处的雨滴落地溅一朵极小的水花（数量封顶；远处的雨直接消失）
				if d > 0.72 and strength > 0.4 and _splashes.size() < 12:
					_splashes.append([drop[0], ground + drop[3], 0.0])
				var n := _spawn(false)
				for k in range(4):
					drop[k] = n[k]
		for s in _splashes:
			s[2] += delta
		_splashes = _splashes.filter(func(s): return s[2] < 0.28)
		queue_redraw()

	func _draw() -> void:
		if strength <= 0.01:
			return
		var drift := WIND - cam_vx * 0.6
		for drop in _drops:
			var d: float = drop[2]
			var vel := Vector2(drift * d, lerpf(380.0, 680.0, d))
			var head := Vector2(drop[0], drop[1])
			var tail := head - vel.normalized() * lerpf(7.0, 15.0, d)
			draw_line(head, tail, Color(RAIN_COLOR, lerpf(0.10, 0.25, d) * strength), 1.0, true)
		for s in _splashes:
			var t: float = s[2] / 0.28
			draw_set_transform(Vector2(s[0], s[1]), 0.0, Vector2(1.0, 0.32))
			draw_arc(Vector2.ZERO, 2.0 + 9.0 * t, 0.0, TAU, 10,
				Color(RAIN_COLOR, 0.30 * (1.0 - t) * strength), 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 心情条（对齐 north-star 概念图）：深色胶囊轨道里一团蓝→紫柔光，
## 前沿带辉光渗出。值变化走缓动，拾取/受击有脉冲呼吸
class MoodGlow extends ColorRect:
	const PAD := 12.0  # 给外溢辉光留的边距，节点尺寸 = 胶囊 + 2*PAD
	var value := 1.0   # 目标值（main 每帧写入）
	var pulse := 0.0   # 1=拾取亮一下，-1=受击暗一口，自动衰减
	var _shown := 1.0  # 显示值，向目标缓动

	func _ready() -> void:
		color = Color(0, 0, 0, 0)
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform float value = 1.0;
uniform float pulse = 0.0;
uniform vec2 pill = vec2(72.0, 15.0);
uniform float pad = 12.0;
void fragment() {
	vec2 p = UV * (pill + 2.0 * pad) - vec2(pad);
	float r = pill.y * 0.5;
	vec2 q = abs(p - pill * 0.5) - (pill * 0.5 - vec2(r));
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	// 轨道：深色胶囊 + 极淡描边
	float track = 1.0 - smoothstep(-0.5, 0.5, d);
	vec4 col = vec4(0.0, 0.0, 0.0, 0.30 * track);
	col.rgb += vec3(1.0) * (1.0 - smoothstep(0.0, 1.2, abs(d))) * 0.06;
	// 光团：左起 value 宽度，蓝→紫渐变缓慢游动，前沿柔和收尾
	float fx = value * pill.x;
	float fill = track * (1.0 - smoothstep(fx - r, fx + 1.0, p.x));
	vec3 grad = mix(vec3(0.55, 0.78, 1.0), vec3(0.66, 0.56, 0.98),
		clamp(p.x / pill.x + 0.12 * sin(TIME * 0.6), 0.0, 1.0));
	grad *= 1.0 + 0.3 * pulse;
	col.rgb = mix(col.rgb, grad, fill);
	col.a = max(col.a, fill * 0.95);
	// 辉光：从光团向外的柔光（胶囊外 + 前沿外双向衰减）
	float g = exp(-max(d, 0.0) * 0.45) * exp(-max(p.x - fx, 0.0) * 0.30);
	g *= 0.35 * (0.6 + 0.4 * value) * (1.0 + 0.5 * pulse);
	col.rgb += grad * g;
	col.a = max(col.a, g);
	COLOR = col;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = sh
		material = mat

	func _process(delta: float) -> void:
		_shown += (value - _shown) * minf(1.0, 8.0 * delta)
		pulse = move_toward(pulse, 0.0, 2.5 * delta)
		var mat := material as ShaderMaterial
		mat.set_shader_parameter("value", _shown)
		mat.set_shader_parameter("pulse", pulse)
		mat.set_shader_parameter("pill", size - Vector2.ONE * PAD * 2.0)
		mat.set_shader_parameter("pad", PAD)


## 障碍物的贴地软影（一个节点画全部，椭圆软斑和角色接触影同一语言）
class ObstacleShadows extends Node2D:
	var spots: Array = []  # Vector2(中心x, 宽度)
	var ground := 0.0

	func _draw() -> void:
		for s in spots:
			draw_set_transform(Vector2(s.x, ground - 3.0), 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, s.y * 0.52, Color(0.04, 0.05, 0.09, 0.20))
			draw_circle(Vector2.ZERO, s.y * 0.36, Color(0.04, 0.05, 0.09, 0.16))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 统一的可收集物语言：所有物件（咖啡/收音机/雨伞）都裹在同一种
## 暖黄"空气团"里——远看只认一种暖黄泡，走近才知道里面是什么。
## 色谱是灰调琥珀（非街机金币黄）：中央 #E8CC83、外缘 #DDB65A、
## 薄轮廓 #A87938、左上小高光 #F3E0AC。轮廓带轻微不规则的缓慢波动，
## 读作"暖空气"而不是"圆圈"
class ItemBubble extends Node2D:
	var item_tex: Texture2D
	var item_h := 28.0
	var item_tilt := 0.0
	var _t := randf() * TAU
	var _base_y := 0.0

	func _ready() -> void:
		_base_y = position.y

	func _process(delta: float) -> void:
		_t += delta
		position.y = _base_y + 6.0 * sin(_t * 1.3)
		scale = Vector2.ONE * (1.0 + 0.05 * sin(_t * 2.1))  # 轻微呼吸
		queue_redraw()  # 轮廓的不规则波动

	func _draw() -> void:
		# 轻微不规则的外形：像被托住的一团暖空气
		var pts := PackedVector2Array()
		for i in range(40):
			var th := TAU * i / 40.0
			var r := 33.0 + 2.0 * sin(3.0 * th + _t * 0.7) + 1.2 * sin(5.0 * th - _t * 0.5)
			pts.append(Vector2(cos(th), sin(th)) * r)
		draw_colored_polygon(pts, Color(Color("ddb65a"), 0.5))
		# 中心比边缘更浅更透：淡淡的雾感梯度
		draw_circle(Vector2.ZERO, 26.0, Color(Color("e8cc83"), 0.72))
		draw_circle(Vector2.ZERO, 18.0, Color(Color("f2e6c2"), 0.55))
		var iw := item_h * item_tex.get_width() / item_tex.get_height()
		draw_set_transform(Vector2.ZERO, item_tilt, Vector2.ONE)
		draw_texture_rect(item_tex, Rect2(-iw / 2.0, -item_h / 2.0, iw, item_h), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(Color("a87938"), 0.7), 1.6, true)
		draw_circle(Vector2(-13, -15), 4.5, Color(Color("f3e0ac"), 0.8))


func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	# --- 场景循环长图 ---
	var scene_tex: Texture2D = load("res://assets/scenes/loop.png")
	var scene_scale := SCREEN_H / scene_tex.get_height()
	var scene_w := scene_tex.get_width() * scene_scale
	_scene_scale = scene_scale
	_scene_w = scene_w
	world_width = scene_w * SCENE_LOOPS
	for i in range(SCENE_LOOPS):
		var s := Sprite2D.new()
		s.texture = scene_tex
		s.centered = false
		s.scale = Vector2(scene_scale, scene_scale)
		s.position = Vector2(i * scene_w, 0)
		world.add_child(s)

	# --- 暖光源（位置来自烘焙的 lights.json，用真正的 2D 光）---
	var baked: Dictionary = {}
	var lights_file := FileAccess.open("res://assets/scenes/lights.json", FileAccess.READ)
	if lights_file:
		var data: Dictionary = JSON.parse_string(lights_file.get_as_text())
		baked = data
		_baked = data
		for light in data.lights:
			for i in range(SCENE_LOOPS):
				world.add_child(_make_warm_light(
					Vector2(light.x * scene_scale + i * scene_w,
							light.y * scene_scale),
					light.get("energy", 0.6),
					light.get("scale", 2.0)
				))

	# --- 流云：从母图天空抠出的云带，挂在相机之外独立缓漂。
	# 母图整体随相机走是"一张画"，天空自己在动才是"一个世界" ---
	var cloud_tex: Texture2D = load("res://assets/scenes/clouds.png")
	for layer in CLOUD_LAYERS:
		var s: float = scene_scale * layer.scale
		var lw := cloud_tex.get_width() * s
		for i in range(3):
			var c := Sprite2D.new()
			c.texture = cloud_tex
			c.centered = false
			c.scale = Vector2(s, s)
			c.flip_h = i % 2 == 1  # 镜像平铺，接缝天然对齐
			c.position = Vector2(i * lw, 0)
			c.modulate = Color(1, 1, 1, layer.alpha)
			c.set_meta("w", lw)
			c.set_meta("speed", layer.speed)
			add_child(c)
			_cloud_sprites.append(c)

	# 全场景轻微压暗（阴天暮色基调；UI 在独立 CanvasLayer 不受影响）
	_dim = CanvasModulate.new()
	_dim.color = Color(0.9, 0.9, 0.94)
	add_child(_dim)

	# --- 雨（屏幕空间，挂在相机之外，画在世界和云之上；T 键开关）---
	_rain = RainLayer.new()
	_rain.ground = ground_y
	add_child(_rain)
	_set_rain(_rain_on, true)

	_generate_obstacles()
	_generate_pickups()
	_generate_step_boxes()

	# --- 环境声总线：电台开着时整体压低+低通闷化，世界退到音乐后面。
	# 网页端跳过：运行时建总线+挂效果会弄死 Web 音频的整个混音器 ---
	if not OS.has_feature("web"):
		var bus_idx := AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "Ambient")
		AudioServer.set_bus_send(bus_idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus_idx, lp)

	# --- 玩家 ---
	player = load("res://scripts/player.gd").new()
	player.ground_y = ground_y
	player.position = Vector2(200, 0)
	# 水坑区间（母图标定，脚步声干湿切换用）
	player.scene_loop_w = scene_w
	for z in baked.get("puddles", []):
		player.puddle_zones.append(Vector2(z[0] * scene_scale, z[1] * scene_scale))
	# 可站立平台：车站顶棚（每循环重复）+ 踏脚箱（世界坐标，共享数组引用）
	for pl in baked.get("platforms", []):
		player.platform_zones.append(Vector3(
			pl[0] * scene_scale, pl[1] * scene_scale, pl[2] * scene_scale))
	player.step_boxes = _step_boxes
	world.add_child(player)

	# --- 环境声：风声常驻低音量循环 ---
	var wind := AudioStreamPlayer.new()
	wind.stream = load("res://assets/sounds/wind.mp3")
	wind.stream.loop = true
	wind.volume_db = linear_to_db(0.22)
	if AudioServer.get_bus_index("Ambient") != -1:
		wind.bus = "Ambient"
	add_child(wind)
	wind.play()

	# --- UI：左下心情面板、右上电台开关、重开按钮 ---
	_ui_font = load("res://assets/fonts/ui-font.otf")
	var ui := CanvasLayer.new()
	add_child(ui)

	_ui_layer = ui

	# 左下：心情面板（概念图同款：软云贴图 + "心情/状态词" + 辉光条）
	var mood_panel := _make_panel(Vector2(24, SCREEN_H - 112), Vector2(300, 88))
	_mood_panel = mood_panel
	ui.add_child(mood_panel)
	_cloud_icon = TextureRect.new()
	_cloud_icon.texture = load("res://assets/ui/mood-cloud.png")
	_cloud_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cloud_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cloud_icon.position = Vector2(16, 17)
	_cloud_icon.size = Vector2(64, 54)
	_cloud_base_y = _cloud_icon.position.y
	mood_panel.add_child(_cloud_icon)
	_lbl_mood_title = _make_label(_t("mood"), 13, Color(0.72, 0.74, 0.82, 0.6), Vector2(94, 16))
	mood_panel.add_child(_lbl_mood_title)
	_lbl_mood = _make_label(_t("calm"), 25, Color(0.92, 0.93, 0.97), Vector2(94, 33))
	_lbl_mood.size = Vector2(98, 36)  # 固定框 + 垂直居中：字号缩小时不上浮
	_lbl_mood.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mood_panel.add_child(_lbl_mood)
	_mood_glow = MoodGlow.new()
	_mood_glow.position = Vector2(196, 25)  # 含 12px 辉光边距，胶囊本体 80x14
	_mood_glow.size = Vector2(104, 38)
	mood_panel.add_child(_mood_glow)

	# 右上：电台（台标文字 + 收音机图标按钮，点击开关背景音乐）
	var radio_panel := _make_panel(Vector2(SCREEN_W - 352, 14), Vector2(272, 58))
	_radio_panel = radio_panel
	ui.add_child(radio_panel)
	_lbl_station = _make_label(_t("radio_off"), 14, Color(0.85, 0.86, 0.92, 0.5), Vector2(16, 9))
	radio_panel.add_child(_lbl_station)
	_lbl_fm = _make_label(_t("radio_hint"), 12, Color(0.72, 0.74, 0.82, 0.4), Vector2(16, 32))
	radio_panel.add_child(_lbl_fm)
	_radio_icon = TextureRect.new()
	_radio_icon.texture = load("res://assets/items/radio.png")
	_radio_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radio_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_radio_icon.position = Vector2(216, 9)
	_radio_icon.size = Vector2(42, 40)
	_radio_icon.modulate = Color(1, 1, 1, 0.45)
	radio_panel.add_child(_radio_icon)
	var radio_btn := Button.new()
	radio_btn.flat = true
	radio_btn.position = Vector2.ZERO
	radio_btn.size = radio_panel.size
	radio_btn.pressed.connect(_toggle_radio)
	radio_panel.add_child(radio_btn)

	# 背景音乐播放器；开局直接拧开第一个台（网页端要等首次点按解锁音频，
	# 解锁后正在播的流会自然接进来）
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = linear_to_db(0.3)
	add_child(_bgm)
	_toggle_radio()

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
	ui.add_child(_btn_restart)

	# 右下角隐藏测试菜单：一个几乎看不见的"·"，点开语言/雨的开关（测试用，无设计）
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
			_set_ui_hidden(false)
		else:
			_menu_panel.visible = not _menu_panel.visible)
	_menu_dot = dot
	ui.add_child(dot)

	_menu_panel = _make_panel(Vector2(SCREEN_W - 186, SCREEN_H - 192), Vector2(150, 132))
	_menu_panel.visible = false
	ui.add_child(_menu_panel)
	_btn_lang = _make_menu_button(_t("menu_lang"), Vector2(10, 8))
	_btn_lang.pressed.connect(func():
		_lang = "en" if _lang == "zh" else "zh"
		_refresh_texts())
	_menu_panel.add_child(_btn_lang)
	_btn_rain = _make_menu_button(_t("menu_rain_on"), Vector2(10, 48))
	_btn_rain.pressed.connect(func():
		_set_rain(not _rain_on)
		_refresh_texts())
	_menu_panel.add_child(_btn_rain)
	_btn_hide = _make_menu_button(_t("menu_hide"), Vector2(10, 88))
	_btn_hide.pressed.connect(func(): _set_ui_hidden(true))
	_menu_panel.add_child(_btn_hide)


# 两首歌 = 两个台：开局默认播 91.7，点击循环 91.7 → 88.1 → 关 → 91.7
const STATIONS := [
	{"path": "res://assets/music/Two Second Signal.mp3", "name": "st0", "fm": "st0fm"},
	{"path": "res://assets/music/Rain Archive.mp3", "name": "st1", "fm": "st1fm"},
]


## 语言切换后刷新所有静态文案（心情状态词在 _process 里每帧对齐，不用管）
func _refresh_texts() -> void:
	_lbl_mood_title.text = _t("mood")
	if _btn_lang != null:  # _ready 里首次开台时菜单还没建出来
		_btn_lang.text = _t("menu_lang")
		_btn_rain.text = _t("menu_rain_on") if _rain_on else _t("menu_rain_off")
		_btn_hide.text = _t("menu_hide")
	if _btn_restart != null:
		_btn_restart.text = _t("restart")
	if _radio_idx >= 0:
		_lbl_station.text = _t(STATIONS[_radio_idx].name)
		_lbl_fm.text = _t(STATIONS[_radio_idx].fm)
	else:
		_lbl_station.text = _t("radio_off")
		_lbl_fm.text = _t("radio_hint")
	# 台名区可用宽度到收音机图标为止（x=216），长台名自动缩字号
	_fit_label(_lbl_station, 14, 192.0)
	_fit_label(_lbl_fm, 12, 192.0)


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


func _toggle_radio() -> void:
	_radio_idx += 1
	if _radio_idx >= STATIONS.size():
		_radio_idx = -1

	var ambient := AudioServer.get_bus_index("Ambient")
	var lp: AudioEffectLowPassFilter = null
	if ambient != -1:
		lp = AudioServer.get_bus_effect(ambient, 0)
	var tween := create_tween().set_parallel(true)

	if _radio_idx >= 0 and ResourceLoader.exists(STATIONS[_radio_idx].path):
		var st: Dictionary = STATIONS[_radio_idx]
		_bgm.stream = load(st.path)
		_bgm.stream.loop = true
		_bgm.play()
		_lbl_station.add_theme_color_override("font_color", Color(0.9, 0.91, 0.95, 0.95))
		_refresh_texts()
		_radio_icon.modulate = Color(1, 1, 1, 1)
		# 世界退后：环境声（风/脚步/落地）在 1.2 秒内压低并闷化
		if lp != null:
			tween.tween_method(
				func(v: float): AudioServer.set_bus_volume_db(ambient, v),
				AudioServer.get_bus_volume_db(ambient), linear_to_db(0.3), 1.2)
			tween.tween_method(
				func(v: float): lp.cutoff_hz = v,
				lp.cutoff_hz, 620.0, 1.2)
	else:
		_radio_idx = -1
		_bgm.stop()
		_lbl_station.add_theme_color_override("font_color", Color(0.85, 0.86, 0.92, 0.5))
		_refresh_texts()
		_radio_icon.modulate = Color(1, 1, 1, 0.45)
		# 世界回来：环境声恢复原样
		if lp != null:
			tween.tween_method(
				func(v: float): AudioServer.set_bus_volume_db(ambient, v),
				AudioServer.get_bus_volume_db(ambient), 0.0, 1.2)
			tween.tween_method(
				func(v: float): lp.cutoff_hz = v,
				lp.cutoff_hz, 20000.0, 1.2)


## 截图模式：隐藏全部 UI，只留右下角几乎看不见的"·"作为恢复入口（键盘 H 同效）
func _set_ui_hidden(hidden: bool) -> void:
	_ui_hidden = hidden
	_mood_panel.visible = not hidden
	_radio_panel.visible = not hidden
	_btn_restart.visible = not hidden
	_menu_panel.visible = false


func _set_rain(on: bool, instant := false) -> void:
	# 雨来/雨停都是渐变的：雨量 2 秒内淡入淡出，环境色同步滑向雨色。
	# 压暗差刻意很小——雨是天气不是滤镜，画面基调仍由母图负责
	_rain_on = on
	var strength_target := 1.0 if on else 0.0
	var dim_target := Color(0.86, 0.87, 0.93) if on else Color(0.9, 0.9, 0.94)
	if instant:
		_rain.strength = strength_target
		_dim.color = dim_target
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_rain, "strength", strength_target, 2.0)
	tween.tween_property(_dim, "color", dim_target, 2.0)


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


## 按可用宽度收缩字号：文案随语言变长时自动缩小（心情词/电台台名用）
func _fit_label(lbl: Label, base_size: int, max_w: float) -> void:
	var f: Font = lbl.get_theme_font("font")
	var s := base_size
	while s > 10 and f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w:
		s -= 1
	lbl.add_theme_font_size_override("font_size", s)


func _make_label(text: String, font_size: int, color: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_override("font", _ui_font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_warm_light(pos: Vector2, energy: float, scale_factor: float) -> PointLight2D:
	var gradient := Gradient.new()
	# 三段衰减：中心亮核 → 缓坡 → 边缘归零，走近灯时亮度是渐进的
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	var light := PointLight2D.new()
	light.texture = tex
	light.position = pos
	light.color = Color(1.0, 0.78, 0.5)
	light.energy = energy
	light.texture_scale = scale_factor
	# 只照角色（light_mask=2）：母图的光晕是烘焙死的，再叠动态光会过曝；
	# 光源只管把路过的人"点亮"
	light.range_item_cull_mask = 2
	return light


# 两种"荒城旧物"障碍：A字路障（高，要跳）、泡软的纸箱（中，可以站上去）。
# 检修板已移除：太矮太扁，在湿路面上看不清（素材留在 assets/obstacles/ 备用）
const OBSTACLE_TYPES := [
	{"tex": "res://assets/obstacles/barrier.png", "h": 56.0},
	{"tex": "res://assets/obstacles/box.png", "h": 40.0, "standable": true},
]
const NOTEBOOK_CHANCE := 0.2  # 可站立箱子顶上偶尔有一本笔记本
# 障碍物是阴天里的旧物：压暗压冷才能沉进场景（素材本身偏亮）
const OBSTACLE_TONE := Color(0.58, 0.59, 0.68)


func _generate_obstacles() -> void:
	var shadows := ObstacleShadows.new()
	shadows.ground = ground_y
	_obstacle_shadows = shadows
	world.add_child(shadows)  # 先加，影子垫在障碍物下面
	# 踏脚箱一带留空：箱子是"道具"，紧邻再放路障会打架（不论该圈箱子出不出）
	var box_xs: Array = []
	for spot in _baked.get("step_boxes", []):
		for i in range(SCENE_LOOPS):
			box_xs.append(spot.x * _scene_scale + i * _scene_w)
	var x := 1350.0
	while x < world_width - 900.0:
		for bx in box_xs:
			if absf(x - bx) < 450.0:
				x = bx + 450.0
				break
		var type: Dictionary = OBSTACLE_TYPES.pick_random()
		var tex: Texture2D = load(type.tex)
		var h: float = type.h
		var w: float = h * tex.get_width() / tex.get_height()
		var rect := Rect2(x, ground_y - h, w, h)
		var node := Sprite2D.new()
		node.texture = tex
		node.centered = false
		node.position = rect.position
		node.scale = Vector2(w / tex.get_width(), h / tex.get_height())
		node.modulate = OBSTACLE_TONE
		world.add_child(node)
		shadows.spots.append(Vector2(x + w / 2.0, w))
		var o := {"rect": rect, "hit": false, "node": node,
			"standable": type.get("standable", false)}
		# 可站立的箱子顶上偶尔有笔记本：贴着箱顶，只有跳上去落稳才能拿
		if o.standable and randf() < NOTEBOOK_CHANCE \
				and _items_near(x + w / 2.0) < 2:
			var cx := x + w / 2.0
			var note := {
				"rect": Rect2(cx - 26, rect.position.y - 64, 52, 60),
				"taken": false,
				"node": _make_bubble("notebook", cx, rect.position.y - 34.0),
				"item": "notebook",
				"perch_y": rect.position.y,  # 必须落稳在这个高度才算拿到
			}
			pickups.append(note)
			o["note"] = note
		obstacles.append(o)
		x += randf_range(OBSTACLE_GAP_MIN, OBSTACLE_GAP_MAX)
	shadows.queue_redraw()


const BUBBLE_ITEMS := {
	"coffee": {"tex": "res://assets/items/coffee-can.png", "h": 30.0, "tilt": 0.30},
	"bell": {"tex": "res://assets/items/bell.png", "h": 36.0, "tilt": 0.22},
	"umbrella": {"tex": "res://assets/items/umbrella.png", "h": 34.0, "tilt": 0.10},
	"feather": {"tex": "res://assets/items/feather.png", "h": 34.0, "tilt": 0.35},
	"notebook": {"tex": "res://assets/items/notebook.png", "h": 26.0, "tilt": -0.15},
}


## 以 x 为中心、半屏（640px）内的活跃物品数。世界要空，物品要稀：
## 任何生成/复活路径都不允许让半屏内同时出现超过 2 件
func _items_near(x: float, exclude = null, radius: float = 640.0) -> int:
	var n := 0
	for p in pickups:
		if p != exclude and not p.taken \
				and absf(p.rect.position.x + 26.0 - x) < radius:
			n += 1
	return n


func _make_bubble(item_key: String, cx: float, cy: float) -> ItemBubble:
	var item: Dictionary = BUBBLE_ITEMS[item_key]
	var bubble := ItemBubble.new()
	bubble.item_tex = load(item.tex)
	bubble.item_h = item.h
	bubble.item_tilt = item.tilt
	bubble.position = Vector2(cx, cy)
	world.add_child(bubble)
	return bubble


## 车站前的踏脚箱：一半概率出现。跳上箱顶、再跳上车站顶棚——
## 世界里第一件"可以踩的东西"（双层纸箱素材，调亮一档读作"能用"）
func _generate_step_boxes() -> void:
	var tex: Texture2D = load("res://assets/obstacles/jump-boxes.png")
	var w := STEP_BOX_H * tex.get_width() / tex.get_height()
	# 可站立面收窄到上层箱的顶面（素材实测约 22%~72%），
	# 站在下层箱翻盖的空气上会出戏
	var inset := w * 0.22
	var top_w := w * 0.50
	for spot in _baked.get("step_boxes", []):
		for i in range(SCENE_LOOPS):
			var x: float = spot.x * _scene_scale + i * _scene_w
			var node := Sprite2D.new()
			node.texture = tex
			node.centered = false
			node.scale = Vector2(w / tex.get_width(), STEP_BOX_H / tex.get_height())
			node.modulate = Color(0.66, 0.67, 0.75)
			node.light_mask = 2  # 吃车站暖灯的光，别当一张死贴纸
			node.position = Vector2(x, ground_y - STEP_BOX_H)
			var active: bool = randf() < spot.get("chance", 0.5)
			node.visible = active
			world.add_child(node)
			_step_boxes.append({
				"rect": Rect2(x + inset, ground_y - STEP_BOX_H, top_w, STEP_BOX_H),
				"dx": inset,  # rect 相对贴图左缘的偏移（环绕搬移时同步）
				"node": node,
				"active": active,
				"chance": spot.get("chance", 0.5),  # 复活时沿用同一概率
			})


func _generate_pickups() -> void:
	# 世界观：物品各有出处——咖啡只在售货机旁、风铃在车站长椅、
	# 伞在水洼段栏杆边、羽毛落在顶棚上。点位标定在 lights.json 的 pickup_spots
	var plats: Array = _baked.get("platforms", [])
	if not plats.is_empty():
		_roof_top = plats[0][2] * _scene_scale
	# 羽毛的出现先掷好骰子：羽毛和风铃同在车站，一圈里只出一个（羽毛优先）
	var feather_loops := {}
	for spot in _baked.get("pickup_spots", []):
		if spot.get("item", "") == "feather":
			for i in range(SCENE_LOOPS):
				if randf() <= PICKUP_SPAWN_CHANCE:
					feather_loops[i] = true
	for spot in _baked.get("pickup_spots", [{"x": 1500.0, "item": "coffee"}]):
		for i in range(SCENE_LOOPS):
			var it: String = spot.get("item", "coffee")
			if it == "bell" and feather_loops.has(i):
				continue  # 这一圈顶棚有羽毛，风铃让位
			if it == "feather":
				if not feather_loops.has(i):
					continue
			elif randf() > PICKUP_SPAWN_CHANCE:
				continue  # 这一圈这个点位空着——不是每次路过都有惊喜
			# 水平：以来源为锚随机漂几步，最远约 4 个身位（~200px）
			var cx: float = (spot.x + randf_range(-80.0, 80.0)) * _scene_scale + i * _scene_w
			# 半空随机高度：低的轻轻一跳、高的要跳到顶（上限留了拾取余量）
			var cy := ground_y - randf_range(130.0, 205.0)
			var on_roof: bool = spot.get("item", "") == "feather"
			if on_roof:
				# 羽毛悬在顶棚上方一头身处。高度是算出来的窗口：
				# 判定框下沿(cy+30)要高于地面满跳的头顶(y≈200)——跳起来连碰都
				# 碰不到，不会有"蹭到却捡不到"的别扭；又要低于站上顶棚时的
				# 头顶(y≈181)——上了棚跑过去就能穿过拿到
				cy = _roof_top - 116.0
			if _items_near(cx) >= 2:
				continue  # 半屏内已有两件物品，这个点位这圈不出
			var bubble := _make_bubble(it, cx, cy)
			pickups.append({
				"rect": Rect2(cx - 26, cy - 30, 52, 60),
				"taken": false,
				"node": bubble,
				"item": it,
				"roof_only": on_roof,  # 防止从棚下起跳把头探进顶棚白捡
			})


## 无限世界：场景每循环一模一样，玩家跑进第 5 个循环时把玩家/相机/物件
## 整体左移一个循环宽度，视觉上毫无接缝；甩到身后的障碍和物品向前搬
## 三个循环并复活。世界从"6 圈到头"变成无尽跑道
func _wrap_world() -> void:
	if player.position.x < _scene_w * 4.0:
		return
	var s := _scene_w
	player.position.x -= s
	camera_x -= s
	var revived_obs: Array = []
	for o in obstacles:
		var r: Rect2 = o.rect
		r.position.x -= s
		if r.position.x < player.position.x - 1600.0:
			r.position.x += s * 3.0
			o.hit = false
			revived_obs.append(o)
		o.rect = r
	for o in revived_obs:
		# 复活的障碍若和别人贴脸（回收目的地本来就有原生障碍），向前挪开
		var r: Rect2 = o.rect
		for attempt in range(8):
			var blocked := false
			for q in obstacles:
				if q != o and absf(q.rect.position.x - r.position.x) < 900.0:
					blocked = true
					break
			if not blocked:
				for q in _step_boxes:  # 踏脚箱一带同样留空
					if absf(q.rect.position.x - r.position.x) < 450.0:
						blocked = true
						break
			if not blocked:
				break
			r.position.x += randf_range(900.0, 1400.0)
		o.rect = r
	for i in obstacles.size():
		var o: Dictionary = obstacles[i]
		o.node.position.x = o.rect.position.x
		var spot: Vector2 = _obstacle_shadows.spots[i]
		_obstacle_shadows.spots[i] = Vector2(
			o.rect.position.x + o.rect.size.x / 2.0, spot.y)
		# 箱顶笔记本跟随箱子；箱子复活时笔记本一起回来
		if o.has("note"):
			var n: Dictionary = o.note
			var cx: float = o.rect.position.x + o.rect.size.x / 2.0
			var nr: Rect2 = n.rect
			nr.position.x = cx - 26.0
			n.rect = nr
			n.node.position.x = cx
			if o in revived_obs and _items_near(cx, n) < 2:
				n.taken = false
				n.node.visible = true
	_obstacle_shadows.queue_redraw()
	# 两遍式：先统一移动全部坐标，再决定复活。回收目的地正是别的物品
	# 所在的循环，若边移边查，未处理者的旧坐标会把真重合看成假远离
	var revived: Array = []
	for p in pickups:
		if p.has("perch_y"):
			continue  # 箱顶笔记本跟着所属箱子搬，不走通用回收
		var r: Rect2 = p.rect
		r.position.x -= s
		if r.position.x < player.position.x - 1600.0:
			r.position.x += s * 3.0
			revived.append(p)
		p.rect = r
		p.node.position.x = r.position.x + 26.0
	# 羽毛排前面：车站区羽毛和风铃靠拥挤检查互斥，先处理的优先占位
	revived.sort_custom(func(a, b):
		return a.item == "feather" and b.item != "feather")
	for p in revived:
		# 复活遵守原始生成规则：一半概率空着，且不和别的暖泡挤在一屏
		# ——扑空是常态、每屏一个焦点，回收不能把世界越跑越满
		var crowded := false
		for q in pickups:
			if q != p and not q.taken \
					and absf(q.rect.position.x - p.rect.position.x) < 900.0:
				crowded = true
				break
		p.taken = crowded or randf() > PICKUP_SPAWN_CHANCE
		p.node.visible = not p.taken

	# 踏脚箱同步搬移（规则同暖泡：两遍式，目的地已有箱子就这轮不出）
	var revived_boxes: Array = []
	for b in _step_boxes:
		var r: Rect2 = b.rect
		r.position.x -= s
		if r.position.x < player.position.x - 1600.0:
			r.position.x += s * 3.0
			revived_boxes.append(b)
		b.rect = r
		b.node.position.x = r.position.x - b.dx
	for b in revived_boxes:
		var crowded := false
		for q in _step_boxes:
			if q != b and q.active \
					and absf(q.rect.position.x - b.rect.position.x) < 600.0:
				crowded = true
				break
		b.active = not crowded and randf() < b.chance
		b.node.visible = b.active


func _process(delta: float) -> void:
	_wrap_world()
	player.step(delta, world_width, obstacles, pickups)

	# 吃掉的物品从画面移除
	for pickup in pickups:
		if pickup.taken and pickup.node.visible:
			pickup.node.visible = false

	# 相机平滑跟随（防晕），世界反向移动
	var target: float = clamp(
		player.position.x - SCREEN_W * 0.4, 0.0, world_width - SCREEN_W
	)
	var prev_cam := camera_x
	camera_x += (target - camera_x) * minf(1.0, CAMERA_SMOOTHING * delta)
	# 雨在屏幕空间，需要知道相机速度才能把雨丝"甩"向奔跑的反方向
	if delta > 0.0:
		_rain.cam_vx = (camera_x - prev_cam) / delta

	# 休息演出：进入休息镜头绕玩家缓缓拉远，音乐退到风雨声后面；起身复原
	if player.resting != _was_resting:
		_was_resting = player.resting
		var tw := create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "_zoom", 0.93 if player.resting else 1.0, 2.2)
		tw.tween_property(_bgm, "volume_db",
			linear_to_db(0.12 if player.resting else 0.3), 2.2)
	# 缩放锚在玩家身上：_zoom=1 时退化为普通的相机平移
	var pivot: Vector2 = player.position + Vector2(25.0, 47.0)
	world.scale = Vector2(_zoom, _zoom)
	world.position = Vector2(
		-camera_x + pivot.x * (1.0 - _zoom), pivot.y * (1.0 - _zoom))

	# 流云缓漂（向左，与世界滚动同向，对比度最低的动法）
	for c in _cloud_sprites:
		var lw: float = c.get_meta("w")
		c.position.x -= c.get_meta("speed") * delta
		if c.position.x <= -lw:
			c.position.x += lw * 3.0

	# 心情面板：数值藏进"词 + 光条"，不给玩家看数字。
	# 心情骤增（拾取）光条亮一下，骤减（撞击）暗一口
	var pct: float = player.mood / player.MOOD_MAX
	_mood_glow.value = pct
	if _prev_mood >= 0.0:
		if player.mood - _prev_mood > 5.0:
			_mood_glow.pulse = 1.0
		elif _prev_mood - player.mood > 5.0:
			_mood_glow.pulse = -0.7
	_prev_mood = player.mood
	# 云朵慢呼吸：2px 起伏
	_cloud_icon.position.y = _cloud_base_y + 2.0 * sin(Time.get_ticks_msec() / 1000.0 * 1.1)
	var word := _t("calm")
	if player.resting:
		word = _t("resting")
	elif pct < 0.3:
		word = _t("low")
	elif pct < 0.65:
		word = _t("down")
	if _lbl_mood.text != word:
		_lbl_mood.text = word
		# 心情词可用宽度到光条为止（x=196），"想坐一会儿/Feeling low"这类长词缩字号
		_fit_label(_lbl_mood, 25, 94.0)


func _unhandled_input(event: InputEvent) -> void:
	# 用 _unhandled_input：被 UI（重开按钮）吃掉的点击不会再触发跳跃
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
			return
		if event.keycode == KEY_T:
			_set_rain(not _rain_on)
			return
		if event.keycode == KEY_H:
			_set_ui_hidden(not _ui_hidden)
			return
	# 触屏：右半屏点按 = 跳（按住跳得高），左半屏按住 = 减速（鼠标模拟同样生效）
	if event is InputEventScreenTouch:
		var half := get_viewport().get_visible_rect().size.x / 2.0
		if event.position.x >= half:
			if event.pressed:
				player.touch_jump_queued = true
			player.touch_jump_held = event.pressed
		else:
			player.touch_slow = event.pressed
