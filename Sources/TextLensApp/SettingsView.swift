import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject var loginItemController: LoginItemController
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingClear = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }

            shortcutSettings
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            historyAndPrivacySettings
                .tabItem { Label("History & Privacy", systemImage: "lock.shield") }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 500)
        .onAppear {
            loginItemController.refresh()
        }
        .confirmationDialog(
            "Clear all captures?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                guard !model.isWorking else { return }
                model.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes saved text from this Mac. It can't be undone.")
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TextLens")
                            .font(.title2.weight(.semibold))
                        Text("Version \(appVersion)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Select text on your screen and paste it into any app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button("About TextLens…") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [:])
                }
            } header: {
                Text("About")
            }

            Section("Quick access") {
                Button {
                    model.capture()
                } label: {
                    Label("Capture text now", systemImage: "viewfinder")
                }
                .disabled(model.isWorking)

                Button {
                    openWindow(id: "capture-history")
                } label: {
                    Label("Open Capture History…", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("Startup") {
                Toggle(isOn: loginAtStartupBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open TextLens at login")
                        Text(loginItemDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(loginItemUnavailable)

                if loginItemRequiresApproval {
                    Button("Open Login Items Settings…") {
                        loginItemController.openSystemSettings()
                    }
                }

                if let errorMessage = loginItemController.errorMessage {
                    Label {
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                }
            }

            Section("After processing") {
                PreferenceToggle(
                    preferences: model.preferences,
                    title: "Automatically copy recognized text",
                    detail: "When off, recognized text remains in Capture History.",
                    keyPath: \.autoCopy
                )

                PreferenceToggle(
                    preferences: model.preferences,
                    title: "Show a notification after successful processing",
                    detail: "Notifications include a short preview of recognized text, which macOS may show on screen or on the Lock Screen. They require notification permission; Focus may suppress them.",
                    keyPath: \.notifyOnSuccess
                )

                PreferenceToggle(
                    preferences: model.preferences,
                    title: "Play a sound with notifications",
                    detail: "macOS notification settings and Focus may still silence the sound.",
                    keyPath: \.playNotificationSound,
                    disabledWhenNotificationsOff: true
                )
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private var shortcutSettings: some View {
        Form {
            Section("Capture with line breaks") {
                KeyboardShortcuts.Recorder("Shortcut", name: .captureText)

                Text("Keeps the line breaks from the selected area.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Capture without line breaks") {
                KeyboardShortcuts.Recorder("Shortcut", name: .captureTextWithoutLineBreaks)

                Text("Joins the recognized text into one line. Set or clear this shortcut independently.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private var historyAndPrivacySettings: some View {
        Form {
            Section("Local history") {
                LabeledContent("Saved captures", value: "\(model.history.count)")

                Text("The newest 100 captures are stored on this Mac. You can clear them at any time. Screen selections are processed locally and aren't uploaded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Clear Local History…", role: .destructive) {
                    confirmingClear = true
                }
                .disabled(model.history.isEmpty || model.isWorking)
            }

            Section("Screen recording access") {
                Text("If macOS denies a capture, allow TextLens in System Settings under Privacy & Security → Screen & System Audio Recording, then try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Screen & System Audio Recording Settings…", systemImage: "arrow.up.forward.app") {
                    openScreenRecordingSettings()
                }
            }
        }
        .formStyle(.grouped)
        .scenePadding()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var loginAtStartupBinding: Binding<Bool> {
        Binding(
            get: { loginItemController.isRegistered },
            set: { enabled in
                loginItemController.clearError()
                loginItemController.setEnabled(enabled)
            }
        )
    }

    private var loginItemUnavailable: Bool {
        if case .unavailable = loginItemController.state {
            return true
        }
        return false
    }

    private var loginItemRequiresApproval: Bool {
        if case .requiresApproval = loginItemController.state {
            return true
        }
        return false
    }

    private var loginItemDescription: String {
        switch loginItemController.state {
        case .notRegistered:
            "Enable this to make TextLens available in the menu bar after you sign in."
        case .enabled:
            "TextLens opens automatically when you sign in."
        case .requiresApproval:
            "Waiting for approval in System Settings. TextLens won't start at login until allowed."
        case .unavailable:
            "Launch at login is unavailable for this installation."
        }
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct PreferenceToggle: View {
    @ObservedObject var preferences: CapturePreferences
    let title: String
    let detail: String
    let keyPath: ReferenceWritableKeyPath<CapturePreferences, Bool>
    var disabledWhenNotificationsOff = false

    var body: some View {
        Toggle(isOn: preferenceBinding) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(disabledWhenNotificationsOff && !preferences.notifyOnSuccess)
    }

    private var preferenceBinding: Binding<Bool> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0 }
        )
    }
}
