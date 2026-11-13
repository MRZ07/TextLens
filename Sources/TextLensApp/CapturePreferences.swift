import Combine
import Foundation

@MainActor
final class CapturePreferences: ObservableObject {
    private let defaults: UserDefaults

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
        autoCopy = defaults.object(forKey: Self.autoCopyKey) as? Bool ?? true
        notifyOnSuccess = defaults.object(forKey: Self.notifyOnSuccessKey) as? Bool ?? true
        playNotificationSound = defaults.object(forKey: Self.playNotificationSoundKey) as? Bool ?? true
    }

    private static let autoCopyKey = "capture.autoCopy"
    private static let notifyOnSuccessKey = "capture.notifyOnSuccess"
    private static let playNotificationSoundKey = "capture.playNotificationSound"
}
