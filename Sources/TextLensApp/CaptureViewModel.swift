import Combine
import Foundation
import KeyboardShortcuts
import TextLensCore

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
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var feedback = CaptureFeedback(
        title: "Ready when you are",
        detail: "Select a region on screen and TextLens will copy the words for you.",
        tone: .neutral
    )
    @Published private(set) var history: [CapturedText] = []
    @Published private(set) var historyLoadError: String?
    @Published var searchText = ""

    private let screenCapture: any ScreenCapturing
    private let recognizer: any TextRecognizing
    private let clipboard: any ClipboardWriting
    private let historyStore: CaptureHistoryStore
    let preferences: CapturePreferences
    private let notificationService: any CaptureNotificationSending
    private var captureShortcutTasks: [Task<Void, Never>] = []

    var isWorking: Bool { phase.isWorking }

    var filteredHistory: [CapturedText] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history }
        return history.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    init(
        screenCapture: any ScreenCapturing = MacOSScreenCapture(),
        recognizer: any TextRecognizing = VisionTextRecognizer(),
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
        startCapture(mode: .preserveLineBreaks)
    }

    func captureWithoutLineBreaks() {
        startCapture(mode: .singleLine)
    }

    private func startCapture(mode: CaptureTextMode) {
        guard !isWorking else { return }
        let autoCopy = preferences.autoCopy
        let notifyOnSuccess = preferences.notifyOnSuccess
        let playNotificationSound = preferences.playNotificationSound
        phase = .capturing
        feedback = CaptureFeedback(
            title: "Choose a region…",
            detail: "Drag over the text you want to capture.",
            tone: .neutral
        )

        Task { [weak self] in
            await self?.performCapture(
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
        autoCopy: Bool,
        notifyOnSuccess: Bool,
        playNotificationSound: Bool,
        mode: CaptureTextMode
    ) async {
        let imageData: Data
        do {
            guard let capturedImage = try await screenCapture.captureRegion() else {
                phase = .idle
                feedback = CaptureFeedback(
                    title: "Capture cancelled",
                    detail: "Nothing was saved or copied.",
                    tone: .neutral
                )
                return
            }
            imageData = capturedImage
        } catch {
            presentError(
                title: "Couldn't capture the screen",
                detail: "Try selecting a region again. \(error.localizedDescription)"
            )
            return
        }

        phase = .recognizing
        feedback = CaptureFeedback(
            title: "Reading text…",
            detail: "TextLens is recognizing words on this Mac.",
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
                detail: "Try a larger, sharper selection. \(error.localizedDescription)"
            )
            return
        }

        guard !recognizedText.isEmpty else {
            presentError(
                title: "No text found",
                detail: "Try selecting a larger area with clearer text."
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
                    : "It's available in local history. Use Copy Again to copy it.",
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
