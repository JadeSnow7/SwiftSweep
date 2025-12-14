import Foundation

/// Protocol for storing organization data (categories and app assignments).
public protocol OrganizationStoring {
    func loadCategories() -> [AppCategory]
    func saveCategories(_ categories: [AppCategory])
    func loadAssignments() -> [String: UUID] // BundleID -> CategoryID
    func saveAssignments(_ assignments: [String: UUID])
}

/// Default implementation using UserDefaults.
public final class OrganizationStore: OrganizationStoring {
    private let defaults: UserDefaults
    private let categoriesKey = "appInventory.categories"
    private let assignmentsKey = "appInventory.assignments"
    
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    public func loadCategories() -> [AppCategory] {
        guard let data = defaults.data(forKey: categoriesKey),
              let categories = try? JSONDecoder().decode([AppCategory].self, from: data) else {
            return []
        }
        return categories.sorted { $0.order < $1.order }
    }
    
    public func saveCategories(_ categories: [AppCategory]) {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        defaults.set(data, forKey: categoriesKey)
    }
    
    public func loadAssignments() -> [String: UUID] {
        guard let data = defaults.data(forKey: assignmentsKey),
              let assignments = try? JSONDecoder().decode([String: UUID].self, from: data) else {
            return [:]
        }
        return assignments
    }
    
    public func saveAssignments(_ assignments: [String: UUID]) {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        defaults.set(data, forKey: assignmentsKey)
    }
}
