import AppKit
import KeyboardShortcuts
import SwiftUI
import TextLensCore

struct SettingsView: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject var preferences: CapturePreferences
    @ObservedObject var loginItemController: LoginItemController
    @Environment(\.openWindow) private var openWindow
    @State private var selection: SettingsSection? = .capture
    @State private var confirmingClear = false

    private var section: SettingsSection { selection ?? .capture }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 172)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.rawValue)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(section.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                Form {
                    switch section {
                    case .capture: captureSettings
                    case .shortcuts: shortcutSettings
                    case .general: generalSettings
                    case .privacy: privacySettings
                    }
                }
                .formStyle(.grouped)
                .id(section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 660, idealWidth: 710, minHeight: 460, idealHeight: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loginItemController.refresh() }
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
            Text("This permanently removes saved text from this Mac.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.rawValue)
                } icon: {
                    Image(systemName: section.symbol)
                        .foregroundStyle(.secondary)
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TextLens")
                        .font(.subheadline.weight(.semibold))
                    if let appVersion {
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .accessibilityElement(children: .combine)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var captureSettings: some View {
        Section("Recognition") {
            Picker("Text language", selection: $preferences.recognitionLanguage) {
                Text("System language").tag(CapturePreferences.systemLanguage)
                Text("Detect automatically").tag("")
                ForEach(Self.languageOptions, id: \.self) { language in
                    Text(Self.languageName(language)).tag(language)
                }
                if !preferences.recognitionLanguage.isEmpty,
                   preferences.recognitionLanguage != CapturePreferences.systemLanguage,
                   !Self.languageOptions.contains(preferences.recognitionLanguage) {
                    Text(Self.languageName(preferences.recognitionLanguage)).tag(preferences.recognitionLanguage)
                }
            }
            Picker("Recognition mode", selection: $preferences.recognitionMode) {
                Text("Accurate").tag(VisionTextRecognizer.Mode.accurate)
                Text("Fast").tag(VisionTextRecognizer.Mode.fast)
            }

            Text(recognitionHelp)
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(isOn: $preferences.correctsLanguage) {
                SettingsLabel(
                    title: "Correct spelling",
                    detail: "Uses Vision’s language correction. Leave this off for names, codes, and exact spelling."
                )
            }
        }

        Section("Clipboard") {
            Toggle(isOn: $preferences.autoCopy) {
                SettingsLabel(
                    title: "Copy text automatically",
                    detail: "When off, use Capture History to review and copy text."
                )
            }
        }
    }

    private var recognitionHelp: String {
        if preferences.recognitionLanguage.isEmpty {
            return "Automatic language detection uses Accurate mode and may take longer for mixed text."
        }
        if preferences.recognitionMode == .accurate {
            return "Best for small text, images, and video. TextLens retries weak results with enhanced contrast."
        }
        return "Tries a quicker pass for clear text in supported languages. Difficult text uses Accurate mode."
    }

    @ViewBuilder
    private var shortcutSettings: some View {
        Section("Global shortcuts") {
            KeyboardShortcuts.Recorder("Capture text", name: .captureText)
            KeyboardShortcuts.Recorder("Capture as one line", name: .captureTextWithoutLineBreaks)
            Text("Each shortcut can be changed or cleared independently.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        Section("Startup") {
            Toggle(isOn: loginAtStartupBinding) {
                SettingsLabel(title: "Open TextLens at login", detail: loginItemDescription)
            }
            .disabled(loginItemController.state == .unavailable)

            if loginItemController.state == .requiresApproval {
                Button("Open Login Items Settings…", action: loginItemController.openSystemSettings)
            }

            if let errorMessage = loginItemController.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section("Notifications") {
            Toggle(isOn: $preferences.notifyOnSuccess) {
                SettingsLabel(
                    title: "Show capture notifications",
                    detail: "Text previews can appear on screen or on the Lock Screen."
                )
            }

            Toggle("Play notification sound", isOn: $preferences.playNotificationSound)
                .disabled(!preferences.notifyOnSuccess)
        }

        Section {
            Button("About TextLens…") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [:])
            }
        }
    }

    @ViewBuilder
    private var privacySettings: some View {
        Section("Local history") {
            LabeledContent {
                Text(model.history.count, format: .number)
                    .monospacedDigit()
            } label: {
                SettingsLabel(
                    title: "Saved captures",
                    detail: "TextLens keeps the newest 100 text captures on this Mac."
                )
            }

            Button("Open Capture History…") { openWindow(id: "capture-history") }
            Button("Clear Local History…", role: .destructive) { confirmingClear = true }
                .disabled(model.history.isEmpty || model.isWorking)
        }

        Section("Screen recording access") {
            Text("macOS requires screen recording access to capture a region. Recognition runs on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Screen Recording Settings…", systemImage: "arrow.up.forward.app") {
                CaptureViewModel.openScreenRecordingSettings()
            }
        }
    }

    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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

    private var loginItemDescription: String {
        switch loginItemController.state {
        case .notRegistered: "Start TextLens in the menu bar when you sign in."
        case .enabled: "TextLens opens automatically when you sign in."
        case .requiresApproval: "Approve TextLens in Login Items to finish setup."
        case .unavailable: "Launch at login is unavailable for this installation."
        }
    }

    private static let languageOptions = VisionTextRecognizer.supportedLanguages.sorted {
        languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending
    }

    private static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case shortcuts = "Shortcuts"
    case general = "General"
    case privacy = "History & Privacy"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .capture: "text.viewfinder"
        case .shortcuts: "keyboard"
        case .general: "gearshape"
        case .privacy: "lock.shield"
        }
    }

    var detail: String {
        switch self {
        case .capture: "Recognition, language, and clipboard behavior."
        case .shortcuts: "Start a capture from any app."
        case .general: "Startup and notifications."
        case .privacy: "Local captures and macOS permissions."
        }
    }
}

private struct SettingsLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
