import Foundation
import Testing
@testable import transactions_ui

/// Covers the view model's link index: transfer auto-pairing on load, manual
/// links, Keep/Unlink, rejections, the type lock, the delete cascade, and
/// dangling links.
@Suite("Links")
struct AppViewModelLinkTests {

    private let chequing = Account(id: UUID(), name: "Chequing", type: .chequing,
                                   initialBalance: 0, csvFileName: "chq.csv")
    private let savings = Account(id: UUID(), name: "Savings", type: .savings,
                                  initialBalance: 0, csvFileName: "sav.csv")
    private let investment = Account(id: UUID(), name: "RRSP", type: .investment,
                                     initialBalance: 0, csvFileName: "rrsp.csv")

    private func makeVM(dir: TempDataDirectory) -> AppViewModel {
        AppViewModel(
            accountStore: AccountStore(fileURL: dir.file("accounts.json")),
            reserveStore: ReserveStore(fileURL: dir.file("reserves.json")),
            reserveEventStore: ReserveEventStore(fileURL: dir.file("reserveEvents.json")),
            editStore: EditStore(fileURL: dir.file("edits.json")),
            categoryStore: CategoryStore(fileURL: dir.file("categories.json")),
            reimbursementStore: ReimbursementStore(fileURL: dir.file("reimbursements.json")),
            linkStore: LinkStore(fileURL: dir.file("links.json")),
            csvDirectory: dir.file("csv")
        )
    }

    /// Chequing: a $500 transfer out (Mar 1) and a payroll (Mar 5).
    /// Savings: the matching $500 transfer in (Mar 2). RRSP: no CSV.
    private func seed(_ dir: TempDataDirectory) throws {
        try AtomicJSONFile.save([chequing, savings, investment], to: dir.file("accounts.json"))
        let csv = dir.file("csv")
        try FileManager.default.createDirectory(at: csv, withIntermediateDirectories: true)
        try Data("""
        2026-03-01,INTERNET TRANSFER 000111,500.00,
        2026-03-05,GLOBEX CORP PAYROLL,,2000.00

        """.utf8).write(to: csv.appendingPathComponent("chq.csv"))
        try Data("""
        2026-03-02,INTERNET TRANSFER 000111,,500.00

        """.utf8).write(to: csv.appendingPathComponent("sav.csv"))
    }

    private struct Fixture {
        let vm: AppViewModel
        let out: Transaction
        let inn: Transaction
        let payroll: Transaction
    }

    private func load(_ dir: TempDataDirectory) throws -> Fixture {
        let vm = makeVM(dir: dir)
        let out = try #require(vm.allTransactions.first { $0.accountID == chequing.id && $0.effectiveType == .transfer_out })
        let inn = try #require(vm.allTransactions.first { $0.accountID == savings.id })
        let payroll = try #require(vm.allTransactions.first { $0.details == "GLOBEX CORP PAYROLL" })
        return Fixture(vm: vm, out: out, inn: inn, payroll: payroll)
    }

    private func diskLinks(_ dir: TempDataDirectory) throws -> LinkStore {
        let store = LinkStore(fileURL: dir.file("links.json"))
        try store.load()
        return store
    }

    private func snapshot(_ vm: AppViewModel, _ tx: Transaction) -> TransactionSnapshot? {
        vm.transactionsByDateDesc.first { $0.id == tx.contentHash }
    }

    // MARK: - Auto-pairing

    @Test func autoPairsOnLoad() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        let link = try #require(f.vm.links(for: f.out.contentHash).first)
        #expect(link.origin == .auto)
        #expect(link.kind == .transfer)
        #expect(link.counterpartHash == f.inn.contentHash)
        #expect(link.isLive)
        #expect(f.vm.links(for: f.inn.contentHash).first?.counterpartHash == f.out.contentHash)
    }

    @Test func snapshotFlagsReflectLinks() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(snapshot(f.vm, f.out)?.isLinked == true)
        #expect(snapshot(f.vm, f.out)?.hasTransferLink == true)
        #expect(snapshot(f.vm, f.payroll)?.isLinked == false)
    }

    @Test func loadDoesNotWriteLinksFile() throws {
        let dir = TempDataDirectory(); try seed(dir)
        _ = try load(dir)
        #expect(!FileManager.default.fileExists(atPath: dir.file("links.json").path))
    }

    @Test func unlinkAutoPairSavesRejection() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        let auto = try #require(f.vm.links(for: f.out.contentHash).first)
        #expect(f.vm.unlink(auto))
        #expect(f.vm.links(for: f.out.contentHash).isEmpty)
        #expect(f.vm.links(for: f.inn.contentHash).isEmpty)
        #expect(try diskLinks(dir).rejections.count == 1)
    }

    @Test func rejectionSurvivesReload() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        f.vm.unlink(try #require(f.vm.links(for: f.out.contentHash).first))
        let reloaded = try load(dir)
        #expect(reloaded.vm.links(for: reloaded.out.contentHash).isEmpty)
    }

    @Test func keepPinsAutoPairAsManual() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.out, f.inn))
        let pinned = try #require(f.vm.links(for: f.out.contentHash).first)
        #expect(f.vm.links(for: f.out.contentHash).count == 1)
        #expect(pinned.kind == .transfer)
        guard case .manual = pinned.origin else { Issue.record("expected manual"); return }

        let reloaded = try load(dir)
        let again = try #require(reloaded.vm.links(for: reloaded.out.contentHash).first)
        guard case .manual = again.origin else { Issue.record("expected manual after reload"); return }
    }

    /// Unlinking a kept (manual) transfer must not let the auto-pairer re-propose it.
    @Test func keepThenUnlinkStaysUnlinked() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.out, f.inn))
        #expect(f.vm.unlink(try #require(f.vm.links(for: f.out.contentHash).first)))
        #expect(f.vm.links(for: f.out.contentHash).isEmpty)
        #expect(f.vm.links(for: f.inn.contentHash).isEmpty)
        let disk = try diskLinks(dir)
        #expect(disk.links.isEmpty)
        #expect(disk.rejections.count == 1)
    }

    @Test func manualLinkOfRejectedPairClearsRejection() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        f.vm.unlink(try #require(f.vm.links(for: f.out.contentHash).first))
        #expect(f.vm.linkTransactions(f.out, f.inn))
        let disk = try diskLinks(dir)
        #expect(disk.rejections.isEmpty)
        #expect(disk.links.count == 1)
    }

    // MARK: - Manual links

    @Test func relatedLinkFromIncome() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.payroll, f.inn, note: "Employer RRSP match"))
        let fromPayroll = try #require(f.vm.links(for: f.payroll.contentHash).first)
        #expect(fromPayroll.kind == .related)
        #expect(fromPayroll.note == "Employer RRSP match")
        let inLinks = f.vm.links(for: f.inn.contentHash)
        #expect(inLinks.contains { $0.counterpartHash == f.payroll.contentHash && $0.kind == .related })
        #expect(inLinks.contains { $0.counterpartHash == f.out.contentHash && $0.origin == .auto })
    }

    @Test func duplicateManualLinkRejected() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.payroll, f.inn))
        #expect(f.vm.linkTransactions(f.inn, f.payroll) == false)
        #expect(f.vm.lastSaveError != nil)
        #expect(try diskLinks(dir).links.count == 1)
    }

    @Test func selfLinkRejected() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.payroll, f.payroll) == false)
        #expect(f.vm.links(for: f.payroll.contentHash).isEmpty)
    }

    @Test func manualTransferBlocksAutoPair() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        // A second transfer in (RRSP, Mar 1, $480) linked by hand to the out.
        #expect(f.vm.addManualTransaction(date: f.out.date, signedAmount: 480,
                                          details: "INTERNET TRANSFER 000111", into: investment))
        let rrspIn = try #require(f.vm.allTransactions.first { $0.accountID == investment.id })
        #expect(f.vm.linkTransactions(f.out, rrspIn))
        let outLinks = f.vm.links(for: f.out.contentHash)
        #expect(outLinks.count == 1)
        #expect(outLinks.first?.counterpartHash == rrspIn.contentHash)
        #expect(outLinks.first?.kind == .transfer)
        #expect(f.vm.links(for: f.inn.contentHash).isEmpty)
    }

    @Test func manualTransferLocksType() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.isTypeLocked(f.out) == false)   // auto-pair only
        #expect(f.vm.linkTransactions(f.out, f.inn))
        #expect(f.vm.isTypeLocked(f.out))
        #expect(f.vm.isTypeLocked(f.inn))
    }

    @Test func relatedLinkDoesNotLockType() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.payroll, f.inn))
        #expect(f.vm.isTypeLocked(f.payroll) == false)
    }

    @Test func typeOverrideDropsAutoPair() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.saveEdit(for: f.out, category: nil, subcategory: nil, notes: nil, transactionType: .expense))
        #expect(f.vm.links(for: f.inn.contentHash).isEmpty)
        #expect(f.vm.links(for: f.out.contentHash).isEmpty)
    }

    // MARK: - Deletion and dangling links

    @Test func deleteCascadesLinks() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.linkTransactions(f.payroll, f.inn))
        #expect(f.vm.deleteTransaction(f.inn, from: savings))
        #expect(try diskLinks(dir).links.isEmpty)
        #expect(f.vm.links(for: f.payroll.contentHash).isEmpty)
        #expect(f.vm.links(for: f.out.contentHash).isEmpty)
    }

    @Test func danglingLinkIsNotLive() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let payrollHash = try load(dir).payroll.contentHash
        try LinkStore(fileURL: dir.file("links.json"))
            .add(TransactionLink(pair: HashPair(payrollHash, "missing"), kind: .related))

        let f = try load(dir)
        #expect(f.vm.danglingLinks.count == 1)
        let link = try #require(f.vm.links(for: f.payroll.contentHash).first)
        #expect(link.isLive == false)
        #expect(link.counterpartHash == "missing")
        #expect(snapshot(f.vm, f.payroll)?.isLinked == false)
    }

    @Test func danglingTransferLinkDoesNotBlockAutoPair() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let outHash = try load(dir).out.contentHash
        try LinkStore(fileURL: dir.file("links.json"))
            .add(TransactionLink(pair: HashPair(outHash, "missing"), kind: .transfer))

        let f = try load(dir)
        #expect(f.vm.links(for: f.out.contentHash).contains { $0.origin == .auto && $0.counterpartHash == f.inn.contentHash })
        #expect(f.vm.isTypeLocked(f.out) == false)
    }

    @Test func linksIgnoredByMonthlyMetrics() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        func totals() -> [[Double]] {
            f.vm.monthlyMetrics.map { [$0.income, $0.expense, $0.net, $0.netWorth] }
        }
        let before = totals()
        #expect(f.vm.linkTransactions(f.payroll, f.inn))
        #expect(totals() == before)
    }

    // MARK: - Create & link

    @Test func appendManualTransactionReturnsHash() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        let hash = try #require(f.vm.appendManualTransaction(
            date: f.payroll.date, signedAmount: 150, details: "Employer RRSP match", into: investment))
        let row = try #require(f.vm.transaction(withHash: hash))
        #expect(row.details == "Employer RRSP match")
        #expect(row.accountID == investment.id)
    }

    @Test func appendManualTransactionReturnsNilForBlankDetails() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.appendManualTransaction(date: .now, signedAmount: 10, details: "  ", into: investment) == nil)
    }

    @Test func createLinkedTransferWritesTypeEdit() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        f.vm.unlink(try #require(f.vm.links(for: f.out.contentHash).first))

        #expect(f.vm.createLinkedTransaction(
            from: f.out, into: investment, date: f.out.date, amount: 500,
            details: "Transfer from Chequing", type: .transfer_in, note: nil))

        let created = try #require(f.vm.allTransactions.first { $0.accountID == investment.id })
        #expect(created.transactionType == .income)          // no transfer keyword in the details
        #expect(created.effectiveType == .transfer_in)
        #expect(created.edit?.transactionType == .transfer_in)
        let link = try #require(f.vm.links(for: f.out.contentHash).first)
        #expect(link.counterpartHash == created.contentHash)
        #expect(link.kind == .transfer)
        guard case .manual = link.origin else { Issue.record("expected manual"); return }
    }

    @Test func createLinkedSkipsEditWhenParsedTypeMatches() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.createLinkedTransaction(
            from: f.payroll, into: investment, date: f.payroll.date, amount: 150,
            details: "Employer RRSP match", type: .income, note: "Employer RRSP match"))
        let created = try #require(f.vm.allTransactions.first { $0.accountID == investment.id })
        #expect(created.edit == nil)
        #expect(f.vm.links(for: f.payroll.contentHash).first?.note == "Employer RRSP match")
    }

    @Test func createLinkedRrspFromPayroll() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.createLinkedTransaction(
            from: f.payroll, into: investment, date: f.payroll.date, amount: 150,
            details: "Employer RRSP match", type: .income, note: nil))
        #expect(f.vm.createLinkedTransaction(
            from: f.payroll, into: investment, date: f.payroll.date, amount: 75,
            details: "Employer ESPP match", type: .income, note: nil))

        let links = f.vm.links(for: f.payroll.contentHash)
        #expect(links.count == 2)
        #expect(links.allSatisfy { $0.kind == .related })
        let amounts = links.compactMap { f.vm.transaction(withHash: $0.counterpartHash)?.effectiveAmount }
        #expect(amounts.sorted() == [75, 150])
    }

    @Test func createLinkedSignFollowsType() throws {
        let dir = TempDataDirectory(); try seed(dir)
        let f = try load(dir)
        #expect(f.vm.createLinkedTransaction(
            from: f.payroll, into: investment, date: f.payroll.date, amount: 40,
            details: "Account fee", type: .expense, note: nil))
        let created = try #require(f.vm.allTransactions.first { $0.accountID == investment.id })
        #expect(created.amount == -40)
        #expect(created.effectiveType == .expense)
    }
}
