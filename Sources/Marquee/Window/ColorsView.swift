import AppKit
import SwiftUI

@MainActor
struct ColorsView: View {
    @ObservedObject var picker = ColorPickerController.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Colors").font(.system(size: 20, weight: .bold))
                Spacer()
                Picker("Copy as", selection: $picker.format) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .help("Format used when you pick or click a color")
                Button {
                    AppModel.shared.perform(.pickColor)
                } label: {
                    Label("Pick Color", systemImage: "eyedropper")
                }
                .glassButtonStyle(prominent: true)
                .keyboardShortcut("p", modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if let latest = picker.history.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LatestColorCard(color: latest)
                        if picker.history.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Recent")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Clear…") { confirmClear = true }.buttonStyle(.link)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                                    ForEach(picker.history.dropFirst()) { color in
                                        Swatch(color: color)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Pick any color on your screen").font(.system(size: 15, weight: .semibold))
                    Text("A magnifier follows the pointer. Click to pick; the color is copied as \(picker.format.rawValue).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button("Pick Color") { AppModel.shared.perform(.pickColor) }
                        .glassButtonStyle(prominent: true)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Clear all picked colors?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { picker.clear() }
        }
    }
}

private struct LatestColorCard: View {
    let color: PickedColor

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 140, height: 140)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                .accessibilityLabel("Color \(color.hex)")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ColorFormat.allCases) { format in
                    HStack(spacing: 10) {
                        Text(format.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        Text(color.string(in: format))
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            ColorPickerController.shared.copy(color, as: format)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy \(format.rawValue)")
                        .accessibilityLabel("Copy \(format.rawValue)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: 460)
        }
    }
}

private struct Swatch: View {
    let color: PickedColor
    @State private var hovering = false

    var body: some View {
        Button {
            ColorPickerController.shared.copy(color)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: color.nsColor))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(hovering ? 0.3 : 0.1), lineWidth: hovering ? 2 : 1))
                Text(color.hex)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Click to copy")
        .contextMenu {
            ForEach(ColorFormat.allCases) { format in
                Button("Copy \(format.rawValue)") { ColorPickerController.shared.copy(color, as: format) }
            }
            Divider()
            Button("Delete", role: .destructive) { ColorPickerController.shared.remove(color) }
        }
        .accessibilityLabel("Color \(color.hex)")
        .accessibilityHint("Copies the color")
    }
}
