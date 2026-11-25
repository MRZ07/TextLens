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
                Label("Capture Text", systemImage: "viewfinder")
            }
            .globalKeyboardShortcut(.captureText)
            .disabled(model.isWorking)

            Button(action: model.captureWithoutLineBreaks) {
                Label("Capture as One Line", systemImage: "text.alignleft")
            }
            .globalKeyboardShortcut(.captureTextWithoutLineBreaks)
            .disabled(model.isWorking)

            Button("Read Text from Image…", systemImage: "photo", action: model.chooseImage)
                .disabled(model.isWorking)

            Section {
                Button("Capture History…", systemImage: "clock.arrow.circlepath") {
                    openWindow(id: "capture-history")
                }

                Button("Settings…", systemImage: "gearshape") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            if model.phase != .idle || model.feedback.tone != .neutral {
                Section("Last activity") {
                    Button(model.feedback.title, systemImage: model.feedback.symbol) {
                        openWindow(id: "capture-history")
                    }
                    if model.feedback.needsScreenRecordingAccess {
                        Button("Open Screen Recording Settings…", systemImage: "arrow.up.forward.app") {
                            CaptureViewModel.openScreenRecordingSettings()
                        }
                    }
                }
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
            Label("TextLens", systemImage: menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)

        Window("Capture History", id: "capture-history") {
            CaptureHistoryView(model: model)
        }
        .defaultSize(width: 760, height: 490)

        Settings {
            SettingsView(
                model: model,
                preferences: model.preferences,
                loginItemController: applicationDelegate.loginItemController
            )
        }
    }

    private var menuBarSymbol: String {
        if model.isWorking { return "ellipsis.circle" }
        if model.feedback.tone == .error { return "exclamationmark.circle" }
        return "text.viewfinder"
    }
}
