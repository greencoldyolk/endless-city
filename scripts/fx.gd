class_name Fx
extends Object
## 视觉特效类集合：雨、心情光条、障碍软影、暖泡。
## 都是自绘/自更新的独立节点，从 main.gd 拆出（纯搬运，行为不变）。


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
	var value := 1.0   # 目标值（hud 每帧写入）
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


## 统一的可收集物语言：所有物件（咖啡/风铃/雨伞/羽毛/笔记本）都裹在
## 同一种暖黄"空气团"里——远看只认一种暖黄泡，走近才知道里面是什么。
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
