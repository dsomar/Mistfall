// Runs the real screen saver view from a built Mistfall.saver in a plain window
// for a few seconds, to check it starts and draws outside System Settings.
// (The preview app cannot load a locally built saver: macOS refuses to mix
// differently signed code in an app with the hardened runtime.)
//
//   swiftc tools/saver-test.swift -o /tmp/mistfall-saver-test
//   /tmp/mistfall-saver-test /path/to/Mistfall.saver [seconds]
import AppKit
import ScreenSaver

let args = CommandLine.arguments
guard args.count > 1, let bundle = Bundle(path: args[1]) else { print("usage: saver-test <Mistfall.saver> [seconds]"); exit(2) }
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
do { try bundle.loadAndReturnError() } catch { print("saver: load failed: \(error)"); exit(2) }
guard let cls = bundle.principalClass as? ScreenSaverView.Type else { print("saver: no screen saver class"); exit(2) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let rect = NSRect(x: 0, y: 0, width: 1024, height: 768)
guard let saver = cls.init(frame: rect, isPreview: false) else { print("saver: init failed"); exit(3) }
let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Mistfall saver test"
window.contentView = saver
window.center()
window.orderFront(nil)
saver.startAnimation()
var frames = 0
let start = Date()
let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in saver.animateOneFrame(); frames += 1 }
RunLoop.main.add(timer, forMode: .common)
/// What the window really shows on screen (a Metal picture is not caught by cacheDisplay).
/// A process may read its own windows without the screen recording permission.
func windowPicture() -> CGImage? {
    typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
    let f = unsafeBitCast(sym, to: Fn.self)
    return f(.null, 1 << 3, UInt32(window.windowNumber), 1)?.takeRetainedValue()
}

DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    if let img = windowPicture() {
        let rep = NSBitmapImageRep(cgImage: img)
        var sum = 0.0, lit = 0, n = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let v = Double(c.redComponent + c.greenComponent + c.blueComponent) / 3
                sum += v; n += 1
                if v > 0.04 { lit += 1 }
            }
        }
        print(String(format: "on screen: %dx%d, mean brightness %.4f, lit %.1f%%", rep.pixelsWide, rep.pixelsHigh, sum / Double(max(n, 1)), 100 * Double(lit) / Double(max(n, 1))))
        if args.count > 3, let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: args[3])) }
    } else { print("on screen: could not read the window") }
    let kinds = saver.subviews.map { String(describing: type(of: $0)) }.joined(separator: ",")
    let rate = Double(frames) / Date().timeIntervalSince(start)
    print(String(format: "saver ok: %.0f frames a second, subviews=[%@], settings sheet=%@", rate, kinds,
                 saver.hasConfigureSheet && saver.configureSheet != nil ? "yes" : "no"))
    exit(0)
}
app.run()
