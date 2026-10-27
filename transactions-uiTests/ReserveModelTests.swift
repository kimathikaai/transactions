import Foundation
import Testing
@testable import transactions_ui

@Suite("Reserve computations")
struct ReserveModelTests {

    // MARK: - Helpers

    private func reserve(name: String = "Test", target: Double = 0) -> Reserve {
        Reserve(name: name, emoji: "💰", colorHex: "#000",
               target: target, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func alloc(reserveID: UUID, accountID: UUID = UUID(), amount: Double) -> Reservation {
        Reservation(amount: amount, reserveID: reserveID, accountID: accountID)
    }

    // MARK: - Reserve struct defaults (replaces reservePersists)

    @Test("Reserve has correct default field values")
    func reserveDefaultsAreCorrect() {
        let b = Reserve(name: "House", emoji: "🏠", colorHex: "#80b1d3")
        #expect(b.name == "House")
        #expect(b.emoji == "🏠")
        #expect(b.colorHex == "#80b1d3")
        #expect(b.sortOrder == 0)
        #expect(b.target == 0)
        #expect(b.tagline == "")
    }

    // MARK: - Reservation struct fields (replaces reservationLinks)

    @Test("Reservation carries correct amount, reserveID, and accountID")
    func reservationHasCorrectFields() {
        let b = reserve(name: "Vacation")
        let accountID = UUID()
        let a = alloc(reserveID: b.id, accountID: accountID, amount: 250)
        #expect(a.amount == 250)
        #expect(a.reserveID == b.id)
        #expect(a.accountID == accountID)
    }

    // MARK: - total()

    @Test("total sums reservations belonging to a reserve and ignores others")
    func totalSumsReservationsForThatReserve() {
        let b = reserve()
        let other = UUID()
        let allocs = [
            alloc(reserveID: b.id, amount: 10),
            alloc(reserveID: b.id, amount: 5),
            alloc(reserveID: other, amount: 999),
        ]
        #expect(total(of: b.id, reservations: allocs) == 15)
    }

    @Test("total returns 0 when there are no reservations for the reserve")
    func totalIsZeroWithNoReservations() {
        let b = reserve()
        #expect(total(of: b.id, reservations: []) == 0)
    }

    // MARK: - progress()

    @Test("progress caps at 1.0 when over-funded")
    func progressCapsAtOne() {
        let b = reserve(target: 100)
        let allocs = [alloc(reserveID: b.id, amount: 250)]
        #expect(progress(of: b, reservations: allocs) == 1.0)
    }

    @Test("progress returns 0 when reserve has no target")
    func progressIsZeroWithoutTarget() {
        let b = reserve(target: 0)
        let allocs = [alloc(reserveID: b.id, amount: 100)]
        #expect(progress(of: b, reservations: allocs) == 0)
    }

    // MARK: - hasTarget()

    @Test("hasTarget is false at zero and true above zero")
    func hasTargetIsFalseAtZero() {
        #expect(hasTarget(reserve(target: 0)) == false)
        #expect(hasTarget(reserve(target: 1)) == true)
    }

    // MARK: - isAtTarget()

    @Test("isAtTarget is true when total reaches the target")
    func isAtTargetTrueWhenTotalReachesTarget() {
        let b = reserve(target: 50)
        let allocs = [alloc(reserveID: b.id, amount: 50)]
        #expect(isAtTarget(b, reservations: allocs))
    }

    @Test("isAtTarget is false when reserve has no target even if funded")
    func isAtTargetFalseWithNoTarget() {
        let b = reserve(target: 0)
        let allocs = [alloc(reserveID: b.id, amount: 100)]
        #expect(isAtTarget(b, reservations: allocs) == false)
    }

    // MARK: - allotted() — account-scoped sum (replaces accountCascade)

    @Test("allotted sums reservations from a given account and ignores other accounts")
    func allottedFiltersToAccount() {
        let accountID = UUID()
        let otherAccountID = UUID()
        let bID = UUID()
        let allocs = [
            Reservation(amount: 300, reserveID: bID, accountID: accountID),
            Reservation(amount: 200, reserveID: bID, accountID: accountID),
            Reservation(amount: 999, reserveID: bID, accountID: otherAccountID),
        ]
        #expect(allotted(for: accountID, reservations: allocs) == 500)
    }

    @Test("allotted returns 0 when account has no reservations (account-cascade analog)")
    func allottedIsZeroAfterAccountRemoval() {
        let removedAccountID = UUID()
        // Simulate post-cascade: no reservations remain for this account
        let remainingAllocs: [Reservation] = []
        #expect(allotted(for: removedAccountID, reservations: remainingAllocs) == 0)
    }
}
