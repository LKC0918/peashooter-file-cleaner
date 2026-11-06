import AppKit

@MainActor
final class AppCoordinator {
    private let safetyPolicy: FileSafetyPolicy
    private let trashService: TrashServicing
    private var activeExperience: AnimationWindowController?
    private var isPreparingExperience = false

    var isExperienceActive: Bool {
        activeExperience != nil || isPreparingExperience
    }

    init(
        safetyPolicy: FileSafetyPolicy = FileSafetyPolicy(),
        trashService: TrashServicing? = nil
    ) {
        self.safetyPolicy = safetyPolicy
        self.trashService = trashService ?? TrashService(safetyPolicy: safetyPolicy)
    }

    func handleIncomingURL(_ url: URL) {
        guard let request = SummonURLCodec.parse(url) else {
            presentError(title: "无法召唤豌豆射手", message: "Finder 传来的请求格式无效。")
            return
        }
        begin(request)
    }

    func startDemo(at point: CGPoint = NSEvent.mouseLocation) {
        AppLogger.lifecycle.notice("Peashooter demo request accepted")
        begin(.demo(at: point))
    }

    func summon(
        fileAt fileURL: URL,
        globalPoint: CGPoint,
        pointSource: FinderPointSource
    ) {
        begin(SummonRequest(
            fileURL: fileURL,
            globalPoint: globalPoint,
            pointSource: pointSource,
            isDemo: false
        ))
    }

    private func begin(_ request: SummonRequest) {
        guard activeExperience == nil, !isPreparingExperience else {
            NSSound.beep()
            presentError(title: "豌豆射手正在忙", message: "请等当前动画结束后再召唤一次。")
            return
        }

        let validatedFile: ValidatedFile?
        if request.isDemo {
            validatedFile = nil
        } else {
            guard let fileURL = request.fileURL else {
                presentError(title: "无法召唤豌豆射手", message: "没有找到目标文件。")
                return
            }
            do {
                validatedFile = try safetyPolicy.validate(fileURL)
            } catch {
                presentError(title: "这个目标不能攻击", message: error.localizedDescription)
                return
            }
        }

        if request.isDemo {
            startExperience(
                request: request,
                validatedFile: validatedFile,
                visualTarget: .demo(at: request.globalPoint)
            )
            return
        }

        guard let fileURL = validatedFile?.url else {
            presentError(title: "无法召唤豌豆射手", message: "目标文件信息丢失。")
            return
        }

        isPreparingExperience = true
        FinderItemFrameLocator.locate(
            fileURL: fileURL,
            fallbackPoint: request.globalPoint,
            fallbackSource: request.pointSource
        ) { [weak self] visualTarget in
            guard let self else { return }
            self.isPreparingExperience = false
            guard let visualTarget else {
                self.presentLocationError()
                return
            }
            self.startExperience(
                request: request,
                validatedFile: validatedFile,
                visualTarget: visualTarget
            )
        }
    }

    private func startExperience(
        request: SummonRequest,
        validatedFile: ValidatedFile?,
        visualTarget: FinderVisualTarget
    ) {
        guard activeExperience == nil else { return }
        let controller = AnimationWindowController(
            request: request,
            validatedFile: validatedFile,
            visualTarget: visualTarget,
            trashService: trashService
        )
        controller.onFinished = { [weak self, weak controller] in
            guard let self else { return }
            if self.activeExperience === controller {
                self.activeExperience = nil
            }
        }
        activeExperience = controller
        AppLogger.lifecycle.notice("Peashooter experience controller created")
        controller.start()
    }

    private func presentError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func presentLocationError() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法精确定位文件图标"
        alert.informativeText = "没有取得 Finder 中与目标路径完全一致的图标位置。请保持 Finder 只选中这个文件；若目标位于 Finder 窗口，请允许 Peashooter File Cleaner 使用辅助功能。程序仍不会使用菜单按钮的位置。"
        alert.addButton(withTitle: "打开辅助功能设置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              let settingsURL = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              )
        else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
