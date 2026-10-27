import SwiftUI

private enum SidebarPage: Hashable {
    case transactions
    case categories
    case accounts
    case reserves
    #if DEBUG
    case debug
    #endif
}

struct DashboardSidebarView: View {
    @Environment(AppViewModel.self) private var viewModel
    #if DEBUG
    @State private var selection: SidebarPage = .debug
    #else
    @State private var selection: SidebarPage = .accounts
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Accounts", systemImage: "creditcard")
                    .tag(SidebarPage.accounts)
                Label("Transactions", systemImage: "list.bullet")
                    .tag(SidebarPage.transactions)
                Label("Reserves", systemImage: "tray.2")
                    .tag(SidebarPage.reserves)
                Label("Categories", systemImage: "square.grid.2x2")
                    .tag(SidebarPage.categories)
                #if DEBUG
                Label("Developer", systemImage: "hammer")
                    .tag(SidebarPage.debug)
                #endif
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                if !viewModel.loadWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.loadWarnings) { w in
                            Label("\(w.scope): \(w.message)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                switch selection {
                case .transactions:
                    PageContainer(title: "Transactions") { TransactionListView() }
                case .accounts:
                    PageContainer(title: "Accounts") { AccountsPage() }
                case .reserves:
                    PageContainer(title: "Reserves") { ReservesPage() }
                case .categories:
                    PageContainer(title: "Categories") { CategoriesPanelView() }
                #if DEBUG
                case .debug:
                    PageContainer(title: "Developer") { DebugPanelView() }
                #endif
                }
            }
        }
    }
}
