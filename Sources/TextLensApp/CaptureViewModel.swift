import AppKit
import Combine
import Foundation
import KeyboardShortcuts
import TextLensCore
import UniformTypeIdentifiers

enum CapturePhase: Equatable {
    case idle
    case capturing
    case recognizing
    case recognized
    case copied
    case failed

    var isWorking: Bool {
        self == .capturing || self == .recognizing
    }
}

private enum CaptureTextMode: Equatable {
    case preserveLineBreaks
    case singleLine
}

private enum CaptureSource {
    case screen
    case image(URL)
}

enum FeedbackTone: Equatable {
    case neutral
    case success
    case warning
    case error
}

struct CaptureFeedback {
    let title: String
    let detail: String
    let tone: FeedbackTone
    var needsScreenRecordingAccess = false

    var symbol: String {
        switch tone {
        case .neutral: "text.viewfinder"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        }
    }
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var feedback = CaptureFeedback(
        title: "Ready to capture",
        detail: "Select an area of your screen or open an image to read its text.",
        tone: .neutral
    )
    @Published private(set) var history: [CapturedText] = []
    @Published private(set) var historyLoadError: String?
    @Published var searchText = ""
    @Published private var isChoosingImage = false

    private let screenCapture: any ScreenCapturing
    private let recognizer: (any TextRecognizing)?
    private let clipboard: any ClipboardWriting
    private let historyStore: CaptureHistoryStore
    let preferences: CapturePreferences
    private let notificationService: any CaptureNotificationSending
    private var captureShortcutTasks: [Task<Void, Never>] = []

    var isWorking: Bool { phase.isWorking || isChoosingImage }

    var filteredHistory: [CapturedText] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history }
        return history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    init(
        screenCapture: any ScreenCapturing = MacOSScreenCapture(),
        recognizer: (any TextRecognizing)? = nil,
        clipboard: any ClipboardWriting = SystemClipboard(),
        historyStore: CaptureHistoryStore = CaptureHistoryStore(),
        preferences: CapturePreferences? = nil,
        notificationService: (any CaptureNotificationSending)? = nil,
        listensForCaptureShortcuts: Bool = true
    ) {
        self.screenCapture = screenCapture
        self.recognizer = recognizer
        self.clipboard = clipboard
        self.historyStore = historyStore
        self.preferences = preferences ?? CapturePreferences()
        self.notificationService = notificationService ?? CaptureNotificationService()
        reloadHistory()
        if listensForCaptureShortcuts {
            let preserveLineBreaksTask = Task { [weak self] in
                for await _ in KeyboardShortcuts.events(.keyUp, for: .captureText) {
                    guard let self else { return }
                    self.capture()
                }
            }
            let singleLineTask = Task { [weak self] in
                for await _ in KeyboardShortcuts.events(.keyUp, for: .captureTextWithoutLineBreaks) {
                    guard let self else { return }
                    self.captureWithoutLineBreaks()
                }
            }
            captureShortcutTasks = [preserveLineBreaksTask, singleLineTask]
        }
    }

    deinit {
        captureShortcutTasks.forEach { $0.cancel() }
    }

    func capture() {
        startCapture(from: .screen, mode: .preserveLineBreaks)
    }

    func captureWithoutLineBreaks() {
        startCapture(from: .screen, mode: .singleLine)
    }

    func chooseImage() {
        guard !isWorking else { return }
        isChoosingImage = true

        let panel = NSOpenPanel()
        panel.title = "Read text from an image"
        panel.prompt = "Read Text"
        panel.allowedContentTypes = [.image]
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingImage = false
            if response == .OK, let url = panel.url {
                self.importImage(at: url)
            }
        }
    }

    func importImage(at url: URL) {
        startCapture(from: .image(url), mode: .preserveLineBreaks)
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startCapture(from source: CaptureSource, mode: CaptureTextMode) {
        guard !isWorking else { return }
        let recognizer = recognizer ?? VisionTextRecognizer(
            mode: preferences.recognitionMode,
            language: preferences.preferredRecognitionLanguage,
            correctsLanguage: preferences.correctsLanguage
        )
        let autoCopy = preferences.autoCopy
        let notifyOnSuccess = preferences.notifyOnSuccess
        let playNotificationSound = preferences.playNotificationSound
        switch source {
        case .screen:
            phase = .capturing
            feedback = CaptureFeedback(
                title: "Choose a region…",
                detail: "Drag around the text. Press Escape to cancel.",
                tone: .neutral
            )
        case .image:
            phase = .recognizing
            feedback = CaptureFeedback(
                title: "Opening image…",
                detail: "TextLens is loading the selected image.",
                tone: .neutral
            )
        }

        Task { [weak self] in
            await self?.performCapture(
                from: source,
                recognizer: recognizer,
                autoCopy: autoCopy,
                notifyOnSuccess: notifyOnSuccess,
                playNotificationSound: playNotificationSound,
                mode: mode
            )
        }
    }

    func copyAgain(_ capture: CapturedText) {
        do {
            try clipboard.copy(capture.text)
            phase = .copied
            feedback = CaptureFeedback(
                title: "Copied again",
                detail: "This text is ready to paste.",
                tone: .success
            )
        } catch {
            presentError(
                title: "Couldn't copy that capture",
                detail: error.localizedDescription
            )
        }
    }

    func clearHistory() {
        do {
            try historyStore.clear()
            history.removeAll()
            historyLoadError = nil
            phase = .idle
            feedback = CaptureFeedback(
                title: "History cleared",
                detail: "Saved captures have been removed from this Mac.",
                tone: .success
            )
        } catch {
            presentError(
                title: "Couldn't clear local history",
                detail: error.localizedDescription
            )
        }
    }

    func reloadHistory() {
        do {
            history = try historyStore.load().sorted { $0.capturedAt > $1.capturedAt }
            historyLoadError = nil
        } catch {
            history = []
            historyLoadError = error.localizedDescription
            feedback = CaptureFeedback(
                title: "History couldn't be loaded",
                detail: "Your captures stay on this Mac. Try loading history again.",
                tone: .warning
            )
        }
    }

    private func performCapture(
        from source: CaptureSource,
        recognizer: any TextRecognizing,
        autoCopy: Bool,
        notifyOnSuccess: Bool,
        playNotificationSound: Bool,
        mode: CaptureTextMode
    ) async {
        let imageData: Data
        switch source {
        case .screen:
            do {
                guard let capturedImage = try await screenCapture.captureRegion() else {
                    phase = .idle
                    feedback = CaptureFeedback(
                        title: "Capture cancelled",
                        detail: "Choose Capture Text to select another region.",
                        tone: .neutral
                    )
                    return
                }
                imageData = capturedImage
            } catch let error as ScreenRecordingAccessRequired {
                phase = .failed
                feedback = CaptureFeedback(
                    title: "Screen recording access required",
                    detail: error.localizedDescription,
                    tone: .error,
                    needsScreenRecordingAccess: true
                )
                return
            } catch {
                presentError(
                    title: "Couldn't capture the screen",
                    detail: "\(error.localizedDescription) Try another region or open a saved image."
                )
                return
            }
        case .image(let url):
            do {
                imageData = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
            } catch {
                presentError(
                    title: "Couldn't open the image",
                    detail: error.localizedDescription
                )
                return
            }
        }

        phase = .recognizing
        feedback = CaptureFeedback(
            title: "Reading text…",
            detail: "TextLens is recognizing text on this Mac.",
            tone: .neutral
        )

        let recognizedText: String
        do {
            let rawText = try await recognizer
                .recognize(imageData: imageData)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            recognizedText = mode == .singleLine ? Self.joinLines(rawText) : rawText
        } catch {
            presentError(
                title: "Couldn't read text from that area",
                detail: error.localizedDescription
            )
            return
        }

        guard !recognizedText.isEmpty else {
            presentError(
                title: "No text found",
                detail: "Try a tighter crop around the text or choose its language in Settings."
            )
            return
        }

        let item = CapturedText(id: UUID(), text: recognizedText, capturedAt: Date())
        if autoCopy {
            do {
                try clipboard.copy(recognizedText)
            } catch {
                presentError(
                    title: "Text was recognized but not copied",
                    detail: "Check clipboard access, then try capturing again. \(error.localizedDescription)"
                )
                return
            }
        }

        do {
            history = try historyStore.append(item).sorted { $0.capturedAt > $1.capturedAt }
            historyLoadError = nil
            phase = autoCopy ? .copied : .recognized
            feedback = CaptureFeedback(
                title: autoCopy ? "Text copied" : "Text recognized",
                detail: autoCopy
                    ? "It's ready to paste and has been saved in local history."
                    : "Open Capture History to review and copy it.",
                tone: .success
            )
            if notifyOnSuccess {
                await notificationService.notifySuccess(
                    recognizedText: recognizedText,
                    copiedToClipboard: autoCopy,
                    playSound: playNotificationSound
                )
            }
        } catch {
            phase = autoCopy ? .copied : .failed
            feedback = CaptureFeedback(
                title: autoCopy ? "Copied, but not saved to history" : "Text recognized, but not saved",
                detail: autoCopy
                    ? "The text is on your clipboard. History couldn't be updated: \(error.localizedDescription)"
                    : "History couldn't be updated: \(error.localizedDescription)",
                tone: .warning
            )
            if autoCopy, notifyOnSuccess {
                await notificationService.notifySuccess(
                    recognizedText: recognizedText,
                    copiedToClipboard: true,
                    playSound: playNotificationSound
                )
            }
        }
    }

    private static func joinLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func presentError(title: String, detail: String) {
        phase = .failed
        feedback = CaptureFeedback(title: title, detail: detail, tone: .error)
    }
}
