import SwiftUI

struct ToolbarActions {
    var undo: @MainActor () -> Void
    var redo: @MainActor () -> Void
    var copy: @MainActor () -> Void
    var save: @MainActor () -> Void
    var done: @MainActor () -> Void
    /// 画像を閉じる（編集中でもそのまま閉じる。メニューの「閉じた画像を戻す」で戻せる）
    var close: @MainActor () -> Void
    /// つまみのドラッグで動かす（最初の呼び出しでマウスと位置を覚え、そこからの差で動かす）。
    /// ツールバーが画像に付いているときは画像ごと、切り離しているときはツールバーだけを動かす
    var move: @MainActor () -> Void
    var endMove: @MainActor () -> Void
}

/// 編集モードのときに出るツールバー。
/// 幅は 1 行目（ツール・色・操作）で決まり、2 行目（オプション）は入りきらなければまとまりごとに折り返す
struct EditorToolbar: View {
    @ObservedObject var state: EditorState
    let actions: ToolbarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mainContent
                .background(
                    // 1 行目の幅を測って、2 行目の折り返しの幅にする
                    GeometryReader { proxy in
                        Color.clear.preference(key: ToolbarRowWidthKey.self, value: proxy.size.width)
                    }
                )
            if hasOptions {
                optionsContent
                    .padding(.leading, ToolbarMetrics.optionsIndent)
            }
        }
        .onPreferenceChange(ToolbarRowWidthKey.self) { width in
            if abs(state.toolbarRowWidth - width) > 0.5 {
                state.toolbarRowWidth = width
            }
        }
        .padding(ToolbarMetrics.toolbarPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - 1 行目

    private var mainContent: some View {
        HStack(spacing: ToolbarMetrics.itemSpacing) {
            moveHandle

            ToolbarDivider()

            ToolbarSection {
                ForEach(ToolGroup.allCases) { group in
                    ToolGroupButton(state: state, group: group)
                }
            }

            ToolbarDivider()

            ToolbarSection {
                ColorMenuButton(state: state)
                PresetMenuButton(state: state)
                BackdropMenuButton(state: state)
            }

            ToolbarDivider()

            ToolbarSection {
                ToolbarIconButton(state: state, symbol: "arrow.uturn.backward", hint: "元に戻す（⌘Z）", isEnabled: state.canUndo, action: actions.undo)
                ToolbarIconButton(state: state, symbol: "arrow.uturn.forward", hint: "やり直す（⌘⇧Z）", isEnabled: state.canRedo, action: actions.redo)
                ToolbarIconButton(state: state, symbol: "doc.on.doc", hint: "コピー（⌘C）：書き込みごとクリップボードへ", action: actions.copy)
                ToolbarIconButton(state: state, symbol: "square.and.arrow.down", hint: "保存（⌘S）：PNG で保存", action: actions.save)
            }

            ToolbarDivider()

            layoutMenu

            Button {
                actions.done()
            } label: {
                Label("完了", systemImage: "checkmark")
                    .font(ToolbarMetrics.buttonFont)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .hint("編集を終える（esc・⌘E）", state: state)

            // 右端に、画像ごと閉じるボタン
            ToolbarIconButton(state: state, symbol: "xmark", hint: "画像を閉じる（⌘W）：書き込みごと閉じる。メニューの「閉じた画像を戻す」で戻せる", action: actions.close)
        }
    }

    /// ドラッグすると画像ごと（切り離しているときはツールバーだけ）動かせるつまみ
    private var moveHandle: some View {
        Image(systemName: state.isDetached ? "hand.draw" : "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: ToolbarMetrics.handleWidth, height: ToolbarMetrics.cell.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in actions.move() }
                    .onEnded { _ in actions.endMove() }
            )
            .hint(
                state.isDetached
                    ? "ドラッグでツールバーを移動（切り離し中）"
                    : "ドラッグで画像を移動（space か ⌘ を押しながら画像をドラッグしても動く）",
                state: state,
                cursor: .openHand
            )
    }

    /// ツールバーの表示（短く・縦向き・切り離し・説明）
    private var layoutMenu: some View {
        ToolbarIconButton(state: state, symbol: "slider.horizontal.3", hint: "ツールバーの表示（切り離し・説明）") {
            PopupMenu.popUp([
                .item(title: "画像から切り離す（好きな場所に置ける）", isChecked: state.isDetached) { state.isDetached.toggle() },
                .separator,
                .item(title: "ボタンに乗せたら説明を出す", isChecked: state.showsHints) { state.showsHints.toggle() },
            ])
        }
    }

    // MARK: - 2 行目（ツールごとのオプション）

    private var hasOptions: Bool {
        switch state.optionsTool {
        case .rectangle, .ellipse, .arrow, .pen, .highlight, .counter, .text: true
        default: false
        }
    }

    private var optionsContent: some View {
        let width = state.toolbarRowWidth - ToolbarMetrics.optionsIndent
        return FlowLayout(spacing: 14, lineSpacing: 6) {
            optionSections
        }
        .frame(width: width > 0 ? width : nil, alignment: .leading)
    }

    @ViewBuilder
    private var optionSections: some View {
        let tool = state.optionsTool
        switch tool {
        case .rectangle:
            lineWidthSection(for: tool)
            OptionSection(label: "角") {
                SegmentedGroup {
                    ForEach(CornerStyle.allCases) { corner in
                        SegmentButton(state: state, text: corner.label, hint: "四角の角の丸み：\(corner.label)", isSelected: state.rectangleStyle.corner == corner) {
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
                    SegmentButton(state: state, symbol: "arrow.left", text: "始点", hint: "始点（描き始めの側）に矢じりを付ける・外す", isSelected: state.arrowStyle.startHead) {
                        state.arrowStyle.startHead.toggle()
                    }
                    SegmentButton(state: state, symbol: "arrow.right", text: "終点", hint: "終点（描き終わりの側）に矢じりを付ける・外す", isSelected: state.arrowStyle.endHead) {
                        state.arrowStyle.endHead.toggle()
                    }
                }
            }
            if state.arrowStyle.hasHeads {
                OptionSection(label: "形") {
                    SegmentedGroup {
                        ForEach(ArrowHeadShape.allCases) { shape in
                            SegmentButton(state: state, symbol: shape.symbolName, text: shape.label, hint: "矢じりの形：\(shape.label)", isSelected: state.arrowStyle.shape == shape) {
                                state.arrowStyle.shape = shape
                            }
                        }
                    }
                }
                OptionSection(label: "矢じりの大きさ") {
                    SegmentedGroup {
                        ForEach(ArrowHead.allCases) { head in
                            SegmentButton(state: state, text: head.label, hint: "矢じりの大きさ：\(head.label)", isSelected: state.arrowStyle.head == head) {
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

        case .counter:
            OptionSection(label: "大きさ") {
                SegmentedGroup {
                    ForEach(CounterSize.allCases) { size in
                        SegmentButton(state: state, text: size.label, hint: "番号の大きさ：\(size.label)", isSelected: state.counterSize == size) {
                            state.counterSize = size
                        }
                    }
                }
            }
            OptionSection(label: "デザイン") {
                SegmentedGroup {
                    ForEach(CounterDesign.allCases) { design in
                        SegmentButton(state: state, symbol: design.symbolName, text: design.label, hint: "番号のデザイン：\(design.label)", isSelected: state.counterStyle.design == design) {
                            state.counterStyle.design = design
                        }
                    }
                }
            }
            OptionSection(label: "表記") {
                SegmentedGroup {
                    ForEach(CounterFormat.allCases) { format in
                        SegmentButton(state: state, text: format.label, hint: "番号の表記：\(format.label)", isSelected: state.counterStyle.format == format) {
                            state.counterStyle.format = format
                        }
                    }
                }
                Text("次は \(state.counterStyle.format.text(for: state.nextCounterNumber))")
                    .font(ToolbarMetrics.labelFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            opacitySection

        case .text:
            OptionSection(label: "大きさ") {
                fontSizeControl
            }
            OptionSection(label: "縁取り") {
                SegmentedGroup {
                    ForEach(TextDecoration.allCases) { decoration in
                        SegmentButton(state: state, text: decoration.label, hint: "文字の縁取り：\(decoration.label)", isSelected: state.textStyle.decoration == decoration) {
                            state.textStyle.decoration = decoration
                        }
                    }
                }
            }
            if state.textStyle.decoration == .whiteOutline || state.textStyle.decoration == .blackOutline {
                OptionSection(label: "縁取りの太さ") {
                    SegmentedGroup {
                        ForEach(OutlineWeight.allCases) { weight in
                            SegmentButton(state: state, text: weight.label, hint: "文字の縁取りの太さ：\(weight.label)", isSelected: state.textStyle.outline == weight) {
                                state.textStyle.outline = weight
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
                        state: state,
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
                    SegmentButton(state: state, text: fill.label, hint: "塗り：\(fill.label)", isSelected: selection == fill) {
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
                Text("\(Int((state.opacity * 100).rounded()))%")
                    .font(ToolbarMetrics.labelFont.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: ToolbarMetrics.segmentHeight + 4)
            .background(RoundedRectangle(cornerRadius: ToolbarMetrics.groupCorner).fill(ToolbarMetrics.groupFill))
            .hint("書き込みの不透明度（選んでいる書き込みにも反映。画像そのものの不透明度は、画像の下のバーで変える）", state: state, cursor: .arrow)
        }
    }

    /// 文字の大きさ（− / 数字（押すと手入力）/ ▾ 一覧 / ＋）
    private var fontSizeControl: some View {
        SegmentedGroup {
            SegmentButton(state: state, hint: "文字を小さく（⌘- か [）", isSelected: false) {
                state.stepFontSize(up: false)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }

            SegmentButton(state: state, hint: "文字の大きさ（押すと数字を入力。入力中は、カーソルの位置の大きさを表示）", isSelected: false) {
                FontSizeInputController.show(current: state.fontSize) { size in
                    state.fontSize = size
                }
            } label: {
                Text(FontSizes.format(state.fontSize))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .frame(minWidth: 26)
            }

            SegmentButton(state: state, hint: "文字の大きさを一覧から選ぶ", isSelected: false) {
                PopupMenu.popUp(FontSizes.presets.map { size in
                    .item(title: "\(Int(size)) pt", isChecked: abs(state.fontSize - size) < 0.01) { state.fontSize = size }
                })
            } label: {
                Image(systemName: "chevron.down")
                    .font(ToolbarMetrics.chevronFont)
            }

            SegmentButton(state: state, hint: "文字を大きく（⌘+ か ]）", isSelected: false) {
                state.stepFontSize(up: true)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
        }
    }
}
