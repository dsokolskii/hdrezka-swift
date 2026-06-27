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

    /// Числовой идентификатор категории для AJAX-endpoint'а
    /// `/engine/ajax/get_newest_slider_content.php`, которым сайт наполняет
    /// подборки новинок на главной (аниме — 82, фильмы — 1, сериалы — 2, мультфильмы — 3).
    var sliderCatId: Int? {
        switch self {
        case .films: return 1
        case .series: return 2
        case .cartoons: return 3
        case .animation: return 82
        default: return nil
        }
    }
}

extension Category: Identifiable {
    var id: Self { self }
}
