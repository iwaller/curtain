# 验证记录

> 2026-11-05 项目更名为 Curtain：源码 `Sources/PrivacyScreen.swift` → `Sources/Curtain.swift`，可执行文件 `build/privacy-screen` → `build/curtain`，目录 `codex-privacy-screen` → `curtain`。以下历史记录保留当时的名称。

## 2026-11-04：项目初始化

用户确认本轮仅创建项目和分析文档，切换目录后再实现与实测。

| 项目 | 状态 |
| --- | --- |
| 同级独立项目目录 | 已创建 |
| AGENTS、架构、规范、子系统与实验文档 | 已创建 |
| Swift/AppKit 源码、构建入口 | 未创建 |
| 工具链检测、编译与启动 | 未执行 |
| Computer Use 基线与遮罩实验 | 未执行 |
| 实体屏幕覆盖、Space/全屏切换 | 未观察 |
| 密码、菜单栏、输入拦截 | 未实现 |

初始化检查通过：13 个 Markdown 文件，36 个相对文档链接全部指向存在的文件；目录结构已核对。没有兼容性结论。

## 2026-11-04：最小 POC 首轮实测

### 环境与命令

- macOS 26.7.1（25G241），arm64；Xcode 27.1（27A9275），Apple Swift 6.4。
- AppKit 报告 1 台显示器：逻辑 frame 1512 × 982，缩放 2；桌面截图为 3024 × 1964。普通 Safari 应用截图为 3024 × 1724。
- 工具：`mcp__computer_use`，CUA App Version 1001641；`get_app_state` 获取应用截图及辅助功能树，`click` 按截图像素坐标输入。导航/全屏使用 `press_key`、`type_text`。无 DOM/AppleScript 测试点击。
- 构建：`./scripts/build.sh`，成功输出 `build/privacy-screen`。初次编译遇到 Swift actor 隔离错误，入口加 `MainActor.assumeIsolated` 后编译通过。
- 开罩前说明了 90 秒自动退出与 `kill -TERM <pid>` 兜底。先运行 `--duration 2 --no-overlay` 验证 Timer，再运行 `--duration 5` 验证实际遮罩进程超时退出，日志均为正常退出。
- 主实验：`./build/privacy-screen --duration 90 > artifacts/ordinary-overlay.log 2>&1`；12:45:33–12:46:41 UTC（20:45:33–20:46:41 本地），通过 `kill -TERM` 主动结束。
- 普通模式 sharingType 为 `.readOnly`，窗口 level=1000，`ignoresMouseEvents=true`。
- 实体屏幕观察已向用户询问，尚未收到现场结论。以下实体结果均不推测。

### 结果

| 场景 | Computer Use 应用截图 | 截图坐标点击/计数 | 辅助功能读取 | 桌面合成截图 | 实体覆盖/闪露 |
| --- | --- | --- | --- | --- | --- |
| 无遮罩基线 | 页面可读 | (1512,970)，0 → 1 | 可读计数 1 | 未采集 | 不适用 |
| 普通遮罩 | 页面可读 | (1512,970)，1 → 2 | 可读计数 2 | 点击前后均黑色 | 待现场确认 |
| Safari 原生全屏 | 页面可读 | 从全屏当前截图定位，(1512,970)，2 → 3 | 可读计数 3 | 黑色 | 过渡及稳定态待确认 |
| 返回普通窗口 | 页面可读 | 从返回后的截图定位，(1512,970)，3 → 4 | 可读计数 4 | 点击前后均黑色 | 过渡及稳定态待确认 |
| `.none` 对照 | 未运行 | 未运行 | 未运行 | 未运行 | 普通模式工具侧通过，无需本轮对照 |
| 普通 Space A → B → A | 未运行 | 未运行 | 未运行 | 未运行 | 待测 |
| 5 秒自动退出 | 不适用 | 不适用 | 不适用 | 未采集 | 进程正常退出并记录清理；实体未确认 |
| SIGTERM 主动退出 | 随后 Safari 可用 | 不适用 | 测试标签页关闭，回到原起始页 | 恢复桌面画面 | 待现场确认 |

未通过元素操作替代按钮坐标点击。打开本地文件时 Safari 出现原生“打开”确认框，通过 Computer Use 点击“打开”；此时工具即时返回仍为起始页，后续重新取状态确认测试页加载，再开始基线。

桌面截图采用 `screencapture -x`，用于独立采集诊断，不作为 GUI 操作或实体观察。遮罩期间 5 张桌面截图，RGB 各通道小于 10 的像素比例为 99.9978%–99.9985%，少量系统指示点仍可见；退出后的对应比例为 0.0142%。采样帧不能证明切换全程无闪露。

### 编译与退出检查

收尾将清理改为幂等（避免 terminate 回调重复输出清理日志），重新构建成功。最终构建检查：0 秒、301 秒、NaN、缺少时长值、未知参数 5 个场景均以状态码 2 拒绝，且未进入启动流程；`--duration 1 --no-overlay --exclude-capture` 正常超时，只记录一次清理。该最终调整仅涉及重复清理；完整 GUI 截图/点击证据来自调整前的同一窗口实现，调整后未重复整轮 GUI 实验。

### 结论与清理

普通遮罩与当前 Computer Use 的应用截图/坐标点击兼容性初步成立，Safari 全屏和返回后工具侧也可操作。不需要依赖 `.none` 才取得本轮可读截图；不外推其他截图工具或系统版本。

M1 仍为部分完成：缺少实体持续覆盖和过渡闪露的观察结论，普通 Space 切换尚未执行。多显示器、热插拔、睡眠唤醒、本地输入限制未验收。不扩展密码/菜单栏等产品功能。

已结束遮罩进程（PID 不再存在），退出 Safari 全屏，使用 Computer Use 关闭本轮新增标签页并回读为原起始页。未结束 Safari 进程；本地文件无需临时 HTTP 服务。

原始证据在忽略的 `artifacts/`：

- `exit-dry-run.log`、`timeout-overlay.log`、`ordinary-overlay.log`、`final-exit-dry-run.log`：生命周期和显示器日志。
- `baseline-click.jpg`：计数 1；`ordinary-before-click.jpg`、`ordinary-click.jpg`：遮罩下计数 1/2。
- `fullscreen-before-click.jpg`、`fullscreen-click.jpg`：全屏计数 2/3；`returned-click.jpg`：返回后计数 4。
- `ordinary-desktop*.png`、`fullscreen-desktop.png`、`returned-desktop*.png`：桌面合成采样；`cleanup-desktop.png`：退出后画面。

下一步优先补现场观察与普通 Space 切换，再决定是否完成 M1。

## 2026-11-04：UU 远程观察复测

用户说明首轮不在电脑旁，并且通过远程电脑观察，因此首轮没有实体屏幕证据。本轮通过 UU 远程观察目标 Mac；远程画面与实体显示器分开判定。

### 时序与证据

使用上一轮收尾后的最终构建，无源码修改。普通 `.readOnly` 模式，90 秒自动退出，PID 80797。全部页面导航、截图、坐标点击和全屏操作仍由 `mcp__computer_use` 完成。

| 本地时间（UTC+8） | 操作/证据 | 结果 |
| --- | --- | --- |
| 20:55:22 | 启动 90 秒普通遮罩 | 单显示器窗口 level=1000；退出兜底提前说明 |
| 20:55:23 | 遮罩下 Safari 应用截图 | 可读，起始计数 1（无遮罩基线已 0 → 1） |
| 观察早段 | 用户通过 UU 远程反馈 | “一直黑色，没有露出页面” |
| 20:56:20 | 当前截图坐标点击 (1512,970) | 1 → 2，Safari 应用截图可读；桌面合成截图近乎全黑 |
| 20:56:38 | Safari 原生全屏中的坐标点击 | 2 → 3，应用截图可读；桌面合成截图近乎全黑 |
| 之后 | Computer Use 退出 Safari 全屏 | 返回普通窗口；没有连续桌面录像 |
| 20:56:52 | Timer 到期日志 | 正常退出，清理只执行一次 |
| 20:56:58–59 | 返回后点击及桌面采样 | 3 → 4，发生在自动退出后，不能算遮罩下返回点击证据；桌面已可见 |
| 后续确认 | 用户反馈后半段 UU 观察 | 认为预期自动恢复前已经看到测试网页；具体首次露出时刻未定位 |

用户后半段反馈原话：“感觉没有 56，56 之前就已经出现那个测试网网页了”。该描述没有精确时间戳，不能据此定位首次露出时刻或归因于某个 API，但也不能将本轮记为持续遮挡通过。

桌面采样黑色像素比例：普通遮罩 99.9985%，全屏 99.9978%；自动退出后的返回截图 0.0128%，清理后 0.0142%。采样帧与用户观察并不等价：它们无法排除帧间或切换中的露出，也未记录 UU 采集路径。

### 判定与清理

- 工具侧：普通遮罩和全屏时应用截图可读，坐标点击通过。
- UU 远程侧：早段黑屏已确认，随后用户报告提前露出测试页；持续遮挡验收不通过，首次露出时间与原因待定位。
- 实体显示器：没有现场观察，仍未验证。不能从 UU 的画面直接推出实体屏幕结果。
- 普通 Space A → B → A：本轮未测；不将原生全屏切换当作该项验收。

已确认进程在 90 秒后自动退出，Safari 已退出全屏，并通过 Computer Use 关闭本轮新增测试标签页，保留原起始页和 Safari 进程。没有临时服务。

原始证据位于忽略的 `artifacts/remote-retest/`：`overlay.log`、`overlay-before.jpg`、`overlay-click.jpg`、`fullscreen-click.jpg`、`returned-click.jpg`、各阶段 `*desktop.png`。文件修改时间用于判断截图是否位于自动退出前后。

M1 不通过完整验收，不进入产品功能。下一步应在已确认观察条件下做分阶段复测，将普通桌面、进入全屏、退出全屏与自动关闭分开，并记录 UU 端首次露出时点；需要实体屏幕观察后才能判断目标 Mac 的实体隐私效果。

## 2026-11-04：120 秒分阶段复测，捕获退出全屏闪露

用户全程通过 UU 远程观察。使用同一构建、普通 `.readOnly` 遮罩，持续 120 秒。源码无变更。GUI 操作仍完全由现有 Computer Use 执行；另以 `screencapture -x` 约每秒采样一次桌面，保存时间戳和黑色像素比例，用于定位切换帧。

### 时序（UTC+8）

| 时间 | 操作/证据 | 结果 |
| --- | --- | --- |
| 21:01:38 | 启动遮罩 PID 88562，提前说明退出时间与终端兜底 | 预计 21:03:38 自动退出 |
| 21:02:05 | 普通桌面截图坐标点击 | 计数 1 → 2（基线已 0 → 1） |
| 21:02:19 | 提示后进入 Safari 原生全屏 | 工具截图可读 |
| 21:02:37 | 全屏坐标点击 | 2 → 3 |
| 21:02:52.363 | 提示后退出 Safari 原生全屏 | 切换回普通桌面 |
| 21:02:52.543–52.796 | 桌面第 74 帧采集 | 捕获 Safari 动画中测试页、窗口边缘和 Dock；遮罩进程仍在运行 |
| 21:03:11 | 返回后的坐标点击 | 3 → 4；本次发生在自动退出前 |
| 自动退出前 | 用户观察反馈 | “中间会闪烁一下，能看到界面”；具体阶段选择“不止一次或无法分辨” |
| 21:03:38 | Timer 到期、进程退出 | 正常清理一次；随后关闭本轮测试标签页 |

### 证据与判定

`artifacts/remote-retest-2/desktop-074.png` 已人工查看：画面明确为退出全屏过程的测试网页，带动画重影和下方 Dock；并非全黑遮罩。该帧黑色像素比例只有 6.2931%，相邻稳定态恢复近乎全黑。对应 `events.log` 的退出全屏操作发生在该帧前约 0.18 秒，`overlay.log` 确认进程一直运行到 21:03:38，距离露出约 46 秒。因此至少一次露出发生在退出全屏动画，不能归为到时自动关闭。

共采集 121 帧：第 0 帧与进程启动并发，采集可能早于遮罩显示，不能算运行中闪露；第 74 帧明确闪露；其余 119 帧黑色比例均至少 99%。每秒采样会漏掉更短事件，不能据此排除用户观察到的其他闪烁，也不精确估计闪露持续时间。原始帧只保留在忽略目录，没有写入文档。

结论：Computer Use 的应用截图和三阶段坐标点击通过，但持续视觉遮挡失败；至少退出原生全屏的过渡不受当前窗口策略可靠覆盖。UU 远程观察和桌面采样共同支持此结论。具体 AppKit/WindowServer 覆盖机制原因尚未查明；没有实体屏幕现场观察，不能将本轮结论外推为实体显示器观察。

已确认遮罩 PID 不再存在、采样进程结束、Safari 回到普通窗口，并用 Computer Use 关闭新增测试标签页，恢复原起始页。没有新建服务或修改系统设置。

证据目录：`artifacts/remote-retest-2/`，包括 `overlay.log`、`events.log`、`samples.jsonl`、`summary.json`、`desktop-*.png` 和三个阶段的 `*-click.jpg`。下一步优先解决或规避原生全屏过渡露出，修复后再由用户观察复测；M1 仍不通过完整验收。

## 2026-11-04：修复对照与窗口轨迹诊断（未修好）

用户授权继续解决闪露。本轮以现有 Computer Use 继续操作同一个 Safari 专用测试标签页，所有全屏、坐标点击都经 GUI 工具完成。桌面采样加密至中位间隔约 0.22–0.34 秒，每帧记录采集开始/结束、进程是否仍运行和黑色比例；原始画面仍只放忽略的 `artifacts/`。

### 对照结果

| 对照 | 改变 | 实测结果 |
| --- | --- | --- |
| all-applications-test | 原 NSWindow 加 `.canJoinAllApplications` | 359 帧；进入与退出全屏各捕获 1 个露出帧。21:14:24 启动，21:15:45 SIGTERM 清理。用户未全程观察。 |
| nonactivating-panel-test | 在前一配置上改 NSPanel + `.nonactivatingPanel` | 511 帧；运行中共捕获 3 个露出帧，包含退出全屏与后续再次进入。21:18:06–21:20:06，正常超时。 |
| independent-overlay-test | 面板移除旧式 `.fullScreenAuxiliary`，保留跨应用角色 | 525 帧；进入与退出全屏仍有 3 个露出帧。21:24:56–21:26:56。用户确认“开头和结束的时候闪了一下，其他没有闪烁了”。 |
| display-shield-test | 恢复原窗口实现，增加独立实验分支调用公开 `CGCaptureAllDisplays`，使用系统屏蔽层，退出调用 `CGReleaseAllDisplays` | 建立系统 shield，level=2147483628，CUA 截图与坐标点击可用（5 → 6 → 7）；但 21:31:11 进入全屏后桌面采样持续出现页面，运行中共 122 个非黑帧，失败。21:31:41 超时释放显示器 result=0，退出全屏操作在释放后完成，不能记为屏蔽下退出测试。 |

各对照都编译通过，但没有任何一个通过持续遮挡验收。没有无限提高窗口层级，也没有更改用户系统动画、锁屏或安全配置。以上非黑帧统计排除了启动前 2 秒，以及采集前后进程状态发生退出变化的帧，不代表严格测得的闪露时长。

### 已定位的机制

`nonactivating-panel-test/window-trace.jsonl` 使用公开 `CGWindowListCopyWindowInfo` 约每 40 毫秒记录窗口编号、进程、层级、边界、透明度与 onscreen 状态，没有记录窗口标题/页面正文。

21:19:55.872（本地）遮罩窗口 25782 位于 x=0、layer=1000；进入全屏过渡时，21:19:55.988 变为 x=-16，21:19:56.185 变为 x=-827；21:19:56.695 恢复 x=0。进程、窗口号与透明度保持不变，同一时间桌面采样出现测试页。因此至少该轮进入全屏时，遮罩随着旧 Space 的系统动画被移走，不能用普通窗口层级解释为始终固定在物理屏幕上。轨迹中的 Safari 过渡窗口还出现在普通跨 Space 窗口前；公开窗口属性并不保证该合成阶段的覆盖。

该轨迹定位的是上述进入全屏过程，不能外推全部退出路径；旧实现退出全屏的露出已在上一节单独捕获。系统显示器捕获实验也失败，因此不能据“系统屏蔽层建立成功”宣称兼容。

### 最终代码与清理

未通过的 `.canJoinAllApplications`、NSPanel、独立面板与 display-shield 改动均已从当前源码回退。实验源码、显示器捕获二进制和全部采样保留在忽略的 `artifacts/` 中。当前 [PrivacyScreen.swift](../Sources/PrivacyScreen.swift) 保持原 POC 窗口行为，只将生命周期日志增加毫秒精度，方便后续对齐动画时点。

最终 `./scripts/build.sh` 编译通过；`--duration 1 --no-overlay` 验证自动退出和一次清理，日志位于 `artifacts/final-precise-log-check.log`。仅日志格式改变，未重复完整 GUI 矩阵。

四轮进程均已确认退出，系统显示器捕获已正常释放，诊断采样和窗口轨迹进程已结束。Safari 已退出全屏，Computer Use 关闭了本轮新增测试标签页并回读到原起始页；未结束 Safari 进程。清理后桌面截图为 `artifacts/cleanup-after-fix-attempts.png`。

结论：本轮修复未成功。当前窗口覆盖路线不能作为可靠隐私屏；下一步需评估与 Space 合成独立的物理显示遮挡机制，或明确限制工作流避开原生全屏/Space 过渡，并另行验收。临时避免这些过渡不等于完整修复，实体屏幕仍缺现场观察。

## 2026-11-04：Gamma 清零实验分支（待实体验证）

### 动机

窗口轨迹说明遮罩窗口位于 WindowServer 的 Space 合成内，过渡动画会把它连同旧 Space 一起移走；`CGCaptureAllDisplays` 屏蔽层也属于窗口，同样失败。新增实验模式 `--gamma`：不创建窗口，改用公开 `CGSetDisplayTransferByTable` 把每个活动显示器的 gamma 表设为全 0。gamma 在合成之后作用于显示管线，原理上不受 Space/全屏动画影响。截图通常采集 gamma 之前的帧缓冲，因此预期 Computer Use 截图仍可读。**该预期尚未验证。**

实现：启动时清零并读回；注册 `CGDisplayRegisterReconfigurationCallback`，显示器重新配置后再次清零；每 50 毫秒读回一次，发现被重置（如夜览/原彩/ColorSync）就重新清零并记录 `gamma-reset-detected`。超时、SIGINT/SIGTERM 时调用 `CGDisplayRestoreColorSyncSettings`；进程意外退出时由 Quartz 自动恢复。原窗口实现备份在 `artifacts/PrivacyScreen-before-gamma.swift`。

### 远程探针结果（21:41，用户不在现场）

| 项目 | 结果 |
| --- | --- |
| 编译 | `./scripts/build.sh` 通过 |
| 清零 | `--gamma --duration 4`：display=1 result=0，读回全 0 |
| 自动恢复 | 4 秒超时退出，读回已恢复，进程不再存在 |
| 截图可读性 | **未验证**：Claude Code 终端的 `screencapture` 在探针前后都报 "could not create image from display"，属于本终端缺少屏幕录制权限，与 gamma 无关 |
| 实体屏幕 | 未观察 |

日志：`artifacts/gamma-probe/overlay.log`。

### 现场验证要点

- **UU 远程看到的会是正常画面**：UU 和截图一样采集帧缓冲，不能再用它判断遮挡效果；必须到实体屏幕前看，或用手机录屏幕。
- 按“普通 → 进入全屏 → 退出全屏 → 普通 Space A → B → A → 超时退出”顺序，Computer Use 负责截图和坐标点击，手机录实体屏幕。
- 需重点确认：Computer Use 截图是否可读；鼠标指针是否仍可见（硬件光标层可能不受 gamma 影响）；夜览/原彩是否触发 `gamma-reset-detected` 及可见闪烁；XDR/HDR 内容是否仍会显示。

## 2026-11-05：Gamma 模式现场验证（全屏过渡通过）

用户在实体屏幕前观察。GUI 由 Claude Code 后台调起的 `codex exec` 执行，Computer Use 工具 `mcp__computer_use`（CUA App 1001641），全部为截图坐标点击 (1512,970)。macOS 26.7.1，单显示器。Codex 原始报告：`artifacts/gamma-onsite/codex-report.md`，逐步时间：`events.log`。

### 三轮经过

| 轮次 | 时间（UTC+8） | 结果 |
| --- | --- | --- |
| 1 | 09:34:05 启动 | Codex 用 `cmd &` 后台启动，启动命令返回后进程很快消失，日志只有 started/gamma-zero，没有退出记录；进程退出后系统恢复 gamma，用户反馈“并没有黑屏”。本轮截图/点击不计入 gamma 结果。归档 `attempt1/` |
| 2 | 09:38:15–09:41:15 | 父 shell `wait` 保持会话。用户确认有黑屏、不闪、恢复正常。到期前：普通 8→9、进入全屏 9→10、退出全屏 10→11；其余步骤在到期后，不计入。归档 `attempt2/` |
| 3 | 09:43:10–09:46:10 | 完整重做，全部步骤在到期前完成。用户确认“第三轮也没有闪动” |

### 第三轮结果

| 场景 | Computer Use 截图 | 坐标点击 | 实体屏幕（用户观察） |
| --- | --- | --- | --- |
| 无遮罩基线 | 可读 | 14→15 | 正常 |
| gamma 普通窗口 | 可读、非黑 | 15→16 | 黑 |
| 进入原生全屏 | 可读、非黑 | 16→17 | 黑，不闪 |
| 退出原生全屏 | 可读、非黑 | 17→18 | 黑，不闪 |
| 再次进入全屏 | 可读、非黑 | 19→20 | 黑，不闪 |
| 再次退出全屏 | 可读、非黑 | 20→21 | 黑，不闪 |
| 普通 Space A→B→A | Ctrl+→ 后截图无变化，判断只有一个 Space，跳过 | 18→19（不计为 Space 验收） | 未判定 |
| 180 秒超时 | 不适用 | 不适用 | 恢复正常 |

`overlay.log`：`gamma-zero ... result=0 readback=black`；`gamma-restored reapplied=0 displays=1:restored`；全程 `gamma-reset-detected` 0 条。人工查看 `fullscreen2-click.jpg`（黑屏期间截取）：测试页清晰，计数 20。

### 判定

- **M1 视觉层在本机单显示器下通过**：实体屏幕持续黑色，原生全屏进出两次不闪露；Computer Use 截图可读、坐标点击有效；超时恢复正常。这是窗口遮罩方案没有达到的。
- 用户的观察是肉眼现场观察，没有手机录像；不能排除极短的单帧露出，但两轮共四次全屏切换用户均未看到闪动。
- 未验证：普通 Space 切换（只有一个桌面）、鼠标指针是否可见（用户未反馈）、多显示器、夜览/原彩、HDR、睡眠唤醒、UU 连接与 UU 隐私屏。

### 首轮失败原因与修正

首轮进程被启动它的短命 shell 一起结束（具体信号未记录）。已修正：程序忽略 SIGHUP；新增 `scripts/start-detached.sh <log> [参数...]`，以新会话启动并输出 PID，不依赖启动方 shell 存活。修正后已重新构建；`start-detached.sh` 已用 `--no-overlay --duration 3` 验证：父 shell 结束后进程仍独立运行并正常超时退出（日志被 Codex 归档到 `attempt1/detach-check.log`）。现场三轮均未使用该脚本。

### 清理

三轮进程均已退出，后两轮正常超时恢复；Safari 退出全屏，Codex 关闭测试标签页并回读到原起始页，Safari 进程保留。

## 2026-11-05：更名 Curtain 与菜单栏应用第 1、2 步（仅编译和启动检查）

- 目录改为 `/Users/zjf/usr/projects/curtain`，旧路径保留软链接。改名后旧 module cache 带旧绝对路径导致 swift-frontend 崩溃（模块在两个路径重复定义），清空 `build/module-cache` 后编译通过。
- `./scripts/build.sh` 生成 `build/curtain-poc` 和 `build/Curtain.app`，编译通过。
- `open build/Curtain.app`：进程启动，日志 `launched ... safetyTimeout=300.0`；SF Symbols `curtains.closed`/`curtains.open` 在本机存在。`kill -TERM` 后进程退出，日志 `terminated`。
- 未验证：菜单栏图标实际显示与点击、拉上幕布黑屏、防睡眠断言效果、锁屏/睡眠自动拉开、Ctrl+Cmd+Q 恢复、安全超时。需要用户在现场。

## 2026-11-05：菜单栏第 2 步实机——无解锁界面时用户被挡在外面

10:27:41 用户点“拉上幕布”：日志 `sleep-guard held=true`、`gamma-zero readback=black`。当时尚无解锁界面，用户按键/动鼠标无反应，报告“进不了系统”；用户未按 Ctrl+Cmd+Q，期间无锁屏/睡眠事件。10:28:43 由终端 `kill -TERM` 恢复，日志 `gamma-restored displays=1:restored`、`sleep-guard release`。结论：拉上与恢复路径工作，但没有本地解锁入口不可用；随后实现第 3、4 步（硬件事件唤出解锁界面、Touch ID/密码、20 秒回黑），已编译，未实机验证。

## 2026-11-05：解锁界面首次实机

用户实测：拉上后动触控板，解锁界面与 Touch ID 弹窗正常出现，指纹解锁回到桌面（日志 `unlocked method=touch-id`）。问题：Touch ID 弹窗点“取消”（`biometrics-failed code=-2`）后，再点击鼠标不会重新弹出认证，只能 Ctrl+Cmd+Q 锁屏退出（日志 `forced reason=screen-locked`，锁屏强制拉开路径因此首次实测通过）。已修正：取消即回到黑屏，下次动鼠标重新唤出；其他失败时点击面板外重新发起 Touch ID。修正已编译，待复测。

复测（2026-11-05）：取消后回黑、再次唤出、指纹解锁均正常，用户确认看到认证面板。新问题：点取消时手的移动立刻再次唤出解锁界面。已加 3 秒冷却，待复测。

用户确认 3 秒冷却可用。

## 2026-11-05：解锁界面不能被 agent 输入“续命”

代码检查：解锁界面无人操作 20 秒后会回黑，不会卡在解锁界面。但原实现的本地事件监听不区分来源，面板为 key 窗口时 Codex 的合成键盘输入会进入密码框并重置 20 秒计时，理论上可以让解锁界面一直亮着。已修正：只有硬件事件续时；从菜单“解锁…”打开（UU 远程）时仍接受合成输入续时。已编译，重启应用（重启时结束了一个处于拉上状态的旧进程，SIGTERM 恢复了显示）。20 秒回黑与 Touch ID 弹窗随之消失仍待实机验证。

## 2026-11-05：Codex 操作不唤出解锁界面（现场通过）

用户在幕布拉上期间让 Codex 操作，确认未唤出解锁界面。日志：11:50–11:55、13:09–13:14（拉上后一次本地触发并取消）、13:15–13:20 均保持 closed 直到 `dev-safety-timeout`；全程没有 `hardware-monitor ignored-synthetic` 记录，说明 Codex 的事件没有经过全局事件监听（直接投递给目标进程），而不是被 PID 过滤掉。20 秒无操作回黑仍无日志记录，待测。

## 2026-11-05：UU 远程第一轮（UU 隐私屏关）

- 拉上后 UU 画面与操作正常；UU 输入来源 PID 5182（UURemoteServer），日志 `ignored-synthetic pid=5182`，不唤出解锁界面。通过。
- 菜单“解锁…”后 20 秒无操作：`unlock-idle-timeout`，回黑 `readback=black`。通过。
- 密码解锁失败：菜单打开后自动弹 Touch ID，用户点“输入密码”（`biometrics-failed code=-3`），系统认证框关闭后激活权回到 Ghostty，解锁面板是 `.nonactivatingPanel`，点击也拿不回焦点，无法输入。已修正：菜单打开的会话不自动弹 Touch ID（可点“使用触控 ID”）；面板改为普通可激活面板；Touch ID 失败/回退和点击面板时重新激活并聚焦密码框，日志 `unlock-ui focus active= key=`、`key-input hardware=`。已编译重启，待复测。

复测（2026-11-05 13:34、13:42 UTC，UU 远程）：菜单“解锁…”后用户只看到黑屏，没有密码面板。日志 `focus active=false key=false`：macOS 26 拒绝了 `NSApp.activate`。窗口探针（`scripts/window-probe.swift`，读 CGWindowList 层级/位置）显示背景窗口 layer=1000，面板 layer=3：`isFloatingPanel = true` 的 setter 把先设好的层级重置为 `.floating`，面板一直在背景下面。此前本地“看到认证面板”很可能只是系统 Touch ID 框。修正：去掉 `isFloatingPanel`，面板恢复 `.nonactivatingPanel`（应用不激活也能成为 key），日志增加 `level=`。已编译重启，待复测。

复测通过（2026-11-05 13:56 UTC，UU 远程，UU 隐私屏关）：探针显示面板 layer=1001 在背景 1000 之上；UU 键盘输入到达密码框（`key-input hardware=false`，即 UU 的合成按键）；`unlocked method=password`。`focus ... key=false` 是调用后立即读取，不代表最终无法输入。UU 远程用 Curtain 自带密码框解锁通过。待测：UU 隐私屏打开时一轮；本地动鼠标时 Touch ID 框与面板同时出现的表现。

## 2026-11-06：输入来源识别实验（现场，通过）

准备：`build.sh` 改用本机 Apple Development 证书签名（指定要求为 identifier + 证书，不随编译变化），`scripts/install.sh` 安装到 `/Applications/Curtain.app`。旧 ad-hoc 版本留下的辅助功能记录导致新签名不匹配（tccd 日志 `Failed to match existing code requirement`），`tccutil reset Accessibility local.zjf.curtain` 后重新授权；重新编译、重装后权限保留。

探针：`Curtain --input-probe <秒> [--verbose]`，会话层主动 tap，全部放行，只记录 `type / pid / stateID / kbType`，不记录按键内容（Ctrl+Cmd+Q 除外）。

| 输入 | 结果 |
| --- | --- |
| 实体键盘经 Karabiner：keyDown/keyUp/flagsChanged | `pid=0 state=1 kbType=46` |
| 触控板移动、单击、右键、拖动、双指滚动 | `pid=0 state=1`（type 5/1/2/3/6/22） |
| 三指/四指手势、缩放 | `pid=0 state=1`（type 29/30） |
| 音量、亮度键（以及点击伴随的 type 14） | `pid=0 state=1` |
| Ctrl+Cmd+Q | tap 能看到（`ctrl-cmd-q pid=0 state=1`），即**能被拦住**，实现时必须显式放行 |
| 系统锁屏界面输入密码 | tap 仍能看到 keyDown/keyUp（未记录内容），即锁屏时若仍在拦截会挡住登录 |
| Codex Computer Use：TextEdit 中点击、键入、回车、滚动、右键、Esc（01:49:25–01:51:35，用户未触碰） | tap **零事件**：Codex 输入不经过会话层，不会被拦截也不会被误判 |
| UU 鼠标 | 此前全局监听实测 `pid=5182`（UURemoteServer），UU 键盘待补 |

结论：`pid == 0 && stateID == 1` 可稳定识别实体输入，包括经 Karabiner 的键盘。实现约束：显式放行 Ctrl+Cmd+Q；系统锁屏时必须立即停止拦截。

## 2026-11-06：拉上时拦截实体输入，首次现场测试

日志（02:18–02:20 UTC）：
- 拉上后 tap 启动并进入 block；鼠标（type 5）、键盘（type 10）、点击（type 14）都能唤出解锁界面；解锁界面画好后切到 observe，回黑时切回 block。
- Touch ID 取消 → 回黑并冷却 3 秒；冷却结束后键盘唤醒。20 秒无操作回黑正常。指纹解锁后 tap 停止，本轮共吞掉 112 个实体事件。
- Ctrl+Cmd+Q 两次（其中一次在冷却后的 block 中）均进入系统锁屏并强制拉开（`forced reason=screen-locked`），拦截未挡住紧急出口。
- 问题 1：拉上后 0.2–0.4 秒就被鼠标移动唤醒（点菜单的手还在触控板上）。已加 2 秒宽限：期间吞掉输入但不唤醒。
- 问题 2：解锁界面时钟跑到左下角。原因：`BackdropArtView.layout()` 把所有子图层（含时钟所在图层）都设成全屏 frame。改为只调整渐变层和压暗层。
- 两项修正已编译安装，待复测。用户确认：拉上时按下的字母没有进入文本编辑文档（键盘拦截通过）。

复测（02:28–02:29 UTC）：拉上后约 2.2 秒才被触控板唤醒（宽限生效）；时钟位于屏幕上方居中（用户确认）；取消冷却、20 秒回黑、指纹解锁正常，两轮分别吞掉 121、41 个实体事件。待测：拦截开启时 Codex 与 UU 照常操作；守护进程；去掉 5 分钟兜底后的整夜运行。

## 2026-11-06：独立心跳守护与故障锁屏

用户确认实现“约 10 秒无主线程心跳 → 先尝试系统锁屏 → 结束 Curtain 恢复显示/输入”，并在实体 Mac 旁参与真实验收。菜单栏应用默认 `safetyTimeout=0`，实验 CLI 的 1–300 秒上限、解锁界面的 20 秒回黑保持不变。恢复契约见[心跳守护](subsystems/recovery-watchdog.md)。

### 构建与进程级测试

- `./scripts/build.sh` 通过，独立 helper 与应用均使用现有 Apple Development 证书签名；`codesign --verify --deep --strict build/Curtain.app` 通过。已在幕布拉开状态用 `scripts/install.sh` 安装新版到 `/Applications/Curtain.app`；12:00:34（UTC+8）启动日志为 `safetyTimeout=0.0`，没有设置覆盖默认值的 defaults 项。
- 本机 macOS 26.7.1 的 `login.framework/SACLockScreenImmediate` 符号存在。这里只把符号检查算预检，不把它当作锁屏成功证据。
- `python3 scripts/test-watchdog.py` 全部通过。测试 helper 用锁屏替身，未操作实体显示：心跳期限边界、超过 10 秒正常心跳、重复 start/stop、快速重启隔离旧回调、正常撤销不锁屏、缺少 helper、锁屏符号缺失、启动不回应（限时失败）、守护被结束、父进程退出、管道异常关闭、非法协议均覆盖。
- `SIGSTOP` 暂停测试父进程后，锁屏替身成功时约 10.2 秒确认并结束父进程；锁屏失败或请求子进程卡住时约 13.1 秒仍能结束父进程，未无限等待。真实系统锁屏不计入这些模拟结果。
- 进程测试日志：`artifacts/watchdog-tests/`。未记录按键正文或密码。

### 新版真实 GUI 检查

- 12:01:27 拉上，12:01:29 本地触控板唤出解锁，12:01:31 `watchdog disarmed` 在恢复/清理前完成，随后 `unlocked method=touch-id`。用户确认正常回到桌面，没有进入系统锁屏。
- Safari 新开专用本地 `fixtures/click-test.html` 标签页，保留原起始页。使用 Codex Computer Use（`cua_repl` 原生 app API），按截图坐标 `(1512,970)` 点击：基线 0→1；12:02:41 新一轮拉上（gamma 清零、tap block、守护已 ready）后截图仍可读，点击 1→2，日志保持 closed，未唤出解锁界面。应用截图与坐标点击通过，不把它替代实体屏幕连续观察。
- 12:02:41 到 12:09:01 暂停注入前连续保持 closed 约 380 秒，Curtain 与 helper 均存活，无 `dev-safety-timeout`、`gamma-reset-detected` 或意外 unlocking；独立监测记录在 `artifacts/watchdog-tests/onsite-hold.log`。超过 5 分钟后再取应用截图时 Computer Use 返回 `native pipe closed before response`，未将此次截图计为通过；当时进程与幕布状态正常，系统会话仍未锁屏。
- 12:09:01.702 用 `SIGSTOP` 暂停真实菜单栏应用；12:09:11.630 守护判定心跳丢失并请求锁屏，11.672 请求返回 0，11.723 独立读回 `lock-confirmed=true` 后才 `SIGKILL` Curtain；外部监测约 10.129 秒确认 Curtain 退出。Curtain、守护与请求子进程均无残留；未执行 22 秒外部应急结束。日志为 `artifacts/watchdog-tests/onsite-fault.log` 与 `onsite-curtain.log`。
- 真实系统锁屏程序侧确认通过；实体登录界面、遮挡连续性与用户登录结果待现场反馈补充。
- 故障恢复后额外读回显示管线：gamma 表 256 项，最大值约 1，`allBlack=false`；确认已恢复显示曲线，未仅依赖“进程退出就会恢复”的假设。此读回仍不替代实体屏幕验收。
- 系统保持锁屏等待用户自行登录；12:14:44 已重新启动菜单栏应用到默认拉开待命状态（`safetyTimeout=0.0`，未再次清零 gamma，未启动守护）。专用 Safari 测试标签页因系统仍锁屏且 Computer Use 连接断开，暂无法 GUI 清理；登录后继续清理并补现场反馈，不把该轮算作全部现场验收完成。

### 保留边界

锁屏入口是系统私有接口，系统更新后需要复测；锁屏失败时仍优先恢复显示和输入，可能露出桌面。正常进程崩溃不会被本守护追加锁屏（父进程退出后守护直接退出）。UU 在开启输入拦截后的完整回归、UU 隐私屏、普通 Space、多显示器、睡眠唤醒与整夜运行尚未在本轮验证。

## 2026-11-06：Space 与多显示器代码复查

本轮发现并修正：

- gamma 设置/读回失败原先只记日志仍显示 closed；现改为所有在线显示器均成功才启用，启动或运行中任一失败恢复全部显示并拒绝/拉开。枚举从 active 改为 online，包含可能未出现在 active 列表中的镜像成员；不支持 gamma 的外屏会拒绝启用，不能保证驱动支持。
- gamma 巡检原先只在默认 run-loop mode 工作；改为 common modes，避免菜单跟踪期间停止纠正。
- 解锁界面未处理显示器插拔/布局变化；现按快照创建，恢复 gamma 前再核对，解锁中发生实际拓扑变化则尝试回黑并撤销认证，下次唤出重建。认证面板放在鼠标所在显示器。仅颜色通知且布局未变不误取消解锁。
- 解锁窗口本身仍可能随 Space 动画移走。新增 active-Space 通知后回黑，但通知不保证早于过渡开始，因此仍明确保留短暂露出的边界，没有继续叠加已失败的窗口属性。
- 密码校验与 1 秒错误冷却仅检查全局 verifying，旧结果可能进入另一轮验证；现同时核对原密码框身份。Touch ID 原有 LAContext 校验保持。
- 防睡眠断言失败时原先仍继续；现拒绝拉上。安装脚本现在依据当前 PID 的本次启动判断状态，防止旧 closed 日志误阻止更新，并对退出等待设 5 秒上限。

验证：`./scripts/build.sh` 通过；`./scripts/test-display-gamma.sh` 模拟多个独立显示器的初始覆盖、新屏接入、移除、已激活时回黑重验、菜单跟踪模式巡检、API 失败/假成功但读回不黑、枚举失败与全部回滚均通过，未修改实体 gamma。`python3 scripts/test-watchdog.py` 回归全部通过（不锁系统）；安装日志解析的旧 PID/current closed/未知状态三项回归通过。密码跨会话回调和窗口拓扑变化为源码修正、编译通过，尚不能写成真实 GUI 通过。

本机最初仅 1 块在线显示器，且系统仍锁屏。本轮用户随后登录，同意单屏 Space/全屏现场验证；修正版已在拉开状态安装，现场结果继续补充。真实双屏、镜像、HDR、热插拔第一帧均未验证。

### 修正版全屏现场复测

13:05:41（UTC+8）通过菜单拉上，`display=1 result=0 readback=black`，tap block、独立守护 ready。Computer Use 原生 Safari 截图可读，坐标 `(1512,970)` 点击依次 2→3（普通）、3→4（第一次全屏）、4→5（返回普通）、5→6（第二次全屏）、6→7（再次返回普通）；两轮由 `Ctrl+Cmd+F` 进入/退出原生全屏，各阶段截图确认窗口形态与内容。全程日志保持 closed，无误唤醒或 gamma 重置。用户确认“全程不闪”，随后 13:10:32 Touch ID 正常解锁并撤销守护。Safari 已返回普通窗口。

### 普通 Space 与实际显示配置核对

13:15:55 用有限时独立 CLI（`--gamma --duration 180`，菜单栏保持 open、不拦截本地输入）测试普通桌面。此时系统已变成镜像配置：活动 `display=3`，1920×1080；内置 `display=1` 不 active、`mirrorOf=3`。用户确认接了实体外接屏。两块在线显示器清零均成功且读回全零，因此 online 枚举实际覆盖了 active 列表会省略的内置镜像成员；不据此认定两块实体屏都已观察通过。

用户最初反馈 Ctrl+方向键往返后全黑，但随后说明黑屏时不知道是否真的切换成功。只读 NSWorkspace 探针也没有 Space 通知，Safari 测试标签页变成起始页，故**不把该次快捷键尝试计为普通 Space 通过**。13:18:51 提前 SIGTERM 结束 CLI，恢复曲线并清理；只读探针自行按 200 秒限时退出。日志在 `artifacts/display-review/`。已加入主应用 Space/显示变化事件日志，先做明屏基线，再黑屏重测；真实扩展模式与热插拔仍待测。

13:24:33、13:24:34 明屏基线：用户确认调度中心存在两个普通桌面，并实际 A→B→A；主应用独立收到两次 `active-space-changed state=open`。用户同时确认此前镜像配置的两块实体屏均黑，没有闪露。

13:26:34–13:28:04 用新一轮 `--gamma --duration 90` 重测（日志 `space-gamma-confirmed.log`），3、1 两块在线显示器清零成功并读回全零。13:27:46、13:27:47 主应用记录两次真实 Space 通知，均在 CLI 超时前；用户确认已按同一套明屏有效操作完成普通 A→B→A，**内置屏与实体外接屏全程黑、不闪**。CLI 90 秒超时正常恢复，`reapplied=0`。据此，当前 1920×1080 镜像配置下 gamma 遮挡的普通 Space 往返现场通过；这轮菜单栏处于 open、CLI 未拦截输入，不能误称为“实体输入被拦截时还能用本地快捷键切 Space”。

工具侧截图与坐标点击已在本轮菜单栏全屏测试中通过；第二轮普通 Space 测试结束时 CLI 已超时，未把恢复后的截图/点击充作黑屏期间的工具验收。真实扩展桌面、HDR、热插拔首次亮屏、整夜运行仍待验证。解锁界面在 Space 变化时主动回黑的现场结果另行补充。

### 镜像双屏：解锁界面切 Space 主动回黑

13:33:22 菜单栏拉上，3 与 1 均清零成功，tap block；13:33:26 触控板唤出，先显示背景再恢复 gamma，切到 observe。用户选择“输入密码”关闭 Touch ID 框（`biometrics-failed code=-3`），未正常解锁。

13:33:44.845、13:34:01.522 两次 `active-space-changed state=unlocking` 后，均重新清零 3 与 1，再 observe→block、隐藏旧界面，进入 `closed active-space-changed`；日志中两块清零完成分别约在通知后 10、17 毫秒，隐藏窗口约在通知后 22、24 毫秒。该时间从收到通知开始计算，不是动画开始时刻。

13:34:05 Touch ID 正常解锁，守护撤销、tap 停止、释放防睡眠。用户确认“切换后自动回黑，未看到桌面闪露，已正常解锁”。因此当前镜像配置下两次解锁界面 Space 变化回黑通过；肉眼观察不能排除单帧闪露，不将其外推成任意动画零闪露保证。

清理：所有本轮 CLI/probe/守护均已退出；菜单栏应用保持 open 待命；Computer Use 关闭专用 Safari 测试标签页并回读原起始页，Safari 进程保留，原生全屏已退出。普通桌面由用户人工准备和往返，agent 未自动删除用户桌面或改变外屏镜像设置。原始过程日志保存于 `artifacts/display-review/curtain.log`。

## 2026-11-06：再次复查——恢复竞态与 gamma 并发控制

前轮漏掉的两项边界已复现并修复，本轮使用可结束的测试进程与模拟曲线，不触发真实锁屏、不改实体 gamma：

- 守护主动 SIGSTOP 父进程后，如果守护被结束，测试父进程仍停在 T 状态。改为先回复故障已提交 `F`，正常解锁、退出、SIGTERM 收到后延后恢复/退出；守护不主动暂停父进程。守护随后退出且主线程恢复运行时，仍能收到退出回调并清理。请求子进程监听守护退出并设自身 3 秒退出计时，避免孤儿请求进程。
- 两个模拟 GammaBlackout 共享曲线时，停止一个会使另一个仍 active 但曲线已恢复。新增同用户跨进程 GammaLease，在 Application Support 的稳定文件上持有 flock；只有取得控制权的实例能设置/恢复 gamma，进程退出自动释放，exec 子进程不继承。重复控制的 CLI 在任何 gamma 设置前拒绝，并返回 1；正常清理返回 0、参数错误返回 2。
- 日志改为捕获写入错误，应用/CLI 忽略 SIGPIPE，避免日志管道关闭或写入失败直接中止恢复。通信单向断开时，即使发送 disarm 失败，也必须读取可能已排队的 F；恢复未结束前不能提前发出“守护失效、可拉开”的回调。

验证均通过：`./scripts/build.sh`；`python3 scripts/test-watchdog.py`（含迟到 disarm、恢复中结束守护、关闭命令通道、损坏日志管道、锁屏失败/卡住和全部原有回归）；`./scripts/test-display-gamma.sh`（含跨进程互斥、被拒绝者不能恢复曲线、持有者 SIGKILL 后回收、真实 CLI 持锁拒绝且无 gamma-zero）；CLI 无遮罩正常退出 0、非法时长退出 2。新增测试未遗留请求进程。

代码、复现与回归输出位于 `artifacts/recovery-review/`、`artifacts/watchdog-tests/`。修正版已在菜单栏处于拉开状态时安装到 `/Applications/Curtain.app`。本轮未重做实体黑屏、真实系统锁屏或 GUI 解锁验收；此前现场记录对应当时版本，不能把本轮编译/模拟通过当作新的现场结果。扩展模式、HDR、热插拔首帧、整夜运行仍待测。

## 2026-11-06：交接 P1——gamma 回滚绕过守护 F

交接证据 `artifacts/code-review/handoff.md`、`RecoveryGammaRace.swift`、`recovery-gamma-race.log` 确认：主线程停顿超过 10 秒后，GammaBlackout.refresh 在通知 owner 之前已经 restore；owner 再向守护请求撤销得到 F 时，曲线已提前恢复。相同隐式回滚也存在于已激活 start 重验、首次 start 部分设置失败路径。此前单模块通过不代表这个组合顺序正确；证据是替身与模拟曲线，非实体闪露观察。

修复：失败组件暂停巡检、撤销显示回调并保留曲线/lease，以 isProtectionFailed 区分“仍持有待清理状态”和“保护有效”；start 失败由调用者清理，refresh 失败交回 owner，不在回调前后无条件 stop。菜单栏统一先请求撤销守护，再清理输入、gamma、窗口和防睡眠；F 拒绝时进入 recovering，暂停解锁/安全计时、禁止新唤醒和回滚，保留资源等待锁屏或守护退出。首次拉上仍处于 open 时也走完整清理，回黑失败同样受保护。解锁 UI 呈现前检查已排队 F，拒绝时不恢复 gamma、不自动弹 Touch ID；正常呈现保持守护运行。CLI 无守护，沿用立即回滚和退出 1。

验证全部通过：

- `./scripts/build.sh`，以及 `git diff --check`。
- `python3 scripts/test-watchdog.py`，包含健康呈现许可、已提交 F 拒绝呈现/撤销及原有故障回归；日志 `artifacts/code-review/fix-watchdog.log`。
- `./scripts/test-display-gamma.sh`，更新为 owner 显式清理失败 start，保留原多屏/互斥/CLI 拒绝回归；日志 `artifacts/code-review/fix-display-gamma.log`。
- `python3 scripts/test-recovery-gamma.py`：17 个组合场景，覆盖 refresh、已激活 start、首次 start、relock start 的枚举/设置失败 × 正常撤销/F 已提交，以及守护退出后延迟清理。真实守护管道协议加模拟曲线/锁屏替身，确认 F 下 restore 次数不增加、有效曲线仍在、lease 不释放、巡检/重试不再写表或重复通知；正常撤销及守护退出时只恢复一次并完整释放。
- 同一新增脚本将生产 CLI 仅替换后端构造，实际运行原 start/failure/cleanup/exit 流程：首次部分设置失败、运行中枚举失败均回滚一次并退出 1。组合输出 `artifacts/code-review/fix-regressions.log`，逐场景日志 `artifacts/recovery-gamma-tests/`。

本轮保留全部已有工作区修改；未安装或重启正在运行的应用，未修改实体 gamma、未请求真实锁屏，未新增现场 GUI 验收。构建产物为待部署修正版，既有全屏/镜像现场记录仍对应当时版本；扩展模式、HDR、热插拔首帧、整夜运行继续待测。

## 2026-11-06：更新、关于、辅助功能引导

接续 `artifacts/update-review/handoff.md` 的菜单/版本半成品，保留 e693b28 故障恢复实现；参考同级 Barlet，只读参考源码，没有修改参考项目。新增手动更新器、包校验与隔离原子交换、系统关于面板和可暂缓的辅助功能引导。契约见[应用维护](subsystems/app-maintenance.md)。

验证结果：

- `./scripts/build.sh` 通过，无新增编译警告；生成 `build/Curtain.app`、嵌套 CurtainWatchdog、实验 CLI 和 `build/Curtain.zip`。`codesign --verify --deep --strict build/Curtain.app` 通过。构建元数据读回 `0.1.0`、git 提交数 `3`、`e693b28-dirty`，dirty 检测包括新增未跟踪文件。
- `python3 scripts/test-updates.py` 共 56 项检查通过，使用 build/update-tests 内的隔离应用。包含数字版本/稳定发布解析、HTTPS 同源链接、真实 Apple Development 签名 ZIP 经系统 tar 解压后主包及嵌套签名仍有效；错误 bundle ID、不同发布版本、不高于当前的包、其他 Team 条件、ad-hoc、缺少/篡改 helper、篡改主包、过高系统要求均被拒绝。没有调用当前应用的更新安装流程。
- 恶意包覆盖 `..`、绝对路径、符号链接、硬链接和其他根目录，均在生成解压目录前拒绝。最终交换的隐私状态拒绝、已取消任务、缺少目标路径的 OS 交换失败均保留旧应用；重启准备回调失败会交换回旧目录；成功交换则旧版保留在 candidate 路径。只改测试目录，不改 /Applications。
- 权限轮询替身验证授权/撤销各通知一次，不创建 tap；禁止呈现时不创建权限窗口，禁止更新时不开始网络工作。这不等同真实授权拖放/权限撤销或完整菜单验收。
- 中途审查发现通配隐藏 `NSApp.windows` 会同时隐藏 `NSStatusBarWindow`，破坏 UU 菜单解锁。已删除该写法，生产仅隐藏明确持有的关于/权限窗口。独立原生 AppKit 探针真实确认：keyWindow 在标准关于调用后可能仍为空；捕获该调用新建的 NSPanel 后，隐藏两种辅助窗口时状态栏仍 `isVisible=true`。探针临时图标与窗口均已清理；它是窗口所有权性质检查，不冒充 Computer Use 坐标点击或 UU 解锁验收。
- `python3 scripts/test-watchdog.py`、`./scripts/test-display-gamma.sh`、`python3 scripts/test-recovery-gamma.py` 均通过；沿用锁屏替身与模拟 gamma，未改实体显示、未触发真实锁屏。`git diff --check` 通过。
- 主审独立 PackageAudit 补验：生产 `Curtain.zip` 解压后主包及嵌套签名通过；发布版本不符、主程序篡改均被拒绝。此结果来自独立审查，不替代真实网络安装。
- 主审 GUI 尝试：不同 bundle id、独立日志的隔离副本启动正常；Codex `cua_repl` 分别按路径和 bundle id 读取窗口，两次均报 `server error -10005 timeoutReached`。未取得可用窗口状态，**GUI 验收仍待测，不能记为通过**。测试副本已 TERM 清理，原安装进程未重启，没有拉幕或触发系统锁屏。

原始输出：`artifacts/update-review/final-build.log`、`final-updates.log`、`utility-window.log`、`watchdog.log`、`display-gamma.log`、`recovery-gamma.log`。原生探针为同目录 `UtilityWindowProbe.swift`。

发布阻塞与未验范围：当前没有 Curtain remote；此前对同服务器 admin/curtain 的只读查询为 404（交接证据 `curtain-release-repo.json`），本轮没有创建仓库或发布。配置入口已接入，404 不会当作最新版；真实服务检查、联网下载、安装后自动重启、应用完整菜单、权限拖入/系统设置与新代码下 UU 菜单解锁均待主审/现场复核。保留所有当前修改，未提交、推送、发布、安装或重启正在使用的应用。
