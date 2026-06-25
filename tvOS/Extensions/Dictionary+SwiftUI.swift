import SwiftUI
import OrderedCollections

fileprivate struct ArrayItem {
    var id = UUID()
    
    let text: String
}

extension ArrayItem: Identifiable, Hashable {}

extension OrderedDictionary {
    var grid: AnyView {
        let items: [ArrayItem] = self.keys.reduce(into: []) { partialResult, key in
            partialResult.append(contentsOf: [ArrayItem(text: "\(key)"), ArrayItem(text: "\(self[key]!)")])
        }
        
        let columns = [
            GridItem(.fixed(labelWidth), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ]
        
        return AnyView(
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(Array(zip(items.indices, items)), id: \.0) { index, item in
                    Text(item.text)
                        .font(index % 2 == 0 ? .caption.weight(.bold) : .callout.weight(.semibold))
                        .foregroundStyle(index % 2 == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                        .lineLimit(index % 2 == 0 ? 1 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    private var labelWidth: CGFloat {
        190
    }
}
