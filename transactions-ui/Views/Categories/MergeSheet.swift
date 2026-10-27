import SwiftUI

struct MergeSheet: View {
    @Environment(AppViewModel.self) private var viewModel
    let source: Category
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var selected: String?
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge \(source.displayName) into…")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates, id: \.id) { c in
                        Button {
                            selected = c.id
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: c.color)).frame(width: 10, height: 10)
                                Image(systemName: c.symbol).frame(width: 16)
                                Text(c.displayName)
                                Spacer()
                                let n = viewModel.categories.first(where: { $0.id == c.id })?.patterns.count ?? 0
                                let m = editCount(for: c.id)
                                Text("(\(n) patterns · \(m) edits)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4).padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 5).fill(selected == c.id ? Color.accentColor.opacity(0.18) : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            Text(blastRadius)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button(role: .destructive) { showConfirm = true } label: { Text("Merge") }
                    .disabled(selected == nil)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
        .confirmationDialog("Merge \(source.displayName) into the selected target?",
                            isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Merge", role: .destructive) {
                if let id = selected { onConfirm(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(blastRadius)
        }
    }

    private var candidates: [Category] {
        viewModel.categories.filter {
            $0.id != source.id
            && $0.transactionType == source.transactionType
            && (($0.parent == nil) == (source.parent == nil))
            && (source.parent == nil || $0.parent == source.parent)
        }
    }
    private func editCount(for id: String) -> Int {
        var n = 0
        for (_, e) in viewModel.editStoreEdits {
            if e.category?.rawValue == id || e.subcategory?.rawValue == id { n += 1 }
        }
        return n
    }
    private var blastRadius: String {
        guard let id = selected, let target = viewModel.categories.first(where: { $0.id == id }) else { return "Select a target." }
        return "This will merge \(source.patterns.count) patterns into \(target.displayName) and rewrite \(editCount(for: source.id)) edits."
    }
}
