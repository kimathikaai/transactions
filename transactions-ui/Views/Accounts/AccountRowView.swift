import SwiftUI

/// One account rendered as a table row. Left-click opens a dropdown menu,
/// right-click opens the same context menu — today both contain only "Edit".
/// Mirrors `ReserveCardView`'s click model. Column widths come from `AccountColumn`.
struct AccountRowView: View {
    let account: Account
    var onEdit: () -> Void
    var onManageTransactions: () -> Void

    @Environment(AppViewModel.self) private var viewModel

    private var accountTransactions: [Transaction] {
        viewModel.allTransactions.filter { $0.accountID == account.id }
    }

    private var balance: Double {
        netBalance(of: account, transactions: viewModel.allTransactions)
    }

    private var balanceColor: Color {
        balance < 0 ? .expense : .income
    }

    private var latestDateText: String {
        guard let latest = accountTransactions.map(\.date).max() else {
            return "—"
        }
        return Self.dateFormatter.string(from: latest)
    }

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        // Dates originate from BankCsvParser anchored at 00:00 UTC — render
        // in UTC so a 2026-06-29 CSV row displays as Jun 29 in any local TZ.
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var tint: Color { Color(hex: account.type.tint) }

    var body: some View {
        Menu {
            menuItems
        } label: {
            HStack(spacing: AccountColumn.spacing) {
                HStack(spacing: 6) {
                    Image(systemName: account.type.symbol)
                    Text(account.type.displayName)
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .accountColumn(.type)

                Text(account.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accountColumn(.name)

                Text(latestDateText)
                    .foregroundStyle(.secondary)
                    .accountColumn(.updated)

                Text(accountTransactions.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accountColumn(.count)

                Text(balance, format: .cad)
                    .foregroundStyle(balanceColor)
                    .monospacedDigit()
                    .accountColumn(.balance)
            }
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 25, maxHeight: 25, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, AccountColumn.horizontalPadding)
            .padding(.vertical, 2)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .hoverHighlight(in: .rect(cornerRadius: 6))
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Edit", systemImage: "pencil") { onEdit() }
        Button("Transactions", systemImage: "list.bullet") { onManageTransactions() }
    }
}

#Preview {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let sampleAccount = Account(
        name: "Chequing",
        type: .chequing,
        initialBalance: 142.07,
        csvFileName: "chequing.csv"
    )
    return AccountRowView(account: sampleAccount, onEdit: {}, onManageTransactions: {})
        .padding()
        .environment(AppViewModel(
            accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
        ))
}
