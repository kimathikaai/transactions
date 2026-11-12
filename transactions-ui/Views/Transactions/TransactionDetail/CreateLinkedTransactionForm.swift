import SwiftUI

/// Links section, "Create & link new": append the counterpart as a real CSV row
/// in another account (e.g. an investment account with no CSV export), give it a
/// type, and link it — one step. The amount is a positive magnitude; the type
/// sets the sign, so the two can't disagree.
struct CreateLinkedTransactionForm: View {
    @Environment(AppViewModel.self) private var viewModel

    let source: Transaction

    @State private var accountID: UUID?
    @State private var date: Date
    @State private var amountText: String
    @State private var type: TransactionType
    @State private var details = ""
    @State private var note = ""

    init(source: Transaction) {
        self.source = source
        _date = State(initialValue: Self.localDay(matching: source.date))
        _amountText = State(initialValue: String(format: "%.2f", abs(source.effectiveAmount)))
        _type = State(initialValue: source.effectiveType.mirrored)
    }

    private var sourceAccountName: String {
        viewModel.account(id: source.accountID)?.name ?? ""
    }

    private var accountChoices: [Account] {
        CreateLinkDefaults.accountChoices(for: source, in: viewModel.accounts)
    }

    private var account: Account? {
        accountID.flatMap { id in accountChoices.first { $0.id == id } }
    }

    private var magnitude: Double? {
        Double(amountText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private var canCreate: Bool {
        account != nil && magnitude != nil && !details.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create & link new")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("Account", selection: $accountID) {
                    Text("Choose account").tag(UUID?.none)
                    ForEach(accountChoices) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
                TextField("Amount", text: $amountText)
                    .frame(maxWidth: 100)
            }
            TextField("Details", text: $details)
            HStack(spacing: 8) {
                TextField("Link note (optional)", text: $note)
                Button(action: create) {
                    Label("Create & link", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(!canCreate)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.callout)
        .onAppear {
            if details.isEmpty {
                details = CreateLinkDefaults.details(for: type, sourceAccountName: sourceAccountName)
            }
        }
        .onChange(of: type) { oldType, newType in
            // Re-default only while the user hasn't typed their own details.
            let oldDefault = CreateLinkDefaults.details(for: oldType, sourceAccountName: sourceAccountName)
            if details == oldDefault {
                details = CreateLinkDefaults.details(for: newType, sourceAccountName: sourceAccountName)
            }
        }
    }

    private func create() {
        guard canCreate, let account, let magnitude else { return }
        let ok = viewModel.createLinkedTransaction(
            from: source, into: account, date: date, amount: magnitude,
            details: details, type: type, note: note
        )
        if ok {
            amountText = ""
            details = ""
            note = ""
        }
    }

    /// CSV dates are 00:00 UTC, but the DatePicker and `addManualTransaction`
    /// work in the current time zone. Rebuild the same calendar day locally so
    /// the default date writes the source's day, not the one before it.
    private static func localDay(matching utcDate: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: utcDate)
        return Calendar.current.date(from: parts) ?? utcDate
    }
}
