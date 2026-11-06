import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var statusItemController: StatusItemController?
    private var finderServiceProvider: FinderServiceProvider?
    private var contextClickTracker: FinderContextClickTracker?
    private var pendingURLs: [URL] = []
    private var directLaunchPresentation: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchArguments = ProcessInfo.processInfo.arguments
        let isUITestLaunch = launchArguments.contains("--ui-test")
        let isRunningTests = ProcessInfo.processInfo.environment.keys.contains {
            $0.hasPrefix("XCTest") || $0.hasPrefix("XCInjectBundle")
        }
        NSApp.setActivationPolicy(isUITestLaunch ? .regular : .accessory)
        NSLog("Peashooter File Cleaner finished launching")

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        let statusItemController = StatusItemController(coordinator: coordinator)
        self.statusItemController = statusItemController
        let contextClickTracker = FinderContextClickTracker()
        self.contextClickTracker = contextClickTracker
        let finderServiceProvider = FinderServiceProvider { [weak self, weak coordinator] fileURL, point in
            self?.directLaunchPresentation?.cancel()
            self?.directLaunchPresentation = nil
            self?.statusItemController?.hideControlPanel()
            let target = self?.preferredFinderTarget(fallback: point)
                ?? (point, FinderPointSource.menuPoint)
            coordinator?.summon(
                fileAt: fileURL,
                globalPoint: target.0,
                pointSource: target.1
            )
        }
        self.finderServiceProvider = finderServiceProvider
        NSApp.servicesProvider = finderServiceProvider
        NSUpdateDynamicServices()

        let hadPendingURLs = !pendingURLs.isEmpty
        handleIncomingURLs(pendingURLs, coordinator: coordinator)
        pendingURLs.removeAll()

        // A deterministic, file-free launch path makes the complete visual flow
        // testable even on macOS releases where Finder Sync is unavailable.
        AppLogger.lifecycle.notice(
            "Launch options: demo=\(launchArguments.contains("--demo"), privacy: .public) ui-test=\(isUITestLaunch, privacy: .public)"
        )
        let shouldStartDemo = isUITestLaunch || launchArguments.contains("--demo")
        if shouldStartDemo {
            NSLog("Peashooter File Cleaner is starting demo mode")
            let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let point = CGPoint(x: frame.midX, y: frame.midY)
            coordinator.startDemo(at: point)
            NSLog("Peashooter File Cleaner started demo mode")
        } else if !hadPendingURLs && !isRunningTests {
            scheduleDirectLaunchPresentation()
        }

        AppLogger.lifecycle.notice("Peashooter File Cleaner is ready")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        directLaunchPresentation?.cancel()
        directLaunchPresentation = nil
        guard let coordinator else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        handleIncomingURLs(urls, coordinator: coordinator)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        directLaunchPresentation?.cancel()
        directLaunchPresentation = nil

        guard filenames.count == 1, let filename = filenames.first, let coordinator else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        AppLogger.lifecycle.notice("Finder Quick Action summon request accepted")
        statusItemController?.hideControlPanel()
        let fallbackPoint = NSEvent.mouseLocation
        let target = preferredFinderTarget(fallback: fallbackPoint)
        coordinator.summon(
            fileAt: URL(fileURLWithPath: filename),
            globalPoint: target.point,
            pointSource: target.source
        )
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, coordinator?.isExperienceActive != true {
            statusItemController?.showControlPanel()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        directLaunchPresentation?.cancel()
    }

    private func scheduleDirectLaunchPresentation() {
        directLaunchPresentation?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.statusItemController?.showControlPanel()
            self?.directLaunchPresentation = nil
        }
        directLaunchPresentation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func preferredFinderTarget(
        fallback: CGPoint
    ) -> (point: CGPoint, source: FinderPointSource) {
        if let point = contextClickTracker?.recentRightClick(maximumAge: 12) {
            AppLogger.lifecycle.notice(
                "Using recent Finder right-click point x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)"
            )
            return (point, .recentFinderRightClick)
        }
        AppLogger.lifecycle.notice(
            "No recent Finder right-click point; menu point will not be used as an animation target"
        )
        return (fallback, .menuPoint)
    }

    private func handleIncomingURLs(_ urls: [URL], coordinator: AppCoordinator) {
        if urls.count == 1, let fileURL = urls.first, fileURL.isFileURL {
            AppLogger.lifecycle.notice("Finder Quick Action file URL accepted")
            statusItemController?.hideControlPanel()
            let fallbackPoint = NSEvent.mouseLocation
            let target = preferredFinderTarget(fallback: fallbackPoint)
            coordinator.summon(
                fileAt: fileURL,
                globalPoint: target.point,
                pointSource: target.source
            )
            return
        }

        if urls.contains(where: { $0.scheme == SummonURLCodec.scheme }) {
            statusItemController?.hideControlPanel()
        }
        urls.forEach(coordinator.handleIncomingURL)
    }
}

@MainActor
private final class FinderContextClickTracker {
    private var monitor: Any?
    private var lastRightClick: (point: CGPoint, date: Date)?

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            // A global monitor is not associated with a stable window. Read the
            // cursor directly so the stored value is always in macOS screen
            // coordinates, including displays with negative origins.
            let point = NSEvent.mouseLocation
            let date = Date()
            let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard frontmostBundleIdentifier == "com.apple.finder" else { return }
                self?.lastRightClick = (point, date)
                AppLogger.lifecycle.debug(
                    "Recorded global right-click x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)"
                )
            }
        }
        if monitor == nil {
            AppLogger.lifecycle.error("Global right-click monitoring is unavailable")
        } else {
            AppLogger.lifecycle.notice("Global right-click monitoring is active")
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func recentRightClick(maximumAge: TimeInterval) -> CGPoint? {
        guard let lastRightClick,
              Date().timeIntervalSince(lastRightClick.date) <= maximumAge
        else {
            return nil
        }
        return lastRightClick.point
    }
}

@MainActor
private final class FinderServiceProvider: NSObject {
    private let summon: (URL, CGPoint) -> Void

    init(summon: @escaping (URL, CGPoint) -> Void) {
        self.summon = summon
    }

    @objc(summonPeashooter:userData:error:)
    func summonPeashooter(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let fileURLs = objects.compactMap { object -> URL? in
            guard let url = object as? NSURL else { return nil }
            return url as URL
        }

        guard fileURLs.count == 1, let fileURL = fileURLs.first else {
            error.pointee = "请只选择一个普通文件后再召唤豌豆射手。" as NSString
            return
        }

        AppLogger.lifecycle.notice("Finder Services summon request accepted")
        summon(fileURL, NSEvent.mouseLocation)
    }
}

@main
@MainActor
enum PeashooterApplicationMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // NSApplication keeps a weak delegate reference. Keeping this local alive
        // for the duration of the event loop is therefore intentional.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
