import CoreImage
import MosaicCore
import Observation
import SwiftUI

/// 사진 한 장의 편집 상태: 찾은 영역, 가린 영역, 되돌리기 기록.
@MainActor @Observable
final class EditorModel: Identifiable {
    enum Phase: Equatable {
        case detecting
        case ready
        case failed(String)
    }

    let id = UUID()
    let original: CGImage
    private(set) var regions: [Region] = []
    private(set) var masked: Set<UUID> = []
    private(set) var phase: Phase = .detecting
    /// 화면에 보이는 축소본 (모자이크 반영)
    private(set) var preview: CGImage

    @ObservationIgnored private let previewBase: CGImage
    @ObservationIgnored private let previewScale: CGFloat
    @ObservationIgnored private var history: [(regions: [Region], masked: Set<UUID>)] = []
    @ObservationIgnored private let context = CIContext()

    init(image: CGImage) {
        original = image
        previewBase = image.downscaled(maxSide: 2048)
        previewScale = CGFloat(previewBase.width) / CGFloat(image.width)
        preview = previewBase
    }

    var imageSize: CGSize { CGSize(width: original.width, height: original.height) }
    var canUndo: Bool { !history.isEmpty }
    var allMasked: Bool { !regions.isEmpty && masked.count == regions.count }
    var plateCount: Int { regions.filter { $0.kind == .plate }.count }
    var faceCount: Int { regions.filter { $0.kind == .face }.count }

    func detect() async {
        phase = .detecting
        let start = ContinuousClock.now
        do {
            let found = try await RegionDetector.shared.detect(in: original)
            regions = found + regions.filter { $0.kind == .manual }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
        #if DEBUG
        debugLog("탐지 \(debugElapsed(since: start)) · \(original.width)×\(original.height) · 번호판 \(plateCount) · 얼굴 \(faceCount)")
        if ProcessInfo.processInfo.environment["MOSAIC_DEMO_MASK_ALL"] != nil, !allMasked { toggleAll() }
        #endif
    }

    func isMasked(_ region: Region) -> Bool { masked.contains(region.id) }

    /// 탭한 곳의 영역. 작은 얼굴도 누를 수 있게 최소 크기로 넓혀서 찾고, 겹치면 작은 쪽.
    func region(at point: CGPoint, minSide: CGFloat) -> Region? {
        regions
            .filter { r in
                let dx = max(0, (minSide - r.rect.width) / 2), dy = max(0, (minSide - r.rect.height) / 2)
                return r.rect.insetBy(dx: -dx, dy: -dy).contains(point)
            }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    func toggle(_ region: Region) {
        record()
        if masked.contains(region.id) { masked.remove(region.id) } else { masked.insert(region.id) }
        render()
    }

    func toggleAll() {
        record()
        masked = allMasked ? [] : Set(regions.map(\.id))
        render()
    }

    func addManual(_ rect: CGRect) {
        let clipped = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clipped.isEmpty else { return }
        record()
        let region = Region(rect: clipped, kind: .manual)
        regions.append(region)
        masked.insert(region.id)
        render()
    }

    func undo() {
        guard let last = history.popLast() else { return }
        regions = last.regions
        masked = last.masked
        render()
    }

    /// 저장·공유용 원본 해상도 결과
    func renderFull() -> CGImage? {
        let start = ContinuousClock.now
        let image = Mosaic.apply(to: original, regions: selected, context: context)
        #if DEBUG
        debugLog("원본 렌더링 \(debugElapsed(since: start)) · 가린 곳 \(selected.count)")
        #else
        _ = start
        #endif
        return image
    }

    private var selected: [Region] { regions.filter { masked.contains($0.id) } }

    private func record() {
        history.append((regions, masked))
        if history.count > 100 { history.removeFirst() }
    }

    private func render() {
        let chosen = selected
        preview = chosen.isEmpty
            ? previewBase
            : Mosaic.apply(to: previewBase, regions: chosen, scale: previewScale, context: context) ?? previewBase
    }
}
