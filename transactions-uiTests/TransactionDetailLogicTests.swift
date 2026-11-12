import Testing
@testable import transactions_ui

/// Which sections of the transaction modal start expanded.
@MainActor
@Suite("Transaction detail expansion")
struct TransactionDetailLogicTests {

    @Test func editFocusOpensWhatNeedsAttention() {
        #expect(TransactionDetailSection.initialExpansion(
            focus: .edit, isUncategorized: true, hasNotes: false,
            isReimbursed: false, hasReserveActivity: true) == [.category, .reserve])
        #expect(TransactionDetailSection.initialExpansion(
            focus: .edit, isUncategorized: false, hasNotes: true,
            isReimbursed: true, hasReserveActivity: false) == [.notes, .reimbursement])
    }

    @Test func actionFocusOpensOnlyThatSection() {
        #expect(TransactionDetailSection.initialExpansion(
            focus: .reserve, isUncategorized: true, hasNotes: true,
            isReimbursed: true, hasReserveActivity: true) == [.reserve])
        #expect(TransactionDetailSection.initialExpansion(
            focus: .category, isUncategorized: false, hasNotes: false,
            isReimbursed: false, hasReserveActivity: false) == [.category])
        #expect(TransactionDetailSection.initialExpansion(
            focus: .reimbursement, isUncategorized: true, hasNotes: false,
            isReimbursed: false, hasReserveActivity: false) == [.reimbursement])
    }

    @Test func linksFocusExpandsLinks() {
        #expect(TransactionDetailSection.initialExpansion(
            focus: .links, isUncategorized: true, hasNotes: true,
            isReimbursed: false, hasReserveActivity: false, isUnlinkedTransfer: true, hasLinks: true) == [.links])
    }

    @Test func editExpandsLinksForUnlinkedTransfer() {
        #expect(TransactionDetailSection.initialExpansion(
            focus: .edit, isUncategorized: false, hasNotes: false,
            isReimbursed: false, hasReserveActivity: false, isUnlinkedTransfer: true).contains(.links))
    }

    @Test func editExpandsLinksWhenLinked() {
        #expect(TransactionDetailSection.initialExpansion(
            focus: .edit, isUncategorized: false, hasNotes: false,
            isReimbursed: false, hasReserveActivity: false, hasLinks: true).contains(.links))
    }

    @Test func editLeavesLinksCollapsedOtherwise() {
        #expect(!TransactionDetailSection.initialExpansion(
            focus: .edit, isUncategorized: true, hasNotes: true,
            isReimbursed: true, hasReserveActivity: true).contains(.links))
    }
}
