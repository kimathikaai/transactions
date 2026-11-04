import SwiftUI

/// The Accounts list rendered as a table: header row, divider, then a scrolling list
/// of `AccountRowView`s. Closure-driven — the parent page owns the edit/create sheet
/// state and the "add" button.
struct AccountsContent: View {
    @Environment(AppViewModel.self) private var viewModel

    var onSelect: (Account) -> Void
    var onManageTransactions: (Account) -> Void

    /// Group by account type (declaration order), then alphabetical by name.
    private var sortedAccounts: [Account] {
        viewModel.accounts.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type.sortRank < rhs.type.sortRank
            }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            AccountsHeaderRow()
            Divider()
            ScrollView {
                ForEach(sortedAccounts) { account in
                    AccountRowView(
                        account: account,
                        onEdit: { onSelect(account) },
                        onManageTransactions: { onManageTransactions(account) }
                    )
                }
            }
        }
    }
}

/// Column headers. Widths come from `AccountColumn` so they always match the rows.
private struct AccountsHeaderRow: View {
    var body: some View {
        HStack(spacing: AccountColumn.spacing) {
            header("Type").accountColumn(.type)
            header("Name").accountColumn(.name)
            header("Updated").accountColumn(.updated)
            header("Transactions").accountColumn(.count)
            header("Balance").accountColumn(.balance)
        }
        .padding(.horizontal, AccountColumn.horizontalPadding)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AccountsContent(onSelect: { _ in }, onManageTransactions: { _ in })
        .padding()
        .environment(AppViewModel(
            accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
        ))
}
