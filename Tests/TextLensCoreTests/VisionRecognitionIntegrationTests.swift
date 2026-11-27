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

    func testRecognizesTightDarkCropInFastMode() async throws {
        let expectedText = "Build 4827"
        let imageData = try renderedCoreTextImage(
            expectedText,
            width: 162,
            height: 34,
            fontSize: 22,
            background: 0.10,
            foreground: 0.83
        )

        let recognizedText = try await VisionTextRecognizer(mode: .fast, language: "en-US")
            .recognize(imageData: imageData)

        XCTAssertTrue(recognizedText.localizedCaseInsensitiveContains(expectedText), recognizedText)
    }

    func testBlankImageDoesNotProduceText() async throws {
        let imageData = try renderedCoreTextImage("", width: 240, height: 90)

        let recognizedText = try await VisionTextRecognizer().recognize(imageData: imageData)

        XCTAssertTrue(recognizedText.isEmpty)
    }

    private func renderedCoreTextImage(
        _ text: String,
        width: Int = 1000,
        height: Int = 180,
        fontSize: CGFloat = 54,
        background: CGFloat = 1,
        foreground: CGFloat = 0
    ) throws -> Data {
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
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let systemFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let font = CTFontCreateWithName(systemFont.fontName as CFString, fontSize, nil)
        let color = CGColor(gray: foreground, alpha: 1)
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        context.textPosition = CGPoint(x: fontSize / 2, y: (CGFloat(height) - fontSize) / 2)
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
