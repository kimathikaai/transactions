import SwiftUI

/// The modal's Notes card: an always-visible text box with an "Add notes…" hint.
/// Saves when the field loses focus, on Return, or when it leaves the screen
/// (modal closed) — not per keystroke, so typing doesn't rebuild derived state
/// on every character.
///
/// A vertical `TextField` rather than `TextEditor`: `TextEditor` has no prompt
/// API, and a hand-placed overlay hint doesn't line up with AppKit's text inset
/// (the caret drew through the hint's first letter). Return commits; Option-Return
/// inserts a newline.
struct NotesSection: View {
    @Environment(AppViewModel.self) private var viewModel

    let transaction: Transaction

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(transaction: Transaction) {
        self.transaction = transaction
        _text = State(initialValue: transaction.effectiveNotes ?? "")
    }

    var body: some View {
        TextField("Notes", text: $text, prompt: Text("Add notes…"), axis: .vertical)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.body)
            .focused($isFocused)
            .onSubmit(flush)
            .onChange(of: isFocused) { _, focused in
                if !focused { flush() }
            }
            .onDisappear(perform: flush)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
    }

    private func flush() {
        guard text != (transaction.effectiveNotes ?? "") else { return }
        viewModel.updateNotes(for: transaction, notes: text.isEmpty ? nil : text)
    }
}
