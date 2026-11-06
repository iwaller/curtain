# 黑色遮罩与生命周期

状态：已实现最小 POC；单显示器退出和工具侧截图/坐标点击已测。UU 远程分阶段复测确认闪露，退出全屏动画中的桌面采样捕获露页，持续覆盖失败；实体覆盖与普通 Space 切换待确认。源码：窗口实验 [POC](../../Sources/POC/main.swift)，gamma [GammaBlackout.swift](../../Sources/Shared/GammaBlackout.swift)。

## 职责

管理当前登录会话中的黑色覆盖窗口、显示器边界、Space 相关行为和有限时退出。首版只提供视觉覆盖，不认证用户、不拦截本地输入、不触发系统锁屏。

## 窗口契约

- 每个显示器一个不透明黑色无边框窗口，覆盖完整 `screen.frame`，不能只覆盖不含菜单栏/Dock 的可用区。
- 使用 `CGWindowLevelForKey(.screenSaverWindow)`（本机值 1000），组合 `.canJoinAllSpaces`、`.fullScreenAuxiliary`、`.stationary`、`.ignoresCycle`；普通桌面和 Safari 全屏工具侧已测，实体与普通 Space 待确认。
- 避免成为 key/main window，不主动抢走底层应用焦点；观察工具激活 Safari 时遮罩是否仍在上方。
- 初始 `ignoresMouseEvents = true`；此设置允许本地鼠标穿透，因此不构成输入锁。
- 普通模式与 `sharingType = .none` 对照模式保持其他条件一致，方便定位截图差异。

以上为实现目标，不代表这些属性在所有 macOS、全屏组合或截图 API 中保证有效。

## 生命周期

实现状态：未启动 → 安装 Timer/信号退出 → 显示遮罩 → 超时或主动退出 → 释放全部窗口。显示遮罩前先安装自动关闭机制。不要只依赖应用内按键退出，因为遮罩不会持有键盘焦点。

首版为有时间上限的实验进程，不自动重启。退出须移除观察者并释放窗口；终止进程后也应由系统移除其窗口，并在实测中确认。

显示器热插拔、系统睡眠唤醒、其他全屏 App 组合属于后续可靠性验收；若首轮没有执行，明确标为未验证。

## 失败语义

截图不可用、输入失败、实体内容露出、Space 覆盖失效分别记录，不用“遮罩启动成功”掩盖整体实验失败。若只是窗口属性设置成功而没有观察覆盖，状态仍为待验证。

## 命令与退出

`--duration` 接受 1–300 秒（默认 90），拒绝缺值、非有限值及越界值；未知参数返回 2，不创建窗口。`--exclude-capture` 将 sharingType 从 `.readOnly` 改为 `.none`；首轮普通模式通过工具侧检查，未运行 `.none` GUI 对照。`--no-overlay` 只跑生命周期，不创建遮罩。

主线程处理窗口；`.prohibited` 激活策略及不成为 key/main 的窗口避免抢焦点。SIGINT/SIGTERM 通过主队列信号源调用清理，超时同样清理窗口/观察者/定时器；清理可重复调用且只执行一次。启动日志含 PID，终端兜底为 `kill -TERM <pid>`。未使用 Escape、系统锁屏或开机自启。

## 已知失败：退出原生全屏动画

同一窗口实现下，120 秒分阶段复测捕获退出 Safari 原生全屏动画中的桌面测试页。遮罩进程未提前退出，后续稳定态又恢复黑色。因此当前高层级/跨 Space/全屏辅助属性组合不能保证过渡覆盖。不得以稳定态截图通过宣称隐私功能可用；需要调整或规避该过渡后实测。详见 [验证记录](../verification.md)。

## 2026-11-04 修复对照结论

`.canJoinAllApplications`、NSPanel/非激活面板以及去除 `.fullScreenAuxiliary` 的独立角色均仍闪露。公开 `CGCaptureAllDisplays` 系统屏蔽层在本机全屏切换后同样不能满足遮挡要求，已正常释放并回退实验分支。当前源码未保留这些失败配置，只有日志增加毫秒精度。

窗口轨迹确认，至少一轮进入全屏时，遮罩坐标随旧 Space 从 x=0 移至 -827 后返回；“onscreen=true / layer=1000”不能代表始终覆盖物理屏幕。后续应更换或限定遮挡机制，并以真实过渡验证，详见 [验证记录](../verification.md)。

## Gamma 清零实验模式（`--gamma`）

不创建窗口；把所有在线显示器的 gamma 表设为 0，在合成之后的显示管线让整屏变黑，用于绕开 Space/全屏过渡把窗口移走的问题。2026-11-06 起枚举使用 `CGGetOnlineDisplayList`，覆盖 active 列表可能省略的镜像成员；每块均要求设置成功并读回全零，不能仅靠 API 返回成功。不支持 gamma 的虚拟屏/外屏可能因此无法启用，必须用实际驱动验证。

任一块失败或枚举不可用时，先暂停 50 毫秒巡检、撤销显示器回调，保留已设置的曲线及 lease，标记 `isProtectionFailed`。`isActive` 此时仅表示仍持有待清理的显示状态，不代表遮挡通过。失败后 `start` 拒绝重试，`refresh` 不重复通知或写表；只有 owner 的 `stop` 才恢复曲线、清除失败标志并释放 lease。

运行中失败只通知 `onFailure`，不在通知前后自行回滚；首次 `start` 或已激活重验失败返回 false，同样不隐式恢复。菜单栏 owner 统一先请求撤销守护：允许时清理全部资源并拉开；收到 `F` 时进入 recovering、保留曲线/lease/窗口/防睡眠等待锁屏或守护退出，避免提前露出。即使控制器尚处于 open 的首次拉上准备阶段，也必须经过完整清理门槛。CLI 没有守护，失败后立即 `stop`、回滚并返回 1；没有配置失败回调的独立实例在运行失败时沿用立即回滚的默认语义。

显示器重新配置时再次校验，并每 50 毫秒在 common run-loop modes 读回检测是否被重置；菜单跟踪期间也继续巡检。已运行时再次 start 仍校验当前显示器，避免重新回黑时漏掉刚接入的屏幕。退出时恢复 ColorSync 设置，进程意外退出由 Quartz 自动恢复。CLI 不能与 `--exclude-capture`、`--no-overlay` 同用。

**边界：热插拔的首次亮屏可能早于系统通知和巡检，不能保证零帧闪露；HDR、镜像、不同厂商外屏与驱动均需实体观察。** 单屏应用截图、模拟多屏表的全零读回都不是多显示器实体隐私验收。驱动边界在 [DisplayGamma.swift](../../Sources/Shared/DisplayGamma.swift)，模拟验证为 `./scripts/test-display-gamma.sh`，不改变实体 gamma。

## 同一用户的 gamma 控制权

`GammaLease` 在 `~/Library/Application Support/Curtain/gamma.lock` 上持有非阻塞排他 flock；先取得控制权，才注册回调、设置曲线。菜单栏、实验 CLI、重复进程都使用同一路径，与 TMPDIR 无关。未取得控制权就拒绝启用，不调用全局 `CGDisplayRestoreColorSyncSettings`，避免退出时把另一实例的幕布拉开。CLI 的 gamma 启动/持续保护失败返回 1，参数错误返回 2，正常超时/信号清理保持原有成功退出语义。

锁覆盖 gamma 生效及失败等待授权清理期间；正常显示解锁窗口时 gamma 已恢复，因此释放。停止时先恢复再释放锁，进程崩溃/SIGKILL 则由内核释放；文件保留但不等于仍被占用，不在释放时 unlink，防止新旧 inode 分别被锁。fd 使用 close-on-exec，守护及请求子进程不继承控制权。该锁只协调 Curtain，不能阻止 UU、ColorSync 等其他软件修改 gamma。

状态：2026-11-05 现场验证通过（单显示器）：实体屏幕持续黑色，原生全屏进出不闪，Computer Use 截图可读、坐标点击有效，超时恢复正常，未发生 gamma 重置。光标、普通 Space、夜览/原彩、HDR、多显示器、UU 未验证。程序忽略 SIGHUP，避免随启动 shell 退出。UU 远程采集帧缓冲，看到的是正常画面，不能用来判断遮挡。详见 [验证记录](../verification.md)。

2026-11-06 更新：修正版单屏菜单栏两轮原生全屏进出通过（截图与坐标点击、用户实体观察均通过）。另接实体外屏形成 1920×1080 镜像：active 为 3，内置 1 镜像到 3；两块 online 均清零成功。先确认明屏 Space 切换，再在 90 秒 CLI 生效期间记录两次实际普通 Space 通知，用户确认两块实体屏均全黑且不闪。该镜像组合的普通 Space 遮挡通过；扩展桌面、HDR、夜览/原彩、热插拔首次亮屏仍待测。
