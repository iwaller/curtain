# 心跳守护与故障锁屏

状态：2026-11-06 已实现，构建和进程级测试通过；真实应用暂停后约 10.1 秒先确认系统锁屏再结束，超过 5 分钟保持也已检查。实体登录验收等结果分别记录在[验证记录](../verification.md)。这不是开机自启或后台常驻服务，只在菜单栏应用的 closed/unlocking 会话运行。

源码：[RecoveryWatchdog.swift](../../Sources/App/RecoveryWatchdog.swift)、[Watchdog](../../Sources/Watchdog/Watchdog.swift)、[锁屏入口](../../Sources/Watchdog/SystemScreenLock.swift)。

## 启动与正常结束

1. 拉上前启动应用包内独立、单独签名的 `Contents/Helpers/CurtainWatchdog`。子进程确认系统锁屏符号存在，向专用管道回复 ready；最多等待 2 秒。失败时保持幕布拉开并提示用户。
2. ready 后才清零 gamma、启动输入拦截。主线程每秒通过非阻塞管道发心跳；Timer 加到 common run-loop modes，避免展开菜单导致误报。closed 与 unlocking 全程受保护，20 秒回黑不会撤销守护。
3. 正常解锁、系统锁屏/睡眠、退出和 SIGTERM 清理时，先发送 disarm，收到确认后关闭管道，再恢复 gamma、停止输入拦截。确认最长等 2 秒；守护已异常时结束守护并继续恢复。若收到故障已提交的 `F` 回复，则暂缓拉开与正常退出，等故障锁屏/结束流程完成，不能在锁屏前恢复桌面。
4. 正常 disarm 不锁屏。旧进程的异步退出回调按进程对象隔离，不影响下一次拉上。父进程已退出时守护自行退出，不在用户重新登录后补锁屏。

所有 gamma 失败回滚也必须经过该门槛：GammaBlackout 只暂停巡检并保留曲线/lease，运行失败交回 owner，start/relock 失败由调用者处理。菜单栏不能在调用 `stop()` 询问守护之前恢复曲线。若清理被拒绝，进入 recovering，停用解锁/安全计时和新的本地唤醒，保留其他资源；守护退出且主线程可运行时统一清理。正常解锁窗口呈现前另外非阻塞检查已排队的 `F`，拒绝时不恢复 gamma、不发起 Touch ID，正常呈现仍保持守护运行。

默认取消菜单栏应用的 300 秒自动拉开；开发调试仍可用 `defaults write local.zjf.curtain devSafetyTimeoutSeconds -float 300` 临时恢复，`defaults delete local.zjf.curtain devSafetyTimeoutSeconds` 返回默认无限时。实验 CLI 仍限时 1–300 秒；解锁界面的 20 秒无操作回黑保持不变。

## 故障恢复

- 使用单调运行时间判断心跳；约 10 秒无心跳、管道异常关闭或非法协议，视为故障。只处理自身的直接父进程，不接受命令行传入的目标 PID；每次破坏性操作前核对父子关系，防止旧 PID 被重用后误杀新进程。
- 故障判定后先向专用回复管道写入 `F`，再请求锁屏。主程序后来恢复响应、恰好正常解锁/退出时，disarm 会读到 `F` 并延后清理；重复请求也不能取消已提交的恢复。正常退出代理和 SIGTERM 路径同样遵守该结果。
- **守护不再主动 SIGSTOP 父进程。** 原实现会在守护随后崩溃时把父进程永久留在暂停状态；现保留父进程恢复执行及接收守护退出通知的机会。测试仍可从外部 SIGSTOP 模拟无响应，但那不是产品主动暂停。
- 守护启动另一个短命子进程请求系统锁屏；通过 `CGSessionCopyCurrentDictionary` 的 `CGSSessionScreenIsLocked` 确认结果。已锁屏时不重复请求；不在当前控制台的会话不请求锁屏，避免干扰另一用户。
- 锁屏确认最多等待 3 秒，随后 `SIGKILL` 父进程；系统释放 gamma 与 tap。请求子进程若卡住也会被结束；请求子进程另监听守护退出并持有自身 3 秒退出计时，避免守护异常后留下长期运行的请求进程。日志明确记录 `lock-confirmed=true/false`，请求返回成功不等同于锁屏已经确认。
- **锁屏失败/超时仍结束 Curtain，优先恢复显示和输入，可能露出桌面。** 本功能不是安全锁屏保证。正常系统锁屏会中断 Computer Use；这里只在故障时主动请求。
- 守护自身被结束：主线程可运行时，通过进程退出回调或下一次心跳发现后强制拉开；即使已经收到 `F`，确认守护已退出后仍允许恢复。主线程也一直无响应、或父子进程同时被停止时不在单守护恢复范围内，仍可从终端 `kill -KILL <Curtain pid>`，最坏强制重启。

## 系统接口边界

macOS 没有公开的 AppKit 锁屏入口。此个人应用通过 `dlopen/dlsym` 动态解析系统私有 `login.framework` 的 `SACLockScreenImmediate`，不注入快捷键、不使用 AppleScript、不修改系统安全设置。系统更新可能改变此入口：符号缺失时拒绝拉上；运行时失败按上述恢复优先策略处理。本机符号存在只算预检，实际调用与系统登录验收必须单独记录。

## 验证

`python3 scripts/test-watchdog.py` 编译测试用锁屏替身与客户端，执行真实管道、心跳、暂停和结束进程测试；不会锁屏、改 gamma 或操作正在运行的 Curtain。替身只链接到 `build/watchdog-tests/`，生产 helper 没有跳过锁屏的测试开关。日志放 `artifacts/watchdog-tests/`。

真实验收：说明恢复办法 → 拉上幕布 → 确认 Computer Use 截图与坐标输入 → `kill -STOP <Curtain pid>` → 约 10 秒后请求系统锁屏并结束 Curtain → 现场确认看到登录界面且能正常登录。还需单测正常解锁不锁系统、重复拉上/拉开、超过 5 分钟保持、UU 和整夜运行。
