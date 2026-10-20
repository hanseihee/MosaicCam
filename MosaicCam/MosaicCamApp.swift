import MosaicCore
import SwiftUI

@main
struct MosaicCamApp: App {
    init() {
        // 첫 사진에서 기다리지 않게 모델을 미리 올린다
        Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            try? await RegionDetector.shared.warmUp()
            #if DEBUG
            debugLog("모델 준비 \(debugElapsed(since: start))")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
    }
}
