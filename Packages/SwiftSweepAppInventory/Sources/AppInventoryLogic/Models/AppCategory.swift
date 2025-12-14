import Foundation

public struct AppCategory: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var order: Int
    
    public init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}
