# Peashooter File Cleaner · 豌豆射手文件清理器

原生 macOS 桌面动画工具，使用 **Swift、AppKit、SpriteKit 和 Finder Sync Extension**。在 Finder 或桌面上右键一个普通文件，选择「召唤豌豆射手」，通过两次独立确认后，以动画形式将文件移入系统废纸篓。

## 普通用户：下载安装

到 **[Releases 下载 Mac 安装包](https://github.com/LKC0918/peashooter-file-cleaner/releases)**，下载文件名以 `universal.dmg` 结尾的安装盘，不要选择 GitHub 自动生成的 `Source code` 源码包。支持 macOS 13+，包含 Apple Silicon 和 Intel 架构，不需要 Xcode、终端或开发者账户。

打开 DMG → 把应用拖到 Applications → 从“应用程序”启动 → 先播放安全演示 → 点击“设置 Finder 右键菜单…”按说明启用扩展和权限。详细图文排版的[安装与使用说明](Resources/UserGuide.html)也在安装盘和应用内提供，可离线阅读。

**当前发布的是未经 Apple 公证的匿名本地签名测试版。** 首次打开可能需要系统设置“隐私与安全性”中的“仍要打开”；若系统报告恶意、损坏或没有允许入口，停止操作，不要关闭 Gatekeeper、SIP 或绕过隔离保护。不能承诺在所有 Mac 上无提示打开。正式的默认安全设置下分发需要 Developer ID 签名与 Apple 公证；签名开发者名称通常是公开信息。参见 [Apple 的公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)和[安全打开应用说明](https://support.apple.com/102445)。

发布者已确认本版本运行素材的再分发授权；仓库仅包含经过元数据清理的必要运行资源，不含原始 Scratch 归档。相关素材不因公开下载而转授进一步使用权，见 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 功能设计

- Finder Sync 右键召唤，附 Finder Quick Action 和 macOS Services 兼容入口。
- 射手从目标显示器左侧进入，绿色对话气泡完成两次确认。
- 前四次命中在真实文件图标上叠加裂纹和粒子，不显示第二个文件图标。
- 第五颗弹丸抵达目标后调用 `FileManager.trashItem`；仅在操作成功后播放最终碎裂。
- 两个角色抬着独立担架，将射手带离屏幕。
- 安全演示模式不操作真实文件；应用可驻留菜单栏等待下次召唤。

尺寸与位置关系集中在 `ExperienceLayout`。射手为 68×68 点，抬担架角色约 96 点高，担架为 190×45 点。

## 环境与源码检查

需要 macOS 13+ 和完整 Xcode。先打开 Xcode 完成组件安装，并确认：

```bash
xcode-select -p
xcodebuild -version
```

无需下载第三方 Swift 包。可先检查公开目录和 Xcode 工程结构：

```bash
ruby Scripts/check_public_snapshot.rb
./Scripts/verify_project.sh --source-only
```

`--source-only` 只检查源码、脚本、plist 和工程结构；完整资源检查请直接运行 `./Scripts/verify_project.sh`。

## 准备资源、构建与安装

1. 本版本已提供经清理的运行资源；如替换美术，请按 [资源规范](Resources/ASSET_SOURCES.md) 准备自己有权使用的 PNG、WAV 和 `AppIcon.icns`。
2. 执行完整检查和构建：

   ```bash
   ./Scripts/verify_project.sh
   ./Scripts/build_local.sh
   ```

3. 安装当前用户的应用和 Finder 命令：

   ```bash
   ./Scripts/install_local.sh
   ```

构建产物位于 `Build/DerivedData/Build/Products/Debug/Peashooter File Cleaner.app`。安装脚本将应用放入 `~/Applications`，将快捷操作放入 `~/Library/Services`，退出已运行的本应用并重启 Finder 以刷新菜单。

本地调试可以使用本地签名。选择自己的开发团队时，主应用和扩展应使用同一团队；若修改 Bundle ID，也应同步调整安装脚本中的扩展标识。

## 使用与系统权限

运行后菜单栏出现叶子图标。对桌面、文稿或下载目录内的单个普通文件右键，选择「召唤豌豆射手」。双击应用或使用菜单栏打开控制面板，可先播放安全演示。

程序优先通过辅助功能读取 Finder 图标的 `AXImage` 范围。桌面文件可回退到 Finder Apple Event 提供的唯一选中项 `desktop position`；文件路径必须与请求完全一致，且坐标必须处于连接的屏幕内。还可使用扩展创建右键菜单时记录的坐标，或后台应用近期记录的 Finder 原始右键坐标。程序拒绝使用点击菜单项后的位置。

辅助功能可在「系统设置 → 隐私与安全性 → 辅助功能」配置；首次请求 Finder 桌面位置时，系统也可能询问是否允许控制 Finder。临时签名在重新构建后可能需要重新授权。Finder 不调用扩展菜单回调的系统版本上，由 Quick Action 提供兼容入口。

## 文件操作边界

- 仅接受用户主目录内单个普通文件。文件夹、应用、符号链接、系统目录以及用户 Library、Applications、废纸篓内的文件会被拒绝。
- 两次确认前不修改目标文件，生产代码仅用 `FileManager.trashItem` 移入废纸篓。
- 执行前在文件协调操作内重做安全校验，并比较设备号和 inode；确认期间被替换的文件会被拒绝。
- 废纸篓操作失败时不播放最终碎裂。Finder 图标刷新和渲染的实际时序仍需在目标系统上手动验收。
- 应用不读取或记录文件内容；仓库不包含运行日志或用户文件样本。

## 自动化与手动验证

准备本地资源后，可运行全部 XCTest：

```bash
xcodebuild test \
  -project PeashooterFileCleaner.xcodeproj \
  -scheme "Peashooter File Cleaner" \
  -destination 'platform=macOS' \
  -derivedDataPath "${TMPDIR%/}/PeashooterFileCleaner-tests"
```

测试涵盖状态机、双重确认、文件类型与身份校验、URL 请求、桌面定位回退、隐藏图标和动画组合。废纸篓集成测试只操作程序自己创建的临时文件，不使用现有用户文件、不清空废纸篓。源码检查通过不等于 Finder 菜单、系统授权、多显示器和完整动画体验已获验证。

## 目录

```text
App/                         主应用、菜单栏与召唤协调
Animation/                   透明窗口、确认面板、SpriteKit 动画和定位
Core/                        状态机、请求、文件校验和废纸篓服务
FinderExtension/             Finder Sync 扩展
QuickAction/                 Finder 快捷操作兼容入口
Resources/                   plist、资源规范与本地素材占位目录
Scripts/                     隐私检查、源码检查、构建与安装
Tests/                       XCTest
PeashooterFileCleaner.xcodeproj/
ARCHITECTURE.md               通信、状态机与安全设计
THIRD_PARTY_NOTICES.md        第三方资源说明
```

## 发布与隐私

源码公开目录通过明确的文件类型白名单整理，不包含私人文件、截图、账户凭据、机器日志、助手配置、Xcode 个人设置、原工作目录的 Git 历史或历史备份包。测试路径仅为合成示例。提交应使用 GitHub 隐藏邮箱，避免把个人邮箱写入公开元数据。

未选择额外的源码开源许可证。第三方素材的再使用需另行取得权利，不应从仓库可见性推断。测试版打包使用 `./Scripts/package_release.sh --unsigned-beta --authorized-assets`；输出只包含经过白名单审核的应用、离线说明和第三方说明，不包含构建日志、调试符号、私人路径或签名证书。发布流程与限制见 [发布说明](docs/RELEASE_NOTES.md)。

GitHub Actions 在 `Distribution/version.txt` 更新或手动触发后执行隐私检查、XCTest、通用构建和安装盘检查，再使用仅限当前仓库的临时令牌发布预发布版本。它不需要个人 Apple ID、证书私钥或长期 GitHub 令牌；不会上传原始构建日志、测试结果包或本机文件。该流程通过不等于所有 macOS 硬件上的 Finder 和 Gatekeeper 实测通过。
