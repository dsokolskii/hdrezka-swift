import Foundation

enum Category: String, CaseIterable, Codable {
    case none
    case general
    case search
    case new
    case films
    case series
    case cartoons
    case animation
    case announce
    case collections
    case loadMore
    
    var text: String {
        if self == .general {
            return "Top Headlines"
        }
        return rawValue.capitalized
    }
    
    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

extension Category: Identifiable {
    var id: Self { self }
}
