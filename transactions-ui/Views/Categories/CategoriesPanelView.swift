import SwiftUI

/// The Categories page: a single tabbed section card with Expense / Income /
/// Transfers tabs (switched via the hover rail), mirroring the Reserves and
/// Transactions panel style. Create and edit happen in a pop-out
/// `CategoryEditSheet`; the tab contents themselves are read-only lists.
struct CategoriesPanelView: View {
    @Environment(AppViewModel.self) private var viewModel

    // Create mode carries the tab's default type; edit mode carries the record.
    @State private var createType: TransactionType?
    @State private var editingCategory: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TabbedSection {
                SectionTab("Expense", symbol: "cart", help: "Expense categories") {
                    CategoryColumn(
                        types: [.expense],
                        showsAddRow: true,
                        onAdd: { createType = .expense },
                        onSelect: { editingCategory = $0 }
                    )
                }
                SectionTab("Income", symbol: "dollarsign.circle", help: "Income categories") {
                    CategoryColumn(
                        types: [.income],
                        showsAddRow: true,
                        onAdd: { createType = .income },
                        onSelect: { editingCategory = $0 }
                    )
                }
                // Transfer categories are fixed — no add row, edit identity only.
                SectionTab("Transfers", symbol: "arrow.left.arrow.right", help: "Transfer categories (fixed)") {
                    CategoryColumn(
                        types: [.transfer_in, .transfer_out],
                        showsAddRow: false,
                        onSelect: { editingCategory = $0 }
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .sheet(item: $createType) { type in
            CategoryEditSheet(category: nil, defaultType: type)
                .environment(viewModel)
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditSheet(category: category)
                .environment(viewModel)
        }
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
    return CategoriesPanelView()
        .frame(width: 900, height: 500)
        .environment(vm)
}
