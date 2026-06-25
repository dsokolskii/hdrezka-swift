final class CategoriesListItem: SubCategoryList {
    typealias ItemType = String

    var object: CategoriesListItemObject {
        return CategoriesListItemObject(name: name, uri: uri)
    }
}

struct CategoriesListItemObject {
    let name: String
    let uri: String
}
