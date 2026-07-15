extends Node2D
## 编排层：场景搭建（母图循环/暖光/流云/雨）、相机与休息演出、电台、输入。
## 世界内容的生成回收在 world_gen.gd，UI 在 hud.gd，特效类在 fx.gd，
## 角色在 player.gd。720p 逻辑分辨率。

const SCREEN_W := 1280.0
const SCREEN_H := 720.0
const SURFACE_FRACTION := 0.68   # 碰撞地面线在屏幕高度的位置（调小=往护栏/画面深处挪）
const SCENE_LOOPS := 6
const CAMERA_SMOOTHING := 5.0

# 两层流云：放大倍率让云朵尺寸和烤死的天错开，相对运动才可读；
# 双速差制造天空自身的纵深。速度慢（px/s），防晕安全
const CLOUD_LAYERS := [
	{"scale": 1.3, "alpha": 0.45, "speed": 24.0},
	{"scale": 1.8, "alpha": 0.32, "speed": 44.0},
]

# 两首歌 = 两个台：开局默认播 91.7，点击循环 91.7 → 88.1 → 关 → 91.7
# name/fm 是 hud 文案表的 key
const STATIONS := [
	{"path": "res://assets/music/Two Second Signal.mp3", "name": "st0", "fm": "st0fm"},
	{"path": "res://assets/music/Rain Archive.mp3", "name": "st1", "fm": "st1fm"},
]

var world: Node2D
var player: Node2D
var gen: WorldGen
var hud: Hud
var camera_x := 0.0
var ground_y := SCREEN_H * SURFACE_FRACTION

var _scene_w := 0.0
var _cloud_sprites: Array[Sprite2D] = []
var _bgm: AudioStreamPlayer
var _radio_idx := -1    # -1=关，0/1=两个台
var _zoom := 1.0        # 休息演出：<1 时镜头绕玩家拉远
var _was_resting := false

# --- 天气 ---
var _rain: Fx.RainLayer
var _rain_on := true  # 美术基准天气是小雨黄昏，默认开；T 键切换
var _dim: CanvasModulate


func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	# --- 场景循环长图 ---
	var scene_tex: Texture2D = load("res://assets/scenes/loop.png")
	var scene_scale := SCREEN_H / scene_tex.get_height()
	_scene_w = scene_tex.get_width() * scene_scale
	for i in range(SCENE_LOOPS):
		var s := Sprite2D.new()
		s.texture = scene_tex
		s.centered = false
		s.scale = Vector2(scene_scale, scene_scale)
		s.position = Vector2(i * _scene_w, 0)
		world.add_child(s)

	# --- 暖光源（位置来自烘焙的 lights.json，用真正的 2D 光）---
	var baked: Dictionary = {}
	var lights_file := FileAccess.open("res://assets/scenes/lights.json", FileAccess.READ)
	if lights_file:
		baked = JSON.parse_string(lights_file.get_as_text())
		for light in baked.lights:
			for i in range(SCENE_LOOPS):
				world.add_child(_make_warm_light(
					Vector2(light.x * scene_scale + i * _scene_w,
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
	_rain = Fx.RainLayer.new()
	_rain.ground = ground_y
	add_child(_rain)
	_set_rain(_rain_on, true)

	# --- 世界内容：障碍、暖泡、踏脚箱 ---
	gen = WorldGen.new()
	gen.world = world
	gen.ground_y = ground_y
	gen.scene_scale = scene_scale
	gen.scene_w = _scene_w
	gen.loops = SCENE_LOOPS
	gen.world_width = _scene_w * SCENE_LOOPS
	gen.baked = baked
	# 暖光源世界 x 列表：接触影（角色/障碍/箱子）的方向偏移用
	var light_xs: Array = []
	for light in baked.get("lights", []):
		for i in range(SCENE_LOOPS):
			light_xs.append(light.x * scene_scale + i * _scene_w)
	gen.light_xs = light_xs
	gen.generate_all()

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
	player.scene_loop_w = _scene_w
	for z in baked.get("puddles", []):
		player.puddle_zones.append(Vector2(z[0] * scene_scale, z[1] * scene_scale))
	# 可站立平台：车站顶棚（每循环重复）+ 踏脚箱（世界坐标，共享数组引用）
	for pl in baked.get("platforms", []):
		player.platform_zones.append(Vector3(
			pl[0] * scene_scale, pl[1] * scene_scale, pl[2] * scene_scale))
	player.step_boxes = gen.step_boxes
	player.light_xs = light_xs
	world.add_child(player)
	gen.player = player

	# --- 环境声：风声常驻低音量循环 ---
	var wind := AudioStreamPlayer.new()
	wind.stream = load("res://assets/sounds/wind.mp3")
	wind.stream.loop = true
	wind.volume_db = linear_to_db(0.22)
	if AudioServer.get_bus_index("Ambient") != -1:
		wind.bus = "Ambient"
	add_child(wind)
	wind.play()

	# --- UI ---
	hud = Hud.new()
	add_child(hud)
	hud.radio_pressed.connect(_toggle_radio)
	hud.rain_pressed.connect(func(): _set_rain(not _rain_on))

	# 背景音乐播放器；开局直接拧开第一个台（网页端要等首次点按解锁音频，
	# 解锁后正在播的流会自然接进来）
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = linear_to_db(0.3)
	add_child(_bgm)
	_toggle_radio()


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
		hud.set_radio_display(st.name, st.fm)
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
		hud.set_radio_display("", "")
		# 世界回来：环境声恢复原样
		if lp != null:
			tween.tween_method(
				func(v: float): AudioServer.set_bus_volume_db(ambient, v),
				AudioServer.get_bus_volume_db(ambient), 0.0, 1.2)
			tween.tween_method(
				func(v: float): lp.cutoff_hz = v,
				lp.cutoff_hz, 20000.0, 1.2)


func _set_rain(on: bool, instant := false) -> void:
	# 雨来/雨停都是渐变的：雨量 2 秒内淡入淡出，环境色同步滑向雨色。
	# 压暗差刻意很小——雨是天气不是滤镜，画面基调仍由母图负责
	_rain_on = on
	if hud != null:
		hud.set_rain_state(on)
	var strength_target := 1.0 if on else 0.0
	var dim_target := Color(0.86, 0.87, 0.93) if on else Color(0.9, 0.9, 0.94)
	if instant:
		_rain.strength = strength_target
		_dim.color = dim_target
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_rain, "strength", strength_target, 2.0)
	tween.tween_property(_dim, "color", dim_target, 2.0)


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


func _process(delta: float) -> void:
	camera_x -= gen.wrap()  # 无限世界：环绕时相机同步左移
	player.step(delta, gen.world_width, gen.obstacles, gen.pickups)
	gen.tick()

	# 相机平滑跟随（防晕），世界反向移动
	var target: float = clamp(
		player.position.x - SCREEN_W * 0.4, 0.0, gen.world_width - SCREEN_W
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

	hud.update_mood(player.mood, player.MOOD_MAX, player.resting)


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
			hud.toggle_ui_hidden()
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
