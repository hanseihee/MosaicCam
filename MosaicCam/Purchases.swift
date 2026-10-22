import Observation
import StoreKit

/// 광고 제거 구매(한 번 사면 계속). 값(₩3,000)은 App Store Connect에서 정하고, 여기서는 상품 ID만 안다.
@MainActor @Observable
final class Purchases {
    static let shared = Purchases()
    static let removeAdsID = "realmasse.mosaiccam.removeads"
    private static let adsRemovedKey = "adsRemoved"

    /// 광고 제거를 샀는지. 마지막 확인 결과를 기억해 두어 인터넷이 없어도 쓴다
    private(set) var adsRemoved = UserDefaults.standard.bool(forKey: Purchases.adsRemovedKey)
    private(set) var product: Product?
    private(set) var loadingProduct = false
    private(set) var busy = false
    private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {}

    /// 앱이 뜰 때 한 번: 거래 변화(다른 기기 구매, 환불, 승인 대기 후 승인)를 계속 듣고, 산 기록과 상품을 확인한다
    func start() {
        updates = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                apply(transaction)
                await transaction.finish()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    /// 상품(값 포함)을 App Store에서 받아 온다. 실패하면 message에 남기고, 구매 화면에서 다시 시도할 수 있다
    func loadProduct() async {
        guard !loadingProduct else { return }
        loadingProduct = true
        defer { loadingProduct = false }
        do {
            product = try await Product.products(for: [Self.removeAdsID]).first
            if product == nil { message = String(localized: "상품을 찾지 못했어요. 잠시 뒤 다시 시도해 주세요.") }
        } catch {
            message = String(localized: "상품을 불러오지 못했어요. 인터넷을 확인하고 다시 시도해 주세요.")
            #if DEBUG
            debugLog("상품 받기 실패 \(error)")
            #endif
        }
    }

    /// App Store가 알려 주는 현재 권한에 맞춘다. 환불돼서 권한이 사라졌으면 광고 제거도 푼다
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.removeAdsID else { continue }
            owned = transaction.revocationDate == nil
        }
        setAdsRemoved(owned)
    }

    /// 구매. 끝났으면 true
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else { return false }
        busy = true
        message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = String(localized: "구매를 확인하지 못했어요.")
                    return false
                }
                apply(transaction)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                message = String(localized: "승인을 기다리고 있어요. 승인되면 자동으로 적용돼요.")
                return false
            @unknown default:
                return false
            }
        } catch {
            message = String(localized: "구매하지 못했어요: \(error.localizedDescription)")
            return false
        }
    }

    /// 다시 설치했거나 기기를 바꿨을 때 산 기록을 가져온다
    func restore() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = adsRemoved ? String(localized: "광고 제거를 다시 적용했어요.") : String(localized: "이 Apple 계정으로 산 기록이 없어요.")
        } catch {
            message = String(localized: "복원하지 못했어요: \(error.localizedDescription)")
        }
    }

    private func apply(_ transaction: Transaction) {
        guard transaction.productID == Self.removeAdsID else { return }
        setAdsRemoved(transaction.revocationDate == nil)
    }

    private func setAdsRemoved(_ owned: Bool) {
        adsRemoved = owned
        UserDefaults.standard.set(owned, forKey: Self.adsRemovedKey)
    }
}
