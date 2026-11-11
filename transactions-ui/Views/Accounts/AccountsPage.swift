import SwiftUI

struct AccountsPage: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var editingAccount: Account?
    @State private var updatingAccount: Account?
    @State private var isCreating = false

    /// Matches the Transactions and Reserves top rows (`ReservesPage.reservoirCardHeight`).
    private let netWorthCardHeight: CGFloat = 98

    /// Caption-sized so the Accounts title row stays the same height as Net Worth's.
    private var addAccountButton: some View {
        Button {
            isCreating = true
        } label: {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(.rect(cornerRadius: 4))
                .hoverHighlight(in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("New Account")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionContainer(title: "Net Worth") {
                NetWorthChart(data: viewModel.monthlyMetrics)
                    .frame(height: netWorthCardHeight)
            }

            SectionContainer(title: "Accounts") {
                addAccountButton
            } content: {
                AccountsContent(
                    onSelect: { editingAccount = $0 },
                    onUpdate: { updatingAccount = $0 }
                )
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .sheet(isPresented: $isCreating) {
            AccountEditSheet(account: nil)
        }
        .sheet(item: $editingAccount) { account in
            AccountEditSheet(account: account)
        }
        .sheet(item: $updatingAccount) { account in
            AccountUpdateSheet(account: account)
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
