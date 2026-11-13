import Foundation
import XCTest
@testable import TextLensCore

final class TextCaptureServiceTests: XCTestCase {
    func testReturnsNilWhenSelectionIsCancelled() async throws {
        let service = TextCaptureService(
            screenCapturer: StubScreenCapture(data: nil),
            textRecognizer: StubTextRecognizer(text: "unused")
        )

        let result = try await service.captureText()
        XCTAssertNil(result)
    }

    func testTrimsRecognizedTextBeforeReturningCapture() async throws {
        let service = TextCaptureService(
            screenCapturer: StubScreenCapture(data: Data([1, 2, 3])),
            textRecognizer: StubTextRecognizer(text: "  recognized text\n")
        )

        let result = try await service.captureText()
        XCTAssertEqual(result?.text, "recognized text")
    }

    func testThrowsActionableErrorForWhitespaceOnlyRecognition() async {
        let service = TextCaptureService(
            screenCapturer: StubScreenCapture(data: Data([1])),
            textRecognizer: StubTextRecognizer(text: " \n  ")
        )

        do {
            _ = try await service.captureText()
            XCTFail("Expected empty OCR output to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No readable text"))
        }
    }
}

private struct StubScreenCapture: ScreenCapturing {
    let data: Data?

    func captureRegion() async throws -> Data? { data }
}

private struct StubTextRecognizer: TextRecognizing {
    let text: String

    func recognize(imageData: Data) async throws -> String { text }
}
