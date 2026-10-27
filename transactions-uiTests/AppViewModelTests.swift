import Foundation
import Testing
@testable import transactions_ui

@Suite("AppViewModel")
struct AppViewModelTests {

    private func makeVM(dir: TempDataDirectory) -> AppViewModel {
        AppViewModel(
            accountStore: AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.file("edits.json")),
            categoryStore: CategoryStore(fileURL: dir.file("categories.json")),
            reimbursementStore: ReimbursementStore(fileURL: dir.file("reimbursements.json")),
            csvDirectory: dir.file("csv")
        )
    }

    // MARK: - Account creation

    @Test("createAccount persists across instances")
    func createAccountPersistsAcrossInstances() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let acct = Account(id: UUID(), name: "New", type: .chequing,
                           initialBalance: 0, csvFileName: "new.csv")
        _ = vm1.createAccount(acct)
        #expect(vm1.accounts.contains(acct))

        let vm2 = makeVM(dir: dir)
        #expect(vm2.accounts.contains(acct))
    }

    @Test("fresh VM with empty store has no accounts")
    func emptyStoreHasNoAccounts() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        #expect(vm.accounts.isEmpty)
    }

    // MARK: - Account updates

    @Test("updateAccount writes draft fields back and persists across instances")
    func updateAccountWritesFields() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let acct = Account(id: UUID(), name: "Chequing", type: .chequing,
                           initialBalance: 0, csvFileName: "chequing.csv")
        _ = vm1.createAccount(acct)

        var draft = AccountDraft()
        draft.name = "Renamed Chequing"
        draft.type = .savings
        draft.initialBalance = 999.99
        _ = vm1.updateAccount(acct, with: draft)

        let vm2 = makeVM(dir: dir)
        let loaded = vm2.accounts.first { $0.id == acct.id }
        #expect(loaded?.name == "Renamed Chequing")
        #expect(loaded?.type == .savings)
        #expect(loaded?.initialBalance == 999.99)
    }

    // MARK: - Account deletion

    @Test("deleteAccount removes account and cascades reservations")
    func deleteAccountCascadesReservations() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let acct = Account(id: UUID(), name: "A", type: .chequing,
                           initialBalance: 1_000, csvFileName: "a_\(UUID().uuidString).csv")
        let reserve = Reserve(id: UUID(), name: "B", emoji: "💰",
                            colorHex: "#000", createdAt: Date(timeIntervalSince1970: 0))
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(reserve)
        // Claim requires positive free — account has initialBalance 1_000 and no transactions.
        try? vm.claim(amount: 100, from: acct, to: reserve)
        #expect(vm.reservations.contains { $0.accountID == acct.id })

        _ = vm.deleteAccount(acct)
        #expect(vm.accounts.contains(acct) == false)
        #expect(vm.reservations.allSatisfy { $0.accountID != acct.id })
    }

    @Test("deleteAccount persists removal across instances")
    func deleteAccountPersistsAcrossInstances() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let acct = Account(id: UUID(), name: "Temp", type: .chequing,
                           initialBalance: 0, csvFileName: "temp.csv")
        _ = vm1.createAccount(acct)
        #expect(vm1.accounts.contains(acct))

        _ = vm1.deleteAccount(acct)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.accounts.contains(acct) == false)
    }

    // MARK: - Edit lifecycle

    @Test("saveEdit creates edit row and persists across instances")
    func saveEditPersistsAcrossInstances() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "STARBUCKS", debit: 5.50, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        _ = vm1.saveEdit(for: tx, category: CategoryID(rawValue: "food"),
                         subcategory: nil, notes: "coffee")
        #expect(vm1.rowCounts().edits == 1)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.rowCounts().edits == 1)
    }

    @Test("saveEdit twice upserts — row count stays at 1")
    func saveEditUpdatesInPlace() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "SHOPPERS", debit: 12.00, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        _ = vm.saveEdit(for: tx, category: CategoryID(rawValue: "food"),
                        subcategory: nil, notes: "v1")
        _ = vm.saveEdit(for: tx, category: CategoryID(rawValue: "entertainment"),
                        subcategory: nil, notes: "v2")
        #expect(vm.rowCounts().edits == 1)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.rowCounts().edits == 1)
    }

    @Test("clearEdit removes the edit row and persists across instances")
    func saveEditThenClearEdit() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "TIM HORTONS", debit: 3.00, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        _ = vm1.saveEdit(for: tx, category: CategoryID(rawValue: "food"),
                         subcategory: nil, notes: "coffee")

        let vm2 = makeVM(dir: dir)
        #expect(vm2.rowCounts().edits == 1)

        _ = vm2.clearEdit(for: tx)
        let vm3 = makeVM(dir: dir)
        #expect(vm3.rowCounts().edits == 0)
    }

    @Test("clearEdit on a transaction without an edit is a no-op success")
    func clearEditNoOp() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "NONE", debit: 1.00, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        let result = vm.clearEdit(for: tx)
        #expect(result)
        #expect(vm.rowCounts().edits == 0)
    }

    @Test("saveEdit with type override persists to store")
    func saveEditTypeOverridePersists() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "PAYROLL", debit: 0, credit: 5.50,
            transactionType: .expense, accountID: UUID()
        )
        let ok = vm.saveEdit(for: tx, category: nil, subcategory: nil,
                             notes: nil, transactionType: .income)
        #expect(ok)
        #expect(vm.rowCounts().edits == 1)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.rowCounts().edits == 1)
    }

    // MARK: - Transfer type ↔ category coercion (saveEdit)

    /// Seeds categories.json with one expense root and the two transfer roots,
    /// then returns a VM pointed at that dir. Reused by the coercion tests.
    private func seedTransferCategories(_ dir: TempDataDirectory) throws {
        let seed: [transactions_ui.Category] = [
            transactions_ui.Category(id: "cat_food", displayName: "Food", parent: nil,
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: []),
            transactions_ui.Category(id: "cat_tin", displayName: "Transfer In", parent: nil,
                     color: "#aec6cf", symbol: "arrow.down.circle.fill",
                     transactionType: .transfer_in, patterns: []),
            transactions_ui.Category(id: "cat_tout", displayName: "Transfer Out", parent: nil,
                     color: "#aec6cf", symbol: "arrow.up.circle.fill",
                     transactionType: .transfer_out, patterns: []),
        ]
        try AtomicJSONFile.encoder().encode(seed).write(to: dir.file("categories.json"))
    }

    /// Decodes the persisted edit record for a contentHash straight off disk.
    private func persistedEdit(_ dir: TempDataDirectory, _ hash: String) throws -> TransactionEdit? {
        let data = try Data(contentsOf: dir.file("edits.json"))
        let edits = try AtomicJSONFile.decoder().decode([String: TransactionEdit].self, from: data)
        return edits[hash]
    }

    @Test("saveEdit strips a transfer category from an expense transaction")
    func saveEditStripsTransferCategoryFromExpense() throws {
        let dir = TempDataDirectory()
        try seedTransferCategories(dir)
        let vm = makeVM(dir: dir)
        let hash = "hash-\(UUID().uuidString)"
        let tx = Transaction(
            contentHash: hash,
            date: Date(timeIntervalSince1970: 0),
            details: "SOBEYS", debit: 40.0, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        // User (or a bulk write) tries to attach the Transfer In category to an expense.
        let ok = vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_tin"),
                             subcategory: nil, notes: nil)
        #expect(ok)
        let stored = try persistedEdit(dir, hash)
        #expect(stored?.category == nil)
        #expect(stored?.subcategory == nil)
    }

    @Test("saveEdit with a transfer type override snaps to the transfer category")
    func saveEditTransferTypeSnapsToCategory() throws {
        let dir = TempDataDirectory()
        try seedTransferCategories(dir)
        let vm = makeVM(dir: dir)
        let hash = "hash-\(UUID().uuidString)"
        let tx = Transaction(
            contentHash: hash,
            date: Date(timeIntervalSince1970: 0),
            details: "E-TRANSFER", debit: 0, credit: 100.0,
            transactionType: .income, accountID: UUID()
        )
        // Override to a transfer type with a bogus category + subcategory — both should
        // be coerced to the matching transfer root and nil.
        let ok = vm.saveEdit(for: tx, category: CategoryID(rawValue: "cat_food"),
                             subcategory: SubcategoryID(rawValue: "cat_gro"),
                             notes: nil, transactionType: .transfer_in)
        #expect(ok)
        let stored = try persistedEdit(dir, hash)
        #expect(stored?.category?.rawValue == "cat_tin")
        #expect(stored?.subcategory == nil)
        #expect(stored?.transactionType == .transfer_in)
    }
    func clearEditRevertsType() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let tx = Transaction(
            contentHash: "hash-\(UUID().uuidString)",
            date: Date(timeIntervalSince1970: 0),
            details: "MISC", debit: 5.50, credit: 0,
            transactionType: .expense, accountID: UUID()
        )
        _ = vm1.saveEdit(for: tx, category: nil, subcategory: nil,
                         notes: nil, transactionType: .income)
        #expect(vm1.rowCounts().edits == 1)

        _ = vm1.clearEdit(for: tx)
        #expect(vm1.rowCounts().edits == 0)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.rowCounts().edits == 0)
    }

    // MARK: - Reserves

    @Test("upsertReserve persists across instances")
    func upsertReservePersists() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        // Use a whole-second createdAt so ISO-8601 round-trip preserves equality.
        let reserve = Reserve(id: UUID(), name: "House", emoji: "🏠",
                            colorHex: "#80b1d3", target: 10_000,
                            createdAt: Date(timeIntervalSince1970: 1_000_000))
        _ = vm1.upsertReserve(reserve)
        #expect(vm1.reserves.contains(reserve))

        let vm2 = makeVM(dir: dir)
        #expect(vm2.reserves.contains(reserve))
    }

    @Test("reserves list contains all inserted reserves and persists across instances")
    func reservesListedAndPersist() {
        let dir = TempDataDirectory()
        let vm1 = makeVM(dir: dir)
        let a = Reserve(id: UUID(), name: "A", emoji: "🅰️", colorHex: "#000", sortOrder: 2)
        let b = Reserve(id: UUID(), name: "B", emoji: "🅱️", colorHex: "#111", sortOrder: 0)
        let c = Reserve(id: UUID(), name: "C", emoji: "🆎", colorHex: "#222", sortOrder: 1)
        _ = vm1.upsertReserve(a)
        _ = vm1.upsertReserve(b)
        _ = vm1.upsertReserve(c)

        // The store preserves insertion order; verify all three are present.
        let vm2 = makeVM(dir: dir)
        let names = Set(vm2.reserves.map(\.name))
        #expect(names == Set(["A", "B", "C"]))
        #expect(vm2.reserves.count == 3)
    }

    // MARK: - Reservoir / reservations

    @Test("reservoirSummary aggregates over reservoir-eligible accounts only")
    func reservoirSummaryAggregates() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)

        // Use unique csvFileNames so the parser finds no matching CSVs — no transactions loaded.
        let uid = UUID().uuidString
        let chq = Account(id: UUID(), name: "Chequing", type: .chequing,
                          initialBalance: 1_000, csvFileName: "chq_\(uid).csv")
        let sav = Account(id: UUID(), name: "Savings", type: .savings,
                          initialBalance: 5_000, csvFileName: "sav_\(uid).csv")
        let debt = Account(id: UUID(), name: "Visa", type: .debt,
                           initialBalance: -300, csvFileName: "cc_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "House", emoji: "🏠", colorHex: "#80b1d3")

        _ = vm.createAccount(chq)
        _ = vm.createAccount(sav)
        _ = vm.createAccount(debt)
        _ = vm.upsertReserve(reserve)
        try? vm.claim(amount: 700, from: sav, to: reserve)

        // debt is excluded (isReservoirSource == false); balance = 1_000 + 5_000 = 6_000.
        let summary = vm.reservoirSummary
        #expect(summary.balance == 6_000)
        #expect(summary.reserved == 700)
        #expect(summary.unreserved == 5_300)

        #expect(vm.perSourceSummary.count == 2)
        #expect(vm.perSourceSummary.contains { $0.account.id == chq.id && $0.unreserved == 1_000 })
        #expect(vm.perSourceSummary.contains { $0.account.id == sav.id && $0.unreserved == 4_300 })
    }

    @Test("claim then release round-trips reservation")
    func claimThenRelease() throws {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 2_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "Emergency", emoji: "🚨", colorHex: "#fb8072")
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(reserve)

        try vm.claim(amount: 500, from: acct, to: reserve)
        #expect(vm.reservations.contains { $0.accountID == acct.id && $0.amount == 500 })

        try vm.release(amount: 500, from: reserve, to: acct)
        #expect(vm.reservations.allSatisfy { $0.accountID != acct.id })
    }

    // MARK: - Reserve activity ledger

    @Test("claim with a note records a ledger event visible in activity")
    func claimRecordsActivityEvent() throws {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 2_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "Vacation", emoji: "🏖️", colorHex: "#80b1d3")
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(reserve)

        try vm.claim(amount: 300, from: acct, to: reserve, note: "summer trip")

        #expect(vm.reserveEvents.count == 1)
        #expect(vm.reserveActivity.count == 1)
        let row = vm.reserveActivity[0]
        #expect(row.type == .allocation)
        #expect(row.amount == 300)
        #expect(row.note == "summer trip")
        #expect(row.reserveEmoji == "🏖️")
        #expect(row.reserveName == "Vacation")
        #expect(row.sourceName == "Savings")
    }

    @Test("activity rows carry reserveID so a single reserve's ledger can be isolated")
    func activityFiltersByReserveID() throws {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 5_000, csvFileName: "sav_\(uid).csv")
        let vacation = Reserve(id: UUID(), name: "Vacation", emoji: "🏖️", colorHex: "#80b1d3")
        let emergency = Reserve(id: UUID(), name: "Emergency", emoji: "🚨", colorHex: "#fb8072")
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(vacation)
        _ = vm.upsertReserve(emergency)

        try vm.claim(amount: 300, from: acct, to: vacation, note: "trip")
        try vm.claim(amount: 100, from: acct, to: emergency, note: "buffer")
        try vm.release(amount: 40, from: vacation, to: acct, note: "refund")

        // Every row reports the reserve it belongs to.
        #expect(vm.reserveActivity.allSatisfy { $0.reserveID == vacation.id || $0.reserveID == emergency.id })

        let vacationRows = vm.reserveActivity.filter { $0.reserveID == vacation.id }
        let emergencyRows = vm.reserveActivity.filter { $0.reserveID == emergency.id }
        #expect(vacationRows.count == 2)
        #expect(emergencyRows.count == 1)
        #expect(vacationRows.allSatisfy { $0.reserveName == "Vacation" })
        #expect(emergencyRows.allSatisfy { $0.reserveName == "Emergency" })
    }

    @Test("activity is ordered newest-first")
    func activityNewestFirst() throws {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 2_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "Emergency", emoji: "🚨", colorHex: "#fb8072")
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(reserve)

        try vm.claim(amount: 100, from: acct, to: reserve, note: "first")
        try vm.release(amount: 40, from: reserve, to: acct, note: "second")

        #expect(vm.reserveActivity.count == 2)
        #expect(vm.reserveActivity[0].note == "second")   // most recent on top
        #expect(vm.reserveActivity[0].type == .release)
        #expect(vm.reserveActivity[1].note == "first")
    }

    @Test("events migrate from legacy reservations.json and reproduce balances")
    func migrationSeedsActivityAndBalances() throws {
        let dir = TempDataDirectory()
        // Pre-seed accounts, reserves, and a legacy reservation before first VM boot.
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 5_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "House", emoji: "🏠", colorHex: "#80b1d3")
        try AccountStore(fileURL: dir.file("accounts.json")).upsert(acct)
        try ReserveStore(fileURL: dir.file("reserves.json")).upsert(reserve)
        try AtomicJSONFile.save(
            [Reservation(id: UUID(), amount: 1_200,
                         updatedAt: Date(timeIntervalSince1970: 1_600_000_000),
                         reserveID: reserve.id, accountID: acct.id)],
            to: dir.file("reservations.json"))

        let vm = makeVM(dir: dir)  // reserveEvents.json absent → migration runs

        #expect(vm.reserveEvents.count == 1)
        #expect(vm.reserveEvents[0].note == "Opening balance (migrated)")
        // Derived reservation reproduces the old balance.
        #expect(vm.reservations.contains { $0.accountID == acct.id && $0.amount == 1_200 })
        #expect(vm.perSourceSummary.first { $0.account.id == acct.id }?.reserved == 1_200)
    }

    @Test("deleteReserve cascades its events out of activity")
    func deleteReserveCascadesEvents() throws {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 2_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "Gone", emoji: "🗑️", colorHex: "#000")
        _ = vm.createAccount(acct)
        _ = vm.upsertReserve(reserve)
        try vm.claim(amount: 100, from: acct, to: reserve, note: nil)
        #expect(vm.reserveEvents.count == 1)

        _ = vm.deleteReserve(id: reserve.id)
        #expect(vm.reserveEvents.isEmpty)
        #expect(vm.reserveActivity.isEmpty)
    }

    // MARK: - Reserve use

    /// Boot a VM with one expense transaction pre-seeded via a CSV + account on
    /// disk, plus a reserve funded from that account. Returns the VM, account,
    /// reserve, and the expense transaction's contentHash.
    private func makeVMWithExpense(
        dir: TempDataDirectory,
        initialBalance: Double = 2_000,
        claim: Double = 500,
        expenseAmount: Double = 50
    ) throws -> (vm: AppViewModel, acct: Account, reserve: Reserve, txHash: String) {
        let uid = UUID().uuidString
        let csvName = "sav_\(uid).csv"
        let csvDir = dir.file("csv")
        try FileManager.default.createDirectory(at: csvDir, withIntermediateDirectories: true)
        let csv = """
        Date,Details,Debit,Credit
        2026-01-15,COFFEE SHOP,\(expenseAmount),
        """
        try csv.write(to: csvDir.appendingPathComponent(csvName), atomically: true, encoding: .utf8)

        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: initialBalance, csvFileName: csvName)
        try AccountStore(fileURL: dir.file("accounts.json")).upsert(acct)

        let vm = makeVM(dir: dir)   // loadEverything parses the CSV at boot
        let reserve = Reserve(id: UUID(), name: "Vacation", emoji: "🏖️", colorHex: "#80b1d3", target: 2_000)
        _ = vm.upsertReserve(reserve)
        try vm.claim(amount: claim, from: acct, to: reserve, note: nil)

        let tx = try #require(vm.expenseTransactions.first { $0.details == "COFFEE SHOP" })
        return (vm, acct, reserve, tx.id)
    }

    @Test("use records an activity row with the linked transaction resolved")
    func useRecordsLinkedActivityRow() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, txHash) = try makeVMWithExpense(dir: dir)
        let txDate = try #require(vm.expenseTransactions.first { $0.id == txHash }).date

        try vm.use(amount: 50, from: acct, on: reserve,
                        transactionContentHash: txHash, note: "coffee run")

        let row = try #require(vm.reserveActivity.first { $0.type == .use })
        #expect(row.amount == 50)
        #expect(row.note == "coffee run")
        #expect(row.transactionContentHash == txHash)
        #expect(row.linkedDetails == "COFFEE SHOP")
        #expect(row.linkedDate == txDate)
    }

    @Test("use reduces reserved/held but leaves filled unchanged")
    func useReducesReservedNotFilled() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, txHash) = try makeVMWithExpense(dir: dir)

        let filledBefore = filled(of: reserve, reservations: vm.reservations, events: vm.reserveEvents)
        #expect(filledBefore == 500)

        try vm.use(amount: 50, from: acct, on: reserve,
                        transactionContentHash: txHash, note: nil)

        // held drops by 50, used rises by 50, filled unchanged.
        #expect(total(of: reserve.id, reservations: vm.reservations) == 450)
        #expect(used(of: reserve.id, events: vm.reserveEvents) == 50)
        #expect(filled(of: reserve, reservations: vm.reservations, events: vm.reserveEvents) == 500)
        #expect(vm.perSourceSummary.first { $0.account.id == acct.id }?.reserved == 450)
    }

    @Test("exercising an already-linked transaction throws")
    func useRejectsDoubleLink() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, txHash) = try makeVMWithExpense(dir: dir)
        try vm.use(amount: 50, from: acct, on: reserve,
                        transactionContentHash: txHash, note: nil)
        #expect(throws: ReserveError.transactionAlreadyLinked(contentHash: txHash)) {
            try vm.use(amount: 50, from: acct, on: reserve,
                            transactionContentHash: txHash, note: nil)
        }
    }

    @Test("deleteReserveEvent frees the linked transaction to be used again")
    func deleteReserveEventFreesTransaction() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, txHash) = try makeVMWithExpense(dir: dir)
        try vm.use(amount: 50, from: acct, on: reserve,
                        transactionContentHash: txHash, note: nil)
        #expect(vm.usedTransactionIDs.contains(txHash))

        let useEvent = try #require(vm.reserveEvents.first { $0.type == .use })
        _ = vm.deleteReserveEvent(id: useEvent.id)

        #expect(!vm.usedTransactionIDs.contains(txHash))
        #expect(vm.reserveActivity.allSatisfy { $0.type != .use })
        // Held is restored, so it can be used again without throwing.
        #expect(total(of: reserve.id, reservations: vm.reservations) == 500)
        try vm.use(amount: 50, from: acct, on: reserve,
                        transactionContentHash: txHash, note: nil)
    }

    @Test("usageEvent resolves the .use event linking an expense, nil otherwise")
    func usageEventResolvesLink() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, txHash) = try makeVMWithExpense(dir: dir)

        #expect(vm.usageEvent(forExpense: txHash) == nil)

        try vm.use(amount: 50, from: acct, on: reserve,
                   transactionContentHash: txHash, note: nil)

        let event = try #require(vm.usageEvent(forExpense: txHash))
        #expect(event.type == .use)
        #expect(event.reserveID == reserve.id)
        #expect(event.accountID == acct.id)
        #expect(event.amount == 50)
        #expect(event.transactionContentHash == txHash)

        // After unlink it resolves to nil again.
        _ = vm.deleteReserveEvent(id: event.id)
        #expect(vm.usageEvent(forExpense: txHash) == nil)
    }

    @Test("deleteReserveEvent refuses to delete an allocation event")
    func deleteReserveEventRejectsAllocation() throws {
        let dir = TempDataDirectory()
        let (vm, _, reserve, _) = try makeVMWithExpense(dir: dir)

        let allocation = try #require(vm.reserveEvents.first { $0.type == .allocation })
        let didDelete = vm.deleteReserveEvent(id: allocation.id)

        #expect(didDelete == false)
        #expect(vm.reserveEvents.contains { $0.id == allocation.id })
        #expect(vm.reserveActivity.contains { $0.id == allocation.id })
        // Held balance untouched by the rejected deletion.
        #expect(total(of: reserve.id, reservations: vm.reservations) == 500)
    }

    @Test("deleteReserveEvent refuses to delete a release event")
    func deleteReserveEventRejectsRelease() throws {
        let dir = TempDataDirectory()
        let (vm, acct, reserve, _) = try makeVMWithExpense(dir: dir)
        try vm.release(amount: 200, from: reserve, to: acct, note: nil)

        let releaseEvent = try #require(vm.reserveEvents.first { $0.type == .release })
        let didDelete = vm.deleteReserveEvent(id: releaseEvent.id)

        #expect(didDelete == false)
        #expect(vm.reserveEvents.contains { $0.id == releaseEvent.id })
        #expect(vm.reserveActivity.contains { $0.id == releaseEvent.id })
        // Held balance still reflects the release (500 allocated − 200 released).
        #expect(total(of: reserve.id, reservations: vm.reservations) == 300)
    }

    @Test("an use event with an unresolvable hash renders as unlinked")
    func useUnlinkedWhenHashUnresolvable() throws {
        let dir = TempDataDirectory()
        let uid = UUID().uuidString
        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 2_000, csvFileName: "sav_\(uid).csv")
        let reserve = Reserve(id: UUID(), name: "Vacation", emoji: "🏖️", colorHex: "#80b1d3")
        try AccountStore(fileURL: dir.file("accounts.json")).upsert(acct)
        try ReserveStore(fileURL: dir.file("reserves.json")).upsert(reserve)
        // Pre-seed an event log: an allocation and an use linked to a hash
        // that no live transaction will ever produce.
        try AtomicJSONFile.save([
            ReserveEvent(reserveID: reserve.id, accountID: acct.id, type: .allocation, amount: 100),
            ReserveEvent(reserveID: reserve.id, accountID: acct.id, type: .use, amount: 30,
                         transactionContentHash: "ghost-hash"),
        ], to: dir.file("reserveEvents.json"))

        let vm = makeVM(dir: dir)
        let row = try #require(vm.reserveActivity.first { $0.type == .use })
        #expect(row.transactionContentHash == "ghost-hash")
        #expect(row.linkedDetails == nil)
        #expect(row.linkedDate == nil)
    }

    // MARK: - Categories

    @Test("AppViewModel loads categories.json into `categories` on init")
    func loadsCategories() throws {
        let dir = TempDataDirectory()
        let seed: [transactions_ui.Category] = [
            transactions_ui.Category(id: "cat_food", displayName: "Food", parent: nil,
                     color: "#8dd3c7", symbol: "fork.knife",
                     transactionType: .expense, patterns: [])
        ]
        try JSONEncoder().encode(seed).write(to: dir.file("categories.json"))

        let vm = AppViewModel(
            accountStore:    AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore:     ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore:       EditStore(fileURL: dir.file("edits.json")),
            categoryStore:   CategoryStore(fileURL: dir.file("categories.json")),
            csvDirectory:    dir.file("csv")
        )
        #expect(vm.categories.map(\.id) == ["cat_food"])
    }

    @Test("categoryValidation surfaces broken edits and stale refs on load")
    func categoryValidationOnLoad() throws {
        let dir = TempDataDirectory()
        defer { dir.cleanup() }

        // Create categories file with one valid category
        let catURL = dir.file("categories.json")
        try JSONEncoder().encode([
            transactions_ui.Category(id: "cat_food", displayName: "Food", parent: nil,
                                     color: "#000", symbol: "folder",
                                     transactionType: .expense, patterns: [])
        ]).write(to: catURL)

        // Create edits file with a broken edit (references non-existent category)
        let editURL = dir.file("edits.json")
        let editsData: [String: TransactionEdit] = [
            "orphan_hash": TransactionEdit(category: CategoryID(rawValue: "cat_ghost"))
        ]
        try AtomicJSONFile.encoder().encode(editsData).write(to: editURL)

        let csvDir = dir.file("csv")
        try FileManager.default.createDirectory(at: csvDir, withIntermediateDirectories: true)

        let vm = AppViewModel(
            accountStore:    AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore:     ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore:       EditStore(fileURL: editURL),
            categoryStore:   CategoryStore(fileURL: catURL),
            csvDirectory:    csvDir
        )

        #expect(vm.categoryValidation.brokenEdits.count == 1)
        #expect(vm.categoryValidation.brokenEdits[0].referencedID == "cat_ghost")
        #expect(vm.categoryValidation.staleRefs.map(\.contentHash) == ["orphan_hash"])
    }

    // MARK: - Reimbursement derived lookups

    /// Seeds the reimbursement store file directly (no VM mutation exists yet),
    /// then verifies the VM loads and exposes the derived lookups.
    @Test("reimbursement links load and drive claimed/remaining/hashes")
    func reimbursementDerivedLookups() throws {
        let dir = TempDataDirectory()
        // Two expenses reimbursed from the same $200 income, plus one from another.
        let links: [String: ReimbursementLink] = [
            "expense-1": ReimbursementLink(reimbursementHash: "income-A", amount: 30),
            "expense-2": ReimbursementLink(reimbursementHash: "income-A", amount: 50),
            "expense-3": ReimbursementLink(reimbursementHash: "income-B", amount: 10)
        ]
        try AtomicJSONFile.save(links, to: dir.file("reimbursements.json"))

        let vm = makeVM(dir: dir)

        #expect(vm.reimbursementLinks.count == 3)
        #expect(vm.reimbursedExpenseHashes == ["expense-1", "expense-2", "expense-3"])
        #expect(vm.reimbursementLink(forExpense: "expense-2")?.amount == 50)
        #expect(vm.reimbursementLink(forExpense: "missing") == nil)

        // income-A: 30 + 50 = 80 claimed.
        #expect(vm.claimed(forReimbursement: "income-A") == 80)
        #expect(vm.claimed(forReimbursement: "income-B") == 10)
        #expect(vm.claimed(forReimbursement: "income-unused") == 0)

        // Remaining against a $200 capacity, floored at zero.
        #expect(vm.remaining(forReimbursement: "income-A", capacity: 200) == 120)
        #expect(vm.remaining(forReimbursement: "income-B", capacity: 200) == 190)
        // Over-claimed capacity never goes negative.
        #expect(vm.remaining(forReimbursement: "income-A", capacity: 50) == 0)
    }

    @Test("fresh VM has no reimbursement links")
    func emptyReimbursements() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        #expect(vm.reimbursementLinks.isEmpty)
        #expect(vm.reimbursedExpenseHashes.isEmpty)
        #expect(vm.claimed(forReimbursement: "anything") == 0)
    }

    // MARK: - Reimbursement mutations

    private func expenseTx(_ hash: String, _ amount: Double) -> Transaction {
        Transaction(contentHash: hash, date: Date(timeIntervalSince1970: 0), details: "e",
                    debit: amount, credit: 0, transactionType: .expense, accountID: UUID())
    }

    private func incomeTx(_ hash: String, _ amount: Double) -> Transaction {
        Transaction(contentHash: hash, date: Date(timeIntervalSince1970: 0), details: "i",
                    debit: 0, credit: amount, transactionType: .income, accountID: UUID())
    }

    @Test("link uses min(expense, remaining) for full coverage and persists")
    func linkFullCoverage() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        #expect(vm.linkReimbursement(expense: expenseTx("e1", 100), toIncome: incomeTx("inc", 200)))
        #expect(vm.reimbursementLink(forExpense: "e1")?.amount == 100)
        #expect(vm.reimbursementLink(forExpense: "e1")?.reimbursementHash == "inc")
        #expect(vm.claimed(forReimbursement: "inc") == 100)
        #expect(vm.remaining(forReimbursement: "inc", capacity: 200) == 100)

        let vm2 = makeVM(dir: dir)
        #expect(vm2.reimbursementLink(forExpense: "e1")?.amount == 100)
    }

    @Test("link caps at remaining pool for partial coverage (US2)")
    func linkPartialCoverage() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        #expect(vm.linkReimbursement(expense: expenseTx("e1", 100), toIncome: incomeTx("inc", 60)))
        #expect(vm.reimbursementLink(forExpense: "e1")?.amount == 60)
        #expect(vm.remaining(forReimbursement: "inc", capacity: 60) == 0)
    }

    @Test("links draw down the same pool in order; exhausted pool blocks more (US7)")
    func linkOrderBasedDrawdown() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let inc = incomeTx("inc", 200)
        #expect(vm.linkReimbursement(expense: expenseTx("e1", 150), toIncome: inc))
        #expect(vm.reimbursementLink(forExpense: "e1")?.amount == 150)
        #expect(vm.linkReimbursement(expense: expenseTx("e2", 100), toIncome: inc))
        #expect(vm.reimbursementLink(forExpense: "e2")?.amount == 50)   // only 50 left
        #expect(vm.remaining(forReimbursement: "inc", capacity: 200) == 0)
        // Fully claimed → next link rejected.
        #expect(!vm.linkReimbursement(expense: expenseTx("e3", 20), toIncome: inc))
        #expect(vm.reimbursementLink(forExpense: "e3") == nil)
    }

    @Test("linking an already-linked expense is rejected (US3)")
    func linkRejectsDoubleLink() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        #expect(vm.linkReimbursement(expense: expenseTx("e1", 50), toIncome: incomeTx("a", 100)))
        #expect(!vm.linkReimbursement(expense: expenseTx("e1", 50), toIncome: incomeTx("b", 100)))
        #expect(vm.reimbursementLink(forExpense: "e1")?.reimbursementHash == "a")
    }

    @Test("unlink frees the expense and returns amount to the pool (US12)")
    func unlinkFreesAndReleases() {
        let dir = TempDataDirectory()
        let vm = makeVM(dir: dir)
        let inc = incomeTx("inc", 200)
        _ = vm.linkReimbursement(expense: expenseTx("e1", 80), toIncome: inc)
        #expect(vm.claimed(forReimbursement: "inc") == 80)
        #expect(vm.unlinkReimbursement(expenseHash: "e1"))
        #expect(vm.reimbursementLink(forExpense: "e1") == nil)
        #expect(vm.claimed(forReimbursement: "inc") == 0)
        // Freed → can link again.
        #expect(vm.linkReimbursement(expense: expenseTx("e1", 80), toIncome: inc))
    }

    @Test("linking sets the expense snapshot's isReimbursed flag; unlinking clears it")
    func reimbursedSnapshotFlag() throws {
        let dir = TempDataDirectory()
        let (vm, _, _, txHash) = try makeVMWithExpense(dir: dir)   // COFFEE SHOP expense loaded via CSV
        let expense = try #require(vm.expenseTransactions.first { $0.id == txHash }).transaction

        func expenseSnap() throws -> TransactionSnapshot {
            try #require(vm.transactionsByDateDesc.first { $0.id == txHash })
        }

        // Unlinked to start.
        #expect(try expenseSnap().isReimbursed == false)

        #expect(vm.linkReimbursement(expense: expense, toIncome: incomeTx("inc", 500)))
        #expect(try expenseSnap().isReimbursed == true)
        // Only the reimbursed expense row carries the flag.
        #expect(vm.transactionsByDateDesc.filter(\.isReimbursed).count == 1)

        #expect(vm.unlinkReimbursement(expenseHash: txHash))
        #expect(try expenseSnap().isReimbursed == false)
    }

    // MARK: - Reimbursement review table (US10)

    /// Boot a VM with one expense and one income transaction pre-seeded via a
    /// CSV + account on disk, so the review table's hash resolution has live
    /// transactions to resolve against. Returns the underlying `Transaction`s.
    private func makeVMWithExpenseAndIncome(
        dir: TempDataDirectory
    ) throws -> (vm: AppViewModel, expense: Transaction, income: Transaction) {
        let uid = UUID().uuidString
        let csvName = "acct_\(uid).csv"
        let csvDir = dir.file("csv")
        try FileManager.default.createDirectory(at: csvDir, withIntermediateDirectories: true)
        let csv = """
        Date,Details,Debit,Credit
        2026-01-15,COFFEE SHOP,50,
        2026-01-10,WORK PAYOUT,,200
        """
        try csv.write(to: csvDir.appendingPathComponent(csvName), atomically: true, encoding: .utf8)

        let acct = Account(id: UUID(), name: "Savings", type: .savings,
                           initialBalance: 0, csvFileName: csvName)
        try AccountStore(fileURL: dir.file("accounts.json")).upsert(acct)

        let vm = makeVM(dir: dir)   // loadEverything parses the CSV at boot
        let expenseSnap = try #require(vm.expenseTransactions.first { $0.details == "COFFEE SHOP" })
        let incomeSnap = try #require(vm.incomeTransactions.first { $0.details == "WORK PAYOUT" })
        return (vm, expenseSnap.transaction, incomeSnap.transaction)
    }

    @Test("reimbursementReview is ordered newest-first by linkedAt")
    func reimbursementReviewNewestFirst() throws {
        let dir = TempDataDirectory()
        let links: [String: ReimbursementLink] = [
            "old": ReimbursementLink(reimbursementHash: "inc", amount: 10,
                                     linkedAt: Date(timeIntervalSince1970: 1_000)),
            "new": ReimbursementLink(reimbursementHash: "inc", amount: 20,
                                     linkedAt: Date(timeIntervalSince1970: 3_000)),
            "mid": ReimbursementLink(reimbursementHash: "inc", amount: 30,
                                     linkedAt: Date(timeIntervalSince1970: 2_000))
        ]
        try AtomicJSONFile.save(links, to: dir.file("reimbursements.json"))
        let vm = makeVM(dir: dir)

        #expect(vm.reimbursementReview.map(\.id) == ["new", "mid", "old"])
        // Snapshot amount survives even when no transaction resolves.
        #expect(vm.reimbursementReview.first?.amount == 20)
    }

    @Test("reimbursementReview resolves expense/source details from live transactions")
    func reimbursementReviewResolvesDetails() throws {
        let dir = TempDataDirectory()
        let (vm, expense, income) = try makeVMWithExpenseAndIncome(dir: dir)

        #expect(vm.linkReimbursement(expense: expense, toIncome: income))

        #expect(vm.reimbursementReview.count == 1)
        let row = try #require(vm.reimbursementReview.first)
        #expect(row.id == expense.contentHash)
        #expect(row.expenseDetails == "COFFEE SHOP")
        #expect(row.expenseAccountName == "Savings")
        #expect(row.sourceDetails == "WORK PAYOUT")
        #expect(row.sourceDate == income.date)
        #expect(row.amount == 50)   // min(|expense| 50, remaining 200)
    }

    @Test("dangling link still renders and is flagged in danglingReimbursementLinks (US13)")
    func danglingReimbursementLinksDetectsMissing() throws {
        let dir = TempDataDirectory()
        // Neither hash resolves — no transactions are loaded.
        let links: [String: ReimbursementLink] = [
            "ghost-expense": ReimbursementLink(reimbursementHash: "ghost-income", amount: 42,
                                               linkedAt: Date(timeIntervalSince1970: 500))
        ]
        try AtomicJSONFile.save(links, to: dir.file("reimbursements.json"))
        let vm = makeVM(dir: dir)

        // Still renders in the review table; amount + date intact, details nil.
        let row = try #require(vm.reimbursementReview.first)
        #expect(row.amount == 42)
        #expect(row.expenseDetails == nil)
        #expect(row.sourceDetails == nil)

        // Flagged with both sides missing.
        #expect(vm.danglingReimbursementLinks.count == 1)
        let dangling = try #require(vm.danglingReimbursementLinks.first)
        #expect(dangling.expenseHash == "ghost-expense")
        #expect(dangling.reimbursementHash == "ghost-income")
        #expect(dangling.expenseMissing)
        #expect(dangling.sourceMissing)
    }
}
