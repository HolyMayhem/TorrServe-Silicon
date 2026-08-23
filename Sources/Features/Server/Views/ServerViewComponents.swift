import SwiftUI

struct TorrServerUpdateProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(Color.blue.gradient)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.18), value: progress)
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}
