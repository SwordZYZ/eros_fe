# 第六步：iOS 开发入口、本地验收与 review 索引

## 1. 结论与范围

本地开发入口和 CI job 已实现；真机／arm64 模拟器基础冒烟、热重载和异常退出后重新取锁已验证。最终冻结副本的完整 CI 入口结果见下方验收汇总。**远端 GitHub Actions 尚未执行，不能把本地 CI 入口通过写成远端 job 已通过。验收执行时源码尚未提交、未推送；用户随后验收通过并授权提交到主分支，提交状态以 Git 历史为准。**

本次基于 `d636c80ba5874cec570e34a958c09ae1309f6649`。临时验证仓库中的候选 commit 只用于记录源码，不属于用户仓库历史，也不是待合并提交。最终源码哈希见 [accepted-candidate.json](accepted-candidate.json)；每段命令另有日志和源码清单。

修改先解决锁 FD 继承，再固化 check / prepare / pods / build / run / smoke / logs / ci。真机操作使用命令行与既有 Debug 驱动，没有使用 computer use。原第五步失败保留，本次没有扩大到分享／遮罩／锁屏业务修复。

## 2. 环境与本地配置

| 项目 | 本次实际环境 |
| --- | --- |
| Xcode / SDK | 27.0 / build 27A266a / iOS SDK 27.0 |
| Flutter / Dart | 3.47.3 / 3.13.3，stable |
| CocoaPods | 1.16.2，Gemfile.lock + Podfile.lock；日常 deployment 安装 |
| 最低支持系统 | 15.6；与测试 runtime 27.0 分开 |
| 模拟器 | iPad Pro 11-inch (M5)，arm64 iOS 27.0 / 24A434；按 checkout 创建专用设备 |
| 真机 | iPad Pro 11-inch (M4)，iPad16,3，UDID 00008132-000278923E99001C |
| 真机系统 / 连接 | iPadOS 27.0 / 24A437，USB wired，Developer Mode enabled |
| 构建模式 | Debug |
| Bundle ID | 模拟器 com.example.erosfe.dev；真机 com.fuhua.erosfe.step6 |
| 签名 | 开发者已有本地团队；Local.xcconfig 被忽略，不提交维护者私钥 |
| 真机调试选择 | 本命令环境 FLUTTER_LLDB_DEBUGGING=true；没有改全局 Flutter 配置 |

真机详情见 [preflight-details.json](device/preflight-details.json)。公开配置首次准备不依赖 Firebase 解密或维护者私钥。最终新副本开始时没有 Pods、.dart_tool、build 和 Local.xcconfig，初始 Git 状态为空；证据在 accepted-candidate.json。首次准备创建公开本地配置，依赖按三个锁文件解析。

## 3. 必修修复：孤立 devicectl 不再占用锁

旧脚本通过环境变量和 pass_fds 传出锁 FD。真实控制台能够进入自己的 PGID，失去父进程后继续持有该 FD；只清理 Flutter 原进程组不能覆盖它。

现在只有外层监督进程持有 flock。Popen 使用 close_fds=True，不传 pass_fds；嵌套入口通过随机令牌 UNIX socket 向存活监督进程校验。监督进程结束后关闭 socket 并显式 unlock，旧环境不能绕过新锁。原 macOS zombie / EPERM 处理保留。日志包装器在主命令退出后只排空已可读的数据，不等待孤立控制台持有 stdout 管道的 EOF。

### 真实控制台的前后对比

使用已安装的独立开发 App，CLI `--start-stopped --console` 将真实 devicectl 放入独立进程组；启动包装器随后退出。此夹具验证进程孤立与 FD 继承，不冒充自然 USB 断连或业务操作。

| 版本 | 控制台父进程 / PGID | 控制台存活时有锁 FD | 下一任务（no-wait） |
| --- | --- | --- | --- |
| 旧版 | PPID 1 / PGID 86546 | 是 | 75，拒绝启动 |
| 修复版 | PPID 1 / PGID 86576 | 否 | 0，正常启动 |

完整证据：[comparison.json](real-orphan-console/comparison.json)、[旧版 FD](real-orphan-console/before/console-fds.log)、[修复版 FD](real-orphan-console/after/console-fds.log)、[可复现夹具](device-console-fixture.py)。两轮真实控制台均按其已核对的 PID 清理，未删除锁文件。

### 实际 Flutter run 的异常路径

统一入口启动 iPad Debug App，已有驱动确认 HomePage、无账号、启动无 Dart 异常；`r` 热重载成功。运行期间第二入口返回 75。随后仅对本轮 Flutter 调试客户端发送 SIGKILL，监督进程保留以完成清理，原命令记录退出 137。真实 devicectl 位于独立 PGID，lsof 确认不持有锁 FD；本轮控制台最终退出。下一次真实 check 入口在 no-wait 模式下返回 0。

证据：[断连前进程](device-run/disconnect-processes-before.json)、[断连后进程](device-run/disconnect-processes-after.json)、[真实下一任务](device-run/next-task-after-disconnect.json)、[驱动快照](device-run/snapshot-before-disconnect.json)、[lsof](device-run/lsof-before-disconnect.log)。这一轮验证不是只使用正常 q / d。

**强制结束调试客户端后新增一份 App 原生崩溃**：北京时间 2026-10-03 07:37:57，com.fuhua.erosfe.step6，EXC_BAD_ACCESS / SIGBUS，faulting thread 11 / DartWorker。它发生在本次受控强制中断之后，时间关联不足以确认根因。完整 .ips 已保留；不得把锁验收 PASS 解读为断连后 App 无崩溃。

崩溃索引：[native-crash-summary.json](device-diagnostics/native-crash-summary.json)、[完整 .ips](device-diagnostics/diagnostics-20261002T234338Z-device/fehviewer-2026-10-03-073757.ips)。正常真机冒烟另行通过，普通 lib/main.dart Debug App 在测试完成后重新安装。

## 4. 启动冒烟与必要源码修复

新增官方 integration_test 使用真实 main.dart，覆盖无账号首页、真实样式设置页面及返回，检查 Flutter 异常；不以线上账号、API 实时结果或网络可用性为通过条件。真机使用独立开发 Bundle ID 和测试数据，避免清除日常 App 数据。

首次真实冒烟发现 iOS 相对 Download 路径用于 .nomedia 时访问只读工作目录。最小修复在文件访问前将相对路径解析到 Documents，并 await 文件创建／删除；没有迁移 DB 或改变保存的相对路径。测试显式检查 marker 创建和删除。

[修复前日志](smoke-before-wrapper.log)和 [修复后日志](smoke-after-wrapper.log)保留。故意注入 IOS_SMOKE_FORCE_FAILURE 的真实模拟器测试返回 1；最终相同源码再注入失败也返回1，见 [final-injected-failure-wrapper.log](final-injected-failure-wrapper.log)。宿主 CI 编排测试另验证 smoke 的非零码完整上抛，CI 没有 continue-on-error。

## 5. 验收结果与证据

最终汇总见 [acceptance.json](acceptance.json)。本表由最终命令状态核对，历史失败没有改写。

| 验收项 | 结果 / 索引 |
| --- | --- |
| 最终全新 checkout 完整 ci | PASS0，14个宿主回归及prepare/check/build/smoke均成功，三锁不变；[accepted-ci-wrapper.log](accepted-ci-wrapper.log)、accepted-ci/ 每段清单 |
| 冻结前全新副本完整 ci | PASS0；[fresh-ci-wrapper.log](fresh-ci-wrapper.log)；其后只更新文档、import 顺序与日志目标目录处理，再做最终验收 |
| 最终真机集成冒烟 | PASS0；[device-final-smoke-wrapper.log](device-final-smoke-wrapper.log)、device-final-smoke/ |
| 两端生产入口启动 / 热重载 | PASS；simulator-run/ 与 device-run/；模拟器正常 detach0，真机受控强制断连137 单独判定 |
| 重复 deployment 安装 | PASS，两次前后三锁 SHA 不变；[lock-stability.json](repeated-pods/lock-stability.json) |
| 可写 Pods 隔离 | PASS；[pods-isolation.json](pods-isolation.json)，按实际 helper 的只读迭代器检查所选二进制与三个副本／下载缓存的 inode |
| 真实孤立控制台锁修复 | 旧版 FAIL75 → 修复版 PASS0；见第 3 节 |
| 宿主回归 | 14/14 PASS；[host-tests-final.txt](host-tests-final.txt) |
| macOS zombie / EPERM 回归 | 11/11 PASS；[lock-exit-final.json](lock-exit-final.json) |
| Dart 静态检查 | PASS，两个文件无 issue；[dart-analyze-final.txt](dart-analyze-final.txt) |
| Shell / Python / diff 检查 | PASS；[static-checks.json](static-checks.json) |
| Workflow 静态检查 | PASS；[actionlint-final.txt](actionlint-final.txt)。actionlint 1.7.12 内置表尚不识别 preview 的 xcode-27，验证配置仅补充该已核实 label；首轮诊断保留于 actionlint.txt |
| 真机日志导出 | PASS，各采集命令成功；[collection.json](device-diagnostics-fixed/diagnostics-20261002T234544Z-device/collection.json) |
| 模拟器已安装 App 日志导出 | PASS，各命令成功；[collection.json](simulator-installed-diagnostics/diagnostics-20261002T233803Z-simulator/collection.json) |
| 普通真机 App 最终恢复 | PASS，标准lib/main.dart启动与detach0；installed-app.json确认Eros-FE 1.9.2(566)已安装；device-restored/ |
| 远端 GitHub Actions | NOT_RUN；待用户确认提交／推送后首次运行 |

首次模拟器诊断发生在 integration_test 卸载测试 App 后，容器查询 exit2 如实保留；随后生产入口启动、detach 后重新采集成功。真机日志复制初次因缺少目标目录失败，修复后重跑成功，并新增空／非空日志目录的宿主回归。当前 App 日志目录可以为空，以 run / smoke 控制台为主要调试日志；采集0本身不是业务通过证明。

其他历史失败：ci-local 的早期锁校验失败未计入验收；暂停前 clean-ci 以 143 终止，未记完整 PASS；初次真机 Xcode 自动化等待过久以 143 取消，LLDB 命令环境重跑成功。原日志与清单全部保留。

## 6. CI 配置与开发入口

[开发文档](/Users/fuhua/.codex/worktrees/32af/eros_fe/docs/ios-development.md)给出新 checkout 准备、两端构建运行、Debug 驱动、日志和开发签名配置。

CI 使用 xcode-27 arm64 runner、显式 Xcode 27.0、Flutter 3.47.3 和缓存 Ruby 3.4.11；运行同一个 ci 入口。环境不匹配、代码生成失败、构建失败、测试断言失败或锁漂移都会使 job 失败。always 采集／上传原始日志、清单与可用 xcresult，保留14天。

官方 [runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)列出 Xcode 27、iOS 27 SDK 和对应模拟器；preview 镜像仍需每次严格检查实际版本和 arm64 runtime。配置存在与实际远端运行成功是不同证据，本次未发布或运行远端 job。

## 7. Review 文件索引

| 文件 / 入口 | Review 重点 |
| --- | --- |
| [scripts/ios_lock.py:27](/Users/fuhua/.codex/worktrees/32af/eros_fe/scripts/ios_lock.py:27) | 嵌套会话必须向存活监督进程校验；旧 socket / token 无法绕过锁 |
| [scripts/ios_lock.py:140](/Users/fuhua/.codex/worktrees/32af/eros_fe/scripts/ios_lock.py:140) | supervisor 独占 FD、close_fds、退出顺序；保留 zombie / EPERM 清理 |
| [scripts/ios_common.sh:6](/Users/fuhua/.codex/worktrees/32af/eros_fe/scripts/ios_common.sh:6) | 所有入口修改前复用同一个锁会话；本次仅更新说明 |
| [scripts/ios_dev.sh:26](/Users/fuhua/.codex/worktrees/32af/eros_fe/scripts/ios_dev.sh:26) | check / prepare / pods / build / run / smoke / logs / ci 全程持锁；ci失败码传播 |
| [scripts/ios_env_check.sh:20](/Users/fuhua/.codex/worktrees/32af/eros_fe/scripts/ios_env_check.sh:20) | 宿主 arm64、严格27.0 runtime及架构检查；其余基线沿用 |
| [tool/ios_evidence.py:23](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/ios_evidence.py:23) | 命令清单与源码哈希；主命令退出后不等待孤立 stdout EOF；中断记录 |
| [tool/ios_simulator.py:20](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/ios_simulator.py:20) | 按 checkout 隔离模拟器；只接受 available27.0 arm64；无版本 fallback |
| [tool/ios_logs.py:12](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/ios_logs.py:12) | 两端诊断命令有 timeout；真机目标目录创建；按 Bundle ID 留崩溃报告；部分采集失败可见 |
| [integration_test/ios_smoke_test.dart:20](/Users/fuhua/.codex/worktrees/32af/eros_fe/integration_test/ios_smoke_test.dart:20) | 真实入口、无账号导航、文件 marker 与异常断言；故意失败开关只在测试末尾 |
| [download_path_manager.dart:124](/Users/fuhua/.codex/worktrees/32af/eros_fe/lib/common/controller/download/download_path_manager.dart:124) | 本次唯一生产逻辑修复：iOS相对目录解析与await，不改变保存的路径 |
| [pubspec.yaml:217](/Users/fuhua/.codex/worktrees/32af/eros_fe/pubspec.yaml:217)、[pubspec.lock](/Users/fuhua/.codex/worktrees/32af/eros_fe/pubspec.lock) | SDK integration_test / flutter_test 及必要测试依赖成组锁定，没有业务包升级 |
| [ios/Podfile.lock:100](/Users/fuhua/.codex/worktrees/32af/eros_fe/ios/Podfile.lock:100) | integration_test pod；Gemfile.lock未改 |
| [.github/workflows/ios-development.yml:34](/Users/fuhua/.codex/worktrees/32af/eros_fe/.github/workflows/ios-development.yml:34) | 真实目标runner、同入口、always留证、无发布或私钥解密；release workflow未改 |
| [test_ios_lock.py](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/tests/test_ios_lock.py) | 等待／拒绝、嵌套、旧会话、失败退出、孤立进程、独立 checkout |
| [test_ios_evidence.py](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/tests/test_ios_evidence.py) | 失败码、缺失命令、孤立输出管道 |
| [test_ios_ci_entry.py](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/tests/test_ios_ci_entry.py) | CI完整阶段及 smoke失败使ci失败；使用临时假SDK，不碰真实Pods |
| [test_ios_logs.py](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/tests/test_ios_logs.py) | 复制前目录存在；空／非空App日志均可导出 |
| [tool/ios_lock_exit_check.py](/Users/fuhua/.codex/worktrees/32af/eros_fe/tool/ios_lock_exit_check.py) | 旧夹具仅在遗留FD环境存在时关闭它，兼容新设计；原11项验证保留 |
| [docs/ios-development.md](/Users/fuhua/.codex/worktrees/32af/eros_fe/docs/ios-development.md)、[docs/ios-build-lock.md](/Users/fuhua/.codex/worktrees/32af/eros_fe/docs/ios-build-lock.md) | 操作步骤、锁边界、完整worktree隔离、故障日志与既有失败范围 |

入口锁只保护遵守入口的操作。直接 Xcode / flutter / xcodebuild 必须串行或使用独立 checkout。需要并行时不能共享 helper 改写的 Pods 文件；不同副本各自保留生成配置、Dart状态、输出和DerivedData。下载缓存可以共享。

## 8. 保留的限制与清理

第五步的 ScrollController disposed、遮罩观察失败、物理锁屏后灰色种子按钮原生崩溃没有在本次修复；此处基础冒烟通过不能覆盖这些失败。强制调试中断后的新增原生崩溃也单独保留。

清理范围仅为本阶段暂停／续做缓存和自行建立的临时验证 checkout、临时工具及专用模拟器。验收日志、源码哈希、旧版复现脚本和 .ips 保留；两份历史 merge review 报告不动。清理结果见 [cleanup.json](cleanup.json)。本阶段 `.log` 作为验收证据随本次提交保存；普通开发日志仍由现有忽略规则排除，CI通过artifact上传原始日志。验收执行时源码尚未提交、未推送；用户随后验收通过并授权提交到主分支，提交状态以 Git 历史为准。

清理后的 Xcode resave 提示来自已删除的临时副本。已关闭该临时窗口、清理重新保存的 workspace 空壳，并打开当前完整工作区 `32af/eros_fe/ios/Runner.xcworkspace`；Runner.xcodeproj 和 Pods.xcodeproj 引用均存在，源码无额外改动。
