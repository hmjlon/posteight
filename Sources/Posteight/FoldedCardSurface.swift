import SwiftUI

enum MemoSurfaceMetrics {
    static let cornerRadius: CGFloat = 12
    static let tabBarHeight: CGFloat = 38
    static let activeTabHeight: CGFloat = 32
    static let inactiveTabHeight: CGFloat = 27
    static let maximumTabWidth: CGFloat = 180
    /// Below this, the sticker and its drag handle no longer fit (`showsSticker` needs 54pt) —
    /// so equal division stops shrinking tabs here instead of squeezing them into unreadable
    /// slivers, and the tab strip clips whatever no longer fits rather than distorting it.
    static let minimumTabWidth: CGFloat = 56
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

/// The memo window no longer uses a folded corner; the status item instead traces the "eight" in
/// Posteight's own name lying on its side — the ∞ shape, so the glyph reads as infinite as much
/// as it reads as eight.
private struct InfinityLoopShape: Shape {
    /// The raw curve's lobes only reach ~0.35 of the requested half-height at their tallest; this
    /// scales the y term back out so the loop actually fills the box it is asked to fit.
    private static let lobeCorrection: CGFloat = 2.83

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2

        var path = Path()
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let s = sin(t)
            let c = cos(t)
            let denom = 1 + s * s
            let point = CGPoint(
                x: cx + halfWidth * c / denom,
                y: cy + halfHeight * Self.lobeCorrection * c * s / denom
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// The status item glyph: a figure-eight loop that traces solid as today's items get done, with
/// a short bright segment that keeps travelling the whole loop while anything is left — the same
/// "still running" cue RunCat gives with its cat, run here around the number in the app's own
/// name. A face reacts to how the day is going on the two days there is no count worth reading.
/// macOS flattens a menu bar label to a template image, so this stays monochrome and carries its
/// meaning in the traced fraction, the moving segment and the face alone.
///
/// `MenuBarExtra` only renders `Text` and `Image` in its label — a `Shape` or `Canvas` put there
/// draws nothing at all, and the status item silently comes up with the text beside it and no
/// picture. So the loop is drawn once into an `NSImage` and handed over as an `Image`.
// ponytail: renders a frame on demand, no cache. It is a 14x16 raster at 8fps; measure first.
// ponytail: the loop only writes state when something actually changed, which is what keeps a
// still glyph free. A `TimelineView(.animation)` here instead spins the status item's
// update -> re-render -> update loop at 100% CPU and the app never finishes launching: that
// redraws the label itself forever, where this swaps a picture a few times a second.
struct MenuBarProgressCard: View {
    let done: Int
    let total: Int
    /// The one number written on the loop — whichever of remaining or done the user picked.
    let count: Int

    /// The fraction actually drawn, which walks to `fill` instead of jumping to it.
    @State private var shown: Double
    /// Which lap position the moving segment is at.
    @State private var frame = 0

    private static let fps = 8.0
    private static let runnerSteps = 16

    init(done: Int, total: Int, count: Int) {
        self.done = done
        self.total = total
        self.count = count
        _shown = State(initialValue: Self.fill(done: done, total: total))
    }

    var body: some View {
        Image(nsImage: Self.render(fill: shown, frame: frame, mood: mood, count: count))
            .renderingMode(.template)
            .accessibilityHidden(true)
            .task { await run() }
    }

    /// One loop drives both the runner's motion and the traced fraction easing toward a new
    /// count. `.task` cancels it with the view, and a glyph with nothing left to do writes no
    /// state at all, so SwiftUI stops re-evaluating and it costs nothing until the day changes.
    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1 / Self.fps))
            guard !Task.isCancelled else { return }

            // The runner only moves while there is something left to do; a cleared or empty day
            // sits still, which reads as "nothing running" and stops burning battery for it.
            if mood == .working {
                frame = (frame + 1) % Self.runnerSteps
            }

            let target = fill
            if abs(target - shown) > 0.004 {
                shown += (target - shown) * 0.35
            } else if shown != target {
                shown = target
            }
        }
    }

    private static func fill(done: Int, total: Int) -> Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    private var fill: Double {
        Self.fill(done: done, total: total)
    }

    private var mood: CardFace.Mood {
        guard total > 0 else { return .idle }
        return done >= total ? .cleared : .working
    }

    @MainActor
    private static func render(fill: Double, frame: Int, mood: CardFace.Mood, count: Int) -> NSImage {
        let renderer = ImageRenderer(content: CardGlyph(fill: fill, frame: frame, mood: mood, count: count))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else {
            return NSImage(size: CardGlyph.size(count: count, mood: mood))
        }

        // Only the alpha survives into the menu bar, which is what makes the face and the traced
        // loop readable against either a light or a dark bar.
        image.isTemplate = true
        return image
    }
}

/// The drawing itself: a faint full loop as the track, a solid trace over the completed
/// fraction, and — while there is still work left — a short segment that keeps moving around the
/// whole loop as a "this is still running" cue. The face is kept for the two days that have no
/// number worth reading: nothing on the list, and nothing left on it.
private struct CardGlyph: View {
    let fill: Double
    /// 0..<`runnerSteps`, the moving segment's current position on the loop.
    let frame: Int
    let mood: CardFace.Mood
    let count: Int

    private static let trackStroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
    private static let progressStroke = StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
    private static let height: CGFloat = 16
    private static let runnerSteps = 16
    private static let runnerSpan = 0.06

    /// Wide enough to read as ∞ rather than a squeezed circle, and wide enough for the digits it
    /// has to hold on top of that, so a busy day does not crop its own count.
    static func size(count: Int, mood: Mood) -> CGSize {
        guard mood == .working else { return CGSize(width: 22, height: height) }
        return CGSize(width: 16 + CGFloat(String(count).count) * 5.5, height: height)
    }

    typealias Mood = CardFace.Mood

    private var size: CGSize { Self.size(count: count, mood: mood) }

    var body: some View {
        HStack(spacing: 1) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let loop = InfinityLoopShape().path(in: rect)

                let numeral = context.resolve(
                    Text(String(count))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                )

                context.stroke(loop, with: .color(.black.opacity(0.22)), style: Self.trackStroke)

                if fill > 0.002 {
                    context.stroke(
                        loop.trimmedPath(from: 0, to: fill),
                        with: .color(.black),
                        style: Self.progressStroke
                    )
                }

                if mood == .working {
                    let start = Double(frame % Self.runnerSteps) / Double(Self.runnerSteps)
                    let end = start + Self.runnerSpan
                    if end <= 1 {
                        context.stroke(
                            loop.trimmedPath(from: start, to: end),
                            with: .color(.black),
                            style: Self.progressStroke
                        )
                    } else {
                        context.stroke(
                            loop.trimmedPath(from: start, to: 1),
                            with: .color(.black),
                            style: Self.progressStroke
                        )
                        context.stroke(
                            loop.trimmedPath(from: 0, to: end - 1),
                            with: .color(.black),
                            style: Self.progressStroke
                        )
                    }

                    // The loop's track, progress trace and runner all pass right behind the
                    // count, and stacked together they turn the digits into a smudge. Erasing a
                    // halo to fully transparent first — not just drawing over it — is what keeps
                    // them legible against both a light and dark menu bar.
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
                    let numeralSize = numeral.measure(in: size)
                    let halo = CGRect(
                        x: center.x - numeralSize.width / 2 - 2,
                        y: center.y - numeralSize.height / 2 - 1,
                        width: numeralSize.width + 4,
                        height: numeralSize.height + 2
                    )
                    var eraser = context
                    eraser.blendMode = .clear
                    eraser.fill(Path(roundedRect: halo, cornerRadius: halo.height / 2), with: .color(.black))

                    context.draw(numeral, at: center, anchor: .center)
                } else {
                    context.stroke(CardFace.path(mood: mood, in: size), with: .color(.black), style: Self.trackStroke)
                }
            }
            .frame(width: size.width, height: size.height)

            // The payoff for clearing the day. SF Symbols already draws it, so this is a glyph
            // rather than another Shape to maintain.
            if mood == .cleared {
                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.black)
            }
        }
    }
}

/// Two eyes and, once the day is cleared, a mouth — as a bare path, stroked directly onto the
/// loop rather than filled.
enum CardFace {
    enum Mood {
        /// Nothing on the list yet, so the card is dozing.
        case idle
        case working
        case cleared
    }

    static func path(mood: Mood, in size: CGSize) -> Path {
        var path = Path()
        let eyeY = size.height * 0.44

        for x in [size.width * 0.5 - 2.7, size.width * 0.5 + 2.7] {
            switch mood {
            case .cleared:
                // ^ ^ — the eyes curve up with the smile.
                path.move(to: CGPoint(x: x - 1.7, y: eyeY + 1.1))
                path.addLine(to: CGPoint(x: x, y: eyeY - 1.1))
                path.addLine(to: CGPoint(x: x + 1.7, y: eyeY + 1.1))
            case .idle:
                // - - — closed, because there is nothing to look at.
                path.move(to: CGPoint(x: x - 1.6, y: eyeY))
                path.addLine(to: CGPoint(x: x + 1.6, y: eyeY))
            case .working:
                // A dot: a zero-length line whose round cap makes it circular.
                path.move(to: CGPoint(x: x, y: eyeY))
                path.addLine(to: CGPoint(x: x, y: eyeY))
            }
        }

        guard mood == .cleared else { return path }

        let mouthY = size.height * 0.66
        path.move(to: CGPoint(x: size.width * 0.5 - 2.2, y: mouthY))
        path.addQuadCurve(
            to: CGPoint(x: size.width * 0.5 + 2.2, y: mouthY),
            control: CGPoint(x: size.width * 0.5, y: mouthY + 2.4)
        )

        return path
    }
}
