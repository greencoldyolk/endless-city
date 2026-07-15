class_name WorldGen
extends RefCounted
## 世界内容：障碍/暖泡/踏脚箱的生成、回收与无限环绕。
## main 负责场景与编排，这里负责"路上会遇到什么"。
## 所有物件仍是"字典 + Rect2"的轻量表示（详见 docs §20：不提前引入复杂体系）。

# 这个游戏是用来放空的：障碍平均十秒一个，大部分时间只是跑着看城市
const OBSTACLE_GAP_MIN := 1600
const OBSTACLE_GAP_MAX := 3400
const PICKUP_SPAWN_CHANCE := 0.35  # 悬浮物约三分之一概率出现，扑空是常态、遇见是运气
const STEP_BOX_H := 80.0  # 双层箱。箱顶起跳到顶棚需抬升 ~133px < 满跳 194px
const NOTEBOOK_CHANCE := 0.2  # 可站立箱子顶上偶尔有一本笔记本

# 两种"荒城旧物"障碍：A字路障（高，要跳）、泡软的纸箱（中，可以站上去）。
# 检修板已移除：太矮太扁，在湿路面上看不清（素材留在 assets/obstacles/ 备用）
const OBSTACLE_TYPES := [
	{"tex": "res://assets/obstacles/barrier.png", "h": 56.0},
	{"tex": "res://assets/obstacles/box.png", "h": 40.0, "standable": true},
]
# 障碍物是阴天里的旧物：压暗压冷才能沉进场景（素材本身偏亮）
const OBSTACLE_TONE := Color(0.58, 0.59, 0.68)

const BUBBLE_ITEMS := {
	"coffee": {"tex": "res://assets/items/coffee-can.png", "h": 30.0, "tilt": 0.30},
	"bell": {"tex": "res://assets/items/bell.png", "h": 36.0, "tilt": 0.22},
	"umbrella": {"tex": "res://assets/items/umbrella.png", "h": 34.0, "tilt": 0.10},
	"feather": {"tex": "res://assets/items/feather.png", "h": 34.0, "tilt": 0.35},
	"notebook": {"tex": "res://assets/items/notebook.png", "h": 26.0, "tilt": -0.15},
}

# --- main 在 setup 时注入 ---
var world: Node2D
var player: Node2D          # 环绕判定需要（生成完后由 main 赋值）
var ground_y := 0.0
var scene_scale := 1.0
var scene_w := 0.0
var loops := 6
var world_width := 0.0
var baked: Dictionary = {}
var light_xs: Array = []  # 暖光源世界 x（main 注入），接触影的方向偏移用

# --- 生成产物（player/main 直接引用这些数组）---
var obstacles: Array = []   # {rect, hit, node, standable[, note]}
var pickups: Array = []     # {rect, taken, node, item[, roof_only, perch_y]}
var step_boxes: Array = []  # {rect, dx, node, active, chance}
var roof_top := 280.0       # 车站顶棚可行走线（世界 y），从 lights.json 平台标定读取
var _shadows: Fx.ObstacleShadows      # spots[i] 与 obstacles[i] 一一对应
var _box_shadows: Fx.ObstacleShadows  # spots[i] 与 step_boxes[i] 一一对应


## 接触影的光向偏移：靠近暖光源时影子往光的反方向偏（光在左，影偏右）。
## 远离一切光源时归零——阴天环境光下的影子就该端正地躺在正下方
func _light_dx(cx: float) -> float:
	var best := 0.0
	var best_w := 0.0
	for lx in light_xs:
		var d: float = cx - lx
		var ad := absf(d)
		if ad < 420.0 and ad > 1.0:
			var w := 1.0 - ad / 420.0
			if w > best_w:
				best_w = w
				best = signf(d) * 14.0 * w
	return best


func generate_all() -> void:
	_generate_obstacles()
	_generate_pickups()
	_generate_step_boxes()


## 每帧：吃掉的物品从画面移除
func tick() -> void:
	for pickup in pickups:
		if pickup.taken and pickup.node.visible:
			pickup.node.visible = false


## 以 x 为中心、半屏（640px）内的活跃物品数。世界要空，物品要稀：
## 任何生成/复活路径都不允许让半屏内同时出现超过 2 件
func _items_near(x: float, exclude = null, radius: float = 640.0) -> int:
	var n := 0
	for p in pickups:
		if p != exclude and not p.taken \
				and absf(p.rect.position.x + 26.0 - x) < radius:
			n += 1
	return n


func _make_bubble(item_key: String, cx: float, cy: float) -> Fx.ItemBubble:
	var item: Dictionary = BUBBLE_ITEMS[item_key]
	var bubble := Fx.ItemBubble.new()
	bubble.item_tex = load(item.tex)
	bubble.item_h = item.h
	bubble.item_tilt = item.tilt
	bubble.position = Vector2(cx, cy)
	world.add_child(bubble)
	return bubble


func _generate_obstacles() -> void:
	var shadows := Fx.ObstacleShadows.new()
	shadows.ground = ground_y
	_shadows = shadows
	world.add_child(shadows)  # 先加，影子垫在障碍物下面
	# 踏脚箱一带留空：箱子是"道具"，紧邻再放路障会打架（不论该圈箱子出不出）
	var box_xs: Array = []
	for spot in baked.get("step_boxes", []):
		for i in range(loops):
			box_xs.append(spot.x * scene_scale + i * scene_w)
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
		shadows.spots.append(Vector3(x + w / 2.0, w, _light_dx(x + w / 2.0)))
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


func _generate_pickups() -> void:
	# 世界观：物品各有出处——咖啡只在售货机旁、风铃在车站长椅、
	# 伞在水洼段栏杆边、羽毛落在顶棚上。点位标定在 lights.json 的 pickup_spots
	var plats: Array = baked.get("platforms", [])
	if not plats.is_empty():
		roof_top = plats[0][2] * scene_scale
	# 羽毛的出现先掷好骰子：羽毛和风铃同在车站，一圈里只出一个（羽毛优先）
	var feather_loops := {}
	for spot in baked.get("pickup_spots", []):
		if spot.get("item", "") == "feather":
			for i in range(loops):
				if randf() <= PICKUP_SPAWN_CHANCE:
					feather_loops[i] = true
	for spot in baked.get("pickup_spots", [{"x": 1500.0, "item": "coffee"}]):
		for i in range(loops):
			var it: String = spot.get("item", "coffee")
			if it == "bell" and feather_loops.has(i):
				continue  # 这一圈顶棚有羽毛，风铃让位
			if it == "feather":
				if not feather_loops.has(i):
					continue
			elif randf() > PICKUP_SPAWN_CHANCE:
				continue  # 这一圈这个点位空着——不是每次路过都有惊喜
			# 水平：以来源为锚随机漂几步，最远约 4 个身位（~200px）
			var cx: float = (spot.x + randf_range(-80.0, 80.0)) * scene_scale + i * scene_w
			# 半空随机高度：低的轻轻一跳、高的要跳到顶（上限留了拾取余量）
			var cy := ground_y - randf_range(130.0, 205.0)
			var on_roof: bool = it == "feather"
			if on_roof:
				# 羽毛悬在顶棚上方一头身处。高度是算出来的窗口：
				# 判定框下沿(cy+30)要高于地面满跳的头顶(y≈200)——跳起来连碰都
				# 碰不到，不会有"蹭到却捡不到"的别扭；又要低于站上顶棚时的
				# 头顶(y≈181)——上了棚跑过去就能穿过拿到
				cy = roof_top - 116.0
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


## 车站前的踏脚箱：跳上箱顶、再跳上车站顶棚——
## 世界里第一件"可以踩的东西"（双层纸箱素材，调亮一档读作"能用"）
func _generate_step_boxes() -> void:
	var tex: Texture2D = load("res://assets/obstacles/jump-boxes.png")
	var w := STEP_BOX_H * tex.get_width() / tex.get_height()
	# 可站立面收窄到上层箱的顶面（素材实测约 22%~72%），
	# 站在下层箱翻盖的空气上会出戏
	var inset := w * 0.22
	var top_w := w * 0.50
	_box_shadows = Fx.ObstacleShadows.new()
	_box_shadows.ground = ground_y
	world.add_child(_box_shadows)
	for spot in baked.get("step_boxes", []):
		for i in range(loops):
			var x: float = spot.x * scene_scale + i * scene_w
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
			var bcx := x + w / 2.0
			_box_shadows.spots.append(
				Vector3(bcx, w * 0.9 if active else 0.0, _light_dx(bcx)))
			step_boxes.append({
				"rect": Rect2(x + inset, ground_y - STEP_BOX_H, top_w, STEP_BOX_H),
				"dx": inset,  # rect 相对贴图左缘的偏移（环绕搬移时同步）
				"w": w,       # 贴图宽（影子宽度用）
				"node": node,
				"active": active,
				"chance": spot.get("chance", 0.5),  # 复活时沿用同一概率
			})
	_box_shadows.queue_redraw()


## 无限世界：场景每循环一模一样，玩家跑进第 5 个循环时把玩家/物件整体
## 左移一个循环宽度，视觉上毫无接缝；甩到身后的障碍和物品向前搬三个循环
## 并复活。返回本次左移量（main 用它同步相机），未触发返回 0。
func wrap() -> float:
	if player.position.x < scene_w * 4.0:
		return 0.0
	var s := scene_w
	player.position.x -= s
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
				for q in step_boxes:  # 踏脚箱一带同样留空
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
		var spot: Vector3 = _shadows.spots[i]
		var scx: float = o.rect.position.x + o.rect.size.x / 2.0
		_shadows.spots[i] = Vector3(scx, spot.y, _light_dx(scx))
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
	_shadows.queue_redraw()
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
		# 复活遵守原始生成规则：按概率空着，且不和别的暖泡挤在一屏
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
	for b in step_boxes:
		var r: Rect2 = b.rect
		r.position.x -= s
		if r.position.x < player.position.x - 1600.0:
			r.position.x += s * 3.0
			revived_boxes.append(b)
		b.rect = r
		b.node.position.x = r.position.x - b.dx
	for b in revived_boxes:
		var crowded := false
		for q in step_boxes:
			if q != b and q.active \
					and absf(q.rect.position.x - b.rect.position.x) < 600.0:
				crowded = true
				break
		b.active = not crowded and randf() < b.chance
		b.node.visible = b.active
	# 箱影跟随箱子（active=false 时宽度置 0 隐藏）
	for i in step_boxes.size():
		var b: Dictionary = step_boxes[i]
		var bcx: float = b.node.position.x + b.w / 2.0
		_box_shadows.spots[i] = Vector3(
			bcx, b.w * 0.9 if b.active else 0.0, _light_dx(bcx))
	_box_shadows.queue_redraw()
	return s
