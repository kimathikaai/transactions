import Foundation

/// Pure formatter: turns `CategoryValidationResult` sub-lists into a
/// pretty-printed JSON array string suitable for clipboard export.
///
/// Kept outside `#if DEBUG` so it stays unit-testable via `xcodebuild test`.
/// The only caller is the DEBUG-only `DebugPanelView` copy buttons.
enum DebugValidationClipboard {

    static func brokenEditsJSON(_ items: [BrokenEdit]) -> String {
        let objects = items.map { b -> [String: String] in
            [
                "contentHash": b.contentHash,
                "field": b.field.rawValue,
                "referencedID": b.referencedID,
            ]
        }
        return encode(objects)
    }

    static func structuralViolationsJSON(_ items: [StructuralViolation]) -> String {
        let objects = items.map { v -> [String: String] in
            [
                "categoryID": v.categoryID,
                "displayName": v.displayName,
                "kind": v.kind.rawValue,
            ]
        }
        return encode(objects)
    }

    static func staleRefsJSON(_ items: [StaleEditRef]) -> String {
        let objects = items.map { ["contentHash": $0.contentHash] }
        return encode(objects)
    }

    static func danglingUseLinksJSON(_ items: [AppViewModel.DanglingUseLink]) -> String {
        let objects = items.map { ["reserve": $0.reserveName, "contentHash": $0.contentHash] }
        return encode(objects)
    }

    static func danglingReimbursementLinksJSON(_ items: [AppViewModel.DanglingReimbursementLink]) -> String {
        let objects = items.map { link -> [String: String] in
            [
                "expenseHash": link.expenseHash,
                "reimbursementHash": link.reimbursementHash,
                "missing": [link.expenseMissing ? "expense" : nil,
                            link.sourceMissing ? "source" : nil]
                    .compactMap { $0 }.joined(separator: "+"),
            ]
        }
        return encode(objects)
    }

    // MARK: - Private

    private static func encode(_ objects: [[String: String]]) -> String {
        guard !objects.isEmpty else { return "[]" }
        let data = try! JSONSerialization.data(
            withJSONObject: objects,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
