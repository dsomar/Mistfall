import ScreenSaver
import QuartzCore

@objc(MistfallView)
final class MistfallView: ScreenSaverView {
    private var engine: Engine!
    private var last = CACurrentMediaTime()
    private var panel: SettingsPanel?
    private var meter = FrameMeter()
    private var showFPS = false
    private var canvas: MetalCanvas?
    private var hud: HUDView?
    private var hudShowing = false

    /// Where the screen saver's own settings are kept.
    private var defaults: UserDefaults {
        let id = Bundle(for: MistfallView.self).bundleIdentifier ?? "com.secretweaponlabs.Mistfall.saver"
        return ScreenSaverDefaults(forModuleWithName: id) ?? .standard
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        animationTimeInterval = 1.0 / 60.0
        let count = isPreview ? 15_000 : 70_000
        let settings = MistfallSettings.load(defaults)
        engine = Engine(count: count, start: .orb, seed: UInt64.random(in: 1...UInt64.max))
        engine.shuffle = true
        engine.randomStart(pattern: settings.only)
        engine.intro = true
        engine.pointerEnabled = false
        settings.apply(to: engine)
        showFPS = settings.showFPS
        // The graphics-chip picture showed nothing inside the screen saver on macOS 26
        // (black screen, blank preview; reported 2026-11-17), so the screen saver draws
        // the plain way until that is understood. The standalone app still uses the chip.
        if Self.drawWithGPU, engine.useGPU(), let gpu = engine.gpu {
            let c = MetalCanvas(frame: bounds, device: gpu.device)
            let h = HUDView(frame: bounds)
            h.onDraw = { [weak self] rect in
                guard let self = self, self.showFPS else { return }
                self.meter.draw(in: rect)
            }
            addSubview(c)
            addSubview(h)
            canvas = c; hud = h
        }
        NSLog("Mistfall: setUp preview=%d bounds=%@ gpu=%d", isPreview ? 1 : 0, NSStringFromRect(bounds), engine.gpu != nil ? 1 : 0)
    }
    private var diagFrames = 0
    private static let drawWithGPU = false

    private func renderSize() -> (Int, Int) {
        let scale = window?.backingScaleFactor ?? 1
        var w = bounds.width * scale, h = bounds.height * scale
        let maxW: CGFloat = isPreview ? 600 : 1600
        if w > maxW { h *= maxW / w; w = maxW }
        return (max(Int(w), 1), max(Int(h), 1))
    }

    override func startAnimation() {
        super.startAnimation()
        last = CACurrentMediaTime()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - last, 0.001), 0.1)
        last = now
        let (w, h) = renderSize()
        engine.resize(width: w, height: h)
        engine.step(dt: dt)
        if let canvas = canvas, let gpu = engine.gpu {
            canvas.fit(scale: window?.backingScaleFactor ?? 1, maxWidth: isPreview ? 1200 : 3200)
            let res = gpu.present(in: canvas.metalLayer)
            diagFrames += 1
            if diagFrames == 1 || diagFrames == 600 {
                NSLog("Mistfall: frame %d present=%@ bounds=%@ canvas=%@ drawable=%@ render=%dx%d window=%d scale=%.1f hidden=%d superlayer=%d preview=%d",
                      diagFrames, res, NSStringFromRect(bounds), NSStringFromRect(canvas.frame), NSStringFromSize(canvas.metalLayer.drawableSize),
                      w, h, window != nil ? 1 : 0, Double(window?.backingScaleFactor ?? 0), canvas.isHiddenOrHasHiddenAncestor ? 1 : 0,
                      canvas.metalLayer.superlayer != nil ? 1 : 0, isPreview ? 1 : 0)
            }
            meter.frame(at: now)
            if showFPS || hudShowing { hud?.needsDisplay = true }
            hudShowing = showFPS
        } else {
            setNeedsDisplay(bounds)
        }
    }

    override func draw(_ rect: NSRect) {
        guard canvas == nil, let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.setFillColor(CGColor(gray: 0, alpha: 1))
        cg.fill(bounds)
        if let img = engine.makeImage() {
            cg.interpolationQuality = .high
            cg.draw(img, in: bounds)
        }
        meter.frame(at: CACurrentMediaTime())
        if showFPS { meter.draw(in: bounds) }
        diagFrames += 1
        if diagFrames == 1 || diagFrames == 600 {
            NSLog("Mistfall: plain frame %d bounds=%@ preview=%d", diagFrames, NSStringFromRect(bounds), isPreview ? 1 : 0)
        }
    }

    // The Options button in System Settings > Screen Saver opens this.
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        let p = SettingsPanel(settings: MistfallSettings.load(defaults)) { [weak self] chosen in
            guard let self = self else { return }
            if let s = chosen {
                s.save(to: self.defaults)
                s.apply(to: self.engine)
                self.showFPS = s.showFPS
            }
            self.panel = nil
        }
        panel = p
        return p.window
    }
}
