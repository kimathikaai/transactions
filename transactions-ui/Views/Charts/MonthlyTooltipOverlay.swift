import Charts
import SwiftUI

struct MonthlyTooltipOverlay<Tooltip: View>: ViewModifier {
    @Environment(AppViewModel.self) private var vm
    let width: CGFloat
    let tooltip: (Date) -> Tooltip

    @State private var localSelection: Date?

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            content
                .chartXSelection(value: $localSelection)
                .onChange(of: localSelection) { _, newValue in
                    vm.publishHover(newValue)
                }
                .onTapGesture {
                    if let month = vm.hoveredMonth ?? vm.activeMonth {
                        vm.togglePin(month)
                    }
                }

            Divider()

            Group {
                if let month = vm.displayedMonth {
                    tooltip(month)
                } else {
                    Color.clear
                }
            }
            .frame(width: width)
        }
    }
}

extension View {
    func monthlyTooltip<T: View>(
        width: CGFloat = 170,
        @ViewBuilder _ tooltip: @escaping (Date) -> T
    ) -> some View {
        modifier(MonthlyTooltipOverlay(width: width, tooltip: tooltip))
    }
}
