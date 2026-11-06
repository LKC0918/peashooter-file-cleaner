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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeControlPanelController() -> NSWindowController {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 330),
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
