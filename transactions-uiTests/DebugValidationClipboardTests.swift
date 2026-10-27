import Foundation
import Testing
@testable import transactions_ui

@Suite("DebugValidationClipboard")
struct DebugValidationClipboardTests {

    @Test("brokenEditsJSON: empty input → []")
    func brokenEmpty() {
        #expect(DebugValidationClipboard.brokenEditsJSON([]) == "[]")
    }

    @Test("brokenEditsJSON: one item → sorted-key JSON")
    func brokenOne() {
        let items = [
            BrokenEdit(contentHash: "3787ae6d0fd6", field: .subcategory, referencedID: "apparel.clothing")
        ]
        let expected = """
        [
          {
            "contentHash" : "3787ae6d0fd6",
            "field" : "subcategory",
            "referencedID" : "apparel.clothing"
          }
        ]
        """
        #expect(DebugValidationClipboard.brokenEditsJSON(items) == expected)
    }

    @Test("brokenEditsJSON: preserves input order")
    func brokenOrder() {
        let items = [
            BrokenEdit(contentHash: "b", field: .category,    referencedID: "x"),
            BrokenEdit(contentHash: "a", field: .subcategory, referencedID: "y"),
        ]
        let s = DebugValidationClipboard.brokenEditsJSON(items)
        let iB = s.range(of: "\"b\"")!.lowerBound
        let iA = s.range(of: "\"a\"")!.lowerBound
        #expect(iB < iA)
    }

    @Test("structuralViolationsJSON: one item → sorted-key JSON with kind rawValue")
    func structuralOne() {
        let items = [
            StructuralViolation(categoryID: "cat_food", displayName: "Food", kind: .orphanLeaf)
        ]
        let expected = """
        [
          {
            "categoryID" : "cat_food",
            "displayName" : "Food",
            "kind" : "orphanLeaf"
          }
        ]
        """
        #expect(DebugValidationClipboard.structuralViolationsJSON(items) == expected)
    }

    @Test("staleRefsJSON: one item → sorted-key JSON")
    func staleOne() {
        let items = [StaleEditRef(contentHash: "abc123def456")]
        let expected = """
        [
          {
            "contentHash" : "abc123def456"
          }
        ]
        """
        #expect(DebugValidationClipboard.staleRefsJSON(items) == expected)
    }

    @Test("structuralViolationsJSON: empty → []")
    func structuralEmpty() {
        #expect(DebugValidationClipboard.structuralViolationsJSON([]) == "[]")
    }

    @Test("staleRefsJSON: empty → []")
    func staleEmpty() {
        #expect(DebugValidationClipboard.staleRefsJSON([]) == "[]")
    }
}
