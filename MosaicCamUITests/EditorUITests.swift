import XCTest

/// 디버그 경로(MOSAIC_DEMO_IMAGE)로 사진을 바로 열어 탭·직접 그리기·되돌리기를 확인한다.
final class EditorUITests: XCTestCase {
    private let samples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MosaicCore/Tests/MosaicCoreTests/Samples")

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTapToMaskThenDrawAndUndo() throws {
        let app = XCUIApplication()
        // 독일 번호판 하나만 있는 사진
        app.launchEnvironment["MOSAIC_DEMO_IMAGE"] = samples.appendingPathComponent("world6.jpg").path
        // 문구를 한국어로 고정 (앱이 여러 언어를 지원한다)
        app.launchArguments += ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()

        let plate = app.buttons["번호판"]
        XCTAssertTrue(plate.waitForExistence(timeout: 30), "번호판을 찾지 못함")
        XCTAssertEqual(plate.value as? String, "안 가림")

        // 상자 자체는 터치를 받지 않으니 그 자리를 눌러 사진 쪽 탭으로 처리되는지 본다
        plate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // 실패 원인 조사용: TEST_RUNNER_UITEST_DEBUG_DIR=폴더 를 주면 화면과 접근성 트리를 남긴다
        if let dir = ProcessInfo.processInfo.environment["UITEST_DEBUG_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/after_tap.png"))
            try? "\(plate.frame) \(app.frame)\n\(app.debugDescription)".write(toFile: dir + "/tree.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(plate.value as? String, "가림")
        XCTAssertTrue(app.buttons["모두 풀기"].exists)

        // 직접 그리기: 사진 왼쪽 위 빈 곳을 끈다
        app.buttons["직접 그리기"].tap()
        let image = app.coordinate(withNormalizedOffset: .zero)
        let frame = plate.frame
        let start = image.withOffset(CGVector(dx: 30, dy: frame.minY - 120))
        let end = image.withOffset(CGVector(dx: 130, dy: frame.minY - 60))
        start.press(forDuration: 0.2, thenDragTo: end)
        let manual = app.buttons["직접 그린 곳"]
        XCTAssertTrue(manual.waitForExistence(timeout: 3), "직접 그린 영역이 생기지 않음")
        XCTAssertEqual(manual.value as? String, "가림")

        // 되돌리기 두 번 → 처음 상태
        app.buttons["되돌리기"].tap()
        XCTAssertFalse(manual.exists)
        app.buttons["되돌리기"].tap()
        XCTAssertEqual(plate.value as? String, "안 가림")
        XCTAssertTrue(app.buttons["모두 가리기"].exists)
    }
}
