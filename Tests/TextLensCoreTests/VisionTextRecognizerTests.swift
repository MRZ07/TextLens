import XCTest
@testable import TextLensCore

final class VisionTextRecognizerTests: XCTestCase {
    func testFormattingTrimsLinesAndDropsWhitespaceOnlyResults() {
        let formatted = VisionTextRecognizer.formatRecognizedLines([
            "  first line  ",
            " \n ",
            "second line\t",
        ])

        XCTAssertEqual(formatted, "first line\nsecond line")
    }
}
