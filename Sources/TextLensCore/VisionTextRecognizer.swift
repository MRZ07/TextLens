import CoreImage
import CoreML
import Foundation
import ImageIO
import Vision

public struct VisionTextRecognizer: TextRecognizing {
    public enum Mode: String, CaseIterable, Sendable {
        case accurate
        case fast
    }

    private static let imageContext = CIContext()
    public static let supportedLanguages = supportedLanguages(for: .accurate)
    private static let fastLanguages = supportedLanguages(for: .fast)

    private let mode: Mode
    private let language: String?
    private let correctsLanguage: Bool

    public init(mode: Mode = .accurate, language: String? = nil, correctsLanguage: Bool = false) {
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

        let configuredLanguage = language.flatMap { Self.supportedLanguages.contains($0) ? $0 : nil }
        var fastResult: RecognitionResult?
        if mode == .fast, let configuredLanguage, Self.fastLanguages.contains(configuredLanguage) {
            fastResult = try? recognize(image, orientation: orientation, level: .fast, language: configuredLanguage)
            if let fastResult, fastResult.isReliable { return fastResult.text }
        }

        let primary: RecognitionResult
        do {
            primary = try recognize(image, orientation: orientation, language: configuredLanguage)
        } catch {
            return try recoverFromVisionError(
                error, image: image, orientation: orientation, language: configuredLanguage, fastResult: fastResult
            )
        }
        if primary.isReliable { return primary.text }

        var best = fastResult.map { primary.preferring($0) } ?? primary
        if configuredLanguage != nil,
           let detected = try? recognize(image, orientation: orientation, language: nil) {
            best = best.preferring(detected)
        }

        if let enhanced = Self.enhancedImage(image, orientation: orientation) {
            if let processed = try? recognize(enhanced, orientation: .up, language: configuredLanguage) {
                best = best.preferring(processed)
            }
            if !best.isReliable, configuredLanguage != nil,
               let detected = try? recognize(enhanced, orientation: .up, language: nil) {
                best = best.preferring(detected)
            }
        }
        return best.text
    }

    private func recoverFromVisionError(
        _ error: Error,
        image: CGImage,
        orientation: CGImagePropertyOrientation,
        language: String?,
        fastResult: RecognitionResult?
    ) throws -> String {
        let cpuResult = try? recognize(image, orientation: orientation, language: language, onCPU: true)
        if let cpuResult, cpuResult.isReliable { return cpuResult.text }

        let recovered = cpuResult.map { cpu in fastResult.map { cpu.preferring($0) } ?? cpu } ?? fastResult
        let upright = CIImage(cgImage: image).oriented(orientation)
        let fallbackImage = orientation == .up ? image : Self.imageContext.createCGImage(upright, from: upright.extent)
        if let fallbackImage,
           let text = try? TesseractTextRecognizer.recognize(
               fallbackImage, language: language, correctsLanguage: correctsLanguage
           ) {
            return text.isEmpty ? recovered?.text ?? "" : text
        }
        if let recovered { return recovered.text }
        throw VisionTextRecognitionError.failed(error.localizedDescription)
    }

    private func recognize(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel = .accurate,
        language: String?,
        onCPU: Bool = false
    ) throws -> RecognitionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = correctsLanguage
        if let language {
            request.recognitionLanguages = [language]
        } else {
            request.automaticallyDetectsLanguage = true
        }
        if onCPU {
            for (stage, devices) in try request.supportedComputeStageDevices {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }

        try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> RecognitionResult.Line? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognitionResult.Line(text: text, confidence: candidate.confidence)
        }
        return RecognitionResult(lines: lines)
    }

    private static func enhancedImage(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let upright = CIImage(cgImage: image).oriented(orientation)
        let longestSide = max(upright.extent.width, upright.extent.height)
        let scale = min(3, max(1, 1800 / longestSide))
        let scaled = upright.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
        let enhanced = scaled
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.35])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.35])
        return imageContext.createCGImage(enhanced, from: scaled.extent.integral)
    }

    struct RecognitionResult {
        struct Line {
            let text: String
            let confidence: VNConfidence
        }

        let lines: [Line]

        var text: String {
            VisionTextRecognizer.formatRecognizedLines(lines.map(\.text))
        }

        var isReliable: Bool {
            !lines.isEmpty && lines.allSatisfy { $0.confidence >= 0.8 }
        }

        private var score: Float {
            lines.reduce(0) { score, line in
                // Reward additional readable text while discounting long, low-confidence guesses.
                let length = Float(min(line.text.count, 40))
                return score + length * pow(line.confidence, 3)
            }
        }

        func preferring(_ other: Self) -> Self {
            other.score > score || (lines.isEmpty && !other.lines.isEmpty) ? other : self
        }
    }
}

private enum VisionTextRecognitionError: LocalizedError {
    case invalidImage
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The image could not be opened. Try a PNG, JPEG, or another format macOS can read."
        case .failed(let details): "The macOS text recognition engine could not process this image. \(details)"
        }
    }
}
