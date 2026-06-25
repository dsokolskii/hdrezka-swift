import SwiftUI

struct SubcategoryListView: View {
    
    let items: [SubCategoryList]
    
    @Binding var selection: SubCategoryList?
    let useSelection: Bool
    
    init(items: [SubCategoryList], selection: Binding<SubCategoryList?>? = nil, useSelection: Bool = false) {
        self.items = items
        
        self._selection = selection ?? .constant(nil)
        
        self.useSelection = useSelection
    }
    
    var body: some View {
        if useSelection {
            List(items, selection: $selection) { row( $0 ) }
        } else {
            List(items) { row( $0 ) }
        }
    }
    
    @ViewBuilder
    private func row(_ item: SubCategoryList) -> some View {
        NavigationLink(value: item) {
            Text(LocalizedStringKey(item.name))
                .font(.callout.weight(.semibold))
        }
    }
}

struct SubcategoryList_Previews: PreviewProvider {
    static var previews: some View {
        SubcategoryListView(items: [SubCategoryList(name: "preview", uri: "hello")], selection: .constant(nil), useSelection: true)
            .previewLayout(.fixed(width: 375, height: 600))
    }
}
