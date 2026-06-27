import SwiftUI

extension View {
    @ViewBuilder
    func onMoveLeftToProfileMenu(_ isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        if isEnabled {
            onMoveCommand { direction in
                guard direction == .left else { return }
                action()
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
