// Makes the Mistfall app icon set from a picture of the orb.
//   swiftc -O tools/make-icon.swift -o /tmp/mistfall-make-icon
//   /tmp/mistfall-make-icon <picture.png> Mistfall/Assets.xcassets/AppIcon.appiconset [centreX centreY zoom]
// centreX and centreY say where in the picture the icon is centred (0 to 1, from the top
// left; default 0.5 0.5) and zoom is how much of the shorter side it shows (default 0.86).
import AppKit

let args = CommandLine.arguments
guard args.count > 2, let src = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: make-icon <orb.png> <AppIcon.appiconset>"); exit(2)
}
let out = URL(fileURLWithPath: args[2])
let nums = args.dropFirst(3).compactMap { Double($0) }
let centreX = nums.count > 0 ? nums[0] : 0.5, centreY = nums.count > 1 ? nums[1] : 0.5
let zoom = nums.count > 2 ? nums[2] : 0.86
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let s = CGFloat(px)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    // The macOS icon shape: a rounded square inset in the canvas, with a soft shadow.
    let box = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = CGPath(roundedRect: box, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10 / 1024), blur: s * 22 / 1024, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // The middle square of the picture, a little enlarged so the orb fills the icon.
    let side = CGFloat(min(src.width, src.height)) * CGFloat(zoom)
    let x = min(max(CGFloat(src.width) * CGFloat(centreX) - side / 2, 0), CGFloat(src.width) - side)
    let y = min(max(CGFloat(src.height) * CGFloat(centreY) - side / 2, 0), CGFloat(src.height) - side)
    let crop = CGRect(x: x, y: y, width: side, height: side)
    if let c = src.cropping(to: crop) { ctx.draw(c, in: box) }
    ctx.restoreGState()
    ctx.addPath(shape); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(max(s * 2 / 1024, 0.5)); ctx.strokePath()
    guard let img = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
}

var images: [String] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = "icon_\(px).png"
    let file = out.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: file.path) || true {
        guard let data = render(px) else { print("could not draw \(px)"); exit(3) }
        try data.write(to: file)
    }
    images.append("    { \"idiom\" : \"mac\", \"size\" : \"\(pt)x\(pt)\", \"scale\" : \"\(scale)x\", \"filename\" : \"\(name)\" }")
}
let json = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try json.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("icon set written to \(out.path)")
