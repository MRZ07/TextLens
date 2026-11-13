import Foundation

public protocol ScreenCapturing {
    func captureRegion() async throws -> Data?
}

public protocol TextRecognizing {
    func recognize(imageData: Data) async throws -> String
}

public protocol ClipboardWriting {
    func copy(_ text: String) throws
}
