# 菜单栏应用

状态：第一版菜单栏、解锁、本地输入拦截已实现；本地 Touch ID、取消冷却、20 秒回黑、Ctrl+Cmd+Q 和 UU 菜单密码解锁已实测。2026-11-06 接入心跳守护，默认取消 300 秒限制；新版本验收与待测范围见[验证记录](../verification.md)。需求见 [产品需求](../requirements.md)。

源码：[CurtainApp.swift](../../Sources/App/CurtainApp.swift)、[SystemGuards.swift](../../Sources/App/SystemGuards.swift)，共享 [GammaBlackout.swift](../../Sources/Shared/GammaBlackout.swift)。构建：`./scripts/build.sh` 生成 `build/Curtain.app`（优先 Apple Development 签名，回退 ad-hoc；`LSUIElement`，不在 Dock 显示，bundle id `local.zjf.curtain`）。日志：`~/Library/Logs/Curtain/curtain.log`。

## 状态与菜单

The app now supports English and Simplified Chinese using native macOS language selection. The primary action is “Enable Privacy Screen” / “开启隐私屏”; the existing transition and authentication contracts below still apply. See [localization](app-maintenance.md#localization) for resource packaging and validation.

新增“关于 Curtain”“检查更新…”及仅缺辅助功能权限时显示的“允许拦截本地输入…”。授权后隐藏权限入口，撤销后重新出现；打开菜单及触发引导时都重新检查权限。以上入口仅 open 且无更新任务时可用；更新期间禁止拉幕，退出先取消任务并清理。标准关于面板及权限窗口在拉幕前定向隐藏，不隐藏状态栏菜单。完整契约见[应用维护](app-maintenance.md)。

| 状态 | 菜单 | 效果 |
| --- | --- | --- |
| 拉开（默认） | “开启隐私屏”可用 | 无遮挡，不影响输入 |
| 拉上 | “解锁…”可用；退出不可用 | gamma 清零、持有防显示器睡眠断言、监听硬件输入 |
| 解锁中 | 都不可用 | 先画全屏黑色背景窗口（鼠标穿透），再恢复 gamma；中间显示认证面板，自动发起 Touch ID |
| 恢复中（recovering） | 都不可用 | 守护已提交故障恢复；保留仍有效曲线、lease 和背景窗口，暂停 gamma 巡检及解锁计时，等待系统锁屏/进程结束；守护退出后可统一清理 |

“退出 Curtain”先拉开再退出。点击“开启隐私屏”后延迟 0.3 秒，等菜单收起再黑屏。

## 解锁

- 唤出：拉上状态下，来源 PID 为 0 的鼠标移动/点击/滚动/按键（硬件事件）唤出解锁界面；合成事件（Codex、UU 等）只记录 `ignored-synthetic pid=…`，不唤出。鼠标事件无需权限；按键需辅助功能/输入监控授权，否则只有鼠标能唤出。菜单“解锁…”供 UU 远程使用。
- 认证：Touch ID（`LAContext`，仅生物识别）或面板密码框（OpenDirectory `verifyPassword` 校验当前用户登录密码，不保存；失败后 1 秒冷却）。
- 解锁中 20 秒无本地操作：先清零 gamma，再移除窗口（同时作废未完成的 Touch ID 弹窗），把焦点还给原应用，回到拉上状态。只有硬件事件（来源 PID 为 0）会重置计时；Codex 等 agent 的合成输入即使落到面板上也不续时，避免 agent 持续操作让解锁界面一直亮着。例外：从菜单“解锁…”打开时（UU 远程场景）任何输入都续时，因为远程键盘可能是合成事件；这种会话不自动弹 Touch ID，直接聚焦 Curtain 自带密码框（系统认证框关闭后会把激活权还给之前的应用，导致密码框收不到键盘）。
- Touch ID 弹窗点“取消”：视为暂不解锁，立即回到拉上状态；之后 3 秒内忽略硬件输入（点取消时手还在触控板上），3 秒后再动鼠标重新唤出。选“输入密码”、多次失败或被系统关闭：保留面板，点击面板外任意处重新发起 Touch ID。
- 成功：移除窗口、释放防睡眠、停止监听，`NSApp.hide` 把焦点交还原应用。

## Space 与多显示器（2026-11-06 复查修正）

- 黑屏本身是显示管线 gamma，没有属于某个 Space 的窗口；独立心跳守护也没有窗口。已有的单屏全屏验证不能外推为所有 Space/外屏通过。
- 解锁界面仍是窗口，保留窗口遮罩在过渡动画中可能被移走的已知风险。收到普通 Space/原生全屏的 active-Space 通知时立即尝试回黑并取消认证，但通知可能晚于动画开始，**不承诺解锁界面期间零闪露**。
- 解锁时使用同一份屏幕快照为各屏建立背景；唯一认证面板放在鼠标所在屏幕，无匹配时才选主屏。无可用屏幕则不恢复 gamma。
- 在恢复 gamma 前重新核对在线显示器 ID、AppKit 屏幕 ID/位置/尺寸/缩放；解锁期间拓扑变化也立即尝试回黑（2 秒唤醒宽限），下次再按新布局创建窗口。仅颜色配置通知、几何布局与在线列表未变时不取消解锁。
- 任一显示器无法清零/读回，回黑失败时直接拉开并清理，不保留“部分黑屏但状态显示已拉上”。防睡眠断言创建失败同样拒绝拉上。
- 密码异步校验和错误冷却回调必须仍属于原密码框实例，防止旧解锁界面的结果进入新一轮；Touch ID 继续用 LAContext 身份校验。

现场状态：修正版单屏两轮原生全屏进出通过；内置屏与实体外屏的 1920×1080 镜像组合，gamma 普通 Space A→B→A 遮挡通过；同一镜像组合两次解锁界面 Space 变化后自动回黑、再 Touch ID 解锁通过，用户未见闪露。扩展桌面、HDR 和热插拔第一帧待测；日志时间从收到通知起算，肉眼通过不代表零帧暴露。

`scripts/install.sh` 只读取当前 PID 本次启动后的状态，忽略已结束实例遗留的 closed；多实例或状态不明时拒绝替换，正常退出最多等待 5 秒。不得在幕布拉上时重启应用。

## 强制拉开

系统锁屏（`com.apple.screenIsLocked`）、系统将要睡眠、显示器睡眠、快速切换用户：立即拉开，系统锁屏/登录界面可见（需求 F8）；系统解锁后不自动重新拉上。另有 SIGINT/SIGTERM、退出（仅拉开状态可点）。2026-11-06 起默认不再 300 秒自动拉开，改由[独立心跳守护](recovery-watchdog.md)保护 closed/unlocking 会话；守护未就绪则不拉上，守护意外退出则拉开。主线程约 10 秒无心跳时，守护先请求系统锁屏，再结束 Curtain。开发调试可显式设置 `devSafetyTimeoutSeconds` 正数恢复限时。进程崩溃时系统自动恢复 gamma。忽略 SIGHUP。

若独立守护已提交故障恢复，正常解锁/退出、SIGTERM 和系统中断的清理都先检查撤销结果；收到 `F` 时暂缓恢复曲线/退出，等待锁屏和进程结束。守护随后异常退出且主线程已恢复时，清理重新允许执行。守护不主动暂停主进程，避免把临时无响应变成永久暂停。

gamma 的运行失败、首次拉上失败和回黑失败均通过同一清理入口；组件失败时不提前恢复任何曲线。初次拉上即便还没把状态从 open 改为 closed，也要完整清理部分设置的 gamma。清理被 F 拒绝时转 recovering，不再误报 open/closed、重新唤醒或展示失败后“已恢复”的提示；已有输入 tap 转 block，背景窗口保留。解锁 UI 的 ready 回调返回是否批准呈现，F 拒绝后不恢复 gamma 或弹 Touch ID。

## 待做

第 5 步：现场验收（本地 Touch ID、取消冷却、Codex 不唤出、UU 不唤出、20 秒回黑、UU 菜单+密码解锁已通过；UU 隐私屏开、本地面板显示待测）。

## 解锁界面外观（2026-11-05，macOS 26 锁屏风格）

- 背景：当前桌面壁纸经模糊、提饱和并压暗（`BackdropArt`，拉上幕布时预先渲染并按屏幕尺寸缓存）；没有缓存或壁纸读不到时用深色渐变。只显示壁纸，不显示任何窗口。上方是日期和圆体大号时间，每秒刷新。背景窗口不接收鼠标。
- 控件：透明、不激活应用的面板，放在屏幕下部：账户头像（本地目录 JPEGPhoto，失败用系统人像图标）、全名、Liquid Glass 胶囊密码框（`NSGlassEffectView`，macOS 26 以下用 HUD 材质；输入后右侧出现提交箭头，验证时转圈）、错误提示、“使用触控 ID”（设备不支持时隐藏）、底部提示“20 秒无操作自动回到黑屏 · Esc 立即返回”。
- 占位文字：菜单打开（远程）为“输入登录密码”，本地为“触控 ID 或输入登录密码”。
- 密码错误：与系统锁屏一致，不显示文字；1 秒后只让密码胶囊左右晃动，清空并重新聚焦。Touch ID 识别失败、锁定、不可用分别提示；选择“输入密码”时不提示。
- Esc：与 Touch ID 取消相同，回到黑屏并进入 3 秒冷却。

## Backdrop resource lifecycle (2026-11-06)

[BackdropArt.swift](../../Sources/App/BackdropArt.swift) decodes wallpaper with ImageIO at the aspect-fill resolution needed for the half-point-size backdrop, with a 2048-pixel maximum thumbnail dimension. EXIF orientation is applied before the existing Core Image blur/color treatment. Missing or unsupported images still use the dark-gradient fallback. This is wallpaper-only processing; it never captures desktop windows.

Preparation runs on one utility queue with an autorelease pool per work item, preventing simultaneous source-image decodes for multiple displays. Art is reused while closed/unlocking, including timeout/cancel returns to black. After the guardian permits cleanup and unlock windows are removed, `finishOpen()` clears the cache and invalidates pending results with a session generation. An old completion cannot repopulate the cache or remove a new session's pending request. Recovery that refuses cleanup retains the current session's resources. The next close prepares fresh art, so old wallpaper paths and screen sizes do not accumulate across sessions.

`./scripts/test-backdrop-art.sh` checks PNG/JPEG/HEIC rendering, rotated-image color regions, opaque corners, missing/corrupt files, cache reuse/release and overlapping asynchronous sessions. It creates no windows and changes no display state. Measurements and limits are in the [verification record](../verification.md).

## 应用图标（2026-11-06 “光缝”）

`Resources/Curtain.icon`（Icon Composer 格式）由 `scripts/make-icon.py` 生成，改图标请改脚本后重新运行，再 `build.sh`（`actool` 编译为 macOS 26+ 的 `Assets.car` 与 macOS 15 用的 `Curtain.icns`）。

- 寓意：整个图标是一幅合上的深色幕布，一道 S 形光缝贯穿上下——屏幕被遮住，后面的 agent 仍在工作。
- 光缝：中线 x = 512 + S·sin(π(2t − ½))，宽度 W·sin(πt)^0.8（两端收尖、中间最宽）；金 → 珊瑚 → 玫红竖向渐变，中心一道浅色芯，两侧细暖色亮边。
- 光晕：5 层同形状、逐层加宽、透明度递减的带子，代替模糊滤镜。
- 褶皱：两侧各 4 道与光缝同向摆动的柔和条带，摆幅随距离线性减小；靠近光缝的褶皱带暖色。
- 所有图层关闭玻璃效果；旧方案保存在 `artifacts/icon/`（含丝绒幕布版生成脚本 `make-icon-velvet.py`）。
- 菜单栏图标与应用图标刻意不同：菜单栏用 SF Symbols `curtains.closed` / `curtains.open` 表示状态（界面内使用，许可允许）。SF Symbols 许可禁止把系统符号或与之高度相似的图形用于应用图标，所以应用图标不照搬这个窗帘造型（2026-11-06 试过“横杆 + 两幅幕”版本后放弃）。
