import Darwin
import Foundation

struct FileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct ValidatedFile: Equatable {
    let url: URL
    let displayName: String
    let byteCount: Int
    let identity: FileIdentity
}

enum FileSafetyError: LocalizedError, Equatable {
    case missingFile
    case outsideUserHome
    case protectedLocation
    case notRegularFile
    case symbolicLink
    case applicationBundle
    case unreadableMetadata

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "目标文件已经不存在。"
        case .outsideUserHome:
            return "第一版只能处理当前用户目录内的文件。"
        case .protectedLocation:
            return "这个位置受到保护，不能作为攻击目标。"
        case .notRegularFile:
            return "第一版只支持单个普通文件。"
        case .symbolicLink:
            return "为了避免误操作，第一版不处理符号链接。"
        case .applicationBundle:
            return "第一版不处理应用程序。"
        case .unreadableMetadata:
            return "无法安全读取这个文件的基本信息。"
        }
    }
}

struct FileSafetyPolicy {
    private let fileManager: FileManager
    private let userHome: URL
    private let protectedRoots: [URL]

    init(
        fileManager: FileManager = .default,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        protectedRoots: [URL] = [
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/usr", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true),
            URL(fileURLWithPath: "/sbin", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true)
        ]
    ) {
        self.fileManager = fileManager
        let normalizedHome = userHome.standardizedFileURL
        self.userHome = normalizedHome
        self.protectedRoots = (
            protectedRoots + [
                normalizedHome.appendingPathComponent("Library", isDirectory: true),
                normalizedHome.appendingPathComponent("Applications", isDirectory: true),
                normalizedHome.appendingPathComponent(".Trash", isDirectory: true)
            ]
        ).map(\.standardizedFileURL)
    }

    func validate(_ candidate: URL) throws -> ValidatedFile {
        let url = candidate.standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL

        guard fileManager.fileExists(atPath: url.path) else {
            throw FileSafetyError.missingFile
        }
        // Reject both a symbolic-link target and a regular file reached through
        // a symbolic-link directory. This prevents a path under Home from
        // escaping the allowed root after resolution.
        guard resolvedURL.path == url.path else {
            throw FileSafetyError.symbolicLink
        }
        guard isStrictDescendant(resolvedURL, of: userHome.resolvingSymlinksInPath()) else {
            throw FileSafetyError.outsideUserHome
        }
        guard !protectedRoots.contains(where: { isSameOrDescendant(resolvedURL, of: $0.resolvingSymlinksInPath()) }) else {
            throw FileSafetyError.protectedLocation
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isApplicationKey,
            .fileSizeKey,
            .nameKey
        ]

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: keys)
        } catch {
            throw FileSafetyError.unreadableMetadata
        }

        guard values.isSymbolicLink != true else {
            throw FileSafetyError.symbolicLink
        }
        guard values.isApplication != true,
              url.pathExtension.caseInsensitiveCompare("app") != .orderedSame
        else {
            throw FileSafetyError.applicationBundle
        }
        guard values.isRegularFile == true else {
            throw FileSafetyError.notRegularFile
        }

        var fileStatus = stat()
        guard lstat(url.path, &fileStatus) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG
        else {
            throw FileSafetyError.unreadableMetadata
        }

        return ValidatedFile(
            url: url,
            displayName: values.name ?? url.lastPathComponent,
            byteCount: values.fileSize ?? 0,
            identity: FileIdentity(
                device: UInt64(fileStatus.st_dev),
                inode: UInt64(fileStatus.st_ino)
            )
        )
    }

    private func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        candidate.path != root.path && isSameOrDescendant(candidate, of: root)
    }

    private func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }
}
