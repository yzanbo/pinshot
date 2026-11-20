import SwiftUI

// 編集ツールバーの 2 行目（ツールごとのオプション）。
// 背景のボタンを押したときは背景の設定、それ以外はいまのツール（選んでいる書き込み・入力中の文字）の設定を出す。
// ツールバーの組み立て（上のバー・道具の段・2 行目の吹き出し）は EditorToolbar.swift
extension EditorToolbar {
    /// 背景のオプション（背景のボタンを押したとき）。まず「なし / 付ける」を選び、付けたときだけ色・余白・角の丸み・影を出す
    @ViewBuilder
    var backdropSections: some View {
        let shown = state.backdropShown
        let decoration = state.backdropDecoration
        OptionSection(label: "背景") {
            SegmentedGroup {
                SegmentButton(text: "なし", hint: "背景を外す", isSelected: !shown) {
                    state.setBackdropShown(false)
                }
                SegmentButton(text: "付ける", hint: "背景を付ける（書き出しも同じ見た目）", isSelected: shown) {
                    state.setBackdropShown(true)
                }
            }
        }
        if shown {
            OptionSection(label: "色") {
                SegmentedGroup {
                    ForEach(ExportBackground.allCases) { background in
                        SegmentButton(
                            hint: "背景の色：\(background.label)",
                            isSelected: decoration.background == background
                        ) {
                            state.updateBackdrop { $0.background = background }
                        } label: {
                            Image(nsImage: background.swatchImage(diameter: 12))
                        }
                    }
                }
            }
            OptionSection(label: "余白") {
                SegmentedGroup {
                    ForEach(ExportPadding.allCases) { padding in
                        SegmentButton(text: padding.label, hint: "背景の余白：\(padding.label)", isSelected: decoration.padding == padding) {
                            state.updateBackdrop { $0.padding = padding }
                        }
                    }
                }
            }
            OptionSection(label: "角") {
                SegmentedGroup {
                    ForEach(ExportCorner.allCases) { corner in
                        SegmentButton(text: corner.label, hint: "画像の角の丸み：\(corner.label)", isSelected: decoration.corner == corner) {
                            state.updateBackdrop { $0.corner = corner }
                        }
                    }
                }
            }
            OptionSection(label: "影") {
                SegmentedGroup {
                    SegmentButton(text: "なし", hint: "画像の影を付けない", isSelected: !decoration.shadow) {
                        state.updateBackdrop { $0.shadow = false }
                    }
                    SegmentButton(text: "あり", hint: "画像に影を付ける", isSelected: decoration.shadow) {
                        state.updateBackdrop { $0.shadow = true }
                    }
                }
            }
        }
        // いまの背景（付けない・付ける・見た目）を、これから浮かせる画像の初期設定にする（設定の画面には背景の項目を置かない）
        let current = currentBackdrop
        let isDefault = settings.exportDecoration == current
        OptionSection(label: "初期設定") {
            SegmentButton(
                symbol: isDefault ? "checkmark" : "arrow.down.to.line",
                text: isDefault ? "次の画像にも使う（いまの初期設定）" : "次の画像にも使う",
                hint: "この背景（なし / 付ける・色・余白・角・影）を、これから浮かせる画像にも最初から使う",
                isSelected: isDefault
            ) {
                settings.exportDecoration = current
            }
        }
    }

    /// この画像のいまの背景（付けているかも含めて）
    private var currentBackdrop: ExportDecoration {
        var decoration = state.backdropDecoration
        decoration.isEnabled = state.backdropShown
        return decoration
    }

    /// いまのツール（入力中の文字・選んだ書き込み）のオプション
    @ViewBuilder
    var toolSections: some View {
        let tool = state.optionsTool
        switch tool {
        case .rectangle:
            lineWidthSection(for: tool)
            OptionSection(label: "角") {
                SegmentedGroup {
                    ForEach(CornerStyle.allCases) { corner in
                        SegmentButton(text: corner.label, hint: "四角の角の丸み：\(corner.label)", isSelected: state.rectangleStyle.corner == corner) {
                            state.rectangleStyle.corner = corner
                        }
                    }
                }
            }
            fillSection(selection: state.rectangleStyle.fill) { state.rectangleStyle.fill = $0 }
            opacitySection

        case .ellipse:
            lineWidthSection(for: tool)
            fillSection(selection: state.ellipseStyle.fill) { state.ellipseStyle.fill = $0 }
            opacitySection

        case .arrow:
            lineWidthSection(for: tool)
            OptionSection(label: "矢じり") {
                SegmentedGroup {
                    SegmentButton(symbol: "arrow.left", text: "始点", hint: "始点（描き始めの側）に矢じりを付ける・外す", isSelected: state.arrowStyle.startHead) {
                        state.arrowStyle.startHead.toggle()
                    }
                    SegmentButton(symbol: "arrow.right", text: "終点", hint: "終点（描き終わりの側）に矢じりを付ける・外す", isSelected: state.arrowStyle.endHead) {
                        state.arrowStyle.endHead.toggle()
                    }
                }
            }
            if state.arrowStyle.hasHeads {
                OptionSection(label: "形") {
                    SegmentedGroup {
                        ForEach(ArrowHeadShape.allCases) { shape in
                            SegmentButton(symbol: shape.symbolName, text: shape.label, hint: "矢じりの形：\(shape.label)", isSelected: state.arrowStyle.shape == shape) {
                                state.arrowStyle.shape = shape
                            }
                        }
                    }
                }
                OptionSection(label: "矢じりの大きさ") {
                    SegmentedGroup {
                        ForEach(ArrowHead.allCases) { head in
                            SegmentButton(text: head.label, hint: "矢じりの大きさ：\(head.label)", isSelected: state.arrowStyle.head == head) {
                                state.arrowStyle.head = head
                            }
                        }
                    }
                }
            }
            opacitySection

        case .pen, .highlight:
            lineWidthSection(for: tool)
            opacitySection

        case .textMark:
            OptionSection(label: "種類") {
                SegmentedGroup {
                    ForEach(TextMarkKind.allCases) { kind in
                        SegmentButton(symbol: kind.symbolName, text: kind.label, hint: "文字マーカーの種類：\(kind.label)", isSelected: state.textMarkStyle.kind == kind) {
                            state.textMarkStyle.kind = kind
                        }
                    }
                }
            }
            switch state.textMarkStyle.kind {
            case .highlight, .box:
                OptionSection(label: "余白") {
                    SegmentedGroup {
                        ForEach(TextMarkPadding.allCases) { padding in
                            SegmentButton(text: padding.label, hint: "文字からの余白：\(padding.label)（選んでいる文字マーカーにも反映）", isSelected: state.textMarkStyle.padding == padding) {
                                state.textMarkStyle.padding = padding
                            }
                        }
                    }
                }
            case .underline, .strikethrough:
                OptionSection(label: "線の位置") {
                    SegmentedGroup {
                        ForEach(TextMarkLinePosition.allCases) { position in
                            SegmentButton(text: position.label, hint: "線の位置：\(position.label)（この画像のすべての文字マーカーをそろえる）", isSelected: state.textMarkStyle.linePosition == position) {
                                actions.setTextMarkLinePosition(position)
                            }
                        }
                    }
                }
            }
            if state.textMarkStyle.kind.usesLineWidth {
                lineWidthSection(for: tool)
            }
            opacitySection

        case .counter:
            OptionSection(label: "大きさ") {
                SegmentedGroup {
                    ForEach(CounterSize.allCases) { size in
                        SegmentButton(text: size.label, hint: "番号の大きさ：\(size.label)", isSelected: state.counterSize == size) {
                            state.counterSize = size
                        }
                    }
                }
            }
            OptionSection(label: "デザイン") {
                SegmentedGroup {
                    ForEach(CounterDesign.allCases) { design in
                        SegmentButton(symbol: design.symbolName, text: design.label, hint: "番号のデザイン：\(design.label)", isSelected: state.counterStyle.design == design) {
                            state.counterStyle.design = design
                        }
                    }
                }
            }
            OptionSection(label: "表記") {
                SegmentedGroup {
                    ForEach(CounterFormat.allCases) { format in
                        SegmentButton(text: format.label, hint: "番号の表記：\(format.label)", isSelected: state.counterStyle.format == format) {
                            state.counterStyle.format = format
                        }
                    }
                }
                Text("次は \(state.counterStyle.format.text(for: state.nextCounterNumber))")
                    .font(ToolbarMetrics.labelFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            OptionSection(label: "フォント") {
                fontFamilyControl(current: state.counterStyle.fontFamily, hint: "番号のフォント（Mac に入っているフォントから選ぶ）") { family in
                    state.counterStyle.fontFamily = family
                }
            }
            opacitySection

        case .text:
            // 次に入力したらどう見えるかの見本（いまの設定で描く）
            OptionSection(label: "見本") {
                TextStylePreview(style: state.textStyle, color: state.drawColor, fontSize: state.fontSize)
            }
            OptionSection(label: "大きさ") {
                fontSizeControl
            }
            OptionSection(label: "フォント") {
                fontFamilyControl(current: state.textStyle.fontFamily, hint: "文字のフォント（Mac に入っているフォントから選ぶ）") { family in
                    state.textStyle.fontFamily = family
                }
            }
            OptionSection(label: "縁取り") {
                SegmentedGroup {
                    ForEach(TextDecoration.allCases) { decoration in
                        SegmentButton(text: decoration.label, hint: "文字の縁取り：\(decoration.label)", isSelected: state.textStyle.decoration == decoration) {
                            state.textStyle.decoration = decoration
                        }
                    }
                }
            }
            if state.textStyle.decoration == .whiteOutline || state.textStyle.decoration == .blackOutline {
                OptionSection(label: "縁取りの太さ") {
                    SegmentedGroup {
                        ForEach(OutlineWeight.allCases) { weight in
                            SegmentButton(text: weight.label, hint: "文字の縁取りの太さ：\(weight.label)", isSelected: state.textStyle.outline == weight) {
                                state.textStyle.outline = weight
                            }
                        }
                    }
                }
            }
            OptionSection(label: "マーカー") {
                SegmentedGroup {
                    SegmentButton(text: "なし", hint: "文字のマーカー：なし", isSelected: state.textStyle.marker == nil) {
                        state.textStyle.marker = nil
                    }
                    ForEach(TextMarkKind.allCases) { kind in
                        SegmentButton(symbol: kind.symbolName, text: kind.label, hint: "文字のマーカー：\(kind.label)（文字マーカーと同じ描き方。縁取りと組み合わせられる）", isSelected: state.textStyle.marker == kind) {
                            state.textStyle.marker = kind
                        }
                    }
                }
            }
            if state.textStyle.marker != nil {
                OptionSection(label: "マーカーの色") {
                    SegmentedGroup {
                        ForEach(RGBAColor.palette, id: \.self) { color in
                            SegmentButton(hint: "マーカーの色", isSelected: state.textStyle.resolvedMarkerColor == color) {
                                state.textStyle.markerColor = color
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25)))
                            }
                        }
                    }
                }
            }
            opacitySection

        default:
            EmptyView()
        }
    }

    /// 線の太さ（ツールごとに覚える）
    private func lineWidthSection(for tool: Tool) -> some View {
        OptionSection(label: "線の太さ") {
            SegmentedGroup {
                ForEach(LineWidths.presets(for: tool), id: \.self) { width in
                    SegmentButton(
                        hint: "太さ：\(Int(width)) pt（[ ] キーでも変えられる。選んでいる書き込みにも反映）",
                        isSelected: abs(state.lineWidth(for: tool) - width) < 0.01
                    ) {
                        state.setLineWidth(width, for: tool)
                    } label: {
                        HStack(spacing: 3) {
                            Capsule()
                                .frame(width: 10, height: max(1, min(width * (tool == .highlight ? 0.2 : 0.6), 7)))
                            Text("\(Int(width))")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    /// 塗り（四角・楕円）
    private func fillSection(selection: FillStyle, set: @escaping (FillStyle) -> Void) -> some View {
        OptionSection(label: "塗り") {
            SegmentedGroup {
                ForEach(FillStyle.allCases) { fill in
                    SegmentButton(text: fill.label, hint: "塗り：\(fill.label)", isSelected: selection == fill) {
                        set(fill)
                    }
                }
            }
        }
    }

    /// 書き込みの不透明度（選んでいる書き込みにも反映）
    private var opacitySection: some View {
        OptionSection(label: "不透明度") {
            HStack(spacing: 6) {
                Slider(value: $state.opacity, in: 0.1...1)
                    .controlSize(.mini)
                    .frame(width: 80)
                Text(state.opacity.percentText)
                    .font(ToolbarMetrics.labelFont.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: ToolbarMetrics.segmentHeight + 4)
            .background(RoundedRectangle(cornerRadius: ToolbarMetrics.groupCorner).fill(ToolbarMetrics.groupFill))
            .hoverHint("書き込みの不透明度（選んでいる書き込みにも反映。画像そのものの不透明度は、画像の下のバーで変える）")
            .hoverRole()
        }
    }

    /// フォント（いまのフォントの名前 ▾。押すと、Mac に入っているフォントの一覧を開く）
    private func fontFamilyControl(current: String?, hint: String, onSelect: @escaping @MainActor (String?) -> Void) -> some View {
        SegmentedGroup {
            SegmentButton(hint: hint, isSelected: false) {
                FontMenu.popUp(current: current, onSelect: onSelect)
            } label: {
                HStack(spacing: 4) {
                    Text(FontMenu.displayName(of: current))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120)
                    Image(systemName: "chevron.down")
                        .font(ToolbarMetrics.chevronFont)
                }
            }
        }
    }

    /// 文字の大きさ（− / 数字（押すと手入力）/ ▾ 一覧 / ＋）
    private var fontSizeControl: some View {
        SegmentedGroup {
            SegmentButton(hint: "文字を小さく（⌘- か [）", isSelected: false) {
                state.stepFontSize(up: false)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }

            SegmentButton(hint: "文字の大きさ（押すと数字を入力。入力中は、カーソルの位置の大きさを表示）", isSelected: false) {
                FontSizeInputController.show(current: state.fontSize) { size in
                    state.fontSize = size
                }
            } label: {
                Text(FontSizes.format(state.fontSize))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .frame(minWidth: 26)
            }

            SegmentButton(hint: "文字の大きさを一覧から選ぶ", isSelected: false) {
                PopupMenu.popUp(FontSizes.presets.map { size in
                    .item(title: "\(Int(size)) pt", isChecked: abs(state.fontSize - size) < 0.01) { state.fontSize = size }
                })
            } label: {
                Image(systemName: "chevron.down")
                    .font(ToolbarMetrics.chevronFont)
            }

            SegmentButton(hint: "文字を大きく（⌘+ か ]）", isSelected: false) {
                state.stepFontSize(up: true)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
        }
    }
}
