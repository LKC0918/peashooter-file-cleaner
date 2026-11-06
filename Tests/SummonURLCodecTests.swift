import XCTest
@testable import PeashooterFileCleaner

final class SummonURLCodecTests: XCTestCase {
    func testRoundTripPreservesUnicodePathAndPoint() throws {
        let file = URL(fileURLWithPath: "/Users/test/桌面/要消灭的文件.txt")
        let point = CGPoint(x: 438.5, y: 792.25)

        let url = try XCTUnwrap(SummonURLCodec.makeURL(fileURL: file, globalPoint: point))
        let parsed = try XCTUnwrap(SummonURLCodec.parse(url))

        XCTAssertEqual(parsed.fileURL, file)
        XCTAssertEqual(parsed.globalPoint.x, point.x, accuracy: 0.001)
        XCTAssertEqual(parsed.globalPoint.y, point.y, accuracy: 0.001)
        XCTAssertEqual(parsed.pointSource, .finderSyncContext)
        XCTAssertFalse(parsed.isDemo)
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(SummonURLCodec.parse(URL(string: "https://example.com/summon")!))
    }

    func testDemoURLRoundTripHasNoRealFile() throws {
        let point = CGPoint(x: 640, y: 420)

        let url = try XCTUnwrap(SummonURLCodec.makeDemoURL(globalPoint: point))
        let parsed = try XCTUnwrap(SummonURLCodec.parse(url))

        XCTAssertTrue(parsed.isDemo)
        XCTAssertNil(parsed.fileURL)
        XCTAssertEqual(parsed.pointSource, .demo)
        XCTAssertEqual(parsed.globalPoint.x, point.x, accuracy: 0.001)
        XCTAssertEqual(parsed.globalPoint.y, point.y, accuracy: 0.001)
    }

    func testDemoURLRejectsNonFiniteCoordinates() {
        XCTAssertNil(SummonURLCodec.parse(URL(string: "peashooter-cleaner://demo?x=nan&y=2")!))
    }

    func testRepeatedQueryKeysCannotCrashOrOverrideFirstValue() throws {
        let url = try XCTUnwrap(URL(string: "peashooter-cleaner://summon?file=file:///Users/test/first.txt&file=file:///Users/test/second.txt&x=1&y=2"))
        let parsed = try XCTUnwrap(SummonURLCodec.parse(url))

        XCTAssertEqual(parsed.fileURL?.path, "/Users/test/first.txt")
    }

    func testMenuClickPointCannotBeUsedAsVisualFallback() {
        XCTAssertFalse(FinderPointSource.menuPoint.permitsVisualFallback)
        XCTAssertTrue(FinderPointSource.finderSyncContext.permitsVisualFallback)
        XCTAssertTrue(FinderPointSource.recentFinderRightClick.permitsVisualFallback)
    }

    func testFinderDesktopPositionConvertsTopLeftCoordinates() throws {
        let file = URL(fileURLWithPath: "/Users/test/Desktop/target.txt")
        let snapshot = FinderDesktopPositionSnapshot(
            selectedFileURL: file,
            finderPosition: CGPoint(x: 1_446, y: 73)
        )

        let target = try XCTUnwrap(snapshot.visualTarget(
            matching: file,
            referenceTop: 1_117,
            screenFrames: [CGRect(x: 0, y: 0, width: 1_728, height: 1_117)]
        ))

        XCTAssertEqual(target.globalCenter.x, 1_446, accuracy: 0.001)
        XCTAssertEqual(target.globalCenter.y, 1_044, accuracy: 0.001)
        XCTAssertFalse(target.usedAccessibilityFrame)
        XCTAssertEqual(target.source, "finder-apple-event-desktop-position")
    }

    func testFinderDesktopPositionRejectsDifferentSelectedFile() {
        let requested = URL(fileURLWithPath: "/Users/test/Desktop/requested.txt")
        let snapshot = FinderDesktopPositionSnapshot(
            selectedFileURL: URL(fileURLWithPath: "/Users/test/Desktop/other.txt"),
            finderPosition: CGPoint(x: 300, y: 200)
        )

        XCTAssertNil(snapshot.visualTarget(
            matching: requested,
            referenceTop: 900,
            screenFrames: [CGRect(x: 0, y: 0, width: 1_400, height: 900)]
        ))
    }

    func testFinderDesktopPositionRejectsInvalidOrOffscreenCoordinates() {
        let file = URL(fileURLWithPath: "/Users/test/Desktop/target.txt")
        let invalid = FinderDesktopPositionSnapshot(
            selectedFileURL: file,
            finderPosition: CGPoint(x: -1, y: -1)
        )
        let offscreen = FinderDesktopPositionSnapshot(
            selectedFileURL: file,
            finderPosition: CGPoint(x: 4_000, y: 100)
        )
        let screens = [CGRect(x: 0, y: 0, width: 1_400, height: 900)]

        XCTAssertNil(invalid.visualTarget(
            matching: file,
            referenceTop: 900,
            screenFrames: screens
        ))
        XCTAssertNil(offscreen.visualTarget(
            matching: file,
            referenceTop: 900,
            screenFrames: screens
        ))
    }
}
