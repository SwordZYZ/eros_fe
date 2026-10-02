# iOS 开发锁：Step 5A 后退出异常核实与修复

**针对性验证通过。** 旧脚本在真实 macOS 进程夹具中重现与 5A 相同的 `finish_group → group_exists → os.killpg(pgid, 0)` 异常；修改后同一退出路径通过，活动进程清理期间仍拒绝下一任务，清理完成后锁可重新取得。另用已有模拟器 Debug 产物验证一次实际 Flutter `q` 退出，结果通过。

## 1. 固定范围和环境

- 源码基点：`641a34d719b2c7230c19ef5a02fe4b72fdbceeea`，其父提交为 `d31e3561`。验证时使用该基点加本目录冻结的修复补丁；本次提交记录该修复及验证证据。
- 修改范围：`scripts/ios_lock.py`、锁文档及一个针对性检查脚本；完整补丁和 SHA-256 见 [源码补丁](source-changes.patch)、[源码清单](source-manifest.json)。
- 宿主：macOS 27.0 / Darwin 27.0.0，arm64；Python 3.14.7；Xcode 27.0 / `27A266a`。
- 实际退出检查：Flutter 3.47.3 / Dart 3.13.3；iPad Pro 11-inch M5 arm64 模拟器，iOS 27.0 / `24A434`；沿用 Step 5A 的 `com.fuhua.erosfe.step5a` Debug `.app`。
- 仅验证宿主进程组退出及锁保护。未重新构建 App，未执行画廊、磁力分享或生命周期操作；未重新运行完整 5A，未执行 5B 或 Step 6。
- 生产应用源码未改动；三个依赖锁文件与基点一致；原有 5A 证据清单中的 149 个文件仍全部匹配。见 [状态核对](verification-state.json)。

## 2. 原异常与原因核实

原始记录见 [5A 锁退出异常索引](../ios-step5a-20261001/lock-exit-issue.json)：`simulator-setup`、`ipad-2`、`ipad-3` 均在 `Application finished.` 之后清理残留进程时抛出 `PermissionError / errno 1`。

macOS 的 `EPERM` 不能直接理解为进程组不存在，也不能据此认定仍有活动进程。Apple 的 [XNU `killpg1` 实现](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sig.c#L1580) 会在进程组遍历时排除僵尸进程；没有可发送信号的成员时，POSIX 调用可能返回 `EPERM`。

本次夹具创建一个受监督进程组，命令退出后让剩余活动成员收到 SIGTERM 并退出，同时由另一个受控父进程暂缓回收该成员。这样可以稳定观察到同组成员为 `Z`、`killpg(pgid, 0)` 返回 `errno 1`。旧脚本在原第 69 行退出循环内抛出同一调用栈，监督进程退出码为 1，原命令退出码 23 丢失。见 [修复前结果](before-results.json)及 [旧脚本快照](before-ios_lock.py)。

5A 未保存故障瞬间的进程组状态，无法追溯证明当时每个成员的状态。本次已用真实系统调用重现相同失败路径，并验证修复；“僵尸进程退出竞争”与旧日志一致，不能将其他活动进程的权限拒绝一并忽略。

## 3. 修复行为

1. `group_exists` 遇到 `PermissionError` 后，用 `/bin/ps -axo pgid=,stat=` 检查指定进程组。
2. 仅在快照读取成功且确认无活动成员时结束清理；僵尸进程已退出，不能访问 Pods，其回收仍由父进程或系统完成。
3. 有活动成员、快照为空、格式异常、读取失败或超时时，继续持锁并输出诊断，避免在状态未知时提前释放。
4. 发送 TERM／KILL 时处理同一权限／退出竞争。如果仍有活动成员，保留等待，不让未捕获的异常终止监督进程。

锁路径、嵌套描述符复用、TERM 到 KILL 的两秒宽限和命令退出码传递保持原有约定。遇到真正不可发送信号的活动进程，监督进程会持锁等待其退出；需要检查诊断中的进程组和权限，不能删除锁文件绕过等待。

## 4. 针对性结果

检查入口：[tool/ios_lock_exit_check.py](../../tool/ios_lock_exit_check.py)。真实进程检查使用临时 checkout，主动创建和回收自己的夹具进程；不会操作当前 checkout 的 Pods。夹具父进程退出受监督组仅用于稳定保留僵尸状态，不表示生产包装器支持脱离会话的后台构建服务。

| 检查 | 修复前 | 修复后 | 证据／断言 |
| --- | --- | --- | --- |
| 命令完成 → TERM 残留成员 → 僵尸组 EPERM | **重现异常，退出 1** | **PASS，退出 23** | 同一失败路径；原命令退出码保留 |
| 残留成员忽略 TERM → 两秒后 KILL → 僵尸组 EPERM | 未执行 | **PASS，退出 23** | 活动成员存在时竞争命令退出 75；清理后退出 0 |
| 监督进程收到 TERM → 残留成员清理 → 僵尸组 EPERM | 未执行 | **PASS，退出 143** | 信号退出码保留；清理期间拒绝下一任务 |
| 僵尸成员 `Z` / `Z+`，无活动成员 | — | **PASS** | `group_exists = false`；发送信号的退出竞争不抛异常 |
| 活动成员与僵尸成员并存 | — | **PASS** | `group_exists = true`，继续等待 |
| 快照中目标组已消失 | — | **PASS** | `group_exists = false` |
| 快照为空、格式异常、权限拒绝、超时、命令失败 | — | **PASS，5 项** | 状态未知时均按需继续等待处理 |

修复后的检查共 **11 项 PASS**，见 [完整结果](after-results.json)。前三项使用真实进程、信号、内核锁和系统返回码；其余八项使用受控快照／权限故障注入，验证不能提前结束清理的分支。真实清理期间的锁竞争断言只覆盖本次退出路径，不能替代整个开发链路的并发验收。

## 5. 实际 Flutter 退出检查

执行命令：

```bash
scripts/ios_dev.sh run --debug \
  -d E3B49F40-CB5C-4CDC-A04D-35E0284103A8 \
  -t tool/ios_baseline_probe.dart \
  --use-application-binary=build/ios/iphonesimulator/fehviewer.app
```

连接 Debug VM 后输入 `q`。Flutter 输出 `Application finished.`，包装器执行剩余子进程清理，最终退出码 **0**；监督进程退出，所记录的进程组无剩余成员；随后当前 checkout 的 `--no-wait` 命令重新取得锁并退出 **0**。见 [退出结果和日志摘录](flutter-simulator-exit-result.json)、[退出前进程组](flutter-simulator-processes-before.json)。

这次实际退出没有触发 EPERM，因此该分支的验证依据是第 4 节修复前失败、修复后通过的真实进程复现。App 启动仍记录既有 `Download` 目录异常，这与宿主锁退出断言分别记录，不表示应用 Bug 已修复。未重新测试真机业务流程。

## 6. 文件索引与复跑

| 文件 | 用途 |
| --- | --- |
| [before-ios_lock.py](before-ios_lock.py)、[before-results.json](before-results.json) | 旧脚本和同栈失败证据 |
| [after-results.json](after-results.json) | 11 项修复后结果，包含真实进程 PID、退出码、stderr 和锁竞争结果 |
| [flutter-simulator-exit-result.json](flutter-simulator-exit-result.json) | 实际 Flutter q 退出及锁重新获取 |
| [verification-state.json](verification-state.json) | 宿主工具链、脚本哈希、依赖锁和旧 5A 证据完整性 |
| [source-manifest.json](source-manifest.json)、[source-changes.patch](source-changes.patch) | 当前修复源码及完整补丁 |
| [evidence-sha256.json](evidence-sha256.json) | 本目录证据 SHA-256；不包含清单自身 |

沿用仓库忽略规则，`before-check.log`、`after-check.log`、`simulator-boot.log`、`flutter-simulator-q.log` 原始日志保留本地；可提交的 JSON 已保存失败调用栈、清理消息和关键退出结果。

```bash
# 重现旧脚本失败路径
python3 tool/ios_lock_exit_check.py \
  --lock-script artifacts/ios-lock-exit-20261002/before-ios_lock.py \
  --expect-regression --output /private/tmp/ios-lock-exit-before.json

# 验证当前修复
python3 tool/ios_lock_exit_check.py \
  --lock-script scripts/ios_lock.py \
  --output /private/tmp/ios-lock-exit-after.json
```

本次只处理锁退出异常。原有 5A 证据保持冻结，分享缺陷及其他应用问题继续由后续步骤处理。
