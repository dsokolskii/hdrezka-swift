import Foundation

extension String {
    var digits: String {
        return components(separatedBy: .decimalDigits.inverted).joined()
    }
    
    var letters: String {
        return components(separatedBy: .letters.inverted).joined()
    }
}
