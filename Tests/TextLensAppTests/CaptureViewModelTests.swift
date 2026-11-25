import Foundation
import UserNotifications
import XCTest
@testable import TextLensApp
import TextLensCore

@MainActor
final class CaptureViewModelTests: XCTestCase {
    func testPreferencesDefaultToEnabledAndPersistDisabledValues() {
        let defaults = makeDefaults()
        let first = CapturePreferences(defaults: defaults)

        XCTAssertTrue(first.autoCopy)
        XCTAssertTrue(first.notifyOnSuccess)
        XCTAssertTrue(first.playNotificationSound)
        XCTAssertEqual(first.recognitionMode, .accurate)
        XCTAssertEqual(first.recognitionLanguage, CapturePreferences.systemLanguage)
        XCTAssertFalse(first.correctsLanguage)

        first.autoCopy = false
        first.notifyOnSuccess = false
        first.playNotificationSound = false
        first.recognitionMode = .fast
        first.recognitionLanguage = ""
        first.correctsLanguage = true

        let restored = CapturePreferences(defaults: defaults)
        XCTAssertFalse(restored.autoCopy)
        XCTAssertFalse(restored.notifyOnSuccess)
        XCTAssertFalse(restored.playNotificationSound)
        XCTAssertEqual(restored.recognitionMode, .fast)
        XCTAssertNil(restored.preferredRecognitionLanguage)
        XCTAssertTrue(restored.correctsLanguage)
    }

    func testImportReadsFileWithoutTakingScreenCapture() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("image.png")
        let input = Data([17, 24, 95])
        try input.write(to: url)
        let clipboard = StubClipboard()
        let model = makeModel(
            screen: FixedScreenCapture(failure: CaptureStubError.capture),
            recognizer: FileDataRecognizer(expectedData: input),
            historyStore: store,
            clipboard: clipboard
        )

        model.importImage(at: url)
        await waitFor { !model.isWorking }

        XCTAssertEqual(clipboard.copiedTexts, ["First line\nSecond line"])
        XCTAssertEqual(try store.load().map(\.text), clipboard.copiedTexts)
    }

    func testMissingScreenRecordingPermissionShowsSettingsAction() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(
            screen: FixedScreenCapture(failure: ScreenRecordingAccessRequired()),
            historyStore: store
        )

        model.capture()
        await waitFor { !model.isWorking }

        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(model.feedback.needsScreenRecordingAccess)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testSuccessfulCaptureCopiesOnceSavesHistoryAndNotifiesOnce() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let model = makeModel(
            historyStore: store,
            clipboard: clipboard,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(clipboard.copiedTexts, ["Readable text"])
        XCTAssertEqual(try store.load().map(\.text), ["Readable text"])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.soundValues, [true])
        XCTAssertEqual(model.feedback.title, "Text copied")
    }

    func testDefaultCapturePreservesRecognizedLineBreaksAcrossEffects() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognized = "\r\n  Alpha  beta\r\n\n  Cafe\u{301}  line \n"
        let expected = "Alpha  beta\r\n\n  Cafe\u{301}  line"
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let model = makeModel(
            recognizer: FixedRecognizer(text: recognized),
            historyStore: store,
            clipboard: clipboard,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(clipboard.copiedTexts, [expected])
        XCTAssertEqual(try store.load().map(\.text), [expected])
        XCTAssertEqual(notifications.recognizedTexts, [expected])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.soundValues, [true])
    }

    func testSingleLineCaptureHandlesUnicodeNewlinesAndPreservesIntraLineTextAcrossEffects() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognized = "\r\n  Alpha  beta \t\r\n \t\r\n Cafe\u{301}  crème\t\rThird\u{2028}    last \n  👩🏽‍🚀 launch  \u{2029}"
        let expected = "Alpha  beta Cafe\u{301}  crème Third last 👩🏽‍🚀 launch"
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let model = makeModel(
            recognizer: FixedRecognizer(text: recognized),
            historyStore: store,
            clipboard: clipboard,
            notifications: notifications
        )

        model.captureWithoutLineBreaks()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(clipboard.copiedTexts, [expected])
        XCTAssertEqual(try store.load().map(\.text), [expected])
        XCTAssertEqual(notifications.recognizedTexts, [expected])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.soundValues, [true])
    }

    func testCopyOffSavesHistoryAndManualCopyAgainStillWorks() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let preferences = makePreferences()
        preferences.autoCopy = false
        let model = makeModel(
            historyStore: store,
            clipboard: clipboard,
            preferences: preferences,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertEqual(try store.load().map(\.text), ["Readable text"])
        XCTAssertEqual(notifications.copiedValues, [false])
        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.soundValues, [true])
        XCTAssertEqual(model.feedback.title, "Text recognized")
        XCTAssertEqual(model.phase, .recognized)

        model.copyAgain(try XCTUnwrap(model.history.first))

        XCTAssertEqual(clipboard.copiedTexts, ["Readable text"])
        XCTAssertEqual(model.feedback.title, "Copied again")
        XCTAssertEqual(notifications.copiedValues, [false])
        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.soundValues, [true])
    }

    func testSoundOffIsSnapshottedAndPassedWithNotificationText() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = StubNotifications()
        let preferences = makePreferences()
        preferences.playNotificationSound = false
        let model = makeModel(
            historyStore: store,
            preferences: preferences,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.soundValues, [false])
    }

    func testNotifyOffDoesNotSendSuccessNotification() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notifications = StubNotifications()
        let preferences = makePreferences()
        preferences.notifyOnSuccess = false
        let model = makeModel(
            historyStore: store,
            preferences: preferences,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking }

        XCTAssertEqual(try store.load().map(\.text), ["Readable text"])
        XCTAssertTrue(notifications.copiedValues.isEmpty)
        XCTAssertTrue(notifications.recognizedTexts.isEmpty)
        XCTAssertTrue(notifications.soundValues.isEmpty)
    }

    func testCancelAndEmptyOCRDoNotNotifyOrSave() async throws {
        let (cancelStore, cancelDirectory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: cancelDirectory) }
        let cancelNotifications = StubNotifications()
        let cancelModel = makeModel(
            screen: FixedScreenCapture(imageData: nil),
            historyStore: cancelStore,
            notifications: cancelNotifications
        )

        cancelModel.capture()
        await waitFor { !cancelModel.isWorking }

        XCTAssertEqual(cancelModel.feedback.title, "Capture cancelled")
        XCTAssertTrue(try cancelStore.load().isEmpty)
        XCTAssertTrue(cancelNotifications.copiedValues.isEmpty)
        XCTAssertTrue(cancelNotifications.recognizedTexts.isEmpty)
        XCTAssertTrue(cancelNotifications.soundValues.isEmpty)

        let (emptyStore, emptyDirectory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let emptyNotifications = StubNotifications()
        let emptyModel = makeModel(
            recognizer: FixedRecognizer(text: " \n "),
            historyStore: emptyStore,
            notifications: emptyNotifications
        )

        emptyModel.capture()
        await waitFor { !emptyModel.isWorking }

        XCTAssertEqual(emptyModel.feedback.title, "No text found")
        XCTAssertTrue(try emptyStore.load().isEmpty)
        XCTAssertTrue(emptyNotifications.copiedValues.isEmpty)
        XCTAssertTrue(emptyNotifications.recognizedTexts.isEmpty)
        XCTAssertTrue(emptyNotifications.soundValues.isEmpty)
    }

    func testCaptureAndRecognitionFailuresDoNotNotify() async throws {
        let (captureStore, captureDirectory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: captureDirectory) }
        let captureNotifications = StubNotifications()
        let captureModel = makeModel(
            screen: FixedScreenCapture(failure: CaptureStubError.capture),
            historyStore: captureStore,
            notifications: captureNotifications
        )

        captureModel.capture()
        await waitFor { !captureModel.isWorking }

        XCTAssertEqual(captureModel.phase, .failed)
        XCTAssertTrue(captureNotifications.copiedValues.isEmpty)
        XCTAssertTrue(captureNotifications.recognizedTexts.isEmpty)
        XCTAssertTrue(captureNotifications.soundValues.isEmpty)

        let (recognitionStore, recognitionDirectory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: recognitionDirectory) }
        let recognitionNotifications = StubNotifications()
        let recognitionModel = makeModel(
            recognizer: FixedRecognizer(failure: .recognition),
            historyStore: recognitionStore,
            notifications: recognitionNotifications
        )

        recognitionModel.capture()
        await waitFor { !recognitionModel.isWorking }

        XCTAssertEqual(recognitionModel.phase, .failed)
        XCTAssertTrue(try recognitionStore.load().isEmpty)
        XCTAssertTrue(recognitionNotifications.copiedValues.isEmpty)
        XCTAssertTrue(recognitionNotifications.recognizedTexts.isEmpty)
        XCTAssertTrue(recognitionNotifications.soundValues.isEmpty)
    }

    func testClipboardFailureDoesNotSaveOrSendSuccessNotification() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = StubClipboard(shouldFail: true)
        let notifications = StubNotifications()
        let model = makeModel(historyStore: store, clipboard: clipboard, notifications: notifications)

        model.capture()
        await waitFor { !model.isWorking }

        XCTAssertEqual(model.feedback.title, "Text was recognized but not copied")
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertTrue(notifications.copiedValues.isEmpty)
        XCTAssertTrue(notifications.recognizedTexts.isEmpty)
        XCTAssertTrue(notifications.soundValues.isEmpty)
    }

    func testHistoryFailureAfterCopyWarnsAndStillReportsCopiedText() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextLensAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("block directory creation".utf8).write(to: blockingFile)
        let store = CaptureHistoryStore(fileURL: blockingFile.appendingPathComponent("history.json"))
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let model = makeModel(historyStore: store, clipboard: clipboard, notifications: notifications)

        model.capture()
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(clipboard.copiedTexts, ["Readable text"])
        XCTAssertEqual(model.phase, .copied)
        XCTAssertEqual(model.feedback.tone, .warning)
        XCTAssertEqual(model.feedback.title, "Copied, but not saved to history")
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.soundValues, [true])
    }

    func testHistoryFailureWithoutCopyDoesNotNotify() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextLensAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("block directory creation".utf8).write(to: blockingFile)
        let store = CaptureHistoryStore(fileURL: blockingFile.appendingPathComponent("history.json"))
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let preferences = makePreferences()
        preferences.autoCopy = false
        let model = makeModel(
            historyStore: store,
            clipboard: clipboard,
            preferences: preferences,
            notifications: notifications
        )

        model.capture()
        await waitFor { !model.isWorking }

        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(notifications.copiedValues.isEmpty)
        XCTAssertTrue(notifications.recognizedTexts.isEmpty)
        XCTAssertTrue(notifications.soundValues.isEmpty)
    }

    func testSettingsAreSnapshottedAndReentryWhileBusyIsIgnored() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = SuspendedScreenCapture()
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let preferences = makePreferences()
        let model = makeModel(
            screen: screen,
            historyStore: store,
            clipboard: clipboard,
            preferences: preferences,
            notifications: notifications
        )

        model.capture()
        for _ in 0..<1_000 {
            if await screen.captureCount() == 1 { break }
            await Task.yield()
        }
        model.capture()
        preferences.autoCopy = false
        preferences.notifyOnSuccess = false
        preferences.playNotificationSound = false
        let captureCountWhileBusy = await screen.captureCount()
        XCTAssertEqual(captureCountWhileBusy, 1)

        await screen.complete(with: Data([1]))
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        XCTAssertEqual(clipboard.copiedTexts, ["Readable text"])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.recognizedTexts, ["Readable text"])
        XCTAssertEqual(notifications.soundValues, [true])
        XCTAssertEqual(try store.load().count, 1)
    }

    func testPendingCaptureKeepsItsLineBreakModeWhenAlternateEntryIsIgnored() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = SuspendedScreenCapture()
        let recognized = "  First line\r\n  Second line  "
        let clipboard = StubClipboard()
        let notifications = StubNotifications()
        let model = makeModel(
            screen: screen,
            recognizer: FixedRecognizer(text: recognized),
            historyStore: store,
            clipboard: clipboard,
            notifications: notifications
        )

        model.captureWithoutLineBreaks()
        for _ in 0..<1_000 {
            if await screen.captureCount() == 1 { break }
            await Task.yield()
        }
        model.capture()
        let captureCountWhileBusy = await screen.captureCount()
        XCTAssertEqual(captureCountWhileBusy, 1)

        await screen.complete(with: Data([1]))
        await waitFor { !model.isWorking && notifications.copiedValues.count == 1 }

        let expected = "First line Second line"
        XCTAssertEqual(clipboard.copiedTexts, [expected])
        XCTAssertEqual(try store.load().map(\.text), [expected])
        XCTAssertEqual(notifications.recognizedTexts, [expected])
        XCTAssertEqual(notifications.copiedValues, [true])
        XCTAssertEqual(notifications.soundValues, [true])
    }

    func testCompletedNotificationDoesNotReplaceNewerFeedback() async throws {
        let (store, directory) = try makeHistoryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clipboard = StubClipboard()
        let notifications = StubNotifications(suspendNext: true)
        let model = makeModel(historyStore: store, clipboard: clipboard, notifications: notifications)

        model.capture()
        await waitFor { notifications.copiedValues.count == 1 }
        model.copyAgain(CapturedText(id: UUID(), text: "Newer feedback", capturedAt: Date()))
        XCTAssertEqual(model.feedback.title, "Copied again")

        notifications.releasePending()
        await waitFor { notifications.completedCount == 1 }

        XCTAssertEqual(model.feedback.title, "Copied again")
        XCTAssertEqual(model.feedback.detail, "This text is ready to paste.")
        XCTAssertEqual(clipboard.copiedTexts, ["Readable text", "Newer feedback"])
    }

    private func makeModel(
        screen: any ScreenCapturing = FixedScreenCapture(imageData: Data([1])),
        recognizer: any TextRecognizing = FixedRecognizer(text: "Readable text"),
        historyStore: CaptureHistoryStore,
        clipboard: StubClipboard = StubClipboard(),
        preferences: CapturePreferences? = nil,
        notifications: StubNotifications? = nil
    ) -> CaptureViewModel {
        let resolvedPreferences = preferences ?? makePreferences()
        let resolvedNotifications = notifications ?? StubNotifications()
        return CaptureViewModel(
            screenCapture: screen,
            recognizer: recognizer,
            clipboard: clipboard,
            historyStore: historyStore,
            preferences: resolvedPreferences,
            notificationService: resolvedNotifications,
            listensForCaptureShortcuts: false
        )
    }

    private func makeHistoryStore() throws -> (CaptureHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextLensAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (CaptureHistoryStore(fileURL: directory.appendingPathComponent("history.json")), directory)
    }

    private func makePreferences() -> CapturePreferences {
        CapturePreferences(defaults: makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TextLensAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitFor(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for capture workflow", file: file, line: line)
    }
}

private struct FixedScreenCapture: ScreenCapturing {
    var imageData: Data? = Data([1])
    var failure: (any Error)?

    func captureRegion() async throws -> Data? {
        if let failure { throw failure }
        return imageData
    }
}

private struct FileDataRecognizer: TextRecognizing {
    let expectedData: Data

    func recognize(imageData: Data) async throws -> String {
        XCTAssertEqual(imageData, expectedData)
        return "First line\nSecond line"
    }
}

private struct FixedRecognizer: TextRecognizing {
    var text: String = "Readable text"
    var failure: CaptureStubError?

    func recognize(imageData: Data) async throws -> String {
        if let failure { throw failure }
        return text
    }
}

private final class StubClipboard: ClipboardWriting {
    private(set) var copiedTexts: [String] = []
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func copy(_ text: String) throws {
        if shouldFail { throw CaptureStubError.clipboard }
        copiedTexts.append(text)
    }
}

@MainActor
private final class StubNotifications: CaptureNotificationSending {
    private(set) var copiedValues: [Bool] = []
    private(set) var recognizedTexts: [String] = []
    private(set) var soundValues: [Bool] = []
    private(set) var completedCount = 0
    private var suspendNext: Bool
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    init(suspendNext: Bool = false) {
        self.suspendNext = suspendNext
    }

    func notifySuccess(
        recognizedText: String,
        copiedToClipboard: Bool,
        playSound: Bool
    ) async {
        recognizedTexts.append(recognizedText)
        copiedValues.append(copiedToClipboard)
        soundValues.append(playSound)
        if suspendNext {
            suspendNext = false
            await withCheckedContinuation { pendingContinuation = $0 }
        }
        completedCount += 1
    }

    func releasePending() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
}

@MainActor
final class CaptureNotificationPreviewTests: XCTestCase {
    func testShortUnicodeTextIsNotChanged() {
        let text = "Café 👩🏽‍🚀"

        XCTAssertEqual(CaptureNotificationService.previewBody(for: text), text)
    }

    func testNotificationSoundPolicyPreservesBodyAndForegroundPresentation() {
        let text = "Café 👩🏽‍🚀 recognized text"
        let mutedContent = CaptureNotificationService.notificationContent(
            recognizedText: text,
            copiedToClipboard: true,
            playSound: false,
            systemSoundSetting: .enabled
        )
        let mutedOptions = CaptureNotificationService.foregroundPresentationOptions(
            hasSound: mutedContent.sound != nil
        )
        XCTAssertEqual(mutedContent.body, text)
        XCTAssertNil(mutedContent.sound)
        XCTAssertTrue(mutedOptions.contains(.banner))
        XCTAssertTrue(mutedOptions.contains(.list))
        XCTAssertFalse(mutedOptions.contains(.sound))

        let soundContent = CaptureNotificationService.notificationContent(
            recognizedText: text,
            copiedToClipboard: false,
            playSound: true,
            systemSoundSetting: .enabled
        )
        let soundOptions = CaptureNotificationService.foregroundPresentationOptions(
            hasSound: soundContent.sound != nil
        )
        XCTAssertEqual(soundContent.body, text)
        XCTAssertNotNil(soundContent.sound)
        XCTAssertTrue(soundOptions.contains(.sound))

        let systemMutedContent = CaptureNotificationService.notificationContent(
            recognizedText: text,
            copiedToClipboard: false,
            playSound: true,
            systemSoundSetting: .disabled
        )
        let systemMutedOptions = CaptureNotificationService.foregroundPresentationOptions(
            hasSound: systemMutedContent.sound != nil
        )
        XCTAssertEqual(systemMutedContent.body, text)
        XCTAssertNil(systemMutedContent.sound)
        XCTAssertFalse(systemMutedOptions.contains(.sound))
    }

    func testPreviewLeavesTextAtTheGraphemeLimitUntruncated() {
        let text = String(repeating: "界", count: CaptureNotificationService.maximumPreviewLength)

        XCTAssertEqual(CaptureNotificationService.previewBody(for: text), text)
    }

    func testLongUnicodePreviewTruncatesOnGraphemeBoundaryAndAddsEllipsis() {
        let grapheme = "👩🏽‍🚀"
        let text = String(repeating: grapheme, count: CaptureNotificationService.maximumPreviewLength) + "尾"

        let preview = CaptureNotificationService.previewBody(for: text)

        XCTAssertEqual(preview.count, CaptureNotificationService.maximumPreviewLength + 1)
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertEqual(
            String(preview.dropLast()),
            String(repeating: grapheme, count: CaptureNotificationService.maximumPreviewLength)
        )
    }
}

private actor SuspendedScreenCapture: ScreenCapturing {
    private var pendingContinuation: CheckedContinuation<Data?, Error>?
    private var calls = 0

    func captureRegion() async throws -> Data? {
        calls += 1
        return try await withCheckedThrowingContinuation { pendingContinuation = $0 }
    }

    func captureCount() -> Int { calls }

    func complete(with data: Data?) {
        pendingContinuation?.resume(returning: data)
        pendingContinuation = nil
    }
}

private enum CaptureStubError: LocalizedError {
    case capture
    case recognition
    case clipboard

    var errorDescription: String? {
        switch self {
        case .capture: "capture failed"
        case .recognition: "recognition failed"
        case .clipboard: "clipboard failed"
        }
    }
}
