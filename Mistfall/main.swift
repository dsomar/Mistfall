import AppKit
import QuartzCore
import ServiceManagement

// Mistfall preview app: shows the screensaver in a window (or full screen) and
// can install the real screensaver. `--screenshot <file.png>` draws about 120
// frames without taking focus, saves the window's picture and quits.

struct Options {
    var screenshot: String?
    var pattern: Pattern?
    var frames = 120
    var skip: Double = 0
    var liveliness: Float = 1
    var seed: UInt64?
    var mood: UInt64?
    var intro = false
    var pointer: (Double, Double)?   // test pointer, as fractions of the window
    var pointerSize: Float?
    var noGlow = false
    var fps = false            // show the frame rate (for pictures)
    var cpu = false            // keep the old drawing, without the graphics chip
    var idleNow = false        // start the full-screen show at once, then end it (for checks)
    var size: (Double, Double)?  // window size in points, e.g. 1440x900 (for listing pictures)
    var panelShot: String?
    var log = false            // print each pattern change (for checks)
    var keys: [UInt16] = []    // key codes to press one second in (for checks)
    var flow: ParticleFlow?    // Particle Flow settings for pictures, e.g. density=0.4,size=3,bg=101830,palette=ocean,seed=7

    init(_ args: [String]) {
        var i = 1
        while i < args.count {
            let a = args[i]
            func value() -> String? { i + 1 < args.count ? args[i + 1] : nil }
            switch a {
            case "--screenshot": screenshot = value(); i += 1
            case "--pattern", "--scene": pattern = value().flatMap(Pattern.named); i += 1
            case "--frames": frames = value().flatMap(Int.init) ?? frames; i += 1
            case "--skip": skip = value().flatMap(Double.init) ?? 0; i += 1
            case "--liveliness", "--lively": liveliness = value().flatMap(Float.init) ?? 1; i += 1
            case "--calm": liveliness = 0
            case "--intro": intro = true
            case "--no-glow": noGlow = true
            case "--fps": fps = true
            case "--cpu": cpu = true
            case "--idle-now": idleNow = true
            case "--size":
                let p = (value() ?? "").split(separator: "x").compactMap { Double($0) }
                if p.count == 2 { size = (p[0], p[1]) }
                i += 1
            case "--log": log = true
            case "--keys": keys = (value() ?? "").split(separator: ",").compactMap { UInt16($0) }; i += 1
            case "--panel-shot": panelShot = value(); i += 1
            case "--pointer":
                let parts = (value() ?? "").split(separator: ",").compactMap { Double($0) }
                if parts.count >= 2 { pointer = (parts[0], parts[1]) }
                if parts.count >= 3 { pointerSize = Float(parts[2]) }
                i += 1
            case "--mood": mood = value().flatMap { UInt64($0) }; i += 1
            case "--seed": seed = value().flatMap { UInt64($0) }; i += 1
            case "--flow":
                var f = ParticleFlow()
                for part in (value() ?? "").split(separator: ",") {
                    let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                    guard kv.count == 2 else { continue }
                    switch kv[0] {
                    case "density": f.density = Double(kv[1]) ?? f.density
                    case "size": f.size = Double(kv[1]) ?? f.size
                    case "strength": f.strength = Double(kv[1]) ?? f.strength
                    case "scale": f.scale = Double(kv[1]) ?? f.scale
                    case "bg": f.background = kv[1]
                    case "palette": f.palette = ParticleFlow.Palette(rawValue: kv[1]) ?? f.palette
                    case "seed": f.seed = Int(kv[1]) ?? f.seed
                    default: break
                    }
                }
                flow = f; i += 1
            default: break
            }
            i += 1
        }
    }
}

final class LightsView: NSView {
    let engine: Engine
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    var fixedStep: Double?
    var onFrame: ((Int) -> Void)?
    /// For pictures: a pretend pointer circling this spot (fractions of the window).
    var testPointer: (Double, Double)?
    private var frames = 0
    var showHint = true
    private var hintUntil = CACurrentMediaTime() + 6
    /// Glow, random or one pattern, and how often it changes.
    var settings = MistfallSettings()
    /// Whether changes are remembered for the next launch.
    var remembers = false
    private var meter = FrameMeter()
    /// Frames drawn a second, as measured.
    var fps: Double { meter.fps }

    /// Puts the settings to work (and remembers them).
    func commit() {
        settings.apply(to: engine)
        if remembers { settings.save(to: .standard) }
        flashHint()
    }

    /// After changing pattern by hand: in one-pattern mode stay on the new one,
    /// otherwise let go of any pattern asked for at launch.
    private func settle() {
        if settings.only != nil { settings.only = engine.current; commit() }
        else { engine.fixedPattern = nil; flashHint() }
    }

    init(frame: NSRect, engine: Engine) {
        self.engine = engine
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func renderSize() -> (Int, Int) {
        let scale = window?.backingScaleFactor ?? 1
        var w = bounds.width * scale, h = bounds.height * scale
        let maxW: CGFloat = 1600
        if w > maxW { h *= maxW / w; w = maxW }
        return (max(Int(w), 16), max(Int(h), 16))
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = fixedStep ?? min(max(now - last, 0.001), 0.1)
        last = now
        let (w, h) = renderSize()
        engine.resize(width: w, height: h)
        if let tp = testPointer {
            let a = Double(frames) * 0.06
            engine.setPointer(x: Float((tp.0 + 0.06 * cos(a)) * Double(engine.width)),
                              y: Float((tp.1 + 0.08 * sin(a)) * Double(engine.height)))
        }
        engine.step(dt: dt)
        if let canvas = canvas, let gpu = engine.gpu {
            canvas.fit(scale: window?.backingScaleFactor ?? 1, maxWidth: 3200)
            gpu.present(in: canvas.metalLayer)
            let now = CACurrentMediaTime()
            meter.frame(at: now)
            // The words on top only need redrawing while they show (and once to clear).
            let showing = settings.showFPS || (showHint && now < max(hintUntil, sizeNoteUntil))
            if showing || hudShowing { hud?.needsDisplay = true }
            hudShowing = showing
        } else {
            needsDisplay = true
        }
        frames += 1
        onFrame?(frames)
    }

    private var canvas: MetalCanvas?
    private var hud: HUDView?
    private var hudShowing = false

    /// Draw with the graphics chip from now on. False if this Mac cannot.
    @discardableResult
    func useGPU() -> Bool {
        guard canvas == nil, engine.useGPU(), let gpu = engine.gpu else { return canvas != nil }
        let c = MetalCanvas(frame: bounds, device: gpu.device)
        let h = HUDView(frame: bounds)
        h.onDraw = { [weak self] _ in self?.drawHUD() }
        addSubview(c)
        addSubview(h)
        canvas = c; hud = h
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard canvas == nil, let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.setFillColor(CGColor(gray: 0, alpha: 1))
        cg.fill(bounds)
        if let img = engine.makeImage() {
            cg.interpolationQuality = .high
            cg.draw(img, in: bounds)
        }
        meter.frame(at: CACurrentMediaTime())
        drawHUD()
    }

    /// The words over the picture: the frame rate and the hints.
    func drawHUD() {
        if settings.showFPS { meter.draw(in: bounds) }
        if showHint && CACurrentMediaTime() < sizeNoteUntil {
            let pct = Int((engine.pointerSize * 100).rounded())
            let note = NSAttributedString(string: "Mouse area: \(pct)%   (scroll to change)", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(white: 1, alpha: 0.6),
            ])
            let sz = note.size()
            note.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: 58))
        }
        if showHint && CACurrentMediaTime() < hintUntil {
            let mood = engine.liveliness >= 0.99 ? "Lively" : engine.liveliness > 0 ? "Gentle" : "Calm"
            let mouse = engine.pointerEnabled ? "Mouse on" : "Mouse off"
            let what = engine.detail.isEmpty ? engine.current.title : engine.current.title + ": " + engine.detail
            let glow = settings.glow ? "Glow on" : "Glow off"
            let mode = settings.only != nil
                ? "Only this pattern (R: back to random)"
                : "Random, changes every \(MistfallSettings.label(minutes: settings.changeMinutes)) (T: change time, R: only this one)"
            let top = "\(what)   ·   \(mode)   ·   \(glow) (G)"
            let text = "\(mood) (L)   ·   \(mouse) (M, scroll: area)   ·   Space: another pattern   ·   P: frame rate   ·   F: full screen   ·   Esc: quit"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(white: 1, alpha: 0.55),
            ]
            for (line, y) in [(top, CGFloat(36)), (text, CGFloat(18))] {
                let s = NSAttributedString(string: line, attributes: attrs)
                let size = s.size()
                s.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y))
            }
        }
    }

    private func flashHint() { hintUntil = CACurrentMediaTime() + 3 }

    /// Scroll wheel: grow or shrink the area the mouse stirs.
    override func scrollWheel(with event: NSEvent) {
        guard engine.pointerEnabled else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.08
        if dy == 0 { return }
        engine.pointerSize *= Float(exp(Double(dy)))
        UserDefaults.standard.set(engine.pointerSize, forKey: "mouseArea")
        sizeNoteUntil = CACurrentMediaTime() + 1.5
    }
    private var sizeNoteUntil: CFTimeInterval = 0

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: engine.fixedPattern = nil; engine.randomNext(); settle()        // space: a random pattern
        case 124: engine.fixedPattern = nil; engine.next(); settle()             // →
        case 123: engine.fixedPattern = nil; engine.previousPattern(); settle()  // ←
        case 35: toggleFPS()                                       // P: frame rate on/off
        case 5: toggleGlow()                                       // G: glow on/off
        case 15: toggleOnly()                                      // R: random ↔ only this pattern
        case 17:                                                   // T: how often a random pattern changes
            settings.changeMinutes = settings.nextPreset
            commit()
        case 3: window?.toggleFullScreen(nil)                     // F
        case 46:                                                   // M: mouse reaction on/off
            toggleMouse()
        case 37:                                                   // L: lively → gentle → calm
            engine.liveliness = engine.liveliness >= 0.99 ? 0.5 : engine.liveliness > 0 ? 0 : 1
            flashHint()
        case 53:                                                   // Esc
            if let w = window, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) } else { NSApp.terminate(nil) }
        default: super.keyDown(with: event)
        }
    }

    func toggleGlow() {
        settings.glow.toggle()
        commit()
    }

    func toggleFPS() {
        settings.showFPS.toggle()
        commit()
    }

    func toggleOnly() {
        settings.only = settings.only == nil ? engine.current : nil
        commit()
    }

    func toggleMouse() {
        engine.pointerEnabled.toggle()
        UserDefaults.standard.set(engine.pointerEnabled, forKey: "mouseReacts")
        flashHint()
    }

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func follow(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0, engine.width > 0 else { return }
        engine.setPointer(x: Float(p.x / bounds.width) * Float(engine.width),
                          y: Float(p.y / bounds.height) * Float(engine.height))
    }

    override func mouseMoved(with event: NSEvent) { follow(event) }
    override func mouseDragged(with event: NSEvent) { follow(event) }
    override func mouseEntered(with event: NSEvent) { follow(event) }
    override func mouseExited(with event: NSEvent) { engine.clearPointer() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.toggleFullScreen(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let options: Options
    var window: NSWindow!
    var view: LightsView!
    private var panel: SettingsPanel?
    /// Full screen on every display after the Mac has been left alone.
    private var idle: IdleStart?
    /// The screen saver bundled with this app, if any (the App Store version has none).
    private var bundledSaver: URL? { Bundle.main.url(forResource: "Mistfall", withExtension: "saver") }

    init(options: Options) { self.options = options }

    /// A fresh picture for one display of the full-screen show, with the current settings.
    private func makeShowView(frame: NSRect) -> LightsView {
        let s = view.settings
        let engine = Engine(count: 70_000, start: .orb, seed: UInt64.random(in: 1...UInt64.max))
        engine.shuffle = true
        engine.randomStart(pattern: s.only)
        engine.intro = true
        engine.pointerEnabled = false
        s.apply(to: engine)
        let v = LightsView(frame: frame, engine: engine)
        if !options.cpu { v.useGPU() }
        v.settings = s
        v.showHint = false
        return v
    }

    private func setUpIdleStart() {
        let i = IdleStart { [weak self] frame in self?.makeShowView(frame: frame) }
        // The window's own picture rests while the show is up.
        i.onBegin = { [weak self] in self?.view.stop() }
        i.onEnd = { [weak self] in
            guard let self = self else { return }
            self.view.start()
            if self.window.isVisible { self.window.makeFirstResponder(self.view) }
        }
        idle = i
        if options.idleNow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                i.begin()
                print("show started: showing=\(i.isShowing) screens=\(NSScreen.screens.count) windows=\(NSApp.windows.filter { $0.level == .screenSaver && $0.isVisible }.count)")
                fflush(stdout)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                i.end()
                print("show ended: showing=\(i.isShowing) windows=\(NSApp.windows.filter { $0.level == .screenSaver && $0.isVisible }.count)")
                exit(0)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = options.panelShot { shootPanel(to: path) }
        let shooting = options.screenshot != nil
        let saved = shooting ? MistfallSettings() : MistfallSettings.load(.standard)
        let startPattern = options.pattern ?? saved.only
        // A fresh random seed every run; pictures for checks stay repeatable.
        let seed = options.seed ?? (shooting ? 0x5EED_1234 : UInt64.random(in: 1...UInt64.max))
        let engine = Engine(count: 70_000, start: options.pattern ?? .orb, seed: seed)
        engine.shuffle = !shooting
        if !shooting {
            // Every launch: a random pattern (unless one was asked for) and a random look,
            // with the dots fading in and gathering into it.
            engine.randomStart(pattern: startPattern)
            engine.intro = true
            engine.pointerEnabled = UserDefaults.standard.object(forKey: "mouseReacts") as? Bool ?? true
            if let a = UserDefaults.standard.object(forKey: "mouseArea") as? Float { engine.pointerSize = a }
        }
        if options.intro { engine.intro = true }
        if let p = options.pointer {
            engine.pointerEnabled = true
            _ = p
            if let r = options.pointerSize { engine.pointerSize = r }
        }
        if let m = options.mood { engine.jumpToMood(seed: m) }
        if !shooting { saved.apply(to: engine) }
        if let f = options.flow { engine.particleFlow = f.clamped() }
        engine.fixedPattern = shooting ? (options.pattern ?? .orb) : startPattern
        if options.noGlow { engine.glowEnabled = false }
        engine.time = options.skip
        engine.liveliness = options.liveliness

        let rect = NSRect(x: 0, y: 0, width: options.size?.0 ?? 1024, height: options.size?.1 ?? 768)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Mistfall"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        view = LightsView(frame: rect, engine: engine)
        view.testPointer = options.pointer
        if !options.cpu { view.useGPU() }
        view.settings = saved
        if options.noGlow { view.settings.glow = false }
        if options.fps { view.settings.showFPS = true }
        // A run started with a pattern or look on the command line is a one-off.
        view.remembers = !shooting && options.pattern == nil && !options.noGlow && options.keys.isEmpty
        if options.log || !options.keys.isEmpty { setUpChecks() }
        window.contentView = view
        window.center()

        if let path = options.screenshot {
            view.showHint = false
            view.fixedStep = 1.0 / 60.0
            let target = options.frames
            view.onFrame = { [weak self] n in
                guard let self = self, n >= target else { return }
                self.view.onFrame = nil
                self.save(to: path)
            }
            window.orderFront(nil)            // shown, but never made active
        } else {
            setUpIdleStart()
            setUpMenu()
            window.acceptsMouseMovedEvents = true
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
        }
        view.start()
    }

    /// For checks: prints every pattern change, and presses the asked-for keys.
    private func setUpChecks() {
        var shown: Pattern?
        func say(_ what: String) {
            let s = view.settings
            print(String(format: "t=%5.1f  %@  pattern=%@ glow=%@ only=%@ every=%.2fmin showFPS=%@ measured=%.1ffps \(view.engine.gpu != nil ? "gpu" : "cpu")", view.engine.time, what,
                         view.engine.current.key, s.glow ? "on" : "off", s.only?.key ?? "random", s.changeMinutes,
                         s.showFPS ? "on" : "off", view.fps))
            fflush(stdout)
        }
        view.onFrame = { [weak self] _ in
            guard let self = self, self.view.engine.current != shown else { return }
            shown = self.view.engine.current
            say("change")
        }
        for (n, code) in options.keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(n) * 0.5) { [weak self] in
                guard let self = self, let e = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: self.window.windowNumber,
                    context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else { return }
                self.view.keyDown(with: e)
                say("key \(code)")
            }
        }
    }

    /// Saves a picture of the settings panel and quits (for checking its layout).
    private func shootPanel(to path: String) {
        var s = MistfallSettings.load(.standard)
        if let p = options.pattern { s.only = p }
        let panel = SettingsPanel(settings: s) { _ in }
        guard let v = panel.window.contentView else { exit(2) }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(2) }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { exit(4) }
        print("Saved \(path)")
        exit(0)
    }

    private func save(to path: String) {
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
        if view.engine.gpu != nil {
            // A Metal picture is not caught by cacheDisplay: read it back and draw it in.
            guard let img = view.engine.makeImage(), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(2) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            ctx.cgContext.interpolationQuality = .high
            ctx.cgContext.draw(img, in: view.bounds)
            view.drawHUD()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try data.write(to: url) } catch {
            FileHandle.standardError.write("Could not save \(path): \(error)\n".data(using: .utf8)!)
            exit(4)
        }
        print("Saved \(path)")
        exit(0)
    }

    // With "Start When Idle" on, the app stays open after its window is closed, waiting.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        (idle?.minutes ?? 0) == 0 && !(idle?.isShowing ?? false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, options.screenshot == nil {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
        return true
    }

    func windowDidEnterFullScreen(_ notification: Notification) { NSCursor.setHiddenUntilMouseMoves(true) }

    private func setUpMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Mistfall", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        if bundledSaver != nil {
            appMenu.addItem(withTitle: "Install as Screen Saver…", action: #selector(installSaver), keyEquivalent: "i").target = self
        }
        appMenu.addItem(.separator())
        let idleItem = NSMenuItem(title: "Start When Idle", action: nil, keyEquivalent: "")
        let idleMenu = NSMenu(title: "Start When Idle")
        for m in IdleStart.choices {
            let item = NSMenuItem(title: IdleStart.label(m), action: #selector(pickIdle(_:)), keyEquivalent: "")
            item.tag = m
            item.target = self
            idleMenu.addItem(item)
        }
        idleItem.submenu = idleMenu
        appMenu.addItem(idleItem)
        appMenu.addItem(withTitle: "Start on All Screens Now", action: #selector(startShow), keyEquivalent: "\r").target = self
        appMenu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Mistfall", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Mistfall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        for p in Pattern.allCases {
            let item = NSMenuItem(title: p.title, action: #selector(pickPattern(_:)), keyEquivalent: p.rawValue < 9 ? "\(p.rawValue + 1)" : "")
            item.tag = p.rawValue
            item.target = self
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Choose Patterns at Random", action: #selector(cycleAll), keyEquivalent: "0").target = self
        let everyItem = NSMenuItem(title: "Change Every", action: nil, keyEquivalent: "")
        let everyMenu = NSMenu(title: "Change Every")
        for m in MistfallSettings.presets {
            let item = NSMenuItem(title: MistfallSettings.label(minutes: m), action: #selector(pickStay(_:)), keyEquivalent: "")
            item.tag = Int((m * 100).rounded())
            item.target = self
            everyMenu.addItem(item)
        }
        everyItem.submenu = everyMenu
        viewMenu.addItem(everyItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Particle Glow", action: #selector(toggleGlowMenu), keyEquivalent: "g").target = self
        viewMenu.addItem(withTitle: "Show Frame Rate", action: #selector(toggleFPSMenu), keyEquivalent: "p").target = self
        let mouseItem = NSMenuItem(title: "Dots React to the Mouse", action: #selector(toggleMouseMenu(_:)), keyEquivalent: "m")
        mouseItem.target = self
        mouseItem.state = view.engine.pointerEnabled ? .on : .off
        viewMenu.addItem(mouseItem)
        viewMenu.addItem(.separator())
        let fs = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fs)
        viewItem.submenu = viewMenu
        NSApp.mainMenu = main
    }

    @objc private func pickPattern(_ sender: NSMenuItem) {
        guard let p = Pattern(rawValue: sender.tag) else { return }
        view.settings.only = p
        view.commit()
        view.engine.show(p)
    }

    @objc private func pickStay(_ sender: NSMenuItem) {
        view.settings.changeMinutes = Double(sender.tag) / 100
        view.settings.only = nil
        view.commit()
    }

    @objc private func toggleGlowMenu() { view.toggleGlow() }

    @objc private func pickIdle(_ sender: NSMenuItem) { idle?.minutes = sender.tag }

    @objc private func startShow() { idle?.begin() }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Could not change Open at Login"
            a.informativeText = "\(error.localizedDescription)\n\nYou can also add Mistfall under System Settings › General › Login Items."
            a.runModal()
        }
    }
    @objc private func toggleFPSMenu() { view.toggleFPS() }

    @objc private func showSettings() {
        guard panel == nil else { return }
        let p = SettingsPanel(settings: view.settings) { [weak self] chosen in
            guard let self = self else { return }
            if let s = chosen {
                self.view.settings = s
                self.view.commit()
            }
            self.panel = nil
            self.window.makeFirstResponder(self.view)
        }
        panel = p
        window.beginSheet(p.window, completionHandler: nil)
    }

    /// Ticks the menu items that match what is showing.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let s = view.settings
        switch item.action {
        case #selector(pickPattern(_:)): item.state = s.only?.rawValue == item.tag ? .on : .off
        case #selector(cycleAll): item.state = s.only == nil ? .on : .off
        case #selector(toggleGlowMenu): item.state = s.glow ? .on : .off
        case #selector(toggleFPSMenu): item.state = s.showFPS ? .on : .off
        case #selector(pickIdle(_:)): item.state = (idle?.minutes ?? 0) == item.tag ? .on : .off
        case #selector(toggleLogin): item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(toggleMouseMenu(_:)): item.state = view.engine.pointerEnabled ? .on : .off
        case #selector(pickStay(_:)):
            item.state = s.only == nil && abs(Double(item.tag) / 100 - s.changeMinutes) < 0.001 ? .on : .off
        default: break
        }
        return true
    }

    @objc private func toggleMouseMenu(_ sender: NSMenuItem) {
        view.toggleMouse()
        sender.state = view.engine.pointerEnabled ? .on : .off
    }

    @objc private func cycleAll() {
        view.settings.only = nil
        view.commit()
    }

    @objc private func about() {
        let a = NSAlert()
        a.messageText = "Mistfall"
        a.informativeText = "Glowing, ever-changing clouds of coloured light: an orb, ribbons, a murmuration, a fountain, northern lights, pulsing rings, waterfall mist and a knot of light — with heartbeat pulses and sparks that fly away like embers. Press L to make it livelier or calmer.\n\nChoose “Start When Idle” in the Mistfall menu and it fills every screen after the Mac has been left alone; any key or mouse move puts it away."
            + (bundledSaver != nil ? "\n\nUse “Install as Screen Saver…” to add it to System Settings › Screen Saver." : "")
        a.runModal()
    }

    @objc private func installSaver() {
        if let url = Bundle.main.url(forResource: "Mistfall", withExtension: "saver") {
            // Opening a .saver lets macOS install it and show it in System Settings.
            NSWorkspace.shared.open(url)
        } else {
            let a = NSAlert()
            a.messageText = "Screen saver not found"
            a.informativeText = "Open Mistfall.saver (next to this app) to install it."
            a.runModal()
        }
    }
}

let options = Options(CommandLine.arguments)
let app = NSApplication.shared
app.setActivationPolicy(options.screenshot != nil ? .accessory : .regular)
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.run()
