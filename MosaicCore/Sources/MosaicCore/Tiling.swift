import CoreGraphics

/// 큰 사진을 640 입력 모델로 훑기 위한 조각 나누기와 결과 합치기.
enum Tiling {
    /// 전체 1장 + 긴 변을 `zoom` 등분한 정사각 조각들(20% 겹침).
    static func tiles(width: CGFloat, height: CGFloat, zoom: CGFloat) -> [CGRect] {
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        let longest = max(width, height)
        let side = max(longest / zoom, CGFloat(Tensor.side))
        guard side < longest * 0.9 else { return [whole] }

        let step = side * 0.8
        let nx = max(1, Int(((width - side * 0.2) / step).rounded(.up)))
        let ny = max(1, Int(((height - side * 0.2) / step).rounded(.up)))
        var out = [whole]
        for j in 0..<ny {
            for i in 0..<nx {
                let x = nx > 1 ? min(width - side, CGFloat(i) * step) : 0
                let y = ny > 1 ? min(height - side, CGFloat(j) * step) : 0
                out.append(CGRect(x: max(0, x), y: max(0, y), width: min(side, width), height: min(side, height)))
            }
        }
        return out
    }

    /// 조각 안쪽 경계에 닿은 상자는 잘린 물체일 수 있어 버린다. 사진 가장자리에 닿은 건 남긴다.
    static func touchesInnerEdge(_ box: CGRect, tile: CGRect, imageSize: CGSize) -> Bool {
        let e = tile.width * 0.01
        return (box.minX < tile.minX + e && tile.minX > 0)
            || (box.minY < tile.minY + e && tile.minY > 0)
            || (box.maxX > tile.maxX - e && tile.maxX < imageSize.width)
            || (box.maxY > tile.maxY - e && tile.maxY < imageSize.height)
    }

    /// 점수 높은 순으로 남기고, 많이 겹치거나 거의 포함되는 상자는 버린다.
    static func suppress(_ regions: [Region], iou threshold: CGFloat) -> [Region] {
        var keep: [Region] = []
        for r in regions.sorted(by: { $0.score > $1.score }) {
            let duplicate = keep.contains { k in
                let i = r.rect.intersection(k.rect)
                guard !i.isNull else { return false }
                let inter = i.width * i.height
                let a = r.rect.width * r.rect.height, b = k.rect.width * k.rect.height
                return inter / (a + b - inter) > threshold || inter / min(a, b) > 0.7
            }
            if !duplicate { keep.append(r) }
        }
        return keep
    }
}
