import Foundation

public struct TextCaptureService {
    private let screenCapturer: any ScreenCapturing
    private let textRecognizer: any TextRecognizing

    public init(screenCapturer: any ScreenCapturing, textRecognizer: any TextRecognizing) {
        self.screenCapturer = screenCapturer
        self.textRecognizer = textRecognizer
    }

    /// Returns nil when the user cancels the native region-selection interface.
    public func captureText() async throws -> CapturedText? {
        guard let imageData = try await screenCapturer.captureRegion() else {
            return nil
        }

        let capturedAt = Date()
        let recognizedText = try await textRecognizer.recognize(imageData: imageData)
        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TextCaptureServiceError.noTextRecognized
        }

        return CapturedText(text: text, capturedAt: capturedAt)
    }
}

private enum TextCaptureServiceError: LocalizedError {
    case noTextRecognized

    var errorDescription: String? {
        "No readable text was found in the selected region. Select an area with visible text and try again."
    }
}
