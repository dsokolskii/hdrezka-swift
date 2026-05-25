import SwiftUI
import Foundation

struct CategoryList: Identifiable, Hashable, Equatable, Codable {
    static func == (lhs: CategoryList, rhs: CategoryList) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
    
    var id = UUID()
    let type: Category
    let items: [SubCategoryList]?
    let filters: [SubCategoryList]
    let genres: [SubCategoryList]
    let name: String
    var iconName: String

    init(
        id: UUID = UUID(),
        type: Category,
        items: [SubCategoryList]? = nil,
        filters: [SubCategoryList] = [],
        genres: [SubCategoryList] = [],
        name: String,
        iconName: String
    ) {
        self.id = id
        self.type = type
        self.items = items
        self.filters = filters
        self.genres = genres
        self.name = name
        self.iconName = iconName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case items
        case filters
        case genres
        case name
        case iconName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(Category.self, forKey: .type)
        items = try container.decodeIfPresent([SubCategoryList].self, forKey: .items)
        filters = try container.decodeIfPresent([SubCategoryList].self, forKey: .filters) ?? []
        genres = try container.decodeIfPresent([SubCategoryList].self, forKey: .genres) ?? items ?? []
        name = try container.decode(String.self, forKey: .name)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? ""
    }
}

protocol ListItemProtocol: Identifiable, Hashable, Codable {
    associatedtype ItemType
    var id: UUID { get }
    
    var name: String { set get }
    var uri: String { get set }
}

extension ListItemProtocol {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }
}

class SubCategoryList: ListItemProtocol, Identifiable {
    typealias ItemType = String
    
    var id = UUID()
    
    var name: String = ""
    var uri: String = ""
    
    init(name: String, uri: String) {
        self.name = name
        self.uri = uri
    }
    
    @ViewBuilder
    var detailsView: AnyView {
        AnyView(PreviewDetailView(item: self))
    }
}
