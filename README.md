# Peashooter File Cleaner · 豌豆射手文件清理器

原生 macOS 桌面动画工具的源码原型，使用 **Swift、AppKit、SpriteKit 和 Finder Sync Extension**。在 Finder 或桌面上右键一个普通文件，选择「召唤豌豆射手」，通过两次独立确认后，以动画形式将文件移入系统废纸篓。

**本仓库是源码分享版，不包含第三方游戏图片、应用图标、音效、原始素材包或编译好的应用。** 完整构建前需要自行准备有权使用的资源，见 [素材准备说明](Resources/ASSET_SOURCES.md)。

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

无需下载第三方 Swift 包。未准备素材时，可先检查公开目录和 Xcode 工程结构：

```bash
ruby Scripts/check_public_snapshot.rb
./Scripts/verify_project.sh --source-only
```

`--source-only` 检查源码、脚本、plist 和工程结构，不表示应用已经具备完整的美术、音频或运行体验。

## 准备资源、构建与安装

1. 按 [资源规范](Resources/ASSET_SOURCES.md) 准备自己有权使用的 PNG、WAV 和 `AppIcon.icns`，放入说明中的本地位置。
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

未选择额外的源码开源许可证，也未提供第三方素材的公开授权。面向普通用户发布应用前，还需要解决美术和音频许可、签名与公证以及目标 macOS 系统实测问题。
