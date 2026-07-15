import SwiftUI

struct PencilCaseView: View {
    @EnvironmentObject private var store: PosteightStore
    let note: StickyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "archivebox")
                Text("필통")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Toggle(
                    "Notion 기록",
                    isOn: Binding(
                        get: { note.includeInNotionLog },
                        set: { store.updateNotionLog(note.id, include: $0) }
                    )
                )
                .toggleStyle(.switch)
                .font(.system(size: 11, weight: .medium, design: .rounded))
            }

            toolRow(title: "종이") {
                ColorSwatchRow(
                    options: DesignTokens.paperColors,
                    selectedHex: note.paperHex
                ) { hex in
                    store.updatePaperColor(note.id, hex: hex)
                }

                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: note.paperHex) },
                        set: { store.updatePaperColor(note.id, hex: $0.hexString) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 28)
                .help("직접 색 선택")
            }

            toolRow(title: "펜") {
                ColorSwatchRow(
                    options: DesignTokens.penColors,
                    selectedHex: note.penHex
                ) { hex in
                    store.updatePenColor(note.id, hex: hex)
                }

                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: note.penHex) },
                        set: { store.updatePenColor(note.id, hex: $0.hexString) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 28)
                .help("직접 색 선택")
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

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
                    ForEach(DesignTokens.stickers) { sticker in
                        Button {
                            store.updateSticker(note.id, symbol: sticker.symbol)
                        } label: {
                            Image(systemName: sticker.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 24)
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
        .padding(11)
        .background(.white.opacity(0.34), in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
    }

    private func toolRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.48))
                .frame(width: 30, alignment: .leading)

            content()
        }
    }
}

private struct ColorSwatchRow: View {
    let options: [ColorOption]
    let selectedHex: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options) { option in
                Button {
                    onSelect(option.hex)
                } label: {
                    Rectangle()
                        .fill(Color(hex: option.hex))
                        .frame(width: 18, height: 18)
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
