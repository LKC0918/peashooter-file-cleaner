import Foundation

protocol TrashServicing {
    func moveToTrash(
        _ fileURL: URL,
        expectedIdentity: FileIdentity,
        completion: @escaping (Result<URL?, Error>) -> Void
    )
}

enum TrashServiceError: LocalizedError, Equatable {
    case targetChanged
    case coordinationFailed

    var errorDescription: String? {
        switch self {
        case .targetChanged:
            return "目标文件在确认后发生了变化，已停止操作。"
        case .coordinationFailed:
            return "无法安全协调这个文件的移动操作。"
        }
    }
}

final class TrashService: TrashServicing {
    private let fileManager: FileManager
    private let safetyPolicy: FileSafetyPolicy
    private let queue: DispatchQueue

    init(
        fileManager: FileManager = .default,
        safetyPolicy: FileSafetyPolicy = FileSafetyPolicy(),
        queue: DispatchQueue = DispatchQueue(label: "com.peashooter.file-cleaner.trash", qos: .userInitiated)
    ) {
        self.fileManager = fileManager
        self.safetyPolicy = safetyPolicy
        self.queue = queue
    }

    func moveToTrash(
        _ fileURL: URL,
        expectedIdentity: FileIdentity,
        completion: @escaping (Result<URL?, Error>) -> Void
    ) {
        queue.async { [fileManager, safetyPolicy] in
            var coordinationError: NSError?
            var coordinatedResult: Result<URL?, Error>?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: fileURL,
                options: .forMoving,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    // Validate inside the coordinated background operation, as
                    // close as possible to the system Trash call. This prevents the prior
                    // main-thread-to-queue gap from accepting a replacement at
                    // the same pathname.
                    let currentFile = try safetyPolicy.validate(coordinatedURL)
                    guard currentFile.identity == expectedIdentity else {
                        throw TrashServiceError.targetChanged
                    }

                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: coordinatedURL, resultingItemURL: &resultingURL)
                    coordinatedResult = .success(resultingURL as URL?)
                } catch {
                    coordinatedResult = .failure(error)
                }
            }

            if let coordinatedResult {
                completion(coordinatedResult)
            } else if let coordinationError {
                completion(.failure(coordinationError))
            } else {
                completion(.failure(TrashServiceError.coordinationFailed))
            }
        }
    }
}
