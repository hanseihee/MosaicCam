// 앱 아이콘을 그려 PNG(1024×1024, 알파 없음)로 저장한다.
// 사용: swift Tools/render-icon.swift [저장할 경로]
// 기본 저장 위치: MosaicCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let side: CGFloat = 1024

// 앱의 Theme와 같은 색
let ink = Color(red: 0.059, green: 0.055, blue: 0.055)
let harbor = Color(red: 0.16, green: 0.30, blue: 0.39)
let clay = Color(red: 0.541, green: 0.376, blue: 0.314)
let peach = Color(red: 0.851, green: 0.659, blue: 0.573)

/// 흐릿한 사진 같은 바탕 위에 유리 질감 모자이크 칸과 인식 상자 모서리
struct IconView: View {
    private let shades: [Double] = [0.84, 0.38, 0.93, 0.50, 0.26, 0.68, 0.42, 0.88, 0.58]

    var body: some View {
        ZStack {
            ink
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45], [0.62, 0.40], [1, 0.55],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    harbor, harbor, Color(red: 0.27, green: 0.42, blue: 0.51),
                    Color(red: 0.42, green: 0.36, blue: 0.33), peach, clay,
                    ink, ink, ink,
                ]
            )
            LinearGradient(
                stops: [.init(color: .clear, location: 0.35), .init(color: ink.opacity(0.75), location: 1)],
                startPoint: .top, endPoint: .bottom
            )

            let cell = side * 0.54 / 3
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { col in
                            Rectangle().fill(.white.opacity(shades[row * 3 + col]))
                        }
                    }
                }
            }
            .frame(width: cell * 3, height: cell * 3)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.09, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: side * 0.006)
            }
            .shadow(color: .black.opacity(0.35), radius: side * 0.05, y: side * 0.03)

            CornerBrackets()
                .stroke(.white.opacity(0.96), style: StrokeStyle(lineWidth: side * 0.042, lineCap: .round, lineJoin: .round))
                .padding(side * 0.155)
                .shadow(color: .black.opacity(0.25), radius: side * 0.02, y: side * 0.01)
        }
        .frame(width: side, height: side)
    }
}

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let l = rect.width * 0.2
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x + l * dx, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + l * dy))
        }
        return p
    }
}

MainActor.assumeIsolated {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        ?? repoRoot.appending(path: "MosaicCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    renderer.isOpaque = true
    guard let rendered = renderer.cgImage else {
        FileHandle.standardError.write(Data("아이콘을 그리지 못했어요\n".utf8))
        exit(1)
    }

    // 앱 아이콘은 알파가 없어야 하므로 RGB 비트맵에 다시 그린다
    let px = Int(side)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
    ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let flat = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(dest, flat, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("저장 실패: \(output.path)\n".utf8))
        exit(1)
    }
    print("저장: \(output.path)")
}
