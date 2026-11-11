import SwiftUI

/// Modal sheet for creating or editing an account. When `account` is nil,
/// the sheet is in create mode (no Delete button; "Upload first CSV" optional
/// affordance). When `account` is non-nil, the sheet is in edit mode and
/// exposes Save and Delete (with confirmation); existing accounts upload CSVs
/// from `AccountUpdateSheet` instead.
///
/// The first-CSV upload (file picker → diff preview → commit, via
/// `csvUploadFlow`) is presented from this sheet so the editor stays visible
/// while the user is mid-upload — canceling the file picker or the diff
/// returns to the editor with the form intact.
struct AccountEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    let account: Account?

    @State private var draft: AccountDraft

    @State private var showDeleteConfirm = false

    @State private var uploadTarget: Account?
    @State private var isImporting = false

    init(account: Account?) {
        self.account = account
        _draft = State(initialValue: account.map {
            AccountDraft(name: $0.name, type: $0.type, initialBalance: $0.initialBalance)
        } ?? AccountDraft())
    }

    private var isEdit: Bool { account != nil }

    private var accountTransactions: [Transaction] {
        guard let account else { return [] }
        return viewModel.allTransactions.filter { $0.accountID == account.id }
    }

    var body: some View {
        AccountFocusedEditView(
            draft: $draft,
            commit: { d in
                save(d)
                dismiss()
            },
            cancel: { dismiss() },
            uploadCSV: isEdit ? nil : { d in startUpload(with: d) },
            delete: isEdit ? { showDeleteConfirm = true } : nil,
            accountTransactions: accountTransactions
        )
        .padding(20)
        .presentationBackground(.clear)
        .csvUploadFlow(
            isPresented: $isImporting,
            account: uploadTarget,
            // The new account isn't saved until its first CSV commits, so
            // account + transactions land together.
            beforeCommit: { viewModel.createAccount($0) },
            onCommitted: { dismiss() }
        )
        .confirmationDialog(
            "Delete account \u{2018}\(account?.name ?? "")\u{2019}?",
            isPresented: $showDeleteConfirm,
            presenting: account
        ) { acct in
            Button("Delete", role: .destructive) {
                viewModel.deleteAccount(acct)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { acct in
            let n = viewModel.allTransactions.filter { $0.accountID == acct.id }.count
            Text("This will permanently remove the account and \(n) transaction\(n == 1 ? "" : "s").")
        }
    }

    // MARK: - Save

    private func save(_ d: AccountDraft) {
        if let account {
            viewModel.updateAccount(account, with: d)
        } else {
            let acct = Account(
                name: d.name,
                type: d.type,
                initialBalance: d.initialBalance,
                csvFileName: "\(UUID()).csv"
            )
            viewModel.createAccount(acct)
        }
    }

    // MARK: - CSV upload

    /// Create mode only: uploads into an orphan account that's saved on commit.
    private func startUpload(with d: AccountDraft) {
        uploadTarget = Account(
            name: d.name,
            type: d.type,
            initialBalance: d.initialBalance,
            csvFileName: "\(UUID()).csv"
        )
        isImporting = true
    }
}

#Preview("Edit") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    let account = Account(
        name: "Daily Chequing",
        type: .chequing,
        initialBalance: 1234.56,
        csvFileName: "chequing.csv"
    )
    return AccountEditSheet(account: account)
        .environment(AppViewModel(
            accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
        ))
        .frame(width: 520, height: 540)
}

#Preview("Create") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-\(UUID())", isDirectory: true)
    return AccountEditSheet(account: nil)
        .environment(AppViewModel(
            accountStore: AccountStore(fileURL: dir.appendingPathComponent("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.appendingPathComponent("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.appendingPathComponent("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.appendingPathComponent("edits.json"))
        ))
        .frame(width: 520, height: 540)
}
