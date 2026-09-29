import SwiftUI

/// Chips in rows, the way words fill a line: each takes its own width, a row
/// fills from the left and the next begins under it, and every row is
/// centred — or, with `centred` off, starts at the leading edge. `stacked`
/// puts one chip on each row instead, at the row's full width for a chip
/// that asks for it — the accessibility text sizes, where a chip is a
/// sentence wide and two on one line would each be a column of broken
/// words.
///
/// SwiftUI has no wrapping stack; this is the fifty lines it takes. Written
/// 27 Sep 2026 for the facts on a person's card, the date and the name on a
/// photograph's, and the row that adds a relative (`ChipRow`); since 30 Sep
/// 2026 it also lays out the names under a telling (`MemoryRow`), leading.
struct ChipFlow: Layout {
    var spacing: CGFloat = 10
    var stacked = false
    var centred = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let rows = rows(in: width, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX + (stacked || !centred ? 0 : (bounds.width - row.width) / 2)
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The rows the chips fall into at a width. A chip is measured at its
    /// own ideal size — one line of its words — and at the row's width when
    /// its line is longer than the row, so that its words wrap rather than
    /// run off the edge.
    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = stacked ? CGSize.zero : subview.sizeThatFits(.unspecified)
            if stacked || size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let fits = row.items.isEmpty || (!stacked && row.width + spacing + size.width <= width)
            if !fits {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index: index, size: size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// One `List` row of chips on the paper: `ChipFlow` at the default sizes and
/// one chip under another at the accessibility sizes, every chip a honey
/// button (`elderSecondary`). The row's own background is cleared and its
/// insets taken away, because the chips carry their own edge and shadow;
/// the padding is the room that shadow needs inside the row.
struct ChipRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        ChipFlow(spacing: 10, stacked: typeSize.isAccessibilitySize) {
            content()
        }
        .buttonStyle(.elderSecondary)
        .padding(6)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}
