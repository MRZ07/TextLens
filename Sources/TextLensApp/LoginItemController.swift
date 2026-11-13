import Combine
import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LoginItemServicing {
    var status: LoginItemServiceStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

enum LoginItemServiceStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

@MainActor
final class SystemLoginItemService: LoginItemServicing {
    var status: LoginItemServiceStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var errorMessage: String?

    private let service: any LoginItemServicing
    private let defaults: UserDefaults

    var isRegistered: Bool {
        state == .enabled || state == .requiresApproval
    }

    var shouldAskOnFirstRun: Bool {
        defaults.object(forKey: Self.firstRunPromptAnsweredKey) == nil && state == .notRegistered
    }

    init(
        service: (any LoginItemServicing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service ?? SystemLoginItemService()
        self.defaults = defaults
        state = .unavailable
        errorMessage = nil
        refresh()
    }

    func refresh() {
        state = Self.state(for: service.status)

        if isRegistered {
            markFirstRunPromptAnswered()
        }
    }

    private static func state(for serviceStatus: LoginItemServiceStatus) -> LoginItemState {
        switch serviceStatus {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            // Allow opt-in; register() reports whether the main app can be added.
            .notRegistered
        case .unknown:
            .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) {
        markFirstRunPromptAnswered()
        performSetEnabled(enabled)
    }

    func respondToFirstRunPrompt(enable: Bool) {
        markFirstRunPromptAnswered()
        if enable {
            performSetEnabled(true)
        } else {
            refresh()
        }
    }

    func openSystemSettings() {
        service.openSystemSettingsLoginItems()
    }

    func clearError() {
        errorMessage = nil
    }

    private func performSetEnabled(_ enabled: Bool) {
        refresh()
        guard state != .unavailable else {
            errorMessage = Self.unavailableMessage
            return
        }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            let action = enabled ? "enable" : "disable"
            errorMessage = "Could not \(action) launch at login: \(error.localizedDescription) Open System Settings → General → Login Items to review TextLens’ login-item permission."
        }

        refresh()
    }

    private func markFirstRunPromptAnswered() {
        defaults.set(true, forKey: Self.firstRunPromptAnsweredKey)
    }

    private static let firstRunPromptAnsweredKey = "loginItem.firstRunPromptAnswered"
    private static let unavailableMessage = "macOS returned an unknown login-item status for TextLens. Update macOS and restart TextLens before trying again."
}
