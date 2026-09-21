import SwiftUI

/// Frames tab / sidebar section: a chip per frame collection — "Basic" (the
/// adaptive frame sets that follow any format) plus every bundled frame pack —
/// and the frames of the chosen collection below. One collection at a time
/// keeps the panel the same height no matter how many packs are bundled.
struct FramesPanel: View {
    @EnvironmentObject var state: CollageState
    /// nil shows the basic, format-independent frames.
    @State private var selectedPackId: String? = nil

    private var selectedPack: FramePack? {
        CollageState.framePacks.first { $0.id == selectedPackId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PackChip(title: "Basic", isActive: selectedPackId == nil) { selectedPackId = nil }
                    ForEach(CollageState.framePacks) { pack in
                        PackChip(title: pack.title, isActive: selectedPackId == pack.id) {
                            selectedPackId = pack.id
                        }
                    }
                }
            }

            FramePickerRow(pack: selectedPack)
        }
        .onAppear {
            // Open on the collection the current frame comes from.
            if let frame = state.canvasFrame {
                selectedPackId = CollageState.framePacks.first { $0.frames.contains(frame) }?.id
            }
        }
    }
}

/// Capsule chip for choosing a pack in the Frames and Overlay panels.
struct PackChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                // White text on a dark fill so it stays readable over the very
                // transparent glass panel.
                .foregroundColor(.white)
                .background(
                    Capsule().fill(isActive ? Color.accentColor : Color.black.opacity(0.55))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal chooser for the decorative canvas frame: "None" plus one option
/// per frame. Without a pack it lists the adaptive frame sets, previewed in
/// the current canvas ratio. With a pack the cells take the pack's format,
/// and picking one switches the canvas to that format — pack frames are used
/// as is, never stretched to another ratio.
struct FramePickerRow: View {
    @EnvironmentObject var state: CollageState
    var pack: FramePack? = nil

    /// Cell size: square for the adaptive sets, the pack's format otherwise.
    private var cellSize: CGSize {
        guard let pack else { return CGSize(width: 56, height: 56) }
        return pack.ratio.canvasSize(base: 88)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                frameOption(set: nil, label: "None")
                ForEach(pack?.frames ?? CollageState.availableFrames) { set in
                    frameOption(set: set, label: set.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private func frameOption(set: CanvasFrameSet?, label: String) -> some View {
        let isSelected = state.canvasFrame == set
        Button {
            if let set, let pack {
                state.applyFrame(set, from: pack)
            } else {
                state.canvasFrame = set
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemFill))
                    if let set, let preview = previewImage(for: set) {
                        #if canImport(UIKit)
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                        #else
                        Image(nsImage: preview)
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                        #endif
                    } else if set == nil {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: cellSize.width + 8, height: cellSize.height + 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
                Text(label)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Thumbnail of the variant for the current ratio, falling back to the
    /// 1:1 variant (pack frames only have their own format).
    private func previewImage(for set: CanvasFrameSet) -> PlatformImage? {
        let suffix = (pack?.ratio ?? state.ratio).rawValue.replacingOccurrences(of: ":", with: "x")
        guard let name = set.assetName(ratioSuffix: suffix) ?? set.assetName(ratioSuffix: "1x1") else {
            return nil
        }
        // Packs ship a "<asset>_Thumb" close-up of the frame's corner over a
        // sample picture; frames without one show the whole PNG.
        return FrameThumbnails.image(named: name + "_Thumb") ?? FrameThumbnails.image(named: name)
    }
}

/// Small cached copies of the frame PNGs for the pickers, so a row of cells
/// doesn't keep a full-resolution bitmap decoded per frame.
enum FrameThumbnails {
    private static var cache: [String: PlatformImage] = [:]

    static func image(named name: String) -> PlatformImage? {
        if let hit = cache[name] { return hit }
        guard let thumb = PlatformImage.named(name)?.downsampled(longEdge: 300) else { return nil }
        cache[name] = thumb
        return thumb
    }
}
