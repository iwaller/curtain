# 阶段与继续条件

## 2026-11-06 当前继续点

Direct distribution now uses Ed25519-authenticated updates from GitHub Releases (`iwaller/curtain`). Local package verification and installer regressions are covered; a published release, real network installation/restart, Gatekeeper approval, and Accessibility retention on another Mac remain acceptance work. See the [release procedure](operations/releasing.md).

更新、关于、辅助功能引导已接续实现，隔离包验证与原生状态栏保留探针通过；完整维护流程 GUI 和真实发布下载安装待复核。尚无可用 Curtain 发布源，不将其描述为已通过在线更新；详见[应用维护](subsystems/app-maintenance.md)。现有隐私路线的继续点如下。

菜单栏、本地输入拦截与解锁已实现；独立心跳守护及故障时先请求系统锁屏已接入，菜单栏默认取消 5 分钟自动拉开。正常解锁不锁系统、超过 5 分钟保持、真实无响应后锁屏恢复、修正版单屏全屏、镜像双屏普通 Space 遮挡与解锁界面 Space 变化回黑均有验证，范围见[验证记录](verification.md)。接下来验证扩展桌面、热插拔、HDR、输入拦截下 UU 完整操作、UU 隐私屏和整夜运行；不把镜像双屏结果外推到所有显示器组合。下文 M0–M3 为早期阶段划分。

## M0：独立项目与分析（已完成）

在 `weiteng-java` 的同级目录创建项目，参考 `dify-cli` 的 agent 文档结构，提供需求分析、架构、子系统契约、实验方案及验证记录模板。本阶段只建立文档，不运行遮罩。

## M1：最小 AppKit POC（gamma 方案视觉层通过，UU/Space 待测）

已检测工具链、建立构建入口，实现手动黑色覆盖窗口、限时退出、SIGTERM 清理与专用 Safari 页面。普通遮罩、Safari 全屏与返回的应用截图和坐标点击通过工具侧检查，桌面合成截图为黑色。

UU 远程分阶段复测已确认闪露，桌面采样明确捕获退出原生全屏动画中的测试网页，且当时遮罩进程仍运行。持续覆盖失败。四项针对性对照仍失败，改动已回退；窗口轨迹确认遮罩可随旧 Space 动画移走。下一步评估独立于 Space 合成的遮挡路线，或明确限定不使用原生全屏/Space 过渡的工作流，再补实体屏幕现场确认。M1 未完整通过，不进入 M2/M3。

用现有 Computer Use 验证基线、遮罩后截图、坐标点击、Space/原生全屏切换。普通遮罩失败时只做必要的采集排除属性对照。

2026-11-05：`--gamma` 现场验证通过，实体全黑、原生全屏进出不闪、Computer Use 截图与点击有效。剩余 UU 连接（含 UU 隐私屏开/关）和普通 Space 切换。产品需求与新阶段划分见 [产品需求](requirements.md)。

继续条件：实体遮罩持续有效，且工具截图、坐标点击均可用。没有观察证据的项目不得标为通过。

## M2：可靠性与输入边界（仅在 M1 通过后评估）

补充显示器插拔、不同缩放、睡眠唤醒、进程异常和更多 Space 切换组合。明确最终产品是否需要阻止本地人员操作。

若需限制本地输入，必须独立验证能否可靠区分并允许 Computer Use 输入；不能假定普通事件拦截天然具备这种能力。若无法满足，需要调整产品定位或技术路线。

## M3：产品体验（待决定）

可靠性和输入边界明确后，再讨论退出验证、密码存储、菜单栏和打包签名。不修改 macOS 系统认证，不把应用遮罩描述为系统锁屏。

M1 失败则回到遮挡/采集机制评估，不继续堆叠产品功能。
