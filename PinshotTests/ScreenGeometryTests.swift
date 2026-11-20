import XCTest

/// ツールバー・操作バーを画像の下に置く位置
final class ScreenGeometryTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let bar = NSSize(width: 200, height: 30)

    func testPlacesBelowImageWhenThereIsRoom() {
        let image = NSRect(x: 300, y: 400, width: 400, height: 300)
        let origin = ScreenGeometry.originBelow(image, size: bar, gap: 8, in: screen)
        XCTAssertEqual(origin, NSPoint(x: 400, y: 362))
    }

    func testMovesToScreenBottomInsteadOfAboveWhenNoRoomBelow() {
        // 画像の下端が画面の下端に近い（ドラッグで下へ動かした）
        let image = NSRect(x: 300, y: 10, width: 400, height: 300)
        let origin = ScreenGeometry.originBelow(image, size: bar, gap: 8, in: screen, edgeGap: 8)
        XCTAssertEqual(origin.y, 8)
    }

    func testCentersOnVisiblePartOfLargeImage() {
        // 拡大して、画像が画面の左と下にはみ出している
        let image = NSRect(x: -1000, y: -500, width: 1600, height: 1000)
        let origin = ScreenGeometry.originBelow(image, size: bar, gap: 8, in: screen)
        // 見えている部分は x 0〜600 なので、その真ん中（300）に置く
        XCTAssertEqual(origin, NSPoint(x: 200, y: 8))
    }

    func testClampedXKeepsMarginFromBothEdges() {
        XCTAssertEqual(ScreenGeometry.clampedX(-50, width: 200, in: screen), 4)
        XCTAssertEqual(ScreenGeometry.clampedX(950, width: 200, in: screen), 1000 - 200 - 4)
        XCTAssertEqual(ScreenGeometry.clampedX(300, width: 200, in: screen), 300)
    }

    func testStaysInsideScreenHorizontally() {
        let image = NSRect(x: 900, y: 400, width: 100, height: 100)
        let origin = ScreenGeometry.originBelow(image, size: bar, gap: 8, in: screen)
        XCTAssertEqual(origin.x, 1000 - 200 - 4)
    }
}

/// 操作パネルを置く位置
final class FirstFittingOriginTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = NSSize(width: 200, height: 50)

    func testPicksFirstCandidateThatFits() {
        // 1 つ目は画面の下にはみ出すので、2 つ目にする
        let origin = ScreenGeometry.firstFittingOrigin([NSPoint(x: 100, y: -20), NSPoint(x: 100, y: 300)], size: size, in: visible)
        XCTAssertEqual(origin, NSPoint(x: 100, y: 300))
    }

    func testFallsBackToBottomRight() {
        let origin = ScreenGeometry.firstFittingOrigin([NSPoint(x: 900, y: -100)], size: size, in: visible)
        XCTAssertEqual(origin, NSPoint(x: 784, y: 16))
    }
}

/// 画像のまわりの部品（ツールバー・操作バー）を置く画面
final class PartsScreenTests: XCTestCase {
    private let left = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let right = NSRect(x: 1000, y: 0, width: 1000, height: 800)

    func testUsesScreenWithImageCenter() {
        // 画像の大部分が右の画面（真ん中も右）。重なっている画面の一覧では左が先でも、右に置く
        let image = NSRect(x: 900, y: 300, width: 400, height: 200)
        XCTAssertEqual(ScreenGeometry.screenIndex(forPartsOf: image, in: [left, right]), 1)
    }

    func testFallsBackToIntersectingScreenWhenCenterIsOutside() {
        // 真ん中がどの画面にもない（画面の下へはみ出させた）
        let image = NSRect(x: 100, y: -300, width: 400, height: 400)
        XCTAssertEqual(ScreenGeometry.screenIndex(forPartsOf: image, in: [left, right]), 0)
    }

    func testNoScreen() {
        XCTAssertNil(ScreenGeometry.screenIndex(forPartsOf: NSRect(x: 5000, y: 5000, width: 10, height: 10), in: [left, right]))
    }
}
