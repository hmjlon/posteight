import SwiftUI

struct PencilCaseView: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                Text("필통")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer(minLength: 4)
                Toggle(
                    "Notion 기록",
                    isOn: Binding(
                        get: { note.includeInNotionLog },
                        set: { store.updateNotionLog(note.id, include: $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                .font(.system(size: 10, weight: .medium, design: .rounded))
            }

            toolRow(title: "종이") {
                ColorSwatchRow(
                    options: DesignTokens.paperColors,
                    selectedHex: note.paperHex
                ) { hex in
                    store.updatePaperColor(note.id, hex: hex)
                }
            }

            toolRow(title: "펜") {
                ColorSwatchRow(
                    options: DesignTokens.penColors,
                    selectedHex: note.penHex
                ) { hex in
                    store.updatePenColor(note.id, hex: hex)
                }
            }

            // The colour wells are wide enough to squeeze the swatches off a narrow card, so
            // they share a row of their own.
            toolRow(title: "직접") {
                customColorWell(systemImage: "doc", help: "종이 색 직접 선택") {
                    Binding(
                        get: { Color(hex: note.paperHex) },
                        set: { store.updatePaperColor(note.id, hex: $0.hexString) }
                    )
                }

                customColorWell(systemImage: "pencil.tip", help: "펜 색 직접 선택") {
                    Binding(
                        get: { Color(hex: note.penHex) },
                        set: { store.updatePenColor(note.id, hex: $0.hexString) }
                    )
                }

                Spacer(minLength: 0)
            }

            Picker(
                "펜촉",
                selection: Binding(
                    get: { note.penStyle },
                    set: { store.updatePenStyle(note.id, style: $0) }
                )
            ) {
                ForEach(PenStyle.allCases) { style in
                    Label(style.title, systemImage: style.systemImage)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text("스티커")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.48))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 34), spacing: 5)], spacing: 5) {
                    ForEach(DesignTokens.stickers) { sticker in
                        Button {
                            store.updateSticker(note.id, symbol: sticker.symbol)
                        } label: {
                            Image(systemName: sticker.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                                .background(
                                    sticker.symbol == note.stickerSymbol
                                        ? Color(hex: note.penHex).opacity(0.16)
                                        : Color.white.opacity(0.34),
                                    in: Rectangle()
                                )
                                .overlay {
                                    Rectangle()
                                        .stroke(
                                            sticker.symbol == note.stickerSymbol
                                                ? Color(hex: note.penHex).opacity(0.58)
                                                : .black.opacity(0.06),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(hex: note.penHex).opacity(0.86))
                        .help(sticker.title)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.34), in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
    }

    private func customColorWell(
        systemImage: String,
        help: String,
        selection: () -> Binding<Color>
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.black.opacity(0.42))

            ColorPicker("", selection: selection(), supportsOpacity: false)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
        }
        .help(help)
    }

    private func toolRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.48))
                .frame(width: 24, alignment: .leading)

            content()
        }
    }
}

private struct ColorSwatchRow: View {
    let options: [ColorOption]
    let selectedHex: String
    let onSelect: (String) -> Void

    // Swatches reflow with the card: they wrap on a narrow note and spread out on a wide one.
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 16, maximum: 28), spacing: 4)], spacing: 4) {
            ForEach(options) { option in
                Button {
                    onSelect(option.hex)
                } label: {
                    Rectangle()
                        .fill(Color(hex: option.hex))
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .overlay {
                            Rectangle()
                                .stroke(
                                    option.hex == selectedHex ? .black.opacity(0.54) : .black.opacity(0.12),
                                    lineWidth: option.hex == selectedHex ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
        }
    }
}
