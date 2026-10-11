// Pulls a film frame out of a screenshot of a framed photo (the Analog
// pack's "Beach" frame, from a 468 x 584 Instagram screenshot): cleans the
// overlaid Instagram icons (coordinates below are for that shot), cuts the
// photo out, makes it 9:16 at the source's scale. Then finish_frame.swift
// enlarges it to 1152 x 2048, names it by its margins and writes the
// imageset and thumbnail.
//   cat img.swift extract_frame.swift > a.swift && swiftc -O a.swift -o extract
//   ./extract <screenshot.png> <work-dir>          -> <work-dir>/small.png
//   cat img.swift finish_frame.swift > b.swift && swiftc -O b.swift -o finish
//   ./finish <work-dir>/small.png <out-dir> <Label>

import Foundation
var m = load(CommandLine.arguments[1])
let outDir = CommandLine.arguments[2]
let W = m.w, H = m.h
func px(_ x: Int, _ y: Int) -> Int { (y*W+x)*4 }
func copyPixel(from: (Int, Int), to: (Int, Int)) { for c in 0..<4 { m.p[px(to.0, to.1)+c] = m.p[px(from.0, from.1)+c] } }

// 1. The screenshot's own 1 px dark edge (row 0 / column 0): white.
for x in 0..<W { for c in 0..<3 { m.p[px(x,0)+c] = 1 } }
for y in 0..<H { for x in 0...1 { for c in 0..<3 { m.p[px(x,y)+c] = 1 } } }
// 2. Instagram's "next" arrow on the right edge and profile icon at the bottom
//    left: border copied down from just above them.
for y in 276...314 { for x in 418..<W { copyPixel(from: (x, y - 40), to: (x, y)) } }
for y in 544...571 { for x in 0...44 { copyPixel(from: (x, y - 32), to: (x, y)) } }

// 3. The photo window: inside the black edge on every side.
func lum(_ x: Int, _ y: Int) -> Float { let i = px(x,y); return 0.299*m.p[i]+0.587*m.p[i+1]+0.114*m.p[i+2] }
func median(_ a: [Int]) -> Int { a.sorted()[a.count/2] }
func smooth(_ a: [Int], _ r: Int) -> [Int] { a.indices.map { i in median(Array(a[max(0,i-r)...min(a.count-1,i+r)])) } }
// From the outside in: past the white margin, through the dark edge (if
// there is one there); the photo starts at the first pixel that is neither.
func isWhite(_ x: Int, _ y: Int) -> Bool {
    let i = px(x,y); let mx = max(m.p[i], m.p[i+1], m.p[i+2]), mn = min(m.p[i], m.p[i+1], m.p[i+2])
    return mn > 0.86 && mx - mn < 0.08
}
func isMark(_ x: Int, _ y: Int) -> Bool {   // the red / orange edge markings
    let i = px(x,y); return m.p[i] > 0.45 && m.p[i] - m.p[i+1] > 0.22 && m.p[i] - m.p[i+2] > 0.22
}
func isBorder(_ x: Int, _ y: Int) -> Bool { isWhite(x, y) || isMark(x, y) || lum(x, y) < 0.3 }
func inner(_ pts: [(Int, Int)], limit: Int) -> Int {
    var i = 0
    while i < limit && (isWhite(pts[i].0, pts[i].1) || isMark(pts[i].0, pts[i].1)) { i += 1 }
    // The soft step from margin to black edge: jump to the black.
    if let d = (i..<min(i + 6, limit)).first(where: { lum(pts[$0].0, pts[$0].1) < 0.3 }) { i = d }
    while i < limit && lum(pts[i].0, pts[i].1) < 0.3 { i += 1 }
    return i
}
var leftE = [Int](), rightE = [Int](), topE = [Int](), botE = [Int]()
for y in 0..<H {
    leftE.append(inner((0..<W).map { ($0, y) }, limit: 60))
    rightE.append(W - 1 - inner((0..<W).reversed().map { ($0, y) }, limit: 60))
}
for x in 0..<W {
    topE.append(inner((0..<H).map { (x, $0) }, limit: 30))
    botE.append(H - 1 - inner((0..<H).reversed().map { (x, $0) }, limit: 30))
}
// Smoothed, and kept near each side's typical edge so dark parts of the
// photo next to the border never count as border.
func tame(_ a: [Int], _ lo: Int, _ hi: Int) -> [Int] {
    let mid = median(Array(a[lo..<hi]))
    return smooth(a, 2).map { min(max($0, mid - 4), mid + 4) }
}
leftE = tame(leftE, 40, H-40); rightE = tame(rightE, 40, H-40)
topE = tame(topE, 60, W-60); botE = tame(botE, 60, W-60)
print("edges L \(median(leftE)) R \(median(rightE)) T \(median(topE)) B \(median(botE))")
// Smoother outline (moving average), then pixel by pixel near it: black
// edge, white margin and marks stay; anything else is photo. Away from the
// outline: inside is photo, outside is frame.
func average(_ a: [Int], _ r: Int) -> [Int] {
    a.indices.map { i in let w = a[max(0,i-r)...min(a.count-1,i+r)]; return Int((Double(w.reduce(0,+)) / Double(w.count)).rounded()) }
}
leftE = average(leftE, 4); rightE = average(rightE, 4); topE = average(topE, 4); botE = average(botE, 4)
let band = 5
for y in 0..<H { for x in 0..<W {
    let dl = x - leftE[y], dr = rightE[y] - x, dt = y - topE[x], db = botE[x] - y
    let d = min(dl, dr, dt, db)                  // > 0 inside the window
    if d > band { m.p[px(x,y)+3] = 0 }
    else if d >= -band && !isBorder(x, y) { m.p[px(x,y)+3] = 0 }
    // Inside the outline the margin can't be: bright photo (sand, sky) goes.
    else if d > 0 && isWhite(x, y) { m.p[px(x,y)+3] = 0 }
}}

// The screenshot cut off the top of the frame: the top edge is the bottom
// edge flipped (its printed numbers left out — they'd read upside down).
let bandH = 15
func markAt(_ x: Int, _ y: Int) -> Bool {
    let i = px(x, y); return m.p[i] > 0.4 && m.p[i] - m.p[i+1] > 0.18 && m.p[i] - m.p[i+2] > 0.18
}
for r in 0..<bandH {
    let sy = H - 1 - r
    for x in 0..<W {
        // A printed mark: filled from the nearest unmarked pixel in its row.
        var sx = x
        if markAt(x, sy) || (x > 0 && markAt(x - 1, sy)) || (x < W - 1 && markAt(x + 1, sy)) {
            for k in 3...24 {
                if x - k >= 0 && !markAt(x - k, sy) && !markAt(max(x - k - 1, 0), sy) { sx = x - k; break }
                if x + k < W && !markAt(x + k, sy) && !markAt(min(x + k + 1, W - 1), sy) { sx = x + k; break }
            }
        }
        for c in 0..<4 { m.p[px(x, r)+c] = m.p[px(sx, sy)+c] }
    }
}
// Rows just below it, where the old top edge was: the window reaches up
// to the new edge.
for y in bandH..<(bandH + 6) { for x in (leftE[y] + 1)..<rightE[y] where !(lum(x, y) < 0.3 && (x < leftE[y] + 4 || x > rightE[y] - 4)) {
    m.p[px(x,y)+3] = 0
}}

// 4. 9:16 at the source's scale: white padding, the border's top part (with
//    the top corners), a repeated middle stretch of the side edges, then
//    the bottom part (with the bottom corners and marks), blended at seams.
let pad = 22, shiftX = 4
let Wt = W, Ht = Int((Double(Wt) * 16 / 9).rounded())
let srcTop = 1, srcBottom = H - 1           // border rows used (top margin is cut off in the shot)
let topRows = 290                           // source rows srcTop..<srcTop+topRows
let botStart = 291                          // source rows botStart...srcBottom
let tTop = pad
let tBotEnd = Ht - pad + 5                  // the bottom marks sit in the margin a little
let fill = (tBotEnd - tTop + 1) - topRows - (srcBottom - botStart + 1)
let fillSrc = 150
var t = Img(w: Wt, h: Ht, p: [Float](repeating: 1, count: Wt*Ht*4))
func srcRow(_ ty: Int) -> Double? {
    let k = ty - tTop
    if k < 0 { return nil }
    if k < topRows { return Double(srcTop + k) }
    if k < topRows + fill { return Double(fillSrc + (k - topRows)) }
    let b = botStart + (k - topRows - fill)
    return b <= srcBottom ? Double(b) : nil
}
let seam = 8
for ty in 0..<Ht {
    guard let sr = srcRow(ty) else { continue }
    let k = ty - tTop
    // Crossfade around the two seams.
    var mix: (Int, Int, Float)? = nil
    for s in [topRows, topRows + fill] where abs(k - s) < seam {
        let before = srcRow(ty - (k - s) - 1).map { Int($0) + (k - s) + 1 } ?? Int(sr)
        let w = Float(k - s + seam) / Float(2 * seam)
        mix = (min(max(before, 0), H-1), Int(sr), w)
    }
    for tx in 0..<Wt {
        let sx = tx - shiftX
        guard sx >= 1 && sx < W else { continue }
        let o = (ty*Wt+tx)*4
        if let (a, b, w) = mix {
            for c in 0..<4 { t.p[o+c] = m.p[px(sx,a)+c] * (1-w) + m.p[px(sx,b)+c] * w }
        } else {
            for c in 0..<4 { t.p[o+c] = m.p[px(sx,Int(sr))+c] }
        }
    }
}
save(t, "\(outDir)/small.png")
print("target \(Wt)x\(Ht) fill \(fill)")
