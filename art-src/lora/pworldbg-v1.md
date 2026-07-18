# pworldbg-v1 风格 LoRA · 配方档案（现役）

> 定档：2026-07-18 用户裁决 **epoch 9**（675 步）。三方一致：六卷判读、
> 训练样张直觉、金丝雀三 seed 统计。
> 模型本体不进 git，两台各存：
> - PC 训练件：`Q:\lora\pworldbg-v1\model\pworldbg-v1-000009.safetensors`
> - PC 现役件：ComfyUI loras\`pworldbg-v1.safetensors`
> - Mac 备份：`art-src/lora/pworldbg-v1.safetensors`
> - md5：`615a7fb16c0448915dee6273f4830812`

## 训练配方（可复现）

- 语料：corpus-candidates 25 png+txt（commit f5ecc93 状态：机场 D 组
  7 张建组、红点全清洗、Codex caption）。触发词 `pworldbg`
- 参数：同 v0 配置仅改路径与 repeats——batch 2 / **repeats 6**
  （`6_pworldbg`）/ dim 16 alpha 8 / lr 1e-4 cosine / fp8_base /
  梯度检查点开 / seed 42 / 7.05s/步
- **教训（重要）**：kohya 真正的刹车是 `max_train_steps`，toml 里的
  `epoch` 键不限步。本炉设 1500 步，实际烧到 ~e12 手动停炉，
  e1–e11 留档。**v0 旧账同此修正**：v0 目录实为 `16_pworldbg`
  （repeats 16），跑满 1440 步，其 e6=864 步

## 选档证据

- 甜区实测：e9（675 步）；e10 起侵蚀（金丝雀 B 卷三 seed：
  e9 载具有人 1/3 轻度，e10 2/3 且双人；e11 训练样张爆红字）
- 会考战绩 vs v0-e6：机场 0.85 全空（v0 需 0.7）✓、红点近零 ✓、
  她开关健在 ✓✓、远景层更好 ✓、六卷零退步 ✓、壮观词汇唤醒力同级
- 全套考卷：`assets/concepts/world-bg-v2/eval/v1/`，
  方法论 `docs/world-bg-eval-method.md`

## 使用纪律

- 权重：语料内 0.85 / 语料外或指令敏感 0.7；euler+simple、
  20–28 步、guidance 3.5、FluxGuidance
- prompt 常备护栏：no palm trees / warm golden lights /
  empty carousel with no riders / 屏幕要纯图案时写 pattern display、
  别用 artwork screen（会召唤美女，详见 eval-method §4）
- 商铺按开门律描述：open warmly lit, fully stocked, unattended

## 已知小毛病（有绕法，不阻生产）

乱码字（底模先验，prompt 压＋后期）；巨屏默认长美女（改词可避）；
摩天轮尺度抢位（distant silhouette 专词）；她的尺度不可控（v2 课题）；
D06/D07 之外的机场标签未考。根治方案全在 corpus-plan §7.8（v2 货架）。

## 谱系

- v0（e6/864 步，md5 7137…17a0）：2026-07-18 退役进档案，
  语料 18 张时代的侦察兵。档案：pworldbg-v0.md
