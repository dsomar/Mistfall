import Foundation

// Cipherfall: a cascade of green characters falling down the screen, drawn the
// way an old dot-matrix display would show them. Every character is a 5 x 7
// grid of round dots; the head of each falling stream is almost white and the
// characters behind it fade away as they are left behind.
//
// This layer is drawn straight into the engine's light buffer (on top of a
// faint green drizzle made by the usual dots), so it shares the same glow and
// soft fading as every other pattern.

/// 5 x 7 dot characters: seven rows each, five bits per row (bit 4 is the left dot).
let cipherGlyphs: [[UInt8]] = [
    [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],  // 0
    [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],  // 1
    [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],  // 2
    [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],  // 3
    [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],  // 4
    [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],  // 5
    [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],  // 6
    [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],  // 7
    [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],  // 8
    [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],  // 9
    [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],  // A
    [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],  // B
    [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],  // C
    [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],  // D
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],  // E
    [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],  // F
    [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],  // G
    [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],  // H
    [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],  // K
    [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],  // M
    [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],  // N
    [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],  // P
    [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],  // R
    [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],  // S
    [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],  // T
    [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],  // V
    [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],  // X
    [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],  // Y
    [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],  // Z
    [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],  // +
    [0x00, 0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00],  // =
    [0x00, 0x04, 0x15, 0x0E, 0x15, 0x04, 0x00],  // *
    [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],  // :
    [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02],  // <
    [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A],  // #
    [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],  // %
    [0x1F, 0x01, 0x05, 0x06, 0x04, 0x04, 0x08],  // kana
    [0x01, 0x02, 0x04, 0x0C, 0x14, 0x04, 0x04],  // kana
    [0x04, 0x1F, 0x11, 0x11, 0x01, 0x02, 0x04],  // kana
    [0x00, 0x1F, 0x04, 0x04, 0x04, 0x04, 0x1F],  // kana
    [0x02, 0x1F, 0x02, 0x06, 0x0A, 0x12, 0x02],  // kana
    [0x08, 0x1F, 0x09, 0x09, 0x09, 0x09, 0x12],  // kana
    [0x04, 0x1F, 0x04, 0x1F, 0x04, 0x04, 0x04],  // kana
    [0x0F, 0x09, 0x11, 0x01, 0x02, 0x04, 0x08],  // kana
    [0x08, 0x0F, 0x12, 0x02, 0x02, 0x02, 0x04],  // kana
    [0x00, 0x1F, 0x01, 0x01, 0x01, 0x01, 0x1F],  // kana
    [0x0A, 0x1F, 0x0A, 0x0A, 0x02, 0x04, 0x08],  // kana
    [0x00, 0x18, 0x01, 0x19, 0x01, 0x02, 0x1C],  // kana
    [0x00, 0x1F, 0x01, 0x02, 0x04, 0x0A, 0x11],  // kana
    [0x08, 0x1F, 0x09, 0x0A, 0x08, 0x08, 0x07],  // kana
    [0x00, 0x11, 0x11, 0x09, 0x01, 0x02, 0x0C],  // kana
    [0x0F, 0x09, 0x15, 0x03, 0x02, 0x04, 0x08],  // kana
    [0x02, 0x1C, 0x04, 0x1F, 0x04, 0x04, 0x08],  // kana
    [0x00, 0x15, 0x15, 0x15, 0x01, 0x02, 0x04],  // kana
    [0x0E, 0x00, 0x1F, 0x04, 0x04, 0x04, 0x08],  // kana
    [0x08, 0x08, 0x08, 0x0C, 0x0A, 0x08, 0x08],  // kana
    [0x04, 0x04, 0x1F, 0x04, 0x04, 0x08, 0x10],  // kana
    [0x00, 0x0E, 0x00, 0x00, 0x00, 0x00, 0x1F],  // kana
    [0x00, 0x1F, 0x01, 0x0A, 0x04, 0x0A, 0x10],  // kana
    [0x04, 0x1F, 0x02, 0x04, 0x0E, 0x15, 0x04],  // kana
    [0x02, 0x02, 0x02, 0x04, 0x04, 0x08, 0x10],  // kana
    [0x00, 0x0A, 0x09, 0x11, 0x11, 0x11, 0x00],  // kana
    [0x10, 0x10, 0x1F, 0x10, 0x10, 0x10, 0x0F],  // kana
    [0x00, 0x1F, 0x01, 0x01, 0x01, 0x02, 0x0C],  // kana
    [0x00, 0x08, 0x14, 0x02, 0x01, 0x01, 0x00],  // kana
    [0x04, 0x1F, 0x04, 0x04, 0x15, 0x15, 0x04],  // kana
    [0x00, 0x1F, 0x01, 0x01, 0x0A, 0x04, 0x02],  // kana
    [0x0E, 0x00, 0x0E, 0x00, 0x0E, 0x00, 0x01],  // kana
    [0x04, 0x04, 0x08, 0x08, 0x12, 0x11, 0x1F],  // kana
    [0x01, 0x01, 0x0A, 0x04, 0x0A, 0x10, 0x00],  // kana
    [0x0E, 0x04, 0x1F, 0x04, 0x04, 0x04, 0x03],  // kana
    [0x08, 0x1F, 0x09, 0x0A, 0x08, 0x08, 0x08],  // kana
    [0x00, 0x0E, 0x02, 0x02, 0x02, 0x02, 0x1F],  // kana
    [0x1F, 0x01, 0x01, 0x1F, 0x01, 0x01, 0x1F],  // kana
    [0x0E, 0x00, 0x1F, 0x01, 0x01, 0x02, 0x0C],  // kana
    [0x12, 0x12, 0x12, 0x12, 0x02, 0x04, 0x08],  // kana
    [0x04, 0x14, 0x14, 0x14, 0x15, 0x15, 0x16],  // kana
    [0x10, 0x10, 0x10, 0x10, 0x11, 0x12, 0x1C],  // kana
    [0x00, 0x1F, 0x11, 0x11, 0x11, 0x11, 0x1F],  // kana
    [0x1F, 0x11, 0x11, 0x01, 0x01, 0x02, 0x04],  // kana
    [0x1F, 0x01, 0x1F, 0x01, 0x01, 0x02, 0x04],  // kana
    [0x00, 0x18, 0x00, 0x01, 0x01, 0x02, 0x1C],  // kana
]
/// The first glyphs are digits and capitals; half of all cells show the later symbol shapes.
let cipherLatinCount = 36

@inline(__always) func cipherHash(_ a: Int, _ b: Int, _ c: Int) -> UInt32 {
    var h = UInt32(truncatingIfNeeded: a &* 73_856_093) ^ UInt32(truncatingIfNeeded: b &* 19_349_663)
        ^ UInt32(truncatingIfNeeded: c &* 83_492_791)
    h ^= h >> 15; h = h &* 0x85EB_CA77; h ^= h >> 13; h = h &* 0xC2B2_AE3D; h ^= h >> 16
    return h
}
@inline(__always) func cipherUnit(_ a: Int, _ b: Int, _ c: Int) -> Float {
    Float(cipherHash(a, b, c) & 0xFF_FFFF) / Float(0x100_0000)
}

/// The grid of character cells for a picture of this size.
struct CipherGrid {
    /// Dots are this far apart (in pixels); a cell is 6 dots wide and 9 tall.
    let pitch: Float
    let cols: Int
    let rows: Int
    let left: Float     // x of the first cell's left edge
    let top: Float      // y (up) of the first row's top edge
    static let cellDotsX: Float = 6
    static let cellDotsY: Float = 9
    /// How many rows of characters fill the screen: more rows, smaller characters.
    static let targetRows: Float = 40

    init(width: Int, height: Int) {
        // About 40 rows of characters whatever the size of the screen.
        pitch = max(Float(height) / (CipherGrid.targetRows * CipherGrid.cellDotsY), 2.2)
        let cw = pitch * CipherGrid.cellDotsX, ch = pitch * CipherGrid.cellDotsY
        cols = max(Int(ceilf(Float(width) / cw)), 1)
        rows = max(Int(ceilf(Float(height) / ch)) + 1, 1)
        left = (Float(width) - Float(cols) * cw) * 0.5
        top = Float(height) + (Float(rows) * ch - Float(height)) * 0.5
    }
}

/// How bright the cell (col, row) is at time t (0 = dark), and whether it is the
/// white head of a stream. Each column carries two streams at different speeds.
@inline(__always)
func cipherLight(col: Int, row: Int, rows: Int, t: Float) -> (light: Float, head: Float) {
    var light: Float = 0, head: Float = 0
    for s in 0..<2 {
        let speed = 5.5 + 9 * cipherUnit(col, s, 11)                 // rows per second
        let tail = 7 + 16 * cipherUnit(col, s, 23)                    // rows long
        let gap = 4 + 22 * cipherUnit(col, s, 37)
        let span = Float(rows) + tail + gap
        let pos = fract((t * speed + cipherUnit(col, s, 51) * span * 3) / span) * span
        let d = pos - Float(row)                                      // rows behind the head
        if d < -0.5 || d > tail { continue }
        let k = clamp01(1 - d / tail)
        let l = d < 0 ? (d + 0.5) * 2 : k * k * (0.35 + 0.65 * k)
        if l > light { light = l }
        let hd = clamp01(1 - fabsf(d) * 1.1)
        if hd > head { head = hd }
    }
    return (light, head)
}

/// Draws the falling characters into the light buffer. `amount` is how much of
/// the picture this pattern owns (it fades in and out with pattern changes) and
/// `hold` scales each frame's light so brightness stays steady as trails fade.
func drawCipherfall(_ acc: UnsafeMutablePointer<Float>, _ W: Int, _ H: Int,
                    t: Float, amount: Float, hold: Float, threads: Int) {
    if amount <= 0.002 { return }
    let grid = CipherGrid(width: W, height: H)
    let pitch = grid.pitch
    let rad = max(pitch * 0.46, 0.9)
    let ir = Int(ceilf(rad))
    let invR2 = 1 / (rad * rad)
    let level = amount * hold * 2.6
    let glyphCount = cipherGlyphs.count
    let workers = max(1, min(threads, grid.cols))
    cipherGlyphs.withUnsafeBufferPointer { table in
        DispatchQueue.concurrentPerform(iterations: workers) { wkr in
            var col = wkr
            while col < grid.cols {
                defer { col += workers }
                let x0 = grid.left + (Float(col) * CipherGrid.cellDotsX + 1) * pitch
                // Columns are whole strips of pixels, so threads never share a pixel
                // as long as the strips do not overlap: keep every dot inside its cell.
                for row in 0..<grid.rows {
                    let (light, head) = cipherLight(col: col, row: row, rows: grid.rows, t: t)
                    if light <= 0.004 { continue }
                    // Each cell swaps its character now and then, faster near the head.
                    let ru = cipherUnit(col, row, 5)
                    let rate = 0.12 + 1.3 * ru * ru + 1.6 * head
                    let tick = Int(floorf(t * rate + cipherUnit(col, row, 9) * 64))
                    let pick = cipherHash(col, row, tick)
                    let symbol = (pick >> 8) & 1 == 0
                    let gi = symbol ? cipherLatinCount + Int((pick >> 12) % UInt32(glyphCount - cipherLatinCount))
                                    : Int((pick >> 12) % UInt32(cipherLatinCount))
                    let mirror = (pick >> 9) & 3 == 0
                    let glyph = table[gi]
                    let flick = 0.8 + 0.2 * cipherUnit(col, row, tick &+ 3)
                    let on = level * light * flick
                    // Head: nearly white. Tail: phosphor green, deeper as it dims.
                    let r = on * (0.10 + 0.80 * head)
                    let g = on * (0.75 + 0.30 * head)
                    let b = on * (0.22 + 0.62 * head)
                    // The dots that are "off" still show faintly: the dot-matrix texture.
                    let off = level * light * 0.055
                    let yTop = grid.top - (Float(row) * CipherGrid.cellDotsY + 1) * pitch
                    for gy in 0..<7 {
                        let bits = glyph[gy]
                        let cy = yTop - Float(gy) * pitch
                        let iy = Int(cy)
                        if iy - ir < 0 || iy + ir >= H { continue }
                        for gx in 0..<5 {
                            let bit = mirror ? gx : 4 - gx
                            let lit = (bits >> UInt8(bit)) & 1 == 1
                            let cx = x0 + Float(gx) * pitch
                            let ix = Int(cx)
                            if ix - ir < 0 || ix + ir >= W { continue }
                            let pr = lit ? r : 0.04 * off, pg = lit ? g : off, pb = lit ? b : 0.25 * off
                            for yy in -ir...ir {
                                for xx in -ir...ir {
                                    let ddx = Float(ix + xx) + 0.5 - cx, ddy = Float(iy + yy) + 0.5 - cy
                                    let wgt = 1 - (ddx * ddx + ddy * ddy) * invR2
                                    if wgt <= 0 { continue }
                                    // A round dot with a soft edge and a flat bright middle.
                                    let q = min(wgt * 2.2, 1)
                                    let p = ((iy + yy) * W + ix + xx) * 3
                                    acc[p] += pr * q; acc[p + 1] += pg * q; acc[p + 2] += pb * q
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The same falling characters for the graphics chip: one entry per lit cell,
/// which draws its own 5 x 7 block of dots.
func emitCipherfall(_ gpu: GPURenderer, _ W: Int, _ H: Int, t: Float, amount: Float, hold: Float) {
    if amount <= 0.002 { return }
    let grid = CipherGrid(width: W, height: H)
    let pitch = grid.pitch
    let rad = max(pitch * 0.46, 0.9)
    gpu.cellPitch = pitch
    gpu.cellInvR2 = 1 / (rad * rad)
    let level = amount * hold * 2.6
    let glyphCount = cipherGlyphs.count
    for col in 0..<grid.cols {
        let x0 = grid.left + (Float(col) * CipherGrid.cellDotsX + 1) * pitch
        for row in 0..<grid.rows {
            let (light, head) = cipherLight(col: col, row: row, rows: grid.rows, t: t)
            if light <= 0.004 { continue }
            let ru = cipherUnit(col, row, 5)
            let rate = 0.12 + 1.3 * ru * ru + 1.6 * head
            let tick = Int(floorf(t * rate + cipherUnit(col, row, 9) * 64))
            let pick = cipherHash(col, row, tick)
            let symbol = (pick >> 8) & 1 == 0
            let gi = symbol ? cipherLatinCount + Int((pick >> 12) % UInt32(glyphCount - cipherLatinCount))
                            : Int((pick >> 12) % UInt32(cipherLatinCount))
            let mirror = (pick >> 9) & 3 == 0
            let glyph = cipherGlyphs[gi]
            let flick = 0.8 + 0.2 * cipherUnit(col, row, tick &+ 3)
            let on = level * light * flick
            var lo: UInt32 = 0
            for gy in 0..<6 { lo |= UInt32(glyph[gy] & 31) << UInt32(gy * 5) }
            gpu.addCell(GPUCell(x0: x0, yTop: grid.top - (Float(row) * CipherGrid.cellDotsY + 1) * pitch,
                                off: level * light * 0.055, mirror: mirror ? 1 : 0,
                                r: on * (0.10 + 0.80 * head), g: on * (0.75 + 0.30 * head), b: on * (0.22 + 0.62 * head),
                                lo: lo, hi: UInt32(glyph[6] & 31)))
        }
    }
}

/// The ordinary dots under the characters: a thin green drizzle that falls down
/// the same columns, snapped to the dot grid, so changes to and from the other
/// patterns still have something to gather from and scatter into.
func cipherfall(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    let colCount = floorf(aspect * CipherGrid.targetRows * 1.5)
    let c = floorf(s2 * colCount)
    let sub = floorf(s3 * 5)
    let x = ((c + 0.5) / colCount * 2 - 1) * aspect + (sub - 2) * (2 * aspect / colCount / 6)
    let speed = 0.25 + 0.5 * hash1(c + 3)
    let u = fract(s1 + t * speed)
    let yRaw = 1.08 - u * 2.16
    let ySteps = CipherGrid.targetRows * 4.5
    let y = floorf(yRaw * ySteps) / ySteps
    let k = 0.07 * (0.3 + 0.7 * s4) * smooth(u * 8) * smooth((1 - u) * 8)
    return Sample(x: x, y: y, z: 0, r: 0.08 * k, g: 1.0 * k, b: 0.3 * k)
}
