import SwiftUI

struct ReservesPage: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showCreate = false
    @State private var moneyRequest: ReserveMoneyRequest?
    @State private var selectedReserve: Reserve?
    @State private var activityReserve: Reserve?
    @State private var isHoveringReservoir = false

    /// A pending money-movement action, targeted at the right-clicked reserve.
    /// Item-driven so the sheet always opens pre-targeted (no in-sheet picker).
    private struct ReserveMoneyRequest: Identifiable {
        let id = UUID()
        let reserve: Reserve
        let action: ReserveMoneyAction
    }

    private let reservoirCardHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TabbedSection {
                SectionTab(isHoveringReservoir ? "Sources" : "Reservoir", symbol: "drop") {
                    SummaryContent(summary: viewModel.reservoirSummary)
                        .frame(height: reservoirCardHeight)
                        .opacity(isHoveringReservoir ? 0 : 1)
                        // Sources cover overlay: matches the summary frame, scrolls if taller.
                        .overlay {
                            ScrollView {
                                SourcesContent(sources: viewModel.perSourceSummary)
                            }
                            .opacity(isHoveringReservoir ? 1 : 0)
                            .allowsHitTesting(isHoveringReservoir)
                        }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.05)) {
                    isHoveringReservoir = hovering
                }
            }

            TabbedSection {
                SectionTab("Reserves", symbol: "tray.2", help: "Reserves — savings goals") {
                    ReservesContent(
                        onAdd: { showCreate = true },
                        onSelect: { selectedReserve = $0 },
                        onMoneyAction: { moneyRequest = ReserveMoneyRequest(reserve: $0, action: $1) },
                        onDelete: { viewModel.deleteReserve(id: $0.id) },
                        onActivity: { activityReserve = $0 }
                    )
                }
                SectionTab(
                    "Activity",
                    symbol: "list.bullet",
                    help: "Activity — allocation, release, and use history"
                ) {
                    ActivityContent(
                        rows: viewModel.reserveActivity,
                        onDelete: { viewModel.deleteReserveEvent(id: $0) }
                    )
                }
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
                ReserveUseSheet(seed: .fromReserve(request.reserve))
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
