import Foundation
import SwiftUI

// MARK: - Chart Data Types

struct MonthlyMetric: Identifiable, Sendable {
    let id = UUID()
    let month: Date

    let income: Double
    let expense: Double
    let net: Double
    let savingsRate: Double?

    let expenseByCategory: [CategoryID: Double]
    let incomeByCategory: [CategoryID: Double]

    let balances: [UUID: Double]
    var netWorth: Double { balances.values.reduce(0, +) }

    let savingsRateEMA6: Double?
    let savingsRateEMA6Unclamped: Double?
    let incomeMoMDelta: Double?
    let expenseMoMDelta: Double?
    let netMoMDelta: Double?
}

struct ReservoirSummary: Sendable {
    let balance: Double
    let reserved: Double
    let unreserved: Double

    static let zero = ReservoirSummary(balance: 0, reserved: 0, unreserved: 0)
}

struct SourceSummary: Identifiable, Sendable {
    var id: UUID { account.id }
    let account: Account
    let balance: Double
    let reserved: Double
    let unreserved: Double
}

/// Plain-value snapshot of a `Transaction` — precomputes the fields the
/// transactions list, filter, and histogram touch so the hot path doesn't
/// reach into the account map on every read.
struct TransactionSnapshot: Identifiable {
    let transaction: Transaction
    let id: String
    let date: Date
    let accountID: UUID?
    let accountName: String?
    let details: String
    let effectiveType: TransactionType
    let effectiveCategory: CategoryID?
    let effectiveSubcategory: SubcategoryID?
    let effectiveAmount: Double
    let notes: String?
    let isEdited: Bool
    let isReimbursed: Bool
    let isUsed: Bool
    /// Has at least one live link (auto or manual). Defaulted so fixtures and
    /// previews that predate links still build.
    var isLinked: Bool = false
    /// Has a live `transfer` link (auto or manual) — tints the row's link glyph.
    var hasTransferLink: Bool = false
}

extension TransactionSnapshot {
    /// Case-insensitive, whitespace-tokenized search across details, notes, and
    /// the plain amount string. Every term must hit at least one field; an empty
    /// query matches everything.
    func matches(searchText: String) -> Bool {
        let terms = searchText.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let amountString = String(format: "%.2f", abs(effectiveAmount))
        let fields = [details, notes ?? "", amountString]
        return terms.allSatisfy { term in
            fields.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }
}

/// Non-fatal issue surfaced on load (missing CSV, dropped dangling ref, etc.).
/// Rendered as a warning banner in the app; also visible in the debug panel.
struct LoadWarning: Identifiable {
    let id = UUID()
    let scope: String
    let message: String
}

// MARK: - ViewModel

@Observable
final class AppViewModel {

    // Stores — mutable so `switchProfile(to:)` can repoint them at another
    // profile's data folder and reload in place.
    private var accountStore: AccountStore
    private var reserveStore: ReserveStore
    private var reserveEventStore: ReserveEventStore
    private var editStore: EditStore
    private var categoryStore: CategoryStore
    private var reimbursementStore: ReimbursementStore
    private var linkStore: LinkStore
    private var csvDirectory: URL

    /// The data folder currently loaded. Set by the profile-aware initializer
    /// and `switchProfile(to:)`; defaults to `.real` for the injected
    /// (test/preview) initializer whose defaults point at the real folder.
    private(set) var activeProfile: DataProfile = .real

    // Loaded data
    private(set) var accounts: [Account] = []
    private(set) var reserves: [Reserve] = []
    private(set) var categories: [Category] = []
    private(set) var reservations: [Reservation] = []
    private(set) var reserveEvents: [ReserveEvent] = []
    /// Reimbursement links keyed by the reimbursed expense's contentHash.
    /// Materialized from `reimbursementStore` on load/mutation (mirroring how
    /// `reservations` is derived) so `@Observable` reactivity fires.
    private(set) var reimbursementLinks: [String: ReimbursementLink] = [:]
    /// Every link touching a transaction, keyed by its contentHash: manual links
    /// from `linkStore` plus the transfer auto-pairs, which are recomputed by
    /// `rebuildLinks()` and never persisted.
    private(set) var linksByHash: [String: [ResolvedLink]] = [:]
    private(set) var allTransactions: [Transaction] = []
    private(set) var transactionsByDateDesc: [TransactionSnapshot] = []
    private(set) var monthlyMetrics: [MonthlyMetric] = []
    private(set) var globalStartMonth: Date?
    private(set) var globalEndMonth: Date?
    private(set) var dataVersion: Int = 0
    private(set) var loadWarnings: [LoadWarning] = []
    private(set) var categoryValidation: CategoryValidationResult = .empty

    var lastSaveError: Error?

    // Chart axis sync state
    var scrollMonth: Date?
    var visibleWindowMonths: Int = 18
    var hoveredMonth: Date?
    var pinnedMonth: Date?

    var activeMonth: Date? { pinnedMonth ?? hoveredMonth }
    var displayedMonth: Date? { activeMonth ?? monthlyMetrics.last?.month }

    init(
        accountStore: AccountStore = AccountStore(fileURL: DataPaths.accountsFile),
        reserveStore: ReserveStore = ReserveStore(fileURL: DataPaths.reservesFile),
        reserveEventStore: ReserveEventStore = ReserveEventStore(fileURL: DataPaths.reserveEventsFile),
        editStore: EditStore = EditStore(fileURL: DataPaths.editsFile),
        categoryStore: CategoryStore = CategoryStore(fileURL: DataPaths.categoriesFile),
        reimbursementStore: ReimbursementStore = ReimbursementStore(fileURL: DataPaths.reimbursementsFile),
        linkStore: LinkStore = LinkStore(fileURL: DataPaths.linksFile),
        csvDirectory: URL = DataPaths.csvDirectory(for: .real)
    ) {
        self.accountStore = accountStore
        self.reserveStore = reserveStore
        self.reserveEventStore = reserveEventStore
        self.editStore = editStore
        self.categoryStore = categoryStore
        self.reimbursementStore = reimbursementStore
        self.linkStore = linkStore
        self.csvDirectory = csvDirectory
        loadEverything()
    }

    /// Profile-aware initializer used by the app root. Builds every store from
    /// the given profile's data folder.
    convenience init(profile: DataProfile) {
        self.init(
            accountStore: AccountStore(fileURL: DataPaths.accountsFile(for: profile)),
            reserveStore: ReserveStore(fileURL: DataPaths.reservesFile(for: profile)),
            reserveEventStore: ReserveEventStore(fileURL: DataPaths.reserveEventsFile(for: profile)),
            editStore: EditStore(fileURL: DataPaths.editsFile(for: profile)),
            categoryStore: CategoryStore(fileURL: DataPaths.categoriesFile(for: profile)),
            reimbursementStore: ReimbursementStore(fileURL: DataPaths.reimbursementsFile(for: profile)),
            linkStore: LinkStore(fileURL: DataPaths.linksFile(for: profile)),
            csvDirectory: DataPaths.csvDirectory(for: profile)
        )
        self.activeProfile = profile
    }

    // MARK: - Profile switching

    /// Repoint every store at another profile's data folder and reload in
    /// place. No-op if already on `profile`. Persists the choice across
    /// launches. Because `AppViewModel` is `@Observable` and held by the
    /// environment, the whole UI refreshes without a relaunch.
    func switchProfile(to profile: DataProfile) {
        guard profile != activeProfile else { return }
        accountStore = AccountStore(fileURL: DataPaths.accountsFile(for: profile))
        reserveStore = ReserveStore(fileURL: DataPaths.reservesFile(for: profile))
        reserveEventStore = ReserveEventStore(fileURL: DataPaths.reserveEventsFile(for: profile))
        editStore = EditStore(fileURL: DataPaths.editsFile(for: profile))
        categoryStore = CategoryStore(fileURL: DataPaths.categoriesFile(for: profile))
        reimbursementStore = ReimbursementStore(fileURL: DataPaths.reimbursementsFile(for: profile))
        linkStore = LinkStore(fileURL: DataPaths.linksFile(for: profile))
        csvDirectory = DataPaths.csvDirectory(for: profile)
        activeProfile = profile
        DataProfile.persist(profile)
        loadEverything()
    }

    /// Absolute path of the currently-loaded profile's data folder — surfaced
    /// in the debug panel.
    var activeDataDirectoryPath: String {
        DataPaths.dataDirectory(for: activeProfile).path
    }

    // MARK: - Load

    /// Startup + full reload. Reads all four JSON files, validates reservation
    /// refs, parses every CSV, stitches edits onto transactions, and rebuilds
    /// derived aggregates.
    private func loadEverything() {
        let start = Date()
        loadWarnings.removeAll()

        do {
            try accountStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "accounts", message: "\(error)"))
        }
        do {
            try reserveStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "reserves", message: "\(error)"))
        }
        do {
            try reserveEventStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "reserveEvents", message: "\(error)"))
        }
        do {
            try editStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "edits", message: "\(error)"))
        }
        do {
            try categoryStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "categories", message: "\(error)"))
        }
        do {
            try reimbursementStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "reimbursements", message: "\(error)"))
        }
        do {
            try linkStore.load()
        } catch {
            loadWarnings.append(LoadWarning(scope: "links", message: "\(error)"))
        }

        accounts = accountStore.accounts
        reserves = reserveStore.reserves
        categories = categoryStore.categories
        reimbursementLinks = reimbursementStore.links

        let accountIDs = Set(accounts.map(\.id))
        let reserveIDs = Set(reserves.map(\.id))
        reserveEvents = reserveEventStore.events
        let (kept, dropped) = ReservationStore.validate(
            reservations: foldEvents(reserveEventStore.events),
            againstAccounts: accountIDs,
            reserves: reserveIDs
        )
        reservations = kept
        for a in dropped {
            loadWarnings.append(LoadWarning(
                scope: "reserveEvents",
                message: "Dropped dangling reservation \(a.id) (reserve=\(a.reserveID), account=\(a.accountID))"
            ))
        }

        parseAllTransactions()

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("[AppViewModel] loadEverything: \(ms) ms")

        rebuildLinks()
        rebuildTransactionSnapshots()
        monthlyMetrics = computeMonthlyMetrics()
        dataVersion &+= 1
        revalidateCategories()
    }

    private func parseAllTransactions() {
        let results = TransactionLoader.loadAll(
            accounts: accounts,
            csvDirectory: csvDirectory,
            transferKeywords: GeneratedConfig.transferKeywords,
            categories: categories
        )
        var merged: [Transaction] = []
        for r in results {
            if let err = r.error {
                if let acct = accounts.first(where: { $0.id == r.accountID }) {
                    loadWarnings.append(LoadWarning(
                        scope: "csv:\(acct.name)",
                        message: "\(err)"
                    ))
                }
            }
            merged.append(contentsOf: r.transactions)
        }
        // Sort ascending by date so downstream code keeps the old invariant.
        merged.sort { $0.date < $1.date }
        TransactionLoader.applyEdits(editStore.edits, to: &merged)
        allTransactions = merged
    }

    /// Reload transactions for exactly one account (used after commitImport).
    private func reparseTransactions(for account: Account) {
        // Drop this account's existing rows and re-add fresh ones.
        allTransactions.removeAll { $0.accountID == account.id }
        let result = TransactionLoader.loadOne(
            account: account,
            csvDirectory: csvDirectory,
            transferKeywords: GeneratedConfig.transferKeywords,
            categories: categories
        )
        if let err = result.error {
            loadWarnings.append(LoadWarning(scope: "csv:\(account.name)", message: "\(err)"))
        }
        var newRows = result.transactions
        TransactionLoader.applyEdits(editStore.edits, to: &newRows)
        allTransactions.append(contentsOf: newRows)
        allTransactions.sort { $0.date < $1.date }
    }

    private func rebuildTransactionSnapshots() {
        let txs = allTransactions
        var snapshots: [TransactionSnapshot] = []
        snapshots.reserveCapacity(txs.count)
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let reimbursed = reimbursedExpenseHashes          // capture once; property rebuilds a Set per access
        let used = usedTransactionIDs                     // capture once; property rebuilds a Set per access
        let links = linksByHash
        for tx in txs.reversed() {
            let acct = accountByID[tx.accountID]
            snapshots.append(TransactionSnapshot(
                transaction: tx,
                id: tx.contentHash,
                date: tx.date,
                accountID: tx.accountID,
                accountName: acct?.name,
                details: tx.details,
                effectiveType: tx.effectiveType,
                effectiveCategory: tx.effectiveCategory,
                effectiveSubcategory: tx.effectiveSubcategory,
                effectiveAmount: tx.effectiveAmount,
                notes: tx.effectiveNotes,
                isEdited: tx.edit != nil,
                isReimbursed: reimbursed.contains(tx.contentHash),
                isUsed: used.contains(tx.contentHash),
                isLinked: links[tx.contentHash]?.contains(where: \.isLive) ?? false,
                hasTransferLink: links[tx.contentHash]?.contains { $0.isLive && $0.kind == .transfer } ?? false
            ))
        }
        transactionsByDateDesc = snapshots

        let calendar = Calendar.current
        globalStartMonth = txs.first.map { calendar.dateInterval(of: .month, for: $0.date)!.start }
        globalEndMonth = txs.last.map { calendar.dateInterval(of: .month, for: $0.date)!.start }
    }

    /// Recompute derived state after any store mutation. Skips CSV re-parse —
    /// callers who mutated a CSV file must call `reparseTransactions(for:)`
    /// themselves before invoking this.
    private func refreshDerivedState() {
        accounts = accountStore.accounts
        reserves = reserveStore.reserves
        reserveEvents = reserveEventStore.events
        let (kept, _) = ReservationStore.validate(
            reservations: foldEvents(reserveEventStore.events),
            againstAccounts: Set(accounts.map(\.id)),
            reserves: Set(reserves.map(\.id))
        )
        reservations = kept
        reimbursementLinks = reimbursementStore.links
        rebuildLinks()
        rebuildTransactionSnapshots()
        monthlyMetrics = computeMonthlyMetrics()
        dataVersion &+= 1
        revalidateCategories()
    }

    private func revalidateCategories() {
        categoryValidation = CategoryValidator.validate(
            categories: categories,
            edits: editStore.edits,
            transactions: allTransactions
        )
    }

    // MARK: - Lookups

    func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: - Category accessors

    func category(id: CategoryID) -> Category? {
        categories.first { $0.id == id.rawValue }
    }

    func subcategory(id: SubcategoryID) -> Category? {
        categories.first { $0.id == id.rawValue }
    }

    /// Returns the leaf's parent root — used for inherited display metadata
    /// (color/symbol) inherited from the root category record.
    func root(forSubcategory id: SubcategoryID) -> Category? {
        guard let leaf = subcategory(id: id), let parentID = leaf.parent else { return nil }
        return categories.first { $0.id == parentID }
    }

    func rootCategories(ofType type: TransactionType? = nil) -> [Category] {
        categories.filter { $0.parent == nil && (type == nil || $0.transactionType == type) }
    }

    func leafCategories(under parentID: String) -> [Category] {
        categories.filter { $0.parent == parentID }
    }

    /// Read-only accessor exposing the edit store's keyed edits to views.
    var editStoreEdits: [String: TransactionEdit] { editStore.edits }

    var reservoirSources: [Account] {
        accounts
            .filter(\.isReservoirSource)
            .sorted { ($0.type.sortRank, $0.name) < ($1.type.sortRank, $1.name) }
    }

    var reservoirSummary: ReservoirSummary {
        let sources = reservoirSources
        let balance = sources.reduce(0) { $0 + netBalance(of: $1, transactions: allTransactions) }
        let reservedTotal = sources.reduce(0) { $0 + allotted(for: $1.id, reservations: reservations) }
        return ReservoirSummary(balance: balance, reserved: reservedTotal, unreserved: balance - reservedTotal)
    }

    var perSourceSummary: [SourceSummary] {
        reservoirSources.map { acct in
            let bal = netBalance(of: acct, transactions: allTransactions)
            let reservedAmt = allotted(for: acct.id, reservations: reservations)
            return SourceSummary(
                account: acct,
                balance: bal,
                reserved: reservedAmt,
                unreserved: bal - reservedAmt
            )
        }
    }

    /// One display row per ledger event, resolved to reserve/source names and
    /// ordered newest-first, for the Reserves-page Activity table. Use rows
    /// additionally resolve their linked expense transaction (details + date) for
    /// the Activity table's transaction column; unresolvable links leave both nil.
    struct ReserveActivityRow: Identifiable {
        let id: UUID
        let date: Date
        let reserveID: UUID
        let reserveEmoji: String
        let reserveName: String
        let sourceName: String
        let type: ReserveEventType
        let amount: Double
        let note: String?
        let transactionContentHash: String?
        let linkedDetails: String?
        let linkedDate: Date?

        /// What the Activity table's information column shows: the linked
        /// transaction when it resolves, "(unlinked)" when its hash dangles
        /// (even if there's a note), otherwise the note.
        var info: ReserveActivityInfo {
            guard transactionContentHash != nil else { return .note(note) }
            return linkedDetails.map { .linked(details: $0) } ?? .dangling
        }
    }

    enum ReserveActivityInfo: Equatable {
        case linked(details: String)
        case dangling
        case note(String?)
    }

    var reserveActivity: [ReserveActivityRow] {
        let reserveByID = Dictionary(uniqueKeysWithValues: reserves.map { ($0.id, $0) })
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let txByHash = Dictionary(allTransactions.map { ($0.contentHash, $0) },
                                  uniquingKeysWith: { first, _ in first })
        return reserveEvents
            .sorted { $0.date > $1.date }
            .map { event in
                let reserve = reserveByID[event.reserveID]
                let account = accountByID[event.accountID]
                let linkedTx = event.transactionContentHash.flatMap { txByHash[$0] }
                return ReserveActivityRow(
                    id: event.id,
                    date: event.date,
                    reserveID: event.reserveID,
                    reserveEmoji: reserve?.emoji ?? "",
                    reserveName: reserve?.name ?? "—",
                    sourceName: account?.name ?? "—",
                    type: event.type,
                    amount: event.amount,
                    note: event.note,
                    transactionContentHash: event.transactionContentHash,
                    linkedDetails: linkedTx?.details,
                    linkedDate: linkedTx?.date
                )
            }
    }

    /// Expense transactions newest-first, the candidate pool for using a
    /// reserve. Filtered from the already-sorted snapshot array.
    var expenseTransactions: [TransactionSnapshot] {
        transactionsByDateDesc.filter { $0.effectiveType == .expense }
    }

    /// Income transactions newest-first — the candidate pool for reimbursing an
    /// expense (US4 Modal 1). Filtered from the already-sorted snapshot array.
    var incomeTransactions: [TransactionSnapshot] {
        transactionsByDateDesc.filter { $0.effectiveType == .income }
    }

    /// contentHashes already linked to a use event; the use sheet uses
    /// this to block linking the same expense twice. Inlined (rather than calling
    /// the same-named free function) to avoid the property shadowing the global.
    var usedTransactionIDs: Set<String> {
        Set(reserveEvents.lazy.filter { $0.type == .use }.compactMap(\.transactionContentHash))
    }

    /// A dangling reserve link: a ledger event (any type) whose
    /// `transactionContentHash` no longer resolves to a loaded transaction (the
    /// CSV row changed, or the transaction/account was removed). Surfaced as a
    /// debug-panel health check; renders as "(unlinked)" in the Activity table.
    struct DanglingReserveLink: Identifiable {
        let id: UUID          // the event id
        let reserveName: String
        let type: ReserveEventType
        let contentHash: String
    }

    var danglingReserveLinks: [DanglingReserveLink] {
        let live = Set(allTransactions.map(\.contentHash))
        let reserveByID = Dictionary(uniqueKeysWithValues: reserves.map { ($0.id, $0) })
        return reserveEvents.compactMap { event in
            guard let hash = event.transactionContentHash,
                  !live.contains(hash) else { return nil }
            return DanglingReserveLink(
                id: event.id,
                reserveName: reserveByID[event.reserveID]?.name ?? "—",
                type: event.type,
                contentHash: hash
            )
        }
    }

    // MARK: - Reimbursements (derived)

    /// Expense contentHashes that already have a reimbursement link. Drives the
    /// US9 badge and the US3 "one reimbursement per expense" guard.
    var reimbursedExpenseHashes: Set<String> {
        Set(reimbursementLinks.keys)
    }

    /// The reimbursement link for a given expense, if any (backs Modal 2).
    func reimbursementLink(forExpense expenseHash: String) -> ReimbursementLink? {
        reimbursementLinks[expenseHash]
    }

    /// Total already claimed against a reimbursement income — the sum of every
    /// link drawing from it. Drives the income's Remaining pool (US6/US7).
    func claimed(forReimbursement incomeHash: String) -> Double {
        reimbursementLinks.values
            .filter { $0.reimbursementHash == incomeHash }
            .reduce(0) { $0 + $1.amount }
    }

    /// Remaining (unclaimed) pool for a reimbursement income = its full amount
    /// (`capacity`) − already-claimed. Never manufactured below zero.
    func remaining(forReimbursement incomeHash: String, capacity: Double) -> Double {
        max(0, capacity - claimed(forReimbursement: incomeHash))
    }

    /// One display row per reimbursement link, resolved to expense/source
    /// transaction details and ordered newest-first (by `linkedAt`), for the
    /// US10 review table. Unresolvable hashes leave the corresponding `…Details`
    /// nil (the table renders that side as "(… no longer available)"); the
    /// snapshot amount and linked-at date are stored on the link, so a dangling
    /// row still renders and stays unlinkable.
    struct ReimbursementReviewRow: Identifiable {
        /// The reimbursed expense's contentHash — unique per link (US3).
        let id: String
        let linkedAt: Date
        let expenseDetails: String?
        let expenseAccountName: String?
        let sourceDetails: String?
        let sourceDate: Date?
        let amount: Double
    }

    var reimbursementReview: [ReimbursementReviewRow] {
        let txByHash = Dictionary(allTransactions.map { ($0.contentHash, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return reimbursementLinks
            .map { expenseHash, link in
                let expenseTx = txByHash[expenseHash]
                let sourceTx = txByHash[link.reimbursementHash]
                return ReimbursementReviewRow(
                    id: expenseHash,
                    linkedAt: link.linkedAt,
                    expenseDetails: expenseTx?.details,
                    expenseAccountName: expenseTx.flatMap { accountByID[$0.accountID]?.name },
                    sourceDetails: sourceTx?.details,
                    sourceDate: sourceTx?.date,
                    amount: link.amount
                )
            }
            .sorted { $0.linkedAt > $1.linkedAt }
    }

    /// A dangling reimbursement link: its expense or reimbursement hash no
    /// longer resolves to a loaded transaction (CSV row changed, or the
    /// transaction/account was removed). Surfaced as a debug-panel health check;
    /// renders inline in the review table as "(… no longer available)".
    struct DanglingReimbursementLink: Identifiable {
        /// The reimbursed expense's contentHash (the link key).
        let id: String
        let expenseHash: String
        let reimbursementHash: String
        let expenseMissing: Bool
        let sourceMissing: Bool
    }

    var danglingReimbursementLinks: [DanglingReimbursementLink] {
        let live = Set(allTransactions.map(\.contentHash))
        return reimbursementLinks.compactMap { expenseHash, link in
            let expenseMissing = !live.contains(expenseHash)
            let sourceMissing = !live.contains(link.reimbursementHash)
            guard expenseMissing || sourceMissing else { return nil }
            return DanglingReimbursementLink(
                id: expenseHash,
                expenseHash: expenseHash,
                reimbursementHash: link.reimbursementHash,
                expenseMissing: expenseMissing,
                sourceMissing: sourceMissing
            )
        }
    }

    /// `monthlyMetrics` with reimbursement amounts netted out of the flow —
    /// income shows only what remains after reimbursements, expense shows only
    /// the unreimbursed portion (see `netReimbursements`). A cheap transform over
    /// the already-computed metrics, so it stays a computed property off the
    /// load/mutation recompute path. Backs the "Flow (net reimbursements)" card.
    var monthlyMetricsNetReimbursed: [MonthlyMetric] {
        netReimbursements(
            from: monthlyMetrics,
            transactions: allTransactions,
            links: reimbursementLinks
        )
    }

    // MARK: - Mutations

    @discardableResult
    func createAccount(_ account: Account) -> Bool {
        do {
            try accountStore.upsert(account)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func updateAccount(_ account: Account, with draft: AccountDraft) -> Bool {
        var updated = account
        updated.name = draft.name
        updated.type = draft.type
        updated.initialBalance = draft.initialBalance
        // csvFileName is edited elsewhere (or left untouched by AccountDraft;
        // see AccountDraft definition for which fields it exposes).
        do {
            try accountStore.upsert(updated)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func deleteAccount(_ account: Account) -> Bool {
        do {
            try reserveEventStore.removeAll(accountID: account.id)
            try accountStore.delete(id: account.id)
            // Drop this account's transactions from memory; edits stay in the
            // store (their content hashes are dead but harmless).
            allTransactions.removeAll { $0.accountID == account.id }
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Write a transaction's edit record, kept minimal: a type equal to the parsed
    /// one isn't an override, a category equal to the rules' pick is stored as nil
    /// (so it keeps following the rules), and a record left with nothing in it is
    /// removed rather than written.
    @discardableResult
    func saveEdit(
        for transaction: Transaction,
        category: CategoryID?,
        subcategory: SubcategoryID?,
        notes: String?,
        transactionType: TransactionType? = nil
    ) -> Bool {
        let typeOverride = transactionType == transaction.transactionType ? nil : transactionType
        // Enforce the transfer type↔category coupling centrally so no write path
        // (edit modal, bulk edits) can persist a mismatch.
        let effectiveType = typeOverride ?? transaction.transactionType
        var coerced = CategoryLookup.coerceCategory(
            for: effectiveType,
            category: category,
            subcategory: subcategory,
            in: categories
        )
        if typeOverride == nil,
           coerced.category == transaction.category,
           coerced.subcategory == transaction.subcategory {
            coerced = (nil, nil)
        }
        if coerced.category == nil, coerced.subcategory == nil, typeOverride == nil,
           notes?.isEmpty ?? true {
            return clearEdit(for: transaction)
        }
        let edit = TransactionEdit(
            category: coerced.category,
            subcategory: coerced.subcategory,
            notes: notes,
            transactionType: typeOverride,
            updatedAt: .now
        )
        do {
            try editStore.upsert(contentHash: transaction.contentHash, record: edit)
            if let idx = allTransactions.firstIndex(where: { $0.contentHash == transaction.contentHash }) {
                allTransactions[idx].edit = edit
            }
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func clearEdit(for transaction: Transaction) -> Bool {
        do {
            try editStore.delete(contentHash: transaction.contentHash)
            if let idx = allTransactions.firstIndex(where: { $0.contentHash == transaction.contentHash }) {
                allTransactions[idx].edit = nil
            }
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    // MARK: - Edit intents (the transaction modal's live writes)
    //
    // Each re-reads the live transaction first: several modal writes can land in
    // one update pass (a notes flush on focus loss plus a category pick), and a
    // caller's stale copy would overwrite the field the other write just saved.

    /// Set type + category, keeping the transaction's notes. A type-locked
    /// transaction (see `isTypeLocked`) keeps its current type whatever is passed.
    @discardableResult
    func updateClassification(
        for transaction: Transaction,
        type: TransactionType,
        category: CategoryID?,
        subcategory: SubcategoryID?
    ) -> Bool {
        let live = self.transaction(withHash: transaction.contentHash) ?? transaction
        let type = isTypeLocked(live) ? live.effectiveType : type
        return saveEdit(for: live, category: category, subcategory: subcategory,
                        notes: live.effectiveNotes, transactionType: type)
    }

    /// Set notes, keeping the edit's raw classification — passing the raw (not
    /// effective) values means a notes-only edit never pins the rules' category.
    @discardableResult
    func updateNotes(for transaction: Transaction, notes: String?) -> Bool {
        let live = self.transaction(withHash: transaction.contentHash) ?? transaction
        return saveEdit(for: live, category: live.edit?.category,
                        subcategory: live.edit?.subcategory, notes: notes,
                        transactionType: live.edit?.transactionType)
    }

    /// Drop the type and category overrides so the rules decide again; notes stay.
    /// A type-locked transaction keeps its type override — only the category reverts.
    @discardableResult
    func revertClassification(for transaction: Transaction) -> Bool {
        let live = self.transaction(withHash: transaction.contentHash) ?? transaction
        let keptType = isTypeLocked(live) ? live.edit?.transactionType : nil
        return saveEdit(for: live, category: nil, subcategory: nil,
                        notes: live.effectiveNotes, transactionType: keptType)
    }

    /// Overwrite the account's CSV file with `rawCsv` and re-parse just that
    /// account. `diff` is preserved in the signature for backward-compat with
    /// the upload view; the value is unused post-migration (the file *is*
    /// the source of truth).
    @discardableResult
    func commitImport(diff: CSVDiff, into account: Account, rawCsv: String) -> Bool {
        let csvURL = csvDirectory.appendingPathComponent(account.csvFileName)
        do {
            try FileManager.default.createDirectory(
                at: csvURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(rawCsv.utf8).write(to: csvURL, options: .atomic)
            reparseTransactions(for: account)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Append-mode CSV import. Preserves existing on-disk rows byte-for-byte
    /// (so their contentHashes and stitched edits stay attached) and appends
    /// only the supplied raw lines to the end of the file.
    ///
    /// File contents post-append: `<existing bytes, trailing-whitespace stripped>`
    /// + `\n` + `addedRawLines.joined(separator: "\n")` + `\n`. If the existing
    /// file was missing or empty, the leading `\n` is omitted so the file
    /// doesn't start with a blank line.
    @discardableResult
    func commitAppend(
        addedRawLines: [String],
        into account: Account
    ) -> Bool {
        let csvURL = csvDirectory.appendingPathComponent(account.csvFileName)
        do {
            try FileManager.default.createDirectory(
                at: csvURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let existing: String
            if FileManager.default.fileExists(atPath: csvURL.path) {
                existing = try String(contentsOf: csvURL, encoding: .utf8)
            } else {
                existing = ""
            }

            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            let appended = addedRawLines.joined(separator: "\n")

            let newContents: String
            if trimmed.isEmpty {
                newContents = appended.isEmpty ? "" : appended + "\n"
            } else if appended.isEmpty {
                newContents = trimmed + "\n"
            } else {
                newContents = trimmed + "\n" + appended + "\n"
            }

            try Data(newContents.utf8).write(to: csvURL, options: .atomic)
            reparseTransactions(for: account)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Formats a picked date as the `yyyy-MM-dd` day string the user sees.
    /// Uses the current time zone (not UTC) so the calendar day chosen in the
    /// DatePicker is the day written; `BankCsvParser` re-anchors it at 00:00 UTC
    /// on reparse, matching how bank CSV dates are stored and displayed.
    private static let manualDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        return fmt
    }()

    /// Manually append one transaction to the account's CSV, then reparse.
    /// `signedAmount` follows the app convention: negative = expense (debit),
    /// positive = income (credit). Details are CSV-quoted and any embedded
    /// double-quote is stripped (the parser has no quote-escape). Returns false
    /// if the amount is zero or the details are blank (both rejected by the
    /// parser anyway).
    @discardableResult
    func addManualTransaction(
        date: Date,
        signedAmount: Double,
        details: String,
        into account: Account
    ) -> Bool {
        appendManualTransaction(date: date, signedAmount: signedAmount, details: details, into: account) != nil
    }

    /// `addManualTransaction`, returning the new row's contentHash (nil on any
    /// failure) so Create & link can find the row it just wrote.
    func appendManualTransaction(
        date: Date,
        signedAmount: Double,
        details: String,
        into account: Account
    ) -> String? {
        let sanitized = details.replacingOccurrences(of: "\"", with: "")
        guard signedAmount != 0,
              !sanitized.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let debit = signedAmount < 0 ? -signedAmount : 0
        let credit = signedAmount > 0 ? signedAmount : 0
        let dateString = Self.manualDateFormatter.string(from: date)
        let debitField = debit == 0 ? "" : String(format: "%.2f", debit)
        let creditField = credit == 0 ? "" : String(format: "%.2f", credit)
        let rawLine = "\(dateString),\"\(sanitized)\",\(debitField),\(creditField)"
        guard commitAppend(addedRawLines: [rawLine], into: account) else { return nil }
        return lastRowHash(in: account)
    }

    /// The contentHash of the account CSV's last row, rebuilt index-aligned with
    /// the file (as `deleteTransaction` does) so the occurrence index matches.
    private func lastRowHash(in account: Account) -> String? {
        let csvURL = csvDirectory.appendingPathComponent(account.csvFileName)
        do {
            let csvString = try String(contentsOf: csvURL, encoding: .utf8)
            let parsed = try BankCsvParser.parse(csvString: csvString)
            let rebuilt = ImportPipeline.makeTransactions(
                from: parsed.map(\.row),
                accountID: account.id,
                transferKeywords: GeneratedConfig.transferKeywords,
                categories: categories
            )
            return rebuilt.last?.contentHash
        } catch {
            lastSaveError = error
            return nil
        }
    }

    /// Create & link: append the counterpart row to `account`, give it `type`
    /// (a minimal type edit when the parsed type differs, e.g. a transfer whose
    /// details carry no transfer keyword), then link it to `source` with the
    /// kind inferred. `magnitude` is positive; the type sets the sign. A failed
    /// step returns false with `lastSaveError` set; the CSV row isn't rolled back.
    @discardableResult
    func createLinkedTransaction(
        from source: Transaction,
        into account: Account,
        date: Date,
        amount magnitude: Double,
        details: String,
        type: TransactionType,
        note: String?
    ) -> Bool {
        let signedAmount = (type == .income || type == .transfer_in) ? abs(magnitude) : -abs(magnitude)
        guard let hash = appendManualTransaction(date: date, signedAmount: signedAmount,
                                                 details: details, into: account),
              let created = transaction(withHash: hash)
        else { return false }
        if created.transactionType != type {
            guard saveEdit(for: created, category: nil, subcategory: nil, notes: nil, transactionType: type)
            else { return false }
        }
        guard let retyped = transaction(withHash: hash) else { return false }
        return linkTransactions(source, retyped, note: note)
    }

    /// Delete one transaction by rewriting the account's CSV without its source
    /// line, then reparse. Works on any row (manual or bank-imported). Also
    /// clears any orphaned edit keyed on the deleted row's hash. Returns false
    /// if the CSV can't be read or the row's source line can't be located.
    @discardableResult
    func deleteTransaction(_ transaction: Transaction, from account: Account) -> Bool {
        let csvURL = csvDirectory.appendingPathComponent(account.csvFileName)
        do {
            let csvString = try String(contentsOf: csvURL, encoding: .utf8)
            let parsed = try BankCsvParser.parse(csvString: csvString)
            // Rebuild transactions index-aligned with `parsed` so contentHash
            // (which depends on per-row occurrence index) matches exactly.
            let rebuilt = ImportPipeline.makeTransactions(
                from: parsed.map(\.row),
                accountID: account.id,
                transferKeywords: GeneratedConfig.transferKeywords,
                categories: categories
            )
            guard let idx = rebuilt.firstIndex(where: { $0.contentHash == transaction.contentHash }) else {
                return false
            }
            var remaining = parsed
            remaining.remove(at: idx)
            let joined = remaining.map(\.rawLine).joined(separator: "\n")
            let rawCsv = joined.isEmpty ? "" : joined + "\n"
            let ok = commitImport(diff: CSVDiff(added: [], removed: []), into: account, rawCsv: rawCsv)
            if ok {
                // Before clearEdit, so its refresh rebuilds the link index.
                try linkStore.removeAll(mentioning: transaction.contentHash)
                clearEdit(for: transaction)
            }
            return ok
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func upsertReserve(_ reserve: Reserve) -> Bool {
        do {
            try reserveStore.upsert(reserve)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func deleteReserve(id: UUID) -> Bool {
        do {
            let service = ReserveService(eventStore: reserveEventStore)
            try service.deleteReserve(id: id, from: reserveStore)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    func claim(amount: Double, from account: Account, to reserve: Reserve, note: String? = nil,
               transactionContentHash: String? = nil) throws {
        let service = ReserveService(eventStore: reserveEventStore)
        let freeAvail = free(of: account, transactions: allTransactions, reservations: reservations)
        try service.claim(amount: amount, from: account, freeAvailable: freeAvail, to: reserve, note: note,
                          transactionContentHash: transactionContentHash)
        refreshDerivedState()
    }

    func release(amount releaseAmount: Double, from reserve: Reserve, to account: Account, note: String? = nil,
                 transactionContentHash: String? = nil) throws {
        let service = ReserveService(eventStore: reserveEventStore)
        let avail = amount(reserveID: reserve.id, accountID: account.id, in: reservations)
        try service.release(amount: releaseAmount, from: reserve, to: account,
                            availableForAccountInReserve: avail, note: note,
                            transactionContentHash: transactionContentHash)
        refreshDerivedState()
    }

    /// Record that a linked expense transaction spent money held in the reserve.
    /// Draws down the same per-(reserve,account) headroom as `release`, tagging
    /// the event `.use` and linking the transaction. Throws `ReserveError`
    /// (surfaced inline by the use sheet) on invalid amount, already-linked
    /// transaction, or over-headroom.
    func use(amount useAmount: Double, from source: Account, on reserve: Reserve,
             transactionContentHash: String, note: String? = nil) throws {
        let service = ReserveService(eventStore: reserveEventStore)
        let avail = amount(reserveID: reserve.id, accountID: source.id, in: reservations)
        let linked = usedTransactionIDs.contains(transactionContentHash)
        try service.use(
            amount: useAmount, from: source, on: reserve,
            availableForAccountInReserve: avail,
            transactionContentHash: transactionContentHash,
            alreadyLinked: linked, note: note
        )
        refreshDerivedState()
    }

    /// Hard-remove a single ledger event — backs the activity detail sheet's
    /// Delete and the transaction modal's use Unlink. Only `.use` events may be deleted: removing an allocation or
    /// release would corrupt the folded balance (a later offsetting event would
    /// still subtract against nothing). Non-`.use` deletions are rejected
    /// (returns `false`, no mutation). Deleting a `.use` event frees any linked
    /// transaction to be used again.
    @discardableResult
    func deleteReserveEvent(id: UUID) -> Bool {
        guard reserveEvents.first(where: { $0.id == id })?.type == .use else {
            return false
        }
        do {
            try reserveEventStore.remove(eventID: id)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Set or clear the provenance link on an allocation/release event. Refuses
    /// (returns `false`, no write) a missing event or a `.use` — a use *is* its
    /// link, so unlinking one means deleting it via `deleteReserveEvent`.
    @discardableResult
    func setReserveEventLink(eventID: UUID, hash: String?) -> Bool {
        guard let event = reserveEvents.first(where: { $0.id == eventID }),
              event.type != .use else { return false }
        do {
            try reserveEventStore.setLink(eventID: eventID, hash: hash)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Every ledger event (any type) linked to this transaction, newest first.
    /// Backs the transaction modal's Reserve section.
    func reserveEvents(linkedTo hash: String) -> [ReserveEvent] {
        reserveEvents
            .filter { $0.transactionContentHash == hash }
            .sorted { $0.date > $1.date }
    }

    /// The `.use` ledger event linking this expense, if any. Backs
    /// the transaction modal's Reserve section (`ReserveActivitySection`).
    func usageEvent(forExpense hash: String) -> ReserveEvent? {
        reserveEvents.first { $0.type == .use && $0.transactionContentHash == hash }
    }

    /// The live transaction for a contentHash — the transaction modal re-reads
    /// through this after every write.
    func transaction(withHash hash: String) -> Transaction? {
        allTransactions.first { $0.contentHash == hash }
    }

    /// A linked transaction's type can't change: re-typing would hide the
    /// modal's Reimbursement/Reserve sections while the links still exist. Covers
    /// a reimbursed expense, a reserve-used expense, an income that funds a
    /// reimbursement, and either side of a live manual transfer link.
    func isTypeLocked(_ transaction: Transaction) -> Bool {
        let hash = transaction.contentHash
        return reimbursementLinks[hash] != nil
            || usedTransactionIDs.contains(hash)
            || claimed(forReimbursement: hash) > 0
            || hasManualTransferLink(hash)
    }

    // MARK: - Reimbursement mutations

    /// Link an expense to a reimbursement income (US1/US4). The reimbursed
    /// amount is computed automatically as `min(|expense|, the income's
    /// remaining pool)` and stored as a snapshot — never user-entered
    /// (US1/US2/US8). Rejects (returns `false`, sets `lastSaveError`):
    ///   • an expense that is already linked (US3 — unlink first), or
    ///   • an income whose remaining pool is ≤ 0 (US7 — fully claimed).
    /// Both are also prevented by the UI up front. On success persists one link
    /// (keyed by the expense's contentHash) and refreshes derived state.
    @discardableResult
    func linkReimbursement(expense: Transaction, toIncome income: Transaction, note: String? = nil) -> Bool {
        let expenseHash = expense.contentHash
        // US3: one reimbursement per expense.
        guard reimbursementLinks[expenseHash] == nil else {
            lastSaveError = NSError(domain: "Reimbursements", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "expense is already reimbursed"])
            return false
        }
        let capacity = abs(income.effectiveAmount)
        let remainingPool = remaining(forReimbursement: income.contentHash, capacity: capacity)
        let amount = min(abs(expense.effectiveAmount), remainingPool)
        // US7/US8: nothing left to claim → no link.
        guard amount > 0 else {
            lastSaveError = NSError(domain: "Reimbursements", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "reimbursement is fully claimed"])
            return false
        }
        let link = ReimbursementLink(
            reimbursementHash: income.contentHash,
            amount: amount,
            linkedAt: .now,
            note: note
        )
        do {
            try reimbursementStore.upsert(expenseHash: expenseHash, record: link)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Remove an expense's reimbursement link (US12). The amount returns to the
    /// income's remaining pool automatically (it is derived), and the expense
    /// becomes available to link again. Safe no-op if the expense isn't linked.
    @discardableResult
    func unlinkReimbursement(expenseHash: String) -> Bool {
        do {
            try reimbursementStore.delete(expenseHash: expenseHash)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    // MARK: - Links

    /// One link as seen from one of its two transactions.
    struct ResolvedLink: Identifiable, Equatable {
        enum Origin: Equatable {
            case auto
            case manual(UUID)
        }
        let pair: HashPair
        let counterpartHash: String
        let kind: LinkKind
        let origin: Origin
        let note: String?
        /// Both sides resolve to a loaded transaction. A dangling link is shown
        /// (so it can be unlinked) but counts as unlinked everywhere else.
        let isLive: Bool

        var id: String { pair.id }
    }

    /// Rebuilds `linksByHash` from the saved manual links plus a fresh run of
    /// the transfer auto-pairer. In memory only — never writes.
    private func rebuildLinks() {
        let loaded = Set(allTransactions.map(\.contentHash))
        var index: [String: [ResolvedLink]] = [:]
        var blocked: Set<String> = []

        for link in linkStore.links {
            let pair = link.pair
            let isLive = loaded.contains(pair.a) && loaded.contains(pair.b)
            if isLive, link.kind == .transfer {
                blocked.insert(pair.a)
                blocked.insert(pair.b)
            }
            for side in [pair.a, pair.b] {
                index[side, default: []].append(ResolvedLink(
                    pair: pair, counterpartHash: pair.other(than: side), kind: link.kind,
                    origin: .manual(link.id), note: link.note, isLive: isLive
                ))
            }
        }

        let excluded = Set(linkStore.rejections.map(\.pair)).union(linkStore.links.map(\.pair))
        for pair in TransferAutoPairer.pairs(in: allTransactions, blocked: blocked, excludedPairs: excluded) {
            for side in [pair.a, pair.b] {
                index[side, default: []].append(ResolvedLink(
                    pair: pair, counterpartHash: pair.other(than: side), kind: .transfer,
                    origin: .auto, note: nil, isLive: true
                ))
            }
        }

        // Live first, then manual before auto; otherwise keep insertion order.
        func rank(_ link: ResolvedLink) -> Int {
            (link.isLive ? 0 : 2) + (link.origin == .auto ? 1 : 0)
        }
        linksByHash = index.mapValues { links in
            links.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element)
        }
    }

    /// Every link touching the transaction, including dangling ones.
    func links(for hash: String) -> [ResolvedLink] {
        linksByHash[hash] ?? []
    }

    /// Whether the transaction has a live manual `transfer` link. Such a link
    /// locks the type and takes the transaction out of auto-pairing.
    func hasManualTransferLink(_ hash: String) -> Bool {
        links(for: hash).contains { link in
            guard link.isLive, link.kind == .transfer, case .manual = link.origin else { return false }
            return true
        }
    }

    /// The kind a manual link between the two would get (see `LinkKind.inferred`).
    func inferredLinkKind(between x: Transaction, and y: Transaction) -> LinkKind {
        LinkKind.inferred(
            x, y,
            eitherHasTransferLink: hasManualTransferLink(x.contentHash) || hasManualTransferLink(y.contentHash)
        )
    }

    /// Manually link two transactions, with the kind inferred. Also backs Keep on
    /// an auto-pair (it saves the pair as a manual link, which supersedes it).
    /// Rejects a self-link or a pair that already has a manual link.
    @discardableResult
    func linkTransactions(_ x: Transaction, _ y: Transaction, note: String? = nil) -> Bool {
        let first = transaction(withHash: x.contentHash) ?? x
        let second = transaction(withHash: y.contentHash) ?? y
        let pair = HashPair(first.contentHash, second.contentHash)
        guard first.contentHash != second.contentHash else {
            lastSaveError = NSError(domain: "Links", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "a transaction can't link to itself"])
            return false
        }
        guard !linkStore.links.contains(where: { $0.pair == pair }) else {
            lastSaveError = NSError(domain: "Links", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "these transactions are already linked"])
            return false
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = TransactionLink(
            pair: pair,
            kind: inferredLinkKind(between: first, and: second),
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        )
        do {
            try linkStore.add(link)
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Unlink applies at once: a manual link is deleted, and either way the pair
    /// is saved as a rejection so the auto-pairer never proposes it again
    /// (otherwise unlinking a kept transfer would bring it straight back as Auto).
    @discardableResult
    func unlink(_ link: ResolvedLink) -> Bool {
        do {
            switch link.origin {
            case .manual(let id): try linkStore.unlink(id: id)
            case .auto:           try linkStore.reject(link.pair)
            }
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Manual links where either side no longer resolves — listed in the
    /// Developer tab. Never cleaned up automatically.
    var danglingLinks: [TransactionLink] {
        let loaded = Set(allTransactions.map(\.contentHash))
        return linkStore.links.filter { !loaded.contains($0.hashA) || !loaded.contains($0.hashB) }
    }

    // MARK: - Category mutations

    @discardableResult
    func addCategory(_ draft: CategoryDraft) -> Bool {
        // Normalize whitespace on the display name at the mutation entry point.
        var draft = draft
        draft.displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.displayName.isEmpty {
            lastSaveError = NSError(domain: "Categories", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "displayName cannot be empty"])
            return false
        }
        // Uniqueness.
        if categories.contains(where: { $0.displayName == draft.displayName }) {
            lastSaveError = NSError(domain: "Categories", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "displayName '\(draft.displayName)' already exists"])
            return false
        }
        // Parent-exists + parent-is-root + type-match.
        if let parentID = draft.parent {
            guard let parent = categories.first(where: { $0.id == parentID }) else {
                lastSaveError = NSError(domain: "Categories", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "parent \(parentID) not found"])
                return false
            }
            if parent.parent != nil {
                lastSaveError = NSError(domain: "Categories", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "parent must itself be a root"])
                return false
            }
            if parent.transactionType != draft.transactionType {
                lastSaveError = NSError(domain: "Categories", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "parent/child transactionType mismatch"])
                return false
            }
        }
        do {
            try categoryStore.upsert(draft.materialize())
            categories = categoryStore.categories
            parseAllTransactions()
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func renameCategory(id: String, to newName: String) -> Bool {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if newName.isEmpty {
            lastSaveError = NSError(domain: "Categories", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "displayName cannot be empty"])
            return false
        }
        guard var record = categories.first(where: { $0.id == id }) else { return false }
        if categories.contains(where: { $0.displayName == newName && $0.id != id }) {
            lastSaveError = NSError(domain: "Categories", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "displayName '\(newName)' already exists"])
            return false
        }
        record.displayName = newName
        do {
            try categoryStore.upsert(record)
            categories = categoryStore.categories
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func reparentCategory(id: String, to newParent: String?) -> Bool {
        guard var record = categories.first(where: { $0.id == id }) else { return false }
        // Demote (root → leaf) only when childless.
        if record.parent == nil, newParent != nil,
           categories.contains(where: { $0.parent == id }) {
            lastSaveError = NSError(domain: "Categories", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "cannot demote a root that has children"])
            return false
        }
        if let newParentID = newParent {
            guard let parent = categories.first(where: { $0.id == newParentID }) else { return false }
            if parent.parent != nil {
                lastSaveError = NSError(domain: "Categories", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "new parent must be a root"])
                return false
            }
            if parent.transactionType != record.transactionType {
                lastSaveError = NSError(domain: "Categories", code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "transactionType mismatch"])
                return false
            }
        }
        record.parent = newParent
        do {
            try categoryStore.upsert(record)
            categories = categoryStore.categories
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func updatePatterns(id: String, patterns: [String]) -> Bool {
        guard var record = categories.first(where: { $0.id == id }) else { return false }
        record.patterns = patterns
        do {
            try categoryStore.upsert(record)
            categories = categoryStore.categories
            parseAllTransactions()
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func updateCategoryColor(id: String, color: String) -> Bool {
        guard var record = categories.first(where: { $0.id == id }) else { return false }
        record.color = color
        do {
            try categoryStore.upsert(record)
            categories = categoryStore.categories
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func updateCategorySymbol(id: String, symbol: String) -> Bool {
        guard var record = categories.first(where: { $0.id == id }) else { return false }
        record.symbol = symbol
        do {
            try categoryStore.upsert(record)
            categories = categoryStore.categories
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    @discardableResult
    func deleteCategory(id: String) -> Bool {
        if categories.contains(where: { $0.parent == id }) {
            lastSaveError = NSError(domain: "Categories", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "cannot delete a category with children"])
            return false
        }
        do {
            try categoryStore.delete(id: id)
            categories = categoryStore.categories
            parseAllTransactions()
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    /// Atomic two-file write. On edits.json failure, rolls back categories.json
    /// to the pre-merge snapshot.
    @discardableResult
    func mergeCategory(source sourceID: String, into targetID: String) -> Bool {
        guard let source = categories.first(where: { $0.id == sourceID }),
              let target = categories.first(where: { $0.id == targetID }) else { return false }
        // Same shape (both roots or both leaves under same root) + same type.
        guard source.transactionType == target.transactionType else { return false }
        switch (source.parent, target.parent) {
        case (nil, nil): break
        case (let sp?, let tp?) where sp == tp: break
        default: return false
        }

        let snapshot = categoryStore.categories
        // Build new categories array.
        var newCats: [Category] = []
        for c in categories {
            if c.id == sourceID { continue }                        // drop source
            if c.parent == sourceID {                                // re-parent source's children to target
                var moved = c
                moved.parent = targetID
                newCats.append(moved)
                continue
            }
            if c.id == targetID {                                    // union patterns
                var updated = c
                var seen = Set(updated.patterns)
                for p in source.patterns where !seen.contains(p) {
                    updated.patterns.append(p)
                    seen.insert(p)
                }
                newCats.append(updated)
                continue
            }
            newCats.append(c)
        }
        // Build new edits dict.
        var newEdits = editStore.edits
        for (hash, edit) in editStore.edits {
            var mutated = edit
            var changed = false
            if edit.category?.rawValue == sourceID {
                mutated.category = CategoryID(rawValue: targetID)
                changed = true
            }
            if edit.subcategory?.rawValue == sourceID {
                mutated.subcategory = SubcategoryID(rawValue: targetID)
                changed = true
            }
            if changed { newEdits[hash] = mutated }
        }

        do {
            try categoryStore.replaceAll(newCats)
            do {
                try editStore.replaceAll(newEdits)
            } catch {
                // Roll back categories.
                try? categoryStore.replaceAll(snapshot)
                throw error
            }
            categories = categoryStore.categories
            parseAllTransactions()
            refreshDerivedState()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    // MARK: - Chart axis interactions

    func publishScroll(to date: Date) {
        guard !monthlyMetrics.isEmpty else { return }
        if scrollMonth != date { scrollMonth = date }
    }

    func publishHover(_ date: Date?) {
        guard let date else {
            if hoveredMonth != nil { hoveredMonth = nil }
            return
        }
        guard !monthlyMetrics.isEmpty else { return }
        let snapped = snapToNearestMonth(date)
        if hoveredMonth != snapped { hoveredMonth = snapped }
    }

    func togglePin(_ date: Date) {
        guard !monthlyMetrics.isEmpty else { return }
        let snapped = snapToNearestMonth(date)
        if pinnedMonth == snapped { pinnedMonth = nil } else { pinnedMonth = snapped }
    }

    private func snapToNearestMonth(_ date: Date) -> Date {
        monthlyMetrics
            .map(\.month)
            .min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }) ?? date
    }

    // MARK: - Chart computation

    /// Per-month income/expense/net over `snapshots`, spanning the full contiguous
    /// [start...end] month range (months with no matching snapshot bin to zero) so the
    /// flow range chart's month slots stay fixed regardless of the active filter. Only the
    /// flow fields are populated — the range chart ignores balances/savings-rate/deltas, so
    /// this deliberately skips the full `computeMonthlyMetrics` pipeline (running balances
    /// over a filtered subset would be meaningless).
    static func flowMetrics(from snapshots: [TransactionSnapshot], start: Date, end: Date) -> [MonthlyMetric] {
        let calendar = Calendar.current
        var income: [Date: Double] = [:]
        var expense: [Date: Double] = [:]
        for snap in snapshots {
            let month = calendar.dateInterval(of: .month, for: snap.date)!.start
            switch snap.effectiveType {
            case .income:  income[month, default: 0]  += snap.effectiveAmount
            case .expense: expense[month, default: 0] += abs(snap.effectiveAmount)
            default: break
            }
        }

        var months: [Date] = []
        var cursor = start
        while cursor <= end {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        return months.map { month in
            let inc = income[month] ?? 0, exp = expense[month] ?? 0
            return MonthlyMetric(
                month: month, income: inc, expense: exp, net: inc - exp,
                savingsRate: nil, expenseByCategory: [:], incomeByCategory: [:],
                balances: [:], savingsRateEMA6: nil, savingsRateEMA6Unclamped: nil,
                incomeMoMDelta: nil, expenseMoMDelta: nil, netMoMDelta: nil
            )
        }
    }

    private func computeMonthlyMetrics() -> [MonthlyMetric] {
        // Body copied verbatim from the pre-migration AppViewModel.
        // Two mechanical substitutions from the old version:
        //   • `tx.account?.id` → `tx.accountID`
        //   • `account.initialBalance` iteration is unchanged; still uses
        //     `for account in accounts` on the local `accounts` array.
        let calendar = Calendar.current

        struct Bin {
            var income: Double = 0
            var expense: Double = 0
            var expenseByCategory: [CategoryID: Double] = [:]
            var incomeByCategory: [CategoryID: Double] = [:]
            var accountDeltas: [UUID: Double] = [:]
        }

        var bins: [Date: Bin] = [:]
        for tx in allTransactions {
            let month = calendar.dateInterval(of: .month, for: tx.date)!.start
            var bin = bins[month] ?? Bin()
            bin.accountDeltas[tx.accountID, default: 0] += tx.effectiveAmount
            switch tx.effectiveType {
            case .income:
                bin.income += tx.effectiveAmount
                let cat = tx.effectiveCategory ?? .uncategorized
                bin.incomeByCategory[cat, default: 0] += abs(tx.effectiveAmount)
            case .expense:
                bin.expense += abs(tx.effectiveAmount)
                let cat = tx.effectiveCategory ?? .uncategorized
                bin.expenseByCategory[cat, default: 0] += abs(tx.effectiveAmount)
            default:
                break
            }
            bins[month] = bin
        }

        guard let firstMonth = bins.keys.min(), let lastMonth = bins.keys.max() else {
            return []
        }

        var contiguousMonths: [Date] = []
        var cursor = firstMonth
        while cursor <= lastMonth {
            contiguousMonths.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        var balances: [UUID: Double] = [:]
        for account in accounts { balances[account.id] = account.initialBalance }

        let alpha = 2.0 / 7.0
        var emaFlooredPrev: Double?
        var emaRawPrev: Double?
        var previousIncome: Double?
        var previousExpense: Double?
        var previousNet: Double?

        return contiguousMonths.map { month in
            let bin = bins[month] ?? Bin()
            for account in accounts {
                balances[account.id, default: 0] += bin.accountDeltas[account.id] ?? 0
            }

            let net = bin.income - bin.expense
            let savingsRate: Double? = bin.income > 0 ? net / bin.income : nil

            let emaFloored: Double?
            let emaRaw: Double?
            if let rate = savingsRate {
                let flooredInput = max(0, rate)
                let nextFloored = emaFlooredPrev.map { alpha * flooredInput + (1 - alpha) * $0 } ?? flooredInput
                emaFlooredPrev = nextFloored
                emaFloored = nextFloored

                let nextRaw = emaRawPrev.map { alpha * rate + (1 - alpha) * $0 } ?? rate
                emaRawPrev = nextRaw
                emaRaw = nextRaw
            } else {
                emaFloored = emaFlooredPrev
                emaRaw = emaRawPrev
            }

            let incomeDelta = previousIncome.map { bin.income - $0 }
            let expenseDelta = previousExpense.map { bin.expense - $0 }
            let netDelta = previousNet.map { net - $0 }
            previousIncome = bin.income
            previousExpense = bin.expense
            previousNet = net

            return MonthlyMetric(
                month: month,
                income: bin.income,
                expense: bin.expense,
                net: net,
                savingsRate: savingsRate,
                expenseByCategory: bin.expenseByCategory,
                incomeByCategory: bin.incomeByCategory,
                balances: balances,
                savingsRateEMA6: savingsRate == nil ? nil : emaFloored,
                savingsRateEMA6Unclamped: savingsRate == nil ? nil : emaRaw,
                incomeMoMDelta: incomeDelta,
                expenseMoMDelta: expenseDelta,
                netMoMDelta: netDelta
            )
        }
    }

    // MARK: - DEBUG helpers

#if DEBUG
    struct RowCounts {
        let accounts: Int
        let transactions: Int
        let edits: Int
        let reserves: Int
        let activity: Int
        let reimbursements: Int
    }

    func rowCounts() -> RowCounts {
        RowCounts(
            accounts: accounts.count,
            transactions: allTransactions.count,
            edits: editStore.edits.count,
            reserves: reserves.count,
            activity: reserveEvents.count,
            reimbursements: reimbursementLinks.count
        )
    }

    @discardableResult
    func resetAllData() -> Bool {
        do {
            // Wipe all four stores. Preserves CSV files on disk.
            for a in accountStore.accounts { try accountStore.delete(id: a.id) }
            for b in reserveStore.reserves { try reserveStore.delete(id: b.id) }
            try reserveEventStore.removeAll()
            for k in editStore.edits.keys { try editStore.delete(contentHash: k) }
            try reimbursementStore.replaceAll([:])
            loadEverything()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }
#endif
}
