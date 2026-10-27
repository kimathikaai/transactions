import Foundation
import Testing
@testable import transactions_ui

@Suite("Category ops (via AppViewModel)")
struct CategoryOpsTests {

    private func makeVM(
        dir: TempDataDirectory,
        seed: [transactions_ui.Category] = [],
        edits: [String: TransactionEdit] = [:]
    ) throws -> AppViewModel {
        let catURL = dir.file("categories.json")
        let editURL = dir.file("edits.json")
        // Use AtomicJSONFile encoder so ISO-8601 dates survive the load round-trip.
        try AtomicJSONFile.encoder().encode(seed).write(to: catURL)
        try AtomicJSONFile.encoder().encode(edits).write(to: editURL)
        return AppViewModel(
            accountStore:    AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore:     ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore:       EditStore(fileURL: editURL),
            categoryStore:   CategoryStore(fileURL: catURL),
            csvDirectory:    dir.file("csv")
        )
    }

    private func root(_ id: String, _ name: String, _ type: TransactionType = .expense) -> transactions_ui.Category {
        transactions_ui.Category(id: id, displayName: name, parent: nil, color: "#000",
                 symbol: "folder", transactionType: type, patterns: [])
    }

    private func leaf(_ id: String, _ name: String, _ parent: String, patterns: [String] = []) -> transactions_ui.Category {
        transactions_ui.Category(id: id, displayName: name, parent: parent, color: "#000",
                 symbol: "folder", transactionType: .expense, patterns: patterns)
    }

    @Test("Add rejects duplicate displayName")
    func addRejectsDup() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [root("cat_food", "Food")])
        let ok = vm.addCategory(CategoryDraft(displayName: "Food", parent: nil, color: "#111", symbol: "x", transactionType: .expense, patterns: []))
        #expect(ok == false)
    }

    @Test("Add rejects parent-type mismatch")
    func addRejectsTypeMismatch() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [root("cat_food", "Food", .expense)])
        let ok = vm.addCategory(CategoryDraft(displayName: "Salary", parent: "cat_food", color: "#111", symbol: "x", transactionType: .income, patterns: []))
        #expect(ok == false)
    }

    @Test("Rename to duplicate is rejected")
    func renameRejectsDup() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [root("cat_a", "A"), root("cat_b", "B")])
        #expect(vm.renameCategory(id: "cat_a", to: "B") == false)
    }

    @Test("Reparent leaf between roots of the same type")
    func reparentLeaf() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [
            root("cat_food", "Food", .expense),
            root("cat_transport", "Transport", .expense),
            leaf("cat_gas", "Gas", "cat_food"),
        ])
        #expect(vm.reparentCategory(id: "cat_gas", to: "cat_transport") == true)
        #expect(vm.categories.first(where: { $0.id == "cat_gas" })?.parent == "cat_transport")
    }

    @Test("Reparent to a leaf is rejected (2-level max)")
    func reparentToLeafRejected() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [
            root("cat_food", "Food"),
            leaf("cat_gro", "Groceries", "cat_food"),
            leaf("cat_new", "New", "cat_food"),
        ])
        #expect(vm.reparentCategory(id: "cat_new", to: "cat_gro") == false)
    }

    @Test("Demote root that has children is rejected")
    func demoteWithChildrenRejected() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [
            root("cat_food", "Food"),
            leaf("cat_gro", "Groceries", "cat_food"),
            root("cat_transport", "Transport"),
        ])
        #expect(vm.reparentCategory(id: "cat_food", to: "cat_transport") == false)
    }

    @Test("Delete refuses when children exist")
    func deleteRefusesParent() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [root("cat_food", "Food"), leaf("cat_gro", "Groceries", "cat_food")])
        #expect(vm.deleteCategory(id: "cat_food") == false)
    }

    @Test("Delete leaves the record's edits as orphans (no touch)")
    func deleteLeavesEditsAlone() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(
            dir: dir,
            seed: [root("cat_food", "Food")],
            edits: ["h1": TransactionEdit(category: CategoryID(rawValue: "cat_food"))]
        )
        #expect(vm.deleteCategory(id: "cat_food") == true)
        let fresh = try makeVM(dir: dir, seed: vm.categories, edits: ["h1": TransactionEdit(category: CategoryID(rawValue: "cat_food"))])
        #expect(fresh.categoryValidation.brokenEdits.contains { $0.referencedID == "cat_food" })
    }

    @Test("Merge unions patterns and rewrites edits")
    func mergeLeaves() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(
            dir: dir,
            seed: [
                root("cat_food", "Food"),
                leaf("cat_a", "GroA", "cat_food", patterns: ["SOBEYS", "COSTCO"]),
                leaf("cat_b", "GroB", "cat_food", patterns: ["COSTCO", "METRO"]),
            ],
            edits: [
                "h1": TransactionEdit(category: CategoryID(rawValue: "cat_food"),
                                      subcategory: SubcategoryID(rawValue: "cat_a")),
                "h2": TransactionEdit(category: CategoryID(rawValue: "cat_food"),
                                      subcategory: SubcategoryID(rawValue: "cat_b")),
            ]
        )
        #expect(vm.mergeCategory(source: "cat_a", into: "cat_b") == true)
        let target = vm.categories.first { $0.id == "cat_b" }!
        #expect(Set(target.patterns) == ["SOBEYS", "COSTCO", "METRO"])
        #expect(vm.categories.contains { $0.id == "cat_a" } == false)
        // Both edits now point at cat_b.
        #expect(vm.categoryValidation.brokenEdits.isEmpty)
    }

    @Test("Merge rejects when transactionType mismatches")
    func mergeRejectsTypeMismatch() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [
            root("cat_food", "Food", .expense),
            root("cat_salary", "Salary", .income),
        ])
        #expect(vm.mergeCategory(source: "cat_food", into: "cat_salary") == false)
    }

    @Test("addCategory trims whitespace on displayName")
    func addCategoryTrimsWhitespace() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [])
        let ok = vm.addCategory(CategoryDraft(displayName: "Food ", parent: nil,
            color: "#111", symbol: "folder", transactionType: .expense, patterns: []))
        #expect(ok == true)
        #expect(vm.categories.contains(where: { $0.displayName == "Food" }))
        // Subsequent add of an untrimmed duplicate is rejected on displayName.
        let dup = vm.addCategory(CategoryDraft(displayName: "Food", parent: nil,
            color: "#111", symbol: "folder", transactionType: .expense, patterns: []))
        #expect(dup == false)
    }

    @Test("renameCategory trims whitespace on new name")
    func renameCategoryTrimsWhitespace() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [root("cat_x", "X")])
        #expect(vm.renameCategory(id: "cat_x", to: "  Food  ") == true)
        #expect(vm.categories.first(where: { $0.id == "cat_x" })?.displayName == "Food")
    }

    @Test("addCategory rejects empty/whitespace-only displayName")
    func addCategoryRejectsEmptyName() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }
        let vm = try makeVM(dir: dir, seed: [])
        let ok = vm.addCategory(CategoryDraft(displayName: "   ", parent: nil,
            color: "#111", symbol: "folder", transactionType: .expense, patterns: []))
        #expect(ok == false)
        #expect(vm.categories.isEmpty)
    }
}
