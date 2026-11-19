import Foundation

// Iridescent glass: a long curved petal of thin glass with several more petals
// fanned out behind it, coloured the way a soap film or oil on water is.
//
// Glass has to be smooth, which dots cannot be, so the petals are drawn as a
// fine mesh of triangles straight into the engine's light buffer (the graphics
// chip draws the same triangles when it is in use). The usual dots trace the
// petals' rims, so changes to and from other patterns still have something to
// gather from and scatter into.

let prismSheets = 7
let prismNU = 72, prismNV = 20
let prismVertexCount = prismSheets * prismNU * prismNV * 6

/// One corner of a triangle: where it is in the picture and how much light it gives.
struct PrismVertex {
    var x: Float, y: Float
    var r: Float, g: Float, b: Float, a: Float = 0
}

/// What makes one petal different from the next: its width, length, where it
/// is widest, how deeply it is cupped, how wavy its outline is, and how much it
/// twists and bends. The front petal keeps the plain shape.
struct PrismShape {
    var width: Float = 1, len: Float = 1, lean: Float = 0.5, skew: Float = 1, power: Float = 0.7
    var cup: Float = 1, rip: Float = 0, ripF: Float = 0, ph: Float = 0
    var twist: Float = 1, bend: Float = 1, shift: Float = 0
}

let prismShapes: [PrismShape] = (0..<prismSheets).map { k in
    if k == 0 { return PrismShape() }
    func h(_ n: Int) -> Float { hashU(UInt32(k * 37 + n) &* 0x9E37_79B1 &+ 0x51ED_270B) }
    var p = PrismShape()
    p.width = 0.55 + 0.85 * h(1)
    p.len = 0.72 + 0.42 * h(2)
    p.lean = 0.15 + 0.75 * h(3)
    p.skew = 0.6 + 1.1 * h(4)
    p.power = 0.45 + 0.9 * h(5)
    p.cup = (h(6) < 0.3 ? -1 : 1) * (0.4 + 1.1 * h(7))
    p.rip = h(8) < 0.55 ? 0.10 + 0.22 * h(9) : 0
    p.ripF = 5 + 9 * h(10)
    p.ph = TAU * h(11)
    p.twist = 0.5 + 1.1 * h(12)
    p.bend = 0.55 + 0.9 * h(13)
    p.shift = (h(14) - 0.35) * 0.5
    return p
}

/// A point on petal k: u runs along it (0 to 1), v across it (-1 to 1).
@inline(__always) func prismPoint(_ u: Float, _ v: Float, _ k: Float, _ t: Float) -> (Float, Float, Float) {
    let sh = prismShapes[min(max(Int(k), 0), prismSheets - 1)]
    let uc = clamp01(u)
    let su = max(sinf(Float.pi * uc), 0)
    let prof = powf(max(sinf(Float.pi * powf(uc, sh.skew)), 0), sh.power)
    // Each petal's outline and proportions drift slowly, at its own pace.
    let ripple = 1 + sh.rip * sinf(sh.ripF * u + sh.ph + t * 0.16)
    let breathe = 1 + 0.12 * sinf(t * 0.06 + sh.ph * 1.7)
    let w = 0.46 * prof * (sh.lean + (1 - sh.lean) * u) * sh.width * ripple * breathe
    let cup = sh.cup * (0.75 + 0.3 * sinf(t * 0.11 + sh.ph))
    let x = 1.9 * sh.len * (u - 0.5) + sh.shift * u * u
    var y = w * v
    var z = cup * w * (1 - v * v) + 0.10 * sinf(u * 5 + t * 0.17 + sh.ph) * su
    // Twisted along its length; the petals behind fan out towards the far end.
    let fan = (0.27 + 0.08 * sinf(t * 0.07)) * k * u * sqrtf(max(u, 0))
    let a = (1.5 + 0.5 * sinf(t * 0.05 + sh.ph)) * sh.twist * (u - 0.5) + fan
    let c = cosf(a), s = sinf(a)
    let ry = y * c - z * s
    z = y * s + z * c
    y = ry
    // Bent like a bow.
    let b = (0.55 + 0.15 * sinf(t * 0.09 + sh.ph)) * sh.bend
    let e = 2 * u - 1
    y += b * (0.4 - e * e)
    return (x, y, z)
}

/// How the whole thing is turned in space at time t: slowly swaying, lying on a slant.
struct PrismTurn {
    let cy: Float, sy: Float, cp: Float, sp: Float, cr: Float, sr: Float
    init(_ t: Float) {
        let yaw = 0.6 * sinf(t * 0.05), pitch = 0.45 + 0.3 * sinf(t * 0.037), roll = 0.45 + 0.25 * sinf(t * 0.03)
        cy = cosf(yaw); sy = sinf(yaw); cp = cosf(pitch); sp = sinf(pitch); cr = cosf(roll); sr = sinf(roll)
    }
    @inline(__always) func apply(_ p: (Float, Float, Float)) -> (Float, Float, Float) {
        let x1 = p.0 * cy + p.2 * sy, z1 = -p.0 * sy + p.2 * cy
        let y2 = p.1 * cp - z1 * sp, z2 = p.1 * sp + z1 * cp
        return (x1 * cr - y2 * sr, x1 * sr + y2 * cr, z2)
    }
}

/// The colours of a thin film, going round as the film gets thicker.
@inline(__always) func prismPalette(_ p: Float) -> (Float, Float, Float) {
    let f = fract(p) * 7
    let i = Int(f) % 7
    let a = smooth(f - floorf(f))
    @inline(__always) func stop(_ n: Int) -> (Float, Float, Float) {
        switch n % 7 {
        case 0: return (1.00, 0.60, 0.08)  // amber
        case 1: return (1.00, 0.22, 0.02)  // orange-red
        case 2: return (1.00, 0.04, 0.42)  // magenta
        case 3: return (0.45, 0.06, 1.00)  // violet
        case 4: return (0.02, 0.22, 1.00)  // blue
        case 5: return (0.00, 0.85, 0.95)  // cyan
        default: return (1.00, 0.82, 0.50) // warm cream
        }
    }
    let c0 = stop(i), c1 = stop(i + 1)
    return (mixf(c0.0, c1.0, a), mixf(c0.1, c1.1, a), mixf(c0.2, c1.2, a))
}

/// Works out this frame's triangles. `amount` is how much of the picture this
/// pattern owns and `hold` scales each frame's light so brightness stays steady
/// as trails fade. Returns how many corners were written.
func prismMesh(_ W: Int, _ H: Int, t: Float, amount: Float, hold: Float,
               into out: UnsafeMutablePointer<PrismVertex>, capacity: Int) -> Int {
    let nu = prismNU + 1, nv = prismNV + 1
    let turn = PrismTurn(t)
    let camD: Float = 3.4
    let halfH = Float(H) * 0.5, cx = Float(W) * 0.5, cyp = Float(H) * 0.5
    let level = amount * hold
    var pos = [SIMD3<Float>](repeating: .zero, count: nu * nv)
    var grid = [PrismVertex](repeating: PrismVertex(x: 0, y: 0, r: 0, g: 0, b: 0), count: nu * nv)
    var n = 0
    for ki in 0..<prismSheets {
        let k = Float(ki)
        for iu in 0..<nu {
            // Corners crowd a little towards the two tips, where the petal narrows fast.
            let fu = Float(iu) / Float(prismNU)
            let u = 0.5 - 0.5 * cosf(Float.pi * fu) * 0.999
            for iv in 0..<nv {
                let v = 2 * Float(iv) / Float(prismNV) - 1
                let p = turn.apply(prismPoint(u, v, k, t))
                pos[iu * nv + iv] = SIMD3(p.0, p.1, p.2)
            }
        }
        for iu in 0..<nu {
            let fu = Float(iu) / Float(prismNU)
            let u = 0.5 - 0.5 * cosf(Float.pi * fu) * 0.999
            for iv in 0..<nv {
                let v = 2 * Float(iv) / Float(prismNV) - 1
                let p = pos[iu * nv + iv]
                let du = pos[min(iu + 1, nu - 1) * nv + iv] - pos[max(iu - 1, 0) * nv + iv]
                let dv = pos[iu * nv + min(iv + 1, nv - 1)] - pos[iu * nv + max(iv - 1, 0)]
                let cxn = du.y * dv.z - du.z * dv.y, cyn = du.z * dv.x - du.x * dv.z, czn = du.x * dv.y - du.y * dv.x
                let len = sqrtf(cxn * cxn + cyn * cyn + czn * czn)
                let facing = len > 1e-9 ? fabsf(czn) / len : 1
                // Film colour: changes with the angle it is seen from, along the petal, and from petal to petal.
                let phase = 0.55 * (1 - facing) + 0.30 * u + 0.035 * k + 0.06 * v * v + t * 0.012
                let c = prismPalette(phase)
                // Broad soft pools of light drifting over the glass; the rest stays clear and dark.
                let wave = sinf(4.2 * u - 1.6 * v + 0.9 * k + t * 0.21) * cosf(1.3 * v + 0.6 * k - t * 0.13)
                let pool = smooth(0.5 + 0.75 * wave)
                let graze = (1 - facing) * (1 - facing)
                let edge = v * v * v * v
                let l = (0.012 + 0.34 * pool * pool * pool + 0.14 * graze + 0.10 * edge * edge) * powf(0.86, k) * level
                let dz = max(camD - p.z, 0.4)
                let ps = camD / dz
                grid[iu * nv + iv] = PrismVertex(x: cx + p.x * ps * halfH, y: cyp + p.y * ps * halfH,
                                                 r: c.0 * l, g: c.1 * l, b: c.2 * l)
            }
        }
        for iu in 0..<prismNU {
            for iv in 0..<prismNV {
                if n + 6 > capacity { return n }
                let a = grid[iu * nv + iv], b = grid[(iu + 1) * nv + iv]
                let c = grid[(iu + 1) * nv + iv + 1], d = grid[iu * nv + iv + 1]
                out[n] = a; out[n + 1] = b; out[n + 2] = c
                out[n + 3] = a; out[n + 4] = c; out[n + 5] = d
                n += 6
            }
        }
    }
    return n
}

/// Adds the triangles' light to the light buffer (the built-in drawing, used when
/// the graphics chip is not). Every pixel belongs to exactly one of two
/// triangles that share an edge, so no seams show.
func rasterPrism(_ acc: UnsafeMutablePointer<Float>, _ W: Int, _ H: Int,
                 _ v: UnsafePointer<PrismVertex>, _ count: Int, threads: Int) {
    if count < 3 { return }
    let workers = max(1, min(threads, 16))
    let band = (H + workers - 1) / workers
    DispatchQueue.concurrentPerform(iterations: workers) { wk in
        // Each thread owns a strip of rows, so no two ever write the same pixel.
        let rowLo = wk * band, rowHi = min(H, rowLo + band) - 1
        if rowLo > rowHi { return }
        var i = 0
        while i + 2 < count {
            let a = v[i]
            var b = v[i + 1], c = v[i + 2]
            i += 3
            let lim: Float = 30000
            if !(fabsf(a.x) < lim && fabsf(a.y) < lim && fabsf(b.x) < lim && fabsf(b.y) < lim
                 && fabsf(c.x) < lim && fabsf(c.y) < lim) { continue }
            // Positions in sixteenths of a pixel, as whole numbers, so edges are exact.
            let x0 = Int((a.x * 16).rounded()), y0 = Int((a.y * 16).rounded())
            var x1 = Int((b.x * 16).rounded()), y1 = Int((b.y * 16).rounded())
            var x2 = Int((c.x * 16).rounded()), y2 = Int((c.y * 16).rounded())
            var area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if area == 0 { continue }
            if area < 0 { swap(&b, &c); swap(&x1, &x2); swap(&y1, &y2); area = -area }
            let yLo = max(rowLo, min(y0, y1, y2) >> 4), yHi = min(rowHi, (max(y0, y1, y2) + 15) >> 4)
            if yLo > yHi { continue }
            let xLo = max(0, min(x0, x1, x2) >> 4), xHi = min(W - 1, (max(x0, x1, x2) + 15) >> 4)
            if xLo > xHi { continue }
            @inline(__always) func bias(_ dx: Int, _ dy: Int) -> Int { (dy > 0 || (dy == 0 && dx < 0)) ? 0 : -1 }
            let b0 = bias(x2 - x1, y2 - y1), b1 = bias(x0 - x2, y0 - y2), b2 = bias(x1 - x0, y1 - y0)
            let inv = 1 / Float(area)
            for y in yLo...yHi {
                let py = y * 16 + 8
                var o = (y * W + xLo) * 3
                for x in xLo...xHi {
                    let px = x * 16 + 8
                    let w0 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)
                    let w1 = (x0 - x2) * (py - y2) - (y0 - y2) * (px - x2)
                    let w2 = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0)
                    if w0 + b0 >= 0 && w1 + b1 >= 0 && w2 + b2 >= 0 {
                        let f0 = Float(w0) * inv, f1 = Float(w1) * inv, f2 = Float(w2) * inv
                        acc[o] += a.r * f0 + b.r * f1 + c.r * f2
                        acc[o + 1] += a.g * f0 + b.g * f1 + c.g * f2
                        acc[o + 2] += a.b * f0 + b.b * f1 + c.b * f2
                    }
                    o += 3
                }
            }
        }
    }
}

/// The ordinary dots: most run along the petals' rims as fine bright lines, the
/// rest are a faint shimmer on the glass.
func prism(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let k = Float(min(Int(s3 * Float(prismSheets)), prismSheets - 1))
    let rim = s4 < 0.6
    let u = 0.004 + 0.992 * s1
    let v: Float = rim ? (s2 < 0.5 ? -1 : 1) : 2 * s2 - 1
    let h: Float = 0.01
    let turn = PrismTurn(t)
    let p = turn.apply(prismPoint(u, v, k, t))
    let pu = turn.apply(prismPoint(u + h, v, k, t))
    let pv = turn.apply(prismPoint(u, v - (v > 0 ? h : -h), k, t))
    let ax = (pu.0 - p.0) / h, ay = (pu.1 - p.1) / h, az = (pu.2 - p.2) / h
    let bx = (pv.0 - p.0) / h, by = (pv.1 - p.1) / h, bz = (pv.2 - p.2) / h
    let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx
    let area = sqrtf(nx * nx + ny * ny + nz * nz)
    let facing = fabsf(nz) / max(area, 1e-5)
    let phase = 0.55 * (1 - facing) + 0.30 * u + 0.035 * k + 0.06 * v * v + t * 0.012
    var c = prismPalette(phase)
    if rim {
        let l = 0.007 * sqrtf(ax * ax + ay * ay + az * az) * (1.1 - 0.1 * k)
        c = (mixf(c.0, 1, 0.2), mixf(c.1, 1, 0.2), mixf(c.2, 1, 0.2))
        return Sample(x: p.0, y: p.1, z: p.2, r: c.0 * l, g: c.1 * l, b: c.2 * l)
    }
    let l = area * 0.008
    return Sample(x: p.0, y: p.1, z: p.2, r: c.0 * l, g: c.1 * l, b: c.2 * l)
}
