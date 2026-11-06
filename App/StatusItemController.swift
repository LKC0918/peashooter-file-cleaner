import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private var controlPanelController: NSWindowController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "leaf.fill",
                accessibilityDescription: "豌豆射手文件清理器"
            )
            button.toolTip = "Peashooter File Cleaner"
        }

        let menu = NSMenu()
        let controlItem = NSMenuItem(
            title: "打开控制面板",
            action: #selector(openControlPanel),
            keyEquivalent: "o"
        )
        controlItem.target = self
        menu.addItem(controlItem)

        let demoItem = NSMenuItem(title: "播放安全演示", action: #selector(playDemo), keyEquivalent: "d")
        demoItem.target = self
        menu.addItem(demoItem)

        let setupItem = NSMenuItem(title: "设置 Finder 右键菜单…", action: #selector(setUpFinder), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let guideItem = NSMenuItem(title: "安装与使用说明", action: #selector(openUserGuide), keyEquivalent: "?")
        guideItem.target = self
        menu.addItem(guideItem)

        let safetyItem = NSMenuItem(title: "安全说明", action: #selector(showSafety), keyEquivalent: "")
        safetyItem.target = self
        menu.addItem(safetyItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func showControlPanel() {
        let controller: NSWindowController
        if let controlPanelController {
            controller = controlPanelController
        } else {
            controller = makeControlPanelController()
            controlPanelController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        AppLogger.lifecycle.notice("Launch control panel is visible")
    }

    func hideControlPanel() {
        controlPanelController?.window?.orderOut(nil)
    }

    @objc private func openControlPanel() {
        showControlPanel()
    }

    @objc private func playDemo() {
        let screenFrame = controlPanelController?.window?.screen?.frame
            ?? NSScreen.main?.frame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        controlPanelController?.window?.orderOut(nil)
        coordinator.startDemo(at: CGPoint(x: screenFrame.midX, y: screenFrame.midY))
    }

    @objc private func showSafety() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "安全说明"
        alert.informativeText = "真实文件必须经过两次确认。应用只调用 macOS 的移入废纸篓接口，不提供永久删除功能。演示模式不会操作任何真实文件。"
        alert.addButton(withTitle: "知道了")
        if let window = controlPanelController?.window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func closeControlPanel() {
        hideControlPanel()
    }

    @objc private func openUserGuide() {
        guard let guide = Bundle.main.url(forResource: "UserGuide", withExtension: "html") else { return }
        NSWorkspace.shared.open(guide)
    }

    @objc private func setUpFinder() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "设置 Finder 右键菜单"
        alert.informativeText = "请在系统设置的扩展管理中启用 Peashooter 的 Finder 扩展。不同 macOS 的位置可能是“通用 → 登录项与扩展 → Finder”，或“隐私与安全性 → 扩展”。\n\n也可安装兼容快捷操作，入口可能位于右键菜单的“快速操作”或“服务”中。只添加本应用的快捷操作，不会自动修改系统权限；已有同名操作不会被覆盖。"
        alert.addButton(withTitle: "安装兼容入口")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                let services = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Services", isDirectory: true)
                let result = try FinderIntegrationInstaller.install(
                    from: Bundle.main.url(forResource: "召唤豌豆射手", withExtension: "workflow"),
                    into: services
                )
                NSUpdateDynamicServices()
                let done = NSAlert()
                done.messageText = result == .installed ? "兼容入口已安装" : "已有同名兼容入口，已保留原文件"
                done.informativeText = "在 Finder 中右键一个普通文件，检查“召唤豌豆射手”、 “快速操作”或“服务”。若尚未出现，请在系统设置中启用对应快捷操作，或重新打开 Finder。辅助功能和控制 Finder 的权限仍需由你手动允许，详见使用说明。"
                done.addButton(withTitle: "知道了")
                done.runModal()
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "未能安装兼容入口"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.addButton(withTitle: "知道了")
                errorAlert.runModal()
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        default:
            break
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeControlPanelController() -> NSWindowController {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Peashooter File Cleaner"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = NSView()
        panel.contentView = contentView

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 76),
            iconView.heightAnchor.constraint(equalToConstant: 76)
        ])

        let titleLabel = NSTextField(labelWithString: "豌豆射手已就位")
        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.alignment = .center

        let statusLabel = NSTextField(labelWithString: "● 已启动，正在后台等待 Finder 召唤")
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .systemGreen
        statusLabel.alignment = .center

        let instructionLabel = NSTextField(
            wrappingLabelWithString: "在 Finder 或桌面中右键点击一个普通文件，选择“召唤豌豆射手”。\n也可以先播放安全演示，演示不会操作任何真实文件。"
        )
        instructionLabel.font = .systemFont(ofSize: 14)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.maximumNumberOfLines = 3

        let demoButton = NSButton(title: "播放安全演示", target: self, action: #selector(playDemo))
        demoButton.bezelStyle = .rounded
        demoButton.controlSize = .large
        demoButton.keyEquivalent = "\r"

        let safetyButton = NSButton(title: "查看安全说明", target: self, action: #selector(showSafety))
        safetyButton.bezelStyle = .rounded
        safetyButton.controlSize = .large

        let closeButton = NSButton(
            title: "关闭面板，保持后台运行",
            target: self,
            action: #selector(closeControlPanel)
        )
        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .large

        let setupButton = NSButton(title: "设置 Finder 右键菜单…", target: self, action: #selector(setUpFinder))
        setupButton.bezelStyle = .rounded
        let guideButton = NSButton(title: "安装与使用说明", target: self, action: #selector(openUserGuide))
        guideButton.bezelStyle = .rounded
        let setupStack = NSStackView(views: [setupButton, guideButton])
        setupStack.orientation = .horizontal
        setupStack.spacing = 12

        let buttonStack = NSStackView(views: [demoButton, safetyButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 12

        let rootStack = NSStackView(views: [
            iconView,
            titleLabel,
            statusLabel,
            instructionLabel,
            buttonStack,
            setupStack,
            closeButton
        ])
        rootStack.orientation = .vertical
        rootStack.alignment = .centerX
        rootStack.spacing = 11
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            rootStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
            rootStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            rootStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            instructionLabel.widthAnchor.constraint(equalToConstant: 420),
            demoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            safetyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 130)
        ])

        return NSWindowController(window: panel)
    }
}

enum FinderIntegrationInstaller {
    enum Result { case installed, alreadyInstalled }
    enum InstallError: LocalizedError {
        case missingResource
        var errorDescription: String? { "安装包中没有找到完整的 Finder 快捷操作，请重新下载应用。" }
    }

    static func install(from source: URL?, into servicesDirectory: URL) throws -> Result {
        let manager = FileManager.default
        guard let source, source.pathExtension == "workflow",
              manager.fileExists(atPath: source.appendingPathComponent("Contents/Resources/document.wflow").path)
        else { throw InstallError.missingResource }
        let destination = servicesDirectory.appendingPathComponent("召唤豌豆射手.workflow", isDirectory: true)
        if manager.fileExists(atPath: destination.path) { return .alreadyInstalled }
        try manager.createDirectory(at: servicesDirectory, withIntermediateDirectories: true)
        try manager.copyItem(at: source, to: destination)
        return .installed
    }
}
