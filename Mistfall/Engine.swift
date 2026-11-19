import Foundation
import CoreGraphics

// Mistfall particle engine: tens of thousands of glowing dots that follow
// slowly changing formations (orb, light ribbons, fountain, aurora, waterfall
// mist, knot). Light is accumulated additively in a float buffer that fades a
// little every frame (so moving dots leave soft trails), then a blurred copy is
// added for glow and the result is tone-mapped to an image.

let TAU: Float = 6.2831853

@inline(__always) func fract(_ x: Float) -> Float { x - floorf(x) }
@inline(__always) func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
@inline(__always) func smooth(_ x: Float) -> Float { let c = clamp01(x); return c * c * (3 - 2 * c) }
@inline(__always) func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Vivid rainbow colour; `h` in turns (0...1 wraps).
@inline(__always) func rainbow(_ h: Float) -> (Float, Float, Float) {
    let a = TAU * h
    var r = 0.5 + 0.5 * cosf(a)
    var g = 0.5 + 0.5 * cosf(a - TAU / 3)
    var b = 0.5 + 0.5 * cosf(a - 2 * TAU / 3)
    r = r * r * 1.15; g = g * g * 1.15; b = b * b * 1.15
    return (r, g, b)
}

enum Pattern: Int, CaseIterable {
    case orb, veil, fountain, aurora, waterfall, knot, murmuration, rings
    case network, globe, lattice, tunnel, mesh, nebula, cipherfall, currents, kaleidoscope, prism

    var title: String {
        switch self {
        case .orb: return "Glowing orb"
        case .veil: return "Light ribbons"
        case .fountain: return "Fountain"
        case .aurora: return "Northern lights"
        case .waterfall: return "Waterfall mist"
        case .knot: return "Light knot"
        case .murmuration: return "Murmuration"
        case .rings: return "Pulsing rings"
        case .network: return "Neural network"
        case .globe: return "Network globe"
        case .lattice: return "Data sphere"
        case .tunnel: return "Data tunnel"
        case .mesh: return "Wave mesh"
        case .nebula: return "Nebula"
        case .cipherfall: return "Cipherfall"
        case .currents: return "Currents"
        case .kaleidoscope: return "Kaleidoscope"
        case .prism: return "Iridescent glass"
        }
    }

    static func named(_ s: String) -> Pattern? {
        switch s.lowercased() {
        case "orb", "sphere": return .orb
        case "veil", "ribbon", "ribbons": return .veil
        case "fountain": return .fountain
        case "aurora", "lights": return .aurora
        case "waterfall", "mist": return .waterfall
        case "knot": return .knot
        case "murmuration", "flock", "starlings": return .murmuration
        case "rings", "pulse", "ripples": return .rings
        case "network", "neural", "plexus": return .network
        case "globe", "planet": return .globe
        case "lattice", "data", "datasphere": return .lattice
        case "tunnel": return .tunnel
        case "mesh", "waves", "wave": return .mesh
        case "nebula", "galaxy": return .nebula
        case "cipherfall", "cipher", "code", "rain": return .cipherfall
        case "currents", "flow", "drift": return .currents
        case "kaleidoscope", "kaleido", "reflections": return .kaleidoscope
        case "prism", "glass", "iridescent": return .prism
        default: return Int(s).flatMap { Pattern(rawValue: $0) }
        }
    }

    /// Trail persistence per 1/60 s, light per dot and glow amount.
    var look: (fade: Float, gain: Float, glow: Float) {
        switch self {
        case .orb: return (0.82, 1.1, 1.7)
        case .veil: return (0.90, 0.5, 1.3)
        case .fountain: return (0.86, 0.8, 1.2)
        case .aurora: return (0.92, 1.6, 1.4)
        case .waterfall: return (0.86, 0.9, 1.3)
        case .knot: return (0.86, 1.1, 1.0)
        case .murmuration: return (0.84, 0.75, 1.3)
        case .rings: return (0.85, 1.0, 1.4)
        case .network: return (0.80, 0.45, 0.55)
        case .globe: return (0.80, 0.5, 0.5)
        case .lattice: return (0.72, 0.9, 0.35)
        case .tunnel: return (0.84, 0.9, 0.55)
        case .mesh: return (0.76, 0.8, 0.4)
        case .nebula: return (0.82, 0.9, 0.7)
        case .cipherfall: return (0.80, 0.5, 0.45)
        case .currents: return (0.90, 0.8, 0.6)
        case .kaleidoscope: return (0.90, 0.8, 0.7)
        case .prism: return (0.80, 0.8, 0.35)
        }
    }

    /// How much each dot wobbles on its own (crisp patterns keep still).
    var wobble: Float {
        switch self {
        case .network, .nebula: return 0.6
        case .globe: return 0.4
        case .tunnel: return 0.3
        case .mesh: return 0.12
        case .lattice: return 0.08
        case .cipherfall, .currents, .kaleidoscope, .prism: return 0
        default: return 1
        }
    }

    /// How strongly nearby dots are joined by lines, and how near is near.
    var lines: (amount: Float, reach: Float) {
        switch self {
        case .network: return (1.7, 0.17)
        case .globe: return (1.0, 0.30)
        default: return (0, 0.24)
        }
    }
}

struct Sample {
    var x: Float, y: Float, z: Float
    var r: Float, g: Float, b: Float
    /// 0 = a fine dot; above 0 = a soft round light about this many pixels across (at 768 high).
    var size: Float = 0
}

@inline(__always) func rotY(_ x: inout Float, _ z: inout Float, _ a: Float) {
    let c = cosf(a), s = sinf(a)
    let nx = x * c + z * s
    z = -x * s + z * c
    x = nx
}

@inline(__always) func rotX(_ y: inout Float, _ z: inout Float, _ a: Float) {
    let c = cosf(a), s = sinf(a)
    let ny = y * c - z * s
    z = y * s + z * c
    y = ny
}

@inline(__always) func hash1(_ x: Float) -> Float {
    var h = UInt32(truncatingIfNeeded: Int(x * 7.0) &+ 0x2F1D) &* 0x9E37_79B1
    h ^= h >> 15; h = h &* 0x85EB_CA77; h ^= h >> 13; h = h &* 0xC2B2_AE3D; h ^= h >> 16
    return Float(h & 0xFF_FFFF) / Float(0x100_0000)
}

// MARK: - Formations

@inline(__always)
func samplePattern(_ p: Pattern, _ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float,
                   _ t: Float, _ aspect: Float) -> Sample {
    switch p {
    case .orb: return orb(s1, s2, s3, s4, t)
    case .veil: return veil(s1, s2, s3, s4, t, aspect)
    case .fountain: return fountain(s1, s2, s3, s4, t)
    case .aurora: return aurora(s1, s2, s3, s4, t, aspect)
    case .waterfall: return waterfall(s1, s2, s3, s4, t, aspect)
    case .knot: return knot(s1, s2, s3, s4, t)
    case .murmuration: return murmuration(s1, s2, s3, s4, t, aspect)
    case .rings: return rings(s1, s2, s3, s4, t)
    case .network: return network(s1, s2, s3, s4, t)
    case .globe: return globe(s1, s2, s3, s4, t)
    case .lattice: return lattice(s1, s2, s3, s4, t, aspect)
    case .tunnel: return tunnel(s1, s2, s3, s4, t)
    case .mesh: return mesh(s1, s2, s3, s4, t, aspect)
    case .nebula: return nebula(s1, s2, s3, s4, t, aspect)
    case .cipherfall: return cipherfall(s1, s2, s3, s4, t, aspect)
    // The flow patterns move real dots; the engine reads those instead of this.
    case .currents, .kaleidoscope: return Sample(x: 0, y: 0, z: 0, r: 0, g: 0, b: 0)
    case .prism: return prism(s1, s2, s3, s4, t)
    }
}

/// A rotating ball of swirling coloured light with a few faint wisps escaping.
func orb(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let R: Float = 0.80
    if s4 < 0.87 {
        var theta = TAU * s1
        var phi = acosf(1 - 2 * s2)
        let band = sinf(phi * 3 + t * 0.31)
        theta += t * (0.20 + 0.32 * band)
        phi += 0.20 * sinf(theta * 2 + t * 0.53)
        var r = R * (1 + 0.008 * sinf(theta * 3 + phi * 2 + t * 1.3))
        if s3 < 0.22 {
            r *= powf(s3 / 0.22, 0.35)          // inner streaks
        } else {
            r *= 1 - 0.07 * (s3 - 0.22)          // fuzzy shell
        }
        let sp = sinf(phi)
        var x = r * sp * cosf(theta), y = r * cosf(phi), z = r * sp * sinf(theta)
        rotY(&x, &z, t * 0.13)
        rotX(&y, &z, 0.45 + 0.25 * sinf(t * 0.09))
        let hue = theta / TAU + 0.18 * cosf(phi * 2 + t * 0.2) + t * 0.015
        let c = orbPalette(hue)
        let patch = 0.12 + 1.05 * smooth(0.5 + 0.9 * sinf(theta * 2 - phi * 3 + t * 0.4))
        let k = patch * (s3 < 0.22 ? 0.7 : 1.0)
        return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
    } else {
        let streams: Float = 5
        let kf = floorf(s1 * streams)
        let u = fract(s1 * streams * 3.7 + t * 0.06)
        let a = kf * TAU / streams + 0.7 * sinf(t * 0.07 + kf * 1.9)
        let r = R * (0.92 + 1.3 * u)
        let ang = a + u * 1.1 + (s2 - 0.5) * 0.45 * (0.25 + u)
        var x = r * cosf(ang)
        let y = r * sinf(ang) * 0.85
        var z = (s3 - 0.5) * 0.7 * u - 0.4
        rotY(&x, &z, 0.2 * sinf(t * 0.05))
        let c = orbPalette(kf * 0.23 + 0.12 + t * 0.015)
        let k = (1 - u) * (1 - u) * 0.9
        return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
    }
}

private let orbStops: [(Float, Float, Float)] = [
    (0.15, 0.90, 1.00),   // cyan
    (0.15, 0.35, 1.00),   // blue
    (0.50, 0.20, 1.00),   // violet
    (1.00, 0.30, 0.80),   // pink
    (0.55, 0.25, 0.95),   // purple
    (0.30, 0.95, 0.50),   // green
    (0.20, 0.75, 0.70),   // teal
]

/// Cyclic cool rainbow used by the orb: cyan, blue, violet, pink, green.
@inline(__always) func orbPalette(_ h: Float) -> (Float, Float, Float) {
    let stops = orbStops
    let n = Float(stops.count)
    let q = fract(h) * n
    let i = Int(q) % stops.count
    let j = (i + 1) % stops.count
    let f = smooth(q - floorf(q))
    let a = stops[i], b = stops[j]
    return (mixf(a.0, b.0, f), mixf(a.1, b.1, f), mixf(a.2, b.2, f))
}

/// Colours along the S-shaped ribbon: green → cyan → white → violet → pink.
private let veilStops: [(Float, Float, Float, Float)] = [
        (0.00, 0.20, 1.00, 0.35),
        (0.24, 0.30, 1.00, 0.55),
        (0.37, 0.15, 0.95, 0.85),
        (0.47, 0.70, 0.95, 1.00),
        (0.53, 0.80, 0.85, 1.00),
        (0.68, 0.55, 0.30, 1.00),
    (1.00, 1.00, 0.22, 0.75),
]

@inline(__always) func veilPalette(_ p: Float) -> (Float, Float, Float) {
    let stops = veilStops
    let q = clamp01(p)
    var i = 0
    while i < stops.count - 2 && q > stops[i + 1].0 { i += 1 }
    let a = stops[i], b = stops[i + 1]
    let f = smooth((q - a.0) / (b.0 - a.0))
    return (mixf(a.1, b.1, f), mixf(a.2, b.2, f), mixf(a.3, b.3, f))
}

/// Twisting S-shaped ribbon of light strands, pinched and white-hot in the middle.
func veil(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    let lanes: Float = 40
    let laneIdx = floorf(s2 * lanes)
    let lane = (laneIdx + 0.5) / lanes
    let haze = s4 > 0.94
    let speed = 0.035 + 0.025 * hash1(laneIdx)
    let u = fract(s1 + t * speed)
    let L: Float = 2.9
    let yy = L / 2 - L * u
    let A = min(aspect, 1.6) * 0.42 * (1 + 0.15 * sinf(t * 0.11))
    let k = Float.pi * (1.0 + 0.18 * sinf(t * 0.07))
    let cx = A * sinf(k * (u - 0.5)) + 0.10 * sinf(t * 0.13 + u * 3)
    let dx = A * k * cosf(k * (u - 0.5))
    let len = sqrtf(dx * dx + L * L)
    let nx = L / len, ny = dx / len
    let e = fabsf(2 * u - 1)
    let w = 0.07 + 0.55 * powf(e, 1.25)
    let l = lane - 0.5
    var off = 2 * l * w * (0.8 + 0.2 * sinf(t * 0.3 + laneIdx))
    off += 0.03 * sinf(u * 7 + laneIdx * 1.3 + t * 0.8) * (0.3 + e)
    if haze { off += (s3 - 0.5) * w * 1.4 } else { off += (s3 - 0.5) * 0.004 }
    var x = cx + nx * off
    var y = yy + ny * off
    var z = 2 * l * w * sinf(Float.pi * u + t * 0.3) * 0.7
    let tilt = 0.25 * sinf(t * 0.05)
    let c0 = cosf(tilt), sn = sinf(tilt)
    let rx = x * c0 - y * sn
    y = x * sn + y * c0
    x = rx
    rotY(&x, &z, 0.3 * sinf(t * 0.09))
    var c = veilPalette(u + 0.08 * l)
    let sh0 = max(0, sinf(t * 0.025)); let shift = sh0 * sh0
    let alt = (c.2, c.0 * 0.9 + 0.1, c.1)
    c = (mixf(c.0, alt.0, shift * 0.6), mixf(c.1, alt.1, shift * 0.6), mixf(c.2, alt.2, shift * 0.6))
    var bright = (0.2 + 0.8 * powf(hash1(laneIdx * 3.1), 2)) * (1 - 0.55 * fabsf(2 * l))
    bright *= smooth(u * 8) * smooth((1 - u) * 8)
    if haze { bright *= 0.3 }
    return Sample(x: x, y: y, z: z, r: c.0 * bright, g: c.1 * bright, b: c.2 * bright)
}

/// A pulsing rainbow fountain that arcs up and falls back, slowly turning.
func fountain(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let maxT: Float = 1.75
    let T = fract(s1 + t * 0.38) * maxT
    let launch = t - T / 0.38 / maxT          // time this dot was launched
    let ang = TAU * s2 + launch * 0.6
    let spread = (0.06 + 0.55 * sqrtf(s3)) * (1 + 0.15 * sinf(launch * 1.7))
    let vy = 2.75 + 0.35 * sinf(launch * 2.1 + s2 * TAU * 2) + 0.4 * (1 - sqrtf(s3))
    var x = cosf(ang) * spread * T
    var z = sinf(ang) * spread * T
    var y = -1.2 + vy * T - 1.65 * T * T
    if s4 > 0.8 {        // spray mist drifting off the arcs
        x *= 1.25; z *= 1.25; y += 0.08 * sinf(s3 * 40 + t)
    }
    rotX(&y, &z, 0.15)
    rotY(&x, &z, t * 0.1)
    let c = rainbow(s2 * 2 + launch * 0.05)
    let k = smooth(T * 3) * (1 - T / maxT) * (s4 > 0.8 ? 0.4 : 0.8)
    return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
}

/// Folding curtains of the northern lights with rising rays.
func aurora(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    let curtain: Float = s3 < 0.55 ? 0 : 1
    let ph = curtain * 2.1
    let xs = (s2 * 2 - 1) * aspect * 1.3
    let base = -0.45 + 0.22 * sinf(xs * 1.3 + t * 0.21 + ph) + 0.09 * sinf(xs * 3.1 - t * 0.37 + ph) + curtain * 0.15
    let v = fract(s1 + t * 0.22 + hash1(floorf(s2 * 400)) * 0.3)
    let ray = 0.5 + 0.5 * sinf(xs * 23 + 3 * sinf(t * 0.3 + xs * 2) + ph)
    let height = 0.6 + 0.3 * sinf(xs * 2.3 + t * 0.17 + ph)
    var x = xs + 0.15 * sinf(xs * 4 + t * 0.5 + ph) + 0.05 * v * sinf(t + xs * 3)
    let y = base + v * height
    var z = 0.5 * sinf(xs * 1.7 + t * 0.23 + ph) - curtain * 0.7
    rotY(&x, &z, 0.08 * sinf(t * 0.05))
    let green: (Float, Float, Float) = (0.1, 1.0, 0.35)
    let violet: (Float, Float, Float) = curtain > 0 ? (0.9, 0.25, 0.85) : (0.55, 0.3, 1.0)
    let m = smooth((v - 0.45) * 3.5)
    let hueDrift = 0.5 + 0.5 * sinf(t * 0.04 + xs * 0.5)
    let g2: (Float, Float, Float) = (mixf(green.0, 0.1, hueDrift), mixf(green.1, 0.85, hueDrift), mixf(green.2, 0.75, hueDrift))
    let c = (mixf(g2.0, violet.0, m), mixf(g2.1, violet.1, m) * (1 - 0.5 * m * (1 - m) * 4), mixf(g2.2, violet.2, m))
    let k = powf(1 - v, 1.3) * (0.15 + 0.85 * ray * ray * ray) * smooth(v * 14)
    return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
}

/// A glowing curtain of falling water with rainbow mist rising from its foot.
func waterfall(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    let halfW = min(aspect, 1.6) * 0.42
    if s4 < 0.5 {
        let u = fract(s1 + t * (0.28 + 0.12 * s3))
        let xs = (s2 * 2 - 1) * halfW * (1 + 0.1 * sinf(t * 0.2))
        let lip = smooth(u * 5)
        var x = xs + 0.02 * sinf(u * 9 + s2 * 11 + t)
        let y = 0.9 + 0.06 * sinf(xs * 2.5 + 0.7) + 0.12 * (1 - lip) - 2.3 * u * u
        var z = -0.6 + 1.0 * u - 0.25 * (1 - lip)
        rotY(&x, &z, 0.25 * sinf(t * 0.06))
        let tint = rainbow(s2 * 0.8 + t * 0.02)
        let k = 0.5 * smooth((1 - u) * 5) * (0.55 + 0.45 * hash1(floorf(s2 * 90))) * smooth((1 - fabsf(2 * s2 - 1)) * 5)
        return Sample(x: x, y: y, z: z,
                      r: (0.45 + 0.25 * tint.0) * k, g: (0.65 + 0.25 * tint.1) * k, b: (0.95 + 0.2 * tint.2) * k)
    } else {
        let u = fract(s1 + t * 0.085)
        let xs = (s2 * 2 - 1) * halfW
        var x = xs * (1 + u * 1.2) + 0.3 * sinf(u * 3 + s3 * TAU + t * 0.2)
        let y = -1.1 + u * 1.7 + 0.12 * sinf(xs * 3 + t * 0.4 + s3 * 5)
        var z = 0.3 + (s3 - 0.5) * 0.9
        rotY(&x, &z, 0.25 * sinf(t * 0.06))
        let d = sqrtf(x * x + (y + 1.9) * (y + 1.9))
        let q = (2.05 - d) / 0.55                      // 0 outer (red) … 1 inner (violet)
        let band = smooth(q * 6) * smooth((1 - q) * 6)
        let rc = rainbow(clamp01(q) * 0.78)
        let k = sinf(Float.pi * u) * 0.4
        let m: (Float, Float, Float) = (0.35, 0.45, 0.65)
        return Sample(x: x, y: y, z: z,
                      r: mixf(m.0, rc.0 * 1.3, band) * k,
                      g: mixf(m.1, rc.1 * 1.3, band) * k,
                      b: mixf(m.2, rc.2 * 1.3, band) * k)
    }
}

@inline(__always) func knotPoint(_ u: Float) -> (Float, Float, Float) {
    let ph = TAU * u
    let r = cosf(3 * ph) + 2.2
    return (0.34 * r * cosf(2 * ph), 0.34 * r * sinf(2 * ph), -0.34 * sinf(3 * ph))
}

/// A tumbling trefoil knot wrapped in spiralling strands of rainbow light.
func knot(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let u = fract(s1 + t * 0.025)
    let p = knotPoint(u)
    let q = knotPoint(u + 0.002)
    var tx = q.0 - p.0, ty = q.1 - p.1, tz = q.2 - p.2
    let tl = sqrtf(tx * tx + ty * ty + tz * tz) + 1e-6
    tx /= tl; ty /= tl; tz /= tl
    // normal: tangent × z-axis-ish, binormal: tangent × normal
    var nx = ty, ny = -tx, nz: Float = 0
    let nl = sqrtf(nx * nx + ny * ny) + 1e-6
    nx /= nl; ny /= nl; nz /= nl
    let bx = ty * nz - tz * ny, by = tz * nx - tx * nz, bz = tx * ny - ty * nx
    let strand = floorf(s2 * 14)
    let a = strand / 14 * TAU + u * TAU * 5 + t * 0.6
    let rad = 0.13 * (0.85 + 0.3 * s3) * (1 + 0.25 * sinf(u * TAU * 4 + t))
    var x = p.0 + rad * (cosf(a) * nx + sinf(a) * bx)
    var y = p.1 + rad * (cosf(a) * ny + sinf(a) * by)
    var z = p.2 + rad * (cosf(a) * nz + sinf(a) * bz)
    rotY(&x, &z, t * 0.17)
    rotX(&y, &z, 0.6 * sinf(t * 0.11))
    let c = rainbow(u * 2 + t * 0.03 + strand * 0.01)
    let k: Float = s4 > 0.9 ? 0.35 : 0.8
    return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
}

/// Shared rhythm: one gentle "heartbeat" every BEAT seconds of engine time.
let BEAT: Float = 2.4

@inline(__always) func hashU(_ v: UInt32) -> Float {
    var h = v &* 0x9E37_79B1
    h ^= h >> 15; h = h &* 0x85EB_CA77; h ^= h >> 13; h = h &* 0xC2B2_AE3D; h ^= h >> 16
    return Float(h & 0xFF_FFFF) / Float(0x100_0000)
}

@inline(__always) func flockPath(_ u: Float) -> (Float, Float, Float) {
    (0.80 * sinf(0.29 * u) + 0.25 * sinf(0.71 * u + 1),
     0.38 * sinf(0.37 * u + 0.5) + 0.12 * sinf(0.93 * u),
     0.55 * sinf(0.23 * u + 2))
}

/// A murmuration: a living cloud of dots that streams along a wandering path,
/// stretches, twists and folds, splits in two and merges, with dark and light
/// waves rippling through it as the "birds" turn.
func murmuration(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    // A soft gaussian cloud, thick in the middle and wispy at the edges.
    let a = TAU * s1
    let cz = 2 * s2 - 1
    // Mostly an even ball with a soft rim; a few strays wander further out.
    let rr = s4 > 0.9 ? 1 + 0.5 * s3 * s3 : cbrtf(s3) * (1 - 0.15 * s3 * s3 * s3)
    let sq = sqrtf(max(0, 1 - cz * cz))
    let bx = rr * cz * 1.25, by = rr * sq * cosf(a), bz = rr * sq * sinf(a)
    // Two flocks that drift apart and merge again.
    let g: Float = s4 < 0.33 ? 1 : 0
    let sep = smooth(sinf(t * 0.06) * 1.6 + 0.2)
    let tl = t * 1.15 - g * 2.6 * sep + g * 0.3
    // The body trails along the path; density waves run through it.
    let along = bx * 0.5 + 0.5
    let lag = 3.0 + 1.2 * sinf(t * 0.09)
    let tq = tl - along * lag + 0.16 * sinf(bx * 7 - t * 2.6)
    let head = flockPath(tl), tail = flockPath(tl - lag)
    let ex = head.0 - tail.0, ey = head.1 - tail.1, ez = head.2 - tail.2
    let bodyLen = sqrtf(ex * ex + ey * ey + ez * ez)
    let p = flockPath(tq)
    let q = flockPath(tq + 0.02)
    var tx = q.0 - p.0, ty = q.1 - p.1, tz = q.2 - p.2
    let tlen = sqrtf(tx * tx + ty * ty + tz * tz) + 1e-6
    tx /= tlen; ty /= tlen; tz /= tlen
    // Frame around the direction of travel.
    var nx = -tz, nz = tx
    let nl = sqrtf(nx * nx + nz * nz) + 1e-6
    nx /= nl; nz /= nl
    let ny: Float = 0
    let bxv = ny * tz - nz * ty, byv = nz * tx - nx * tz, bzv = nx * ty - ny * tx
    // Cross-section that breathes between a ball and a thin sheet, twisting along the body.
    let sy = 0.10 + 0.16 * (0.5 + 0.5 * sinf(t * 0.19 + g * 2)) * (1 + 0.45 * sinf(bx * 3 + t * 0.7))
    let sz = 0.05 + 0.13 * (0.5 + 0.5 * sinf(t * 0.23 + 1 + g))
    let roll = 1.2 * sinf(t * 0.27 + bx * 2.4 + g)
    let cr = cosf(roll), sr = sinf(roll)
    let oy = (by * cr - bz * sr) * sy * 2.2 + 0.05 * sinf(bx * 9 - t * 3)
    let oz = (by * sr + bz * cr) * sz * 2.2
    let ax = bx * 0.22
    let widen = min(aspect, 1.7) / 1.33
    var x = (p.0 * widen + tx * ax + nx * oy + bxv * oz)
    let y = p.1 + ty * ax + ny * oy + byv * oz
    var z = p.2 + tz * ax + nz * oy + bzv * oz
    rotY(&x, &z, 0.15 * sinf(t * 0.05))
    // Colour flows along the flock; dark/light turning waves sweep through.
    let c = orbPalette(along * 0.35 + t * 0.018 + g * 0.45)
    let wave = smooth(0.5 + 0.9 * sinf(bx * 6 + by * 2.5 - t * 2.3 + g * 3))
    // Keep the light even whether the flock is spread thin or bunched up.
    let spread = min(max(0.02 / (sy * sz), 0.3), 1.4) * (0.6 + 0.4 * sep)
        * min(max((bodyLen + 0.3) / 1.2, 0.35), 1.3)
    let k = (0.10 + 0.42 * wave) * (rr > 1 ? 0.5 : 1) * spread
    return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
}

/// A tilted pool of light: rings of dots that throb with standing waves, while
/// every heartbeat sends a bright ripple rolling out from the middle.
func rings(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let R: Float = 1.05
    let r = sqrtf(s1) * R
    let rq = (floorf(r * 15) + 0.5) / 15 + (s3 - 0.5) * 0.014
    let ang = TAU * s2 + t * (0.22 / (0.35 + rq)) * (s4 < 0.5 ? 1 : -0.6)
    var h = 0.05 * sinf(rq * 9 - t * 2.6) + 0.035 * sinf(ang * 3 + t * 1.3) * rq
    var crest: Float = 0
    let beat0 = floorf(t / BEAT)
    for k in 0..<3 {
        let tb = (beat0 - Float(k)) * BEAT
        let age = t - tb
        let d = rq - age * 0.62
        let e = expf(-d * d / 0.008) * expf(-age * 0.45)
        crest += e
        h += 0.20 * e * (1.1 - rq * 0.4)
    }
    var x = rq * cosf(ang)
    var z = rq * sinf(ang)
    var y = h - 0.05
    rotX(&y, &z, 0.55 + 0.12 * sinf(t * 0.1))
    rotY(&x, &z, 0.2 * sinf(t * 0.04))
    let c = rainbow(rq * 0.6 - t * 0.05)
    let edge = smooth((R - rq) * 5)
    let k = (0.16 + 1.3 * crest) * edge * (s4 > 0.93 ? 0.4 : 1)
    return Sample(x: x, y: y, z: z, r: c.0 * k, g: c.1 * k, b: c.2 * k)
}

// MARK: - Mood

/// The look of the moment. Every so often a new random mood is picked and the
/// picture drifts towards it over several seconds: colour shift, how far each
/// dot's colour strays, saturation, glow, trail length, streak length,
/// fuzziness, how many sparks fly and how much the dots twinkle.
struct Mood {
    var hue: Float = 0          // whole-picture colour shift, in turns
    var hueJitter: Float = 0.02 // how far each dot's colour strays, in turns
    var saturation: Float = 1
    var glow: Float = 1
    var trail: Float = 1        // >1: longer trails
    var streak: Float = 1       // length of each dot's streak
    var fuzz: Float = 1         // wobble amount
    var scatter: Float = 0      // fixed random offset of each dot
    var sparks: Float = 1       // how many dots fly away
    var twinkle: Float = 1
    var exposure: Float = 1
    // Calmer colouring: blend towards one tint (mono) or two tints (duo).
    var mono: Float = 0
    var duo: Float = 0
    var tAr: Float = 0.3, tAg: Float = 1, tAb: Float = 0.8
    var tBr: Float = 1, tBg: Float = 0.8, tBb: Float = 0.3
    var lines: Float = 0        // network lines joining nearby dots
    var haze: Float = 0         // faint tinted background

    static let tints: [(Float, Float, Float)] = [
        (0.35, 1.0, 0.45),  // matrix green
        (0.25, 0.95, 0.85), // teal
        (0.45, 0.72, 1.0),  // ice blue
        (1.0, 0.80, 0.35),  // gold
        (1.0, 0.55, 0.22),  // amber
        (0.85, 0.88, 0.95), // soft white
        (0.68, 0.45, 1.0),  // violet
        (1.0, 0.45, 0.62),  // rose
        (0.55, 0.95, 0.30), // lime
    ]

    static func random(_ rng: inout SplitMix) -> Mood {
        func r(_ a: Float, _ b: Float) -> Float { a + (b - a) * rng.nextFloat() }
        var m = Mood()
        // Half the time stay near the pattern's own colours, otherwise wander anywhere.
        m.hue = rng.nextFloat() < 0.5 ? r(-0.08, 0.08) : r(-0.5, 0.5)
        m.hueJitter = rng.nextFloat() < 0.6 ? r(0, 0.06) : r(0.08, 0.22)
        // Often softer: muted colours and little glow.
        let calm = rng.nextFloat() < 0.4
        m.saturation = calm ? r(0.3, 0.75) : r(0.75, 1.3)
        let g = rng.nextFloat()
        m.glow = calm || g < 0.35 ? r(0.12, 0.5) : g < 0.5 ? r(1.2, 1.6) : r(0.5, 1.15)
        m.trail = rng.nextFloat() < 0.3 ? r(1.6, 2.6) : r(0.6, 1.5)
        m.streak = rng.nextFloat() < 0.3 ? r(2.0, 3.6) : r(0.7, 1.8)
        m.fuzz = r(0.4, 2.6)
        m.scatter = rng.nextFloat() < 0.35 ? r(0.01, 0.04) : 0
        m.sparks = rng.nextFloat() < 0.25 ? r(2.0, 3.5) : r(0.4, 1.8)
        m.twinkle = r(0.4, 2.0)
        m.exposure = calm ? r(0.75, 0.95) : r(0.88, 1.12)
        let pal = rng.nextFloat()
        let ts = Mood.tints
        let ia = Int(rng.next() % UInt64(ts.count))
        var ib = Int(rng.next() % UInt64(ts.count))
        if ib == ia { ib = (ia + 3) % ts.count }
        let a = ts[ia], b = ts[ib]
        m.tAr = a.0; m.tAg = a.1; m.tAb = a.2
        m.tBr = b.0; m.tBg = b.1; m.tBb = b.2
        if pal >= 0.42 { m.glow = min(m.glow, 1.0); m.exposure = min(m.exposure, 0.95) }
        if pal < 0.42 { m.mono = 0; m.duo = 0 }
        else if pal < 0.72 { m.mono = r(0.75, 1); m.duo = 0 }
        else { m.mono = r(0.8, 1); m.duo = 1 }
        m.lines = rng.nextFloat() < 0.3 ? r(0.35, 1.0) : 0
        m.haze = rng.nextFloat() < 0.3 ? r(0.012, 0.035) : 0
        return m
    }

    mutating func approach(_ o: Mood, _ k: Float) {
        hue = mixf(hue, o.hue, k); hueJitter = mixf(hueJitter, o.hueJitter, k)
        saturation = mixf(saturation, o.saturation, k); glow = mixf(glow, o.glow, k)
        trail = mixf(trail, o.trail, k); streak = mixf(streak, o.streak, k)
        fuzz = mixf(fuzz, o.fuzz, k); scatter = mixf(scatter, o.scatter, k)
        sparks = mixf(sparks, o.sparks, k); twinkle = mixf(twinkle, o.twinkle, k)
        exposure = mixf(exposure, o.exposure, k)
        mono = mixf(mono, o.mono, k); duo = mixf(duo, o.duo, k)
        tAr = mixf(tAr, o.tAr, k); tAg = mixf(tAg, o.tAg, k); tAb = mixf(tAb, o.tAb, k)
        tBr = mixf(tBr, o.tBr, k); tBg = mixf(tBg, o.tBg, k); tBb = mixf(tBb, o.tBb, k)
        lines = mixf(lines, o.lines, k); haze = mixf(haze, o.haze, k)
    }
}

/// Turns a colour around the colour wheel by `turns`, then sets its saturation.
@inline(__always) func recolor(_ r: inout Float, _ g: inout Float, _ b: inout Float, _ turns: Float, _ sat: Float) {
    let a = TAU * turns
    let c = cosf(a), sn = sinf(a) * 0.57735
    let m = (1 - c) / 3
    let nr = r * (c + m) + g * (m - sn) + b * (m + sn)
    let ng = r * (m + sn) + g * (c + m) + b * (m - sn)
    let nb = r * (m - sn) + g * (m + sn) + b * (c + m)
    let l = (nr + ng + nb) * 0.3333
    r = max(0, l + (nr - l) * sat); g = max(0, l + (ng - l) * sat); b = max(0, l + (nb - l) * sat)
}

/// One place where the dots are being stirred: the mouse pointer, a finger, or the
/// wake trailing behind either. `push` below zero gathers dots instead of parting them.
struct Stir { var x: Float, y: Float, amt: Float, push: Float, turn: Float }

/// A finger on a touch screen (positions in render pixels, y up).
struct Finger {
    var x: Float, y: Float, px: Float, py: Float, lx: Float, ly: Float
    var energy: Float = 0, still: Float = 0, down = true
}

// MARK: - Engine

final class Engine {
    let count: Int
    private(set) var width = 0
    private(set) var height = 0

    // Light buffer (RGB floats), glow buffers and output pixels.
    private var acc: UnsafeMutablePointer<Float>?
    private var small: UnsafeMutablePointer<Float>?
    private var smallTmp: UnsafeMutablePointer<Float>?
    private var sw = 0, sh = 0
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var context: CGContext?

    // Per-dot data.
    private let seeds: UnsafeMutablePointer<Float>      // 8 per dot
    private let prevX: UnsafeMutablePointer<Float>
    private let prevY: UnsafeMutablePointer<Float>
    private let curX: UnsafeMutablePointer<Float>
    private let curY: UnsafeMutablePointer<Float>
    private let col: UnsafeMutablePointer<Float>        // 3 per dot
    private let dotSize: UnsafeMutablePointer<Float>
    // The first few hundred dots double as network nodes: their 3-D positions.
    private let nodeCount: Int
    private let nodeX: UnsafeMutablePointer<Float>
    private let nodeY: UnsafeMutablePointer<Float>
    private let nodeZ: UnsafeMutablePointer<Float>
    private let nodeLinks: UnsafeMutablePointer<Int32>

    var time: Double = 0
    var speed: Double = 1
    /// When set, the engine stays on this pattern; otherwise it cycles.
    var fixedPattern: Pattern?
    var patternDuration: Double = 38
    /// Seconds each pattern stays when cycling; 0 keeps the built-in pacing.
    var changeEvery: Double = 0 {
        didSet { if changeEvery != oldValue { patternDuration = changeEvery > 0 ? changeEvery : 38 } }
    }
    /// The soft glow around the dots; it eases in and out when switched.
    var glowEnabled = true
    private var glowLevel: Float = 1
    var transitionDuration: Double = 6
    /// 0 = classic calm motion; 1 = heartbeat pulses, ripples, wobble, twinkle
    /// and campfire sparks flying away.
    var liveliness: Float = 1

    private(set) var current: Pattern
    private var previous: Pattern?
    private var patternStart: Double = 0
    private var transitionStart: Double = -100
    private var order: [Pattern] = [.orb, .network, .veil, .mesh, .murmuration, .fountain, .globe, .aurora,
                                    .tunnel, .rings, .nebula, .waterfall, .lattice, .knot, .cipherfall,
                                    .currents, .kaleidoscope, .prism]
    private var freshTrails = true

    /// Picks a random next pattern (and a random stay) instead of going in order.
    var shuffle = false
    private var rng: SplitMix
    private(set) var mood = Mood()
    private var moodTarget = Mood()
    private var moodClock: Double = 0
    private var nextMood: Double = 9

    init(count: Int, start: Pattern = .orb, seed: UInt64 = 0x5EED_1234) {
        self.count = count
        self.current = start
        seeds = .allocate(capacity: count * 8)
        prevX = .allocate(capacity: count)
        prevY = .allocate(capacity: count)
        curX = .allocate(capacity: count)
        curY = .allocate(capacity: count)
        col = .allocate(capacity: count * 3)
        dotSize = .allocate(capacity: count)
        dotSize.initialize(repeating: 0, count: count)
        nodeCount = min(count, 650)
        nodeX = .allocate(capacity: nodeCount); nodeY = .allocate(capacity: nodeCount)
        nodeZ = .allocate(capacity: nodeCount); nodeLinks = .allocate(capacity: nodeCount)
        var rng = SplitMix(seed: seed)
        for i in 0..<(count * 8) { seeds[i] = rng.nextFloat() }
        nextMood = 8 + 8 * Double(rng.nextFloat())
        self.rng = rng
        for i in 0..<count { prevX[i] = -1e9; prevY[i] = -1e9 }
    }

    deinit {
        seeds.deallocate(); prevX.deallocate(); prevY.deallocate()
        curX.deallocate(); curY.deallocate(); col.deallocate(); dotSize.deallocate()
        nodeX.deallocate(); nodeY.deallocate(); nodeZ.deallocate(); nodeLinks.deallocate()
        freeBuffers()
    }

    /// Most CPU cores the engine may use at once (the screen saver keeps this low so
    /// it never starves the rest of the Mac, including the lock screen).
    var maxThreads = ProcessInfo.processInfo.activeProcessorCount

    /// Runs body(0..<n) on at most maxThreads cores.
    @inline(__always)
    private func parallel(_ n: Int, _ body: (Int) -> Void) {
        let workers = max(1, min(n, maxThreads))
        if workers == 1 { for i in 0..<n { body(i) }; return }
        DispatchQueue.concurrentPerform(iterations: workers) { w in
            var i = w
            while i < n { body(i); i += workers }
        }
    }

    /// Give back the picture memory (while the screen saver is paused); it is made
    /// again on the next resize.
    func releaseBuffers() {
        freeBuffers()
        width = 0; height = 0
    }

    private func freeBuffers() {
        acc?.deallocate(); small?.deallocate(); smallTmp?.deallocate(); pixels?.deallocate()
        acc = nil; small = nil; smallTmp = nil; pixels = nil; context = nil
    }

    /// Draws with the graphics chip when set; nil keeps the drawing in this file.
    private(set) var gpu: GPURenderer?

    /// Switch to drawing with the graphics chip. False if this Mac cannot.
    @discardableResult
    func useGPU() -> Bool {
        if gpu == nil {
            gpu = GPURenderer(dots: count)
            if gpu != nil { freeBuffers(); width = 0; height = 0 }
        }
        return gpu != nil
    }

    func resize(width w: Int, height h: Int) {
        let w = max(w, 16), h = max(h, 16)
        if w == width && h == height { return }
        freeBuffers()
        width = w; height = h
        if let gpu = gpu {
            gpu.resize(width: w, height: h)
            freshTrails = true
            return
        }
        acc = .allocate(capacity: w * h * 3)
        acc!.initialize(repeating: 0, count: w * h * 3)
        sw = max(w / 4, 4); sh = max(h / 4, 4)
        small = .allocate(capacity: sw * sh * 3)
        small!.initialize(repeating: 0, count: sw * sh * 3)
        smallTmp = .allocate(capacity: sw * sh * 3)
        smallTmp!.initialize(repeating: 0, count: sw * sh * 3)
        pixels = .allocate(capacity: w * h)
        pixels!.initialize(repeating: 0xFF00_0000, count: w * h)
        context = CGContext(data: pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        freshTrails = true
    }

    // MARK: Pattern changes

    func show(_ p: Pattern) {
        guard p != current || previous != nil else { return }
        previous = current
        current = p
        transitionStart = time
        patternStart = time
        if p.isFlow { rollFlow(p) }
    }

    // MARK: Flow patterns (dots that really move)

    private var flows: [Pattern: FlowSim] = [:]
    /// Room for the iridescent glass's triangles when the graphics chip is not drawing.
    private var prismScratch: UnsafeMutablePointer<PrismVertex>?
    /// The user's Particle Flow settings; changing them restarts the flows.
    var particleFlow = ParticleFlow() {
        didSet {
            guard particleFlow != oldValue else { return }
            for p in Array(flows.keys) { rollFlow(p) }
        }
    }
    /// Rolls new settings for a flow pattern, so every visit looks different.
    private func rollFlow(_ p: Pattern) {
        var s: FlowSettings
        if particleFlow.seed != 0 {
            // A chosen seed always rolls the same flow.
            var fixed = SplitMix(seed: UInt64(particleFlow.seed) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(p.rawValue))
            s = FlowSettings.random(&fixed, kaleidoscope: p == .kaleidoscope)
        } else {
            s = FlowSettings.random(&rng, kaleidoscope: p == .kaleidoscope)
        }
        particleFlow.apply(to: &s)
        if let f = flows[p] { f.restart(with: s) } else { flows[p] = FlowSim(capacity: count, settings: s) }
    }
    private func flow(_ p: Pattern?) -> FlowSim? {
        guard let p = p, p.isFlow else { return nil }
        if flows[p] == nil { rollFlow(p) }
        return flows[p]
    }
    /// A few words about what is showing, for patterns that roll their own settings.
    var detail: String { current.isFlow ? (flows[current]?.settings.summary ?? "") : "" }

    func next() {
        let i = order.firstIndex(of: current) ?? 0
        show(order[(i + 1) % order.count])
    }

    /// Jumps to a random pattern, never the one showing. It works through every
    /// pattern before repeating any, so each press brings something new.
    private var bag: [Pattern] = []
    func randomNext() {
        bag.removeAll { $0 == current }
        if bag.isEmpty {
            bag = order.filter { $0 != current }
            for i in stride(from: bag.count - 1, to: 0, by: -1) {
                bag.swapAt(i, Int(rng.next() % UInt64(i + 1)))
            }
        }
        if let p = bag.popLast() { show(p) }
    }

    /// The automatic change: in order, or random with a random stay when shuffling.
    private func autoNext() {
        guard shuffle else { next(); return }
        var p = current
        while p == current { p = order[Int(rng.next() % UInt64(order.count))] }
        show(p)
        patternDuration = 28 + 24 * Double(rng.nextFloat())
        if changeEvery > 0 { patternDuration = changeEvery }
        newMood()
    }

    // MARK: Start-up and the mouse

    /// Dots fade in from a faint scattered mist and gather into the shape.
    var intro = false
    private var introAge: Double = 0

    /// Start on a random pattern with a random look (colours, glow, trails...).
    func randomStart(pattern keep: Pattern? = nil) {
        current = keep ?? order[Int(rng.next() % UInt64(order.count))]
        previous = nil
        patternStart = time
        patternDuration = 28 + 24 * Double(rng.nextFloat())
        if changeEvery > 0 { patternDuration = changeEvery }
        moodTarget = Mood.random(&rng)
        mood = moodTarget
        nextMood = moodClock + 10 + 14 * Double(rng.nextFloat())
    }

    /// Dots near the pointer are pushed aside and swirl, brighter, leaving a wake.
    var pointerEnabled = false
    private var pointer: (Float, Float)?     // render pixels, y up
    private var pointerPrev: (Float, Float)?
    private var pointerLag: (Float, Float) = (0, 0)
    private var pointerEnergy: Float = 0
    /// Size of the area the pointer stirs, as a share of the screen height (the
    /// scroll wheel changes it); the shown size eases towards it.
    var pointerSize: Float = 0.2 {
        didSet { pointerSize = min(max(pointerSize, 0.05), 0.7) }
    }
    private var pointerSizeNow: Float = 0.2

    func setPointer(x: Float, y: Float) { pointer = (x, y) }
    func clearPointer() { pointer = nil }

    // Fingers (touch screens): each one stirs the dots like the pointer does, and any
    // number can be down at once. A finger held still starts to gather dots instead.
    private var fingers: [Int: Finger] = [:]
    var fingerCount: Int { fingers.values.filter { $0.down }.count }
    func touchDown(_ id: Int, x: Float, y: Float) {
        fingers[id] = Finger(x: x, y: y, px: x, py: y, lx: x, ly: y, energy: fingers[id]?.energy ?? 0)
    }
    func touchMove(_ id: Int, x: Float, y: Float) {
        guard var f = fingers[id], f.down else { return }
        f.x = x; f.y = y
        fingers[id] = f
    }
    func touchUp(_ id: Int) { fingers[id]?.down = false }

    /// Jump straight to a random mood (for previews and pictures).
    func jumpToMood(seed: UInt64) {
        var r = SplitMix(seed: seed)
        moodTarget = Mood.random(&r)
        mood = moodTarget
    }

    private func newMood() {
        moodTarget = Mood.random(&rng)
        nextMood = moodClock + 10 + 14 * Double(rng.nextFloat())
    }

    func previousPattern() {
        let i = order.firstIndex(of: current) ?? 0
        show(order[(i + order.count - 1) % order.count])
    }

    private var transitionAmount: Float {
        guard previous != nil else { return 1 }
        return Float(min(max((time - transitionStart) / transitionDuration, 0), 1))
    }

    // MARK: Simulation

    func step(dt: Double) {
        // With the graphics chip drawing there is no light buffer here at all.
        let gpu = self.gpu
        let acc: UnsafeMutablePointer<Float>! = self.acc
        if acc == nil && gpu == nil { return }
        if gpu != nil && width == 0 { return }
        time += dt * speed
        if fixedPattern == nil && time - patternStart > patternDuration { autoNext() }
        moodClock += dt * speed
        if moodClock > nextMood { newMood() }
        mood.approach(moodTarget, Float(1 - exp(-dt * speed / 4.5)))
        let md = mood
        if let f = fixedPattern, f != current { show(f) }
        let w = transitionAmount
        if w >= 1 { previous = nil }

        let t = Float(time)
        let aspect = Float(width) / Float(height)
        let halfH = Float(height) * 0.5
        let cxp = Float(width) * 0.5, cyp = Float(height) * 0.5
        let camD: Float = 3.4
        let cur = current, prev = previous
        // Cipherfall keeps its own green look: how much of the picture it owns right now.
        let cipherAmt: Float = cur == .cipherfall ? (prev == nil ? 1 : w) : (prev == .cipherfall ? 1 - w : 0)
        let keepMood = 1 - cipherAmt
        // A palette chosen in the Particle Flow settings is kept as chosen: the random
        // mood does not recolour a flow pattern then.
        // The iridescent glass always keeps its own colours.
        let holdPalette = particleFlow.palette != .auto
        func keeps(_ p: Pattern?) -> Bool { p == .prism || (holdPalette && (p?.isFlow ?? false)) }
        let colorMood: Float = keepMood * (keeps(cur) ? (prev == nil ? 0 : 1 - w) : 1)
                                        * (keeps(prev) && !keeps(cur) ? w : 1)
        let monoAmt = md.mono * colorMood
        // Flow patterns: move their dots on before reading where they are.
        let flowCur = flow(cur), flowPrev = flow(prev)
        flowCur?.step(dt: dt, aspect: aspect, threads: maxThreads)
        flowPrev?.step(dt: dt, aspect: aspect, threads: maxThreads)
        let seeds = seeds, curX = curX, curY = curY, col = col, dotSize = dotSize
        let nodeX = nodeX, nodeY = nodeY, nodeZ = nodeZ, nodeCount = nodeCount
        let sizeScale = Float(height) / 768
        let n = count
        let live = liveliness
        let wob = prev.map { mixf($0.wobble, current.wobble, transitionAmount) } ?? current.wobble

        // Start-up fade: each dot has its own moment to appear.
        if intro { introAge += dt }
        let age = Float(introAge)
        let introOn = intro && introAge < 5.5
        if intro && introAge >= 5.5 { intro = false }

        // The pointer: stronger while it moves, fading when it rests or leaves.
        var pAmt: Float = 0, px: Float = 0, py: Float = 0, lx: Float = 0, ly: Float = 0
        if pointerEnabled, let p = pointer {
            var speedPx: Float = 0
            if let q = pointerPrev { speedPx = hypotf(p.0 - q.0, p.1 - q.1) / Float(max(dt, 1e-3)) }
            pointerPrev = p
            let target = 0.45 + min(speedPx / Float(height), 1.6)
            pointerEnergy = mixf(pointerEnergy, target, Float(1 - exp(-dt * 6)))
            let lagK = Float(1 - exp(-dt * 3))
            pointerLag = (mixf(pointerLag.0, p.0, lagK), mixf(pointerLag.1, p.1, lagK))
            px = p.0; py = p.1
        } else {
            pointerPrev = nil
            pointerEnergy = mixf(pointerEnergy, 0, Float(1 - exp(-dt * 3)))
            if let p = pointer { px = p.0; py = p.1 }
        }
        pAmt = pointerEnergy
        lx = pointerLag.0; ly = pointerLag.1
        if pointer == nil && pAmt > 0.01 { px = lx; py = ly }
        pointerSizeNow = mixf(pointerSizeNow, pointerSize, Float(1 - exp(-dt * 8)))
        // A soft bell-shaped area: strongest near the pointer, fading smoothly to nothing.
        let sigma = Float(height) * pointerSizeNow * 0.5
        let inv2s2 = 1 / (2 * sigma * sigma)
        let reach2 = 9 * sigma * sigma
        // Everything stirring the dots this frame: the pointer and its wake, then each finger and its wake.
        var stirList: [Stir] = []
        if pAmt > 0.01 {
            stirList.append(Stir(x: px, y: py, amt: pAmt, push: 1, turn: 1))
            stirList.append(Stir(x: lx, y: ly, amt: pAmt * 0.5, push: 1, turn: 1))
        }
        for id in Array(fingers.keys) {
            guard var f = fingers[id] else { continue }
            if f.down {
                let speed = hypotf(f.x - f.px, f.y - f.py) / Float(max(dt, 1e-3)) / Float(max(height, 1))
                f.px = f.x; f.py = f.y
                f.energy = mixf(f.energy, 0.7 + min(speed, 1.6), Float(1 - exp(-dt * 8)))
                f.still = speed < 0.04 ? f.still + Float(dt) : max(0, f.still - Float(dt) * 4)
            } else {
                f.energy = mixf(f.energy, 0, Float(1 - exp(-dt * 2.5)))
                if f.energy < 0.01 { fingers[id] = nil; continue }
            }
            let lagK = Float(1 - exp(-dt * 3))
            f.lx = mixf(f.lx, f.x, lagK); f.ly = mixf(f.ly, f.y, lagK)
            fingers[id] = f
            let pull = smooth((f.still - 0.35) / 0.6)
            stirList.append(Stir(x: f.x, y: f.y, amt: f.energy, push: mixf(1, -0.75, pull), turn: mixf(1, 1.6, pull)))
            stirList.append(Stir(x: f.lx, y: f.ly, amt: f.energy * 0.5, push: 1, turn: 1))
        }
        let stirs = stirList
        let stirCount = stirs.count

        // 1. Positions and colours (in parallel).
        let chunks = 16
        let per = (n + chunks - 1) / chunks
        parallel(chunks) { c in
            let lo = c * per, hi = min(n, lo + per)
            if lo >= hi { return }
            for i in lo..<hi {
                let s1 = seeds[i * 8], s2 = seeds[i * 8 + 1], s3 = seeds[i * 8 + 2], s4 = seeds[i * 8 + 3]
                var sm = flowCur?.sample(i) ?? samplePattern(cur, s1, s2, s3, s4, t, aspect)
                if let prev = prev {
                    let wi = smooth(w * 1.6 - s4 * 0.6)
                    if wi < 1 {
                        let a = flowPrev?.sample(i) ?? samplePattern(prev, s1, s2, s3, s4, t, aspect)
                        let bump = sinf(Float.pi * wi) * 0.45
                        let ang = TAU * s3 + t * 0.7
                        sm.x = mixf(a.x, sm.x, wi) + bump * cosf(ang) * (0.5 + s1)
                        sm.y = mixf(a.y, sm.y, wi) + bump * sinf(ang * 1.3) * (0.5 + s2)
                        sm.z = mixf(a.z, sm.z, wi) + bump * sinf(ang * 0.7)
                        sm.r = mixf(a.r, sm.r, wi); sm.g = mixf(a.g, sm.g, wi); sm.b = mixf(a.b, sm.b, wi)
                    }
                }
                if live > 0 {
                    let s5 = seeds[i * 8 + 4], s6 = seeds[i * 8 + 5], s7 = seeds[i * 8 + 6], s8 = seeds[i * 8 + 7]
                    Engine.enliven(&sm, cur, i, s1, s2, s3, s4, s5, s6, s7, s8, t, aspect, live * keepMood * (cur == .prism ? 0 : 1), md, wob)
                }
                // Colour of the moment, with each dot straying a little on its own.
                let turn = (md.hue + md.hueJitter * (seeds[i * 8 + 7] * 2 - 1)) * colorMood
                if fabsf(turn) > 0.002 || fabsf(md.saturation - 1) > 0.01 {
                    recolor(&sm.r, &sm.g, &sm.b, turn, mixf(1, md.saturation, colorMood))
                }
                // Calmer single- or two-colour looks.
                if monoAmt > 0.01 {
                    let sum = sm.r + sm.g + sm.b
                    let f = clamp01(0.5 + (sm.r - sm.b) / (sum + 1e-3) * 1.2 + (seeds[i * 8 + 7] - 0.5) * 0.4) * md.duo
                    let tr = mixf(md.tAr, md.tBr, f), tg = mixf(md.tAg, md.tBg, f), tb = mixf(md.tAb, md.tBb, f)
                    let l = sum / (tr + tg + tb + 1e-3)   // same total light, new colour
                    sm.r = mixf(sm.r, tr * l, monoAmt); sm.g = mixf(sm.g, tg * l, monoAmt); sm.b = mixf(sm.b, tb * l, monoAmt)
                }
                if introOn {
                    let s5 = seeds[i * 8 + 4], s6 = seeds[i * 8 + 5], s7 = seeds[i * 8 + 6], s8 = seeds[i * 8 + 7]
                    let e = clamp01((age - s6 * 2.4) / 2.6)
                    if e < 1 {
                        let ease = 1 - (1 - e) * (1 - e) * (1 - e)
                        let sx = (s7 * 2 - 1) * aspect * 1.5 + 0.2 * sinf(age * 0.7 + s5 * 9)
                        let sy = (s8 * 2 - 1) * 1.3 + 0.2 * cosf(age * 0.6 + s7 * 9)
                        let sz = (s5 - 0.5) * 2.2
                        sm.x = mixf(sx, sm.x, ease); sm.y = mixf(sy, sm.y, ease); sm.z = mixf(sz, sm.z, ease)
                        let fadeIn = e * (0.35 + 0.65 * e)
                        sm.r *= fadeIn; sm.g *= fadeIn; sm.b *= fadeIn
                    }
                }
                let dz = camD - sm.z
                if i < nodeCount { nodeX[i] = sm.x; nodeY[i] = sm.y; nodeZ[i] = dz < 0.4 ? 1e9 : sm.z }
                if dz < 0.4 { curX[i] = -1e9; curY[i] = -1e9; continue }
                dotSize[i] = sm.size * sizeScale
                let ps = camD / dz
                var sx = cxp + sm.x * ps * halfH
                var sy = cyp + sm.y * ps * halfH
                var depthLight = min(ps, 1.6)
                if stirCount > 0 {
                    // Pushed aside and swirled around the pointer or a finger, and by its lagging wake.
                    for k in 0..<stirCount {
                        let q = stirs[k]
                        let ddx = sx - q.x, ddy = sy - q.y
                        let d2 = ddx * ddx + ddy * ddy
                        if d2 < reach2 {
                            let g = expf(-d2 * inv2s2)
                            let f = g * q.amt
                            // Outward push that is zero at the centre and peaks one "sigma" out,
                            // so dots thin out gently instead of leaving a hole with a rim.
                            let push = f * 1.2 * (0.7 + 0.6 * s3) * q.push
                            // A swirl: turn around the pointer, most near the middle.
                            let turn = f * 1.05 * (0.5 + s2) * (s4 < 0.5 ? 1 : -1) * q.turn
                            sx += ddx * push - ddy * turn
                            sy += ddy * push + ddx * turn
                            depthLight *= 1 + 0.9 * f
                        }
                    }
                }
                curX[i] = sx
                curY[i] = sy
                col[i * 3] = sm.r * depthLight
                col[i * 3 + 1] = sm.g * depthLight
                col[i * 3 + 2] = sm.b * depthLight
            }
        }

        // 2. Splat each dot as a short streak from where it was to where it is.
        let lookA = cur.look
        var fade = lookA.fade, gain = lookA.gain
        if let p = prev {
            let lb = p.look
            fade = mixf(lb.fade, fade, w); gain = mixf(lb.gain, gain, w)
        }
        // Longer trails keep light on screen longer; dim each dot to match.
        let trailFade = min(powf(fade, 1 / md.trail), 0.965)
        gain *= min(max((1 - trailFade) / (1 - fade), 0.3), 1.4)
        fade = trailFade
        // Falling characters need short trails or they smear into bars.
        if cipherAmt > 0 { fade = mixf(fade, min(fade, 0.82), cipherAmt) }
        let base = gain * Float(width * height) / Float(n) * 0.035
        let streak = md.streak
        let W = width, H = height
        let maxJump = Float(H) * 0.08
        let firstFrame = freshTrails
        freshTrails = false
        // Network lines: how strong, and how near two dots must be to join.
        let la = cur.lines
        var lineAmt = la.amount, reach = la.reach
        if let p = prev {
            let lb = p.lines
            lineAmt = mixf(lb.amount, lineAmt, w); reach = mixf(lb.reach, reach, w)
        }
        lineAmt = min(lineAmt + md.lines, 2)
        let nodeR = 1.5 * Float(H) / 768
        if let gpu = gpu {
            // The same dots, handed to the graphics chip as points, streaks and round lights.
            gpu.begin()
            if let out = gpu.dots {
                var k = 0
                for i in 0..<n {
                    let x1 = curX[i], y1 = curY[i]
                    if x1 < -1e8 { prevX[i] = -1e9; continue }
                    var r = col[i * 3] * base, g = col[i * 3 + 1] * base, b = col[i * 3 + 2] * base
                    let x0 = prevX[i], y0 = prevY[i]
                    prevX[i] = x1; prevY[i] = y1
                    if i < nodeCount && lineAmt > 0.05 {
                        let mx = max(r, g, b, 1e-4)
                        let s = base * (1.5 + 3 * lineAmt) / mx
                        out[k] = GPUDot(x0: x1, y0: y1, x1: x1, y1: y1, r: r * s, g: g * s, b: b * s,
                                        kind: min(max(nodeR, 0.8), 8))
                        k += 1
                        continue
                    }
                    let sz = dotSize[i]
                    if sz > 0.3 {
                        r *= 2.5; g *= 2.5; b *= 2.5
                        out[k] = GPUDot(x0: x1, y0: y1, x1: x1, y1: y1, r: r, g: g, b: b, kind: min(max(sz, 0.8), 8))
                        k += 1
                        continue
                    }
                    let mx = x1 - x0, my = y1 - y0
                    let len = sqrtf(mx * mx + my * my)
                    if firstFrame || x0 < -1e8 || len > maxJump || len < 1 {
                        out[k] = GPUDot(x0: x1, y0: y1, x1: x1, y1: y1, r: r, g: g, b: b, kind: 0)
                    } else {
                        let L = streak * (0.55 + 0.9 * seeds[i * 8 + 6])
                        out[k] = GPUDot(x0: x1 - mx * L, y0: y1 - my * L, x1: x1, y1: y1,
                                        r: r * 1.6, g: g * 1.6, b: b * 1.6, kind: 0)
                    }
                    k += 1
                }
                gpu.dotCount = k
            }
        } else {
        for i in 0..<n {
            let x1 = curX[i], y1 = curY[i]
            if x1 < -1e8 { prevX[i] = -1e9; continue }
            var r = col[i * 3] * base, g = col[i * 3 + 1] * base, b = col[i * 3 + 2] * base
            let x0 = prevX[i], y0 = prevY[i]
            prevX[i] = x1; prevY[i] = y1
            if i < nodeCount && lineAmt > 0.05 {
                // Network nodes show as small bright beads.
                let mx = max(r, g, b, 1e-4)
                let k = base * (1.5 + 3 * lineAmt) / mx
                splatDisk(acc, W, H, x1, y1, nodeR, r * k, g * k, b * k)
                continue
            }
            let sz = dotSize[i]
            if sz > 0.3 {
                r *= 2.5; g *= 2.5; b *= 2.5
                splatDisk(acc, W, H, x1, y1, sz, r, g, b)
                continue
            }
            let mx = x1 - x0, my = y1 - y0
            let len = sqrtf(mx * mx + my * my)
            if firstFrame || x0 < -1e8 || len > maxJump || len < 1 {
                splat(acc, W, H, x1, y1, r, g, b)
            } else {
                // Each dot has its own streak length, scaled by the mood.
                let L = streak * (0.55 + 0.9 * seeds[i * 8 + 6])
                let dx = mx * L, dy = my * L
                let sx = x1 - dx, sy = y1 - dy
                let steps = Int(min(len * L, 40)) + 1
                let inv = 1 / Float(steps)
                let sr = r * inv * 1.6, sg = g * inv * 1.6, sb = b * inv * 1.6
                for s in 1...steps {
                    let f = Float(s) * inv
                    splat(acc, W, H, sx + dx * f, sy + dy * f, sr, sg, sb)
                }
            }
        }
        }

        // 2b. Lines between nearby network nodes.
        if lineAmt > 0.05 {
            drawLinks(acc, W, H, reach: reach, amount: lineAmt, base: base, gpu: gpu)
        }

        // 2c. Cipherfall: the falling dot-matrix characters.
        if cipherAmt > 0.002 {
            let hold = 1 - powf(fade, Float(dt * 60))
            if let gpu = gpu {
                emitCipherfall(gpu, W, H, t: t, amount: smooth(cipherAmt), hold: hold)
            } else {
                drawCipherfall(acc, W, H, t: t, amount: smooth(cipherAmt), hold: hold, threads: maxThreads)
            }
        }

        // 2d. Iridescent glass: smooth petals drawn as a mesh of triangles.
        let prismAmt: Float = cur == .prism ? (prev == nil ? 1 : w) : (prev == .prism ? 1 - w : 0)
        if prismAmt > 0.002 {
            let hold = 1 - powf(fade, Float(dt * 60))
            if let gpu = gpu {
                if let out = gpu.tris {
                    gpu.triCount = prismMesh(W, H, t: t, amount: smooth(prismAmt), hold: hold, into: out, capacity: gpu.triCapacity)
                }
            } else {
                if prismScratch == nil { prismScratch = .allocate(capacity: prismVertexCount) }
                if let buf = prismScratch {
                    let n = prismMesh(W, H, t: t, amount: smooth(prismAmt), hold: hold, into: buf, capacity: prismVertexCount)
                    rasterPrism(acc, W, H, buf, n, threads: maxThreads)
                }
            }
        }

        // 3. Glow, tone mapping and fading.
        var glowAmt = lookA.glow
        if let p = prev { glowAmt = mixf(p.look.glow, glowAmt, w) }
        glowLevel = mixf(glowLevel, glowEnabled ? 1 : 0, Float(1 - exp(-dt / 0.35)))
        if !glowEnabled && glowLevel < 0.004 { glowLevel = 0 }
        glowAmt *= md.glow * glowLevel
        // The flow patterns' own background colour, fading in and out with them.
        let prevFlow = prev?.isFlow ?? false
        let flowAmt: Float = cur.isFlow ? (prev == nil || prevFlow ? 1 : w) : (prevFlow ? 1 - w : 0)
        let bg = particleFlow.backgroundLight(exposure: md.exposure)
        let hz = (md.haze * md.tAr * keepMood + bg.0 * flowAmt, md.haze * md.tAg * keepMood + bg.1 * flowAmt,
                  md.haze * md.tAb * keepMood + bg.2 * flowAmt)
        if let gpu = gpu {
            gpu.commit(fade: powf(fade, Float(dt * 60)), glowK: glowAmt * 1.4, exposure: md.exposure,
                       haze: hz, bleach: min(md.glow, 1))
            return
        }
        if glowLevel > 0 { buildGlow() }
        compose(fade: powf(fade, Float(dt * 60)), glow: glowAmt, exposure: md.exposure,
                haze: hz, bleach: min(md.glow, 1))
    }

    /// The lively layer on top of every pattern: a heartbeat that swells and
    /// brightens the shape in a wave from the middle, rippling oscillations,
    /// each dot's own wobble and twinkle, and now and then a dot that breaks
    /// away like a campfire spark, rises, flickers, cools and fades.
    @inline(__always)
    static func enliven(_ sm: inout Sample, _ cur: Pattern, _ i: Int,
                        _ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float,
                        _ s5: Float, _ s6: Float, _ s7: Float, _ s8: Float,
                        _ t: Float, _ aspect: Float, _ live: Float, _ md: Mood, _ wob: Float) {
        // Sparks first: a dot on its spark run leaves the formation entirely.
        let period = 4 + 9 * s5
        let local = t + s6 * period
        let cycle = floorf(local / period)
        let tau = local - cycle * period
        let dur = 1.0 + 1.8 * s7
        if tau < dur + 0.7 {
            let t0 = t - tau
            let burst = max(smooth(sinf(t0 * TAU / 13 - 2.2) * 3 - 2),
                            smooth(sinf(t0 * TAU / 29 + 0.4) * 3 - 2.2))
            let rate = live * md.sparks * (0.012 + 0.07 * burst)
            let key = UInt32(truncatingIfNeeded: i) &* 0x2545_F491 ^ UInt32(truncatingIfNeeded: Int(cycle) & 0xFFFFF) &* 0x27D4_EB2F
            if hashU(key) < rate {
                let kindRoll = hashU(key &+ 77)
                if kindRoll >= 0.72 {
                    // A swirl-away: loops out from the formation and comes back home.
                    let d = dur * 1.2
                    if tau < d {
                        let h1 = hashU(key &+ 11), h2 = hashU(key &+ 23), h3 = hashU(key &+ 37)
                        let bl = sqrtf(sm.x * sm.x + sm.y * sm.y + sm.z * sm.z) + 0.05
                        var ox = sm.x / bl + (h1 - 0.5) * 1.4
                        var oy = sm.y / bl + (h2 - 0.5) * 1.4
                        var oz = sm.z / bl + (h3 - 0.5) * 1.4
                        let ol = sqrtf(ox * ox + oy * oy + oz * oz) + 1e-4
                        ox /= ol; oy /= ol; oz /= ol
                        let u = tau / d
                        let out = sinf(Float.pi * u) * (0.25 + 0.45 * h3)
                        let loop = sinf(TAU * u) * out * 0.8
                        sm.x += ox * out + oz * loop
                        sm.y += oy * out
                        sm.z += oz * out - ox * loop
                        let k = 1 + 1.6 * sinf(Float.pi * u)
                        sm.r = (sm.r + 0.15) * k; sm.g = (sm.g + 0.15) * k; sm.b = (sm.b + 0.15) * k
                        return
                    }
                } else if tau >= dur {
                    // Back in the formation: fade in gently.
                    let f = smooth((tau - dur) / 0.7)
                    sm.r *= f; sm.g *= f; sm.b *= f
                } else {
                    let base = samplePattern(cur, s1, s2, s3, s4, t0, aspect)
                    let h1 = hashU(key &+ 11), h2 = hashU(key &+ 23), h3 = hashU(key &+ 37), h4 = hashU(key &+ 51)
                    let bl = sqrtf(base.x * base.x + base.y * base.y + base.z * base.z) + 0.05
                    var dx = base.x / bl * 0.7 + (h1 - 0.5) * 1.6
                    var dy = base.y / bl * 0.7 + (h2 - 0.5) * 1.2 + 0.7
                    var dz = base.z / bl * 0.7 + (h3 - 0.5) * 1.6
                    let dl = sqrtf(dx * dx + dy * dy + dz * dz) + 1e-4
                    let v = 0.45 + 0.95 * h4
                    dx = dx / dl * v; dy = dy / dl * v; dz = dz / dl * v
                    if kindRoll >= 0.48 {
                        // A comet: a fast straight shot in the dot's own colour, with a long tail.
                        let u = tau / dur
                        let go = (1.4 + 1.6 * h4) * tau
                        sm.x = base.x + dx / v * go
                        sm.y = base.y + (dy / v - 0.35) * go
                        sm.z = base.z + dz / v * go
                        let k = 4.5 * powf(1 - u, 1.3) * smooth(tau * 10)
                        sm.r = (base.r * 1.3 + 0.12) * k; sm.g = (base.g * 1.3 + 0.12) * k; sm.b = (base.b * 1.3 + 0.12) * k
                        return
                    }
                    let travel = (1 - expf(-tau * 1.7)) / 1.7
                    let swirl = 0.03 * tau
                    sm.x = base.x + dx * travel + swirl * sinf(tau * 3.5 + h1 * TAU)
                    sm.y = base.y + dy * travel + 0.16 * tau * tau
                    sm.z = base.z + dz * travel + swirl * cosf(tau * 3 + h2 * TAU)
                    let heat = 1 - tau / dur
                    let flick = 0.6 + 0.4 * sinf(tau * 31 + h3 * 50) * sinf(tau * 13 + h4 * 20)
                    let cool = smooth(1 - heat)
                    // White-hot with a hint of the dot's own colour, cooling to ember orange.
                    let hr = mixf(0.55 + base.r * 0.6, 1.0, cool)
                    let hg = mixf(0.50 + base.g * 0.6, 0.55, cool)
                    let hb = mixf(0.45 + base.b * 0.6, 0.16, cool)
                    let k = 9.0 * powf(heat, 1.4) * flick * smooth(tau * 8)
                    sm.r = hr * k; sm.g = hg * k; sm.b = hb * k
                    return
                }
            }
        }
        // Heartbeat: a swell and a flash that travel outwards from the middle.
        let rad = sqrtf(sm.x * sm.x + sm.y * sm.y + sm.z * sm.z)
        let ph = fract((t - rad * 0.55) / BEAT)
        let pulse = expf(-ph * 5) * smooth(ph * 25)
        let breathe = 1 + live * (0.028 * pulse + 0.018 * sinf(t * 0.52))
        // Rippling oscillation, its strength rising and falling slowly.
        let ripple = live * wob * 0.016 * sinf(rad * 11 - t * 3.1) * (0.6 + 0.4 * sinf(t * 0.31))
        let f = breathe + ripple
        sm.x *= f; sm.y *= f; sm.z *= f
        // Each dot's own wandering wobble.
        let amp = live * wob * md.fuzz * 0.013 * (0.3 + 1.4 * s5 * s5)
        let sc = live * wob * md.scatter
        sm.x += sc * (s6 - 0.5) * 2; sm.y += sc * (s8 - 0.5) * 2; sm.z += sc * (s7 - 0.5) * 2
        sm.x += amp * sinf(t * (0.8 + 2.4 * s6) + s7 * TAU)
        sm.y += amp * sinf(t * (0.7 + 2.1 * s8) + s5 * TAU)
        sm.z += amp * sinf(t * (0.9 + 1.9 * s7) + s6 * TAU)
        // Twinkle and the heartbeat's flash.
        let tw = max(0, sinf(t * (1.3 + 3.2 * s8) + s6 * TAU * 3))
        let tw2 = tw * tw; let tw6 = tw2 * tw2 * tw2
        let b = 1 + live * (0.38 * pulse + 1.3 * md.twinkle * tw6 * s7 - 0.12)
        sm.r *= b; sm.g *= b; sm.b *= b
    }

    /// Joins network nodes that are near each other in 3-D with faint lines,
    /// brighter the closer they are; each node keeps only a handful of links.
    private func drawLinks(_ acc: UnsafeMutablePointer<Float>!, _ W: Int, _ H: Int,
                           reach: Float, amount: Float, base: Float, gpu: GPURenderer?) {
        let m = nodeCount
        nodeLinks.initialize(repeating: 0, count: m)
        let r2 = reach * reach
        let k = base * 0.22 * amount
        let maxLinks: Int32 = 6
        for i in 0..<m {
            let zi = nodeZ[i]
            if zi > 1e8 || curX[i] < -1e8 || nodeLinks[i] >= maxLinks { continue }
            let xi = nodeX[i], yi = nodeY[i]
            if i + 1 >= m { break }
            for j in (i + 1)..<m where nodeLinks[j] < maxLinks {
                let dx = nodeX[j] - xi, dy = nodeY[j] - yi, dz = nodeZ[j] - zi
                let d2 = dx * dx + dy * dy + dz * dz
                if d2 >= r2 || curX[j] < -1e8 { continue }
                let a = 1 - sqrtf(d2) / reach
                // Lines keep the dots' hue but their own steady brightness.
                var cr = col[i * 3] + col[j * 3], cg = col[i * 3 + 1] + col[j * 3 + 1], cb = col[i * 3 + 2] + col[j * 3 + 2]
                let mx = max(cr, cg, cb, 1e-3)
                let s = a * k / mx
                cr *= s; cg *= s; cb *= s
                let x0 = curX[i], y0 = curY[i]
                let lx = curX[j] - x0, ly = curY[j] - y0
                let len = sqrtf(lx * lx + ly * ly)
                let steps = Int(min(len, 900))
                if steps < 1 { continue }
                if let gpu = gpu {
                    // One line carrying the light of all the points along it.
                    let total = Float(steps + 1)
                    gpu.add(GPUDot(x0: x0, y0: y0, x1: x0 + lx, y1: y0 + ly,
                                   r: cr * total, g: cg * total, b: cb * total, kind: 0))
                } else {
                    let inv = 1 / Float(steps)
                    for st in 0...steps {
                        let f = Float(st) * inv
                        splat(acc, W, H, x0 + lx * f, y0 + ly * f, cr, cg, cb)
                    }
                }
                nodeLinks[i] += 1; nodeLinks[j] += 1
                if nodeLinks[i] >= maxLinks { break }
            }
        }
    }

    /// A soft round light of radius `rad` pixels with the given total light.
    @inline(__always)
    private func splatDisk(_ acc: UnsafeMutablePointer<Float>, _ W: Int, _ H: Int,
                           _ x: Float, _ y: Float, _ rad: Float, _ r: Float, _ g: Float, _ b: Float) {
        let R = min(max(rad, 0.8), 8)
        let ir = Int(ceilf(R))
        let cx = Int(x), cy = Int(y)
        if cx - ir < 0 || cy - ir < 0 || cx + ir >= W || cy + ir >= H { return }
        let norm = 1 / (Float.pi * R * R * 0.5)
        for yy in -ir...ir {
            for xx in -ir...ir {
                let ddx = Float(cx + xx) + 0.5 - x, ddy = Float(cy + yy) + 0.5 - y
                let wgt = 1 - (ddx * ddx + ddy * ddy) / (R * R)
                if wgt <= 0 { continue }
                let p = ((cy + yy) * W + cx + xx) * 3
                let q = wgt * norm
                acc[p] += r * q; acc[p + 1] += g * q; acc[p + 2] += b * q
            }
        }
    }

    @inline(__always)
    private func splat(_ acc: UnsafeMutablePointer<Float>, _ W: Int, _ H: Int,
                       _ x: Float, _ y: Float, _ r: Float, _ g: Float, _ b: Float) {
        let fx = x - 0.5, fy = y - 0.5
        if fx < 0 || fy < 0 { return }
        let ix = Int(fx), iy = Int(fy)
        if ix >= W - 1 || iy >= H - 1 { return }
        let ax = fx - Float(ix), ay = fy - Float(iy)
        let w00 = (1 - ax) * (1 - ay), w10 = ax * (1 - ay), w01 = (1 - ax) * ay, w11 = ax * ay
        var p = (iy * W + ix) * 3
        acc[p] += r * w00; acc[p + 1] += g * w00; acc[p + 2] += b * w00
        acc[p + 3] += r * w10; acc[p + 4] += g * w10; acc[p + 5] += b * w10
        p += W * 3
        acc[p] += r * w01; acc[p + 1] += g * w01; acc[p + 2] += b * w01
        acc[p + 3] += r * w11; acc[p + 4] += g * w11; acc[p + 5] += b * w11
    }

    private func buildGlow() {
        guard let acc = acc, let small = small, let tmp = smallTmp else { return }
        let W = width, sw = sw, sh = sh
        // Downsample 4x4 blocks.
        parallel(sh) { sy in
            for sx in 0..<sw {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for yy in 0..<4 {
                    var p = ((sy * 4 + yy) * W + sx * 4) * 3
                    for _ in 0..<4 {
                        r += acc[p]; g += acc[p + 1]; b += acc[p + 2]; p += 3
                    }
                }
                let o = (sy * sw + sx) * 3
                small[o] = r / 16; small[o + 1] = g / 16; small[o + 2] = b / 16
            }
        }
        // Two separable box blurs ≈ a soft gaussian.
        for _ in 0..<2 {
            boxBlur(src: small, dst: tmp, w: sw, h: sh, horizontal: true, radius: 3)
            boxBlur(src: tmp, dst: small, w: sw, h: sh, horizontal: false, radius: 3)
        }
    }

    private func boxBlur(src: UnsafeMutablePointer<Float>, dst: UnsafeMutablePointer<Float>,
                         w: Int, h: Int, horizontal: Bool, radius: Int) {
        let lines = horizontal ? h : w
        let length = horizontal ? w : h
        let stride = horizontal ? 3 : w * 3
        let norm = 1 / Float(radius * 2 + 1)
        parallel(lines) { line in
            let start = horizontal ? line * w * 3 : line * 3
            var r: Float = 0, g: Float = 0, b: Float = 0
            for k in -radius...radius {
                let j = min(max(k, 0), length - 1)
                let p = start + j * stride
                r += src[p]; g += src[p + 1]; b += src[p + 2]
            }
            for i in 0..<length {
                let o = start + i * stride
                dst[o] = r * norm; dst[o + 1] = g * norm; dst[o + 2] = b * norm
                let add = start + min(i + radius + 1, length - 1) * stride
                let rem = start + max(i - radius, 0) * stride
                r += src[add] - src[rem]; g += src[add + 1] - src[rem + 1]; b += src[add + 2] - src[rem + 2]
            }
        }
    }

    private func compose(fade: Float, glow: Float, exposure: Float, haze: (Float, Float, Float), bleach: Float) {
        guard let acc = acc, let small = small, let pixels = pixels else { return }
        let W = width, H = height, sw = sw, sh = sh
        let glowK = glow * 1.4
        parallel(H) { y in
            let gy = (Float(y) + 0.5) / 4 - 0.5
            let gy0 = min(max(Int(floorf(gy)), 0), sh - 1)
            let gy1 = min(gy0 + 1, sh - 1)
            let ay = clamp01(gy - Float(gy0))
            var p = y * W * 3
            // Image rows go top-down; our y axis goes up, so flip.
            var o = (H - 1 - y) * W
            for x in 0..<W {
                let gx = (Float(x) + 0.5) / 4 - 0.5
                let gx0 = min(max(Int(gx), 0), sw - 1)
                let gx1 = min(gx0 + 1, sw - 1)
                let ax = clamp01(gx - Float(gx0))
                let i00 = (gy0 * sw + gx0) * 3, i10 = (gy0 * sw + gx1) * 3
                let i01 = (gy1 * sw + gx0) * 3, i11 = (gy1 * sw + gx1) * 3
                let w00 = (1 - ax) * (1 - ay), w10 = ax * (1 - ay), w01 = (1 - ax) * ay, w11 = ax * ay
                var r = acc[p] + glowK * (small[i00] * w00 + small[i10] * w10 + small[i01] * w01 + small[i11] * w11)
                var g = acc[p + 1] + glowK * (small[i00 + 1] * w00 + small[i10 + 1] * w10 + small[i01 + 1] * w01 + small[i11 + 1] * w11)
                var b = acc[p + 2] + glowK * (small[i00 + 2] * w00 + small[i10 + 2] * w10 + small[i01 + 2] * w01 + small[i11 + 2] * w11)
                acc[p] *= fade; acc[p + 1] *= fade; acc[p + 2] *= fade
                // Bright light bleeds towards white.
                r += haze.0; g += haze.1; b += haze.2
                let m = (r + g + b) * 0.333
                let wb = m * m * 0.12 * bleach
                r = (r + wb) * exposure; g = (g + wb) * exposure; b = (b + wb) * exposure
                let R = UInt32(255 * (1 - expf(-r)))
                let G = UInt32(255 * (1 - expf(-g)))
                let B = UInt32(255 * (1 - expf(-b)))
                pixels[o] = 0xFF00_0000 | (B << 16) | (G << 8) | R
                p += 3; o += 1
            }
        }
    }

    func makeImage() -> CGImage? { gpu?.snapshot() ?? context?.makeImage() }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextFloat() -> Float { Float(next() >> 40) / Float(1 << 24) }
}
