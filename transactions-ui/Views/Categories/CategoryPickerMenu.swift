import SwiftUI

/// A single hierarchical menu that drives both a transaction's category and its
/// subcategory. Root categories sit at the top level (alphabetical), and each
/// root with leaves opens a submenu (also alphabetical) whose first entry
/// re-selects the bare category with no subcategory. A plain `Menu` is used
/// instead of a nested `Picker` because SwiftUI does not surface a selection made
/// inside a nested picker on the collapsed row.
///
/// Extracted from `TransactionEditView` so both the Edit sheet and the dedicated
/// `ChangeCategorySheet` share one source of truth. Renders as a
/// `LabeledContent("Category")` row; the two bindings are the flat category /
/// subcategory state the caller owns.
struct CategoryPickerMenu: View {
    @Environment(AppViewModel.self) private var viewModel

    /// The transaction's (effective) type. The menu only offers roots of this
    /// type; for a transfer type the row is rendered read-only (locked) on the
    /// single fixed transfer root, since transfers have exactly one valid category.
    let transactionType: TransactionType

    @Binding var selectedCategory: CategoryID?
    @Binding var selectedSubcategory: SubcategoryID?

    var body: some View {
        LabeledContent("Category") {
            if isTransfer {
                // Transfers are locked to their single fixed root — no menu, no "None".
                Text(categorySelectionLabel)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    categoryButton(title: "None", symbol: nil, choice: .none)
                    ForEach(sortedRootCategories, id: \.id) { root in
                        categoryMenuItem(for: root)
                    }
                } label: {
                    Text(categorySelectionLabel)
                }
                .fixedSize()
            }
        }
        .font(.callout)
    }

    private var isTransfer: Bool {
        transactionType == .transfer_in || transactionType == .transfer_out
    }

    /// One top-level menu entry per root category. Roots with no leaves are a plain
    /// selectable button; roots with leaves become a submenu (nested `Menu`) whose
    /// first entry re-selects the bare category with no subcategory.
    @ViewBuilder
    private func categoryMenuItem(for root: Category) -> some View {
        let rootID = CategoryID(rawValue: root.id)
        let leaves = viewModel.leafCategories(under: root.id)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if leaves.isEmpty {
            categoryButton(title: root.displayName, symbol: root.symbol, choice: .category(rootID))
        } else {
            Menu {
                categoryButton(title: root.displayName, symbol: root.symbol, choice: .category(rootID))
                Divider()
                ForEach(leaves, id: \.id) { leaf in
                    categoryButton(
                        title: leaf.displayName,
                        symbol: nil,
                        choice: .subcategory(root: rootID, leaf: SubcategoryID(rawValue: leaf.id))
                    )
                }
            } label: {
                Label(root.displayName, systemImage: root.symbol)
            }
        }
    }

    /// A selectable menu row that sets the combined choice and shows a leading
    /// checkmark when it is the current selection.
    @ViewBuilder
    private func categoryButton(title: String, symbol: String?, choice: CategoryChoice) -> some View {
        Button {
            categoryChoiceBinding.wrappedValue = choice
        } label: {
            if categoryChoiceBinding.wrappedValue == choice {
                Label(title, systemImage: "checkmark")
            } else if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }

    /// Text shown on the collapsed Category row: the leaf name when a subcategory
    /// is chosen, otherwise the category name, otherwise "None".
    private var categorySelectionLabel: String {
        switch categoryChoiceBinding.wrappedValue {
        case .none:
            return "None"
        case .category(let cat):
            return viewModel.category(id: cat)?.displayName ?? "None"
        case .subcategory(_, let leaf):
            return viewModel.subcategory(id: leaf)?.displayName ?? "None"
        }
    }

    /// A single selection value spanning the category → subcategory hierarchy, so
    /// one menu picker can drive both `selectedCategory` and `selectedSubcategory`.
    private enum CategoryChoice: Hashable {
        case none
        case category(CategoryID)
        case subcategory(root: CategoryID, leaf: SubcategoryID)
    }

    /// Root categories of the current transaction type, alphabetized for the
    /// top-level menu. Filtering by type keeps the transfer roots out of the
    /// menu for Expense/Income (and vice versa).
    private var sortedRootCategories: [Category] {
        viewModel.rootCategories()
            .filter { $0.transactionType == transactionType }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Bridges the flat `selectedCategory` / `selectedSubcategory` state to the
    /// hierarchical picker's single tag value. When a subcategory is set, its root
    /// is resolved (falling back to the stored category) so the tag matches the one
    /// declared inside the submenu.
    private var categoryChoiceBinding: Binding<CategoryChoice> {
        Binding(
            get: {
                if let sub = selectedSubcategory {
                    let root = selectedCategory
                        ?? viewModel.root(forSubcategory: sub).map { CategoryID(rawValue: $0.id) }
                    if let root {
                        return .subcategory(root: root, leaf: sub)
                    }
                }
                if let cat = selectedCategory {
                    return .category(cat)
                }
                return .none
            },
            set: { choice in
                switch choice {
                case .none:
                    selectedCategory = nil
                    selectedSubcategory = nil
                case .category(let cat):
                    selectedCategory = cat
                    selectedSubcategory = nil
                case .subcategory(let root, let leaf):
                    selectedCategory = root
                    selectedSubcategory = leaf
                }
            }
        )
    }
}
