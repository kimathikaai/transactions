import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// The CSV upload flow: file picker → diff preview (`CSVUploadDiffView`) → commit.
    /// Setting `isPresented` opens the picker; `account` is read when the file comes
    /// back, so it may be built late (e.g. an unsaved account in create mode).
    ///
    /// - `beforeCommit` runs just before the CSV is written (create mode saves the
    ///   new account there, so account + transactions land together).
    /// - `onCommitted` runs after a successful commit.
    func csvUploadFlow(
        isPresented: Binding<Bool>,
        account: Account?,
        beforeCommit: @escaping (Account) -> Void = { _ in },
        onCommitted: @escaping () -> Void = {}
    ) -> some View {
        modifier(CSVUploadFlow(
            isImporting: isPresented,
            account: account,
            beforeCommit: beforeCommit,
            onCommitted: onCommitted
        ))
    }
}

private struct CSVUploadFlow: ViewModifier {
    @Environment(AppViewModel.self) private var viewModel

    @Binding var isImporting: Bool
    let account: Account?
    let beforeCommit: (Account) -> Void
    let onCommitted: () -> Void

    @State private var pendingUpload: PendingUpload?
    @State private var parseError: Error?
    @State private var commitError: Error?

    func body(content: Content) -> some View {
        content
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
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let target = account else { return }

        switch result {
        case .failure(let error):
            parseError = error
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
        beforeCommit(upload.account)
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
            onCommitted()
        } else {
            commitError = viewModel.lastSaveError
        }
    }

    private func dismissUpload() {
        commitError = nil
        pendingUpload = nil
    }
}
