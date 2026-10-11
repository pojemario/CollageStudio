import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
struct Img { var w: Int; var h: Int; var p: [Float] } // RGBA 0..1, straight alpha
func load(_ path: String) -> Img {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let im = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = im.width, h = im.height
    var b = [UInt8](repeating: 0, count: w*h*4)
    let c = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Img(w: w, h: h, p: b.map { Float($0) / 255 })
}
func save(_ m: Img, _ path: String) {
    var b = [UInt8](repeating: 0, count: m.w*m.h*4)
    for i in 0..<(m.w*m.h) { let a = m.p[i*4+3]; for c in 0..<3 { b[i*4+c] = UInt8(max(0,min(255,(m.p[i*4+c]*a*255).rounded()))) }; b[i*4+3] = UInt8(max(0,min(255,(a*255).rounded()))) }
    let c = CGContext(data: &b, width: m.w, height: m.h, bitsPerComponent: 8, bytesPerRow: m.w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c.makeImage()!, nil); CGImageDestinationFinalize(d)
}
extension Img {
    func lum(_ x: Int, _ y: Int) -> Float { let i=(y*w+x)*4; return 0.299*p[i]+0.587*p[i+1]+0.114*p[i+2] }
}
