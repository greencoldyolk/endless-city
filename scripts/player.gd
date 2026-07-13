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
const RUN_TILT := -0.12  # 跑步姿势整体回正角度（弧度，负=往后转正）。Q版素材画得前倾过猛，用这个抵消
const RUN_CROSSFADE := false  # 帧间淡化：多帧后可能不再需要，先关掉对比
const RUN_BOB := 3.0
const IDLE_BOB := 1.5

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

var _sprite: Sprite2D
var _sprite_next: Sprite2D
var _frames_idle: Array[Texture2D] = []
var _frames_run: Array[Texture2D] = []
var _frames_jump: Array[Texture2D] = []
var _scale_idle := 1.0
var _scale_run := 1.0
var _scale_jump := 1.0
var _snd_land: AudioStreamPlayer
var _snd_pickup: AudioStreamPlayer
var _snd_rest: AudioStreamPlayer
var _snd_steps: AudioStreamPlayer


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

	_snd_land = _make_sound("res://assets/sounds/land.mp3", 0.35)
	_snd_pickup = _make_sound("res://assets/sounds/pickup.wav", 0.4)
	_snd_rest = _make_sound("res://assets/sounds/rest.wav", 0.45)
	_snd_steps = _make_sound("res://assets/sounds/run-wet.mp3", 0.3)
	_snd_steps.stream.loop = true

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

	vy += GRAVITY * delta
	position.y += vy * delta

	var was_in_air := not on_ground
	if position.y + BOX_H >= ground_y:
		position.y = ground_y - BOX_H
		vy = 0.0
		on_ground = true
		if was_in_air:
			_snd_land.play()
			land_timer = 0.12

	if on_ground:
		anim_time += delta * (vx / RUN_SPEED)
	if land_timer > 0.0:
		land_timer -= delta
	idle_time += delta

	# --- 脚步声：只在贴地奔跑时循环；起跳/减速/休息即停，不与跳跃落地音重叠 ---
	var stepping := on_ground and not resting and vx > RUN_SPEED * 0.4
	if stepping and not _snd_steps.playing:
		_snd_steps.play()
	elif not stepping and _snd_steps.playing:
		_snd_steps.stop()

	# --- 障碍与正向物品（心情系统）---
	var box := Rect2(position.x, position.y, BOX_W, BOX_H)
	# 撞击判定比身体小一圈：蹭到边角不算撞（温和跑酷，判定宁松勿严）；
	# 物品拾取仍用全身框，奖励从宽
	var hit_box := box.grow_individual(-14.0, -10.0, -14.0, -6.0)
	for obstacle in obstacles:
		if not obstacle.hit and hit_box.intersects(obstacle.rect):
			obstacle.hit = true
			mood = max(0.0, mood - MOOD_HIT_COST)
			hit_flash = 0.3
			if mood <= 0.0:
				resting = true
				_snd_rest.play()
	for pickup in pickups:
		if not pickup.taken and box.intersects(pickup.rect):
			pickup.taken = true
			mood = min(MOOD_MAX, mood + MOOD_PICKUP_RESTORE)
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
		_sprite.rotation = RUN_TILT if is_running else 0.0
	_sprite.scale = Vector2(frame_scale, frame_scale) * squash

	if hit_flash > 0.0:
		_sprite.modulate = Color(1.25, 0.85, 0.85)
	elif resting:
		_sprite.modulate = Color(0.52, 0.53, 0.58)
	else:
		# 阴天暮色的环境调：压暗压冷，暖光源经过时由 PointLight2D 抬回来
		_sprite.modulate = Color(0.72, 0.73, 0.83)

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


func _bob() -> float:
	if not on_ground or land_timer > 0.0:
		return 0.0
	if resting or vx < 10.0:
		return IDLE_BOB * (0.5 - 0.5 * cos(TAU * 0.5 * idle_time))
	# 重心起伏每步一次（一个循环两步），直接用循环相位
	var cycle := fmod(anim_time * RUN_CYCLES_PER_SEC, 1.0)
	return RUN_BOB * (0.5 - 0.5 * cos(2.0 * TAU * cycle))


func _draw() -> void:
	# 接触阴影：软椭圆贴在地面，跳起时变淡变小
	var height_above := ground_y - (position.y + BOX_H)
	var closeness: float = max(0.0, 1.0 - height_above / 130.0)
	if closeness <= 0.0:
		return
	var w := BOX_W * 1.7 * (0.6 + 0.4 * closeness)
	var shadow_y := ground_y - position.y
	draw_set_transform(Vector2(BOX_W / 2.0, shadow_y), 0.0, Vector2(w / 2.0, w / 14.0))
	draw_circle(Vector2.ZERO, 1.0, Color(0.04, 0.04, 0.07, 0.31 * closeness))
