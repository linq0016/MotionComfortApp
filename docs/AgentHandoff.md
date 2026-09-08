# Stellar / MotionComfortApp 交接上下文

核对日期：2026-09-08。本文整理了 9 个旧会话的必要上下文，并按 1.1.0 / Build 1 的代码更新。旧会话中的试验、回退和未实施建议，不自动构成待办事项。

## 1. 版本与本次保存范围

- 主项目目录：`/Users/linq0016/Desktop/Projects/MotionComfortApp`。
- 工作分支：`main`；本次版本：`1.1.0`，Build：`1`。
- 提交前基线：`aae3f4534e8a60a647872c564ef02fa2c2dac902`，`Save v1.0.2-b6`。
- 本次保存包括此前未提交的 Minimal 圆点交互、Debug 模拟器预览入口、Xcode 工程引用调整，以及本轮关键注释和本文。
- 本文不记录自身提交的 SHA；接手时通过 Git 查询实际 HEAD、工作区和远端状态。
- 只有一个登记的 Git 工作区，多数旧会话共用这份代码。`new main` 是近期功能接续会话，`main` 保存主要早期开发历史。

此前用户要求保护的三个修改文件现已获准纳入本次提交：

| 文件 | 保存的内容 |
| --- | --- |
| `App/Sources/FullscreenSessionView.swift` | 交互路由与 Minimal 可点击圆点 |
| `App/Sources/MotionComfortApp.swift` | 仅限 Debug 模拟器的 `--preview-minimal` 入口 |
| `MotionComfort.xcodeproj/project.pbxproj` | 隐私文件类型、Stellar.app 产物引用及本次版本配置 |

关键注释涉及 10 个 Swift / Metal 文件，仅解释模块关系、代码块作用和主要参数含义。注释轮次已与修改前快照比较，所有非注释源码字节保持一致。

## 2. 产品与协作方式

Stellar 是面向乘客的本地视听舒适辅助 App：

- Minimal：黑底外围点阵。
- Interstellar：Metal 星空、星尘和星云。
- Live View：相机预览叠加外围点阵。
- 音频：关闭、100 Hz 单音、以约 100 Hz 根音为基础的原创旋律。

产品约定是本地运行，不引入健康、位置或使用记录上传。面向用户的说明保持克制，不把研究结果直接写成产品疗效保证。产品文案边界见 `docs/ResearchAndSafety.md`。

协作约定：

- 先读代码，优先最小修改。性能整理默认保持布局、视觉、动画、手势和用户流程。
- 参数职责明确，避免同一效果多层重复调节。新增或调整参数、接口、状态时，先说明名称、用途和影响，按用户确认实施。
- 注释只需简要说明当前代码的作用、框架和参数结构，不加入防御性提醒或历史故障叙述。
- 不因架构整理恢复已撤销功能，不自动重做旧审计计划。
- 回复以“Codex：”开头，面向缺少代码经验的用户解释实际意义。
- Shell 命令遵循用户 RTK 规则。

## 3. 工程结构与配置

Swift 6、iOS 26、SwiftUI、UIKit 桥接与 Metal；面向 iPhone，支持竖屏和左右横屏，采用深色界面及 Liquid Glass。

- Bundle ID：`com.linq.StellarMotionComfort`。
- 桌面显示名与 App 产物名：`Stellar`。
- `App/`：欢迎页、首页、设置、全屏控件、状态编排、触觉反馈。
- `Core/`：共享运动数据模型。
- `Visual/`：传感器、点阵、Metal 和相机。
- `Audio/`：音频引擎与资源。
- `App/Resources/`：中英文本地化字符串。
- `App/Assets.xcassets/`：品牌与模式图标。
- `project.yml`：工程生成配置；生成的 `MotionComfort.xcodeproj` 也纳入版本管理。

版本由 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 提供，`App/Info.plist` 使用对应变量。本次将 project.yml 和 Xcode 工程的 Debug / Release 配置同步为 1.1.0 / 1。

重新生成工程曾丢失本地化资源引用，使界面显示字符串 key。生成后应核对 `Localizable.xcstrings`、`InfoPlist.xcstrings` 的资源构建引用，以及中英文显示。音频资源 `GStringsFinal.wav` 的打包引用也保留在工程配置中。

用户要求“回到某个 Git 版本”时，核实实际提交，不能只改版本号文字。历史最早 Build 为 1，中间曾与版本号混用；`1.0.2-bN` 提交名从 b2 开始，之后到 b6。

## 4. 状态、生命周期与控件

运动数据流为 `MotionManager.$sample` → `ComfortSessionViewModel` → `SessionRenderState.sample` → 视觉层。

高频运动快照由 `SessionRenderState` 单独发布。App 外壳和 Dashboard 分别观察较窄的 `appShellState`、`dashboardState`，全屏子层按所需值与 binding 组合。隐藏首页的背景动画由活动状态控制。

启动准备、全屏挂载与淡入淡出具有任务取消及 token 校验。音频预热在后台准备资源，完成后回主 actor 安装缓冲区并处理待播放模式。

两类滑杆的语义不同：

| 控件 | 当前语义 |
| --- | --- |
| 三种模式的运动灵敏度 | 拖动中不提交新值，结束操作后提交 |
| Interstellar 巡航速度 | 通过 `DynamicRenderControl` 实时预览，结束操作后提交正式值 |

滑杆保留步进、默认值吸附、触觉反馈和双击复位。HUD 在滑杆操作结束后重新计时，持久化在编辑结束等节点写入。

历史一次 `DynamicMetalView.updateUIView` 优化引发过灵敏度拖动卡顿，用户将其回退。后续改动需实际验证预览值与正式值的边界。旧版 `valueCommitTask` 已不在当前滑杆实现中，其析构取消补丁也不是当前待办。

## 5. 现行主要参数与共享范围

以下数值来自本次代码核对，优先于旧会话中的试验值。

| 项目 | 当前值或行为 |
| --- | --- |
| 运动采样配置 | 120 Hz |
| Dynamic 渲染目标 | 60 FPS，`framebufferOnly = true` |
| `MotionSample` | 三轴用户加速度，单位 g，无 pitch / roll / yawRate |
| 默认视觉 / 音频 | Interstellar / Melodic |
| 巡航速度 | 0...6，默认 2 |
| `motionSensitivityFactor` | 0.5...1.5，默认 1 |
| 灵敏度方向 | 左侧迟钝、右侧敏感；factor 越小，响应越强 |
| 后台音频 / 快速启动 | 默认关闭 |
| 加载提示 | 延迟 100 ms 出现，出现后至少显示 200 ms |
| 设置面板圆角 | 54 pt；100 pt 的试验已回退 |
| 设置中的 App 说明 | 竖屏收起不渲染、展开渲染；横屏默认渲染 |
| 全屏运动控件中心 | 横竖屏均为屏幕高度的 0.75 处 |

速度与灵敏度跨重启保留，Reset Stellar 恢复相应默认值。

Minimal 与 Live View 共用 `FlowGridConfiguration`、`FlowGridPhase`，通过不同 preset 控制外观。配置分为 Layout / Motion / Appearance / SafeZone。

Dynamic 的 World / Motion / Nebula / Particles / Counts 保持独立。用户不要求 Dynamic 与另外两种模式共用底层渲染参数。面向用户的统一灵敏度控件不等于合并所有内部配置。

星云使用 quad 渲染；历史 point sprite 大尺寸表现受限，因此改为两个三角形承载一朵星云。屏幕尺寸由基础缩放、深度和个体差异决定，纹理网格与边缘采样由 atlas 参数控制。

## 6. 相机、旋转、音频与待复核问题

正常运行路径由一个全局方向观察器提供界面方向，方向探针已有重复调度去重。

历史旋转半屏快照问题涉及系统转场。黑色遮罩、自定义双帧方案没有形成稳定保留实现，部分试验引发启动异常并被回退。Live View 的旋转体验以相机预览连续性为重要要求。

相机配置目标为 60 FPS。设备格式依次匹配 1080p HLG/HDR、720p P3，再使用 legacy 格式选择；另在 session 配置阶段选择可用的 preset。格式配置包含防抖，实际能力以设备支持为准。

相机权限文案：

- 英文：Camera access is needed for Live View mode to overlay the motion comfort effects onto the real world.
- 中文：“实况视窗”模式需要访问相机，以将晕动缓解效果与真实世界场景结合。

音频 session 使用 `.playback`，不带 mixing 选项。用户期望其他播放或录音正常中断 Stellar，回到 App 后合理恢复。这是交互要求，不代表本次已经重新验证所有音频中断场景。

待复核：Live View 分析状态跨队列读写曾被修复，但之后发生版本回退。当前 `stop()` 仍在 `sessionQueue` 重置部分分析状态，不能将历史修复视为已经保留。后续若处理，应独立复核队列归属，不捆绑 Dynamic 桥接优化。本次未修复此项，也未做运行时线程验证。

## 7. 当前 Minimal 交互

早期曾实现三模式玩法，随后用户要求删除具体玩法、只留路由。之后 `new main` 又重新加入了 Minimal 圆点交互，这是本次提交保留的当前功能。

- Minimal 有可点击圆点。
- Interstellar 和 Live View 的交互分支仍为空。
- `SessionInteractionLayer` 位于视觉引导层与 HUD 之间。
- `--preview-minimal` 仅在 Debug 模拟器构建中直接进入 Minimal，音频设为关闭。

旧“只有空交互层”的交接描述已经失效。旧彗星、星云环、碰撞和水平仪不属于当前功能范围。

圆点最多 5 个，生成间隔 1.7...2.3 秒，半径 18...24 pt。中央安全区内另预留约 68...79 pt 的缩放与模糊扩散边界，圆点间也有避让，因此实际同时出现数量受屏幕可用空间限制，不一定达到上限。

## 8. 隐私配置与外围内容

当前 App 级隐私清单声明 UserDefaults，理由代码 `CA92.1`。历史 Visual 清单和启动时间 API 讨论属于当时实现背景；后续调整应核对实际 API 与最终构建产物。历史审计不代表新版本的审核保证。

占位证书 App、图片导出、音频加工和 Blender 接入讨论不是 Stellar 主工程必需模块；会话中讨论过的工具不等于已经安装的项目依赖。

## 9. 清理决定与未执行事项

用户之前允许删除旧交接文件；本次最新要求是将整理后的交接文档纳入版本管理，因此复用 `docs/AgentHandoff.md` 保存本文，替代过时内容。

用户已允许清理以下对象，但本次提交不执行清理：

- 历史分支 `codex/live-view-fig-lifecycle`。
- 暂存备份 `codex-temp-before-v0.6.4`：Xcode 界面状态。
- 暂存备份 `codex-temp-before-v0.5.1`：字符串变化和 16 张历史图片素材。

执行时按说明与实际对象识别暂存备份，删除后编号会变化。清理前后核对 main、HEAD、暂存区、工作区文件及 Git 对象完整性，不通过重置主分支或清空工作区实现清理。

旧任务归档与目录重定向尚未执行。两个空目录仍分别被 `project discussions` 与 `new main` 引用：

- `/Users/linq0016/Documents/Codex/2026-08-25/new-chat`
- `/Users/linq0016/Documents/Codex/2026-08-25/new-chat-2`

删除前先处理任务目录指向。其他多个旧任务共用主项目目录，不能连带删除它。

## 10. 旧会话来源

| 会话及 ID | 提取内容 |
| --- | --- |
| project discussions — `019d9042-b4dc-7550-bcbb-7fb7c54191f5` | 参数职责、星云 quad、灵敏度、滑杆与设置性能 |
| main_alt — `019da70b-4233-7b80-8133-8f9ad247c788` | 控件演化、参数分组、Dynamic 与 FlowGrid 边界 |
| 先审计再计划 — `019db98e-01f6-7d32-ba18-40af880882bb` | 高频状态拆分、音频预热、滑杆回归、版本回退 |
| `019dba9e-f175-7ea3-ba8c-7f84b2173259` | 启动任务取消、全屏异步边界、历史隐私清单 |
| 更新相机权限提示文案 — `019dbad3-d884-7810-8a32-6de0bc03830d` | 权限文案、音频中断语义 |
| 调整更多设置面板圆角为100 — `019dbe45-70ab-7273-b3eb-605ec9323af9` | 圆角回退、说明区条件渲染 |
| 移除旋转旧快照残留 — `019dbdd5-e13f-7b33-ac07-3c9a536f1607` | 旋转试验、相机连续性、运动模型、加载时序 |
| side chats — `019da603-993e-7932-976e-8103e5c55c0f` | 视觉设计、命名、方向去重与窄状态观察 |
| side chats — `019d86f7-c3f8-7c11-8c02-32d349f87e7a` | 本地化资源、版本配置、素材与外围内容 |

## 11. 本次验证

本次 Debug 与 Release 的通用 iOS Simulator 构建均通过，未启用代码签名。构建使用 `/Applications/Xcode-beta.app/Contents/Developer`，通过单次命令的 `DEVELOPER_DIR` 指定，没有修改系统默认 Xcode。

- Debug / Release 配置均为 1.1.0 / 1，Info.plist 使用版本变量。
- 两种构建生成的 App 及三个内嵌 framework 均核对为 1.1.0 / 1。
- Release App 已包含旋律音频、App 隐私清单、中英文 Localizable 与 InfoPlist 字符串资源。
- `git diff --check` 通过；本次版本保存未进一步修改此前已有功能的源码逻辑。
- 首次受限环境构建报 Metal 工具链不可用，允许访问系统构建服务后重试通过，无需修改代码或安装工具链。

本次验证命令模板（将 CONFIGURATION 替换为 Debug 或 Release）：

```sh
rtk proxy env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project MotionComfort.xcodeproj -scheme MotionComfortApp -configuration CONFIGURATION -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/stellar-release-1.1.0-b1 CODE_SIGNING_ALLOWED=NO build
```

尚未重新验证真机交互、相机、音频中断与性能，也未执行 App Store 上传。构建通过不等于上述场景已经验证。
