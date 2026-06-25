import SwiftUI

struct RetryView: View {
    let text: String
    let retryAction: () -> ()
    @FocusState private var isRetryButtonFocused: Bool

    var body: some View {
        ZStack {
            ScreenBackground()

            AppPanel {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.yellow)

                    Text(text)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Button(action: retryAction) {
                        Text("Try again")
                    }
                    .buttonStyle(.glassProminent)
                    .focused($isRetryButtonFocused)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            isRetryButtonFocused = true
        }
    }
}

struct RetryView_Previews: PreviewProvider {
    static var previews: some View {
        RetryView(text: "An error ocurred") {}
    }
}
