import Foundation
import OSLog

enum AppLogger {
    static let lifecycle = Logger(subsystem: "com.peashooter.file-cleaner", category: "lifecycle")
    static let fileOperation = Logger(subsystem: "com.peashooter.file-cleaner", category: "file-operation")
    static let finderExtension = Logger(subsystem: "com.peashooter.file-cleaner.finder-extension", category: "finder")
}
