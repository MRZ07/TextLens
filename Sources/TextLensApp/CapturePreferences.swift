import Combine
import Foundation
import TextLensCore

@MainActor
final class CapturePreferences: ObservableObject {
    static let systemLanguage = "system"
    private let defaults: UserDefaults

    @Published var recognitionMode: VisionTextRecognizer.Mode {
        didSet { defaults.set(recognitionMode.rawValue, forKey: Self.recognitionModeKey) }
    }

    @Published var recognitionLanguage: String {
        didSet { defaults.set(recognitionLanguage, forKey: Self.recognitionLanguageKey) }
    }

    @Published var correctsLanguage: Bool {
        didSet { defaults.set(correctsLanguage, forKey: Self.correctsLanguageKey) }
    }

    @Published var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: Self.autoCopyKey) }
    }

    @Published var notifyOnSuccess: Bool {
        didSet { defaults.set(notifyOnSuccess, forKey: Self.notifyOnSuccessKey) }
    }

    @Published var playNotificationSound: Bool {
        didSet { defaults.set(playNotificationSound, forKey: Self.playNotificationSoundKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recognitionMode = defaults.string(forKey: Self.recognitionModeKey)
            .flatMap(VisionTextRecognizer.Mode.init(rawValue:)) ?? .accurate
        recognitionLanguage = defaults.string(forKey: Self.recognitionLanguageKey) ?? Self.systemLanguage
        correctsLanguage = defaults.bool(forKey: Self.correctsLanguageKey)
        autoCopy = defaults.object(forKey: Self.autoCopyKey) as? Bool ?? true
        notifyOnSuccess = defaults.object(forKey: Self.notifyOnSuccessKey) as? Bool ?? true
        playNotificationSound = defaults.object(forKey: Self.playNotificationSoundKey) as? Bool ?? true
    }

    var preferredRecognitionLanguage: String? {
        switch recognitionLanguage {
        case Self.systemLanguage: VisionTextRecognizer.preferredLanguage()
        case "": nil
        default: recognitionLanguage
        }
    }

    private static let recognitionModeKey = "capture.recognitionMode"
    private static let recognitionLanguageKey = "capture.recognitionLanguage"
    private static let correctsLanguageKey = "capture.correctsLanguage"
    private static let autoCopyKey = "capture.autoCopy"
    private static let notifyOnSuccessKey = "capture.notifyOnSuccess"
    private static let playNotificationSoundKey = "capture.playNotificationSound"
}
