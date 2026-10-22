import StoreKitTest
import XCTest

/// 저장 → 전면 광고 → 저장, 그리고 광고 제거 구매 화면을 확인한다.
/// 광고는 구글 시험 광고(DEBUG), 결제는 스킴의 Products.storekit 시험 설정을 쓴다.
final class AdsAndPurchaseUITests: XCTestCase {
    private let samples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("MosaicCore/Tests/MosaicCoreTests/Samples")

    override func setUp() {
        continueAfterFailure = false
    }

    /// 실패 원인 조사용: TEST_RUNNER_UITEST_DEBUG_DIR=폴더 를 주면 화면과 접근성 트리를 남긴다
    @MainActor
    private func dump(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["UITEST_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/\(name).png"))
        try? app.debugDescription.write(toFile: dir + "/\(name).txt", atomically: true, encoding: .utf8)
    }

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// 시스템 알림(추적 허용, 사진 추가 등)이 떠 있으면 허용 쪽을 누른다. 없으면 바로 돌아온다
    @MainActor
    @discardableResult
    private func allowSystemAlertIfShown() -> Bool {
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return false }
        let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "허용", "OK", "확인"])).firstMatch
        if allow.exists {
            allow.tap()
        } else {
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        }
        return true
    }

    /// 알림을 허용해 가며 element가 나타날 때까지 기다린다 (잠깐만 보이는 안내 문구도 놓치지 않게 짧게 자주 본다)
    @MainActor
    private func waitAllowingAlerts(for element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            allowSystemAlertIfShown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.exists
    }

    @MainActor
    func testSaveShowsAdThenSaves() throws {
        // 다른 테스트가 시험 결제로 산 기록을 지워 광고가 나오는 상태로 만든다
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.clearTransactions()
        // 지운 기록이 앱 시작 때 아직 보이면 "광고 제거 구매함"으로 잡히므로 잠깐 기다린다
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let app = XCUIApplication()
        app.launchEnvironment["MOSAIC_DEMO_IMAGE"] = samples.appendingPathComponent("world6.jpg").path
        // 다른 테스트가 남긴 "광고 제거 구매함" 기억을 덮어쓴다 (UserDefaults 인자 도메인)
        app.launchArguments += ["-adsRemoved", "0", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()

        XCTAssertTrue(app.buttons["번호판"].waitForExistence(timeout: 30), "번호판을 찾지 못함")
        // 광고 SDK 준비와 첫 광고 받기에 몇 초 걸리므로 사람처럼 잠깐 둘러본 뒤 저장한다
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        app.buttons["저장"].tap()

        // 처음 한 번 뜨는 추적 허용 알림을 지나, 시험 광고의 카운트다운이 끝나 닫기("Close")가 생길 때까지
        let closeAd = app.buttons["Close"]
        let closeArea = app.buttons["Close Advertisement"]
        let shown = waitAllowingAlerts(for: closeAd, timeout: 40)
        dump(app, "ad")
        XCTAssertTrue(shown, "전면 광고가 뜨지 않음")
        // 닫기는 광고가 뜨고 5초 카운트다운이 끝나야 먹는다. 그 전에 누르면 광고 본문 탭(클릭)으로 처리되므로
        // 충분히 기다린 뒤 한 번 누르고, 남아 있으면 2초 간격으로 몇 번 더 누른다
        RunLoop.current.run(until: Date().addingTimeInterval(6))
        for _ in 0..<4 where closeAd.exists {
            let frame = closeArea.exists ? closeArea.frame : closeAd.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
        }
        XCTAssertFalse(closeAd.exists, "광고가 닫히지 않음")

        // 광고가 닫히면 바로 저장된다. 사진 추가 권한 알림이 뜨면 허용하고, 2초만 보이는 안내 문구를 잡는다
        let saved = waitAllowingAlerts(for: app.staticTexts["사진 앱에 저장했어요"], timeout: 20)
        dump(app, "saved")
        XCTAssertTrue(saved, "광고 뒤에 저장되지 않음")
    }

    @MainActor
    func testRemoveAdsSheetShowsPriceAndPurchases() throws {
        // 시험 결제: 확인 창 없이 바로 성공하고, 전에 산 기록은 지운다
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()

        let app = XCUIApplication()
        app.launchArguments += ["-adsRemoved", "0", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()

        let link = app.buttons["광고 없이 쓰기"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "홈 아래 광고 없이 쓰기 링크가 없음")
        link.tap()

        // 스킴의 시험 결제 설정에서 ₩3,000 상품을 받아 온다
        let buy = app.buttons.matching(NSPredicate(format: "label CONTAINS '3,000' AND label CONTAINS '광고 제거'")).firstMatch
        let priced = buy.waitForExistence(timeout: 15)
        dump(app, "sheet")
        XCTAssertTrue(priced, "₩3,000 상품이 보이지 않음")
        buy.tap()

        // 사고 나면 시트가 닫히고 홈 아래 문구가 바뀐다
        let done = app.staticTexts["광고 없이 쓰고 있어요"].waitForExistence(timeout: 20)
        dump(app, "purchased")
        XCTAssertTrue(done, "구매 뒤 광고 없이 쓰는 상태가 되지 않음")

        // 다음 테스트가 광고를 볼 수 있게 시험 구매 기록을 지운다
        session.clearTransactions()
    }
}
