import CoreGraphics
import XCTest
@testable import MosaicCore

final class MosaicTests: XCTestCase {
    /// 가로 줄무늬 테스트 이미지 (픽셀마다 값이 달라 모자이크 여부가 드러난다)
    private func stripes(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            let v = CGFloat((x * 37) % 256) / 255
            ctx.setFillColor(CGColor(srgbRed: v, green: 1 - v, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buf.withUnsafeMutableBytes {
            let ctx = CGContext(data: $0.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buf
    }

    func testOnlySelectedAreaChanges() throws {
        let image = stripes(width: 400, height: 300)
        let region = Region(rect: CGRect(x: 100, y: 50, width: 160, height: 80), kind: .manual)
        let out = try XCTUnwrap(Mosaic.apply(to: image, regions: [region]))
        XCTAssertEqual(out.width, 400)
        XCTAssertEqual(out.height, 300)

        let before = pixels(image), after = pixels(out)
        func px(_ p: [UInt8], _ x: Int, _ y: Int) -> UInt8 { p[(y * 400 + x) * 4] }

        // 영역 밖은 그대로 (위쪽 줄, 왼쪽 위 원점)
        for x in stride(from: 0, to: 400, by: 7) {
            XCTAssertEqual(px(before, x, 10), px(after, x, 10), "영역 밖 x=\(x)")
        }
        // 영역 안은 이웃한 픽셀끼리 같은 칸 → 원본보다 값 변화가 훨씬 적다
        var changesBefore = 0, changesAfter = 0
        for x in 101..<259 {
            if px(before, x, 90) != px(before, x + 1, 90) { changesBefore += 1 }
            if px(after, x, 90) != px(after, x + 1, 90) { changesAfter += 1 }
        }
        XCTAssertGreaterThan(changesBefore, 100)
        XCTAssertLessThan(changesAfter, 15)
    }
}
