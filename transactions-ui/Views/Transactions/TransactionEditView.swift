import SwiftUI

/// Edit a transaction's overrides (type / category / subcategory / notes). The
/// amount is shown read-only — its sign follows the selected type. Styled after
/// `CategoryEditSheet` / `ReserveEditSheet`: material cards floating over a clear
/// background, label/value rows, and a glass Cancel/Save footer. Persists through
/// `AppViewModel.saveEdit`; the "minimal override" logic in `commit()` keeps
/// unchanged fields out of the edit record.
struct TransactionEditView: View {
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
            contextCard
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

    // MARK: Context

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            contextRow("Date", Self.dateFormatter.string(from: transaction.date))
            Divider()
            contextRow("Account", viewModel.account(id: transaction.accountID)?.name ?? "—")
            Divider()
            amountRow
            Divider()
            contextRow("Description", transaction.details)
        }
        .cardBackground()
    }

    /// Read-only amount. The magnitude comes from the parsed transaction; the sign
    /// and color follow the currently selected type, previewing how a type change
    /// will re-sign the amount once saved.
    private var amountRow: some View {
        LabeledContent {
            Text(signedAmount, format: .cad)
                .monospacedDigit()
                .foregroundStyle(amountTint)
        } label: {
            Text("Amount")
        }
        .font(.callout)
    }

    @ViewBuilder
    private func contextRow(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(label)
        }
        .font(.callout)
    }

    // MARK: Fields

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    /// Tint the amount by the selected type: expenses/outflows red, income/
    /// inflows green — matching the finance color tokens used across the app.
    private var amountTint: Color {
        switch selectedType {
        case .expense, .transfer_out: return .expense
        case .income, .transfer_in:   return .income
        }
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
            Button { reset() } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.glass)
            .disabled(transaction.edit == nil)

            if let message = footerMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.lastSaveError != nil ? .red : .secondary)
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

    /// Only a save failure produces footer text; there is no amount to validate.
    private var footerMessage: String? {
        viewModel.lastSaveError?.localizedDescription
    }

    // MARK: Helpers

    /// A single selection value spanning the category → subcategory hierarchy, so
    /// one menu picker can drive both `selectedCategory` and `selectedSubcategory`.
    private enum CategoryChoice: Hashable {
        case none
        case category(CategoryID)
        case subcategory(root: CategoryID, leaf: SubcategoryID)
    }

    /// Root categories, alphabetized for the top-level menu.
    private var sortedRootCategories: [Category] {
        viewModel.rootCategories()
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

    /// The parsed magnitude signed per the selected type (expense / transfer_out →
    /// negative, income / transfer_in → positive). Drives the read-only amount row's
    /// value and color; the amount is not user-editable.
    private var signedAmount: Double {
        let magnitude = abs(transaction.amount)
        switch selectedType {
        case .expense, .transfer_out: return -magnitude
        case .income, .transfer_in:   return magnitude
        }
    }

    private func commit() {
        // Only persist the type as an override when it differs from the parsed value
        // — keeps the edit row minimal.
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

    private func reset() {
        if viewModel.clearEdit(for: transaction) {
            dismiss()
        }
    }
}

// MARK: - Card styling

private extension View {
    /// The shared editor-card recipe: material fill, continuous 16pt corners.
    /// Matches `CategoryEditSheet` / `ReserveEditSheet`.
    func cardBackground() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
    }
}
