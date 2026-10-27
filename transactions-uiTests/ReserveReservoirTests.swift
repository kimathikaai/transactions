import Foundation
import Testing
@testable import transactions_ui

@Suite("Reservoir computations")
struct ReserveReservoirTests {

    // MARK: - Helpers

    private func tx(accountID: UUID, credit: Double = 0, debit: Double = 0) -> Transaction {
        Transaction(
            contentHash: UUID().uuidString,
            date: Date(timeIntervalSince1970: 0),
            details: "t",
            debit: debit, credit: credit,
            transactionType: debit > 0 ? .expense : .income,
            accountID: accountID
        )
    }

    // MARK: - netBalance

    @Test func netBalanceAddsInitialAndTransactions() {
        let a = Account(id: UUID(), name: "A", type: .chequing,
                        initialBalance: 100, csvFileName: "a.csv")
        let txs = [
            tx(accountID: a.id, credit: 50),
            tx(accountID: a.id, debit: 20),
        ]
        #expect(netBalance(of: a, transactions: txs) == 130)
    }

    @Test func netBalanceIgnoresOtherAccounts() {
        let a = Account(id: UUID(), name: "A", type: .chequing,
                        initialBalance: 500, csvFileName: "a.csv")
        let other = UUID()
        let txs = [
            tx(accountID: a.id, credit: 100),
            tx(accountID: other, credit: 9_999), // should be ignored
        ]
        #expect(netBalance(of: a, transactions: txs) == 600)
    }

    @Test func netBalanceEqualsInitialWhenNoTransactions() {
        let a = Account(id: UUID(), name: "A", type: .savings,
                        initialBalance: 1_200, csvFileName: "a.csv")
        #expect(netBalance(of: a, transactions: []) == 1_200)
    }

    // MARK: - allotted

    @Test func allottedSumsReservationsForAccount() {
        let acctA = UUID(); let acctB = UUID()
        let allocs = [
            Reservation(amount: 10, reserveID: UUID(), accountID: acctA),
            Reservation(amount: 5,  reserveID: UUID(), accountID: acctA),
            Reservation(amount: 999, reserveID: UUID(), accountID: acctB),
        ]
        #expect(allotted(for: acctA, reservations: allocs) == 15)
    }

    @Test func allottedIsZeroWhenNoReservations() {
        let acctID = UUID()
        #expect(allotted(for: acctID, reservations: []) == 0)
    }

    // MARK: - free

    @Test func freeIsBalanceMinusAllotted() {
        let a = Account(id: UUID(), name: "A", type: .chequing,
                        initialBalance: 100, csvFileName: "a.csv")
        let txs = [tx(accountID: a.id, credit: 50)]
        let allocs = [Reservation(amount: 30, reserveID: UUID(), accountID: a.id)]
        #expect(free(of: a, transactions: txs, reservations: allocs) == 120)
    }

    @Test func freeEqualsBalanceWhenNoReservations() {
        let a = Account(id: UUID(), name: "Chequing", type: .chequing,
                        initialBalance: 1_200, csvFileName: "chequing.csv")
        #expect(free(of: a, transactions: [], reservations: []) == 1_200)
    }

    // MARK: - reservoirSources / isReservoirSource

    @Test func reservoirSourcesExcludesDebt() {
        let cheq = Account(id: UUID(), name: "C", type: .chequing, initialBalance: 0, csvFileName: "c.csv")
        let debt = Account(id: UUID(), name: "D", type: .debt,     initialBalance: 0, csvFileName: "d.csv")
        let sources = reservoirSources([cheq, debt])
        #expect(sources == [cheq])
    }

    @Test func reservoirSourcesIncludesAllNonDebtTypes() {
        let chq = Account(id: UUID(), name: "Chequing",   type: .chequing,   initialBalance: 1, csvFileName: "c.csv")
        let sav = Account(id: UUID(), name: "Savings",    type: .savings,    initialBalance: 1, csvFileName: "s.csv")
        let inv = Account(id: UUID(), name: "TFSA",       type: .investment, initialBalance: 1, csvFileName: "t.csv")
        let cc  = Account(id: UUID(), name: "Visa",       type: .debt,       initialBalance: 0, csvFileName: "v.csv")
        let sources = reservoirSources([chq, sav, inv, cc])
        #expect(sources.count == 3)
        #expect(!sources.contains { $0.type == .debt })
    }

    @Test func isReservoirSourceFlagReflectsType() {
        let chq = Account(id: UUID(), name: "Chequing",   type: .chequing,   initialBalance: 0, csvFileName: "c.csv")
        let sav = Account(id: UUID(), name: "Savings",    type: .savings,    initialBalance: 0, csvFileName: "s.csv")
        let inv = Account(id: UUID(), name: "TFSA",       type: .investment, initialBalance: 0, csvFileName: "t.csv")
        let cc  = Account(id: UUID(), name: "Visa",       type: .debt,       initialBalance: 0, csvFileName: "v.csv")
        #expect(chq.isReservoirSource)
        #expect(sav.isReservoirSource)
        #expect(inv.isReservoirSource)
        #expect(!cc.isReservoirSource)
    }

    // MARK: - Reserve-level computations (total / amount / reservation)

    @Test func totalSumsAllReservationsForReserve() {
        let reserveID = UUID()
        let acctA = UUID(); let acctB = UUID()
        let allocs = [
            Reservation(amount: 1_000, reserveID: reserveID, accountID: acctA),
            Reservation(amount: 4_000, reserveID: reserveID, accountID: acctB),
            Reservation(amount: 999,   reserveID: UUID(),   accountID: acctA), // different reserve
        ]
        #expect(total(of: reserveID, reservations: allocs) == 5_000)
    }

    @Test func amountReturnsPerSourceReservation() {
        let reserveID = UUID()
        let acctA = UUID(); let acctB = UUID()
        let allocs = [
            Reservation(amount: 1_000, reserveID: reserveID, accountID: acctA),
            Reservation(amount: 4_000, reserveID: reserveID, accountID: acctB),
        ]
        #expect(amount(reserveID: reserveID, accountID: acctA, in: allocs) == 1_000)
        #expect(amount(reserveID: reserveID, accountID: acctB, in: allocs) == 4_000)
    }

    @Test func amountIsZeroWhenNoReservationExists() {
        let reserveID = UUID()
        let other = UUID()
        let allocs = [Reservation(amount: 500, reserveID: reserveID, accountID: UUID())]
        #expect(amount(reserveID: reserveID, accountID: other, in: allocs) == 0)
    }

    @Test func reservationLookupReturnsNilWhenAbsent() {
        let reserveID = UUID()
        let acctID = UUID()
        let allocs = [Reservation(amount: 100, reserveID: UUID(), accountID: acctID)]
        #expect(reservation(reserveID: reserveID, accountID: acctID, in: allocs) == nil)
    }

    @Test func reservationLookupReturnsRowWhenPresent() {
        let reserveID = UUID()
        let acctID = UUID()
        let row = Reservation(amount: 250, reserveID: reserveID, accountID: acctID)
        let allocs = [row, Reservation(amount: 999, reserveID: UUID(), accountID: acctID)]
        #expect(reservation(reserveID: reserveID, accountID: acctID, in: allocs) == row)
    }
}
