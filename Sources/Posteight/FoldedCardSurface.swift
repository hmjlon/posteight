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
