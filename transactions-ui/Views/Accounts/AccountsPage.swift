import SwiftUI

struct AccountsPage: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var editingAccount: Account?
    @State private var managingAccount: Account?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                TabbedSection {
                    SectionTab("Accounts", symbol: "creditcard") {
                        AccountsContent(
                            onAdd: { isCreating = true },
                            onSelect: { editingAccount = $0 },
                            onManageTransactions: { managingAccount = $0 }
                        )
                        .frame(maxHeight: .infinity)
                    }
                    SectionTab("Trends", symbol: "chart.line.uptrend.xyaxis") {
                        VStack(alignment: .leading, spacing: 32) {
                            captionedChart("Net Worth") {
                                NetWorthChart(data: viewModel.monthlyMetrics)
                                    .frame(height: 160)
                            }
                            captionedChart("Savings Rate") {
                                MonthlySavingsRateBarChart(data: viewModel.monthlyMetrics)
                                    .frame(height: 80)
                            }
                        }
                    }
                }
                // Pin the card to the top so the shorter Trends tab doesn't float mid-page.
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(20)
        .sheet(isPresented: $isCreating) {
            AccountEditSheet(account: nil)
        }
        .sheet(item: $editingAccount) { account in
            AccountEditSheet(account: account)
        }
        .sheet(item: $managingAccount) { account in
            ManageTransactionsSheet(account: account)
        }
    }

    /// A small secondary caption above a full-width chart, labelling it within the Trends tab.
    private func captionedChart<ChartContent: View>(
        _ title: String,
        @ViewBuilder chart: () -> ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            chart()
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AccountsPage()
        .environment(AppViewModel(
            accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
        ))
        .frame(width: 720, height: 540)
}
