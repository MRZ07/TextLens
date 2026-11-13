import Foundation
import XCTest
@testable import TextLensCore

final class CaptureHistoryStoreTests: XCTestCase {
    func testLoadReturnsEmptyWhenHistoryDoesNotExist() throws {
        let store = CaptureHistoryStore(fileURL: makeTemporaryURL())

        XCTAssertEqual(try store.load(), [])
    }

    func testAppendPersistsEntriesInCaptureOrderAndClearRemovesThem() throws {
        let store = CaptureHistoryStore(fileURL: makeTemporaryURL())
        let first = CapturedText(text: "first", capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let second = CapturedText(text: "second", capturedAt: Date(timeIntervalSince1970: 1_700_000_001))

        XCTAssertEqual(try store.append(first), [first])
        XCTAssertEqual(try store.append(second), [first, second])
        XCTAssertEqual(try store.load(), [first, second])

        try store.clear()
        XCTAssertEqual(try store.load(), [])
    }

    func testHistoryKeepsOnlyNewestOneHundredEntries() throws {
        let store = CaptureHistoryStore(fileURL: makeTemporaryURL())
        var expected: [CapturedText] = []

        for index in 0..<105 {
            let item = CapturedText(
                text: "item-\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            expected.append(item)
            _ = try store.append(item)
        }

        expected.removeFirst(5)
        XCTAssertEqual(try store.load(), expected)
        XCTAssertEqual(try store.load().count, CaptureHistoryStore.maximumEntryCount)
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TextLensCoreTests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
    }
}
