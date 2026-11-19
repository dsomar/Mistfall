import AppKit
import IOKit.pwr_mgt
import QuartzCore

// Mistfall as its own screen saver: after the Mac has been left alone for a chosen
// number of minutes the app covers every display, and the first key press, click or
// mouse move puts it away again. This is how the App Store version works, since an
// App Store app cannot add a screen saver to System Settings.

private final class SaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class IdleStart {
    /// Minutes of inactivity to choose from; 0 is off.
    static let choices = [0, 1, 2, 5, 10, 15, 30]

    var minutes: Int {
        didSet {
            UserDefaults.standard.set(minutes, forKey: "idleMinutes")
            schedule()
        }
    }
    private(set) var isShowing = false
    /// Called as the full-screen show starts and after it ends.
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?

    private let makeView: (NSRect) -> LightsView?
    private var watch: Timer?
    private var poll: Timer?
    private var windows: [NSWindow] = []
    private var views: [LightsView] = []
    private var monitor: Any?
    private var began: CFTimeInterval = 0
    private var previousApp: NSRunningApplication?

    init(makeView: @escaping (NSRect) -> LightsView?) {
        self.makeView = makeView
        minutes = UserDefaults.standard.integer(forKey: "idleMinutes")
        schedule()
    }

    static func label(_ m: Int) -> String {
        m == 0 ? "Never" : m == 1 ? "After 1 Minute" : "After \(m) Minutes"
    }

    /// Seconds since the last key press, click or mouse move anywhere on the Mac.
    private var idleSeconds: Double {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    /// True while something (a film, a call) is keeping the display awake on purpose.
    private var displayHeldAwake: Bool {
        var out: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&out) == kIOReturnSuccess,
              let d = out?.takeRetainedValue() as? [String: Int] else { return false }
        return (d["PreventUserIdleDisplaySleep"] ?? 0) > 0 || (d["NoDisplaySleepAssertion"] ?? 0) > 0
    }

    private func schedule() {
        watch?.invalidate()
        watch = nil
        guard minutes > 0 else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        watch = t
    }

    private func check() {
        guard minutes > 0, !isShowing else { return }
        if idleSeconds >= Double(minutes) * 60, !displayHeldAwake, CGDisplayIsAsleep(CGMainDisplayID()) == 0 {
            begin()
        }
    }

    /// Cover every display now.
    func begin() {
        guard !isShowing else { return }
        isShowing = true
        previousApp = NSWorkspace.shared.frontmostApplication
        onBegin?()
        for screen in NSScreen.screens {
            let w = SaverWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.backgroundColor = .black
            w.isOpaque = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            if let v = makeView(NSRect(origin: .zero, size: screen.frame.size)) {
                w.contentView = v
                v.start()
                views.append(v)
            }
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        NSCursor.hide()
        began = CACurrentMediaTime()
        // Keys and clicks that reach the app end the show and go no further.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown,
                                                              .otherMouseDown, .scrollWheel, .mouseMoved]) { [weak self] e in
            guard let self = self, self.isShowing else { return e }
            if CACurrentMediaTime() - self.began > 0.7 { self.end() }
            return nil
        }
        // Any input anywhere ends it too, even if another app kept the keyboard.
        let p = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let shown = CACurrentMediaTime() - self.began
            if shown > 0.7 && self.idleSeconds < shown - 0.5 { self.end() }
            else if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { self.end() }
        }
        RunLoop.main.add(p, forMode: .common)
        poll = p
    }

    func end() {
        guard isShowing else { return }
        isShowing = false
        poll?.invalidate(); poll = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        for v in views { v.stop() }
        for w in windows { w.orderOut(nil); w.contentView = nil }
        views = []; windows = []
        NSCursor.unhide()
        if let app = previousApp, app != NSRunningApplication.current { app.activate() }
        previousApp = nil
        onEnd?()
    }
}
