import AppKit
import FinderSync

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private var contextMenuOrigin = CGPoint.zero

    override init() {
        super.init()

        // Finder Sync is most reliable when it is given the concrete folders it
        // owns instead of the entire home directory. These are also the only
        // Finder locations supported by the first release.
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        controller.directoryURLs = Set([
            homeURL.appendingPathComponent("Desktop", isDirectory: true),
            homeURL.appendingPathComponent("Documents", isDirectory: true),
            homeURL.appendingPathComponent("Downloads", isDirectory: true)
        ])
        AppLogger.finderExtension.notice("Finder Sync extension initialized")
    }

    override func beginObservingDirectory(at url: URL) {
        AppLogger.finderExtension.notice("Finder began observing a configured directory")
    }

    override func endObservingDirectory(at url: URL) {
        AppLogger.finderExtension.notice("Finder stopped observing a configured directory")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else {
            return nil
        }

        // Capture the pointer before it moves through the contextual menu. This is
        // the best non-invasive approximation of the desktop icon's screen position.
        contextMenuOrigin = NSEvent.mouseLocation

        let menu = NSMenu(title: "Peashooter File Cleaner")
        let item = NSMenuItem(
            title: "召唤豌豆射手",
            action: #selector(summonPeashooter(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)
        // The extension sandbox may not have permission to read arbitrary file
        // metadata while Finder is only constructing its menu. Limit this side
        // to selection cardinality; the unsandboxed host performs the
        // authoritative FileSafetyPolicy validation before showing any UI and
        // again immediately before Trash.
        item.isEnabled = singleSelectedURL() != nil
        menu.addItem(item)
        AppLogger.finderExtension.debug("Finder requested the item context menu")
        return menu
    }

    @objc private func summonPeashooter(_ sender: Any?) {
        guard let fileURL = singleSelectedURL(),
              let commandURL = SummonURLCodec.makeURL(fileURL: fileURL, globalPoint: contextMenuOrigin)
        else {
            NSSound.beep()
            return
        }

        guard NSWorkspace.shared.open(commandURL) else {
            AppLogger.finderExtension.error("The host application could not be opened")
            NSSound.beep()
            return
        }

        AppLogger.finderExtension.notice("A validated Finder selection was sent to the host app")
    }

    private func singleSelectedURL() -> URL? {
        guard let selectedURLs = controller.selectedItemURLs(),
              selectedURLs.count == 1,
              let selectedURL = selectedURLs.first
        else {
            return nil
        }
        return selectedURL
    }
}
