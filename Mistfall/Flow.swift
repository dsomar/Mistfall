import Foundation

// Flow: dots that really move. Every other pattern places each dot by formula;
// here each dot has a position and a speed, and is pushed around by a handful
// of invisible forces, the way dots drift in a thick liquid. The settings are
// the classic ones: activity, turbulence, viscosity, complexity, confinement,
// influence range, wrap, reflections and symmetry, plus where new dots are born
// (the style), how the forces travel (the motion) and how their strength changes
// over time (the tempo). A fresh set of settings is rolled every time one of
// these patterns comes up, so it never looks the same twice.

@inline(__always) func flowHash(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
    var h = (a &* 0x9E37_79B1) ^ (b &* 0x85EB_CA77) ^ (c &* 0xC2B2_AE3D)
    h ^= h >> 15; h = h &* 0x2C1B_3C6D; h ^= h >> 12; h = h &* 0x297A_2D39; h ^= h >> 15
    return h
}
/// A repeatable random number from 0 up to (not including) 1.
@inline(__always) func flowUnit(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> Float {
    Float(flowHash(a, b, c) >> 8) / Float(1 << 24)
}

/// The "Particle Flow" settings the user can set for the flow patterns (Currents and
/// Kaleidoscope). Everything else about a flow is still rolled afresh each visit.
struct ParticleFlow: Equatable {
    enum Palette: String, CaseIterable {
        case auto, rainbow, ember, sunset, ocean, aurora, violet
        var title: String {
            switch self {
            case .auto: return "Different every time"
            case .rainbow: return "Rainbow"
            case .ember: return "Ember"
            case .sunset: return "Sunset"
            case .ocean: return "Ocean"
            case .aurora: return "Aurora"
            case .violet: return "Violet"
            }
        }
        /// Where on the colour wheel the dots start, and how far round they spread.
        var hues: (Float, Float)? {
            switch self {
            case .auto: return nil
            case .rainbow: return (0, 1)
            case .ember: return (0.98, 0.07)
            case .sunset: return (0.80, 0.22)
            case .ocean: return (0.50, 0.12)
            case .aurora: return (0.30, 0.20)
            case .violet: return (0.68, 0.14)
            }
        }
    }

    /// Share of the dots that are used, 0.1 to 1.
    var density = 1.0
    /// 1 = fine dots; more = soft round lights about this many pixels across.
    var size = 1.0
    /// Multiplies how hard the forces push.
    var strength = 1.0
    /// Multiplies how far each force reaches (bigger = broader, smoother flow).
    var scale = 1.0
    /// Background colour as six hex digits, "000000" = black.
    var background = "000000"
    var palette = Palette.auto
    /// 0 = a new flow every time; anything else always gives the same flow.
    var seed = 0

    static let densityRange = 0.1...1.0, sizeRange = 1.0...5.0
    static let strengthRange = 0.25...2.5, scaleRange = 0.4...2.5

    /// Tidies whatever was typed into six hex digits, or nil if it is not a colour.
    static func cleanHex(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { return nil }
        return t
    }

    /// The background as red, green and blue from 0 to 1.
    var backgroundRGB: (Float, Float, Float) {
        guard let h = ParticleFlow.cleanHex(background), let v = UInt32(h, radix: 16) else { return (0, 0, 0) }
        return (Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255)
    }

    /// How much light to add everywhere so an empty screen comes out the background colour.
    func backgroundLight(exposure: Float) -> (Float, Float, Float) {
        let c = backgroundRGB
        func light(_ v: Float) -> Float { v <= 0 ? 0 : -logf(1 - min(v, 0.97)) / max(exposure, 0.25) }
        return (light(c.0), light(c.1), light(c.2))
    }

    func clamped() -> ParticleFlow {
        func c(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }
        var p = self
        p.density = c(density, ParticleFlow.densityRange); p.size = c(size, ParticleFlow.sizeRange)
        p.strength = c(strength, ParticleFlow.strengthRange); p.scale = c(scale, ParticleFlow.scaleRange)
        p.background = ParticleFlow.cleanHex(background) ?? "000000"
        p.seed = min(max(seed, 0), 999_999_999)
        return p
    }

    /// Lays these choices over a freshly rolled flow.
    func apply(to s: inout FlowSettings) {
        s.density = Float(density)
        s.dotSize = size > 1.05 ? Float(size) : 0
        s.activity *= Float(strength)
        s.range *= Float(scale)
        if let h = palette.hues { s.hue = h.0; s.hueSpread = h.1 }
    }
}

struct FlowSettings {
    /// Where new dots are born.
    enum Style: Int, CaseIterable {
        case point, ring, line, spiral, scatter, cross, twin
        var title: String {
            switch self {
            case .point: return "Point"
            case .ring: return "Ring"
            case .line: return "Line"
            case .spiral: return "Spiral"
            case .scatter: return "Scatter"
            case .cross: return "Cross"
            case .twin: return "Twin jets"
            }
        }
    }
    /// How the forces travel around the screen.
    enum Motion: Int, CaseIterable {
        case still, linear, organic, recursive, circular, warp
        var title: String {
            switch self {
            case .still: return "Static"
            case .linear: return "Linear"
            case .organic: return "Organic"
            case .recursive: return "Recursive"
            case .circular: return "Circular"
            case .warp: return "Warp"
            }
        }
    }
    /// How the strength of the forces changes over time.
    enum Tempo: Int, CaseIterable {
        case natural, clockwork, waves, digital, directional
        var title: String {
            switch self {
            case .natural: return "Natural"
            case .clockwork: return "Clockwork"
            case .waves: return "Waves"
            case .digital: return "Digital"
            case .directional: return "Directional"
            }
        }
    }

    var reflections = 1          // 1 = none; more = that many turned copies
    var symmetric = false        // also mirror every copy
    var wrap = false             // dots leaving one side come back on the other
    var mobius = false           // ...and flip over as they do
    var activity: Float = 1      // how hard the forces push
    var turbulence: Float = 0.4  // how much the flow churns
    var viscosity: Float = 1.5   // how thick the liquid is
    var complexity = 4           // how many forces are at work
    var confinement: Float = 0.7 // how strongly dots are kept near the middle
    var range: Float = 0.9       // how far each force reaches
    var style = Style.point
    var motion = Motion.organic
    var tempo = Tempo.natural
    var twist = false            // extra small local swirls
    var pace: Float = 1          // how fast the forces move and change
    var life: Float = 6          // seconds a dot lasts
    var hue: Float = 0
    var hueSpread: Float = 0.3
    /// Moves the birthplace off-centre, so turned and mirrored copies make a figure
    /// instead of piling up in the middle.
    var offsetX: Float = 0
    var offsetY: Float = 0
    var seed: UInt32 = 1
    var density: Float = 1       // share of the dots in use
    var dotSize: Float = 0       // 0 = fine dots; more = round lights this many pixels across

    /// Rolls a fresh set of settings.
    static func random(_ rng: inout SplitMix, kaleidoscope: Bool) -> FlowSettings {
        func u() -> Float { rng.nextFloat() }
        func logRange(_ lo: Float, _ hi: Float) -> Float { lo * powf(hi / lo, u()) }
        var s = FlowSettings()
        s.seed = UInt32(truncatingIfNeeded: rng.next())
        if kaleidoscope {
            let choices = [3, 3, 4, 5, 6, 6, 8]
            s.reflections = choices[Int(u() * Float(choices.count)) % choices.count]
            s.symmetric = u() < 0.65
        } else {
            s.reflections = 1
            s.symmetric = u() < 0.2
            s.wrap = !s.symmetric && u() < 0.45
            s.mobius = s.wrap && u() < 0.35
        }
        s.activity = 0.55 + 0.95 * u()
        s.turbulence = u() * u() * 1.2
        s.viscosity = logRange(0.8, 4.5)
        // Hard pushing in a thin liquid is just snow: thicken it a little.
        if s.activity > 1.1 { s.viscosity = max(s.viscosity, 1.4) }
        s.complexity = 2 + Int(u() * 6) % 6
        s.confinement = 0.4 + 1.0 * u()
        s.range = logRange(0.4, 2.2)
        s.style = Style.allCases[Int(u() * Float(Style.allCases.count)) % Style.allCases.count]
        s.motion = Motion.allCases[Int(u() * Float(Motion.allCases.count)) % Motion.allCases.count]
        s.tempo = Tempo.allCases[Int(u() * Float(Tempo.allCases.count)) % Tempo.allCases.count]
        s.twist = u() < 0.4
        s.pace = logRange(0.45, 2.2)
        s.life = 4 + 5 * u()
        s.hue = u()
        s.hueSpread = 0.08 + 0.42 * u()
        if kaleidoscope {
            // A kaleidoscope needs a clear figure to repeat: calmer, thicker, held closer in,
            // born off-centre, and never born everywhere at once.
            s.turbulence = min(s.turbulence, 0.55)
            s.viscosity = max(s.viscosity, 1.3)
            s.confinement = max(s.confinement, 0.75)
            if s.style == .scatter { s.style = u() < 0.5 ? .spiral : .line }
            let a = TAU * u(), r = 0.2 + 0.3 * u()
            s.offsetX = cosf(a) * r; s.offsetY = sinf(a) * r
        }
        return s
    }

    /// A short description for the preview app's caption.
    var summary: String {
        var parts = [style.title, motion.title, tempo.title, "\(complexity) forces"]
        if reflections > 1 { parts.append("\(reflections) reflections") }
        if symmetric { parts.append("symmetric") }
        if wrap { parts.append(mobius ? "Mobius wrap" : "wrap") }
        if twist { parts.append("twist") }
        return parts.joined(separator: ", ")
    }
}

final class FlowSim {
    static let maxForces = 8
    static let maxWaves = 6

    let capacity: Int
    private(set) var settings: FlowSettings
    /// How many times each moving dot is drawn (turned and mirrored copies).
    private(set) var copies = 1
    /// How many dots are really being moved (capacity / copies).
    private(set) var active = 0

    private let px: UnsafeMutablePointer<Float>, py: UnsafeMutablePointer<Float>
    private let vx: UnsafeMutablePointer<Float>, vy: UnsafeMutablePointer<Float>
    private let age: UnsafeMutablePointer<Float>, life: UnsafeMutablePointer<Float>
    private let tint: UnsafeMutablePointer<Float>
    private let gen: UnsafeMutablePointer<UInt32>

    private var clock: Float = 0
    private var needsReset = true
    // The forces: where each one is, how strong, and how it pushes (out/in and around).
    private var fcx = [Float](repeating: 0, count: FlowSim.maxForces)
    private var fcy = [Float](repeating: 0, count: FlowSim.maxForces)
    private var fs = [Float](repeating: 0, count: FlowSim.maxForces)
    private var fa = [Float](repeating: 0, count: FlowSim.maxForces)
    private var fb = [Float](repeating: 0, count: FlowSim.maxForces)
    private var groupX = [Float](repeating: 0, count: FlowSim.maxForces)
    private var groupY = [Float](repeating: 0, count: FlowSim.maxForces)
    // Turbulence: a few crossing ripples the dots are carried along.
    private var wkx = [Float](repeating: 0, count: FlowSim.maxWaves)
    private var wky = [Float](repeating: 0, count: FlowSim.maxWaves)
    private var wom = [Float](repeating: 0, count: FlowSim.maxWaves)
    private var wph = [Float](repeating: 0, count: FlowSim.maxWaves)
    private var wam = [Float](repeating: 0, count: FlowSim.maxWaves)
    private var waveCount = 0
    private var rotC = [Float](repeating: 1, count: 16)
    private var rotS = [Float](repeating: 0, count: 16)

    init(capacity: Int, settings: FlowSettings) {
        let cap = max(capacity, 1)
        self.capacity = cap
        self.settings = settings
        func make() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: cap)
            p.initialize(repeating: 0, count: cap)
            return p
        }
        px = make(); py = make(); vx = make(); vy = make(); age = make(); life = make(); tint = make()
        gen = UnsafeMutablePointer<UInt32>.allocate(capacity: cap)
        gen.initialize(repeating: 0, count: cap)
    }

    deinit {
        px.deallocate(); py.deallocate(); vx.deallocate(); vy.deallocate()
        age.deallocate(); life.deallocate(); tint.deallocate(); gen.deallocate()
    }

    /// Starts over with new settings.
    func restart(with s: FlowSettings) {
        settings = s
        needsReset = true
    }

    private func reset(aspect: Float) {
        let s = settings
        let turns = max(1, min(s.reflections, 12))
        copies = turns * (s.symmetric ? 2 : 1)
        active = max(Int(Float(capacity / copies) * min(max(s.density, 0.02), 1)), 1)
        clock = 0
        for q in 0..<turns {
            let a = TAU * Float(q) / Float(turns)
            rotC[q] = cosf(a); rotS[q] = sinf(a)
        }
        let K = min(max(s.complexity, 1), FlowSim.maxForces)
        for k in 0..<K {
            let kk = UInt32(k)
            fcx[k] = (flowUnit(s.seed, kk, 1) * 2 - 1) * aspect * 0.8
            fcy[k] = (flowUnit(s.seed, kk, 2) * 2 - 1) * 0.8
            groupX[k] = fcx[k]; groupY[k] = fcy[k]
            // Some forces pull in, some push out, and all of them turn the dots a little.
            fa[k] = flowUnit(s.seed, kk, 3) * 1.7 - 1.0
            let turn = (flowUnit(s.seed, kk, 4) * 2 - 1)
            fb[k] = turn * (s.twist ? 1.7 : 1.0) + (turn < 0 ? -0.25 : 0.25)
            fs[k] = 1
        }
        // Ripples: more of them, and finer ones, as complexity rises.
        waveCount = 2 + (s.complexity > 3 ? 1 : 0) + (s.complexity > 5 ? 1 : 0)
        for w in 0..<waveCount {
            let ww = UInt32(w)
            let ang = TAU * flowUnit(s.seed, ww, 11)
            let k = 1.6 + 1.5 * Float(w) + 1.2 * flowUnit(s.seed, ww, 12)
            wkx[w] = cosf(ang) * k; wky[w] = sinf(ang) * k
            wom[w] = (0.25 + 0.5 * flowUnit(s.seed, ww, 13)) * s.pace * (w % 2 == 0 ? 1 : -1)
            wph[w] = TAU * flowUnit(s.seed, ww, 14)
            wam[w] = s.turbulence * 1.15 / k
        }
        if s.twist {
            // The extra twist: two tight ripples that make small local flare-outs.
            for extra in 0..<2 {
                let w = waveCount
                let ww = UInt32(40 + extra)
                let ang = TAU * flowUnit(s.seed, ww, 11)
                let k = 8.5 + 4 * flowUnit(s.seed, ww, 12)
                wkx[w] = cosf(ang) * k; wky[w] = sinf(ang) * k
                wom[w] = (0.5 + 0.6 * flowUnit(s.seed, ww, 13)) * s.pace * (extra == 0 ? 1 : -1)
                wph[w] = TAU * flowUnit(s.seed, ww, 14)
                wam[w] = 0.5 * s.activity / k
                waveCount += 1
            }
        }
        for j in 0..<active {
            gen[j] = 0
            spawn(j, aspect: aspect, s: s, clock: 0)
            // Spread the first births out so they do not all fade in at once.
            age[j] = life[j] * flowUnit(s.seed ^ 0xA5A5, UInt32(truncatingIfNeeded: j), 7)
        }
        needsReset = false
    }

    /// Gives dot j a new life: a birthplace and first push that depend on the style.
    @inline(__always)
    private func spawn(_ j: Int, aspect: Float, s: FlowSettings, clock: Float) {
        let jj = UInt32(truncatingIfNeeded: j) &+ s.seed
        let g = gen[j]
        let h1 = flowUnit(jj, g, 21), h2 = flowUnit(jj, g, 22), h3 = flowUnit(jj, g, 23), h4 = flowUnit(jj, g, 24)
        let side = min(aspect, 1.5)
        var x: Float = 0, y: Float = 0, u: Float = 0, v: Float = 0
        var shade = h1
        let slow = clock * s.pace
        switch s.style {
        case .point:
            let ex = 0.3 * side * sinf(slow * 0.13), ey = 0.3 * sinf(slow * 0.17 + 1)
            let a = TAU * h1, sp = 0.15 + 0.7 * h2
            x = ex + 0.02 * cosf(a); y = ey + 0.02 * sinf(a)
            u = cosf(a) * sp; v = sinf(a) * sp
        case .ring:
            let a = TAU * h1, r = 0.55 + 0.03 * (h2 - 0.5)
            x = cosf(a) * r; y = sinf(a) * r
            u = -sinf(a) * 0.25; v = cosf(a) * 0.25
        case .line:
            let a = slow * 0.07 + TAU * flowUnit(s.seed, 5, 5)
            let d = (h1 * 2 - 1) * 0.9 * side
            x = cosf(a) * d; y = sinf(a) * d
            let push = (h2 - 0.5) * 0.3
            u = -sinf(a) * push; v = cosf(a) * push
        case .spiral:
            let r = 0.04 + 0.8 * h1, a = h1 * 2 * TAU + slow * 0.6 + (h2 < 0.5 ? 0 : Float.pi)
            x = cosf(a) * r; y = sinf(a) * r
            u = -sinf(a) * 0.3; v = cosf(a) * 0.3
        case .scatter:
            x = (h1 * 2 - 1) * aspect; y = h2 * 2 - 1
            shade = h3
        case .cross:
            let a = slow * 0.05 + (h2 < 0.5 ? 0 : Float.pi / 2)
            let d = (h1 * 2 - 1) * 0.85
            x = cosf(a) * d; y = sinf(a) * d
        case .twin:
            let which: Float = h3 < 0.5 ? 0 : Float.pi
            let orbit = slow * 0.35 + which
            let a = orbit + Float.pi / 2 + (h1 - 0.5) * 0.9, sp = 0.3 + 0.6 * h2
            x = cosf(orbit) * 0.5 * side; y = sinf(orbit) * 0.5
            u = cosf(a) * sp; v = sinf(a) * sp
            shade = h1 * 0.5 + (h3 < 0.5 ? 0 : 0.5)
        }
        px[j] = x + s.offsetX; py[j] = y + s.offsetY; vx[j] = u; vy[j] = v
        age[j] = 0
        life[j] = s.life * (0.5 + h4)
        tint[j] = s.hue + s.hueSpread * shade + clock * 0.004
    }

    /// Moves the forces along and works out how strong each is right now.
    private func moveForces(dt: Float, aspect: Float) -> (Float, Float) {
        let s = settings
        let K = min(max(s.complexity, 1), FlowSim.maxForces)
        let T = clock * s.pace
        let side = min(aspect, 1.5)
        var windX: Float = 0, windY: Float = 0
        for k in 0..<K {
            let kk = UInt32(k)
            let p1 = TAU * flowUnit(s.seed, kk, 31), p2 = TAU * flowUnit(s.seed, kk, 32)
            let f1 = 0.6 + 0.8 * flowUnit(s.seed, kk, 33), f2 = 0.6 + 0.8 * flowUnit(s.seed, kk, 34)
            switch s.motion {
            case .still:
                break
            case .linear:
                let ux = fract(T * 0.045 * f1 + p1), uy = fract(T * 0.037 * f2 + p2)
                fcx[k] = (fabsf(2 * ux - 1) * 2 - 1) * aspect * 0.85
                fcy[k] = (fabsf(2 * uy - 1) * 2 - 1) * 0.85
            case .organic:
                fcx[k] = aspect * 0.85 * (0.6 * sinf(T * 0.23 * f1 + p1) + 0.4 * sinf(T * 0.41 * f2 + p2))
                fcy[k] = 0.85 * (0.6 * sinf(T * 0.19 * f2 + p2) + 0.4 * sinf(T * 0.37 * f1 + p1 + 1))
            case .recursive:
                // Each force chases the middle of its own share of the dots.
                let ease = 1 - expf(-dt * 1.4 * s.pace)
                fcx[k] += (groupX[k] + 0.12 * sinf(T * 0.5 + p1) - fcx[k]) * ease
                fcy[k] += (groupY[k] + 0.12 * sinf(T * 0.4 + p2) - fcy[k]) * ease
            case .circular:
                let r = 0.2 + 0.6 * flowUnit(s.seed, kk, 35)
                let a = T * 0.35 * f1 * (k % 2 == 0 ? 1 : -1) + p1
                fcx[k] = cosf(a) * r * side; fcy[k] = sinf(a) * r
            case .warp:
                // Every few seconds, jump somewhere new.
                let tick = UInt32(max(0, T * 0.22 + flowUnit(s.seed, kk, 36)))
                let tx = (flowUnit(s.seed ^ tick, kk, 37) * 2 - 1) * aspect * 0.85
                let ty = (flowUnit(s.seed ^ tick, kk, 38) * 2 - 1) * 0.85
                let ease = 1 - expf(-dt * 5)
                fcx[k] += (tx - fcx[k]) * ease; fcy[k] += (ty - fcy[k]) * ease
            }
            switch s.tempo {
            case .natural:
                fs[k] = 0.35 + 1.3 * (0.5 + 0.5 * sinf(T * 0.31 * f1 + p1)) * (0.5 + 0.5 * sinf(T * 0.17 * f2 + p2))
                    + 0.3 * sinf(T * 0.07 + p2)
            case .clockwork:
                let beat = fract(T * 0.25 + Float(k) / Float(K))
                fs[k] = 0.25 + 1.5 * expf(-beat * 4)
            case .waves:
                fs[k] = 0.2 + 0.9 * (1 + sinf(T * 0.6 - TAU * Float(k) / Float(K)))
            case .digital:
                let tick = UInt32(max(0, T * 0.5 + flowUnit(s.seed, kk, 39)))
                fs[k] = flowUnit(s.seed ^ (tick &* 7919), kk, 40) > 0.45 ? 1.4 : 0.12
            case .directional:
                fs[k] = 0.8
            }
        }
        if s.tempo == .directional {
            // A steady wind that slowly swings round.
            let a = T * 0.1 + TAU * flowUnit(s.seed, 9, 41)
            windX = cosf(a) * 0.55 * s.activity; windY = sinf(a) * 0.55 * s.activity
        }
        return (windX, windY)
    }

    /// Moves every dot forward by dt seconds.
    func step(dt dtIn: Double, aspect: Float, threads: Int) {
        if needsReset { reset(aspect: aspect) }
        let dt = Float(min(max(dtIn, 0), 1.0 / 20))
        clock += dt
        let (windX, windY) = moveForces(dt: dt, aspect: aspect)
        let s = settings
        let K = min(max(s.complexity, 1), FlowSim.maxForces)
        let W = waveCount
        let drag = expf(-s.viscosity * dt)
        let invR2 = 1 / (s.range * s.range)
        let push = 1.7 * s.activity
        let conf = s.confinement
        let bx = aspect * 1.04, by: Float = 1.04
        let now = clock
        let n = active
        let workers = max(1, min(threads, 16))
        let per = (n + workers - 1) / workers
        let px = px, py = py, vx = vx, vy = vy, age = age, life = life, gen = gen
        fcx.withUnsafeBufferPointer { fcx in fcy.withUnsafeBufferPointer { fcy in
        fs.withUnsafeBufferPointer { fs in fa.withUnsafeBufferPointer { fa in fb.withUnsafeBufferPointer { fb in
        wkx.withUnsafeBufferPointer { wkx in wky.withUnsafeBufferPointer { wky in
        wom.withUnsafeBufferPointer { wom in wph.withUnsafeBufferPointer { wph in wam.withUnsafeBufferPointer { wam in
            DispatchQueue.concurrentPerform(iterations: workers) { c in
                let lo = c * per, hi = min(n, lo + per)
                if lo >= hi { return }
                for j in lo..<hi {
                    var x = px[j], y = py[j], u = vx[j], v = vy[j]
                    var ax = windX, ay = windY
                    for k in 0..<K {
                        let dx = x - fcx[k], dy = y - fcy[k]
                        let r2 = dx * dx + dy * dy
                        let g = expf(-r2 * invR2) * fs[k] * push
                        let inv = 1 / (sqrtf(r2) + 0.06)
                        let ux = dx * inv, uy = dy * inv
                        ax += g * (fa[k] * ux - fb[k] * uy)
                        ay += g * (fa[k] * uy + fb[k] * ux)
                    }
                    for w in 0..<W {
                        let cw = cosf(wkx[w] * x + wky[w] * y + wom[w] * now + wph[w]) * wam[w]
                        ax += cw * wky[w]; ay -= cw * wkx[w]
                    }
                    if !s.wrap {
                        // Confinement: a gentle pull home once a dot strays too far out.
                        let d = sqrtf(x * x + y * y)
                        let over = max(0, d * conf - 0.42)
                        ax -= x * over * 1.6; ay -= y * over * 1.6
                    }
                    u = (u + ax * dt) * drag; v = (v + ay * dt) * drag
                    x += u * dt; y += v * dt
                    if s.wrap {
                        if x > bx { x -= 2 * bx; if s.mobius { y = -y; v = -v } }
                        else if x < -bx { x += 2 * bx; if s.mobius { y = -y; v = -v } }
                        if y > by { y -= 2 * by; if s.mobius { x = -x; u = -u } }
                        else if y < -by { y += 2 * by; if s.mobius { x = -x; u = -u } }
                    } else {
                        // Walls: dots bounce back in.
                        if x > bx { x = bx; u = -fabsf(u) * 0.8 } else if x < -bx { x = -bx; u = fabsf(u) * 0.8 }
                        if y > by { y = by; v = -fabsf(v) * 0.8 } else if y < -by { y = -by; v = fabsf(v) * 0.8 }
                    }
                    px[j] = x; py[j] = y; vx[j] = u; vy[j] = v
                    age[j] += dt
                    if age[j] >= life[j] || !(x == x) || !(y == y) {
                        gen[j] = gen[j] &+ 1
                        self.spawn(j, aspect: aspect, s: s, clock: now)
                    }
                }
            }
        }}}}}}}}}}
        if s.motion == .recursive {
            // Where is each force's share of the dots gathered?
            var sx = [Float](repeating: 0, count: K), sy = [Float](repeating: 0, count: K)
            var cnt = [Float](repeating: 0, count: K)
            let stride = max(1, n / 3000)
            var j = 0
            while j < n {
                let k = (j / stride) % K
                sx[k] += px[j]; sy[k] += py[j]; cnt[k] += 1
                j += stride
            }
            for k in 0..<K where cnt[k] > 0 { groupX[k] = sx[k] / cnt[k]; groupY[k] = sy[k] / cnt[k] }
        }
    }

    /// Where engine dot i is and what colour it is. Dots that share one moving
    /// dot are its turned and mirrored copies.
    @inline(__always)
    func sample(_ i: Int) -> Sample {
        let j = i / copies
        if j >= active { return Sample(x: 0, y: 0, z: 0, r: 0, g: 0, b: 0) }
        var x = px[j], y = py[j]
        if copies > 1 {
            let c = i - j * copies
            let turns = max(1, min(settings.reflections, 12))
            let q = c % turns
            if c >= turns { x = -x }
            if q > 0 {
                let cs = rotC[q], sn = rotS[q]
                let rx = x * cs - y * sn
                y = x * sn + y * cs
                x = rx
            }
        }
        let sp = sqrtf(vx[j] * vx[j] + vy[j] * vy[j])
        let a = age[j], L = life[j]
        let env = smooth(a * 2.5) * smooth((L - a) * 1.2)
        // Faster dots run brighter and warmer; slow ones dim, as in a settling liquid.
        let c3 = rainbow(tint[j] + 0.16 * min(sp, 1.5))
        var b = env * (0.28 + 0.72 * min(sp * 1.2, 1)) * 0.9
        // A round light spreads over more of the screen than a fine dot: dim it to match.
        let ds = settings.dotSize
        if ds > 0 { b *= 0.55 / (0.5 + 0.22 * ds * ds) }
        return Sample(x: x, y: y, z: 0, r: c3.0 * b, g: c3.1 * b, b: c3.2 * b, size: ds)
    }
}

extension Pattern {
    /// Patterns whose dots are moved by the flow simulation.
    var isFlow: Bool { self == .currents || self == .kaleidoscope }
}
