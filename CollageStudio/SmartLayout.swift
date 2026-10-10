import SwiftUI
import Vision

// MARK: - Subject-aware cropping

enum FocusFinder {
    /// Where a picture's subject is, in normalized image coordinates (0...1,
    /// y down): the faces if there are any, else what draws the eye; nil
    /// when nothing stands out.
    static func focus(in image: PlatformImage) -> CGPoint? {
        guard let cg = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let faces = VNDetectFaceRectanglesRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        // One at a time: one failing doesn't take the other down with it.
        try? handler.perform([faces])
        try? handler.perform([attention])
        // Vision's rectangles are normalized with the origin at the bottom left.
        func center(of rects: [CGRect]) -> CGPoint? {
            guard let first = rects.first else { return nil }
            let union = rects.dropFirst().reduce(first) { $0.union($1) }
            return CGPoint(x: union.midX, y: 1 - union.midY)
        }
        // Faces win; small background faces are left out.
        let faceRects = (faces.results ?? []).map(\.boundingBox)
        if let largest = faceRects.map({ $0.width * $0.height }).max() {
            return center(of: faceRects.filter { $0.width * $0.height >= largest * 0.25 })
        }
        let salient = (attention.results?.first?.salientObjects ?? []).map(\.boundingBox)
        guard let point = center(of: salient) else { return nil }
        // Something dead center needs no help.
        return abs(point.x - 0.5) < 0.04 && abs(point.y - 0.5) < 0.04 ? nil : point
    }
}

extension CollageState {
    /// Finds the subject of every photo that hasn't been looked at yet, off
    /// the main thread; each box then crops around it.
    func detectFocusPoints() {
        let todo = pages.flatMap(\.images).filter {
            $0.canProtrude && $0.focus == nil && !focusChecked.contains($0.id)
        }
        for img in todo {
            focusChecked.insert(img.id)
            let id = img.id, proxy = img.proxy, source = img.image
            Task.detached(priority: .utility) {
                var point = FocusFinder.focus(in: proxy)
                #if DEBUG
                // Vision's models don't run in the Simulator: `-fakeFocus`
                // stands in, to check the cropping there.
                if point == nil, ProcessInfo.processInfo.arguments.contains("-fakeFocus") {
                    point = CGPoint(x: 0.7, y: 0.3)
                }
                #endif
                let found = point
                await MainActor.run {
                    guard let point = found, let pi = self.pageIndex(containing: id),
                          let idx = self.pages[pi].images.firstIndex(where: { $0.id == id }),
                          self.pages[pi].images[idx].image === source else { return }
                    var img = self.pages[pi].images[idx]
                    img.focus = point
                    if let pan = Self.focusPan(for: img, boxSize: img.lastBoxSize) { img.panOffset = pan }
                    self.pages[pi].images[idx] = img
                    self.scheduleAutosave()
                }
            }
        }
    }

    /// The pan (normalized) that brings a photo's subject as close to the
    /// middle of its box as the crop allows — for photos the user hasn't
    /// positioned by hand.
    static func focusPan(for img: CollageImage, boxSize: CGSize) -> CGSize? {
        guard let f = img.focus, !img.framedByUser, boxSize.width > 1, boxSize.height > 1,
              let base = ImagePlacement.compute(natural: img.naturalSize, boxSize: boxSize, zoom: img.zoom,
                                                rotation: img.rotation, pan: .zero) else { return nil }
        let p = base.boxPoint(f.x, f.y)
        guard let placed = ImagePlacement.compute(natural: img.naturalSize, boxSize: boxSize, zoom: img.zoom,
                                                  rotation: img.rotation,
                                                  pan: CGSize(width: -p.x, height: -p.y)) else { return nil }
        return normalizedPan(placed.offset, in: boxSize)
    }

    // MARK: - Photos into fitting boxes

    /// An order for a fresh page that puts tall photos into the tallest boxes
    /// and wide ones into the widest. Boxes differ when the lanes hold
    /// different numbers of photos (5 photos in 2 columns: 3 and 2); photos
    /// are otherwise kept in the order given.
    static func fittingOrder(_ images: [CollageImage], numCols: Int, canvas: CGSize, rows: Bool) -> [UUID] {
        let n = images.count
        let cols = max(1, min(numCols, n))
        guard n > cols, n % cols != 0, canvas.width > 0, canvas.height > 0 else { return images.map(\.id) }
        // Round-robin: position p goes to lane p % cols.
        let counts = (0..<cols).map { j in (n - j + cols - 1) / cols }
        func slotAspect(_ p: Int) -> CGFloat {
            let k = CGFloat(counts[p % cols])
            // Box height / width, in columns or (transposed) rows.
            return rows
                ? (canvas.height / CGFloat(cols)) / (canvas.width / k)
                : (canvas.height / k) / (canvas.width / CGFloat(cols))
        }
        func aspect(_ img: CollageImage) -> CGFloat {
            img.naturalSize.height / max(img.naturalSize.width, 1)
        }
        let slots = (0..<n).sorted { (slotAspect($0), $0) < (slotAspect($1), $1) }
        let byShape = images.indices.sorted { (aspect(images[$0]), $0) < (aspect(images[$1]), $1) }
        var order = [UUID](repeating: images[0].id, count: n)
        for (slot, imageIndex) in zip(slots, byShape) { order[slot] = images[imageIndex].id }
        return order
    }
}
