import AppKit
import SpriteKit
import XCTest
@testable import PeashooterFileCleaner

@MainActor
final class ExperienceStateMachineTests: XCTestCase {
    func testDistributionBundleHasGuideAndPortableFinderWorkflow() throws {
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertNotNil(bundle.url(forResource: "UserGuide", withExtension: "html"))
        let workflow = try XCTUnwrap(bundle.url(forResource: "召唤豌豆射手", withExtension: "workflow"))
        let data = try Data(contentsOf: workflow.appendingPathComponent("Contents/Resources/document.wflow"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("/usr/bin/open -b com.peashooter.file-cleaner"))
        XCTAssertFalse(text.contains("$HOME/Applications"))
    }

    func testFinderWorkflowInstallerDoesNotOverwriteExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PeashooterSetupTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("Source.workflow")
        let sourceResources = source.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: sourceResources, withIntermediateDirectories: true)
        let original = Data("app-created workflow".utf8)
        try original.write(to: sourceResources.appendingPathComponent("document.wflow"))
        let services = root.appendingPathComponent("Services")
        XCTAssertEqual(try FinderIntegrationInstaller.install(from: source, into: services), .installed)
        let installed = services.appendingPathComponent("召唤豌豆射手.workflow/Contents/Resources/document.wflow")
        XCTAssertEqual(try Data(contentsOf: installed), original)
        try Data("new source".utf8).write(to: sourceResources.appendingPathComponent("document.wflow"))
        XCTAssertEqual(try FinderIntegrationInstaller.install(from: source, into: services), .alreadyInstalled)
        XCTAssertEqual(try Data(contentsOf: installed), original)
        XCTAssertThrowsError(try FinderIntegrationInstaller.install(from: nil, into: services))
    }

    func testHappyPathMatchesSafetyFlow() throws {
        let machine = ExperienceStateMachine()
        let path: [ExperienceState] = [
            .summoned,
            .approaching,
            .firstConfirmation,
            .finalConfirmation,
            .charging,
            .shooting,
            .trashing,
            .shattering,
            .success,
            .zombieExit,
            .hidden
        ]

        for state in path {
            try machine.transition(to: state)
        }
        XCTAssertEqual(machine.state, .hidden)
    }

    func testCannotTrashBeforeBothConfirmationsAndShooting() throws {
        let machine = ExperienceStateMachine()
        try machine.transition(to: .summoned)
        try machine.transition(to: .approaching)
        try machine.transition(to: .firstConfirmation)

        XCTAssertThrowsError(try machine.transition(to: .trashing))
        XCTAssertEqual(machine.state, .firstConfirmation)
    }

    func testUserCanGoBackFromFinalConfirmation() throws {
        let machine = ExperienceStateMachine()
        try machine.transition(to: .summoned)
        try machine.transition(to: .approaching)
        try machine.transition(to: .firstConfirmation)
        try machine.transition(to: .finalConfirmation)
        try machine.transition(to: .firstConfirmation)

        XCTAssertEqual(machine.state, .firstConfirmation)
    }

    func testAnimationLayoutKeepsCharactersCompactAndStretcherVisible() {
        XCTAssertEqual(ExperienceLayout.shooterSize, CGSize(width: 68, height: 68))
        XCTAssertEqual(ExperienceLayout.zombieSize.height, 96)
        XCTAssertEqual(ExperienceLayout.stretcherSize, CGSize(width: 190, height: 45))
        XCTAssertEqual(ExperienceLayout.shooterTargetCenterDistance, 82)
        XCTAssertGreaterThan(ExperienceLayout.stretcherSize.width, ExperienceLayout.zombieSize.width * 2)
        XCTAssertEqual(ExperienceLayout.shooterMuzzleOffset.x, 17.68, accuracy: 0.001)
        XCTAssertEqual(ExperienceLayout.shooterMuzzleOffset.y, 17.68, accuracy: 0.001)
        XCTAssertEqual(ExperienceLayout.projectileSize, CGSize(width: 20, height: 20))
        XCTAssertEqual(ExperienceLayout.impactSize, CGSize(width: 60, height: 60))
        XCTAssertGreaterThan(ExperienceLayout.crackOutlineWidth, ExperienceLayout.crackLineWidth)
    }

    func testRealFinderTargetDoesNotShowASecondFileIcon() {
        let scene = PeashooterScene(size: CGSize(width: 1_200, height: 800))
        scene.configure(
            fileIcon: NSImage(size: NSSize(width: 128, height: 128)),
            fileName: "temporary-test.txt",
            targetPoint: CGPoint(x: 800, y: 420),
            targetIconSize: CGSize(width: 72, height: 72),
            showsVirtualFile: false
        )

        let deferredIcon = scene.childNode(withName: "//deferredFileRepresentation")
        let caption = scene.childNode(withName: "//virtualFileCaption")
        XCTAssertEqual(deferredIcon?.isHidden, true)
        XCTAssertEqual(deferredIcon?.alpha, 0)
        XCTAssertEqual(caption?.alpha, 0)
        XCTAssertNotNil(scene.childNode(withName: "//finderDamageOverlay"))
        XCTAssertNotNil(scene.childNode(withName: "//visibleCrackOutline"))
        XCTAssertNotNil(scene.childNode(withName: "//visibleCrackLine"))
    }

    func testInitialRealHitsCreateVisibleOutlinedCracksWithoutRevealingIcon() {
        let scene = PeashooterScene(size: CGSize(width: 1_200, height: 800))
        scene.configure(
            fileIcon: NSImage(size: NSSize(width: 128, height: 128)),
            fileName: "temporary-test.txt",
            targetPoint: CGPoint(x: 800, y: 420),
            targetIconSize: CGSize(width: 72, height: 72),
            showsVirtualFile: false
        )

        scene.renderDamageOverlay(level: 1)

        let deferredIcon = scene.childNode(withName: "//deferredFileRepresentation")
        let crackOutline = scene.childNode(withName: "//visibleCrackOutline") as? SKShapeNode
        let crackLine = scene.childNode(withName: "//visibleCrackLine") as? SKShapeNode
        XCTAssertTrue(deferredIcon?.isHidden == true)
        XCTAssertNotNil(crackOutline?.path)
        XCTAssertNotNil(crackLine?.path)
    }

    func testFinalProjectileArrivesBeforeImpactAndFragmentsAreCommitted() {
        let scene = PeashooterScene(size: CGSize(width: 1_200, height: 800))
        scene.configure(
            fileIcon: NSImage(size: NSSize(width: 128, height: 128)),
            fileName: "temporary-test.txt",
            targetPoint: CGPoint(x: 800, y: 420),
            targetIconSize: CGSize(width: 72, height: 72),
            showsVirtualFile: false
        )

        scene.launchFinalShot {}

        XCTAssertNotNil(scene.childNode(withName: "//pendingFinalProjectile"))
        XCTAssertTrue(scene["//fileFragment"].isEmpty)

        scene.completeFinalHitAndShatter {}

        XCTAssertNil(scene.childNode(withName: "//pendingFinalProjectile"))
        XCTAssertEqual(scene["//fileFragment"].count, 16)
    }

    func testZombieExitStartsWithOneSynchronizedStretcherGroup() {
        let scene = PeashooterScene(size: CGSize(width: 1_200, height: 800))
        scene.configure(
            fileIcon: NSImage(size: NSSize(width: 128, height: 128)),
            fileName: "demo.txt",
            targetPoint: CGPoint(x: 800, y: 420),
            targetIconSize: CGSize(width: 72, height: 72),
            showsVirtualFile: true
        )
        scene.playZombieExit {}

        let carryGroup = scene.childNode(withName: "//zombieCarryGroup")
        XCTAssertNotNil(carryGroup?.childNode(withName: "stretcher"))
        XCTAssertNotNil(carryGroup?.childNode(withName: "leftStretcherZombie"))
        XCTAssertNotNil(carryGroup?.childNode(withName: "rightStretcherZombie"))
    }

    func testTargetCoordinatesAreNotInsetAndShooterRemainsToTheirLeft() {
        let scene = PeashooterScene(size: CGSize(width: 1_200, height: 800))
        scene.configure(
            fileIcon: NSImage(size: NSSize(width: 128, height: 128)),
            fileName: "edge-test.txt",
            targetPoint: CGPoint(x: 12, y: 18),
            targetIconSize: CGSize(width: 72, height: 72),
            showsVirtualFile: false
        )

        XCTAssertEqual(scene.visualTargetPosition.x, 12, accuracy: 0.001)
        XCTAssertEqual(scene.visualTargetPosition.y, 18, accuracy: 0.001)
        XCTAssertLessThan(scene.shooterRestingPosition.x, scene.visualTargetPosition.x)
    }

    func testFinalConfirmationCannotBeConsumedUntilSeparatelyArmed() {
        let gate = ConfirmationInputGate()
        XCTAssertEqual(gate.consumePrimary(), .first)

        gate.presentFinal(armAfter: 60) {}
        XCTAssertNil(gate.consumePrimary())
        XCTAssertTrue(gate.secondaryEnabled)
    }

    func testRealConfirmationHidesFilePreview() throws {
        let controller = ConfirmationPanelController()
        let screen = try XCTUnwrap(NSScreen.main)
        controller.showFirst(
            file: nil,
            anchorGlobal: CGPoint(x: screen.frame.midX, y: screen.frame.midY),
            on: screen
        )
        XCTAssertFalse(controller.isFilePreviewVisible)
        XCTAssertTrue(controller.isDocumentIllustrationVisible)
        XCTAssertLessThanOrEqual(controller.confirmationPanelSize.width, 410)
        XCTAssertLessThanOrEqual(controller.confirmationPanelSize.height, 220)

        controller.showFinal(
            file: nil,
            anchorGlobal: CGPoint(x: screen.frame.midX, y: screen.frame.midY),
            on: screen
        )
        XCTAssertFalse(controller.isFilePreviewVisible)
        XCTAssertTrue(controller.isDocumentIllustrationVisible)
        controller.hide()
    }
}
