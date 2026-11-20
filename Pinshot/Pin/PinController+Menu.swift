import AppKit

extension PinController {
    // MARK: - 右クリックメニュー

    /// 右クリック（と操作バーの「…」）のメニュー。見出しで「編集・コピーと保存・履歴・文字の読み取り・見た目・置き方と表示」に分ける
    func makeContextMenu() -> NSMenu {
        let opacityPercent = Int((panel.alphaValue * 100).rounded())
        let symbol = MenuEntry.symbol
        return PopupMenu.makeMenu([
            .item(title: state.isEditing ? "編集を終える" : "編集する", image: symbol(state.isEditing ? "checkmark.circle" : "pencil"), key: "e") { [weak self] in
                self?.toggleEditing()
            },

            .separator,
            .header("コピー・保存"),
            .item(title: "コピー", image: symbol("doc.on.doc"), key: "c") { [weak self] in self?.copyToPasteboard() },
            .item(title: "コピーして閉じる", image: symbol("doc.on.doc.fill"), key: "c", modifiers: [.command, .shift]) { [weak self] in
                self?.copyAndClose()
            },
            .item(title: "保存…", image: symbol("square.and.arrow.down"), key: "s") { [weak self] in self?.save() },
            .item(title: "アップロードしてリンクをコピー", image: symbol("link"), key: "u") { [weak self] in self?.uploadAndCopyLink() },

            // 履歴だけの枠（見出しは付けない）。画像・文字・共有は、ウィンドウの上の帯で切り替える
            .separator,
            .item(title: "履歴…", image: symbol("clock.arrow.circlepath")) { [weak self] in self?.openHistory() },

            .separator,
            .header("文字の読み取り"),
            .item(title: "文字をコピー", image: symbol("text.viewfinder"), key: "t", modifiers: [.command, .shift]) { [weak self] in
                self?.copyRecognizedText()
            },
            .item(title: "範囲を選んで文字をコピー…", image: symbol("text.magnifyingglass")) { [weak self] in
                self?.canvas.beginPickingTextRegion()
            },

            .separator,
            .header("見た目"),
            .submenu(title: "不透明度（\(opacityPercent)%）", image: symbol("circle.lefthalf.filled"), entries: [100, 80, 60, 40, 20].map { percent in
                .item(title: "\(percent)%", isChecked: opacityPercent == percent) { [weak self] in
                    self?.setOpacity(CGFloat(percent) / 100)
                }
            }),
            .submenu(title: "拡大率（\(zoom.percentText)）", image: symbol("magnifyingglass"), entries: zoomEntries),
            .item(title: "背景を付ける（書き出しも同じ見た目）", image: symbol("photo.artframe"), isChecked: showsBackdrop) { [weak self] in
                guard let self else { return }
                self.setBackdropShown(!self.showsBackdrop)
            },

            .separator,
            .header("置き方・表示"),
            .item(title: "最前面に表示", image: symbol("square.3.layers.3d.top.filled"), isChecked: isOnTop) { [weak self] in
                guard let self else { return }
                self.setOnTop(!self.isOnTop)
            },
            .item(title: "クリックを透過する（下のアプリを操作できる）", image: symbol("cursorarrow.rays")) { [weak self] in
                self?.setClickThrough(true)
            },
            // 操作バーを出さないときは、ダブルクリックで編集モードに入るまで、画像の下に何も出さない（すべての画像に効く）
            .item(title: "画像の下に操作バーを出す", image: symbol("rectangle.bottomthird.inset.filled"), isChecked: AppSettings.shared.showsQuickActions) {
                AppSettings.shared.showsQuickActions.toggle()
            },


            .separator,
            .item(title: "閉じる", image: symbol("xmark"), key: "w") { [weak self] in self?.close() },
        ])
    }

    /// 拡大率の一覧（ツールバー・操作バーの拡大率と同じ選択肢。いちばん上は実際のサイズ）
    private var zoomEntries: [MenuEntry] {
        let current = Double(zoom)
        return [.item(title: "実際のサイズ（100%）", key: "0") { [weak self] in self?.resetZoom() }, .separator]
            + ViewControls.zoomPresets.map { value in
                .item(title: value.percentText, isChecked: abs(current - value) < 0.005) { [weak self] in
                    self?.setZoom(CGFloat(value))
                }
            }
    }
}
