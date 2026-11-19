import AppKit

extension PinController {
    // MARK: - 右クリックメニュー

    func makeContextMenu() -> NSMenu {
        let opacityPercent = Int((panel.alphaValue * 100).rounded())
        return PopupMenu.makeMenu([
            .item(title: state.isEditing ? "編集を終える" : "編集する", key: "e") { [weak self] in self?.toggleEditing() },
            .separator,
            .item(title: "コピー", key: "c") { [weak self] in self?.copyToPasteboard() },
            .item(title: "コピーして閉じる", key: "c", modifiers: [.command, .shift]) { [weak self] in self?.copyAndClose() },
            .item(title: "背景を付ける（書き出しも同じ見た目）", isChecked: showsBackdrop) { [weak self] in
                guard let self else { return }
                self.setBackdropShown(!self.showsBackdrop)
            },
            .item(title: "保存…", key: "s") { [weak self] in self?.save() },
            .separator,
            .submenu(title: "不透明度", entries: [100, 80, 60, 40, 20].map { percent in
                .item(title: "\(percent)%", isChecked: opacityPercent == percent) { [weak self] in
                    self?.setOpacity(CGFloat(percent) / 100)
                }
            }),
            .item(title: "実際のサイズ", key: "0") { [weak self] in self?.resetZoom() },
            .item(title: "最前面に表示", isChecked: isOnTop) { [weak self] in
                guard let self else { return }
                self.setOnTop(!self.isOnTop)
            },
            .item(title: "クリックを透過する（下のアプリを操作できる）") { [weak self] in self?.setClickThrough(true) },
            .separator,
            .item(title: "閉じる", key: "w") { [weak self] in self?.close() },
        ])
    }
}
