import Foundation
import SwiftSoup

struct NavigationRezkaApiResponse: Decodable {
    let categories: [CategoryList]
    let userProfile: RezkaUserProfile?
    
    init(from html: String) throws {
        let doc = try SwiftSoup.parse(html)
        let items = try doc.body()?.getElementById("topnav-menu")?.getElementsByClass("b-topnav__item")
        let filtersElement = try doc.body()?.getElementById("main")?.getElementsByClass("b-content__main_filters").first
        
        var categories: [CategoryList] = []
        
        try items?.forEach({ item in
            let titleElement = try item.getElementsByClass("b-topnav__item-link").first
            let subCategoriesElement = try item.getElementsByClass("b-topnav__sub").first
            
            let titleElementTag = try titleElement?.getElementsByTag("a").first
            
            let typeString = try titleElementTag?.attr("href") ?? ""
            let title = try titleElementTag?.text() ?? ""
            
            let mainSubCategories = try subCategoriesElement?.getElementsByClass("left").first?.getElementsByTag("li")
            let additionalSubCategories = try subCategoriesElement?.getElementsByClass("right").first?.getElementsByTag("li")
            let filterCategories = try filtersElement?.getElementsByClass("b-content__main_filters_item")
            
            var filters = [SubCategoryList]()
            var genres = [SubCategoryList]()
            
            try filterCategories?.forEach({ sub in
                let aTag = try sub.getElementsByTag("a")
                let title = try aTag.text()
                let uri = Self.uri(from: try aTag.attr("href"))
                
                filters.append(SubCategoryList(name: title, uri: uri))
            })
            
            try mainSubCategories?.forEach({ sub in
                let aTag = try sub.getElementsByTag("a")
                let title = try aTag.text()
                let uri = Self.uri(from: try aTag.attr("href"))
                
                genres.append(SubCategoryList(name: title, uri: uri))
            })
            
            try additionalSubCategories?.forEach({ sub in
                let aTag = try sub.getElementsByTag("a")
                let title = try aTag.text()
                let uri = Self.uri(from: try aTag.attr("href"))
                
                genres.append(SubCategoryList(name: title, uri: uri))
            })
            
            let type = Category(rawValue: typeString.letters) ?? .none
            guard type != .none else {
                return
            }
            
            let categoryList = CategoryList(
                type: type,
                items: genres,
                filters: filters,
                genres: genres,
                name: title,
                iconName: ""
            )
            
            categories.append(categoryList)
        })
        
        let preferredOrder: [Category] = [.films, .series, .animation, .cartoons, .general, .new]
        var orderedCategories = preferredOrder.compactMap { type in
            categories.first(where: { $0.type == type })
                .map(Self.normalizedCategory)
        }

        let remainingCategories = categories.filter { category in
            category.type != .collections
                && category.type != .announce
                && !orderedCategories.contains(where: { $0.type == category.type })
        }
        orderedCategories.append(contentsOf: remainingCategories.map(Self.normalizedCategory))
        
        let categoryList = CategoryList(type: .search, items: [], name: "Поиск", iconName: "magnifyingglass")
        orderedCategories.insert(categoryList, at: 0)
        
        self.categories = orderedCategories
        self.userProfile = try Self.userProfile(from: doc)
    }

    private static func normalizedCategory(_ category: CategoryList) -> CategoryList {
        CategoryList(
            id: category.id,
            type: category.type,
            items: category.items,
            filters: category.filters,
            genres: category.genres,
            name: category.type == .new ? "Новинки" : category.name,
            iconName: category.iconName
        )
    }

    private static func uri(from href: String) -> String {
        guard let components = URLComponents(string: href) else {
            return href
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""

        if path.isEmpty {
            return query.isEmpty ? "" : query
        }

        return path + query
    }

    private static func userProfile(from document: Document) throws -> RezkaUserProfile? {
        let containerSelectors = [
            ".b-topnav__user",
            ".b-topnav__profile",
            ".b-header__user",
            ".header-login",
            ".login-panel",
            "a[href*=\"/user/\"]",
            "a[href*=\"/users/\"]",
            "a[href*=\"/profile/\"]"
        ]

        for selector in containerSelectors {
            guard let container = try document.select(selector).first() else {
                continue
            }

            let displayName = try firstNonEmptyText(
                in: container,
                selectors: [
                    ".name",
                    ".user-name",
                    ".profile-name",
                    ".login_name",
                    "span",
                    "strong",
                    "a[title]"
                ]
            )
            let avatarURL = try firstNonEmptyAttribute(
                in: container,
                selectors: [
                    "img.avatar",
                    ".avatar img",
                    ".user-avatar img",
                    ".profile-avatar img",
                    "img[src*=\"avatar\"]",
                    "img"
                ],
                attribute: "src"
            )

            if let displayName, displayName.isEmpty == false {
                return RezkaUserProfile(
                    displayName: displayName,
                    avatarURLString: normalizedAvatarURL(from: avatarURL)
                )
            }

            if let avatarURL {
                return RezkaUserProfile(
                    displayName: "Профиль",
                    avatarURLString: normalizedAvatarURL(from: avatarURL)
                )
            }
        }

        return nil
    }

    private static func firstNonEmptyText(in element: Element, selectors: [String]) throws -> String? {
        for selector in selectors {
            for node in try element.select(selector).array() {
                let text = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty == false {
                    return text
                }

                let title = try node.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty == false {
                    return title
                }
            }
        }

        return nil
    }

    private static func firstNonEmptyAttribute(
        in element: Element,
        selectors: [String],
        attribute: String
    ) throws -> String? {
        for selector in selectors {
            for node in try element.select(selector).array() {
                let value = try node.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty == false {
                    return value
                }
            }
        }

        return nil
    }

    private static func normalizedAvatarURL(from value: String?) -> String? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }

        if value.hasPrefix("//") {
            return "https:\(value)"
        }

        guard let baseURL = URL(string: ConstantsApi.server) else {
            return value
        }

        return URL(string: value, relativeTo: baseURL)?.absoluteURL.absoluteString ?? value
    }
}
