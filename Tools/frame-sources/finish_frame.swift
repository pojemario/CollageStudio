let small = load(CommandLine.arguments[1])
let outDir = CommandLine.arguments[2], label = CommandLine.arguments[3]
let W = 1152, H = 2048
// Upscale (premultiplied, high quality), then read back.
func cg(_ m: Img) -> CGImage {
    var b = [UInt8](repeating: 0, count: m.w*m.h*4)
    for i in 0..<(m.w*m.h) { let a = m.p[i*4+3]; for c in 0..<3 { b[i*4+c] = UInt8(max(0,min(255,(m.p[i*4+c]*a*255).rounded()))) }; b[i*4+3] = UInt8(max(0,min(255,(a*255).rounded()))) }
    let c = CGContext(data: &b, width: m.w, height: m.h, bitsPerComponent: 8, bytesPerRow: m.w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return c.makeImage()!
}
var big = [UInt8](repeating: 0, count: W*H*4)
let ctx = CGContext(data: &big, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(cg(small), in: CGRect(x: 0, y: 0, width: W, height: H))
var m = Img(w: W, h: H, p: [Float](repeating: 0, count: W*H*4))
func ss(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
for i in 0..<(W*H) {
    let a = Float(big[i*4+3]) / 255
    var r: Float = 1, g: Float = 1, b: Float = 1
    if a > 0 { r = Float(big[i*4]) / 255 / a; g = Float(big[i*4+1]) / 255 / a; b = Float(big[i*4+2]) / 255 / a }
    // Crisp edges again after the enlargement: the cut-out, and black vs white.
    let a2 = ss(0.25, 0.75, a)
    let mx = max(r, g, b), mn = min(r, g, b)
    if mx - mn < 0.18 {                         // greys: the black edge and the margin
        let l = 0.299*r + 0.587*g + 0.114*b
        let l2 = 0.06 + 0.94 * ss(0.22, 0.72, l)
        let k = l > 0.001 ? l2 / l : 0
        r = min(r * k, 1); g = min(g * k, 1); b = min(b * k, 1)
        if l < 0.001 { r = l2; g = l2; b = l2 }
    }
    m.p[i*4] = r; m.p[i*4+1] = g; m.p[i*4+2] = b; m.p[i*4+3] = a2
}
// The photo window's minimum margins (canvas points = half these pixels),
// measured over the middle of each side so the corners' curves don't count.
func firstClear(_ pts: [(Int, Int)]) -> Int { pts.firstIndex { m.p[($0.1*W+$0.0)*4+3] < 0.5 } ?? 0 }
var l = 0, r = 0, t = 0, bo = 0
for y in stride(from: H/10, to: H*9/10, by: 2) {
    l = max(l, firstClear((0..<W).map { ($0, y) })); r = max(r, firstClear((0..<W).reversed().map { ($0, y) }))
}
for x in stride(from: W/8, to: W*7/8, by: 2) {
    t = max(t, firstClear((0..<H).map { (x, $0) })); bo = max(bo, firstClear((0..<H).reversed().map { (x, $0) }))
}
let mg = [l, t, r, bo].map { Int((Double($0) / 2).rounded(.up)) }
let name = String(format: "Analog916_%@_m%02d%02d%02d%02d_r9x16", label, mg[0], mg[1], mg[2], mg[3])
print(name)
let dir = "\(outDir)/\(name).imageset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
save(m, "\(dir)/\(name).png")
func contents(_ file: String) -> String { "{\n  \"images\" : [\n    {\n      \"filename\" : \"\(file)\",\n      \"idiom\" : \"universal\"\n    }\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n" }
try! contents("\(name).png").write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
// Thumbnail: the top-left corner (420 x 747) over a soft sky, 180 x 320.
let tw = 180, th = 320
var thumb = Img(w: tw, h: th, p: [Float](repeating: 1, count: tw*th*4))
for y in 0..<th { for x in 0..<tw {
    let v = Float(y) / Float(th - 1)
    let sky: [Float] = [0.38 + 0.45 * v, 0.66 + 0.25 * v, 0.96 - 0.19 * v]
    let sx = min(Int(Float(x) * 420 / Float(tw)), W - 1), sy = min(Int(Float(y) * 747 / Float(th)), H - 1)
    let i = (sy*W+sx)*4, a = m.p[i+3]
    for c in 0..<3 { thumb.p[(y*tw+x)*4+c] = m.p[i+c] * a + sky[c] * (1 - a) }
}}
let tdir = "\(outDir)/\(name)_Thumb.imageset"
try? FileManager.default.createDirectory(atPath: tdir, withIntermediateDirectories: true)
save(thumb, "\(tdir)/\(name)_Thumb.png")
try! contents("\(name)_Thumb.png").write(toFile: "\(tdir)/Contents.json", atomically: true, encoding: .utf8)
