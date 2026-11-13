import Foundation

public struct CapturedText: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let capturedAt: Date

    public init(id: UUID = UUID(), text: String, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
    }
}
