import XCTest
@testable import TextLensCore

final class VisionTextRecognizerTests: XCTestCase {
    func testPreferredLanguageMatchesSupportedRegionOrFallsBack() {
        XCTAssertEqual(VisionTextRecognizer.preferredLanguage(in: ["de-AT", "en-US"]), "de-DE")
        XCTAssertEqual(VisionTextRecognizer.preferredLanguage(in: ["zz-ZZ"]), "en-US")
    }

    func testAConfidentFirstLineDoesNotMakeAnUncertainPassReliable() {
        let result = VisionTextRecognizer.RecognitionResult(lines: [
            .init(text: "Recognized heading", confidence: 0.98),
            .init(text: "Unclear detail", confidence: 0.6),
        ])

        XCTAssertFalse(result.isReliable)
    }

    func testRetryPrefersReadableCoverageOverTheHighestSingleConfidence() {
        let partial = VisionTextRecognizer.RecognitionResult(lines: [
            .init(text: "Heading", confidence: 0.99),
        ])
        let complete = VisionTextRecognizer.RecognitionResult(lines: [
            .init(text: "Heading", confidence: 0.91),
            .init(text: "A second line", confidence: 0.88),
        ])
        let noise = VisionTextRecognizer.RecognitionResult(lines: [
            .init(text: "A long low-confidence string of characters", confidence: 0.2),
        ])

        XCTAssertEqual(partial.preferring(complete).text, "Heading\nA second line")
        XCTAssertEqual(complete.preferring(noise).text, complete.text)
    }

    func testFormattingTrimsLinesAndDropsWhitespaceOnlyResults() {
        let formatted = VisionTextRecognizer.formatRecognizedLines([
            "  first line  ",
            " \n ",
            "second line\t",
        ])

        XCTAssertEqual(formatted, "first line\nsecond line")
    }
}
