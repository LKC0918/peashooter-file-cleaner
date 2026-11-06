import CoreGraphics
import Foundation

enum FinderPointSource: String, Equatable {
    case demo
    case finderSyncContext
    case recentFinderRightClick
    case menuPoint

    var permitsVisualFallback: Bool {
        switch self {
        case .finderSyncContext, .recentFinderRightClick, .demo:
            return true
        case .menuPoint:
            return false
        }
    }
}

struct SummonRequest: Equatable {
    let fileURL: URL?
    let globalPoint: CGPoint
    let pointSource: FinderPointSource
    let isDemo: Bool

    static func demo(at point: CGPoint) -> SummonRequest {
        SummonRequest(fileURL: nil, globalPoint: point, pointSource: .demo, isDemo: true)
    }
}

enum SummonURLCodec {
    static let scheme = "peashooter-cleaner"
    static let host = "summon"
    static let demoHost = "demo"

    static func makeURL(fileURL: URL, globalPoint: CGPoint) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "file", value: fileURL.absoluteString),
            URLQueryItem(name: "x", value: String(Double(globalPoint.x))),
            URLQueryItem(name: "y", value: String(Double(globalPoint.y)))
        ]
        return components.url
    }

    static func makeDemoURL(globalPoint: CGPoint) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = demoHost
        components.queryItems = [
            URLQueryItem(name: "x", value: String(Double(globalPoint.x))),
            URLQueryItem(name: "y", value: String(Double(globalPoint.y)))
        ]
        return components.url
    }

    static func parse(_ url: URL) -> SummonRequest? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        // Do not use Dictionary(uniqueKeysWithValues:): another process can invoke
        // a registered URL scheme and repeated query keys must not crash the host.
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value
        }

        guard let xValue = query["x"],
              let yValue = query["y"],
              let x = Double(xValue),
              let y = Double(yValue),
              x.isFinite,
              y.isFinite
        else {
            return nil
        }

        let point = CGPoint(x: x, y: y)

        if url.host == demoHost {
            return .demo(at: point)
        }

        guard url.host == host,
              let fileValue = query["file"],
              let fileURL = URL(string: fileValue),
              fileURL.isFileURL
        else {
            return nil
        }

        return SummonRequest(
            fileURL: fileURL,
            globalPoint: point,
            pointSource: .finderSyncContext,
            isDemo: false
        )
    }
}
