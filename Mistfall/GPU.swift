#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Metal
import QuartzCore

// Mistfall on the graphics chip. The engine still works out where every dot is;
// this draws them, the trails, the glow and the final colours with Metal, so the
// processor no longer touches every pixel of every frame. The built-in drawing
// in Engine.swift stays as the fallback for a Mac with no Metal device.

/// One thing to draw: a soft point (start == end), a streak or line (start to
/// end), or a round light (kind = its radius in pixels). Colour is total light.
struct GPUDot {
    var x0: Float, y0: Float, x1: Float, y1: Float
    var r: Float, g: Float, b: Float, kind: Float
}

/// One Cipherfall character: a 5 x 7 block of dots, lit or faint.
struct GPUCell {
    var x0: Float, yTop: Float, off: Float, mirror: Float
    var r: Float, g: Float, b: Float, pad: Float = 0
    var lo: UInt32, hi: UInt32, p0: UInt32 = 0, p1: UInt32 = 0
}

/// Per-frame numbers shared with the shaders (same layout as `Frame` below).
struct GPUFrame {
    var size = SIMD2<Float>(1, 1)
    var fade: Float = 1
    var glowK: Float = 0
    var haze = SIMD4<Float>(0, 0, 0, 1)      // haze colour, then exposure
    var bleach: Float = 0
    var pitch: Float = 4
    var invR2: Float = 1
    var pad: Float = 0
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Frame { float2 size; float fade; float glowK; float4 haze; float bleach; float pitch; float invR2; float pad; };
struct Dot { float2 p0; float2 p1; float4 colk; };
struct Cell { float4 a; float4 col; uint4 bits; };

struct QuadOut { float4 pos [[position]]; float2 uv; };

vertex QuadOut quadVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    QuadOut o;
    o.pos = float4(p * 2 - 1, 0, 1);
    o.uv = float2(p.x, 1 - p.y);
    return o;
}

// Smooth shapes (the iridescent glass): plain triangles carrying their own light.
struct Tri { packed_float2 p; packed_float4 c; };
struct TriOut { float4 pos [[position]]; float4 col; };

vertex TriOut triVertex(uint vid [[vertex_id]], const device Tri *tris [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    Tri t = tris[vid];
    TriOut o;
    o.pos = float4(float2(t.p) / f.size * 2 - 1, 0, 1);
    o.col = float4(t.c);
    return o;
}

fragment float4 triFragment(TriOut i [[stage_in]]) {
    return float4(i.col.rgb, 0);
}

// Trails: everything already drawn dims a little.
fragment float4 fadeFragment(QuadOut i [[stage_in]], constant Frame &f [[buffer(0)]]) {
    return float4(f.fade);
}

struct DotOut {
    float4 pos [[position]];
    float2 uv;
    float3 col [[flat]];
    float2 ext [[flat]];      // length of the streak, radius of a round light
};

vertex DotOut dotVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        const device Dot *dots [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    Dot d = dots[iid];
    float2 c = float2(vid & 1, vid >> 1);
    DotOut o;
    float2 p;
    float kind = d.colk.w;
    if (kind > 0) {
        float h = kind + 1;
        float2 q = (c * 2 - 1) * h;
        p = d.p0 + q;
        o.uv = q;
        o.ext = float2(0, kind);
    } else {
        float2 D = d.p1 - d.p0;
        float L = length(D);
        float2 ax = L > 1e-4 ? D / L : float2(1, 0);
        float2 pr = float2(-ax.y, ax.x);
        float u = mix(-1.0, L + 1.0, c.x);
        float v = c.y * 2 - 1;
        p = d.p0 + ax * u + pr * v;
        o.uv = float2(u, v);
        o.ext = float2(L, 0);
    }
    o.pos = float4(p / f.size * 2 - 1, 0, 1);
    o.col = d.colk.xyz;
    return o;
}

// The area under a one-pixel soft edge up to x.
static float cum(float x) {
    if (x <= -1) return 0;
    if (x < 0) return (x + 1) * (x + 1) * 0.5;
    if (x < 1) return 1 - (1 - x) * (1 - x) * 0.5;
    return 1;
}

fragment float4 dotFragment(DotOut i [[stage_in]]) {
    float w;
    if (i.ext.y > 0) {
        float R = i.ext.y;
        w = max(0.0, 1 - dot(i.uv, i.uv) / (R * R)) / (3.14159265 * R * R * 0.5);
    } else {
        float L = i.ext.x;
        float across = max(0.0, 1 - abs(i.uv.y));
        float along = L > 1e-3 ? (cum(i.uv.x) - cum(i.uv.x - L)) / L : max(0.0, 1 - abs(i.uv.x));
        w = across * along;
    }
    return float4(i.col * w, 0);
}

struct CellOut {
    float4 pos [[position]];
    float2 p;
    float4 a [[flat]];
    float3 col [[flat]];
    uint2 bits [[flat]];
};

vertex CellOut cellVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                          const device Cell *cells [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    Cell c = cells[iid];
    float2 k = float2(vid & 1, vid >> 1);
    CellOut o;
    o.p = float2(c.a.x + mix(-0.5, 4.5, k.x) * f.pitch, c.a.y + mix(0.5, -6.5, k.y) * f.pitch);
    o.pos = float4(o.p / f.size * 2 - 1, 0, 1);
    o.a = c.a;
    o.col = c.col.xyz;
    o.bits = c.bits.xy;
    return o;
}

fragment float4 cellFragment(CellOut i [[stage_in]], constant Frame &f [[buffer(0)]]) {
    float2 l = float2(i.p.x - i.a.x, i.a.y - i.p.y) / f.pitch;
    float2 g = clamp(round(l), float2(0), float2(4, 6));
    float2 d = (l - g) * f.pitch;
    float wgt = 1 - dot(d, d) * f.invR2;
    if (wgt <= 0) discard_fragment();
    float q = min(wgt * 2.2, 1.0);
    uint gx = uint(g.x), gy = uint(g.y);
    uint row = gy < 6 ? (i.bits.x >> (gy * 5)) & 31u : i.bits.y & 31u;
    uint bit = i.a.w > 0.5 ? gx : 4 - gx;
    bool lit = ((row >> bit) & 1u) == 1u;
    float off = i.a.z;
    float3 c = lit ? i.col : float3(0.04 * off, off, 0.25 * off);
    return float4(c * q, 0);
}

// Glow: a quarter-size copy of the light, then blurred.
fragment float4 downFragment(QuadOut i [[stage_in]], texture2d<float> acc [[texture(0)]]) {
    uint2 ip = uint2(i.pos.xy) * 4;
    float4 s = float4(0);
    for (uint y = 0; y < 4; y++)
        for (uint x = 0; x < 4; x++)
            s += acc.read(ip + uint2(x, y));
    return s / 16;
}

fragment float4 blurFragment(QuadOut i [[stage_in]], texture2d<float> src [[texture(0)]], constant int2 &dir [[buffer(0)]]) {
    int2 ip = int2(i.pos.xy);
    int2 mx = int2(src.get_width() - 1, src.get_height() - 1);
    float4 s = float4(0);
    for (int k = -3; k <= 3; k++)
        s += src.read(uint2(clamp(ip + dir * k, int2(0), mx)));
    return s / 7;
}

// Light to screen colours.
fragment float4 composeFragment(QuadOut i [[stage_in]], texture2d<float> acc [[texture(0)]], texture2d<float> glow [[texture(1)]],
                                sampler s [[sampler(0)]], constant Frame &f [[buffer(0)]]) {
    float3 c = acc.sample(s, i.uv).rgb;
    if (f.glowK > 0) c += f.glowK * glow.sample(s, i.uv).rgb;
    c += f.haze.xyz;
    float m = (c.r + c.g + c.b) * 0.333;
    float wb = m * m * 0.12 * f.bleach;
    c = (c + wb) * f.haze.w;
    return float4(1 - exp(-c), 1);
}
"""

/// Hands out buffers for one frame's dots and takes them back when the graphics
/// chip has finished with them, so a frame being drawn is never overwritten.
private final class BufferPool {
    private let device: MTLDevice
    private let length: Int
    private var free: [MTLBuffer] = []
    private let lock = NSLock()

    init(device: MTLDevice, length: Int) { self.device = device; self.length = length }

    func take() -> MTLBuffer? {
        lock.lock(); defer { lock.unlock() }
        return free.popLast() ?? device.makeBuffer(length: length, options: .storageModeShared)
    }

    func give(_ b: MTLBuffer) {
        lock.lock(); free.append(b); lock.unlock()
    }
}

final class GPURenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let fadePipe: MTLRenderPipelineState
    private let dotPipe: MTLRenderPipelineState
    private let cellPipe: MTLRenderPipelineState
    private let triPipe: MTLRenderPipelineState
    private let downPipe: MTLRenderPipelineState
    private let blurPipe: MTLRenderPipelineState
    private let composePipe: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let accFormat: MTLPixelFormat
    private let glowFormat = MTLPixelFormat.rgba16Float
    private var accTex: MTLTexture?
    private var smallTex: MTLTexture?
    private var tmpTex: MTLTexture?
    private var shotTex: MTLTexture?
    private(set) var width = 0
    private(set) var height = 0

    let dotCapacity: Int
    let cellCapacity = 16384
    let triCapacity = prismVertexCount
    private let triPool: BufferPool
    private var triBuf: MTLBuffer?
    /// This frame's triangle corners; the engine writes them here and sets triCount.
    private(set) var tris: UnsafeMutablePointer<PrismVertex>?
    var triCount = 0
    private let dotPool: BufferPool
    private let cellPool: BufferPool
    private var dotBuf: MTLBuffer?
    private var cellBuf: MTLBuffer?
    /// This frame's dots; the engine writes them here and sets dotCount.
    private(set) var dots: UnsafeMutablePointer<GPUDot>?
    private var cells: UnsafeMutablePointer<GPUCell>?
    var dotCount = 0
    private(set) var cellCount = 0
    var cellPitch: Float = 4
    var cellInvR2: Float = 1
    /// The dimming still owed from the frame before (it is applied after showing).
    private var pendingFade: Float = 1
    private var last = GPUFrame()

    init?(dots count: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        accFormat = device.supports32BitFloatFiltering ? .rgba32Float : .rgba16Float
        dotCapacity = count + 8192
        dotPool = BufferPool(device: device, length: dotCapacity * MemoryLayout<GPUDot>.stride)
        cellPool = BufferPool(device: device, length: cellCapacity * MemoryLayout<GPUCell>.stride)
        triPool = BufferPool(device: device, length: triCapacity * MemoryLayout<PrismVertex>.stride)
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            func pipe(_ v: String, _ f: String, _ format: MTLPixelFormat,
                      blend: (MTLBlendFactor, MTLBlendFactor)? = nil) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                let a = d.colorAttachments[0]!
                a.pixelFormat = format
                if let b = blend {
                    a.isBlendingEnabled = true
                    a.rgbBlendOperation = .add; a.alphaBlendOperation = .add
                    a.sourceRGBBlendFactor = b.0; a.sourceAlphaBlendFactor = b.0
                    a.destinationRGBBlendFactor = b.1; a.destinationAlphaBlendFactor = b.1
                }
                return try device.makeRenderPipelineState(descriptor: d)
            }
            fadePipe = try pipe("quadVertex", "fadeFragment", accFormat, blend: (.zero, .sourceColor))
            dotPipe = try pipe("dotVertex", "dotFragment", accFormat, blend: (.one, .one))
            cellPipe = try pipe("cellVertex", "cellFragment", accFormat, blend: (.one, .one))
            triPipe = try pipe("triVertex", "triFragment", accFormat, blend: (.one, .one))
            downPipe = try pipe("quadVertex", "downFragment", glowFormat)
            blurPipe = try pipe("quadVertex", "blurFragment", glowFormat)
            composePipe = try pipe("quadVertex", "composeFragment", .bgra8Unorm)
        } catch {
            FileHandle.standardError.write("Mistfall: Metal set-up failed: \(error)\n".data(using: .utf8)!)
            return nil
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        guard let s = device.makeSamplerState(descriptor: sd) else { return nil }
        sampler = s
    }

    private func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, storage: MTLStorageMode = .private) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = storage
        return device.makeTexture(descriptor: d)
    }

    private func pass(_ cb: MTLCommandBuffer, _ target: MTLTexture, load: MTLLoadAction,
                      _ body: (MTLRenderCommandEncoder) -> Void) {
        let rp = MTLRenderPassDescriptor()
        let a = rp.colorAttachments[0]!
        a.texture = target
        a.loadAction = load
        a.storeAction = .store
        a.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        body(e)
        e.endEncoding()
    }

    func resize(width w: Int, height h: Int) {
        if w == width && h == height && accTex != nil { return }
        width = w; height = h
        let sw = max(w / 4, 4), sh = max(h / 4, 4)
        accTex = texture(accFormat, w, h)
        smallTex = texture(glowFormat, sw, sh)
        tmpTex = texture(glowFormat, sw, sh)
        shotTex = nil
        pendingFade = 1
        // New pictures hold rubbish until cleared.
        guard let cb = queue.makeCommandBuffer() else { return }
        for t in [accTex, smallTex, tmpTex] { if let t = t { pass(cb, t, load: .clear) { _ in } } }
        cb.commit()
    }

    /// Start a frame: fresh room for its dots and characters.
    func begin() {
        if let b = dotBuf { dotPool.give(b) }
        if let b = cellBuf { cellPool.give(b) }
        if let b = triBuf { triPool.give(b) }
        triBuf = triPool.take()
        tris = triBuf?.contents().bindMemory(to: PrismVertex.self, capacity: triCapacity)
        triCount = 0
        dotBuf = dotPool.take()
        cellBuf = cellPool.take()
        dots = dotBuf?.contents().bindMemory(to: GPUDot.self, capacity: dotCapacity)
        cells = cellBuf?.contents().bindMemory(to: GPUCell.self, capacity: cellCapacity)
        dotCount = 0
        cellCount = 0
    }

    @inline(__always) func add(_ d: GPUDot) {
        guard dotCount < dotCapacity, let dots = dots else { return }
        dots[dotCount] = d
        dotCount += 1
    }

    @inline(__always) func addCell(_ c: GPUCell) {
        guard cellCount < cellCapacity, let cells = cells else { return }
        cells[cellCount] = c
        cellCount += 1
    }

    /// Finish a frame: dim the old light, add this frame's, and rebuild the glow.
    func commit(fade: Float, glowK: Float, exposure: Float, haze: (Float, Float, Float), bleach: Float) {
        guard let acc = accTex, let small = smallTex, let tmp = tmpTex, let cb = queue.makeCommandBuffer() else { return }
        var f = GPUFrame()
        f.size = SIMD2(Float(width), Float(height))
        f.fade = pendingFade
        f.glowK = glowK
        f.haze = SIMD4(haze.0, haze.1, haze.2, exposure)
        f.bleach = bleach
        f.pitch = cellPitch
        f.invR2 = cellInvR2
        let fLen = MemoryLayout<GPUFrame>.stride
        let db = dotBuf, cbuf = cellBuf, tb = triBuf
        dotBuf = nil; cellBuf = nil; dots = nil; cells = nil; triBuf = nil; tris = nil
        pass(cb, acc, load: .load) { e in
            e.setRenderPipelineState(fadePipe)
            e.setFragmentBytes(&f, length: fLen, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if triCount > 0, let tb = tb {
                e.setRenderPipelineState(triPipe)
                e.setVertexBuffer(tb, offset: 0, index: 0)
                e.setVertexBytes(&f, length: fLen, index: 1)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triCount)
            }
            if dotCount > 0, let db = db {
                e.setRenderPipelineState(dotPipe)
                e.setVertexBuffer(db, offset: 0, index: 0)
                e.setVertexBytes(&f, length: fLen, index: 1)
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: dotCount)
            }
            if cellCount > 0, let cbuf = cbuf {
                e.setRenderPipelineState(cellPipe)
                e.setVertexBuffer(cbuf, offset: 0, index: 0)
                e.setVertexBytes(&f, length: fLen, index: 1)
                e.setFragmentBytes(&f, length: fLen, index: 0)
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: cellCount)
            }
        }
        if glowK > 0 {
            pass(cb, small, load: .dontCare) { e in
                e.setRenderPipelineState(downPipe)
                e.setFragmentTexture(acc, index: 0)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            // Two soft blurs, each across then down.
            for _ in 0..<2 {
                for (src, dst, dx, dy) in [(small, tmp, Int32(1), Int32(0)), (tmp, small, Int32(0), Int32(1))] {
                    pass(cb, dst, load: .dontCare) { e in
                        var dir = SIMD2<Int32>(dx, dy)
                        e.setRenderPipelineState(blurPipe)
                        e.setFragmentTexture(src, index: 0)
                        e.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
                        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    }
                }
            }
        }
        let dp = dotPool, cp = cellPool, tp = triPool
        cb.addCompletedHandler { _ in
            if let db = db { dp.give(db) }
            if let cbuf = cbuf { cp.give(cbuf) }
            if let tb = tb { tp.give(tb) }
        }
        cb.commit()
        pendingFade = fade
        last = f
    }

    private func compose(_ cb: MTLCommandBuffer, into target: MTLTexture) {
        guard let acc = accTex, let small = smallTex else { return }
        pass(cb, target, load: .dontCare) { e in
            var f = last
            e.setRenderPipelineState(composePipe)
            e.setFragmentTexture(acc, index: 0)
            e.setFragmentTexture(small, index: 1)
            e.setFragmentSamplerState(sampler, index: 0)
            e.setFragmentBytes(&f, length: MemoryLayout<GPUFrame>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
    }

    /// Show the picture in a Metal layer. Says what stopped it, or "ok".
    @discardableResult
    func present(in layer: CAMetalLayer) -> String {
        guard width > 0, accTex != nil else { return "no picture yet" }
        guard let drawable = layer.nextDrawable() else { return "no drawable" }
        guard let cb = queue.makeCommandBuffer() else { return "no command buffer" }
        compose(cb, into: drawable.texture)
        cb.present(drawable)
        cb.commit()
        return "ok"
    }

    /// The picture as an image (for saved pictures and checks).
    func snapshot() -> CGImage? {
        guard width > 0, accTex != nil, let cb = queue.makeCommandBuffer() else { return nil }
        if shotTex == nil {
            #if os(macOS)
            shotTex = texture(.bgra8Unorm, width, height, storage: device.hasUnifiedMemory ? .shared : .managed)
            #else
            shotTex = texture(.bgra8Unorm, width, height, storage: .shared)
            #endif
        }
        guard let shot = shotTex else { return nil }
        compose(cb, into: shot)
        #if os(macOS)
        if shot.storageMode == .managed, let b = cb.makeBlitCommandEncoder() {
            b.synchronize(resource: shot)
            b.endEncoding()
        }
        #endif
        cb.commit()
        cb.waitUntilCompleted()
        let rowBytes = width * 4
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
        shot.getBytes(bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let data = Data(bytesNoCopy: bytes, count: rowBytes * height, deallocator: .custom { p, _ in p.deallocate() })
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: space, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}

#if os(macOS)
/// The view the graphics chip draws into.
final class MetalCanvas: NSView {
    let metalLayer = CAMetalLayer()

    init(frame: NSRect, device: MTLDevice) {
        super.init(frame: frame)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer = metalLayer
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Match the picture to the view, at most maxWidth pixels wide.
    func fit(scale: CGFloat, maxWidth: CGFloat) {
        var w = bounds.width * scale, h = bounds.height * scale
        if w > maxWidth { h *= maxWidth / w; w = maxWidth }
        let size = CGSize(width: max(w.rounded(), 1), height: max(h.rounded(), 1))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }
}

/// Text drawn over the picture (hints, the frame rate).
final class HUDView: NSView {
    var onDraw: ((NSRect) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { onDraw?(bounds) }
}
#endif
