import AppKit
import ApplicationServices
import OSLog
import SpriteKit

struct FinderVisualTarget {
    let globalCenter: CGPoint
    let iconSize: CGSize?
    let usedAccessibilityFrame: Bool
    let source: String

    static func demo(at point: CGPoint) -> FinderVisualTarget {
        FinderVisualTarget(
            globalCenter: point,
            iconSize: ExperienceLayout.defaultFinderIconSize,
            usedAccessibilityFrame: false,
            source: "demo"
        )
    }
}

@MainActor
final class AnimationWindowController {
    private let request: SummonRequest
    private let validatedFile: ValidatedFile?
    private let trashService: TrashServicing
    private let stateMachine = ExperienceStateMachine()
    private let confirmationController = ConfirmationPanelController()
    private let screen: NSScreen
    private let overlayPanel: AnimationOverlayPanel
    private let scene: PeashooterScene
    private let fileIcon: NSImage
    private let visualTarget: FinderVisualTarget
    private var attackStarted = false
    private var didFinish = false

    var onFinished: (() -> Void)?

    init(
        request: SummonRequest,
        validatedFile: ValidatedFile?,
        visualTarget: FinderVisualTarget,
        trashService: TrashServicing = TrashService()
    ) {
        self.request = request
        self.validatedFile = validatedFile
        self.trashService = trashService

        self.visualTarget = visualTarget

        let targetScreen = Self.screen(containing: visualTarget.globalCenter)
        screen = targetScreen
        overlayPanel = AnimationOverlayPanel(screen: targetScreen)

        let sceneSize = targetScreen.frame.size
        let animationScene = PeashooterScene(size: sceneSize)
        scene = animationScene
        fileIcon = validatedFile.map { NSWorkspace.shared.icon(forFile: $0.url.path) }
            ?? NSImage(named: NSImage.multipleDocumentsName)
            ?? NSImage(size: NSSize(width: 128, height: 128))

        let view = SKView(frame: NSRect(origin: .zero, size: sceneSize))
        view.allowsTransparency = true
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.presentScene(animationScene)
        overlayPanel.contentView = view

        configureConfirmationCallbacks()
    }

    func start() {
        AppLogger.lifecycle.notice("Peashooter animation window is starting")
        do {
            try stateMachine.transition(to: .summoned)
        } catch {
            AppLogger.lifecycle.fault(
                "Initial experience transition failed: \(error.localizedDescription, privacy: .public)"
            )
            finishImmediately()
            return
        }

        let localTarget = CGPoint(
            x: visualTarget.globalCenter.x - screen.frame.minX,
            y: visualTarget.globalCenter.y - screen.frame.minY
        )
        let name = validatedFile?.displayName ?? "演示文件.psd"
        AppLogger.lifecycle.notice(
            "Target positioning source=\(self.visualTarget.source, privacy: .public) global=(\(self.visualTarget.globalCenter.x, privacy: .public),\(self.visualTarget.globalCenter.y, privacy: .public)) local=(\(localTarget.x, privacy: .public),\(localTarget.y, privacy: .public)) screen=(\(self.screen.frame.minX, privacy: .public),\(self.screen.frame.minY, privacy: .public),\(self.screen.frame.width, privacy: .public),\(self.screen.frame.height, privacy: .public))"
        )
        scene.configure(
            fileIcon: fileIcon,
            fileName: name,
            targetPoint: localTarget,
            targetIconSize: visualTarget.iconSize,
            showsVirtualFile: request.isDemo
        )
        overlayPanel.orderFrontRegardless()

        guard transition(to: .approaching) else {
            finishImmediately()
            return
        }
        scene.spawnAndApproach { [weak self] in
            guard let self else { return }
            guard self.transition(to: .firstConfirmation) else { return }
            self.showFirstConfirmation()
        }
    }

    private func configureConfirmationCallbacks() {
        confirmationController.onCancel = { [weak self] in
            self?.cancelExperience()
        }
        confirmationController.onFirstConfirm = { [weak self] in
            guard let self else { return }
            guard self.transition(to: .finalConfirmation) else { return }
            self.showFinalConfirmation()
        }
        confirmationController.onBack = { [weak self] in
            guard let self else { return }
            guard self.transition(to: .firstConfirmation) else { return }
            self.showFirstConfirmation()
        }
        confirmationController.onFinalConfirm = { [weak self] in
            self?.beginAttack()
        }
    }

    private func showFirstConfirmation() {
        confirmationController.showFirst(
            file: validatedFile,
            anchorGlobal: confirmationAnchor,
            on: screen
        )
    }

    private func showFinalConfirmation() {
        confirmationController.showFinal(
            file: validatedFile,
            anchorGlobal: confirmationAnchor,
            on: screen
        )
    }

    // Anchor the confirmation bubble to the target file icon itself so the
    // dialogue reads as being about the selected file, not about the shooter.
    private var confirmationAnchor: CGPoint {
        visualTarget.globalCenter
    }

    private func beginAttack() {
        guard !attackStarted else { return }
        attackStarted = true
        guard transition(to: .charging) else {
            attackStarted = false
            return
        }
        confirmationController.hide()
        scene.playCharge { [weak self] in
            guard let self else { return }
            guard self.transition(to: .shooting) else { return }
            self.scene.fireInitialShots { [weak self] in
                self?.launchFinalShot()
            }
        }
    }

    private func launchFinalShot() {
        scene.launchFinalShot { [weak self] in
            self?.performTrashOperationAtFinalImpact()
        }
    }

    private func performTrashOperationAtFinalImpact() {
        guard transition(to: .trashing) else { return }

        guard !request.isDemo else {
            completeFinalImpactAndShatter()
            return
        }
        guard let validatedFile else {
            fail(with: "目标文件信息丢失")
            return
        }

        trashService.moveToTrash(
            validatedFile.url,
            expectedIdentity: validatedFile.identity
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    AppLogger.fileOperation.notice("A confirmed file was moved to Trash successfully")
                    self.completeFinalImpactAndShatter()
                case let .failure(error):
                    self.scene.cancelPendingFinalShot()
                    let nsError = error as NSError
                    AppLogger.fileOperation.error("Trash operation failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
                    self.fail(with: error.localizedDescription)
                }
            }
        }
    }

    private func completeFinalImpactAndShatter() {
        guard transition(to: .shattering) else { return }
        scene.completeFinalHitAndShatter { [weak self] in
            guard let self else { return }
            guard self.transition(to: .success) else { return }
            self.scene.waitBeforeZombieExit { [weak self] in
                self?.beginZombieExit()
            }
        }
    }

    private func beginZombieExit() {
        guard transition(to: .zombieExit) else { return }
        scene.playZombieExit { [weak self] in
            guard let self else { return }
            guard self.transition(to: .hidden) else { return }
            self.finishImmediately()
        }
    }

    private func cancelExperience() {
        guard transition(to: .hidden) else { return }
        confirmationController.hide()
        finishImmediately()
    }

    private func fail(with message: String) {
        guard transition(to: .failure) else { return }
        confirmationController.hide()
        scene.cancelPendingFinalShot()
        scene.showFailure(message: message) { [weak self] in
            guard let self else { return }
            guard self.transition(to: .hidden) else { return }
            self.finishImmediately()
        }
    }

    @discardableResult
    private func transition(to nextState: ExperienceState) -> Bool {
        do {
            try stateMachine.transition(to: nextState)
            AppLogger.lifecycle.debug("Experience state: \(nextState.rawValue, privacy: .public)")
            return true
        } catch {
            AppLogger.lifecycle.fault("State transition failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func finishImmediately() {
        guard !didFinish else { return }
        didFinish = true
        confirmationController.hide()
        overlayPanel.orderOut(nil)
        onFinished?()
    }

    private static func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

enum FinderItemFrameLocator {
    private static let maximumElementsToInspect = 2_500
    private static let searchTimeLimit: TimeInterval = 0.9
    private static let accessibilityQueue = DispatchQueue(
        label: "com.peashooter.file-cleaner.finder-accessibility",
        qos: .userInitiated
    )

    @MainActor
    static func locate(
        fileURL: URL,
        fallbackPoint: CGPoint,
        fallbackSource: FinderPointSource,
        completion: @escaping (FinderVisualTarget?) -> Void
    ) {
        let referenceTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrames = NSScreen.screens.map(\.frame)
        accessibilityQueue.async {
            let target = locateSynchronously(fileURL: fileURL, referenceTop: referenceTop)
                ?? FinderDesktopSelectionLocator.locate(
                    fileURL: fileURL,
                    referenceTop: referenceTop,
                    screenFrames: screenFrames
                )
                ?? fallback(point: fallbackPoint, source: fallbackSource)
            DispatchQueue.main.async {
                completion(target)
            }
        }
    }

    @MainActor
    static func waitUntilItemDisappears(
        fileURL: URL,
        timeout: TimeInterval,
        completion: @escaping () -> Void
    ) {
        guard AXIsProcessTrusted() else {
            // Without AX permission Finder cannot expose when the real icon has
            // left its view. A short refresh beat is the only available signal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                completion()
            }
            return
        }

        let referenceTop = NSScreen.screens.first?.frame.maxY ?? 0
        accessibilityQueue.async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                guard locateSynchronously(fileURL: fileURL, referenceTop: referenceTop) != nil else { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private static func locateSynchronously(
        fileURL: URL,
        referenceTop: CGFloat
    ) -> FinderVisualTarget? {
        guard AXIsProcessTrusted() else {
            AppLogger.lifecycle.error("Finder AX frame lookup skipped because Accessibility is not trusted")
            return nil
        }
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            AppLogger.lifecycle.error("Finder AX frame lookup failed because Finder is not running")
            return nil
        }

        let application = AXUIElementCreateApplication(finder.processIdentifier)
        let fileName = fileURL.lastPathComponent
        var roots: [(element: AXUIElement, permitsNameOnlyMatch: Bool)] = []
        if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application) {
            roots.append((focusedWindow, true))
        }
        if let windows = attribute(kAXWindowsAttribute, from: application) as? [AXUIElement] {
            roots.append(contentsOf: windows.map { ($0, false) })
        }
        roots.append((application, false))

        var elements = roots
        var nextIndex = 0
        var inspected = 0
        var visited = Set<CFHashCode>()
        let deadline = Date().addingTimeInterval(searchTimeLimit)

        while nextIndex < elements.count,
              inspected < maximumElementsToInspect,
              Date() < deadline {
            let entry = elements[nextIndex]
            let element = entry.element
            nextIndex += 1
            let elementHash = CFHash(element)
            guard visited.insert(elementHash).inserted else { continue }
            inspected += 1

            let match = matchKind(element: element, fileURL: fileURL, fileName: fileName)
            let isSelected = boolAttribute(kAXSelectedAttribute, from: element) == true
            if (match == .exactURL || (match == .nameOnly && isSelected && entry.permitsNameOnlyMatch)),
               let target = visualTargetForFinderIcon(
                   near: element,
                   referenceTop: referenceTop
               ) {
                return target
            }

            elements.append(contentsOf: children(of: element).map {
                ($0, entry.permitsNameOnlyMatch)
            })
        }

        AppLogger.lifecycle.error(
            "Finder AX frame lookup found no unambiguous selected item after inspecting \(inspected, privacy: .public) elements"
        )
        return nil
    }

    private static func fallback(
        point: CGPoint,
        source: FinderPointSource
    ) -> FinderVisualTarget? {
        guard source.permitsVisualFallback else {
            AppLogger.lifecycle.error(
                "Finder AX frame unavailable and menu-click position was rejected as an animation target"
            )
            return nil
        }
        AppLogger.lifecycle.debug(
            "Finder AX frame unavailable; using trusted request point source=\(source.rawValue, privacy: .public)"
        )
        return FinderVisualTarget(
            globalCenter: point,
            iconSize: ExperienceLayout.defaultFinderIconSize,
            usedAccessibilityFrame: false,
            source: source.rawValue
        )
    }

    private enum MatchKind: Equatable {
        case none
        case exactURL
        case nameOnly
    }

    private static func matchKind(
        element: AXUIElement,
        fileURL: URL,
        fileName: String
    ) -> MatchKind {
        if let rawURL = attribute(kAXURLAttribute, from: element) {
            if let url = rawURL as? URL, url.standardizedFileURL == fileURL.standardizedFileURL {
                return .exactURL
            }
            if let url = rawURL as? NSURL,
               (url as URL).standardizedFileURL == fileURL.standardizedFileURL {
                return .exactURL
            }
        }

        let candidates = [
            stringAttribute(kAXTitleAttribute, from: element),
            stringAttribute(kAXDescriptionAttribute, from: element),
            stringAttribute(kAXHelpAttribute, from: element)
        ].compactMap { $0 }
        return candidates.contains { candidate in
            candidate == fileName || candidate.hasPrefix("\(fileName),")
        } ? .nameOnly : .none
    }

    private static func visualTargetForFinderIcon(
        near matchedElement: AXUIElement,
        referenceTop: CGFloat
    ) -> FinderVisualTarget? {
        guard let iconElement = nearestFinderIconElement(to: matchedElement),
              let position = pointAttribute(kAXPositionAttribute, from: iconElement),
              let size = sizeAttribute(kAXSizeAttribute, from: iconElement),
              size.width > 0,
              size.height > 0
        else {
            AppLogger.lifecycle.error(
                "A Finder item matched, but its actual AXImage frame could not be resolved"
            )
            return nil
        }

        let center = CGPoint(
            x: position.x + size.width / 2,
            y: referenceTop - position.y - size.height / 2
        )
        return FinderVisualTarget(
            globalCenter: center,
            iconSize: size,
            usedAccessibilityFrame: true,
            source: "finder-accessibility-icon-frame"
        )
    }

    private static func nearestFinderIconElement(to matchedElement: AXUIElement) -> AXUIElement? {
        if isPlausibleFinderIcon(matchedElement) {
            return matchedElement
        }

        let matchedCenter = frame(of: matchedElement).map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        var ancestor = matchedElement

        // Finder usually exposes a file as an AXCell/AXGroup containing one
        // AXImage and one filename element. Search the nearest container first
        // so an icon from another row or desktop item can never be selected.
        for _ in 0..<4 {
            guard let parent = elementAttribute(kAXParentAttribute, from: ancestor) else {
                break
            }
            let candidates = imageDescendants(of: parent, maximumDepth: 2)
            if !candidates.isEmpty {
                guard let matchedCenter else { return candidates.first }
                return candidates.min { lhs, rhs in
                    squaredDistance(from: frame(of: lhs), to: matchedCenter)
                        < squaredDistance(from: frame(of: rhs), to: matchedCenter)
                }
            }
            ancestor = parent
        }
        return nil
    }

    private static func imageDescendants(
        of root: AXUIElement,
        maximumDepth: Int
    ) -> [AXUIElement] {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var nextIndex = 0
        var images: [AXUIElement] = []
        var visited = Set<CFHashCode>()

        while nextIndex < queue.count, queue.count <= 80 {
            let entry = queue[nextIndex]
            nextIndex += 1
            let hash = CFHash(entry.element)
            guard visited.insert(hash).inserted else { continue }

            if isPlausibleFinderIcon(entry.element) {
                images.append(entry.element)
            }
            guard entry.depth < maximumDepth else { continue }
            queue.append(contentsOf: children(of: entry.element).map {
                ($0, entry.depth + 1)
            })
        }
        return images
    }

    private static func isPlausibleFinderIcon(_ element: AXUIElement) -> Bool {
        guard stringAttribute(kAXRoleAttribute, from: element) == kAXImageRole,
              let frame = frame(of: element)
        else {
            return false
        }
        return frame.width >= 8 && frame.height >= 8
            && frame.width <= 256 && frame.height <= 256
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element),
              size.width > 0,
              size.height > 0
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func squaredDistance(from frame: CGRect?, to point: CGPoint) -> CGFloat {
        guard let frame else { return .greatestFiniteMagnitude }
        let deltaX = frame.midX - point.x
        let deltaY = frame.midY - point.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] ?? []
    }

    private static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private static func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
        (attribute(name, from: element) as? NSNumber)?.boolValue
    }

    private static func elementAttribute(_ name: String, from element: AXUIElement) -> AXUIElement? {
        guard let rawValue = attribute(name, from: element),
              CFGetTypeID(rawValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private static func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
        guard let rawValue = attribute(name, from: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
        guard let rawValue = attribute(name, from: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

struct FinderDesktopPositionSnapshot {
    let selectedFileURL: URL
    let finderPosition: CGPoint

    func visualTarget(
        matching expectedFileURL: URL,
        referenceTop: CGFloat,
        screenFrames: [CGRect]
    ) -> FinderVisualTarget? {
        guard selectedFileURL.standardizedFileURL == expectedFileURL.standardizedFileURL,
              finderPosition.x.isFinite,
              finderPosition.y.isFinite,
              referenceTop.isFinite,
              finderPosition.x >= 0,
              finderPosition.y >= 0
        else {
            return nil
        }

        // Finder exposes desktop positions in a top-left-origin coordinate
        // system. The value describes the icon's centre, so only the vertical
        // axis needs converting to AppKit's bottom-left-origin screen space.
        let globalCenter = CGPoint(
            x: finderPosition.x,
            y: referenceTop - finderPosition.y
        )
        guard globalCenter.x.isFinite,
              globalCenter.y.isFinite,
              screenFrames.contains(where: { $0.contains(globalCenter) })
        else {
            return nil
        }

        return FinderVisualTarget(
            globalCenter: globalCenter,
            iconSize: ExperienceLayout.defaultFinderIconSize,
            usedAccessibilityFrame: false,
            source: "finder-apple-event-desktop-position"
        )
    }
}

private enum FinderDesktopSelectionLocator {
    private static let selectionScript = """
    with timeout of 10 seconds
        tell application "Finder"
            set selectedItems to selection
            if (count of selectedItems) is not 1 then return {}
            set selectedItem to item 1 of selectedItems
            set selectedPath to POSIX path of (selectedItem as alias)
            set selectedPosition to desktop position of selectedItem
            return {selectedPath, item 1 of selectedPosition, item 2 of selectedPosition}
        end tell
    end timeout
    """

    static func locate(
        fileURL: URL,
        referenceTop: CGFloat,
        screenFrames: [CGRect]
    ) -> FinderVisualTarget? {
        guard isDirectDesktopFile(fileURL) else {
            return nil
        }

        var scriptError: NSDictionary?
        guard let script = NSAppleScript(source: selectionScript) else {
            AppLogger.lifecycle.error("Finder desktop position AppleScript could not be created")
            return nil
        }
        let descriptor = script.executeAndReturnError(&scriptError)
        guard let snapshot = snapshot(from: descriptor) else {
            let errorNumber = scriptError?[NSAppleScript.errorNumber] as? NSNumber
            AppLogger.lifecycle.error(
                "Finder desktop position lookup failed with AppleScript code=\(errorNumber?.intValue ?? 0, privacy: .public)"
            )
            return nil
        }

        guard let target = snapshot.visualTarget(
            matching: fileURL,
            referenceTop: referenceTop,
            screenFrames: screenFrames
        ) else {
            AppLogger.lifecycle.error(
                "Finder desktop position lookup rejected a mismatched selection or invalid coordinate"
            )
            return nil
        }

        AppLogger.lifecycle.notice(
            "Using exact Finder desktop selection position x=\(target.globalCenter.x, privacy: .public) y=\(target.globalCenter.y, privacy: .public)"
        )
        return target
    }

    private static func isDirectDesktopFile(_ fileURL: URL) -> Bool {
        guard let desktopURL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }
        return fileURL.deletingLastPathComponent().standardizedFileURL
            == desktopURL.standardizedFileURL
    }

    private static func snapshot(
        from descriptor: NSAppleEventDescriptor
    ) -> FinderDesktopPositionSnapshot? {
        guard descriptor.numberOfItems == 3,
              let path = descriptor.atIndex(1)?.stringValue,
              !path.isEmpty,
              let xDescriptor = descriptor.atIndex(2),
              let yDescriptor = descriptor.atIndex(3)
        else {
            return nil
        }

        return FinderDesktopPositionSnapshot(
            selectedFileURL: URL(fileURLWithPath: path),
            finderPosition: CGPoint(
                x: CGFloat(xDescriptor.int32Value),
                y: CGFloat(yDescriptor.int32Value)
            )
        )
    }
}
