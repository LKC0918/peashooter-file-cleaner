import XCTest
@testable import PeashooterFileCleaner

final class TrashServiceIntegrationTests: XCTestCase {
    func testMovesOnlyAnAppCreatedTemporaryFileToTrash() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("app-created.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("app-created test file".utf8)))
        let policy = FileSafetyPolicy(userHome: root, protectedRoots: [])
        let validated = try policy.validate(file)

        let expectation = expectation(description: "Move app-created file to Trash")
        var result: Result<URL?, Error>?
        TrashService(safetyPolicy: policy).moveToTrash(
            file,
            expectedIdentity: validated.identity
        ) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        switch result {
        case .success:
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        case let .failure(error):
            XCTFail("Trash operation failed: \(error)")
        case .none:
            XCTFail("Trash service did not return a result")
        }
    }

    func testRejectsAReplacementAtTheConfirmedPath() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("confirmed.txt")
        let displaced = root.appendingPathComponent("original.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("original".utf8)))

        let policy = FileSafetyPolicy(userHome: root, protectedRoots: [])
        let validated = try policy.validate(file)
        try FileManager.default.moveItem(at: file, to: displaced)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("replacement".utf8)))

        let expectation = expectation(description: "Reject changed file identity")
        var result: Result<URL?, Error>?
        TrashService(safetyPolicy: policy).moveToTrash(
            file,
            expectedIdentity: validated.identity
        ) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        switch result {
        case let .failure(error):
            XCTAssertEqual(error as? TrashServiceError, .targetChanged)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: displaced.path))
        case .success:
            XCTFail("A replacement file must never be moved to Trash")
        case .none:
            XCTFail("Trash service did not return a result")
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("PeashooterTrashTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
