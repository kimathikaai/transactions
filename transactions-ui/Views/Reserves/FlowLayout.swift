import SwiftUI

/// Lays subviews left-to-right, wrapping to a new row whenever the next subview
/// would overflow the proposed width. SwiftUI has no built-in wrapping stack, so
/// this fills that gap for content-hugging strips like the reserve source pills.
struct FlowLayout: Layout {
    /// Horizontal gap between items on the same row.
    var itemSpacing: CGFloat = 8
    /// Vertical gap between rows.
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + itemSpacing
            }
            y += row.height + rowSpacing
        }
    }

    // MARK: - Row planning

    /// One row's member indices plus its measured width/height.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Greedily packs subviews into rows that fit within `maxWidth`.
    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needsSpacing = !current.indices.isEmpty
            let addedWidth = size.width + (needsSpacing ? itemSpacing : 0)

            if needsSpacing && current.width + addedWidth > maxWidth {
                rows.append(current)
                current = Row()
                current.indices.append(index)
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width += addedWidth
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
