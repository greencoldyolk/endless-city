extends Node2D
## 玩家：自动奔跑、跳跃、心情系统、动画状态机。
## 从 pygame 版 player.py 平移，数值对应 720p 逻辑分辨率。
## 坐标约定和 pygame 一致：position = 碰撞盒左上角。


# --- 数值表（对应 pygame settings.py 的 720p 刻度）---
const RUN_SPEED := 250.0
const ACCEL := 600.0
const DECEL := 900.0
const GRAVITY := 3000.0
const JUMP_SPEED := -1080.0
# 可变跳跃高度：松开跳跃键后上升段的重力倍率。轻点≈半高的小跳，
# 按住到顶才是满跳（满跳高度不变，够到最高的暖泡）。调大=小跳更矮
const JUMP_CUT_GRAVITY := 2.0
const BOX_W := 50.0
const BOX_H := 95.0
# 单图模式：true = 用简化版单张立绘 + 程序化动画（前倾/俯仰/落地压扁），
# false = 用动漫版逐帧动画。两套素材都在 assets/characters/ 里，随时切换对比。
const USE_SIMPLE := false

# 各动画组的目标高度分别标定：跑步/跳跃是前倾姿势，
# 若按同一高度归一化会显得比站立时大一圈（人物大小跳变）
const IDLE_HEIGHT := 110.0
const RUN_HEIGHT := 97.0
const JUMP_HEIGHT := 100.0
const RUN_CYCLES_PER_SEC := 1.5  # 跑步循环节奏（步频），播放 fps = 节奏 × 帧数，换帧数不用调
const RUN_TILT := 0.0  # 跑步姿势整体回正角度（弧度，负=往后转正）。写实版姿势正常不需要；Q版素材前倾过猛时用 -0.12
const RUN_CROSSFADE := false  # 帧间淡化：多帧后可能不再需要，先关掉对比
const RUN_BOB := 3.0
const IDLE_BOB := 1.5

# 倒影：绕地面线翻转的第二个精灵。压扁比例 <1 是水面透视的廉价近似，
# 也让倒影不会伸得太长盖住前景
const REFL_SQUASH := 0.85
const REFL_ALPHA := 0.30
const REFL_FEATHER := 40.0  # 水坑边缘的淡入淡出宽度（px）

# 顶部擦过宽恕：脚只沉进障碍物顶部这个比例以内不算撞。
# 障碍本来就不挡路（只是心情触发器），"差一点就过去了"应该默许而不是惩罚
const GRAZE_FRACTION := 0.45

const MOOD_MAX := 100.0
const MOOD_HIT_COST := 25.0
const MOOD_PICKUP_RESTORE := 30.0
const MOOD_REST_REGEN := 40.0

var ground_y := 518.0  # main 在 _ready 里设置

var vx := 0.0
var vy := 0.0
var on_ground := true
var mood := MOOD_MAX
var resting := false
var hit_flash := 0.0
var anim_time := 0.0
var land_timer := 0.0
var idle_time := 0.0

# 触屏输入（main 的 _input 写入）
var touch_slow := false
var touch_jump_queued := false
var touch_jump_held := false

var _sprite: Sprite2D
var _sprite_next: Sprite2D
var _refl: Sprite2D
var _frames_idle: Array[Texture2D] = []
var _frames_run: Array[Texture2D] = []
var _frames_jump: Array[Texture2D] = []
var _scale_idle := 1.0
var _scale_run := 1.0
var _scale_jump := 1.0
var _snd_land: AudioStreamPlayer
var _snd_land_light: AudioStreamPlayer
var _snd_pickup: AudioStreamPlayer
var _snd_rest: AudioStreamPlayer
var _snd_steps_dry: AudioStreamPlayer
var _snd_steps_wet: AudioStreamPlayer
const STEP_DRY_VOL := 0.32
const STEP_WET_VOL := 0.16
const STEP_DUCK := 0.12  # 特殊音效（伞/电台碎片）播放时脚步几乎退场

var _snd_bell: AudioStreamPlayer
var _snd_umbrella: AudioStreamPlayer
var _step_duck := 1.0
var puddle_zones: Array = []  # 单个场景循环内的水坑区间（Vector2(x0,x1)，世界像素）
var scene_loop_w := 0.0


func _ready() -> void:
	if USE_SIMPLE:
		_frames_idle = _load_frames(["simple"])
		_frames_run = _frames_idle
		_frames_jump = _frames_idle
	else:
		_frames_idle = _load_frames(["idle"])
		_frames_run = _load_frame_series("run")
		_frames_jump = _load_frame_series("jump")
	_scale_idle = _set_scale(_frames_idle, IDLE_HEIGHT)
	_scale_run = _set_scale(_frames_run, RUN_HEIGHT)
	_scale_jump = _set_scale(_frames_jump, JUMP_HEIGHT)

	_sprite = Sprite2D.new()
	_sprite.modulate = Color(0.92, 0.9, 0.96)  # 轻微暮色环境调
	_sprite.light_mask = 2  # 吃场景暖光源（光源只照角色层）
	add_child(_sprite)
	# 第二张精灵用于帧间交叉淡化：8帧动画在60帧世界里会显得"卡"，
	# 当前帧和下一帧按进度混合后，感知流畅度接近翻倍
	_sprite_next = Sprite2D.new()
	_sprite_next.light_mask = 2
	add_child(_sprite_next)

	# 水面倒影：同一张贴图绕地面线翻转压扁、半透明，只在水坑区间上方浮现。
	# 波动不逐帧抖位置，用最简 canvas shader 对 UV 做随时间的水平正弦偏移
	_refl = Sprite2D.new()
	_refl.light_mask = 1  # 不吃角色暖光：倒影的亮度只由自身透明度决定
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// 活水两件事：UV 水平正弦偏移（波纹），离水面越远越淡（消散）。
// 贴图脚在 UV.y=1，翻转后正贴着水面线，所以淡出方向是 UV.y 从 1 到 0
varying vec4 v_mod;
void vertex() { v_mod = COLOR; }
void fragment() {
	vec2 uv = UV;
	uv.x = clamp(uv.x + sin(TIME * 2.4 + UV.y * 16.0) * 0.010, 0.0, 1.0);
	vec4 tex = texture(TEXTURE, uv);
	tex.a *= mix(0.25, 1.0, UV.y);
	COLOR = tex * v_mod;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_refl.material = mat
	add_child(_refl)

	_snd_land = _make_sound("res://assets/sounds/land.mp3", 0.35)
	_snd_land_light = _make_sound("res://assets/sounds/light-land.mp3", 0.35)
	_snd_pickup = _make_sound("res://assets/sounds/picup-new.mp3", 0.4)
	_snd_umbrella = _make_sound("res://assets/sounds/umbrella-sound.mp3", 0.5)
	_snd_rest = _make_sound("res://assets/sounds/rest.wav", 0.45)
	# 脚步声两套：日常=普通跑步声，水坑=水花版（音量压低，尖锐感只做点缀）
	_snd_steps_dry = _make_sound("res://assets/sounds/normal-running.mp3", STEP_DRY_VOL)
	_snd_steps_dry.stream.loop = true
	_snd_steps_wet = _make_sound("res://assets/sounds/run-wet.mp3", STEP_WET_VOL)
	_snd_steps_wet.stream.loop = true
	# 脚步和落地走环境声总线：电台开着时会被整体压低闷化（网页端无此总线则留在 Master）
	if AudioServer.get_bus_index("Ambient") != -1:
		_snd_steps_dry.bus = "Ambient"
		_snd_steps_wet.bus = "Ambient"
		_snd_land.bus = "Ambient"
		_snd_land_light.bus = "Ambient"
	# 风铃：渐出版由 wind-bell.mp3 处理而来（后半段余弦淡出，像被风带走）
	_snd_bell = _make_sound("res://assets/sounds/wind-bell-fade.wav", 0.5)

	position.y = ground_y - BOX_H


func _load_frames(names: Array) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for n in names:
		frames.append(load("res://assets/characters/%s.png" % n))
	return frames


func _load_frame_series(prefix: String) -> Array[Texture2D]:
	# 帧数由管线切出来的文件数决定（换角色/加帧不用改代码）
	var frames: Array[Texture2D] = []
	var i := 0
	while ResourceLoader.exists("res://assets/characters/%s_%d.png" % [prefix, i]):
		frames.append(load("res://assets/characters/%s_%d.png" % [prefix, i]))
		i += 1
	return frames


func _set_scale(frames: Array[Texture2D], target_height: float) -> float:
	var tallest := 0.0
	for f in frames:
		tallest = max(tallest, f.get_height())
	return target_height / tallest


func _update_step_loop(p: AudioStreamPlayer, want: bool) -> void:
	if want and not p.playing:
		p.play()
	elif not want and p.playing:
		p.stop()


func _make_sound(path: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = linear_to_db(volume)
	add_child(p)
	return p


## 每帧由 main 调用。obstacles/pickups 是字典数组（rect/hit/taken），world_width 是世界宽度。
func step(delta: float, world_width: float, obstacles: Array, pickups: Array) -> void:
	# --- 水平：自动奔跑，按住减速；休息时强制停下 ---
	var slowing := touch_slow \
		or Input.is_physical_key_pressed(KEY_S) \
		or Input.is_physical_key_pressed(KEY_DOWN)
	var target_vx := 0.0 if (resting or slowing) else RUN_SPEED

	if vx < target_vx:
		vx = min(vx + ACCEL * delta, target_vx)
	elif vx > target_vx:
		vx = max(vx - DECEL * delta, target_vx)
	position.x = clamp(position.x + vx * delta, 0.0, world_width - BOX_W)

	# --- 垂直：跳跃与重力（触屏排队一次跳跃，键盘按下沿触发）---
	var jump_key := Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_physical_key_pressed(KEY_W) \
		or Input.is_physical_key_pressed(KEY_UP)
	var jump_wanted := touch_jump_queued or (jump_key and not _jump_key_was_down)
	_jump_key_was_down = jump_key
	touch_jump_queued = false

	if jump_wanted and on_ground and not resting:
		vy = JUMP_SPEED
		on_ground = false

	# 可变跳跃：上升途中松开跳跃键，重力加倍把这一跳"收短"；
	# 下落段永远用正常重力，落地手感不变
	var g := GRAVITY
	if vy < 0.0 and not (jump_key or touch_jump_held):
		g *= JUMP_CUT_GRAVITY
	vy += g * delta
	position.y += vy * delta

	var was_in_air := not on_ground
	if position.y + BOX_H >= ground_y:
		position.y = ground_y - BOX_H
		var impact := vy
		vy = 0.0
		on_ground = true
		if was_in_air:
			# 落地音效按下坠速度分两档：小跳（不足满跳 85% 的冲量）用轻版
			# ——脚尖点地，不是整个人砸下来；响度仍随冲量连续变化
			var force: float = clamp(impact / absf(JUMP_SPEED), 0.3, 1.0)
			var snd := _snd_land_light if force < 0.85 else _snd_land
			snd.volume_db = linear_to_db(0.26 * force)
			snd.play()
			land_timer = 0.12

	if on_ground:
		anim_time += delta * (vx / RUN_SPEED)
	if land_timer > 0.0:
		land_timer -= delta
	idle_time += delta

	# --- 脚步声：只在贴地奔跑时循环；起跳/减速/休息即停，不与跳跃落地音重叠。
	# 踩在水坑区间里用水花版，其余路面用闷版 ---
	var stepping := on_ground and not resting and vx > RUN_SPEED * 0.4
	var in_puddle := false
	if stepping and scene_loop_w > 0.0:
		var sx := fposmod(position.x + BOX_W / 2.0, scene_loop_w)
		for zone in puddle_zones:
			if sx >= zone.x and sx <= zone.y:
				in_puddle = true
				break
	_update_step_loop(_snd_steps_wet, stepping and in_puddle)
	_update_step_loop(_snd_steps_dry, stepping and not in_puddle)
	# 闪避：伞/风铃这类"时刻音效"响起时脚步退后，播完平滑恢复
	var special := _snd_umbrella.playing or _snd_bell.playing
	_step_duck += ((STEP_DUCK if special else 1.0) - _step_duck) * minf(1.0, 8.0 * delta)
	_snd_steps_dry.volume_db = linear_to_db(STEP_DRY_VOL * _step_duck)
	_snd_steps_wet.volume_db = linear_to_db(STEP_WET_VOL * _step_duck)

	# --- 障碍与正向物品（心情系统）---
	var box := Rect2(position.x, position.y, BOX_W, BOX_H)
	# 撞击判定比身体小一圈：蹭到边角不算撞（温和跑酷，判定宁松勿严）；
	# 物品拾取仍用全身框，奖励从宽
	var hit_box := box.grow_individual(-14.0, -10.0, -14.0, -6.0)
	for obstacle in obstacles:
		if not obstacle.hit and hit_box.intersects(obstacle.rect):
			# 只蹭到障碍上部（脚的下沉深度不足 GRAZE_FRACTION）→ 宽恕，
			# 不标记 hit：真沉得更深时下一帧照样会触发
			var sink: float = hit_box.end.y - obstacle.rect.position.y
			if sink < obstacle.rect.size.y * GRAZE_FRACTION:
				continue
			obstacle.hit = true
			mood = max(0.0, mood - MOOD_HIT_COST)
			hit_flash = 0.3  # "暖光熄一下"演出在 _update_sprite 的体色段
			_snd_land.volume_db = linear_to_db(0.12)
			_snd_land.play()
			if mood <= 0.0:
				resting = true
				_snd_rest.play()
	for pickup in pickups:
		if not pickup.taken and box.intersects(pickup.rect):
			pickup.taken = true
			mood = min(MOOD_MAX, mood + MOOD_PICKUP_RESTORE)
			var item: String = pickup.get("item", "")
			if item == "bell":
				# 风铃不叠通用提示音，奖励就是那一串被风带走的铃声
				_snd_bell.play()
			elif item == "umbrella":
				_snd_umbrella.play()
			else:
				_snd_pickup.play()

	# --- 休息：心情回满自动继续 ---
	if resting:
		mood += MOOD_REST_REGEN * delta
		if mood >= MOOD_MAX:
			mood = MOOD_MAX
			resting = false
	if hit_flash > 0.0:
		hit_flash -= delta

	_update_sprite()
	queue_redraw()

var _jump_key_was_down := false


func _update_sprite() -> void:
	var texture: Texture2D
	var frame_scale: float
	var next_texture: Texture2D = null
	var next_alpha := 0.0
	var is_running := false
	if not on_ground:
		var speed := absf(JUMP_SPEED)
		var index := 4
		if vy < -0.72 * speed:
			index = 0
		elif vy < -0.33 * speed:
			index = 1
		elif vy < 0.0:
			index = 2
		elif vy < 0.46 * speed:
			index = 3
		texture = _frames_jump[min(index, _frames_jump.size() - 1)]
		frame_scale = _scale_jump
	elif land_timer > 0.0:
		texture = _frames_jump[-1]
		frame_scale = _scale_jump
	elif resting or vx < 10.0:
		texture = _frames_idle[0]
		frame_scale = _scale_idle
	else:
		is_running = true
		var run_fps := RUN_CYCLES_PER_SEC * _frames_run.size()
		texture = _frames_run[int(anim_time * run_fps) % _frames_run.size()]
		frame_scale = _scale_run
		# 跑步循环做帧间淡化（其他状态不需要：跳跃按速度选帧、待机静止）
		if RUN_CROSSFADE and not USE_SIMPLE and _frames_run.size() > 1:
			var pos := anim_time * run_fps
			next_texture = _frames_run[(int(pos) + 1) % _frames_run.size()]
			# 只在每帧末尾一小段里向下一帧过渡：全程淡化会让两个
			# 姿势长时间半透明叠着，看起来像重影
			next_alpha = clampf((pos - floor(pos) - 0.6) / 0.4, 0.0, 1.0)

	_sprite.texture = texture
	# 图形底边中心对齐碰撞盒底边中心，再叠加重心起伏
	var h := texture.get_height() * frame_scale
	_sprite.position = Vector2(BOX_W / 2.0, BOX_H - h / 2.0 - _bob())

	# 单图模式的程序化动画：跑步前倾、空中俯仰、落地压扁回弹
	var squash := Vector2.ONE
	if USE_SIMPLE:
		var lean := 0.10 * (vx / RUN_SPEED)
		var pitch := 0.0
		if not on_ground:
			pitch = clampf(vy / 9000.0, -0.10, 0.14)
		_sprite.rotation = lean + pitch
		if land_timer > 0.0:
			var t := land_timer / 0.12
			squash = Vector2(1.0 + 0.10 * t, 1.0 - 0.10 * t)
	else:
		# 撞击反馈：轻微后仰 + 身体压缩，0.3 秒内自然回正（配合失温，不用特效）
		var hit_k := hit_flash / 0.3
		_sprite.rotation = (RUN_TILT if is_running else 0.0) - 0.4 * hit_flash
		if hit_k > 0.0:
			squash = Vector2(1.0 + 0.07 * hit_k, 1.0 - 0.07 * hit_k)
	_sprite.scale = Vector2(frame_scale, frame_scale) * squash

	# 温度=心情：失去的不是生命值，是温暖。心情越低整个人越冷越灰。
	# 撞击反馈是"暖光熄一下"：身上像有盏小灯最后亮了一瞬（前 1/3 暖亮），
	# 随即熄掉沉入冷灰（后 2/3），再回到当前体温。全程没有红色、没有粒子
	var warmth: float = mood / MOOD_MAX
	var body_tone := Color(0.5, 0.51, 0.58).lerp(Color(0.72, 0.73, 0.83), warmth)
	if hit_flash > 0.0:
		var k := hit_flash / 0.3  # 撞击瞬间 1 → 演出结束 0
		if k > 0.66:
			body_tone = body_tone.lerp(Color(1.0, 0.86, 0.62), (k - 0.66) / 0.34 * 0.85)
		else:
			body_tone = body_tone.lerp(Color(0.4, 0.41, 0.48), k / 0.66 * 0.85)
	_sprite.modulate = body_tone

	# 下一帧精灵：同位置同变换，透明度=帧进度
	if next_texture != null:
		_sprite_next.visible = true
		_sprite_next.texture = next_texture
		var nh := next_texture.get_height() * frame_scale
		_sprite_next.position = Vector2(BOX_W / 2.0, BOX_H - nh / 2.0 - _bob())
		_sprite_next.rotation = _sprite.rotation
		_sprite_next.scale = _sprite.scale
		_sprite_next.modulate = _sprite.modulate
		_sprite_next.modulate.a = next_alpha
	else:
		_sprite_next.visible = false

	# --- 水面倒影：跟随本体，绕地面线镜像；只在水坑上方浮现 ---
	var cover := _puddle_cover()
	_refl.visible = cover > 0.01
	if _refl.visible:
		var ground_local := ground_y - position.y  # 地面线在角色局部坐标里的位置
		_refl.texture = _sprite.texture
		_refl.position = Vector2(_sprite.position.x,
			ground_local + (ground_local - _sprite.position.y) * REFL_SQUASH)
		_refl.rotation = -_sprite.rotation
		_refl.scale = Vector2(_sprite.scale.x, -_sprite.scale.y * REFL_SQUASH)
		# 偏冷偏暗的水色，透明度随水坑边缘淡入淡出
		_refl.modulate = Color(0.6, 0.66, 0.8, REFL_ALPHA * cover)


## 脚下在水坑里的程度：0=不在水上，1=完全在水上；边缘 REFL_FEATHER 内线性过渡。
## 复用湿脚步声的水坑标定（lights.json 的 puddles），但那边是硬判定、这边要软边缘
func _puddle_cover() -> float:
	if scene_loop_w <= 0.0:
		return 0.0
	var sx := fposmod(position.x + BOX_W / 2.0, scene_loop_w)
	var cover := 0.0
	for zone in puddle_zones:
		if sx > zone.x and sx < zone.y:
			cover = maxf(cover, clampf(minf(sx - zone.x, zone.y - sx) / REFL_FEATHER, 0.0, 1.0))
	return cover


func _bob() -> float:
	if not on_ground or land_timer > 0.0:
		return 0.0
	if resting or vx < 10.0:
		return IDLE_BOB * (0.5 - 0.5 * cos(TAU * 0.5 * idle_time))
	# 重心起伏每步一次（一个循环两步），直接用循环相位
	var cycle := fmod(anim_time * RUN_CYCLES_PER_SEC, 1.0)
	return RUN_BOB * (0.5 - 0.5 * cos(2.0 * TAU * cycle))


func _draw() -> void:
	# 接触阴影：软椭圆贴在地面，跳起时变淡变小。
	# 水坑上把影子让位给倒影——两者叠加会像脚下有两个东西；
	# 留一成残影当水面的轻微压暗
	var height_above := ground_y - (position.y + BOX_H)
	var closeness: float = max(0.0, 1.0 - height_above / 130.0)
	var dry := 1.0 - _puddle_cover() * 0.9
	if closeness <= 0.0 or dry <= 0.05:
		return
	var w := BOX_W * 1.7 * (0.6 + 0.4 * closeness)
	var shadow_y := ground_y - position.y
	draw_set_transform(Vector2(BOX_W / 2.0, shadow_y), 0.0, Vector2(w / 2.0, w / 14.0))
	draw_circle(Vector2.ZERO, 1.0, Color(0.04, 0.04, 0.07, 0.31 * closeness * dry))
