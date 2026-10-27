import Charts
import SwiftUI

struct SyncMonthlyAxis: ViewModifier {
    @Environment(AppViewModel.self) private var vm
    @State private var localScrollPosition: Date = .now

    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let months = vm.monthlyMetrics.map(\.month)
        let first = months.first ?? .now
        let last = months.last ?? .now
        let lower = calendar.date(byAdding: .month, value: -1, to: first) ?? first
        let upper = calendar.date(byAdding: .month, value: 1, to: last) ?? last
        return lower...upper
    }

    private var visibleLength: TimeInterval {
        Double(vm.visibleWindowMonths) * 30.4375 * 24 * 3600
    }

    func body(content: Content) -> some View {
        content
            .chartScrollableAxes(.horizontal)
            .chartXScale(domain: xDomain)
            .chartXVisibleDomain(length: visibleLength)
            .chartScrollPosition(x: $localScrollPosition)
            .onAppear {
                if let initial = vm.scrollMonth {
                    localScrollPosition = initial
                } else {
                    seedScrollIfNeeded()
                }
            }
            .onChange(of: localScrollPosition) { _, newValue in
                vm.publishScroll(to: newValue)
            }
            .onChange(of: vm.scrollMonth) { _, newValue in
                if let newValue, newValue != localScrollPosition {
                    localScrollPosition = newValue
                }
            }
    }

    private func seedScrollIfNeeded() {
        guard let last = vm.monthlyMetrics.last?.month else { return }
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .month, value: -vm.visibleWindowMonths, to: last) ?? last
        vm.publishScroll(to: target)
        localScrollPosition = target
    }
}

extension View {
    func syncMonthlyAxis() -> some View {
        modifier(SyncMonthlyAxis())
    }
}
