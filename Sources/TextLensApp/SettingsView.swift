import AppKit
import KeyboardShortcuts
import SwiftUI
import TextLensCore

struct SettingsView: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject var preferences: CapturePreferences
    @ObservedObject var loginItemController: LoginItemController
    let openHistory: () -> Void
    @State private var section: SettingsSection = .general
    @State private var hoveredSection: SettingsSection?
    @FocusState private var focusedSection: SettingsSection?
    @State private var hasScreenRecordingAccess = false
    @State private var confirmingClear = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 178)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(section.rawValue)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                Form {
                    switch section {
                    case .capture: captureSettings
                    case .shortcuts: shortcutSettings
                    case .general: generalSettings
                    case .history: historySettings
                    }
                }
                .formStyle(.grouped)
                .id(section)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loginItemController.refresh()
            refreshScreenRecordingAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshScreenRecordingAccess()
        }
        .onChange(of: section) { _, page in
            if page == .general { refreshScreenRecordingAccess() }
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
            Text("This permanently removes saved text from this Mac.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(.rect(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text("TextLens")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { page in
                    sidebarButton(page)
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 0)

            if let appVersion {
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(.regularMaterial)
    }

    private func sidebarButton(_ page: SettingsSection) -> some View {
        let selected = section == page
        let shape = RoundedRectangle(cornerRadius: 8)
        return Button {
            section = page
        } label: {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(page.rawValue)
                    .fontWeight(selected ? .semibold : .regular)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hoveredSection == page ? 0.06 : 0),
                in: shape
            )
            .overlay {
                if focusedSection == page {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focused($focusedSection, equals: page)
        .onHover { hoveredSection = $0 ? page : nil }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var captureSettings: some View {
        Section("Recognition") {
            Picker("Text language", selection: $preferences.recognitionLanguage) {
                Text("Detect automatically").tag("")
                Text("System language").tag(CapturePreferences.systemLanguage)
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
            return "Automatic detection uses Accurate mode to identify the languages in the image."
        }
        if preferences.recognitionMode == .accurate {
            return "Best for small text, images, and video. TextLens retries weak results with enhanced contrast and automatic language detection."
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
        Section("Permissions") {
            screenRecordingSettings
        }

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

    private var screenRecordingSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "record.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)

                SettingsLabel(
                    title: "Screen Recording",
                    detail: hasScreenRecordingAccess
                        ? "TextLens can capture a region of your screen."
                        : "Allow TextLens to capture a region of your screen. Reopen TextLens if macOS asks."
                )

                Spacer(minLength: 8)
                screenRecordingStatus
            }

            Button("Open System Settings…", systemImage: "arrow.up.forward.app") {
                CaptureViewModel.openScreenRecordingSettings()
            }
            .accessibilityHint("Opens the Screen Recording permission in System Settings")
        }
        .padding(.vertical, 4)
    }

    private var screenRecordingStatus: some View {
        let color: Color = hasScreenRecordingAccess ? .green : .orange
        return Label {
            Text(hasScreenRecordingAccess ? "Granted" : "Not granted")
        } icon: {
            Image(systemName: hasScreenRecordingAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(color)
        }
        .font(.caption.weight(.semibold))
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: .capsule)
        .accessibilityLabel(hasScreenRecordingAccess ? "Screen recording granted" : "Screen recording not granted")
    }

    private func refreshScreenRecordingAccess() {
        hasScreenRecordingAccess = MacOSScreenCapture.hasScreenRecordingAccess
    }

    @ViewBuilder
    private var historySettings: some View {
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

            Button("Open Capture History…", action: openHistory)
            Button("Clear Local History…", role: .destructive) { confirmingClear = true }
                .disabled(model.history.isEmpty || model.isWorking)
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
    case general = "General"
    case capture = "Capture"
    case shortcuts = "Shortcuts"
    case history = "History"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .capture: "text.viewfinder"
        case .shortcuts: "keyboard"
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
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
