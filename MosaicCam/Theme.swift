import SwiftUI

/// 화면 전체에서 쓰는 색·글꼴·유리 질감 부품.
/// 어두운 바탕에 흐릿하게 번진 사진 같은 그라데이션을 깔고, 그 위에 반투명 유리 알약을 올린다.
enum Theme {
    // MARK: 색
    /// 바닥 #0F0E0E
    static let ink = Color(red: 0.059, green: 0.055, blue: 0.055)
    /// 위쪽 청록 #294D63
    static let harbor = Color(red: 0.16, green: 0.30, blue: 0.39)
    /// 가운데 흙빛 #8A6050
    static let clay = Color(red: 0.541, green: 0.376, blue: 0.314)
    /// 따뜻하게 번지는 살구빛 #D9A892
    static let peach = Color(red: 0.851, green: 0.659, blue: 0.573)
    /// 보조 글자 #CFCCCB
    static let mist = Color(red: 0.812, green: 0.800, blue: 0.796)
    /// 강조 #FF5A3C (AccentColor와 같은 값)
    static let ember = Color(red: 1.0, green: 0.353, blue: 0.235)

    /// 찾은 영역 상자 색. 사진 위에서도 잘 보이도록 강조색·청록을 밝힌 것
    static let plateBox = Color(red: 1.0, green: 0.52, blue: 0.40)
    static let faceBox = Color(red: 0.55, green: 0.85, blue: 0.95)
    static let manualBox = Color.white

    // MARK: 유리
    static let glassStroke = Color.white.opacity(0.16)
    static let glassStrokeBright = Color.white.opacity(0.55)

    // MARK: 글꼴
    static let wordmark = Font.system(size: 21, weight: .medium).italic()
    static let headline = Font.system(size: 32, weight: .semibold)
    static let headlineLight = Font.system(size: 32, weight: .regular)

    // MARK: 간격
    static let gutter: CGFloat = 24
    static let controlHeight: CGFloat = 56
}

// MARK: - 바탕

/// 흐릿하게 번진 사진 같은 바탕. 위는 청록, 오른쪽 가운데는 살구빛, 아래로 갈수록 어둡다.
struct BlurredPhotoBackground: View {
    /// 그라데이션의 진하기. 사진을 보는 화면에서는 낮춰서 바탕이 거의 어둡게 보이도록
    var strength: Double = 1

    var body: some View {
        ZStack {
            Theme.ink
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.42], [0.58, 0.38], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Theme.harbor, Theme.harbor, Color(red: 0.27, green: 0.42, blue: 0.51),
                    Color(red: 0.42, green: 0.36, blue: 0.33), Theme.peach, Theme.clay,
                    Theme.ink, Theme.ink, Theme.ink,
                ]
            )
            .opacity(strength)
            // 아래쪽을 가라앉혀 글자와 버튼이 또렷하게
            LinearGradient(
                stops: [.init(color: .clear, location: 0.4), .init(color: Theme.ink.opacity(0.9), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - 유리 알약

/// 알약 모양 유리 바탕. prominent면 밝은 유리(검은 글자용), 아니면 어두운 유리(흰 글자용)
struct GlassPill: View {
    var prominent = false

    var body: some View {
        if prominent {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.68)],
                                                  startPoint: .top, endPoint: .bottom))
                }
                .overlay(Capsule().strokeBorder(Theme.glassStrokeBright, lineWidth: 1))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Theme.glassStroke, lineWidth: 1))
        }
    }
}

extension View {
    /// 글자·아이콘 뒤에 유리 알약을 깐다
    func glassPillBackground(prominent: Bool = false) -> some View {
        background { GlassPill(prominent: prominent) }
    }
}

/// 가로로 꽉 차는 알약 버튼
struct GlassPillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Theme.ink : .white)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .padding(.horizontal, 20)
            .glassPillBackground(prominent: prominent)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 아이콘 하나짜리 둥근 유리 버튼 (44pt)
struct GlassCircleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Theme.ink : .white)
            .frame(width: 44, height: 44)
            .glassPillBackground(prominent: prominent)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPillButtonStyle {
    static var glassPill: GlassPillButtonStyle { .init() }
    static func glassPill(prominent: Bool) -> GlassPillButtonStyle { .init(prominent: prominent) }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static var glassCircle: GlassCircleButtonStyle { .init() }
    static func glassCircle(prominent: Bool) -> GlassCircleButtonStyle { .init(prominent: prominent) }
}

// MARK: - 작은 부품

/// 짧은 설명을 담은 유리 알약. 누르는 것이 아니라 읽는 것
struct GlassChip: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .glassPillBackground()
    }
}

/// 양옆으로 옅어지는 선 사이에 짧은 글자
struct TextDivider: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(spacing: 14) {
            fadingLine(from: .leading)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.mist)
                .fixedSize()
            fadingLine(from: .trailing)
        }
    }

    private func fadingLine(from edge: Alignment) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: edge == .leading ? [.clear, .white.opacity(0.28)] : [.white.opacity(0.28), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }
}
