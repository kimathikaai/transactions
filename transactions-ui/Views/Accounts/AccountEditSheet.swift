import SwiftUI
import UniformTypeIdentifiers

/// Modal sheet for creating or editing an account. When `account` is nil,
/// the sheet is in create mode (no Delete button; "Upload first CSV" optional
/// affordance). When `account` is non-nil, the sheet is in edit mode and
/// exposes Save, Delete (with confirmation), and Upload CSV inline.
///
/// CSV upload (file picker → diff preview → commit) is owned by this sheet so
/// the editor stays visible while the user is mid-upload — canceling the file
/// picker or the diff returns to the editor with the form intact.
struct AccountEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var viewModel

    let account: Account?

    @State private var draft: AccountDraft

    @State private var showDeleteConfirm = false

    @State private var uploadTarget: Account?
    @State private var isImporting = false
    @State private var pendingUpload: PendingUpload?
    @State private var parseError: Error?
    @State private var commitError: Error?
    /// True when the pending upload is for an account that hasn't been saved
    /// yet (the create-mode "Upload first CSV" path). On commit we create the
    /// account first so account + transactions land together.
    @State private var isNewAccountUpload = false

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
            uploadCSV: { d in startUpload(with: d) },
            uploadCSVLabel: isEdit ? "Upload CSV" : "Upload first CSV (optional)",
            delete: isEdit ? { showDeleteConfirm = true } : nil,
            accountTransactions: accountTransactions
        )
        .padding(20)
        .presentationBackground(.clear)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText, .text]
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $pendingUpload) { upload in
            CSVUploadDiffView(
                pending: upload,
                commitReplace: { commitUpload(upload, mode: .replace) },
                commitAppend: { commitUpload(upload, mode: .append) },
                cancel: dismissUpload,
                commitError: commitError
            )
        }
        .alert(
            "Couldn't read CSV",
            isPresented: Binding(
                get: { parseError != nil },
                set: { if !$0 { parseError = nil } }
            ),
            presenting: parseError
        ) { _ in
            Button("OK", role: .cancel) { parseError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
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

    private func startUpload(with d: AccountDraft) {
        if let account {
            isNewAccountUpload = false
            uploadTarget = account
        } else {
            // Create-mode orphan: not saved until commit.
            let orphan = Account(
                name: d.name,
                type: d.type,
                initialBalance: d.initialBalance,
                csvFileName: "\(UUID()).csv"
            )
            isNewAccountUpload = true
            uploadTarget = orphan
        }
        isImporting = true
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let target = uploadTarget else { return }
        defer { uploadTarget = nil }

        switch result {
        case .failure(let error):
            parseError = error
            isNewAccountUpload = false
        case .success(let url):
            do {
                let csv = try readCSV(at: url)
                let parsed = try BankCsvParser.parse(csvString: csv)
                let existingTransactions = viewModel.allTransactions.filter { $0.accountID == target.id }
                let incoming = ImportPipeline.makeTransactions(
                    from: parsed.map { $0.row },
                    accountID: target.id,
                    transferKeywords: GeneratedConfig.transferKeywords,
                    categories: viewModel.categories
                )
                let diff = DiffEngine.diff(existing: existingTransactions, incoming: incoming)

                // Zip parsed lines with the resulting transactions (index-aligned
                // by construction — ImportPipeline preserves order 1:1), then
                // keep only the raw lines whose transaction is in `diff.added`.
                let addedHashes = Set(diff.added.map { $0.contentHash })
                let addedRawLines: [String] = zip(parsed, incoming)
                    .filter { addedHashes.contains($0.1.contentHash) }
                    .map { $0.0.rawLine }

                pendingUpload = PendingUpload(
                    account: target,
                    diff: diff,
                    rawCsv: csv,
                    addedRawLines: addedRawLines,
                    existingIsEmpty: existingTransactions.isEmpty
                )
            } catch {
                parseError = error
                isNewAccountUpload = false
            }
        }
    }

    private func readCSV(at url: URL) throws -> String {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private enum UploadMode {
        case replace
        case append
    }

    private func commitUpload(_ upload: PendingUpload, mode: UploadMode) {
        if isNewAccountUpload {
            viewModel.createAccount(upload.account)
        }
        let ok: Bool
        switch mode {
        case .replace:
            ok = viewModel.commitImport(
                diff: upload.diff,
                into: upload.account,
                rawCsv: upload.rawCsv
            )
        case .append:
            ok = viewModel.commitAppend(
                addedRawLines: upload.addedRawLines,
                into: upload.account
            )
        }

        if ok {
            commitError = nil
            pendingUpload = nil
            isNewAccountUpload = false
            dismiss()
        } else {
            commitError = viewModel.lastSaveError
        }
    }

    private func dismissUpload() {
        commitError = nil
        pendingUpload = nil
        isNewAccountUpload = false
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
