import SwiftUI

/// The modal's Category section: what the import rules picked, the live Type and
/// Category pickers, and a revert back to the rules. Every pick saves at once via
/// `updateClassification`. Type is locked while the transaction has a
/// reimbursement or reserve link (`AppViewModel.isTypeLocked`).
struct CategorySection: View {
    @Environment(AppViewModel.self) private var viewModel

    let transaction: Transaction
    @Binding var isExpanded: Bool

    // Local mirrors so the two-binding category picker produces one save per pick.
    @State private var selectedType: TransactionType
    @State private var selectedCategory: CategoryID?
    @State private var selectedSubcategory: SubcategoryID?

    init(transaction: Transaction, isExpanded: Binding<Bool>) {
        self.transaction = transaction
        _isExpanded = isExpanded
        _selectedType = State(initialValue: transaction.effectiveType)
        _selectedCategory = State(initialValue: transaction.effectiveCategory)
        _selectedSubcategory = State(initialValue: transaction.effectiveSubcategory)
    }

    var body: some View {
        DetailSection(
            title: "Category",
            descriptor: "How this transaction counts in your Expense and Income breakdowns. The rules picked a category on import; a change here overrides it.",
            status: status.text,
            statusTint: status.tint,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                rulesPickedBox
                typePicker
                Divider()
                CategoryPickerMenu(
                    transactionType: selectedType,
                    selectedCategory: $selectedCategory,
                    selectedSubcategory: $selectedSubcategory
                )
                revertButton
            }
        }
        .onChange(of: selectedType) { _, newType in saveType(newType) }
        .onChange(of: [selectedCategory?.rawValue, selectedSubcategory?.rawValue]) { saveCategory() }
    }

    // MARK: Pieces

    private var status: (text: String, tint: DetailStatusTint) {
        switch transaction.categorySource {
        case .rule:          return ("Rule", .done)
        case .overridden:    return ("Overridden", .attention)
        case .uncategorized: return ("Uncategorized", .attention)
        }
    }

    /// The import-time classification, for reference against any override.
    private var rulesPickedBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rules picked")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(rulesPickedText)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rulesPickedText: String {
        let type = transaction.transactionType.displayName
        guard let category = transaction.category else { return "\(type) · No rule matched" }
        return "\(type) · \(categoryLabel(category, transaction.subcategory))"
    }

    private var typePicker: some View {
        let locked = viewModel.isTypeLocked(transaction)
        return VStack(alignment: .leading, spacing: 4) {
            Picker("Type", selection: $selectedType) {
                ForEach(TransactionType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)
            .font(.callout)
            .disabled(locked)
            if locked {
                Text("Unlink the reimbursement, reserve use, or transfer link to change the type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var revertButton: some View {
        Button {
            if viewModel.revertClassification(for: transaction) { syncFromLive() }
        } label: {
            Label("Revert to rules' pick", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.glass)
        .disabled(!canRevert)
    }

    /// Something to revert: a category override, or a type override that isn't
    /// locked by a link (a locked type stays put on revert).
    private var canRevert: Bool {
        guard let edit = transaction.edit else { return false }
        return edit.category != nil
            || (edit.transactionType != nil && !viewModel.isTypeLocked(transaction))
    }

    private func categoryLabel(_ category: CategoryID, _ subcategory: SubcategoryID?) -> String {
        let name = viewModel.category(id: category)?.displayName ?? category.rawValue
        guard let subcategory else { return name }
        return "\(name) › \(viewModel.subcategory(id: subcategory)?.displayName ?? subcategory.rawValue)"
    }

    // MARK: Live writes

    /// Re-couple the category to the new type (transfers lock to their root;
    /// expense/income drop a now-invalid category), then save both in one write.
    private func saveType(_ newType: TransactionType) {
        guard newType != transaction.effectiveType else { return }
        let coerced = CategoryLookup.coerceCategory(
            for: newType,
            category: selectedCategory,
            subcategory: selectedSubcategory,
            in: viewModel.categories
        )
        selectedCategory = coerced.category
        selectedSubcategory = coerced.subcategory
        viewModel.updateClassification(for: transaction, type: newType,
                                       category: coerced.category, subcategory: coerced.subcategory)
        syncFromLive()
    }

    private func saveCategory() {
        guard selectedCategory != transaction.effectiveCategory
                || selectedSubcategory != transaction.effectiveSubcategory else { return }
        viewModel.updateClassification(for: transaction, type: selectedType,
                                       category: selectedCategory, subcategory: selectedSubcategory)
        syncFromLive()
    }

    /// Mirror what was actually stored (a "None" pick resolves back to the rules'
    /// pick). The guards above make the resulting onChange a no-op.
    private func syncFromLive() {
        guard let live = viewModel.transaction(withHash: transaction.contentHash) else { return }
        selectedType = live.effectiveType
        selectedCategory = live.effectiveCategory
        selectedSubcategory = live.effectiveSubcategory
    }
}
