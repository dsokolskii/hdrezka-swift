import SwiftUI

final class CategoriesListItem: SubCategoryList {
    typealias ItemType = String
    
    @ViewBuilder
    override var detailsView: AnyView {
        AnyView(EmptyView())
    }
    
    var object: CategoriesListItemObject {
        return CategoriesListItemObject(name: name, uri: uri)
    }
}

struct CategoriesListItemObject {
    let name: String
    let uri: String
}
