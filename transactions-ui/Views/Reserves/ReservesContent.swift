import SwiftUI

/// The "My Reserves" grid: one `ReserveCardView` tile per reserve, three columns,
/// scrolling vertically inside its section. Row spacing is measured so exactly
/// `rowsPerPage` rows fill the visible height; further rows scroll.
struct ReservesContent: View {
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let rowsPerPage = 4
    private let minRowSpacing: CGFloat = 12

    /// Measured heights of the scroll viewport and one card (all cards share a height).
    @State private var viewportHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    /// Vertical gap that makes `rowsPerPage` rows end exactly at the viewport's bottom edge,
    /// never tighter than `minRowSpacing`. Falls back to the minimum until both are measured.
    private var rowSpacing: CGFloat {
        guard viewportHeight > 0, cardHeight > 0 else { return minRowSpacing }
        let fitted = (viewportHeight - CGFloat(rowsPerPage) * cardHeight) / CGFloat(rowsPerPage - 1)
        return max(minRowSpacing, fitted)
    }

    var body: some View {
        if viewModel.reserves.isEmpty {
            Text("No reserves yet — click + to add one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: rowSpacing) {
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            cardHeight = $0
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                viewportHeight = $0
            }
        }
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

    return SectionContainer(title: "My Reserves", style: .sunken) {
        ReservesContent(onSelect: { _ in }, onMoneyAction: { _, _ in }, onDelete: { _ in }, onActivity: { _ in })
    }
    .frame(width: 708)
    .padding(20)
    .environment(vm)
}
