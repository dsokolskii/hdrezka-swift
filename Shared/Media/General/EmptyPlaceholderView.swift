import Foundation

import SwiftUI

struct EmptyPlaceholderView: View {
    
    let text: String
    let image: Image?
    
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            (image ?? Image(systemName: "rectangle.on.rectangle"))
                .imageScale(.large)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

struct EmptyPlaceholderView_Previews: PreviewProvider {
    static var previews: some View {
        EmptyPlaceholderView(text: "No Bookmarks", image: Image(systemName: "bookmark"))
    }
}
