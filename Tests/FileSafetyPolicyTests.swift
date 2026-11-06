import XCTest
@testable import PeashooterFileCleaner

final class FileSafetyPolicyTests: XCTestCase {
    private var root: URL!
    private var policy: FileSafetyPolicy!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("PeashooterSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        policy = FileSafetyPolicy(userHome: root, protectedRoots: [])
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testAcceptsRegularFileInsideAllowedRoot() throws {
        let file = root.appendingPathComponent("safe-test.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("demo".utf8)))

        let validated = try policy.validate(file)
        XCTAssertEqual(validated.displayName, "safe-test.txt")
        XCTAssertEqual(validated.byteCount, 4)
        XCTAssertGreaterThan(validated.identity.inode, 0)
    }

    func testRejectsDirectory() throws {
        let directory = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try policy.validate(directory)) { error in
            XCTAssertEqual(error as? FileSafetyError, .notRegularFile)
        }
    }

    func testRejectsSymbolicLink() throws {
        let file = root.appendingPathComponent("source.txt")
        let link = root.appendingPathComponent("link.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertThrowsError(try policy.validate(link)) { error in
            XCTAssertEqual(error as? FileSafetyError, .symbolicLink)
        }
    }

    func testRejectsFileOutsideAllowedRoot() throws {
        let outside = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: outside.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertThrowsError(try policy.validate(outside)) { error in
            XCTAssertEqual(error as? FileSafetyError, .outsideUserHome)
        }
    }

    func testRejectsRegularFileInsideUserLibrary() throws {
        let library = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let file = library.appendingPathComponent("sensitive.plist")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))

        XCTAssertThrowsError(try policy.validate(file)) { error in
            XCTAssertEqual(error as? FileSafetyError, .protectedLocation)
        }
    }
}
