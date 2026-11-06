# Peashooter File Cleaner · 豌豆射手文件清理器

原生 macOS 桌面动画工具，使用 **Swift、AppKit、SpriteKit 和 Finder Sync Extension**。在 Finder 或桌面上右键一个普通文件，选择「召唤豌豆射手」，通过两次独立确认后，以动画形式将文件移入系统废纸篓。

> **重要：使用真实文件前，必须先在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Peashooter File Cleaner。** 这是本测试版准确定位 Finder 文件图标的必做配置。未开启时，可能出现「无法精确定位文件图标」并安全停止。安全演示不需要此权限，演示能播放不代表真实文件模式已就绪。

## 普通用户：下载安装

到 **[Releases 下载 Mac 安装包](https://github.com/LKC0918/peashooter-file-cleaner/releases)**，下载文件名以 `universal.dmg` 结尾的安装盘，不要选择 GitHub 自动生成的 `Source code` 源码包。支持 macOS 13+，包含 Apple Silicon 和 Intel 架构，不需要 Xcode、终端或开发者账户。

打开 DMG → 把应用拖到 Applications → 从“应用程序”启动 → 先播放安全演示 → **开启辅助功能权限** → 点击“设置 Finder 右键菜单…”启用扩展 → 只用不含私人内容的临时文件试用。详细图文排版的[安装与使用说明](Resources/UserGuide.html)也在安装盘和应用内提供，可离线阅读。

**当前发布的是未经 Apple 公证的匿名本地签名测试版。** 首次打开可能需要系统设置“隐私与安全性”中的“仍要打开”；若系统报告恶意、损坏或没有允许入口，停止操作，不要关闭 Gatekeeper、SIP 或绕过隔离保护。不能承诺在所有 Mac 上无提示打开。正式的默认安全设置下分发需要 Developer ID 签名与 Apple 公证；签名开发者名称通常是公开信息。参见 [Apple 的公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)和[安全打开应用说明](https://support.apple.com/102445)。

发布者已确认本版本运行素材的再分发授权；仓库仅包含经过元数据清理的必要运行资源，不含原始 Scratch 归档。相关素材不因公开下载而转授进一步使用权，见 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 首次使用：开启辅助功能权限

1. 先把应用安装到“应用程序”并启动一次，不要一直从 DMG 中运行。
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**。
3. 找到 **Peashooter File Cleaner**，打开它旁边的开关。系统要求验证身份时，由你自行完成。
4. 列表中没有应用时，点击 **＋**，选择“应用程序”中的 `Peashooter File Cleaner.app` 并添加，再开启开关；若安装在当前用户的“应用程序”目录，请选择实际安装的那一份。
5. 确认授权的是**当前安装版本**；更新、移动应用或重新构建后可能需要重新授权。系统提示退出并重新打开时按提示处理，然后重新右键召唤。

辅助功能权限用于读取 Finder 界面中图标的范围，才能把弹丸、裂纹和碎片对准目标。此权限本身允许应用读取和控制界面，请只对你信任的应用开启；本应用不因此获得上传私人文件的许可，也不要求你关闭 Gatekeeper、SIP 或无条件授予完全磁盘访问。

**辅助功能权限与 Finder 扩展开关是两件事，都要检查。** 开启辅助功能不会自动启用右键菜单；请在本应用的“设置 Finder 右键菜单…”中查看扩展与兼容入口说明。若出现「无法精确定位文件图标」，先核对辅助功能授权、当前只选中一个普通文件，以及是否正在运行正确的应用副本。仍失败时停止真实文件测试并反馈，不要用重要文件反复尝试。系统另外询问是否允许控制 Finder 或访问所选文件所在目录时，也需要你按实际需求手动决定。

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

请先按上面的必做步骤开启辅助功能，再使用真实文件。桌面位置、原始右键坐标等回退路径仅作为兼容措施，不保证在每种 Finder 视图和系统版本中都可用，不能替代正常授权。临时签名在重新构建后可能需要重新授权。Finder 不调用扩展菜单回调的系统版本上，由 Quick Action 提供兼容入口。

## 文件操作边界

- 仅接受用户主目录内单个普通文件。文件夹、应用、符号链接、系统目录以及用户 Library、Applications、废纸篓内的文件会被拒绝。
- 两次确认前不修改目标文件，生产代码仅用 `FileManager.trashItem` 移入废纸篓。
- 执行前在文件协调操作内重做安全校验，并比较设备号和 inode；确认期间被替换的文件会被拒绝。
- 废纸篓操作失败时不播放最终碎裂。Finder 图标刷新和渲染的实际时序仍需在目标系统上手动验收。
- 应用不读取或记录文件内容；仓库不包含运行日志或用户文件样本。

## 自动化与手动验证

当前测试版已实机检查安装、启动，以及演示模式的两层确认、快速双击阻断、“再想想”返回和取消。真实文件入口在缺少定位权限时显示错误并停止；本轮仅使用程序新建的临时文件，检查其内容校验值和文件身份保持不变。**真实文件从右键召唤到移入废纸篓、最终碎裂与担架退场的完整端到端验收仍待完成，不标为全部实测通过。** 同名顶层菜单可见不等于所有入口都已正常工作；菜单点击无响应时，需要继续核对 Finder 扩展和兼容入口，不能仅靠授予辅助功能就认定问题已经解决。

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
