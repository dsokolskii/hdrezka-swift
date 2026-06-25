import SwiftUI

struct CategoryListView: View {
    
    @State var item: CategoryList
    
    var body: some View {
        NavigationLink(value: item) {
            Label(LocalizedStringKey(item.name), systemImage: iconName)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
        }
    }

    private var iconName: String {
        if item.iconName.isEmpty == false {
            return item.iconName
        }

        switch item.type {
        case .films:
            return "film.fill"
        case .series:
            return "rectangle.stack.fill"
        case .cartoons, .animation:
            return "sparkles"
        case .search:
            return "magnifyingglass"
        case .new:
            return "sparkles"
        case .collections:
            return "rectangle.stack.fill"
        default:
            return "tv.fill"
        }
    }
}
