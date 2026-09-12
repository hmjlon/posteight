import SwiftUI

struct PencilCaseView: View {
    @EnvironmentObject private var store: PosteightStore
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var fonts = NoteFontLibrary.shared
    let note: StickyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                Text(L("필통"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer(minLength: 4)
            }

            toolRow(title: L("폰트")) {
                NoteFontPicker(entries: fonts.entries, language: settings.language, selection: Binding(
                    get: { fonts.resolvedID(for: note.fontID, defaultID: settings.defaultFontID) },
                    set: { store.updateFont(note.id, fontID: $0) }
                ), fontSize: 13)
                .fixedSize()

                FontImportButton()
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .controlSize(.regular)
                    .fixedSize()

                fontSizeButtons
                Spacer(minLength: 0)
            }

            toolRow(title: L("종이")) {
                ColorSwatchRow(
                    options: DesignTokens.paperColors,
                    selectedHex: note.paperHex
                ) { hex in
                    store.updatePaperColor(note.id, hex: hex)
                }
            }

            toolRow(title: L("펜")) {
                ColorSwatchRow(
                    options: DesignTokens.penColors,
                    selectedHex: note.penHex
                ) { hex in
                    store.updatePenColor(note.id, hex: hex)
                }
            }

            // The colour wells are wide enough to squeeze the swatches off a narrow card, so
            // they share a row of their own.
            toolRow(title: L("색상")) {
                customColorWell(systemImage: "doc", help: L("종이 색 직접 선택")) {
                    Binding(
                        get: { Color(hex: note.paperHex) },
                        set: { store.updatePaperColor(note.id, hex: $0.hexString) }
                    )
                }

                customColorWell(systemImage: "pencil.tip", help: L("펜 색 직접 선택")) {
                    Binding(
                        get: { Color(hex: note.penHex) },
                        set: { store.updatePenColor(note.id, hex: $0.hexString) }
                    )
                }

                Spacer(minLength: 0)
            }

            toolRow(title: L("펜촉")) {
                Picker(
                    L("펜촉"),
                    selection: Binding(
                        get: { note.penStyle },
                        set: { store.updatePenStyle(note.id, style: $0) }
                    )
                ) {
                    ForEach(PenStyle.allCases) { style in
                        Label(style.title(in: settings.language), systemImage: style.systemImage)
                            .tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            }

            if let selectedTab = note.selectedTab {
                VStack(alignment: .leading, spacing: 6) {
                    toolLabel(L("탭 아이콘"))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 34), spacing: 5)], spacing: 5) {
                        ForEach(DesignTokens.stickers) { sticker in
                            Button {
                                store.updateTabSticker(
                                    noteID: note.id,
                                    tabID: selectedTab.id,
                                    symbol: sticker.symbol
                                )
                            } label: {
                                Image(systemName: sticker.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 22)
                                    .overlay {
                                        Rectangle()
                                            .stroke(
                                                sticker.symbol == selectedTab.stickerSymbol
                                                    ? Color(hex: note.penHex).opacity(0.58)
                                                    : .black.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(hex: note.penHex).opacity(0.86))
                            .help(sticker.title(in: settings.language))
                        }
                    }
                }
            }

        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            Rectangle()
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var fontSizeButtons: some View {
        HStack(spacing: 0) {
            ForEach(NoteFontSize.allCases) { size in
                let selected = (note.fontSize ?? settings.defaultFontSize) == size
                let diameter: CGFloat = size == .small ? 6 : (size == .medium ? 9 : 12)
                Button {
                    store.updateFontSize(note.id, size: size)
                } label: {
                    Circle()
                        .fill(selected ? Color(hex: note.penHex) : .black.opacity(0.25))
                        .frame(width: diameter, height: diameter)
                        .frame(width: 24, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color(hex: note.penHex).opacity(0.1) : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Lf("글자 크기: %@", size.title(in: settings.language)))
                .accessibilityLabel(Lf("글자 크기: %@", size.title(in: settings.language)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .contextMenu {
                    Button(L("기본값 사용")) {
                        store.updateFontSize(note.id, size: nil)
                    }
                }
            }
        }
        .fixedSize()
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

    private func toolLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.48))
            .fixedSize(horizontal: true, vertical: false)
    }

    private func toolRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            toolLabel(title)
                .frame(width: settings.language.resolved == .korean ? 24 : 32, alignment: .leading)

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
