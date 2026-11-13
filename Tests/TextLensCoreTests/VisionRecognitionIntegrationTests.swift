import AppKit
import CoreText
import XCTest
@testable import TextLensCore

final class VisionRecognitionIntegrationTests: XCTestCase {
    func testRecognizesControlledEnglishTextRenderedWithCoreText() async throws {
        let expectedText = "TextLens OCR Check 4827"
        let imageData = try renderedCoreTextImage(expectedText)

        let recognizedText = try await VisionTextRecognizer().recognize(imageData: imageData)

        XCTAssertTrue(
            recognizedText.localizedCaseInsensitiveContains(expectedText),
            "Vision did not recognize the controlled upright CoreText image"
        )
    }

    private func renderedCoreTextImage(_ text: String) throws -> Data {
        let width = 1000
        let height = 180
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageRenderError.couldNotCreatePNG
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let systemFont = NSFont.systemFont(ofSize: 54, weight: .medium)
        let font = CTFontCreateWithName(systemFont.fontName as CFString, 54, nil)
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0, 0, 0, 1])!
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        context.textPosition = CGPoint(x: 28, y: 64)
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else {
            throw ImageRenderError.couldNotCreatePNG
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageRenderError.couldNotCreatePNG
        }
        return png
    }
}

private enum ImageRenderError: Error {
    case couldNotCreatePNG
}
