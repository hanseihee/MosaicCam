import CoreGraphics
import Foundation

/// 사진 한 장에서 번호판과 얼굴을 찾는다. 모델은 처음 쓸 때 한 번만 올린다.
public actor RegionDetector {
    public static let shared = RegionDetector()

    /// 점수 기준과 조각 크기는 맥 실측(위키미디어 사진 22장)으로 정했다.
    struct Settings {
        var plateScore: Float = 0.4
        var plateIoU: CGFloat = 0.45
        var plateZoom: CGFloat = 2   // 멀리 있는 번호판: 긴 변 2등분
        var faceScore: Float = 0.7   // 0.6이면 바퀴·전조등도 얼굴로 잡힘
        var faceIoU: CGFloat = 0.3
        var faceZoom: CGFloat = 3    // 군중 속 작은 얼굴: 긴 변 3등분
    }

    private var settings = Settings()
    private var plateModel: OnnxModel?
    private var faceModel: OnnxModel?

    public init() {}

    /// 첫 탐지가 느리지 않게 미리 모델을 올려 둔다.
    public func warmUp() throws {
        _ = try models()
    }

    public func detect(in image: CGImage) throws -> [Region] {
        let (plate, face) = try models()
        let plates = try scan(image, zoom: settings.plateZoom, iou: settings.plateIoU) { tile in
            try Self.plates(in: image, tile: tile, model: plate, minScore: self.settings.plateScore)
        }
        let faces = try scan(image, zoom: settings.faceZoom, iou: settings.faceIoU) { tile in
            try Self.faces(in: image, tile: tile, model: face, minScore: self.settings.faceScore)
        }
        return plates + faces
    }

    private func models() throws -> (OnnxModel, OnnxModel) {
        // 번호판 모델은 안에 든 NMS가 후보 0개일 때 CoreML 실행기에서 오류가 나서
        // ("dynamic shape ... has zero elements") CPU로만 돌린다
        if plateModel == nil {
            plateModel = try OnnxModel(resource: "plate-yolov9t-640", inputName: "images", coreML: false)
        }
        if faceModel == nil {
            faceModel = try OnnxModel(resource: "face-yunet-2023mar", inputName: "input", coreML: true)
        }
        return (plateModel!, faceModel!)
    }

    private func scan(_ image: CGImage, zoom: CGFloat, iou: CGFloat,
                      run: (CGRect) throws -> [Region]) throws -> [Region] {
        let size = CGSize(width: image.width, height: image.height)
        var found: [Region] = []
        for (n, tile) in Tiling.tiles(width: size.width, height: size.height, zoom: zoom).enumerated() {
            let hits = try run(tile)
            found += n == 0 ? hits : hits.filter { !Tiling.touchesInnerEdge($0.rect, tile: tile, imageSize: size) }
        }
        return Tiling.suppress(found, iou: iou)
    }

    // MARK: - 번호판 (YOLOv9 end2end, 출력 [N, 7] = batch, x1, y1, x2, y2, class, score)

    private static func plates(in image: CGImage, tile: CGRect, model: OnnxModel, minScore: Float) throws -> [Region] {
        guard let t = Tensor(image: image, source: tile, placement: .centered, fill: 114, bgr: false, normalize: true)
        else { return [] }
        let out = try model.run(t.values, outputs: ["output0"])["output0"] ?? []
        return stride(from: 0, to: out.count - 6, by: 7).compactMap { i in
            let score = out[i + 6]
            guard score >= minScore else { return nil }
            let p1 = t.toImage(x: out[i + 1], y: out[i + 2]), p2 = t.toImage(x: out[i + 3], y: out[i + 4])
            return Region(rect: CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y), kind: .plate, score: score)
        }
    }

    // MARK: - 얼굴 (YuNet 2023mar, OpenCV FaceDetectorYN과 같은 해석)

    private static let faceStrides = [8, 16, 32]

    private static func faces(in image: CGImage, tile: CGRect, model: OnnxModel, minScore: Float) throws -> [Region] {
        guard let t = Tensor(image: image, source: tile, placement: .topLeft, fill: 0, bgr: true, normalize: false)
        else { return [] }
        let names = faceStrides.flatMap { ["cls_\($0)", "obj_\($0)", "bbox_\($0)"] }
        let out = try model.run(t.values, outputs: names)
        var regions: [Region] = []
        for s in faceStrides {
            guard let cls = out["cls_\(s)"], let obj = out["obj_\(s)"], let box = out["bbox_\(s)"] else { continue }
            let cols = Tensor.side / s
            for i in 0..<cls.count {
                let score = (min(max(cls[i], 0), 1) * min(max(obj[i], 0), 1)).squareRoot()
                guard score >= minScore else { continue }
                let row = Float(i / cols), col = Float(i % cols), st = Float(s)
                let cx = (col + box[i * 4]) * st, cy = (row + box[i * 4 + 1]) * st
                let w = exp(box[i * 4 + 2]) * st, h = exp(box[i * 4 + 3]) * st
                let p1 = t.toImage(x: cx - w / 2, y: cy - h / 2), p2 = t.toImage(x: cx + w / 2, y: cy + h / 2)
                regions.append(Region(rect: CGRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y),
                                      kind: .face, score: score))
            }
        }
        return regions
    }
}
