import Foundation

// Abstract and "neural network" formations: a plexus cloud and globe (their
// nodes are joined by lines in the engine), a dotted data sphere over a grid,
// a data tunnel, twisting wire-like meshes and a two-tone nebula. They use
// calmer single colours and less glow than the classic patterns.

@inline(__always) func cellFlicker(_ cell: Int, _ t: Float, _ rate: Float, _ on: Float) -> Float {
    let ph = hashU(UInt32(truncatingIfNeeded: cell) &* 0x2C1B_3C6D)
    let tick = Int(floorf(t * rate + ph * 7))
    return hashU(UInt32(truncatingIfNeeded: cell &* 7919 &+ tick &* 104_729)) < on ? 1 : 0
}

/// A neural-network cloud: a dense glowing cluster with sparse nodes around
/// it; waves of "firing" run outwards through it.
func network(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let a = TAU * s1
    let cz = 2 * s2 - 1
    let sq = sqrtf(max(0, 1 - cz * cz))
    let core = s4 < 0.78
    let r0: Float = core ? min(sqrtf(-2 * logf(s3 * 0.999 + 0.001)) * 0.30, 1.15) : 0.7 + 0.95 * s3
    let r = r0 * (1 + 0.05 * sinf(t * 0.4 + s1 * 20 + s3 * 7))
    var x = r * sq * cosf(a), y = r * cz * 0.92, z = r * sq * sinf(a)
    rotY(&x, &z, t * 0.07)
    rotX(&y, &z, 0.3 * sinf(t * 0.05))
    let fire = smooth(0.5 + 0.8 * sinf(r0 * 13 - t * 2.0 + s2 * 2))
    let hot = smooth(1 - r0 * 1.6)
    let k: Float = core ? (0.22 + 0.45 * fire) * (1.15 - 0.5 * min(r0, 1)) : 0.28 + 0.25 * fire
    return Sample(x: x, y: y, z: z,
                  r: mixf(0.18, 0.70, hot) * k, g: mixf(0.85, 1.0, hot) * k, b: mixf(0.62, 0.92, hot) * k)
}

/// A globe of linked nodes, lit from the sides: green on one edge, violet on
/// the other, with dust blowing off its rims.
func globe(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    let R: Float = 0.82
    let a = TAU * s1
    let cz = 2 * s2 - 1
    let sq = sqrtf(max(0, 1 - cz * cz))
    var r: Float
    var kind = 0
    if s4 < 0.62 { r = R * (1 + 0.008 * sinf(a * 5 + cz * 7 + t)) }
    else if s4 < 0.8 { r = R * cbrtf(s3) * 0.95; kind = 1 }
    else { r = R * (1.0 + 0.3 * s3 * s3); kind = 2 }
    var x = r * sq * cosf(a), y = r * cz, z = r * sq * sinf(a)
    rotY(&x, &z, t * 0.11)
    rotX(&y, &z, 0.35)
    let nz = min(fabsf(z) / max(r, 0.05), 1)
    let edge = (1 - nz) * (1 - nz)
    let side = smooth(0.5 + x / R * 0.9)
    let cr = mixf(0.30, 0.70, side), cg = mixf(1.0, 0.42, side), cb = mixf(0.62, 1.0, side)
    var k: Float
    switch kind {
    case 0: k = 0.10 + 1.0 * edge * edge + (z > 0 ? 0.08 : 0)
    case 1: k = 0.06
    default: k = 0.35 * (1 - s3) * edge * smooth(fabsf(x) / R * 1.3 - 0.35)
    }
    return Sample(x: x, y: y, z: z, r: cr * k, g: cg * k, b: cb * k)
}

/// A dotted wireframe sphere whose points blink like data, over a grid of
/// dots with falling "rain".
func lattice(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    if s4 < 0.62 {
        let R: Float = 0.78
        var lat: Float, lon: Float, cell: Int
        if s3 < 0.5 {
            let ri = floorf(s1 * 18), li = floorf(s2 * 90)
            lat = (ri + 0.5) / 18 * Float.pi
            lon = (li + 0.5) / 90 * TAU
            cell = Int(ri) * 90 + Int(li)
        } else {
            let mi = floorf(s2 * 36), li = floorf(s1 * 45)
            lon = mi / 36 * TAU
            lat = (li + 0.5) / 45 * Float.pi
            cell = 5000 + Int(mi) * 45 + Int(li)
        }
        let j = (s3 - 0.5) * 0.004
        let sl = sinf(lat + j)
        var x = R * sl * cosf(lon + t * 0.0), y = R * cosf(lat + j), z = R * sl * sinf(lon)
        rotY(&x, &z, t * 0.14)
        rotX(&y, &z, 0.4 + 0.1 * sinf(t * 0.07))
        let on = cellFlicker(cell, t, 2.5, 0.6)
        let k = (0.10 + 0.55 * on) * (z > 0 ? 1 : 0.4)
        return Sample(x: x, y: y, z: z, r: 0.55 * k, g: 1.0 * k, b: 0.9 * k)
    }
    let ci = floorf(s1 * 100), ri = floorf(s2 * 58)
    let gx = (ci + 0.5) / 100 * 2 - 1, gy = (ri + 0.5) / 58 * 2 - 1
    let x = gx * 1.9 * min(aspect, 1.8), y = gy * 1.55, z: Float = -1.4
    let h = hash1(ci * 1.37)
    let rain = powf(fract(-gy * 0.7 + t * 0.22 * (0.5 + h) + h * 3), 8)
    let k = 0.035 + 0.45 * rain * (h > 0.45 ? 1 : 0.2)
    return Sample(x: x, y: y, z: z, r: 0.35 * k, g: 0.95 * k, b: 0.7 * k)
}

/// Columns of data dots streaming out of a square tunnel towards you.
func tunnel(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float) -> Sample {
    if s4 < 0.84 {
        let ci = floorf(s1 * 48)
        let layer = floorf(s3 * 3)
        let a = (ci + 0.5) / 48 * TAU
        let sq = 1 / max(fabsf(cosf(a)), fabsf(sinf(a)))
        let R = 0.55 * sq * (1 + layer * 0.4)
        let speed = 0.10 * (0.6 + 0.8 * hash1(ci * 1.3 + layer * 5.1))
        let u = fract(floorf(s2 * 36) / 36 + t * speed)
        let x = R * cosf(a), y = R * sinf(a)
        let z = -7 + u * 9.7
        let col = Int(ci) * 3 + Int(layer)
        let on = cellFlicker(col, t, 1.5, 0.55)
        let k = (0.08 + 0.55 * on) * smooth(u * 4) * smooth((1 - u) * 10)
        var sm = Sample(x: x, y: y, z: z, r: 0.30 * k, g: 1.0 * k, b: 0.45 * k)
        if s3 > 0.95 { sm.size = 1.2 + 2 * s4 }
        return sm
    }
    let a = TAU * s1, cz = 2 * s2 - 1, sq = sqrtf(max(0, 1 - cz * cz))
    let r = 0.3 * cbrtf(s3)
    let x = r * sq * cosf(a + t * 0.3), y = r * cz, z = -4 + r * sq * sinf(a)
    let k = 0.25 + 0.4 * cellFlicker(Int(s3 * 4000), t, 4, 0.5)
    return Sample(x: x, y: y, z: z, r: 0.55 * k, g: 1.0 * k, b: 0.6 * k)
}

/// Two twisting sheets of fine wire-like dots that pinch together in the
/// middle and ripple like cloth.
func mesh(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    var u = s1 * 2 - 1, v = s2 * 2 - 1
    if s4 < 0.5 { v = (floorf(s2 * 26) + 0.5) / 26 * 2 - 1 } else { u = (floorf(s1 * 46) + 0.5) / 46 * 2 - 1 }
    let au = fabsf(u)
    let w = 0.04 + 0.95 * powf(au, 1.15)
    var y = v * w + 0.10 * sinf(u * 5 + v * 3 + t * 0.7) * (0.2 + au) + 0.05 * sinf(v * 9 - t * 0.9 + u * 3)
    var z = 0.25 * sinf(u * 3 + v * 4 + t * 0.5) * au
    rotX(&y, &z, u * 2.0 + t * 0.15 + 0.6 * sinf(t * 0.1))
    var x = u * min(aspect, 1.8) * 1.15 + 0.03 * sinf(v * 6 + t)
    rotY(&x, &z, 0.25 * sinf(t * 0.05))
    let ridge = smooth(0.5 + 0.9 * sinf(u * 6 + v * 5 + t * 0.8))
    let k = (0.12 + 0.45 * ridge) * (0.3 + 0.7 * smooth(au * 3)) + (s3 > 0.97 ? 0.3 : 0)
    return Sample(x: x, y: y, z: z, r: 0.30 * k, g: 0.95 * k, b: 0.95 * k)
}

/// A teal spiral nebula threaded with golden filaments, drifting dust and a
/// few soft out-of-focus lights.
func nebula(_ s1: Float, _ s2: Float, _ s3: Float, _ s4: Float, _ t: Float, _ aspect: Float) -> Sample {
    var sm: Sample
    if s4 < 0.5 {
        let r = 0.04 + 1.25 * powf(s1, 1.4)
        let arm = floorf(s3 * 3)
        let a = arm * TAU / 3 + r * 3.2 - t * 0.12 / (0.3 + r) + (s2 - 0.5) * (0.35 + 0.9 * r)
        var x = r * cosf(a) * 1.15, y = r * sinf(a) * 0.8
        var z = (s2 - 0.5) * 0.15 + r * sinf(a) * 0.3
        rotY(&x, &z, 0.2 * sinf(t * 0.04))
        rotX(&y, &z, 0.15)
        let ring: Float = r < 0.13 ? 1.6 : 1
        let fall: Float = 0.45 + 0.8 * (1 - min(r, 1))
        let k: Float = 0.30 * fall * ring
        sm = Sample(x: x, y: y, z: z, r: 0.22 * k, g: 0.95 * k, b: 0.85 * k)
    } else if s4 < 0.74 {
        let id = floorf(s2 * 6)
        let u = fract(s1 + t * 0.025 * (Int(id) % 2 == 0 ? 1 : -1))
        let x = (u * 2 - 1) * min(aspect, 1.8) * 1.2
        let off = (s3 - 0.5)
        let wave1: Float = 0.28 * sinf(u * 4.5 + id * 1.9 + t * 0.25)
        let wave2: Float = 0.12 * sinf(u * 11 + id * 0.7 - t * 0.4)
        let y: Float = (id - 2.5) * 0.22 + wave1 + wave2 + off * off * off * 0.25
        let z = 0.3 * sinf(u * 3 + id) + off * 0.05
        let k = 0.8 * (0.25 + 0.75 * smooth(0.5 + sinf(u * 7 + id * 2 + t * 0.6))) * max(0, 1 - 1.8 * fabsf(off))
        sm = Sample(x: x, y: y, z: z, r: 1.0 * k, g: 0.82 * k, b: 0.32 * k)
    } else {
        let x = (s1 * 2 - 1) * min(aspect, 1.8) * 1.4 + 0.04 * sinf(t * 0.1 + s3 * 20)
        let y = (s2 * 2 - 1) * 1.3 + 0.05 * sinf(t * 0.2 + s1 * 9)
        let z = (s3 - 0.5) * 2 - 0.3
        let gold = s3 < 0.5
        let k: Float = 0.22
        sm = Sample(x: x, y: y, z: z, r: (gold ? 1.0 : 0.25) * k, g: (gold ? 0.8 : 0.95) * k, b: (gold ? 0.3 : 0.85) * k)
        if s4 > 0.975 { sm.size = 1.3 + 2.2 * s3; sm.r *= 1.6; sm.g *= 1.6; sm.b *= 1.6 }
    }
    return sm
}
