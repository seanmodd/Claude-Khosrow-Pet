import XCTest
@testable import KhosrowKit

/// Frame-coordinate tests (Phase 4). Verifies the pure pixel-rect math against
/// hand-computed values and the real grid.
final class FrameGeometryTests: XCTestCase {

    private let geo = FrameGeometry(cols: 8, rows: 11, cellWidth: 192, cellHeight: 208)

    func testFirstFrameIsOrigin() {
        XCTAssertEqual(geo.rect(row: 0, col: 0),
                       PixelRect(x: 0, y: 0, width: 192, height: 208))
    }

    func testKnownFrameRects() {
        // row 5 (bow), frame 6 -> x = 6*192 = 1152, y = 5*208 = 1040
        XCTAssertEqual(geo.rect(clipRow: 5, frameIndex: 6),
                       PixelRect(x: 1152, y: 1040, width: 192, height: 208))
        // last row (10), last col (7)
        XCTAssertEqual(geo.rect(row: 10, col: 7),
                       PixelRect(x: 1344, y: 2080, width: 192, height: 208))
    }

    func testSequentialIndexMatchesContactSheet() {
        // Contact sheet labels: #idx = row*cols + col
        XCTAssertEqual(geo.sequentialIndex(row: 0, col: 0), 0)
        XCTAssertEqual(geo.sequentialIndex(row: 5, col: 6), 46)
        XCTAssertEqual(geo.sequentialIndex(row: 10, col: 7), 87)
    }

    func testEveryFrameStaysInsideSheet() {
        for row in 0..<geo.rows {
            for col in 0..<geo.cols {
                let r = geo.rect(row: row, col: col)
                XCTAssertGreaterThanOrEqual(r.x, 0)
                XCTAssertGreaterThanOrEqual(r.y, 0)
                XCTAssertLessThanOrEqual(r.x + r.width, geo.sheetWidth)
                XCTAssertLessThanOrEqual(r.y + r.height, geo.sheetHeight)
            }
        }
    }

    func testFramesAreContiguousWithNoGaps() {
        // Adjacent columns abut exactly (no inter-cell padding).
        let a = geo.rect(row: 2, col: 3)
        let b = geo.rect(row: 2, col: 4)
        XCTAssertEqual(a.x + a.width, b.x)
        // Adjacent rows abut exactly.
        let c = geo.rect(row: 2, col: 0)
        let d = geo.rect(row: 3, col: 0)
        XCTAssertEqual(c.y + c.height, d.y)
    }

    func testGeometryFromManifestSheet() throws {
        let m = try KhosrowResources.loadRuntimeManifest()
        let g = FrameGeometry(sheet: m.sheet)
        XCTAssertEqual(g.sheetWidth, m.sheet.width)
        XCTAssertEqual(g.sheetHeight, m.sheet.height)
        // Each clip's last frame must land inside the sheet.
        for (_, clip) in m.clips {
            let last = g.rect(clipRow: clip.row, frameIndex: clip.frameCount - 1)
            XCTAssertLessThanOrEqual(last.x + last.width, g.sheetWidth)
            XCTAssertLessThanOrEqual(last.y + last.height, g.sheetHeight)
        }
    }
}
