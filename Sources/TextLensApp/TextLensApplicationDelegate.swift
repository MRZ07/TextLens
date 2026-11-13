import AppKit

@MainActor
final class TextLensApplicationDelegate: NSObject, NSApplicationDelegate {
    let loginItemController = LoginItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItemController.refresh()
        guard loginItemController.shouldAskOnFirstRun else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open TextLens when you sign in?"
        alert.informativeText = "TextLens will be ready in the menu bar when you sign in. You can change this later in Settings → General."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not now")

        let enable = alert.runModal() == .alertFirstButtonReturn
        loginItemController.respondToFirstRunPrompt(enable: enable)

        guard enable else { return }
        presentEnableResult()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItemController.refresh()
    }

    private func presentEnableResult() {
        switch loginItemController.state {
        case .enabled:
            return
        case .requiresApproval:
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Approve TextLens in Login Items"
            alert.informativeText = loginItemController.errorMessage
                ?? "TextLens is waiting for approval in System Settings. It won't start at login until you allow it."
            alert.addButton(withTitle: "Open Login Items Settings…")
            alert.addButton(withTitle: "Not now")
            if alert.runModal() == .alertFirstButtonReturn {
                loginItemController.openSystemSettings()
            }
        case .notRegistered, .unavailable:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't enable launch at login"
            alert.informativeText = loginItemController.errorMessage
                ?? "TextLens wasn't added to Login Items. You can try again in Settings → General."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
