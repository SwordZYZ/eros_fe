# iPadOS 锁屏调试与取证摘要

开发基线使用 Xcode 27.2、Flutter 3.47.3 和 Dart 3.13.3。可选 Profile 刷新探针在同一工具链的专项 checkout 中验证。3.47.5 是单独测试的候选 SDK。

## 2026-11-20 问题对照

设备为 iPad Pro 11 英寸（M4），iPadOS 27.2（`24B119`），通过 USB 连接。原始日志、崩溃报告、构建详情和设备标识保存在本地。

| 会话 | 进程与锁屏恢复 | VM Service | 业务观察 |
| --- | --- | --- | --- |
| 3.47.3 Profile | 操作后 App 保持响应，缺少完整的锁屏生命周期记录 | 未验收 | 拷贝和刷新成功 |
| 3.47.5 Debug，`flutter run` | 两次锁屏后 VM 连接关闭，随后宿主执行终止，设备记录 `SIGKILL` | 断开 | 因进程退出中断 |
| 3.47.5 Debug，独立 LLDB | 两轮均由各自的原进程恢复前台。无分享的一轮有 `paused` → `resumed` 事件，两轮均无新增 `.ips` | 解锁后均不可达 | 无分享和拷贝后的刷新均未通过 |

先前 3.47.3 Debug 的 `EXC_BAD_ACCESS / SIGBUS` 和本轮宿主终止分别记录。独立 LLDB 的进程恢复、Dart VM 重连和刷新各有独立结论。开发链路复测只验证启动、锁屏恢复和取证，业务修复由对应问题验收。 [开发手册](ios-development.md#cli-真机锁屏回归)

## 2026-11-20 开发链路复测

- **模拟器通过。** 在使用固定工具链的独立 checkout 上，用 arm64 iOS 27.2 跑完整 `ios_dev.sh ci`。14 项宿主测试、Debug 构建、无账号冷启动、设置与返回均通过，三份依赖锁文件的哈希一致。
- **真机启动和锁屏恢复通过。** 核对现有签名、二进制和锁文件哈希后，复用带专项探针的 Flutter 3.47.3 Profile 包。`devicectl` 直接启动成功，锁屏前后 CoreDevice 均通过 USB 可达，App PID 和可执行文件路径一致。探针记录 `paused` 到 `resumed` 约 9.5 秒。使用者确认解锁后回到原画面且 App 可以正常响应。
- **独立取证通过。** 锁屏前后均通过 CoreDevice 导出 `step5a-events.json` 并验证 JSON。`logs device` 成功查询设备、导出 App 日志目录并复制一份已有的匹配 `.ips`。本轮无新增 `.ips`。本轮未附加 Dart VM Service 或 LLDB，重连记为「不适用」。拷贝、分享和刷新留给各自的业务验收。
