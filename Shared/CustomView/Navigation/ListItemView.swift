import SwiftUI

struct ListItemView: View {
        
    @Binding var item: SubCategoryList
    
    var body: some View {
        Text(item.name)
    }
}
