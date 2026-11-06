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
