import Foundation
import Vision

public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognize(imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.recognizeSynchronously(imageData: imageData)
        }.value
    }

    static func formatRecognizedLines(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func recognizeSynchronously(imageData: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(data: imageData).perform([request])
        } catch {
            throw VisionTextRecognitionError.failed(error.localizedDescription)
        }

        let lines = (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        return formatRecognizedLines(lines)
    }
}

private enum VisionTextRecognitionError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        guard case .failed(let details) = self else { return nil }
        return "On-device text recognition could not read the selected screenshot. Select a valid region and try again. Details: \(details)"
    }
}
