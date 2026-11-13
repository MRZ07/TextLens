import Foundation

public final class CaptureHistoryStore: @unchecked Sendable {
    public static let maximumEntryCount = 100

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func load() throws -> [CapturedText] {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    @discardableResult
    public func append(_ item: CapturedText) throws -> [CapturedText] {
        lock.lock()
        defer { lock.unlock() }

        var history = try loadUnlocked()
        history.append(item)
        if history.count > Self.maximumEntryCount {
            history.removeFirst(history.count - Self.maximumEntryCount)
        }
        try saveUnlocked(history)
        return history
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw CaptureHistoryStoreError.couldNotClear(fileURL, error.localizedDescription)
        }
    }

    private func loadUnlocked() throws -> [CapturedText] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let stored: [CapturedText]
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            stored = try decoder.decode([CapturedText].self, from: data)
        } catch {
            throw CaptureHistoryStoreError.couldNotLoad(fileURL, error.localizedDescription)
        }

        let bounded = Array(stored.suffix(Self.maximumEntryCount))
        if bounded.count != stored.count {
            try saveUnlocked(bounded)
        }
        return bounded
    }

    private func saveUnlocked(_ history: [CapturedText]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw CaptureHistoryStoreError.couldNotSave(fileURL, error.localizedDescription)
        }
    }

    private static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return supportDirectory
            .appendingPathComponent("TextLens", isDirectory: true)
            .appendingPathComponent("capture-history.json", isDirectory: false)
    }
}

private enum CaptureHistoryStoreError: LocalizedError {
    case couldNotLoad(URL, String)
    case couldNotSave(URL, String)
    case couldNotClear(URL, String)

    var errorDescription: String? {
        switch self {
        case .couldNotLoad(let url, let details):
            return "Could not load capture history from \(url.path). The history file may be damaged or inaccessible. Details: \(details)"
        case .couldNotSave(let url, let details):
            return "Could not save capture history to \(url.path). Check available disk space and file permissions. Details: \(details)"
        case .couldNotClear(let url, let details):
            return "Could not clear capture history at \(url.path). Check file permissions and try again. Details: \(details)"
        }
    }
}
