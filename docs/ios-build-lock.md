# iOS 真机／模拟器构建互斥与 review 索引

本次在同一 checkout 内采用全过程串行化：准备、Pods 安装、构建和整个 Flutter run 会话共用根目录的 `.ios-development.lock`。真机和模拟器使用同一把锁，不按 SDK 分锁。

ML Kit 0.12.0 的 helper 会在每次构建时根据目标 SDK 修改 Pods 二进制的平台标记，因此锁必须覆盖从修改到链接结束的整个过程。依据：[插件维护者说明](https://pub.dev/packages/google_mlkit_commons/versions/0.12.0)。

## 文件索引

| 文件入口 | 更改与 review 重点 |
| --- | --- |
| [scripts/ios_lock.py](../scripts/ios_lock.py) | checkout 级锁路径；使用 Python 标准库 `fcntl.flock`，无需新增包。 |
| [嵌套会话校验](../scripts/ios_lock.py) | 嵌套调用通过 UNIX socket 向活跃监督进程校验 checkout 和随机令牌，复用同一会话。 |
| [进程组清理](../scripts/ios_lock.py) | 外层命令结束后先清理同一进程组的残留子进程，再释放锁，避免链接进程仍在读取 Pods。 |
| [监督与解锁](../scripts/ios_lock.py) | 获取锁、等待／拒绝、转发中断信号、监督命令生命周期、关闭锁描述符。 |
| [scripts/ios_common.sh:6](../scripts/ios_common.sh) | 共用入口保护，在配置／依赖／构建修改前重新执行受锁保护的脚本。 |
| [scripts/ios_common.sh:24](../scripts/ios_common.sh) | 抽取原准备脚本的 Flutter 查找逻辑，继续要求 3.47.3。 |
| [scripts/ios_dev.sh:23](../scripts/ios_dev.sh) | 新的 prepare／pods／build／run 入口；build 与 run 使用 `bundle exec`，整个 run 会话持锁。 |
| [scripts/ios_prepare.sh:6](../scripts/ios_prepare.sh) | 原准备入口直接接入同一把锁，覆盖本地配置、依赖解析、代码生成和 Pods 安装。 |
| [scripts/build_ipa.sh:4](../scripts/build_ipa.sh) | 接入同一把锁，覆盖 Pods 安装、IPA 构建及后续打包。 |
| [scripts/build_ipa_.sh:4](../scripts/build_ipa_.sh) | 同上。 |
| [scripts/fvm_ipa.sh:4](../scripts/fvm_ipa.sh) | 同上，并覆盖其 pub get。 |
| [scripts/fvm_ipa_nosign.sh:4](../scripts/fvm_ipa_nosign.sh) | 同上，并覆盖未签名构建和产物处理。 |
| [.gitignore](../.gitignore) | 忽略本地持久锁文件。 |
| [本文：使用方式](#使用方式) | 开发命令、保护边界、独立 worktree 并行约定与检查记录。 |

## 使用方式

以下命令在仓库根目录执行。首次准备沿用第二步的公开配置和本地签名设置；build／run 不自动重新执行准备。

```bash
# 模拟器准备和构建
scripts/ios_dev.sh prepare --simulator
scripts/ios_dev.sh build ios --simulator --debug

# 真机准备；未签名 Debug 构建可先检查编译
scripts/ios_dev.sh prepare --device
scripts/ios_dev.sh build ios --debug --no-codesign

# 运行；把 IOS_DEVICE_ID 设置为目标真机或模拟器的 UDID
scripts/ios_dev.sh run -d "$IOS_DEVICE_ID"

# 按既有 Podfile.lock 安装
scripts/ios_dev.sh pods

# 不等待：checkout 忙时退出 75，实际命令不会启动
IOS_LOCK_WAIT=0 scripts/ios_dev.sh build ios --simulator --debug
```

默认等待锁，输出持有者 PID 和等待提示；等待时可以按 Ctrl-C 取消。`IOS_LOCK_WAIT` 只接受 `0` 或 `1`。直接执行原 `scripts/ios_prepare.sh` 及四个 IPA 脚本也会自动获取同一把锁。

`run` 从启动 Flutter 到退出或 detach 一直持锁，热重载和重建均发生在锁内。detach 后，监督进程先处理残留的本地子进程再释放锁；设备或模拟器内的 App 可继续运行。下一个 SDK 的任务只能在释放后开始。

需要把多个命令作为一个连续操作时，可以使用通用包装器；嵌套的项目入口会复用已持有的锁：

```bash
python3 scripts/ios_lock.py -- bash -c \
  'scripts/ios_prepare.sh --simulator && scripts/ios_dev.sh run -d "$IOS_DEVICE_ID"'

# 命令行 Xcode 构建同样可以包装；额外参数按实际需求添加
python3 scripts/ios_lock.py -- xcodebuild \
  -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator build
```

通用包装器使用 `--no-wait` 选择忙时退出。普通命令退出码会传回调用方；无法启动命令时返回 `127`；收到 INT／TERM／HUP 后转发到子进程组，必要时在两秒后强制结束，最终返回 `128 + 信号编号`。

macOS 的 `killpg(pgid, 0)` 在进程组只剩僵尸进程时也可能返回 `EPERM`。锁脚本此时读取 `/bin/ps` 的进程组和状态：确认无活动成员后结束清理；仍有活动成员、检查失败或超时时继续持锁。发送 TERM／KILL 时也处理同一退出竞争，避免未捕获的 `PermissionError` 让监督进程提前结束。僵尸进程已退出，不能继续读取或修改 Pods，其回收仍由父进程或系统负责。

若看到 `Cannot verify process group` 或 `Cannot send signal`，应检查消息中的进程组和本机权限；脚本会等待确认活动成员结束后才释放锁。不要删除锁文件或直接启动另一轮构建来绕过等待。

## 锁的实现与保护边界

- 外层 Python 进程持有内核文件锁直到命令及其受监督的子进程组结束。锁描述符不传给子进程；嵌套脚本通过活跃监督进程的本地 socket 校验，避免准备入口再次获取锁造成死锁。
- 锁文件是持久文件，释放通过监督进程显式解锁并关闭描述符完成。文件中的 PID 只用于提示，不用于判断是否占用；旧 PID 不会造成陈旧锁。**不要删除锁文件来“解锁”**，删除会让不同进程锁住不同 inode。
- 子进程沿用标准输入／输出／错误；监督进程用独立进程组转发信号并处理残留子进程。该入口要求命令在受监督的进程组内完成，不用于启动脱离会话的后台构建服务。
- `flock` 是协作式保护。直接执行 `flutter`、`pod install`、未包装的 `xcodebuild`，以及 Xcode GUI 和现有 VS Code launch 配置，都不会自动获取此锁。使用这些入口时必须遵守同 checkout 串行约定，或改用完整隔离的工作目录。
- iOS release job 尚未启用。第六步新增的开发 CI 和统一入口见 [iOS 开发文档](ios-development.md)，开发 CI 不发布 App。

## 需要并行时：完整隔离

不同 worktree 的根目录和锁文件不同，可以并行，但每个工作目录必须独立准备。分别保留自己的：

- `ios/Pods`，尤其是 helper 会改写的 ML Kit 二进制；不得共用目录、符号链接或硬链接到同一个可写文件。
- `.dart_tool`、Flutter 生成配置、代码生成产物和 `ios/Flutter/Local.xcconfig`。
- DerivedData、`build` 及最终输出目录。手动指定路径时必须按工作目录区分。

下载缓存可以共享。不要将某个 worktree 已准备好的可写 Pods 目录链接给另一个 worktree。四个旧 IPA 脚本仍使用 `para.sh` 的 `$HOME/Public/fehv` 导出位置，跨 worktree 并行打包时还需独立导出位置或串行打包；本地双端开发优先使用上述 build／run 入口。

## 本地回归

在仓库根目录运行 `python3 -m unittest discover -s tool/tests -v`。用例验证锁占用、取消等待和会话退出时的清理，也检查独立进程组的控制台无法继承锁。完整的模拟器构建与冒烟使用 `scripts/ios_dev.sh ci`。
