import SwiftUI

/// The modal's Notes section. Saves when the editor loses focus or leaves the
/// screen (section collapsed, modal closed) — not per keystroke, so typing
/// doesn't rebuild derived state on every character.
struct NotesSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let transaction: Transaction
    @Binding var isExpanded: Bool

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(transaction: Transaction, isExpanded: Binding<Bool>) {
        self.transaction = transaction
        _isExpanded = isExpanded
        _text = State(initialValue: transaction.effectiveNotes ?? "")
    }

    var body: some View {
        DetailSection(
            title: "Notes",
            descriptor: "Your own context for this transaction. Searchable from the Transactions list.",
            status: status,
            statusTint: .neutral,
            isExpanded: $isExpanded
        ) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72)
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Add notes…")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { flush() }
                }
                .onDisappear(perform: flush)
        }
    }

    /// The saved notes' first line, short enough for the chip.
    private var status: String {
        guard let notes = transaction.effectiveNotes, !notes.isEmpty else { return "None" }
        let firstLine = notes.split(whereSeparator: \.isNewline).first.map(String.init) ?? notes
        return firstLine.count > 24 ? String(firstLine.prefix(24)) + "…" : firstLine
    }

    private func flush() {
        guard text != (transaction.effectiveNotes ?? "") else { return }
        viewModel.updateNotes(for: transaction, notes: text.isEmpty ? nil : text)
    }
}
