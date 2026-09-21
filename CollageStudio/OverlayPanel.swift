import SwiftUI

/// Overlay tab / sidebar section: pick a pack (dust & scratches, light
/// leaks) and tap a texture to preview it live on the collage. The preview
/// is adjustable like a layer — opacity, above or below the frame, and
/// placement by finger on the canvas — but only joins the layer stack with
/// "Add layer". Existing layers are edited by selecting them in the stack.
///
/// Choosing this panel puts the app in overlay mode: the collage is frozen
/// and canvas gestures move / zoom / rotate the edited overlay (double tap
/// resets) — see CollageState.overlayModeActive.
struct OverlayPanel: View {
    @EnvironmentObject var state: CollageState
    /// The sidebar is always on screen, so there it only enters overlay mode
    /// while a layer is being edited; the bottom tab is a mode by itself.
    var inSidebar = false
    @State private var selectedPackId: String = CollageState.overlayPacks.first?.id ?? ""

    private var selectedPack: OverlayPack? {
        CollageState.overlayPacks.first { $0.id == selectedPackId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CollageState.overlayPacks) { pack in
                            PackChip(title: pack.name, isActive: selectedPackId == pack.id) {
                                selectedPackId = pack.id
                            }
                        }
                    }
                }

                if let pack = selectedPack {
                    textureRow(pack: pack)
                }

                layerRow

                if let preview = state.overlayPreview {
                    previewBar(preview)
                }
            }
            .panelChrome(state)

            if let layer = state.editedOverlay {
                LabeledSlider(label: "Opacity", value: binding(for: layer.id, \.opacity),
                              range: 0...100, step: 1, format: "%.0f", resetValue: 100)
                positionRow(layerId: layer.id)
                Label("Drag, pinch and rotate on the collage · double-tap to reset",
                      systemImage: "hand.draw")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .panelChrome(state)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.overlayPreview?.id)
        .onAppear {
            if inSidebar { state.overlaySidebarShowing = true } else { state.overlayTabMode = true }
        }
        // Leaving the tab ends overlay mode and drops an unconfirmed preview.
        // Merely hiding the panel does neither — that's how the canvas gets
        // a clear view while an overlay is being placed.
        .onDisappear {
            if inSidebar {
                state.overlaySidebarShowing = false
                state.cancelOverlayPreview()
            } else {
                state.exitOverlayMode()
            }
        }
    }

    // MARK: - Textures (tap to preview)

    private func textureRow(pack: OverlayPack) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(pack.assets, id: \.self) { asset in
                    let isPreviewed = state.overlayPreview?.asset == asset
                    Button {
                        state.previewOverlay(asset: asset, kind: pack.kind)
                    } label: {
                        VStack(spacing: 4) {
                            OverlayThumbnail(asset: asset, height: 72)
                                .padding(2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isPreviewed ? Color.accentColor : .clear, lineWidth: 2)
                                )
                            Text(OverlayPack.label(forAsset: asset))
                                .font(.caption2)
                                .foregroundColor(isPreviewed ? .accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .disabled(!state.canAddOverlay)
        .opacity(state.canAddOverlay ? 1 : 0.4)
    }

    // MARK: - Preview bar (confirm or dismiss the texture being tried)

    private func previewBar(_ preview: OverlayLayer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 13, weight: .medium))
            Text("Previewing \(preview.label)")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                state.cancelOverlayPreview()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                state.commitOverlayPreview()
            } label: {
                Label("Add layer", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.55)))
        .transition(.opacity)
    }

    // MARK: - Layer stack

    private var layerRow: some View {
        HStack(spacing: 8) {
            Text("Layers")
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 76, alignment: .leading)
            if state.overlayLayers.isEmpty {
                Text(state.overlayPreview == nil ? "Tap an overlay to preview it" : "No layers yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(state.overlayLayers.enumerated()), id: \.element.id) { index, layer in
                            layerChip(layer, number: index + 1)
                        }
                    }
                }
            }
        }
    }

    /// One layer in the stack: tap to select (which ends any preview), tap
    /// again to deselect; the selected one can be removed.
    private func layerChip(_ layer: OverlayLayer, number: Int) -> some View {
        let isSelected = state.overlayPreview == nil && state.selectedOverlayId == layer.id
        return HStack(spacing: 6) {
            OverlayThumbnail(asset: layer.asset, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(number) · \(layer.label)")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: layer.aboveFrame ? "square.2.layers.3d.top.filled"
                                                   : "square.2.layers.3d.bottom.filled")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            if isSelected {
                Button {
                    state.removeOverlay(id: layer.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Color.accentColor : Color.black.opacity(0.55))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the selected layer deselects it (in the sidebar that
            // also hands the canvas back to the collage).
            state.selectedOverlayId = isSelected ? nil : layer.id
            state.cancelOverlayPreview()
        }
    }

    // MARK: - Selected layer controls

    private func positionRow(layerId: UUID) -> some View {
        HStack(spacing: 8) {
            Text("Position")
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 76, alignment: .leading)
            Picker("", selection: binding(for: layerId, \.aboveFrame)) {
                Text("Below frame").tag(false)
                Text("Above frame").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Match the sliders' value + swatch trailing block width
            Color.clear.frame(width: 44 + 8 + 24, height: 24)
        }
        .panelChrome(state)
    }

    /// Binding into the preview or a stacked layer, looked up by id, so a
    /// control that outlives its layer (mid-removal) never indexes out of range.
    private func binding<T>(for id: UUID, _ keyPath: WritableKeyPath<OverlayLayer, T>) -> Binding<T> {
        Binding(
            get: {
                let layer = (state.overlayPreview?.id == id ? state.overlayPreview : nil)
                    ?? state.overlayLayers.first { $0.id == id }
                    ?? OverlayLayer(asset: "", kind: .dust)
                return layer[keyPath: keyPath]
            },
            set: { newValue in
                if state.overlayPreview?.id == id {
                    state.overlayPreview?[keyPath: keyPath] = newValue
                } else if let idx = state.overlayLayers.firstIndex(where: { $0.id == id }) {
                    state.overlayLayers[idx][keyPath: keyPath] = newValue
                }
            }
        )
    }
}

/// Overlay texture preview. Packs ship a "<asset>_Thumb" picture — the
/// texture over a sample photo, dust zoomed in so it reads at this size;
/// without one the raw texture is shown on dark gray.
struct OverlayThumbnail: View {
    let asset: String
    let height: CGFloat

    var body: some View {
        ZStack {
            Color(white: 0.3)
            if let thumb = FrameThumbnails.image(named: asset + "_Thumb")
                ?? FrameThumbnails.image(named: asset) {
                #if canImport(UIKit)
                Image(uiImage: thumb).resizable().scaledToFill()
                #else
                Image(nsImage: thumb).resizable().scaledToFill()
                #endif
            }
        }
        .frame(width: height * 9 / 16, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height > 40 ? 6 : 4))
    }
}
