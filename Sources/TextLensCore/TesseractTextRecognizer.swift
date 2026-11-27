import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TesseractTextRecognizer {
    static func recognize(_ image: CGImage, language: String?, correctsLanguage: Bool) throws -> String? {
        let fileManager = FileManager.default
        let prefixes = ["/opt/homebrew", "/usr/local"]
        for prefix in prefixes {
            let executable = URL(fileURLWithPath: "\(prefix)/bin/tesseract")
            let dataDirectory = URL(fileURLWithPath: "\(prefix)/share/tessdata", isDirectory: true)
            guard fileManager.isExecutableFile(atPath: executable.path),
                  let languages = recognitionLanguages(for: language, in: dataDirectory) else { continue }

            let inputURL = fileManager.temporaryDirectory.appendingPathComponent("TextLens-\(UUID()).png")
            defer { try? fileManager.removeItem(at: inputURL) }
            guard let destination = CGImageDestinationCreateWithURL(
                inputURL as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }

            let input = try FileHandle(forReadingFrom: inputURL)
            defer { try? input.close() }
            let output = Pipe()
            let process = Process()
            process.executableURL = executable
            process.arguments = ["stdin", "stdout", "--tessdata-dir", dataDirectory.path, "-l", languages]
            if Double(image.width) / Double(image.height) >= 2.5 {
                process.arguments?.append(contentsOf: ["--psm", "6"])
            }
            if !correctsLanguage {
                process.arguments?.append(contentsOf: ["-c", "load_system_dawg=0", "-c", "load_freq_dawg=0"])
            }
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }
            return VisionTextRecognizer.formatRecognizedLines(String(decoding: data, as: UTF8.self).components(separatedBy: .newlines))
        }
        return nil
    }

    private static func recognitionLanguages(for language: String?, in dataDirectory: URL) -> String? {
        let identifiers = language.map { [$0] } ?? Locale.preferredLanguages
        var installed: [String] = []
        for identifier in identifiers {
            let locale = Locale.Language(identifier: identifier)
            let code: String?
            if locale.languageCode?.identifier == "zh" {
                let script = Locale.Language(identifier: locale.maximalIdentifier).script?.identifier
                code = script == "Hant" ? "chi_tra" : "chi_sim"
            } else {
                code = locale.languageCode.flatMap { languageCodes[$0.identifier] }
            }
            if let code, hasModel(code, in: dataDirectory), !installed.contains(code) {
                installed.append(code)
            }
        }
        let usesLatinScript = language.map {
            Locale.Language(identifier: Locale.Language(identifier: $0).maximalIdentifier).script?.identifier == "Latn"
        } ?? true
        if usesLatinScript, hasModel("eng", in: dataDirectory), !installed.contains("eng") {
            installed.append("eng")
        }
        return installed.isEmpty ? nil : installed.joined(separator: "+")
    }

    private static func hasModel(_ code: String, in directory: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: directory.appendingPathComponent("\(code).traineddata").path)
    }

    private static let languageCodes = [
        "ar": "ara", "cs": "ces", "da": "dan", "de": "deu", "el": "ell", "en": "eng", "es": "spa",
        "fi": "fin", "fr": "fra", "he": "heb", "hi": "hin", "hu": "hun", "id": "ind", "it": "ita",
        "ja": "jpn", "ko": "kor", "ms": "msa", "nl": "nld", "no": "nor", "pl": "pol", "pt": "por",
        "ro": "ron", "ru": "rus", "sk": "slk", "sv": "swe", "th": "tha", "tr": "tur", "uk": "ukr",
        "vi": "vie",
    ]
}
