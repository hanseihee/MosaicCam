import Accelerate
import CoreGraphics

/// 이미지 일부를 모델 입력(640×640, CHW float)으로 바꾼다.
struct Tensor {
    static let side = 640

    enum Placement {
        case centered  // 가운데 정렬 (번호판 모델 학습 방식)
        case topLeft   // 왼쪽 위 정렬 (YuNet/OpenCV 방식)
    }

    var values: [Float]
    /// 캔버스 좌표 = (원본 좌표 - source.origin) * scale + offset
    let source: CGRect
    let scale: CGFloat
    let offset: CGPoint

    /// 캔버스 좌표를 원본 이미지 좌표로 되돌린다.
    func toImage(x: Float, y: Float) -> CGPoint {
        CGPoint(x: (CGFloat(x) - offset.x) / scale + source.minX,
                y: (CGFloat(y) - offset.y) / scale + source.minY)
    }

    /// - Parameters:
    ///   - source: 원본에서 잘라낼 영역 (픽셀, 왼쪽 위 원점)
    ///   - fill: 남는 여백 색 (0~255)
    ///   - bgr: 채널 순서를 BGR로
    ///   - normalize: 0~1로 나눌지 (아니면 0~255 그대로)
    init?(image: CGImage, source: CGRect, placement: Placement, fill: UInt8, bgr: Bool, normalize: Bool) {
        let n = Self.side
        let src = source.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !src.isEmpty, let crop = image.cropping(to: src) else { return nil }

        let r = min(CGFloat(n) / src.width, CGFloat(n) / src.height)
        let w = (src.width * r).rounded(), h = (src.height * r).rounded()
        let ox = placement == .centered ? ((CGFloat(n) - w) / 2).rounded(.down) : 0
        let oy = placement == .centered ? ((CGFloat(n) - h) / 2).rounded(.down) : 0

        var pixels = [UInt8](repeating: fill, count: n * n * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            // 비트맵 메모리는 위쪽 줄부터, CG 좌표는 아래쪽이 원점
            ctx.draw(crop, in: CGRect(x: ox, y: CGFloat(n) - oy - h, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // RGBX 묶음을 채널별 평면(CHW)으로 펼친다
        let plane = n * n
        var t = [Float](repeating: 0, count: plane * 3)
        let channels = bgr ? [2, 1, 0] : [0, 1, 2]
        pixels.withUnsafeBufferPointer { src in
            t.withUnsafeMutableBufferPointer { dst in
                for (i, c) in channels.enumerated() {
                    vDSP_vfltu8(src.baseAddress! + c, 4, dst.baseAddress! + i * plane, 1, vDSP_Length(plane))
                }
                if normalize {
                    var k: Float = 1 / 255
                    vDSP_vsmul(dst.baseAddress!, 1, &k, dst.baseAddress!, 1, vDSP_Length(dst.count))
                }
            }
        }
        values = t
        self.source = src
        scale = r
        offset = CGPoint(x: ox, y: oy)
    }
}
