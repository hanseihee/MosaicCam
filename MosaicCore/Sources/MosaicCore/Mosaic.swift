import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// 고른 영역을 모자이크한 이미지를 만든다. 결과는 픽셀 자체가 바뀌어 되돌릴 수 없다.
public enum Mosaic {
    /// 얼굴 상자는 이마·귀까지 덮도록 넓힌다.
    static func padded(_ region: Region) -> CGRect {
        let r = region.rect
        switch region.kind {
        case .face: return r.insetBy(dx: -r.width * 0.15, dy: -r.height * 0.15)
        case .plate: return r.insetBy(dx: -r.width * 0.04, dy: -r.height * 0.1)
        case .manual: return r
        }
    }

    /// - Parameter scale: `regions` 좌표에 곱할 배율 (미리보기용 축소 이미지에 그릴 때)
    public static func apply(to image: CGImage, regions: [Region], scale: CGFloat = 1,
                             context: CIContext = CIContext()) -> CGImage? {
        let base = CIImage(cgImage: image)
        let extent = base.extent
        var out = base
        for region in regions {
            let p = padded(region)
            // CI 좌표는 왼쪽 아래 원점
            let rect = CGRect(x: p.minX * scale, y: extent.height - p.maxY * scale,
                              width: p.width * scale, height: p.height * scale)
                .integral.intersection(extent)
            guard !rect.isEmpty else { continue }
            // 칸 하나가 영역 긴 변의 1/8 → 가로 8칸 안팎이라 알아볼 수 없다
            let block = max(6 * scale, max(rect.width, rect.height) / 8)
            // 흐리게 한 뒤 칸으로 나눠 칸 안의 색을 평균에 가깝게 만든다
            let blurred = base.clampedToExtent().applyingGaussianBlur(sigma: Double(block) / 2)
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = blurred
            pixellate.center = rect.origin
            pixellate.scale = Float(block)
            guard let blocks = pixellate.outputImage?.cropped(to: rect) else { continue }
            out = blocks.composited(over: out)
        }
        return context.createCGImage(out, from: extent)
    }
}
