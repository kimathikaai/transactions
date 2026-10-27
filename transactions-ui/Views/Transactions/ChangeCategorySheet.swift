import SwiftUI

/// A focused modal for recategorizing a transaction — the app's most common
/// edit. Unlike the full `TransactionEditView`, it omits the read-only context
/// card and Reset; it changes type / category / subcategory / notes and shows the
/// importer's original classification for reference. The Type picker and Category
/// picker stay coupled via `CategoryLookup.coerceCategory` (transfer types lock to
/// their transfer root; non-transfer types drop transfer categories). It pre-selects
/// the picker to the transaction's current effective category. Styled like
/// `TransactionEditView`: material cards over a clear background with a glass
/// Cancel/Save footer. Persists through `AppViewModel.saveEdit`.
struct ChangeCategorySheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction

    @State private var selectedCategory: CategoryID?
    @State private var selectedSubcategory: SubcategoryID?
    @State private var notes: String
    @State private var selectedType: TransactionType

    init(transaction: Transaction) {
        self.transaction = transaction
        _selectedCategory = State(initialValue: transaction.effectiveCategory)
        _selectedSubcategory = State(initialValue: transaction.effectiveSubcategory)
        _notes = State(initialValue: transaction.effectiveNotes ?? "")
        _selectedType = State(initialValue: transaction.effectiveType)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        // Dates originate from BankCsvParser anchored at 00:00 UTC — render
        // in UTC so a 2026-06-29 CSV row displays as Jun 29 in any local TZ.
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerCard
            fieldsCard
            notesCard
            footer
        }
        .padding(20)
        .frame(minWidth: 420)
        .presentationBackground(.clear)
        .task {
            viewModel.lastSaveError = nil
        }
    }

    // MARK: Header

    /// Compact read-only identity so it is clear which row is being recategorized:
    /// description, signed amount (tinted by effective type), and date.
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transaction.details)
                .font(.headline)
                .textSelection(.enabled)
            HStack {
                Text(transaction.effectiveAmount, format: .cad)
                    .monospacedDigit()
                    .foregroundStyle(amountTint)
                Spacer(minLength: 0)
                Text(Self.dateFormatter.string(from: transaction.date))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .cardBackground()
    }

    /// Expense/outflow red, income/inflow green — matching the finance tokens.
    private var amountTint: Color {
        switch transaction.effectiveType {
        case .expense, .transfer_out: return .expense
        case .income, .transfer_in:   return .income
        }
    }

    // MARK: Fields

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Original") {
                Text(originalCategoryLabel)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .font(.callout)

            Divider()

            Picker("Type", selection: $selectedType) {
                ForEach(TransactionType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            Divider()

            CategoryPickerMenu(
                transactionType: selectedType,
                selectedCategory: $selectedCategory,
                selectedSubcategory: $selectedSubcategory
            )
        }
        .cardBackground()
        .onChange(of: selectedType) { _, newType in
            // Keep the category consistent with the type as it changes: a transfer
            // type auto-fills + locks its transfer root; switching to expense/income
            // clears a now-invalid transfer category to None. Mirrors saveEdit's coercion.
            let coerced = CategoryLookup.coerceCategory(
                for: newType,
                category: selectedCategory,
                subcategory: selectedSubcategory,
                in: viewModel.categories
            )
            selectedCategory = coerced.category
            selectedSubcategory = coerced.subcategory
        }
    }

    /// The importer's original classification (before any edit): the leaf name when
    /// a subcategory was parsed, otherwise the category name, otherwise "Uncategorized".
    private var originalCategoryLabel: String {
        if let sub = transaction.subcategory,
           let leaf = viewModel.subcategory(id: sub) {
            return leaf.displayName
        }
        if let cat = transaction.category,
           let root = viewModel.category(id: cat) {
            return root.displayName
        }
        return "Uncategorized"
    }

    // MARK: Notes

    private var notesCard: some View {
        TextEditor(text: $notes)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 72)
            .overlay(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Add notes…")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .cardBackground()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let message = viewModel.lastSaveError?.localizedDescription {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button("Save") { commit() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Helpers

    private func commit() {
        // Only persist the type as an override when it differs from the parsed value
        // — keeps the edit row minimal. saveEdit's coercion normalizes the category.
        let typeOverride: TransactionType? = selectedType == transaction.transactionType ? nil : selectedType

        if viewModel.saveEdit(
            for: transaction,
            category: selectedCategory,
            subcategory: selectedSubcategory,
            notes: notes.isEmpty ? nil : notes,
            transactionType: typeOverride
        ) {
            dismiss()
        }
    }
}

// MARK: - Card styling

private extension View {
    /// The shared editor-card recipe: material fill, continuous 16pt corners.
    /// Matches `TransactionEditView` / `CategoryEditSheet` / `ReserveEditSheet`.
    func cardBackground() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
    }
}
