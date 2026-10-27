import SwiftUI

/// The content of one category section card (analogous to `ReservesContent`).
/// Renders an optional add row, then the roots for this column with their
/// leaves indented underneath. Selecting a row or the add row is delegated
/// to the parent via closures.
struct CategoryColumn: View {
    /// The transaction types this column displays. Expense/Income are a single
    /// type; the Transfers column covers both `transfer_in` and `transfer_out`.
    let types: [TransactionType]
    let showsAddRow: Bool
    var onAdd: () -> Void = {}
    var onSelect: (Category) -> Void = { _ in }

    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 8) {
            if showsAddRow {
                AddCategoryRow(onTap: onAdd)
                Divider()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(roots, id: \.id) { root in
                        CategoryCardRow(
                            category: root,
                            isRoot: true,
                            leafCount: leaves(of: root.id).count,
                            onSelect: onSelect
                        )
                        ForEach(leaves(of: root.id), id: \.id) { leaf in
                            CategoryCardRow(
                                category: leaf,
                                isRoot: false,
                                leafCount: 0,
                                onSelect: onSelect
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: Derived

    private var inColumn: [Category] {
        viewModel.categories.filter { types.contains($0.transactionType) }
    }

    private var roots: [Category] {
        inColumn.filter { $0.parent == nil }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    private func leaves(of rootID: String) -> [Category] {
        inColumn.filter { $0.parent == rootID }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }
}

// MARK: - Add Row

private struct AddCategoryRow: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                Text("Add New Category")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(in: .rect(cornerRadius: 12))
    }
}

#Preview {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let vm = AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
    return SectionContainer(title: "Expense") {
        CategoryColumn(types: [.expense], showsAddRow: true)
    }
    .frame(width: 320)
    .padding(20)
    .environment(vm)
}
