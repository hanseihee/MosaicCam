import CoreGraphics
import UIKit

extension UIImage {
    /// 방향을 바로 세우고(왼쪽 위 원점 픽셀 = 화면에 보이는 그대로) 긴 변을 `maxSide` 이하로 줄인다.
    /// 다시 그리면서 촬영 위치 같은 메타데이터도 떨어져 나간다.
    func normalizedCGImage(maxSide: CGFloat = 4096) -> CGImage? {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        let k = min(1, maxSide / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * k).rounded(), height: (pixels.height * k).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}

extension CGImage {
    /// 미리보기용 축소본. 이미 작으면 그대로.
    func downscaled(maxSide: Int) -> CGImage {
        let longest = max(width, height)
        guard longest > maxSide else { return self }
        let k = CGFloat(maxSide) / CGFloat(longest)
        let w = Int((CGFloat(width) * k).rounded()), h = Int((CGFloat(height) * k).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return self }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? self
    }
}
