import AppKit
import SwiftUI
import Testing

@testable import Posteight

// A bad template render can leave an invisible menu bar icon — which no other test would notice,
// because the app still launches and behaves. These checks render the actual label and inspect it.

@MainActor
private func renderedBitmap(done: Int, total: Int) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: MenuBarProgressCard(done: done, total: total, count: max(total - done, 0)))
    renderer.scale = 3

    let image = try #require(renderer.nsImage)
    let data = try #require(image.tiffRepresentation)
    return try #require(NSBitmapImageRep(data: data))
}

@MainActor
private func inkCoverage(done: Int, total: Int) throws -> Double {
    let bitmap = try renderedBitmap(done: done, total: total)

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

    @Test("할 일이 없으면 숫자 자리를 남기지 않는다")
    @MainActor
    func hidesCountWhenEmpty() throws {
        let empty = try renderedBitmap(done: 0, total: 0)
        let working = try renderedBitmap(done: 0, total: 3)

        #expect(empty.pixelsWide < working.pixelsWide)
    }

    @Test("모두 완료한 뒤에는 0 대신 완료 표시를 남긴다")
    @MainActor
    func replacesZeroAfterClearing() throws {
        let empty = try renderedBitmap(done: 0, total: 0)
        let cleared = try renderedBitmap(done: 3, total: 3)

        #expect(cleared.pixelsWide > empty.pixelsWide)

        var trailingInk = 0
        let checkmarkStart = Int(Double(cleared.pixelsWide) * 0.68)
        for x in checkmarkStart..<cleared.pixelsWide {
            for y in 0..<cleared.pixelsHigh where (cleared.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                trailingInk += 1
            }
        }
        #expect(trailingInk > 0, "완료 이미지의 체크 표시 영역이 비어 있음")
    }
}
