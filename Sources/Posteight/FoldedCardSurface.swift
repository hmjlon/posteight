import SwiftUI

enum FoldedCardMetrics {
    static let foldSize: CGFloat = 30
    static let cornerRadius: CGFloat = 12
}

struct FoldedCardShape: Shape {
    var foldSize = FoldedCardMetrics.foldSize
    var cornerRadius = FoldedCardMetrics.cornerRadius

    func path(in rect: CGRect) -> Path {
        let fold = min(foldSize, rect.width * 0.28, rect.height * 0.28)
        let radius = min(cornerRadius, rect.width * 0.18, rect.height * 0.18)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct FoldedCardSurface: View {
    let paperColor: Color
    let inkColor: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FoldedCardShape()
                .fill(paperColor)

            PaperGrain()
                .clipShape(FoldedCardShape())

            FoldedCornerShape()
                .fill(paperColor)

            FoldedCornerShape()
                .stroke(inkColor.opacity(0.12), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FoldedCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = min(
            FoldedCardMetrics.foldSize,
            rect.width * 0.28,
            rect.height * 0.28
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.closeSubpath()
        return path
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

/// The status item glyph: the same folded card, filling from the bottom as today's items get
/// done, with a face that reacts to how the day is going. macOS flattens a menu bar label to a
/// template image, so this stays monochrome and carries its meaning in the fill height, the
/// expression and the sparkle alone.
///
/// `MenuBarExtra` only renders `Text` and `Image` in its label — a `Shape` or `Canvas` put there
/// draws nothing at all, and the status item silently comes up with the text beside it and no
/// picture. So the card is drawn once into an `NSImage` and handed over as an `Image`.
// ponytail: renders a frame on demand, no cache. It is a 14x16 raster at 8fps; measure first.
// ponytail: the loop only writes state when something actually changed, which is what keeps a
// still card free. A `TimelineView(.animation)` here instead spins the status item's
// update -> re-render -> update loop at 100% CPU and the app never finishes launching: that
// redraws the label itself forever, where this swaps a picture a few times a second.
struct MenuBarProgressCard: View {
    let done: Int
    let total: Int
    /// The one number written on the card — whichever of remaining or done the user picked.
    let count: Int

    /// The level actually drawn, which walks to `fill` instead of jumping to it.
    @State private var shown: Double
    /// Which of the four wave positions is showing.
    @State private var frame = 0

    private static let fps = 8.0

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

    /// One loop drives both the ink sloshing and the level easing toward a new count. `.task`
    /// cancels it with the view, and a card with nothing left to do writes no state at all, so
    /// SwiftUI stops re-evaluating and the glyph costs nothing until the day changes again.
    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1 / Self.fps))
            guard !Task.isCancelled else { return }

            // The wave only moves while there is something left to do; a cleared or empty day
            // sits still, which reads as "nothing running" and stops burning battery for it.
            if mood == .working {
                frame = (frame + 1) % 4
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

        // Only the alpha survives into the menu bar, which is what makes the punched-out face
        // and the two ink tones readable against either a light or a dark bar.
        image.isTemplate = true
        return image
    }
}

/// The drawing itself. One `Canvas`, with the count — or the face — taken out of the card
/// rather than drawn on top: the glyph is reduced to alpha, so both have to be *absent*.
///
/// A note is a thing you write a number on, so on an ordinary day the card carries the count and
/// nothing else. The face is kept for the two days that have no number worth reading: nothing
/// on the list, and nothing left on it.
private struct CardGlyph: View {
    let fill: Double
    /// 0...3, a quarter turn of the wave apiece.
    let frame: Int
    let mood: CardFace.Mood
    let count: Int

    private static let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
    private static let height: CGFloat = 16

    /// Wide enough for the digits it has to hold, so a busy day does not crop its own count.
    static func size(count: Int, mood: Mood) -> CGSize {
        guard mood == .working else { return CGSize(width: 16, height: height) }
        return CGSize(width: 11 + CGFloat(String(count).count) * 5.5, height: height)
    }

    typealias Mood = CardFace.Mood

    private var size: CGSize { Self.size(count: count, mood: mood) }

    var body: some View {
        HStack(spacing: 1) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let card = FoldedCardShape().path(in: rect)
                let wave = InkWave(
                    level: max(fill, 0.1),
                    phase: Double(frame) * .pi / 2,
                    // A touch deeper than the card body's, or the swell is invisible at 14pt.
                    amplitude: 1.1
                ).path(in: rect)

                // Resolved up front: the drawing below runs twice, and `context` is `inout` so
                // it cannot be reached from inside the closure that does it.
                let numeral = context.resolve(
                    Text(String(count))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                )
                let face = CardFace.path(mood: mood, in: size).strokedPath(Self.stroke)

                // The count on an ordinary day, the face on a day with no number worth reading.
                let mark: (GraphicsContext) -> Void = { canvas in
                    guard mood == .working else {
                        canvas.fill(face, with: .color(.black))
                        return
                    }

                    canvas.draw(
                        numeral,
                        at: CGPoint(x: size.width * 0.5, y: size.height * 0.52),
                        anchor: .center
                    )
                }

                context.fill(card, with: .color(.black.opacity(0.22)))

                // Written in ink first, because a hole punched in the pale part of the card is
                // no darker than the card and would vanish in the menu bar.
                mark(context)

                context.drawLayer { ink in
                    ink.clip(to: card)
                    // A sliver of ink keeps the card readable on a day nothing is done yet.
                    ink.fill(wave, with: .color(.black))
                }

                // Below the waterline the ink has swallowed it, so there the same mark is taken
                // back out — the count reads dark above the line and hollow below it.
                // Erasing straight into what is already drawn is safe here: this is one
                // rasterised canvas, not the SwiftUI layer compositing the status item skips.
                var knockout = context
                knockout.clip(to: wave)
                knockout.blendMode = .destinationOut
                mark(knockout)

                context.stroke(card, with: .color(.black), style: Self.stroke)
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

/// Two eyes and, once the day is cleared, a mouth — as a bare path, because the card punches it
/// out rather than drawing it.
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

/// The filled part of the card, with a small wave along its surface.
private struct InkWave: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat = 0.8

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let surface = rect.maxY - rect.height * level

        path.move(to: CGPoint(x: rect.minX, y: surface))
        for step in 0...Int(rect.width * 2) {
            let x = rect.minX + CGFloat(step) / 2
            let y = surface + amplitude * sin(phase + Double(step) / Double(rect.width * 2) * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
