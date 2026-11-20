import Carbon.HIToolbox
import XCTest

/// 端のドラッグで大きさを変える計算
final class ResizeEdgesTests: XCTestCase {
    private let bounds = NSRect(x: 0, y: 0, width: 200, height: 100)

    func testEdgesAtPoint() {
        // flipped（左上が原点）のビューでは、y の小さい方が上
        XCTAssertEqual(ResizeEdges.at(NSPoint(x: 2, y: 2), in: bounds, zone: 8, flipped: true), [.left, .top])
        XCTAssertEqual(ResizeEdges.at(NSPoint(x: 2, y: 2), in: bounds, zone: 8, flipped: false), [.left, .bottom])
        XCTAssertEqual(ResizeEdges.at(NSPoint(x: 199, y: 50), in: bounds, zone: 8, flipped: true), [.right])
        XCTAssertEqual(ResizeEdges.at(NSPoint(x: 100, y: 50), in: bounds, zone: 8, flipped: true), [])
    }

    func testDraggingRightEdgeKeepsLeftEdge() {
        let target = ResizeEdges.right.resizeTarget(startFrame: bounds, dx: 50, dy: 0)
        XCTAssertEqual(target.width, 250)
        XCTAssertEqual(target.anchor, NSPoint(x: 0, y: 50))
    }

    func testDraggingBottomEdgeUsesAspectRatio() {
        // 下の端を 20 下げる（スクリーン座標は上が +）→ 高さ 120、幅は縦横比で 240
        let target = ResizeEdges.bottom.resizeTarget(startFrame: bounds, dx: 0, dy: -20)
        XCTAssertEqual(target.width, 240, accuracy: 0.001)
        XCTAssertEqual(target.anchor, NSPoint(x: 100, y: 100))
    }

    func testCornerFollowsTheLargerChange() {
        let target = ResizeEdges([.top, .right]).resizeTarget(startFrame: bounds, dx: 10, dy: 30)
        // 幅は 5% 、高さは 30% 大きくしたので、高さに合わせる
        XCTAssertEqual(target.width, 260, accuracy: 0.001)
        XCTAssertEqual(target.anchor, NSPoint(x: 0, y: 0))
    }
}

/// ショートカット
final class ShortcutTests: XCTestCase {
    func testDisplayStringOrder() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey), key: "2")
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘2")
        XCTAssertEqual(Shortcut.default.displayString, "⇧⌘2")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Shortcut.default)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), .default)
    }

    func testModifierConversions() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        XCTAssertEqual(Shortcut.carbonModifiers(from: flags), UInt32(cmdKey | shiftKey))
        XCTAssertEqual(Shortcut.default.menuModifierMask, flags)
        XCTAssertEqual(Shortcut.carbonModifiers(from: []), 0)
    }

    func testMenuGroupsCoverEveryActionOnce() {
        let grouped = ShortcutAction.captureActions + ShortcutAction.recordActions + ShortcutAction.pinActions + ShortcutAction.historyActions
        XCTAssertEqual(Set(grouped), Set(ShortcutAction.allCases))
        XCTAssertEqual(grouped.count, ShortcutAction.allCases.count)
    }
}

/// 書き出し
final class ImageExporterTests: XCTestCase {
    func testDecorateAddsPaddingAtImageScale() {
        // 2 倍（Retina）の画像：100×50 ポイント = 200×100 ピクセル
        let image = TestImages.make(width: 200, height: 100) { _, _ in 128 }
        var decoration = ExportDecoration()
        decoration.isEnabled = true
        decoration.padding = .small // 24pt
        let output = ImageExporter.decorate(image, pointSize: CGSize(width: 100, height: 50), with: decoration)
        XCTAssertEqual(output?.image.width, 200 + 24 * 2 * 2)
        XCTAssertEqual(output?.image.height, 100 + 24 * 2 * 2)
        XCTAssertEqual(output?.pointSize, CGSize(width: 148, height: 98))
    }

    func testRenderCropsToTheCropRect() {
        let image = TestImages.make(width: 200, height: 100) { _, _ in 128 }
        let rendered = ImageExporter.render(
            base: image,
            imageSize: CGSize(width: 100, height: 50),
            annotations: [],
            effects: EffectImages(),
            crop: CGRect(x: 10, y: 5, width: 40, height: 20)
        )
        XCTAssertEqual(rendered?.width, 80)
        XCTAssertEqual(rendered?.height, 40)
    }

    func testUniqueURLDoesNotOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PinshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = ImageExporter.uniqueURL(in: folder, fileName: "Pinshot.png")
        XCTAssertEqual(first.lastPathComponent, "Pinshot.png")
        try Data([1]).write(to: first)

        let second = ImageExporter.uniqueURL(in: folder, fileName: "Pinshot.png")
        XCTAssertEqual(second.lastPathComponent, "Pinshot 2.png")
        try Data([2]).write(to: second)

        XCTAssertEqual(ImageExporter.uniqueURL(in: folder, fileName: "Pinshot.png").lastPathComponent, "Pinshot 3.png")
    }
}

/// 画像のファイルを読む
final class ImageLoadingTests: XCTestCase {
    /// 読んだあとにファイルを消しても、画像は空にならない（文字の履歴から浮かせた画像を、もう一度読み取ると、
    /// 同じ文字の履歴をまとめるときに元のファイルを消すため、浮かせた画像が見えなくなっていた）
    func testLoadedImageSurvivesFileDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let original = TestImages.make(width: 8, height: 8) { _, _ in 200 }
        let png = try XCTUnwrap(ImageExporter.pngData(original, pointSize: CGSize(width: 8, height: 8)))
        try png.write(to: url)
        let loaded = try XCTUnwrap(CGImage.load(contentsOf: url))
        try FileManager.default.removeItem(at: url)
        let pixels = TestImages.pixels(of: loaded)
        XCTAssertEqual(pixels.first, 200, "ファイルを消したあとも、読んだ画像を描ける")
        XCTAssertEqual(pixels[3], 255, "透明になっていない")
    }
}

/// ツールのまとめ方（ツールバーのボタン）とキー。ツールを足したときの足し忘れに気づけるようにする
final class ToolGroupTests: XCTestCase {
    /// どのツールも、ちょうど 1 つの組のボタンに入る（入れ忘れると、ツールバーにボタンが出ない）
    func testEveryToolIsInExactlyOneGroup() {
        for tool in Tool.allCases {
            let groups = ToolGroup.allCases.filter { $0.tools.contains(tool) }
            XCTAssertEqual(groups, [ToolGroup.group(of: tool)], "\(tool) の組")
        }
    }

    /// ツールのキーは重ならない（重なると、先に見つけたツールしか選べない）。色の 1〜6 と太さの [ ] とも重ならない
    func testToolShortcutsAreUnique() {
        let keys = Tool.allCases.map(\.shortcut)
        XCTAssertEqual(Set(keys).count, keys.count)
        for reserved in ["1", "2", "3", "4", "5", "6", "[", "]"] {
            XCTAssertFalse(keys.contains(reserved), reserved)
        }
    }
}

/// 範囲を選ぶ画面で選んでいるもの（モード・タイマー・録画でウィンドウだけを選ぶか）
@MainActor
final class CaptureOptionsTests: XCTestCase {
    func testTimerCycles() {
        let options = CaptureOptions(mode: .region, timer: 0)
        let seen = (0..<4).map { _ in
            options.cycleTimer()
            return options.timer
        }
        XCTAssertEqual(seen, [3, 5, 10, 0])
    }

    /// space は範囲 ⇄ ウィンドウ。録画のときは切り替えない（クリックでウィンドウを選べるため）
    func testSpaceTogglesRegionAndWindowExceptRecording() {
        let options = CaptureOptions(mode: .region, timer: 0)
        options.toggleRegionAndWindow()
        XCTAssertEqual(options.mode, .window)
        options.toggleRegionAndWindow()
        XCTAssertEqual(options.mode, .region)

        options.mode = .record
        XCTAssertFalse(options.togglesWithSpace)
        options.toggleRegionAndWindow()
        XCTAssertEqual(options.mode, .record)
    }
}
