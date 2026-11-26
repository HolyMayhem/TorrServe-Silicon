import SwiftUI

struct NewYearSidebarTitle: View {
    let forcePreview: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var burstGroup: BurstGroup?

    var body: some View {
        TimelineView(.everyMinute) { context in
            if forcePreview || Self.isSeasonActive(at: context.date) {
                title.overlay {
                    fireworks
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            } else {
                title
            }
        }
    }

    static func isSeasonActive(at date: Date, timeZone: TimeZone = .current) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return (day.year == 2026 && day.month == 12 && (day.day ?? 0) >= 10)
            || (day.year == 2027 && day.month == 1 && day.day == 1)
    }

    private var title: some View {
        Text("TorrSilicon")
            .font(.system(size: 20, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var fireworks: some View {
        if reduceMotion {
            flash(Self.palette[2], at: UnitPoint(x: 0.38, y: 0.52), progress: 0.4, intensity: 0.55)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { frame in
                if let group = burstGroup {
                    let elapsed = frame.date.timeIntervalSince(group.startedAt)
                    ZStack {
                        ForEach(group.bursts.indices, id: \.self) { index in
                            let burst = group.bursts[index]
                            let progress = (elapsed - burst.delay) / burst.duration
                            if (0..<1).contains(progress) {
                                // A quick rise and a longer decay.
                                let rise = min(1, progress / 0.19)
                                let decay = min(1, (1 - progress) / 0.81)
                                flash(burst.tint, at: burst.center, progress: progress, intensity: rise * rise * decay * decay)
                            }
                        }
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    burstGroup = BurstGroup(startedAt: .now, bursts: Self.makeBursts())
                    try? await Task.sleep(for: .seconds(Double.random(in: 3.2...4.1)))
                }
            }
        }
    }

    private func flash(_ color: Tint, at center: UnitPoint, progress: Double, intensity: Double) -> some View {
        let tint = colorScheme == .dark ? color.dark : color.light
        let letters = RadialGradient(
            stops: [
                .init(color: tint, location: 0),
                .init(color: tint.opacity(0.76), location: 0.47),
                .init(color: tint.opacity(0.18), location: 0.79),
                .init(color: .clear, location: 1)
            ],
            center: center, startRadius: 0, endRadius: 19 + 20 * progress
        )
        .mask { title }

        return ZStack {
            letters.blur(radius: 5.5).opacity(intensity * (colorScheme == .dark ? 0.95 : 0.48))
            letters.opacity(intensity * 0.94)
        }
    }

    private struct Burst {
        let center: UnitPoint
        let delay: Double
        let duration: Double
        let tint: Tint
    }

    private struct BurstGroup {
        let startedAt: Date
        let bursts: [Burst]
    }

    private typealias Tint = (dark: Color, light: Color)

    private static let palette: [Tint] = [
        (Color(red: 1, green: 0.35, blue: 0.39), Color(red: 0.72, green: 0.13, blue: 0.23)),
        (Color(red: 0.28, green: 0.92, blue: 0.53), Color(red: 0.06, green: 0.47, blue: 0.28)),
        (Color(red: 0.75, green: 0.44, blue: 1), Color(red: 0.46, green: 0.21, blue: 0.74)),
        (Color(red: 0.26, green: 0.48, blue: 1), Color(red: 0.16, green: 0.30, blue: 0.71))
    ]

    private static func makeBursts() -> [Burst] {
        let colors = palette.shuffled().prefix(Int.random(in: 1...3))
        let positions = [0.13, 0.50, 0.87].shuffled()
        return zip(colors, positions).map { tint, x in
            Burst(
                center: UnitPoint(x: x + Double.random(in: -0.035...0.035), y: Double.random(in: 0.38...0.62)),
                delay: Double.random(in: 0...0.22),
                duration: Double.random(in: 1.7...2.15),
                tint: tint
            )
        }
    }
}
