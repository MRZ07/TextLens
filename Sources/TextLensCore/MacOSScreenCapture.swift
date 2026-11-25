import CoreGraphics
import Foundation

public struct ScreenRecordingAccessRequired: LocalizedError {
    public init() {}

    public var errorDescription: String? {
        "Allow TextLens in Screen & System Audio Recording, then reopen TextLens and try again."
    }
}

public struct MacOSScreenCapture: ScreenCapturing {
    public init() {}

    public func captureRegion() async throws -> Data? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextLens-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-tpng", outputURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        let execution = ScreenCaptureExecution(process: process)

        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                let status = try await Task.detached(priority: .userInitiated) {
                    try execution.run()
                }.value
                try Task.checkCancellation()
                return status
            } onCancel: {
                execution.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MacOSScreenCaptureError.couldNotStart(error.localizedDescription)
        }

        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard status == 0 else {
            if !CGPreflightScreenCaptureAccess() {
                throw ScreenRecordingAccessRequired()
            }
            throw MacOSScreenCaptureError.failed(status: status, details: errorOutput)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            // screencapture exits successfully without producing a file when the user cancels.
            return nil
        }

        do {
            return try Data(contentsOf: outputURL)
        } catch {
            throw MacOSScreenCaptureError.couldNotReadImage(error.localizedDescription)
        }
    }
}

private final class ScreenCaptureExecution: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var isCancelled = false

    init(process: Process) {
        self.process = process
    }

    func run() throws -> Int32 {
        lock.lock()
        let cancelledBeforeStart = isCancelled
        lock.unlock()
        if cancelledBeforeStart {
            throw CancellationError()
        }

        try process.run()

        lock.lock()
        let shouldTerminate = isCancelled
        lock.unlock()
        if shouldTerminate && process.isRunning {
            process.terminate()
        }

        process.waitUntilExit()
        return process.terminationStatus
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let shouldTerminate = process.isRunning
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }
}

private enum MacOSScreenCaptureError: LocalizedError {
    case couldNotStart(String)
    case failed(status: Int32, details: String)
    case couldNotReadImage(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let details):
            return "Could not start macOS screen capture. Confirm /usr/sbin/screencapture is available and try again. Details: \(details)"
        case .failed(let status, let details):
            let detailText = details.isEmpty ? "" : " Details: \(details)"
            return "macOS screen capture failed (exit code \(status)).\(detailText)"
        case .couldNotReadImage(let details):
            return "The selected screenshot was created but could not be read. Try capturing the region again. Details: \(details)"
        }
    }
}
