import SwiftUI

enum MemoSurfaceMetrics {
    static let cornerRadius: CGFloat = 12
    static let tabBarHeight: CGFloat = 38
    static let activeTabHeight: CGFloat = 32
    static let inactiveTabHeight: CGFloat = 27
    static let maximumTabWidth: CGFloat = 180
    /// Equal division stops shrinking here. The floor is low enough that `maximumTabCount`
    /// tabs still fit inside the narrowest memo (244 − 56 − 30 = 158pt of strip), because a tab
    /// the strip clips away is one nothing can select and nothing can close — the sticker drops
    /// out below 54pt and the name truncates, which is recoverable, but disappearing is not.
    static let minimumTabWidth: CGFloat = 30
    /// Chosen against the narrowest memo: 158 / 5 ≈ 31pt, just above `minimumTabWidth`.
    static let maximumTabCount = 5
    static let addTabButtonWidth: CGFloat = 30
    static let trailingControlsWidth: CGFloat = 56
    static let tabCornerRadius: CGFloat = 8
}

struct MemoCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: MemoSurfaceMetrics.cornerRadius, style: .continuous)
            .path(in: rect)
    }
}

/// Chrome-like tabs use calm rounded shoulders and a flat bottom that can join the memo body.
struct MemoTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(
            MemoSurfaceMetrics.tabCornerRadius,
            rect.height * 0.42,
            rect.width * 0.25
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct MemoCardSurface: View {
    let paperColor: Color

    var body: some View {
        ZStack {
            MemoCardShape()
                .fill(paperColor)

            PaperGrain()
                .clipShape(MemoCardShape())
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A soft sheen at the top and a faint shadow pooling at the bottom, so the matte paper still
/// reads as lifted off the desktop. No blur, no transparency — the card stays fully opaque; this
/// is lighting, not the glassmorphism the tabbed redesign moved away from. Drawn as the topmost
/// layer over the whole card, tab bar included, so the lift reads across the one continuous
/// surface rather than stopping at the tab strip's own background.
struct MemoCardSheen: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.16), location: 0),
                .init(color: .white.opacity(0), location: 0.22),
                .init(color: .black.opacity(0), location: 0.86),
                .init(color: .black.opacity(0.05), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            let area = max(1, size.width * size.height)
            let fiberCount = max(42, Int(area / 900))

            for index in 0..<fiberCount {
                let x = unitValue(index * 47 + 13) * size.width
                let y = unitValue(index * 71 + 29) * size.height
                let length = 3 + unitValue(index * 31 + 7) * 8
                let rise = (unitValue(index * 19 + 3) - 0.5) * 1.8

                var fiber = Path()
                fiber.move(to: CGPoint(x: x, y: y))
                fiber.addLine(to: CGPoint(x: min(size.width, x + length), y: y + rise))

                context.stroke(
                    fiber,
                    with: .color(.black.opacity(index.isMultiple(of: 3) ? 0.025 : 0.016)),
                    lineWidth: index.isMultiple(of: 4) ? 0.55 : 0.35
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func unitValue(_ seed: Int) -> CGFloat {
        CGFloat((seed * 37 + 17) % 101) / 101
    }
}

/// Posteight's `8` expressed as a clean infinity loop. This embraces the wide silhouette as the
/// mark itself instead of asking a tiny menu-bar glyph to explain that a numeral was rotated.
private struct PosteightInfinityShape: Shape {
    /// The lemniscate's raw y range is only about 0.35 of its nominal half-height.
    private static let lobeCorrection: CGFloat = 2.83

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2
        var path = Path()
        let steps = 64
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let sine = sin(t)
            let cosine = cos(t)
            let denominator = 1 + sine * sine
            let point = CGPoint(
                x: cx + halfWidth * cosine / denominator,
                y: cy + halfHeight * Self.lobeCorrection * cosine * sine / denominator
            )
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// The status item: Posteight's compact infinity mark stays still in the menu bar, while the selected
/// count sits beside it as ordinary text. Completing an item briefly traces the new fraction;
/// clearing the day replaces the number with a persistent, language-neutral checkmark. macOS
/// flattens the mark and check together into one template image, so neither can disappear from
/// the constrained `MenuBarExtra` label renderer.
///
/// `MenuBarExtra` only renders `Text` and `Image` in its label — a `Shape` or `Canvas` put there
/// draws nothing at all, and the status item silently comes up with the text beside it and no
/// picture. So the loop is drawn once into an `NSImage` and handed over as an `Image`.
// ponytail: renders only the few frames following a completion, then becomes completely still.
// A `TimelineView(.animation)` spins the status item's update -> re-render loop at 100% CPU and
// can prevent launch from settling, even when the pixels in the label are no longer changing.
struct MenuBarProgressCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let done: Int
    let total: Int
    /// The number beside the loop — whichever of remaining or done the user picked.
    let count: Int

    /// The fraction actually drawn. It changes only for the brief completion response.
    @State private var shown: Double
    @State private var previousDone: Int

    private struct ProgressState: Equatable {
        let done: Int
        let total: Int
    }

    init(done: Int, total: Int, count: Int) {
        self.done = done
        self.total = total
        self.count = count
        _shown = State(initialValue: Self.fill(done: done, total: total))
        _previousDone = State(initialValue: done)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.render(fill: shown, hasTasks: total > 0, isCleared: isCleared))
                .renderingMode(.template)

            if total > 0 && !isCleared {
                Text(String(count))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityHidden(true)
        .task(id: ProgressState(done: done, total: total)) {
            await updateProgress()
        }
    }

    /// Only an actual completion earns motion. Adding, deleting, or reopening an item updates the
    /// static progress immediately, so the icon never suggests a background operation is running.
    @MainActor
    private func updateProgress() async {
        let target = fill
        let completedItem = done > previousDone
        previousDone = done

        guard completedItem, target > shown else {
            shown = target
            return
        }

        if reduceMotion {
            shown = target
        } else {
            let start = shown
            let steps = 12
            for step in 1...steps {
                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let position = Double(step) / Double(steps)
                let eased = 1 - pow(1 - position, 3)
                shown = start + (target - start) * eased
            }
        }
    }

    private static func fill(done: Int, total: Int) -> Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    private var fill: Double {
        Self.fill(done: done, total: total)
    }

    private var isCleared: Bool {
        total > 0 && done >= total
    }

    @MainActor
    private static func render(fill: Double, hasTasks: Bool, isCleared: Bool) -> NSImage {
        let renderer = ImageRenderer(
            content: CardGlyph(fill: fill, hasTasks: hasTasks, isCleared: isCleared)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(size: CardGlyph.size(isCleared: isCleared))
        }

        // Only the alpha survives into the menu bar, keeping the mark readable against either a
        // light or a dark bar.
        image.isTemplate = true
        return image
    }
}

/// The drawing itself: a faint full loop as the track and a solid trace for the completed
/// fraction. There is no perpetual runner; completion feedback is brief and event-driven.
private struct CardGlyph: View {
    let fill: Double
    let hasTasks: Bool
    let isCleared: Bool

    private static let trackStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
    private static let progressStroke = StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
    private static let markSize = CGSize(width: 18, height: 14)

    static func size(isCleared: Bool) -> CGSize {
        CGSize(width: isCleared ? 29 : markSize.width, height: 16)
    }

    var body: some View {
        HStack(spacing: 3) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.9, dy: 0.9)
                let loop = PosteightInfinityShape().path(in: rect)

                context.stroke(
                    loop,
                    with: .color(.black.opacity(hasTasks ? 0.30 : 0.62)),
                    style: Self.trackStroke
                )

                if fill > 0.002 {
                    context.stroke(
                        loop.trimmedPath(from: 0, to: fill),
                        with: .color(.black),
                        style: Self.progressStroke
                    )
                }
            }
            .frame(width: Self.markSize.width, height: Self.markSize.height)

            if isCleared {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(height: 16)
    }
}
