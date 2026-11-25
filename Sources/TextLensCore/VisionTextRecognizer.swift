import CoreImage
import Foundation
import ImageIO
import Vision

public struct VisionTextRecognizer: TextRecognizing {
    public enum Mode: String, CaseIterable, Sendable {
        case accurate
        case fast
    }

    private static let confident: VNConfidence = 0.75
    private static let imageContext = CIContext()
    public static let supportedLanguages = supportedLanguages(for: .accurate)
    private static let fastLanguages = supportedLanguages(for: .fast)

    private let mode: Mode
    private let language: String?
    private let correctsLanguage: Bool

    public init(mode: Mode = .accurate, language: String? = "en-US", correctsLanguage: Bool = false) {
        self.mode = mode
        self.language = language
        self.correctsLanguage = correctsLanguage
    }

    public static func preferredLanguage(in languages: [String] = Locale.preferredLanguages) -> String {
        for identifier in languages {
            let language = Locale.Language(identifier: Locale.Language(identifier: identifier).maximalIdentifier)
            if let match = supportedLanguages.first(where: {
                Locale.Language(identifier: $0).maximalIdentifier == language.maximalIdentifier
            }) ?? supportedLanguages.first(where: {
                let candidate = Locale.Language(identifier: Locale.Language(identifier: $0).maximalIdentifier)
                return candidate.languageCode == language.languageCode && candidate.script == language.script
            }) {
                return match
            }
        }
        return "en-US"
    }

    private static func supportedLanguages(for level: VNRequestTextRecognitionLevel) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    public func recognize(imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try recognizeSynchronously(imageData: imageData)
        }.value
    }

    static func formatRecognizedLines(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func recognizeSynchronously(imageData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionTextRecognitionError.invalidImage
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up

        do {
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
            // Vision's fast mode supports fewer scripts. Use it only for a known supported language.
            if mode == .fast, let language, Self.fastLanguages.contains(language) {
                let quick = try? candidates(from: handler, request: makeRequest(level: .fast))
                if let quick, !quick.isEmpty, quick.allSatisfy({ $0.confidence >= Self.confident }) {
                    return Self.formatRecognizedLines(quick.map(\.string))
                }
            }

            let accurate = try candidates(from: handler, request: makeRequest(level: .accurate))
            if accurate.contains(where: { $0.confidence >= Self.confident }) {
                return Self.formatRecognizedLines(accurate.map(\.string))
            }

            if let enhanced = Self.enhancedImage(image, orientation: orientation),
               let retry = try? candidates(
                   from: VNImageRequestHandler(cgImage: enhanced),
                   request: makeRequest(level: .accurate)
               ), bestConfidence(in: retry) > bestConfidence(in: accurate) {
                return Self.formatRecognizedLines(retry.map(\.string))
            }
            return Self.formatRecognizedLines(accurate.map(\.string))
        } catch {
            throw VisionTextRecognitionError.failed(error.localizedDescription)
        }
    }

    private func makeRequest(level: VNRequestTextRecognitionLevel) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = correctsLanguage
        let supportedLanguages = level == .fast ? Self.fastLanguages : Self.supportedLanguages
        if let language, supportedLanguages.contains(language) {
            request.recognitionLanguages = [language]
        } else {
            request.automaticallyDetectsLanguage = true
        }
        return request
    }

    private func candidates(
        from handler: VNImageRequestHandler,
        request: VNRecognizeTextRequest
    ) throws -> [VNRecognizedText] {
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return candidate
        }
    }

    private func bestConfidence(in candidates: [VNRecognizedText]) -> VNConfidence {
        candidates.map(\.confidence).max() ?? 0
    }

    private static func enhancedImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let upright = CIImage(cgImage: image).oriented(orientation)
        let longestSide = max(upright.extent.width, upright.extent.height)
        let scale = longestSide > 2400 ? 2400 / longestSide : min(2, max(1, 1600 / longestSide))
        let enhanced = upright
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.4])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.45])
        return imageContext.createCGImage(enhanced, from: enhanced.extent)
    }
}

private enum VisionTextRecognitionError: LocalizedError {
    case invalidImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The image could not be opened. Try a PNG, JPEG, or another format macOS can read."
        case .failed(let details): "Vision could not read this image. \(details)"
        }
    }
}
