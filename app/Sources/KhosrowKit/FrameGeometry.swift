import Foundation

/// A pixel rectangle in spritesheet coordinates (origin top-left, +y down).
public struct PixelRect: Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// Pure frame-rectangle math for a tiled sprite sheet.
///
/// The grid is uniform: every frame is `cellWidth x cellHeight`, packed
/// left-to-right within a row, rows stacked top-to-bottom, no padding *between*
/// cells (transparent padding lives *inside* each cell). This deterministic
/// mapping is what the renderer and the frame-coordinate tests both rely on.
public struct FrameGeometry: Equatable {
    public let cols: Int
    public let rows: Int
    public let cellWidth: Int
    public let cellHeight: Int

    public init(cols: Int, rows: Int, cellWidth: Int, cellHeight: Int) {
        self.cols = cols; self.rows = rows
        self.cellWidth = cellWidth; self.cellHeight = cellHeight
    }

    public init(sheet: RuntimeManifest.Sheet) {
        self.init(cols: sheet.cols, rows: sheet.rows,
                  cellWidth: sheet.cellWidth, cellHeight: sheet.cellHeight)
    }

    public var sheetWidth: Int { cols * cellWidth }
    public var sheetHeight: Int { rows * cellHeight }

    /// Rect of the frame at (`row`, `col`). Traps on out-of-range indices so a
    /// bad manifest fails loudly rather than sampling neighbouring frames.
    public func rect(row: Int, col: Int) -> PixelRect {
        precondition(row >= 0 && row < rows, "row \(row) out of range 0..<\(rows)")
        precondition(col >= 0 && col < cols, "col \(col) out of range 0..<\(cols)")
        return PixelRect(x: col * cellWidth, y: row * cellHeight,
                         width: cellWidth, height: cellHeight)
    }

    /// Rect of frame `frameIndex` (0-based) within a clip on `row`.
    public func rect(clipRow row: Int, frameIndex: Int) -> PixelRect {
        rect(row: row, col: frameIndex)
    }

    /// Sequential, row-major cell index (matches the labels on the contact sheet).
    public func sequentialIndex(row: Int, col: Int) -> Int {
        row * cols + col
    }
}
