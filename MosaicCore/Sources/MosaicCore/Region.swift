import CoreGraphics
import Foundation

/// 사진 속 가릴 수 있는 영역 하나.
public struct Region: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case plate   // 번호판
        case face    // 얼굴
        case manual  // 사용자가 직접 그린 영역
    }

    public let id: UUID
    /// 이미지 픽셀 좌표, 왼쪽 위 원점
    public var rect: CGRect
    public var kind: Kind
    public var score: Float

    public init(id: UUID = UUID(), rect: CGRect, kind: Kind, score: Float = 1) {
        self.id = id
        self.rect = rect
        self.kind = kind
        self.score = score
    }
}
