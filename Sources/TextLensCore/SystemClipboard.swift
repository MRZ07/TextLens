import AppKit
import Foundation

public struct SystemClipboard: ClipboardWriting {
    public init() {}

    public func copy(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw SystemClipboardError.writeFailed
        }
    }
}

private enum SystemClipboardError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "Text could not be copied to the clipboard. Check that the pasteboard is available and try again."
    }
}
