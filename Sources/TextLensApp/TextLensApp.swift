import SwiftUI
import AppKit
import KeyboardShortcuts

@main
struct TextLensApp: App {
    @NSApplicationDelegateAdaptor(TextLensApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = CaptureViewModel()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            Button(action: model.capture) {
                Label(model.isWorking ? "Working…" : "Capture text", systemImage: "viewfinder")
            }
            .globalKeyboardShortcut(.captureText)
            .disabled(model.isWorking)

            Button(action: model.captureWithoutLineBreaks) {
                Label("Capture text without line breaks", systemImage: "text.alignleft")
            }
            .globalKeyboardShortcut(.captureTextWithoutLineBreaks)
            .disabled(model.isWorking)

            Section {
                Button("Capture history…", systemImage: "clock.arrow.circlepath") {
                    openWindow(id: "capture-history")
                }

                Button("Settings…", systemImage: "gearshape") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Section("Status") {
                Label(model.feedback.title, systemImage: statusSymbol)
                    .disabled(true)
            }

            Divider()

            Button("About TextLens") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [:])
            }

            Button("Quit TextLens") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Label("TextLens", systemImage: "text.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Window("Capture History", id: "capture-history") {
            CaptureHistoryView(model: model)
        }
        .defaultSize(width: 560, height: 520)

        Settings {
            SettingsView(model: model, loginItemController: applicationDelegate.loginItemController)
        }
    }

    private var statusSymbol: String {
        switch model.phase {
        case .idle: "info.circle"
        case .capturing: "viewfinder"
        case .recognizing: "text.viewfinder"
        case .recognized: "text.viewfinder"
        case .copied: model.feedback.tone == .warning ? "exclamationmark.triangle" : "checkmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }
}
