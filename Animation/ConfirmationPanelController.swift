import AppKit

private final class InteractivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BubbleBackgroundView: NSView {
    var tailTipX: CGFloat = 90 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bodyRect = NSRect(
            x: 6,
            y: 22,
            width: bounds.width - 12,
            height: bounds.height - 28
        )
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 18, yRadius: 18)
        let fillColor = NSColor(calibratedRed: 0.87, green: 0.96, blue: 0.79, alpha: 0.98)
        let borderColor = NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.19, alpha: 1)
        fillColor.setFill()
        body.fill()

        borderColor.setStroke()
        body.lineWidth = 3.5
        body.stroke()

        // Paint the tail after the body so it reads as one speech bubble and
        // covers the small section of bottom border underneath it.
        let safeTailX = min(max(tailTipX, bodyRect.minX + 34), bodyRect.maxX - 34)
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: safeTailX - 16, y: bodyRect.minY + 2))
        tail.line(to: CGPoint(x: safeTailX, y: 5))
        tail.line(to: CGPoint(x: safeTailX + 16, y: bodyRect.minY + 2))
        tail.close()
        fillColor.setFill()
        tail.fill()

        let tailOutline = NSBezierPath()
        tailOutline.move(to: CGPoint(x: safeTailX - 16, y: bodyRect.minY + 1))
        tailOutline.line(to: CGPoint(x: safeTailX, y: 5))
        tailOutline.line(to: CGPoint(x: safeTailX + 16, y: bodyRect.minY + 1))
        borderColor.setStroke()
        tailOutline.lineWidth = 3.5
        tailOutline.lineCapStyle = .round
        tailOutline.lineJoinStyle = .round
        tailOutline.stroke()
    }
}

/// A generic document illustration that fills the dialogue's visual column
/// without duplicating the selected Finder icon.
private final class DocumentIllustrationView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 76, height: 96)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let documentRect = bounds.insetBy(dx: 8, dy: 5)
        let fold: CGFloat = 15
        let paper = NSBezierPath()
        paper.move(to: CGPoint(x: documentRect.minX, y: documentRect.minY))
        paper.line(to: CGPoint(x: documentRect.maxX, y: documentRect.minY))
        paper.line(to: CGPoint(x: documentRect.maxX, y: documentRect.maxY - fold))
        paper.line(to: CGPoint(x: documentRect.maxX - fold, y: documentRect.maxY))
        paper.line(to: CGPoint(x: documentRect.minX, y: documentRect.maxY))
        paper.close()

        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.22)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.90, alpha: 1).setFill()
        paper.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedRed: 0.23, green: 0.48, blue: 0.13, alpha: 1).setStroke()
        paper.lineWidth = 2.5
        paper.stroke()

        let foldedCorner = NSBezierPath()
        foldedCorner.move(to: CGPoint(x: documentRect.maxX - fold, y: documentRect.maxY))
        foldedCorner.line(to: CGPoint(x: documentRect.maxX - fold, y: documentRect.maxY - fold))
        foldedCorner.line(to: CGPoint(x: documentRect.maxX, y: documentRect.maxY - fold))
        foldedCorner.close()
        NSColor(calibratedRed: 0.72, green: 0.88, blue: 0.48, alpha: 1).setFill()
        foldedCorner.fill()
        NSColor(calibratedRed: 0.23, green: 0.48, blue: 0.13, alpha: 1).setStroke()
        foldedCorner.lineWidth = 1.8
        foldedCorner.stroke()

        NSColor(calibratedRed: 0.48, green: 0.65, blue: 0.28, alpha: 0.78).setStroke()
        for lineIndex in 0..<3 {
            let y = documentRect.midY + 7 - CGFloat(lineIndex) * 12
            let line = NSBezierPath()
            line.move(to: CGPoint(x: documentRect.minX + 10, y: y))
            line.line(to: CGPoint(x: documentRect.maxX - (lineIndex == 2 ? 20 : 10), y: y))
            line.lineWidth = 3
            line.lineCapStyle = .round
            line.stroke()
        }
    }
}

@MainActor
final class ConfirmationInputGate {
    enum Phase: Equatable {
        case first
        case final
    }

    private(set) var phase: Phase = .first
    private(set) var primaryEnabled = true
    private(set) var secondaryEnabled = true
    private var generation = 0

    func presentFirst() {
        generation += 1
        phase = .first
        primaryEnabled = true
        secondaryEnabled = true
    }

    func presentFinal(armAfter delay: TimeInterval, onArmed: @escaping () -> Void) {
        generation += 1
        let expectedGeneration = generation
        phase = .final
        primaryEnabled = false
        secondaryEnabled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.phase == .final,
                  self.secondaryEnabled
            else {
                return
            }
            self.primaryEnabled = true
            onArmed()
        }
    }

    func consumePrimary() -> Phase? {
        guard primaryEnabled, secondaryEnabled else { return nil }
        primaryEnabled = false
        secondaryEnabled = false
        generation += 1
        return phase
    }

    func consumeSecondary() -> Phase? {
        guard secondaryEnabled else { return nil }
        primaryEnabled = false
        secondaryEnabled = false
        generation += 1
        return phase
    }

    func dismiss() {
        generation += 1
        primaryEnabled = false
        secondaryEnabled = false
    }
}

@MainActor
final class ConfirmationPanelController: NSObject {
    private let panel: InteractivePanel
    private let backgroundView = BubbleBackgroundView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let documentIllustrationView = DocumentIllustrationView()
    private let secondaryButton = NSButton()
    private let primaryButton = NSButton()
    private let inputGate = ConfirmationInputGate()

    var isFilePreviewVisible: Bool {
        false
    }

    var isDocumentIllustrationVisible: Bool {
        !documentIllustrationView.isHidden
    }

    var confirmationPanelSize: CGSize {
        panel.frame.size
    }

    var onCancel: (() -> Void)?
    var onFirstConfirm: (() -> Void)?
    var onBack: (() -> Void)?
    var onFinalConfirm: (() -> Void)?

    override init() {
        panel = InteractivePanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureContent()
    }

    func showFirst(
        file: ValidatedFile?,
        anchorGlobal: CGPoint,
        on screen: NSScreen
    ) {
        inputGate.presentFirst()
        titleLabel.stringValue = "就决定是它了吗？"
        detailLabel.stringValue = metadataText(for: file)
        secondaryButton.title = "取消"
        primaryButton.title = "确认是它"
        primaryButton.bezelColor = NSColor(calibratedRed: 0.14, green: 0.62, blue: 0.25, alpha: 1)
        refreshButtonState()
        positionPanel(anchorGlobal: anchorGlobal, screen: screen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showFinal(
        file: ValidatedFile?,
        anchorGlobal: CGPoint,
        on screen: NSScreen
    ) {
        titleLabel.stringValue = "真的要让它从桌面消失吗？"
        detailLabel.stringValue = metadataText(for: file)
        secondaryButton.title = "再想想"
        primaryButton.title = "我无比确认，开火！"
        primaryButton.bezelColor = NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.18, alpha: 1)
        // A fresh final confirmation must survive the mouse-up/double-click
        // sequence that activated the first confirmation. Deliberately arm it
        // after that sequence has expired so two rapid inputs cannot collapse
        // the safety boundary.
        inputGate.presentFinal(armAfter: 0.5) { [weak self] in
            self?.refreshButtonState()
        }
        refreshButtonState()
        positionPanel(anchorGlobal: anchorGlobal, screen: screen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        inputGate.dismiss()
        refreshButtonState()
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    private func configureContent() {
        backgroundView.frame = panel.contentView?.bounds ?? .zero
        backgroundView.autoresizingMask = [.width, .height]
        panel.contentView = backgroundView

        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.10, alpha: 1)
        titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        detailLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        detailLabel.textColor = NSColor(calibratedWhite: 0.20, alpha: 1)
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byTruncatingMiddle

        documentIllustrationView.translatesAutoresizingMaskIntoConstraints = false
        documentIllustrationView.setAccessibilityLabel("文档")

        secondaryButton.bezelStyle = .rounded
        secondaryButton.controlSize = .small
        secondaryButton.font = .systemFont(ofSize: 12.5, weight: .medium)
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryButtonPressed)

        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .small
        primaryButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.spacing = 7
        textStack.alignment = .width
        textStack.distribution = .fill

        let contentRow = NSStackView(views: [documentIllustrationView, textStack])
        contentRow.orientation = .horizontal
        contentRow.spacing = 14
        contentRow.alignment = .top
        contentRow.distribution = .fill

        let buttonRow = NSStackView(views: [secondaryButton, primaryButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually

        let stack = NSStackView(views: [contentRow, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -38),
            contentRow.heightAnchor.constraint(equalToConstant: 112),
            documentIllustrationView.widthAnchor.constraint(equalToConstant: 76),
            documentIllustrationView.heightAnchor.constraint(equalToConstant: 96),
            titleLabel.heightAnchor.constraint(equalToConstant: 28),
            buttonRow.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func metadataText(for file: ValidatedFile?) -> String {
        guard let file else {
            return "演示文件.psd\n12.8 MB · 演示模式不会操作真实文件"
        }

        let size = ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)
        return "\(file.displayName)\n\(size)\n\(file.url.path)"
    }

    private func positionPanel(anchorGlobal: CGPoint, screen: NSScreen) {
        let visible = screen.visibleFrame
        let preferredOrigin = CGPoint(x: anchorGlobal.x - 88, y: anchorGlobal.y + 38)
        let x = min(max(preferredOrigin.x, visible.minX + 12), visible.maxX - panel.frame.width - 12)
        let y = min(max(preferredOrigin.y, visible.minY + 12), visible.maxY - panel.frame.height - 12)
        backgroundView.tailTipX = anchorGlobal.x - x
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func secondaryButtonPressed() {
        guard let phase = inputGate.consumeSecondary() else { return }
        refreshButtonState()
        switch phase {
        case .first:
            onCancel?()
        case .final:
            onBack?()
        }
    }

    @objc private func primaryButtonPressed() {
        guard let phase = inputGate.consumePrimary() else { return }
        refreshButtonState()
        switch phase {
        case .first:
            onFirstConfirm?()
        case .final:
            onFinalConfirm?()
        }
    }

    private func refreshButtonState() {
        primaryButton.isEnabled = inputGate.primaryEnabled
        secondaryButton.isEnabled = inputGate.secondaryEnabled
    }
}
