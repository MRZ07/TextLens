import Foundation
import OSLog
import UserNotifications

@MainActor
protocol CaptureNotificationSending {
    func notifySuccess(
        recognizedText: String,
        copiedToClipboard: Bool,
        playSound: Bool
    ) async
}

@MainActor
final class CaptureNotificationService: NSObject, CaptureNotificationSending, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TextLensApp",
        category: "CaptureNotifications"
    )
    private var requestedAuthorizationOptions = false

    static let maximumPreviewLength = 300

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func notifySuccess(
        recognizedText: String,
        copiedToClipboard: Bool,
        playSound: Bool
    ) async {
        guard let settings = await settingsForDelivery() else { return }

        let content = Self.notificationContent(
            recognizedText: recognizedText,
            copiedToClipboard: copiedToClipboard,
            playSound: playSound,
            systemSoundSetting: settings.soundSetting
        )

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            logFailure(operation: "delivery", error: error)
        }
    }

    static func previewBody(for recognizedText: String) -> String {
        guard recognizedText.count > maximumPreviewLength else { return recognizedText }
        return String(recognizedText.prefix(maximumPreviewLength)) + "…"
    }

    static func notificationContent(
        recognizedText: String,
        copiedToClipboard: Bool,
        playSound: Bool,
        systemSoundSetting: UNNotificationSetting
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = copiedToClipboard ? "Text copied" : "Text recognized"
        content.body = previewBody(for: recognizedText)
        content.sound = playSound && systemSoundSetting == .enabled ? .default : nil
        return content
    }

    nonisolated static func foregroundPresentationOptions(
        hasSound: Bool
    ) -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if hasSound { options.insert(.sound) }
        return options
    }

    private func settingsForDelivery() async -> UNNotificationSettings? {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus != .denied else { return nil }

        if !requestedAuthorizationOptions {
            requestedAuthorizationOptions = true
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logFailure(operation: "authorization request", error: error)
            }
        }

        let currentSettings = await center.notificationSettings()
        return Self.allowsNotifications(currentSettings.authorizationStatus) ? currentSettings : nil
    }

    private static func allowsNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func logFailure(operation: String, error: Error) {
        let details = error as NSError
        logger.error(
            "Notification \(operation, privacy: .public) failed (domain: \(details.domain, privacy: .public), code: \(details.code, privacy: .public))"
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            Self.foregroundPresentationOptions(hasSound: notification.request.content.sound != nil)
        )
    }
}
