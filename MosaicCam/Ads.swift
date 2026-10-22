import AppTrackingTransparency
import GoogleMobileAds
import Observation
import UIKit

/// 광고 단위 ID. DEBUG는 구글 시험용이라 어디서나 시험 광고가 나오고(내 광고를 눌러도 정책 위반이 안 됨),
/// 출시 빌드는 에드몹 콘솔의 "저장 전면 광고" 단위를 쓴다.
enum AdUnit {
    #if DEBUG
    static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let interstitial = "ca-app-pub-4582716621646848/6196518817"
    #endif
}

/// 저장할 때 보여 주는 전면 광고. 광고 제거를 샀으면 아무것도 하지 않는다.
@MainActor @Observable
final class AdManager: NSObject {
    static let shared = AdManager()

    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var dismissed: CheckedContinuation<Void, Never>?

    private override init() { super.init() }

    /// 앱이 뜰 때 한 번. 광고 제거를 안 샀으면 첫 광고를 미리 받아 둔다
    func start() {
        Task { await preload() }
    }

    /// 다음 광고를 미리 받아 둔다. 이미 있거나 받는 중이면 그대로.
    /// SDK는 처음 필요할 때 켠다(광고 제거를 샀다가 환불돼도 다시 광고가 나오도록)
    func preload() async {
        guard !Purchases.shared.adsRemoved, interstitial == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let start = ContinuousClock.now
        if !started {
            started = true
            _ = await MobileAds.shared.start()
            #if DEBUG
            debugLog("광고 SDK 준비 \(debugElapsed(since: start))")
            #endif
        }
        do {
            let ad = try await InterstitialAd.load(with: AdUnit.interstitial, request: Request())
            ad.fullScreenContentDelegate = self
            interstitial = ad
            #if DEBUG
            debugLog("광고 받음 \(debugElapsed(since: start))")
            #endif
        } catch {
            #if DEBUG
            debugLog("광고 받기 실패 \(error.localizedDescription)")
            #endif
        }
    }

    /// 전면 광고를 보여 주고 닫힐 때까지 기다린다.
    /// 받아 둔 광고가 없으면 바로 돌아온다(광고 때문에 저장을 막지 않는다).
    /// - Returns: 광고를 보여 줬는지
    @discardableResult
    func showInterstitial() async -> Bool {
        guard !Purchases.shared.adsRemoved else { return false }
        // 첫 광고 전에 추적 허용 여부를 묻는다. iOS가 한 번만 띄운다
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        // 추적 허용 창을 기다리는 사이에 광고 제거를 샀을 수도 있다
        guard !Purchases.shared.adsRemoved else { return false }
        // 받는 중이면 잠깐만 기다려 본다(최대 3초). 그래도 없으면 광고 없이 저장한다
        for _ in 0..<15 where interstitial == nil && loading {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let ad = interstitial, let presenter = Self.topViewController() else {
            #if DEBUG
            debugLog("광고 없이 진행 (받아 둔 광고 없음)")
            #endif
            Task { await preload() }
            return false
        }
        interstitial = nil
        do {
            // 받아 둔 지 오래돼 만료됐거나 지금 띄울 수 없으면 광고 없이 넘어간다
            try ad.canPresent(from: presenter)
        } catch {
            #if DEBUG
            debugLog("광고 띄울 수 없음 \(error.localizedDescription)")
            #endif
            Task { await preload() }
            return false
        }
        // SDK 콜백이 끝내 오지 않더라도 저장이 영원히 막히지 않게 감시 시간을 둔다
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            finish()
        }
        await withCheckedContinuation { continuation in
            dismissed = continuation
            ad.present(from: presenter)
        }
        watchdog.cancel()
        Task { await preload() }
        return true
    }

    /// 어느 경로로 끝나든 딱 한 번만 깨운다
    private func finish() {
        guard let continuation = dismissed else { return }
        dismissed = nil
        continuation.resume()
    }

    /// 지금 맨 위에 떠 있는 화면(편집 화면은 전체 화면 덮개라 루트가 아니다)
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension AdManager: FullScreenContentDelegate {
    // SDK가 주 스레드에서 부른다
    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        #if DEBUG
        debugLog("광고 띄우기 실패 \(error.localizedDescription)")
        #endif
        MainActor.assumeIsolated { finish() }
    }
}
