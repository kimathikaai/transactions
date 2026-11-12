import SwiftUI

struct ReservesPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showCreate = false
    @State private var moneyRequest: ReserveMoneyRequest?
    @State private var selectedReserve: Reserve?
    @State private var activityReserve: Reserve?

    /// A pending money-movement action, targeted at the right-clicked reserve.
    /// Item-driven so the sheet always opens pre-targeted (no in-sheet picker).
    private struct ReserveMoneyRequest: Identifiable {
        let id = UUID()
        let reserve: Reserve
        let action: ReserveMoneyAction
    }

    /// Shared content height of the Reservoir and Sources cards; Sources scrolls if taller.
    /// Matches the Transactions tab's breakdown cards (`CategoryBreakdownCard`: 22pt bar +
    /// 10pt spacing + 66pt legend viewport) so both pages' top rows are the same height.
    private let reservoirCardHeight: CGFloat = 98
    /// Shared width of the right-hand column (Reservoir above, Activity below).
    private let sideColumnWidth: CGFloat = 240

    /// Caption-sized so the My Reserves title row stays level with Activity's.
    private var addReserveButton: some View {
        Button {
            showCreate = true
        } label: {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(.rect(cornerRadius: 4))
                .hoverHighlight(in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("New Reserve")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Sources (fills the rest) beside Reservoir in the shared right column, no rail gutter.
            HStack(alignment: .top, spacing: 12) {
                SectionContainer(title: "Sources", style: .outlined) {
                    ScrollView {
                        SourcesContent(sources: viewModel.perSourceSummary)
                    }
                    .frame(height: reservoirCardHeight)
                }

                SectionContainer(title: "Reservoir", style: .outlined) {
                    SummaryContent(summary: viewModel.reservoirSummary)
                        .frame(height: reservoirCardHeight)
                }
                .frame(width: sideColumnWidth)
            }

            // My Reserves grid (outlined, fills the rest) beside a fixed-width Activity column.
            HStack(alignment: .top, spacing: 12) {
                SectionContainer(title: "My Reserves", style: .outlined) {
                    addReserveButton
                } content: {
                    ReservesContent(
                        onSelect: { selectedReserve = $0 },
                        onMoneyAction: { moneyRequest = ReserveMoneyRequest(reserve: $0, action: $1) },
                        onDelete: { viewModel.deleteReserve(id: $0.id) },
                        onActivity: { activityReserve = $0 }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                SectionContainer(title: "Activity") {
                    ActivityContent(rows: viewModel.reserveActivity, compact: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: sideColumnWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .sheet(isPresented: $showCreate) {
            ReserveEditSheet(reserve: nil)
                .environment(viewModel)
        }
        .sheet(item: $moneyRequest) { request in
            switch request.action {
            case .add:
                ReserveTransferSheet(mode: .allocate, reserve: request.reserve)
                    .environment(viewModel)
            case .release:
                ReserveTransferSheet(mode: .release, reserve: request.reserve)
                    .environment(viewModel)
            case .use:
                ReserveUseSheet(reserve: request.reserve)
                    .environment(viewModel)
            }
        }
        .sheet(item: $selectedReserve) { reserve in
            ReserveEditSheet(reserve: reserve)
                .environment(viewModel)
        }
        .sheet(item: $activityReserve) { reserve in
            ReserveActivitySheet(reserve: reserve)
                .environment(viewModel)
        }
    }
}
