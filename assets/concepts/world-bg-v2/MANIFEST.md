# world-bg-v2 概念图档案（2026-07-17 归档）

> 规则见 docs/world-bg-v2-corpus-plan.md。评分：五维 0–2
> （favorite / illustration / playable_space / mood / project_fit），8+ = hero。
> 原始 20 张的 prompt 元数据在
> `~/Documents/Codex/2026-07-17/w/outputs/gpt-concept-photo-numbered/*.txt`。

## corpus-candidates/（无人无字无UI，可入炉）

| 文件 | 场景 | 来源 | 评分(待填) | 备注 |
|---|---|---|---|---|
| A00__distant-skyline__r1 | 纯远景天际线 | 编号02 | | support 级，playable_space=0，caption: distant skyline |
| B01__skywalk-network__r1 | 高架连廊网络 | DL 02:42 | | 次级地标定妆照；科幻版被否后的当代版 |
| B03__billboard-closeup__r1 | 海报近景（正典画+维护道） | DL 01:07 | | 圣地近景机位 |
| B03__billboard-rear__r2 | 海报背面维护道 | DL 02:30 | | 透光镜像修正版；镜像朝向待贴图资产阶段统一 |
| B04__times-square-encounter__r1 | 空街心巨屏遭遇 | DL 01:53 | | 圣地#1；信号灯青色/无字/无人修正版 |
| B02__atrium-shrine__r1 | 商场中庭圣地（正典人像+扶梯） | DL 03:00 | | 圣地#2 正典 |
| B05__sky-garden__r1 | 屋顶空中庭院 | DL 03:01 | | 停留点样板；远景她=密度律示范 |
| C01__carousel-plaza__r1 | 旋转木马广场 | 编号09 | | 09/10 二选一胜者 |
| C02__coaster-loops__r1 | 过山车回环 | 编号11 | | 11/12 二选一胜者；回环=远景剪影定案 |
| C02__wheel-promenade__r1 | 湖滨摩天轮长廊 | DL 03:02 | | 超宽比例，入炉时留意 bucket |
| C02__wheel-base-pavilion__r1 | 摩天轮登舱亭 | DL 03:03 | | 轮毂花朵纹样=纹样家族 |
| C04__gate-frontal__r1 | 游乐园大门（图案化无字） | DL 01:03 | | 灯饰拱星月木马 + 车票灯箱定稿 |
| C08__monorail-station-side__r1 | 单轨小火车+站亭（侧视） | DL 03:02 | | §25.9 单轨观景环线概念；超宽 |

> 全部 13 张已配 caption .txt（触发词 pworldbg + 组 + 色调），训练时直接拷。
> 吊舱玻璃碎/完好等场景事实不一致**不影响入炉**——风格 LoRA 学渲染语言
> 不学场景事实；一致性只约束正典资产。

## reference/（带人 hero / 待重出，不入炉）

| 文件 | 说明 |
|---|---|
| A01__station-shelter__r1__需无人无字版 | 分镜1号毛坯：候车亭+售货机+人字牌；待GPT重出无人无字版 |
| B03__billboard-catwalk-run__r1 | 海报正面维护道奔跑（创始图） |
| B03__billboard-top-sit__r1 | 海报顶端停留 |
| C05__track-crouch__r1 | 蹲滑姿态范本（=锚图2） |
| C05__coaster-climb-walk__r1 | 走上爬升段（15/16 近亲，构图不同故保留） |
| C07__wheel-top-sit__r1 | 摩天轮顶停留（有第二座摩天轮=地标增殖，用时注意） |
| C07__gondola-vines-sit__r1 | 藤蔓吊舱内坐姿（带人） |
| C08__monorail-tram-closeup__r1 | 单轨车厢近景（车身有花体字，洗字后可升语料） |

## mockup/（带 UI 游戏示意，设计参照）

03/04/05/06 高架连廊平台组（06=锚图1）；17 大门带字旧版；
18 木马广场奔跑（=锚图3）；19 过山车下方；20 摩天轮步道。
UI 徽章清洗任务（ComfyUI inpaint 首航）：18/19/20 角标。

## anchors/（新生图会话开场三件套，复制件）

anchor-1(06 连廊平台) / anchor-2(16 蹲滑) / anchor-3(18 木马奔跑)。
⚠️ 锚图带 UI 或人物，只做会话参照，不入炉。

## boards/

board__park-facilities-grid：12 设施九宫格（迷宫小丑立面已否决，勿参照）。

## rejected/

10（重复09）、12（超宽+重复11）、15（重复16）、skywalk sci-fi（科幻漂移）。

## 缺失清单（聊天里有、尚未下载高清）

- [x] ~~中庭圣地 v1~~（2026-07-17 03:00 已下，归档）
- [x] ~~空中庭院~~（已下，归档）
- [ ] 开放天台中庭 v2（B02__atrium-terrace__r1）
- [ ] 摩天轮吊舱内部·破窗看城版（C07__gondola-interior__r1）
- [ ] 画像四格选角板（boards 用）

## 待办

- [ ] 下载缺失 6 张 → 按上述名字归档
- [ ] 全表五维评分过堂
- [ ] 18/19/20 角标 inpaint 清洗 → 洗净后升入 corpus-candidates
- [ ] A01 无人无字版重出 → 车站分镜 1 号收工
- [ ] 车站分镜 2–8（docs/world-bg-v2-corpus-plan.md §4）
- [ ] 画作本体贴图（正视无透视）
- [ ] 游乐园母版鸟瞰综合重画
