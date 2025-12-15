import XCTest
@testable import AppInventoryLogic

final class OrganizationStoreTests: XCTestCase {
    
    var defaults: UserDefaults!
    var store: OrganizationStore!
    
    override func setUp() {
        super.setUp()
        let suiteName = "test.organizationstore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = OrganizationStore(defaults: defaults)
    }
    
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }
    
    // MARK: - Categories
    
    func testSaveAndLoadCategories() {
        let categories = [
            AppCategory(name: "Games", order: 0),
            AppCategory(name: "Productivity", order: 1),
            AppCategory(name: "Media", order: 2)
        ]
        
        store.saveCategories(categories)
        let loaded = store.loadCategories()
        
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].name, "Games")
        XCTAssertEqual(loaded[1].name, "Productivity")
        XCTAssertEqual(loaded[2].name, "Media")
    }
    
    func testCategoriesOrderPreserved() {
        var categories = [
            AppCategory(name: "A", order: 0),
            AppCategory(name: "B", order: 1),
            AppCategory(name: "C", order: 2)
        ]
        
        // Reorder
        categories[0].order = 2
        categories[2].order = 0
        categories.sort { $0.order < $1.order }
        
        store.saveCategories(categories)
        let loaded = store.loadCategories()
        
        XCTAssertEqual(loaded[0].name, "C")
        XCTAssertEqual(loaded[2].name, "A")
    }
    
    func testEmptyCategoriesReturnsEmptyArray() {
        let loaded = store.loadCategories()
        XCTAssertTrue(loaded.isEmpty)
    }
    
    // MARK: - Assignments
    
    func testSaveAndLoadAssignments() {
        let catID1 = UUID()
        let catID2 = UUID()
        let assignments: [String: UUID] = [
            "com.app1": catID1,
            "com.app2": catID2,
            "com.app3": catID1
        ]
        
        store.saveAssignments(assignments)
        let loaded = store.loadAssignments()
        
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded["com.app1"], catID1)
        XCTAssertEqual(loaded["com.app2"], catID2)
        XCTAssertEqual(loaded["com.app3"], catID1)
    }
    
    func testRemoveAssignment() {
        let catID = UUID()
        var assignments: [String: UUID] = [
            "com.keep": catID,
            "com.remove": catID
        ]
        
        store.saveAssignments(assignments)
        
        assignments.removeValue(forKey: "com.remove")
        store.saveAssignments(assignments)
        
        let loaded = store.loadAssignments()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded["com.remove"])
    }
    
    func testEmptyAssignmentsReturnsEmptyDict() {
        let loaded = store.loadAssignments()
        XCTAssertTrue(loaded.isEmpty)
    }
    
    // MARK: - Encode/Decode Stability
    
    func testCategoryEncodeDecode() {
        let original = AppCategory(name: "Test 🎮", order: 5)
        
        // Save single category
        store.saveCategories([original])
        let loaded = store.loadCategories()
        
        XCTAssertEqual(loaded.first?.name, "Test 🎮")
        XCTAssertEqual(loaded.first?.order, 5)
        XCTAssertEqual(loaded.first?.id, original.id)
    }
}
