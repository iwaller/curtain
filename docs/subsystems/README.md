# 子系统索引

先读设计，再对照真实源码。已创建最小 Swift/AppKit POC 和专用测试页面；工具侧结果与实体观察分开记录。

| 子系统 | 设计 | 当前实现 |
| --- | --- | --- |
| 黑色遮罩与生命周期 | [privacy-overlay.md](privacy-overlay.md) | [GammaBlackout.swift](../../Sources/Shared/GammaBlackout.swift)、[DisplayGamma.swift](../../Sources/Shared/DisplayGamma.swift)、[GammaLease.swift](../../Sources/Shared/GammaLease.swift)、[POC](../../Sources/POC/main.swift) |
| 菜单栏应用 | [menu-bar-app.md](menu-bar-app.md) | [CurtainApp.swift](../../Sources/App/CurtainApp.swift)、[SystemGuards.swift](../../Sources/App/SystemGuards.swift) |
| 本地输入拦截 | [input-guard.md](input-guard.md) | [InputGuard.swift](../../Sources/App/InputGuard.swift)、[InputProbe.swift](../../Sources/App/InputProbe.swift) |
| 心跳守护与故障锁屏 | [recovery-watchdog.md](recovery-watchdog.md) | [RecoveryWatchdog.swift](../../Sources/App/RecoveryWatchdog.swift)、[Watchdog.swift](../../Sources/Watchdog/Watchdog.swift) |
| Computer Use 兼容性验证 | [computer-use-validation.md](computer-use-validation.md) | [测试页](../../fixtures/click-test.html)、[验证记录](../verification.md) |

## 维护规则

- 职责、输入输出、生命周期和失败语义变化时，同步更新所属设计。
- 一个事实选择一个主要维护位置，其他文档通过链接引用。
- 新增源码后，在本索引及 [架构地图](../architecture.md) 补真实文件链接。
- 设计、编译成功和真实验收分别记录，禁止把预期行为写成实测结论。
- 实验记录放在 [验证记录](../verification.md) 或 `docs/operations/`，原始截图和日志放在忽略的 `artifacts/`。
