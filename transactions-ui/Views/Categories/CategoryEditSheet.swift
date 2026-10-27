import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Create/edit a category. Styled after `ReserveEditSheet`: material cards, no
/// field captions where a placeholder carries intent. `category == nil` is
/// create mode. Commits through the existing `AppViewModel` category ops.
struct CategoryEditSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let category: Category?

    @State private var name: String
    @State private var color: String
    @State private var symbol: String
    @State private var parent: String?
    @State private var transactionType: TransactionType

    @State private var showDeleteConfirm = false
    @State private var showMergeSheet = false
    @State private var saveError: String?

    @FocusState private var nameFocused: Bool

    /// - Parameters:
    ///   - category: the record to edit, or `nil` to create.
    ///   - defaultType: the column's type, used to seed a new category.
    init(category: Category?, defaultType: TransactionType = .expense) {
        self.category = category
        _name = State(initialValue: category?.displayName ?? "")
        _color = State(initialValue: category?.color ?? "#d9d9d9")
        _symbol = State(initialValue: category?.symbol ?? "")
        _parent = State(initialValue: category?.parent)
        _transactionType = State(initialValue: category?.transactionType ?? defaultType)
    }

    private var isCreate: Bool { category == nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var symbolIsValid: Bool {
        guard !symbol.isEmpty else { return false }
        #if canImport(AppKit)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        #elseif canImport(UIKit)
        return UIImage(systemName: symbol) != nil
        #else
        return true
        #endif
    }

    private var nameCollision: Category? {
        guard !trimmedName.isEmpty else { return nil }
        return viewModel.categories.first {
            $0.displayName == trimmedName && $0.id != category?.id
        }
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && nameCollision == nil && symbolIsValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identityCard
            placementCard
            if !isCreate { dangerCard }
            footer
        }
        .padding(20)
        .frame(minWidth: 420)
        .presentationBackground(.clear)
        .onAppear { nameFocused = true }
        .sheet(isPresented: $showMergeSheet) {
            if let source = category {
                MergeSheet(source: source) { targetID in
                    _ = viewModel.mergeCategory(source: source.id, into: targetID)
                    showMergeSheet = false
                    dismiss()
                } onCancel: { showMergeSheet = false }
                .environment(viewModel)
            }
        }
        .confirmationDialog("Delete category?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteCaption)
        }
    }

    // MARK: Identity

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TextField("New Category", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title.weight(.bold))
                    .focused($nameFocused)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(hex: color) },
                    set: { color = $0.toHex() }
                ))
                .labelsHidden()
            }
            if let collider = nameCollision {
                Text("Already used by \(collider.displayName)")
                    .font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("SF Symbol", text: $symbol)
                    .textFieldStyle(.plain)
                    .font(.callout)
                Image(systemName: symbolIsValid ? symbol : "questionmark.circle")
                    .foregroundStyle(symbolIsValid ? Color.primary : Color.red)
            }
            if !symbolIsValid {
                Text("Not a valid SF Symbol")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    // MARK: Placement

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Type", value: transactionType.displayName)
                .font(.callout)

            Divider()

            Picker("Parent", selection: $parent) {
                Text("— Root category —").tag(String?.none)
                ForEach(validParents, id: \.id) { p in
                    Text(p.displayName).tag(String?.some(p.id))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    /// Roots of the same type, excluding self (a category can't parent itself).
    private var validParents: [Category] {
        viewModel.categories.filter {
            $0.parent == nil
            && $0.transactionType == transactionType
            && $0.id != category?.id
        }
        .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    // MARK: Danger zone

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) { showMergeSheet = true } label: {
                Label("Merge into another category", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(deleteDisabled ? Color.secondary : Color.red)
            }
            .buttonStyle(.plain)
            .disabled(deleteDisabled)
            Text(deleteCaption)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var deleteDisabled: Bool {
        guard let id = category?.id else { return true }
        return viewModel.categories.contains { $0.parent == id }
    }

    private var deleteCaption: String {
        guard let id = category?.id else { return "" }
        if viewModel.categories.contains(where: { $0.parent == id }) {
            let n = viewModel.categories.filter { $0.parent == id }.count
            return "Has \(n) children — re-parent or delete them first."
        }
        let editCount = countEdits(referencing: id)
        let patCount = category?.patterns.count ?? 0
        return "This will orphan \(editCount) edits. \(patCount) patterns will be lost."
    }

    private func countEdits(referencing id: String) -> Int {
        var n = 0
        for (_, e) in viewModel.editStoreEdits {
            if e.category?.rawValue == id || e.subcategory?.rawValue == id { n += 1 }
        }
        return n
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            if let saveError {
                HStack {
                    Text(saveError).font(.caption).foregroundStyle(.red)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                if !canSave {
                    Text("Name and valid symbol required")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(isCreate ? "Create" : "Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
    }

    // MARK: Actions

    private func save() {
        saveError = nil
        if isCreate {
            let draft = CategoryDraft(
                displayName: trimmedName,
                parent: parent,
                color: color,
                symbol: symbol,
                transactionType: transactionType,
                patterns: []
            )
            if viewModel.addCategory(draft) {
                dismiss()
            } else {
                saveError = "Could not create category."
            }
            return
        }

        guard let original = category else { return }
        // Order mirrors the previous CategoryEditorForm.commit(): identity /
        // placement first, then presentation.
        if original.displayName != trimmedName {
            if !viewModel.renameCategory(id: original.id, to: trimmedName) {
                saveError = "Could not rename category."
                return
            }
        }
        if original.parent != parent {
            if !viewModel.reparentCategory(id: original.id, to: parent) {
                saveError = "Cannot change parent — target has children or type mismatch."
                return
            }
        }
        if original.color != color {
            if !viewModel.updateCategoryColor(id: original.id, color: color) {
                saveError = "Could not update color."
                return
            }
        }
        if original.symbol != symbol {
            if !viewModel.updateCategorySymbol(id: original.id, symbol: symbol) {
                saveError = "Could not update symbol."
                return
            }
        }
        dismiss()
    }

    private func performDelete() {
        guard let id = category?.id else { return }
        _ = viewModel.deleteCategory(id: id)
        dismiss()
    }
}

// MARK: - Previews

private func previewViewModel() -> AppViewModel {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AppViewModel(
        accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
        reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
        reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
        editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
    )
}

#Preview("Create") {
    CategoryEditSheet(category: nil, defaultType: .expense)
        .frame(width: 460)
        .padding(40)
        .environment(previewViewModel())
}

#Preview("Edit") {
    CategoryEditSheet(category: Category(
        id: "cat_food", displayName: "Food", parent: nil,
        color: "#EB5757", symbol: "fork.knife",
        transactionType: .expense, patterns: []
    ))
    .frame(width: 460)
    .padding(40)
    .environment(previewViewModel())
}
