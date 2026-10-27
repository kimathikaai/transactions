import SwiftUI

struct ReservesContent: View {
    var onAdd: () -> Void
    var onSelect: (Reserve) -> Void
    var onMoneyAction: (Reserve, ReserveMoneyAction) -> Void
    var onDelete: (Reserve) -> Void
    var onActivity: (Reserve) -> Void

    @Environment(AppViewModel.self) private var viewModel

    // Add/Release need at least one reservoir source to move money to or from.
    private var canAddOrRelease: Bool {
        !viewModel.reservoirSources.isEmpty
    }

    // Using additionally needs at least one expense transaction to link.
    private var canUse: Bool {
        canAddOrRelease && !viewModel.expenseTransactions.isEmpty
    }

    // Reserves ordered so the closest-to-complete goals sink to the bottom:
    // primary key is filled % ((held + used)/target), tie-broken by used/target.
    // Keys are precomputed once per reserve rather than recomputed in the comparator.
    private var sortedReserves: [Reserve] {
        let reservations = viewModel.reservations
        let events = viewModel.reserveEvents
        return viewModel.reserves
            .map { reserve -> (reserve: Reserve, filled: Double, used: Double) in
                let filled = filledProgress(of: reserve, reservations: reservations, events: events)
                let usedRatio = reserve.target > 0 ? used(of: reserve.id, events: events) / reserve.target : 0
                return (reserve, filled, usedRatio)
            }
            .sorted { a, b in
                if a.filled != b.filled { return a.filled < b.filled }  // more filled → lower
                return a.used < b.used                                   // tie-break: more used → lower
            }
            .map(\.reserve)
    }

    var body: some View {
        VStack(spacing: 8){
            ReservesHeaderRow()
            Divider()
            AddReserveRow(onTap: onAdd)
            ScrollView{
                ForEach(sortedReserves) { reserve in
                    ReserveCardView(
                        reserve: reserve,
                        onEdit: { onSelect(reserve) },
                        onActivity: { onActivity(reserve) },
                        onDelete: { onDelete(reserve) },
                        canAddOrRelease: canAddOrRelease,
                        canUse: canUse,
                        onMoneyAction: { onMoneyAction(reserve, $0) }
                    )
                }
            }
        }
    }
}

// MARK: - Header Row

/// Column labels above the list. Mirrors `ReserveCardView`'s leading geometry
/// (emoji + ring slots) and trailing column widths so the numeric columns line
/// up exactly with each card's Used/Held/Target figures.
private struct ReservesHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // "Reserve" spans the emoji + ring + name area, left-justified from the edge.
            header("Reserve").frame(maxWidth: .infinity, alignment: .leading)
            header("Used").frame(width: 80, alignment: .trailing)
            header("Reserved").frame(width: 80, alignment: .trailing)
            header("Target").frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Add Row

private struct AddReserveRow: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                Text("Add New Reserve")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.gray.opacity(0.1), in: .rect(cornerRadius: 6))
        .hoverHighlight(in: .rect(cornerRadius: 6))
        .frame(height: 30)
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
    vm.upsertReserve(Reserve(name: "Vacation", emoji: "🏖️", colorHex: "", target: 5_000, tagline: "Costa Rica · December"))
    vm.upsertReserve(Reserve(name: "New Bike", emoji: "🚲", colorHex: "", target: 850, tagline: "Spring rebuild"))
    vm.upsertReserve(Reserve(name: "Emergency Fund", emoji: "🛡️", colorHex: "", target: 10_000, tagline: ""))

    return SectionContainer(title: "Reserves") {
        ReservesContent(onAdd: {}, onSelect: { _ in }, onMoneyAction: { _, _ in }, onDelete: { _ in }, onActivity: { _ in })
    }
    .frame(width: 720)
    .padding(20)
    .environment(vm)
}
