import SwiftUI

struct WrapHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        FlexibleView(
            availableWidth: UIScreen.main.bounds.width - 48,
            data: items,
            spacing: 8,
            alignment: .leading,
            content: content
        )
    }
}

private struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let availableWidth: CGFloat
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content

    var body: some View {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for item in data {
            let itemSize = UIHostingController(rootView: content(item)).view.intrinsicContentSize
            if currentRowWidth + itemSize.width + spacing > availableWidth {
                rows.append([item])
                currentRowWidth = itemSize.width + spacing
            } else {
                rows[rows.count - 1].append(item)
                currentRowWidth += itemSize.width + spacing
            }
        }

        return VStack(alignment: alignment, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: spacing) {
                    ForEach(rows[index], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
    }
}
