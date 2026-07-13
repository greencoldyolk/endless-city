extends Node2D
## 世界编排：场景循环、障碍/物品、相机、暖光、心情条 UI、触屏输入。
## 从 pygame 版 scene_map.py + main.py 平移，720p 逻辑分辨率。

const SCREEN_W := 1280.0
const SCREEN_H := 720.0
const SURFACE_FRACTION := 0.68   # 碰撞地面线在屏幕高度的位置（调小=往护栏/画面深处挪）
const SCENE_LOOPS := 3
const CAMERA_SMOOTHING := 5.0

const OBSTACLE_GAP_MIN := 600
const OBSTACLE_GAP_MAX := 1350

var world: Node2D
var player: Node2D
var camera_x := 0.0
var world_width := 0.0
var ground_y := SCREEN_H * SURFACE_FRACTION

var obstacles: Array = []  # {rect: Rect2, hit: bool, node: ColorRect}
var pickups: Array = []    # {rect: Rect2, taken: bool, node: Node2D}

var _mood_fill: ColorRect
var _baked: Dictionary = {}
var _scene_scale := 1.0
var _scene_w := 0.0


## 售货机旁的咖啡：蜂蜜琥珀色的"保护泡"包着一罐咖啡，轻轻浮动缓慢呼吸。
## 色谱是灰调琥珀（非街机金币黄）：中央 #E8CC83、外缘 #DDB65A、
## 深轮廓 #A87938、左上小高光 #F3E0AC，不做整圈光晕
class CoffeeBubble extends Node2D:
	var _t := randf() * TAU
	var _base_y := 0.0
	var _can: Texture2D = load("res://assets/items/coffee-can.png")
	var _bubble: Texture2D = load("res://assets/items/bubble.png")

	func _ready() -> void:
		_base_y = position.y

	func _process(delta: float) -> void:
		_t += delta
		position.y = _base_y + 6.0 * sin(_t * 1.3)
		scale = Vector2.ONE * (1.0 + 0.05 * sin(_t * 2.1))  # 轻微呼吸

	func _draw() -> void:
		# 三明治：气泡底 → 咖啡罐 → 半透明气泡膜罩在最上（罐子像泡在膜里）
		var bw := 72.0
		var bh := bw * _bubble.get_height() / _bubble.get_width()
		var bubble_rect := Rect2(-bw / 2.0, -bh / 2.0, bw, bh)
		draw_texture_rect(_bubble, bubble_rect, false)
		var ch := 26.0
		var cw := ch * _can.get_width() / _can.get_height()
		draw_set_transform(Vector2.ZERO, 0.30, Vector2.ONE)  # 罐子向右倾约17度
		draw_texture_rect(_can, Rect2(-cw / 2.0, -ch / 2.0, cw, ch), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(_bubble, bubble_rect, false, Color(1, 1, 1, 0.4))


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

	# 全场景轻微压暗（阴天暮色基调；UI 在独立 CanvasLayer 不受影响）
	var dim := CanvasModulate.new()
	dim.color = Color(0.9, 0.9, 0.94)
	add_child(dim)

	_generate_obstacles()
	_generate_pickups()

	# --- 玩家 ---
	player = load("res://scripts/player.gd").new()
	player.ground_y = ground_y
	player.position = Vector2(200, 0)
	# 水坑区间（母图标定，脚步声干湿切换用）
	player.scene_loop_w = scene_w
	for z in baked.get("puddles", []):
		player.puddle_zones.append(Vector2(z[0] * scene_scale, z[1] * scene_scale))
	world.add_child(player)

	# --- 环境声：风声常驻低音量循环 ---
	var wind := AudioStreamPlayer.new()
	wind.stream = load("res://assets/sounds/wind.mp3")
	wind.stream.loop = true
	wind.volume_db = linear_to_db(0.22)
	add_child(wind)
	wind.play()

	# --- 心情条（唯一常驻 UI）---
	var ui := CanvasLayer.new()
	add_child(ui)
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(24, 24)
	bar_bg.size = Vector2(160, 6)
	bar_bg.color = Color(0.16, 0.17, 0.19)
	ui.add_child(bar_bg)
	_mood_fill = ColorRect.new()
	_mood_fill.position = Vector2(24, 24)
	_mood_fill.size = Vector2(160, 6)
	_mood_fill.color = Color(0.66, 0.7, 0.62)
	ui.add_child(_mood_fill)

	# --- 重开按钮（右上角，键盘 R 同效）---
	var restart := Button.new()
	restart.text = "↺"
	restart.flat = true
	restart.add_theme_font_size_override("font_size", 34)
	restart.add_theme_color_override("font_color", Color(0.75, 0.78, 0.74, 0.55))
	restart.position = Vector2(SCREEN_W - 68, 12)
	restart.size = Vector2(52, 52)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	ui.add_child(restart)


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


func _generate_obstacles() -> void:
	var x := 1350.0
	while x < world_width - 900.0:
		var w := randf_range(45, 70)
		var h := randf_range(50, 85)
		var rect := Rect2(x, ground_y - h, w, h)
		var node := ColorRect.new()
		node.position = rect.position
		node.size = rect.size
		node.color = Color(0.2, 0.19, 0.17)
		world.add_child(node)
		obstacles.append({"rect": rect, "hit": false, "node": node})
		x += randf_range(OBSTACLE_GAP_MIN, OBSTACLE_GAP_MAX)


func _generate_pickups() -> void:
	# 世界观：物品不凭空散落——每圈经过自动售货机时，机器旁浮着一罐咖啡，
	# 跑过即拾取（不必跳）。点位标定在 lights.json 的 pickup_spots
	for spot in _baked.get("pickup_spots", [{"x": 1500.0}]):
		for i in range(SCENE_LOOPS):
			# 水平：以售货机为源头随机漂几步，离机器最远约 4 个身位（~200px）
			var cx: float = (spot.x + randf_range(-80.0, 80.0)) * _scene_scale + i * _scene_w
			# 半空随机高度：低的轻轻一跳、高的要跳到顶（上限留了拾取余量）
			var cy := ground_y - randf_range(130.0, 205.0)
			var bubble := CoffeeBubble.new()
			bubble.position = Vector2(cx, cy)
			world.add_child(bubble)
			pickups.append({
				"rect": Rect2(cx - 26, cy - 30, 52, 60),
				"taken": false,
				"node": bubble,
			})


func _process(delta: float) -> void:
	player.step(delta, world_width, obstacles, pickups)

	# 吃掉的物品从画面移除
	for pickup in pickups:
		if pickup.taken and pickup.node.visible:
			pickup.node.visible = false

	# 相机平滑跟随（防晕），世界反向移动
	var target: float = clamp(
		player.position.x - SCREEN_W * 0.4, 0.0, world_width - SCREEN_W
	)
	camera_x += (target - camera_x) * minf(1.0, CAMERA_SMOOTHING * delta)
	world.position.x = -camera_x

	_mood_fill.size.x = 160.0 * (player.mood / player.MOOD_MAX)


func _unhandled_input(event: InputEvent) -> void:
	# 用 _unhandled_input：被 UI（重开按钮）吃掉的点击不会再触发跳跃
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	# 触屏：右半屏点按 = 跳，左半屏按住 = 减速（鼠标模拟同样生效）
	if event is InputEventScreenTouch:
		var half := get_viewport().get_visible_rect().size.x / 2.0
		if event.pressed and event.position.x >= half:
			player.touch_jump_queued = true
		elif event.position.x < half:
			player.touch_slow = event.pressed
