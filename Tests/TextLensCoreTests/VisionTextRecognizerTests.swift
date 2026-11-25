import XCTest
@testable import TextLensCore

final class VisionTextRecognizerTests: XCTestCase {
    func testPreferredLanguageMatchesSupportedRegionOrFallsBack() {
        XCTAssertEqual(VisionTextRecognizer.preferredLanguage(in: ["de-AT", "en-US"]), "de-DE")
        XCTAssertEqual(VisionTextRecognizer.preferredLanguage(in: ["zz-ZZ"]), "en-US")
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
