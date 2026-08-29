import AppKit
import SwiftUI
import Testing

@testable import Posteight

// The status item is drawn with a face punched out of the card, and a blend mode that erases
// too much leaves an invisible menu bar icon — which no other test would notice, because the
// app still launches and behaves. This renders the glyph and counts the ink.

@MainActor
private func inkCoverage(done: Int, total: Int) throws -> Double {
    let renderer = ImageRenderer(content: MenuBarProgressCard(done: done, total: total, count: max(total - done, 0)))
    renderer.scale = 3

    let image = try #require(renderer.nsImage)
    let data = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))

    var opaque = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
            opaque += 1
        }
    }

    return Double(opaque) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
}

@Suite("Menu bar glyph")
struct MenuBarGlyphTests {
    @Test("The card is visible whether the day is empty, running or cleared", arguments: [
        (0, 0), (1, 3), (3, 3)
    ])
    @MainActor
    func drawsInk(counts: (done: Int, total: Int)) throws {
        let coverage = try inkCoverage(done: counts.done, total: counts.total)
        #expect(coverage > 0.1, "\(counts) 상태에서 글리프가 비어 있음 (coverage \(coverage))")
    }
}
