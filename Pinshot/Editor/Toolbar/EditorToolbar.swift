import SwiftUI

struct ToolbarActions {
    var undo: @MainActor () -> Void
    var redo: @MainActor () -> Void
    var copy: @MainActor () -> Void
    var save: @MainActor () -> Void
    /// 画像の文字を読み取ってコピーする（範囲を選ぶときは「…」から）
    var copyText: @MainActor () -> Void
    var copyLink: @MainActor () -> Void
    var done: @MainActor () -> Void
    var setOpacity: (Double) -> Void
    var setZoom: (Double) -> Void
    /// 撮った画像の履歴を開く
    var openHistory: @MainActor () -> Void
    /// 「…」のメニュー（右クリックと同じもの）を開く
    var more: @MainActor () -> Void
    /// 文字マーカーの線の位置を変える（この画像のすべての文字マーカーをそろえる）
    var setTextMarkLinePosition: @MainActor (TextMarkLinePosition) -> Void
    /// つまみのドラッグで動かす（最初の呼び出しでマウスと位置を覚え、そこからの差で動かす）。
    /// ツールバーが画像に付いているときは画像ごと、切り離しているときはツールバーだけを動かす
    var move: @MainActor () -> Void
    var endMove: @MainActor () -> Void
}

/// 編集モードのときに出るツールバー。2 つのバーに分けて出す。
/// 上は、編集に入る前と同じ操作バー（不透明度・拡大率・コピー・保存・文字・履歴・…）をそのまま出し、左端に動かすつまみ ✙、
/// 「編集」の位置に「完了」を置く（編集に入っても、同じ場所に同じ見た目のバーが残る）。
/// 下は道具のバー（ツール・色・スタイル・背景・元に戻す / やり直す・表示）。幅は道具の段で決まり、
/// その下の 2 行目（オプション）は入りきらなければまとまりごとに折り返す
struct EditorToolbar: View {
    @ObservedObject var state: EditorState
    /// 画像の不透明度・拡大率（操作バーと同じものを見る）
    @ObservedObject var appearance: PinAppearance
    /// 背景の初期設定（「次の画像にも使う」が押してあるか見るため）
    @ObservedObject var settings = AppSettings.shared
    let actions: ToolbarActions

    var body: some View {
        VStack(spacing: 6) {
            imageBar
            toolPanel
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: - 上のバー（編集に入る前と同じ操作バー）

    private var imageBar: some View {
        QuickActionBar(
            appearance: appearance,
            edit: { actions.done() },
            setOpacity: actions.setOpacity,
            setZoom: actions.setZoom,
            copy: { actions.copy() },
            save: { actions.save() },
            copyText: { actions.copyText() },
            copyLink: { actions.copyLink() },
            more: { actions.more() },
            history: { actions.openHistory() },
            isEditing: true,
            move: { actions.move() },
            endMove: { actions.endMove() },
            moveHelp: state.isDetached
                ? "ドラッグでツールバーを移動（切り離し中）"
                : "ドラッグで画像を移動（space か ⌘ を押しながら画像をドラッグしても動く）"
        )
    }

    // MARK: - 下のバー（道具と、そのオプション）

    private var toolPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            toolRow
                .background(
                    // 道具の段の幅を測って、2 行目の折り返しの幅にする
                    GeometryReader { proxy in
                        Color.clear.preference(key: ToolbarRowWidthKey.self, value: proxy.size.width)
                    }
                )
            if hasOptions {
                optionsTray
            }
        }
        .coordinateSpace(name: ToolbarMetrics.rowsSpace)
        .onPreferenceChange(ToolbarRowWidthKey.self) { width in
            if abs(state.toolbarRowWidth - width) > 0.5 {
                state.toolbarRowWidth = width
            }
        }
        .onPreferenceChange(OptionsAnchorKey.self) { x in
            if state.optionsAnchorX != x {
                state.optionsAnchorX = x
            }
        }
        .padding(ToolbarMetrics.toolbarPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
    }

    /// 道具の段（ツール・色とスタイルと背景・元に戻す / やり直す・表示）
    private var toolRow: some View {
        HStack(spacing: ToolbarMetrics.itemSpacing) {
            ToolbarSection {
                ForEach(ToolGroup.allCases) { group in
                    ToolGroupButton(state: state, group: group)
                        .optionsAnchor(isActive: !state.showsBackdropOptions && optionsGroup == group)
                }
            }

            ToolbarDivider()

            ToolbarSection {
                ColorMenuButton(state: state)
                PresetMenuButton(state: state)
                BackdropButton(state: state)
                    .optionsAnchor(isActive: state.showsBackdropOptions)
            }

            ToolbarDivider()

            ToolbarSection {
                ToolbarIconButton(symbol: "arrow.uturn.backward", hint: "元に戻す（⌘Z）", isEnabled: state.canUndo, action: actions.undo)
                ToolbarIconButton(symbol: "arrow.uturn.forward", hint: "やり直す（⌘⇧Z）", isEnabled: state.canRedo, action: actions.redo)
            }

            ToolbarDivider()

            // ツールバーの表示（画像から切り離す・乗せたら説明を出す）
            layoutMenu
        }
    }

    /// ツールバーの表示（画像から切り離す・乗せたときの説明を出す）
    private var layoutMenu: some View {
        ToolbarIconButton(symbol: "slider.horizontal.3", hint: "ツールバーの表示（切り離し・説明）") {
            PopupMenu.popUp([
                .item(title: "画像から切り離す（好きな場所に置ける）", isChecked: state.isDetached) { state.isDetached.toggle() },
                .separator,
                .item(title: "ボタンに乗せたら説明を出す", isChecked: state.showsHints) { state.showsHints.toggle() },
            ])
        }
    }

    // MARK: - 2 行目（ツールごとのオプション）

    private var hasOptions: Bool {
        if state.showsBackdropOptions { return true }
        switch state.optionsTool {
        case .rectangle, .ellipse, .arrow, .pen, .highlight, .textMark, .counter, .text: return true
        case .select, .spotlight, .mosaic, .blur, .crop: return false
        }
    }

    /// 2 行目のオプションを出しているツールのまとまり（吹き出しの先を向けるボタン）
    private var optionsGroup: ToolGroup { ToolGroup.group(of: state.optionsTool) }

    /// 2 行目は、1 行目で選んでいるボタンから出た吹き出しの形にする（そのボタンの細かい設定だと分かるように）。
    /// 先頭に、何の設定かの見出し（アイコン＋名前）を置く
    private var optionsTray: some View {
        let padding = ToolbarMetrics.trayPadding
        let width = state.toolbarRowWidth - padding.leading - padding.trailing
        return FlowLayout(spacing: 14, lineSpacing: 6) {
            optionsHeader
            optionSections
        }
        .frame(width: width > 0 ? width : nil, alignment: .leading)
        .padding(padding)
        .padding(.top, ToolbarMetrics.trayNotch.height)
        .background(tray.fill(ToolbarMetrics.trayFill))
        .overlay(tray.stroke(ToolbarMetrics.trayBorder, lineWidth: 1))
    }

    /// 2 行目の吹き出しの形（先は、オプションを出しているボタンに向ける）
    private var tray: CalloutShape {
        CalloutShape(notchX: state.optionsAnchorX, notch: ToolbarMetrics.trayNotch, corner: ToolbarMetrics.trayCorner)
    }

    /// 何の設定かの見出し（背景・入力中の文字・選んだ書き込み・いまのツール）
    private var optionsHeader: some View {
        let symbol: String
        let title: String
        if state.showsBackdropOptions {
            symbol = "photo.artframe"
            title = "背景の設定"
        } else {
            let tool = state.optionsTool
            symbol = tool.symbolName
            if state.isEditingText {
                title = "入力中の文字"
            } else if state.selectionTool != nil {
                title = "選んだ\(tool.label)"
            } else {
                title = "\(tool.label)の設定"
            }
        }
        // 見出しは押せるものではないので、ボタン（台・選んでいる色）の形にはしない。
        // 太字の文字と縦の区切り線で、その右に並ぶ設定の見出しだと分かるようにする
        return HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Rectangle()
                .fill(ToolbarMetrics.trayBorder)
                .frame(width: 1, height: 16)
                .padding(.leading, 7)
        }
        .foregroundStyle(.primary)
        .padding(.leading, 2)
        .frame(height: ToolbarMetrics.segmentHeight)
        .fixedSize()
    }

    @ViewBuilder
    private var optionSections: some View {
        if state.showsBackdropOptions {
            backdropSections
        } else {
            toolSections
        }
    }
}
