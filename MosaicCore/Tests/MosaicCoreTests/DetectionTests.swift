import CoreGraphics
import ImageIO
import XCTest
@testable import MosaicCore

/// 기대값은 같은 처리 과정을 파이썬(onnxruntime)으로 돌린 기준 결과에서 왔다.
final class DetectionTests: XCTestCase {
    private func sample(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Samples"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func counts(_ name: String) async throws -> (plates: Int, faces: Int) {
        let image = try sample(name)
        try await RegionDetector.shared.warmUp()
        let start = ContinuousClock.now
        let regions = try await RegionDetector.shared.detect(in: image)
        let elapsed = ContinuousClock.now - start
        let result = (regions.filter { $0.kind == .plate }.count, regions.filter { $0.kind == .face }.count)
        print("\(name): 번호판 \(result.0), 얼굴 \(result.1), \(elapsed.formatted(.units(allowed: [.milliseconds])))")
        return result
    }

    func testGroupPhotos() async throws {
        let a = try await counts("face1")
        XCTAssertEqual(a.faces, 11)
        XCTAssertEqual(a.plates, 0)
        let b = try await counts("face2")
        XCTAssertEqual(b.faces, 15)
        XCTAssertEqual(b.plates, 0)
    }

    func testCrowdSmallFaces() async throws {
        let c = try await counts("face3")
        XCTAssertGreaterThanOrEqual(c.faces, 10)  // 기준 13
        XCTAssertEqual(c.plates, 0)
    }

    func testPlatesWorldwide() async throws {
        let taxi = try await counts("car5")         // 싱가포르 택시 + 트럭, 문짝 전화번호는 아님
        XCTAssertEqual(taxi.plates, 2)
        let closeUp = try await counts("car6")      // 한국 노란 번호판 근접 → 조각 경계 중복 없어야
        XCTAssertEqual(closeUp.plates, 1)
        let german = try await counts("world6")     // 독일 LB B4
        XCTAssertEqual(german.plates, 1)
        let far = try await counts("world7")        // 멀리 작은 프랑스 번호판
        XCTAssertEqual(far.plates, 1)
    }

    func testPlateAndFacesTogether() async throws {
        let accident = try await counts("car8")
        XCTAssertEqual(accident.plates, 1)
        XCTAssertGreaterThanOrEqual(accident.faces, 1)  // 기준 2
    }

    func testTilesCoverImage() {
        let tiles = Tiling.tiles(width: 4032, height: 3024, zoom: 3)
        XCTAssertEqual(tiles.first, CGRect(x: 0, y: 0, width: 4032, height: 3024))
        let union = tiles.dropFirst().reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union, CGRect(x: 0, y: 0, width: 4032, height: 3024))
    }
}
