import SwiftUI

/// Links section, "link to existing": search every transaction, select one row,
/// then press Link. Likely matches (same amount, within 3 days) are ranked first.
/// The kind is inferred and named next to the button.
struct LinkCandidatePicker: View {
    @Environment(AppViewModel.self) private var viewModel

    let source: Transaction

    @State private var query = ""
    // Selected row by contentHash — persists even if a query later hides it.
    @State private var selectedID: String?
    @State private var note = ""

    private let dateWidth: CGFloat = 90
    private let amountWidth: CGFloat = 90

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        // CSV dates are anchored at 00:00 UTC — render in UTC (see TransactionCard).
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Counterparts of the source's manual links — already linked, so not offered.
    private var alreadyLinked: Set<String> {
        Set(viewModel.links(for: source.contentHash)
            .filter { $0.origin != .auto }
            .map(\.counterpartHash))
    }

    private var candidates: [TransactionSnapshot] {
        LinkCandidates.ranked(for: source, from: viewModel.transactionsByDateDesc, alreadyLinked: alreadyLinked)
            .filter { $0.matches(searchText: query) }
    }

    private var selected: Transaction? {
        selectedID.flatMap { viewModel.transaction(withHash: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link to existing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            searchField
            columnHeader
            table(candidates)
            HStack(spacing: 8) {
                TextField("Link note (optional)", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                if let selected {
                    Text(viewModel.inferredLinkKind(between: source, and: selected) == .transfer
                         ? "Links as Transfer" : "Links as Related")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Button("Link", action: linkSelected)
                    .buttonStyle(.glassProminent)
                    .disabled(selected == nil)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search details, notes, amount", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dateWidth, alignment: .leading)
            Text("Details · Account").frame(maxWidth: .infinity, alignment: .leading)
            Text("Amount").frame(width: amountWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private func table(_ rows: [TransactionSnapshot]) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if rows.isEmpty {
                    Text("No matching transactions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                } else {
                    ForEach(rows) { snap in
                        row(snap)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private func row(_ snap: TransactionSnapshot) -> some View {
        let isSelected = selectedID == snap.id
        let detailText = snap.accountName.map { "\(snap.details) · \($0)" } ?? snap.details
        return Button {
            selectedID = isSelected ? nil : snap.id
        } label: {
            HStack(spacing: 8) {
                Text(Self.dateFormatter.string(from: snap.date))
                    .frame(width: dateWidth, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(detailText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detailText)
                Text(snap.effectiveAmount, format: .cad)
                    .frame(width: amountWidth, alignment: .trailing)
            }
            .font(.callout)
            .monospacedDigit()
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func linkSelected() {
        guard let selected else { return }
        if viewModel.linkTransactions(source, selected, note: note) {
            selectedID = nil
            query = ""
            note = ""
        }
    }
}
