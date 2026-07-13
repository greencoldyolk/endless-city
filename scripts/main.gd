extends Node2D
## 世界编排：场景循环、障碍/物品、相机、暖光、心情条 UI、触屏输入。
## 从 pygame 版 scene_map.py + main.py 平移，720p 逻辑分辨率。

const SCREEN_W := 1280.0
const SCREEN_H := 720.0
const SURFACE_FRACTION := 0.72   # 碰撞地面线在屏幕高度的位置
const SCENE_LOOPS := 3
const CAMERA_SMOOTHING := 5.0

const OBSTACLE_GAP_MIN := 600
const OBSTACLE_GAP_MAX := 1350
const PICKUP_GAP_MIN := 1650
const PICKUP_GAP_MAX := 2700

var world: Node2D
var player: Node2D
var camera_x := 0.0
var world_width := 0.0
var ground_y := SCREEN_H * SURFACE_FRACTION

var obstacles: Array = []  # {rect: Rect2, hit: bool, node: ColorRect}
var pickups: Array = []    # {rect: Rect2, taken: bool, node: ColorRect}

var _mood_fill: ColorRect


func _ready() -> void:
	world = Node2D.new()
	add_child(world)

	# --- 场景循环长图 ---
	var scene_tex: Texture2D = load("res://assets/scenes/loop.png")
	var scene_scale := SCREEN_H / scene_tex.get_height()
	var scene_w := scene_tex.get_width() * scene_scale
	world_width = scene_w * SCENE_LOOPS
	for i in range(SCENE_LOOPS):
		var s := Sprite2D.new()
		s.texture = scene_tex
		s.centered = false
		s.scale = Vector2(scene_scale, scene_scale)
		s.position = Vector2(i * scene_w, 0)
		world.add_child(s)

	# --- 暖光源（位置来自烘焙的 lights.json，用真正的 2D 光）---
	var lights_file := FileAccess.open("res://assets/scenes/lights.json", FileAccess.READ)
	if lights_file:
		var data: Dictionary = JSON.parse_string(lights_file.get_as_text())
		for light in data.lights:
			for i in range(SCENE_LOOPS):
				world.add_child(_make_warm_light(Vector2(
					light.x * scene_scale + i * scene_w,
					light.y * scene_scale
				)))

	_generate_obstacles()
	_generate_pickups()

	# --- 玩家 ---
	player = load("res://scripts/player.gd").new()
	player.ground_y = ground_y
	player.position = Vector2(200, 0)
	world.add_child(player)

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


func _make_warm_light(pos: Vector2) -> PointLight2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0)
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
	light.energy = 0.55
	light.texture_scale = 1.6
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
	var x := 2100.0
	while x < world_width - 900.0:
		var rect := Rect2(x, ground_y - 165.0, 33, 33)
		var node := ColorRect.new()
		node.position = rect.position
		node.size = rect.size
		node.color = Color(0.92, 0.75, 0.43)
		world.add_child(node)
		pickups.append({"rect": rect, "taken": false, "node": node})
		x += randf_range(PICKUP_GAP_MIN, PICKUP_GAP_MAX)


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


func _input(event: InputEvent) -> void:
	# 触屏：右半屏点按 = 跳，左半屏按住 = 减速（鼠标模拟同样生效）
	if event is InputEventScreenTouch:
		var half := get_viewport().get_visible_rect().size.x / 2.0
		if event.pressed and event.position.x >= half:
			player.touch_jump_queued = true
		elif event.position.x < half:
			player.touch_slow = event.pressed
