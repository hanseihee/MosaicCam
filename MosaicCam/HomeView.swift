import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var editor: EditorModel?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var loading = false
    @State private var message: String?

    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                MosaicGlyph()
                    .frame(width: 96, height: 96)
                Text("모자이크")
                    .font(.largeTitle.bold())
                Text("사진 속 번호판과 얼굴을 찾아 드려요.\n가릴 곳을 탭하면 모자이크돼요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("사진 찍기", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .disabled(!cameraAvailable)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("앨범에서 고르기", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)

                Group {
                    if loading {
                        ProgressView()
                    } else if let message {
                        Text(message).foregroundStyle(.orange)
                    } else {
                        Text(cameraAvailable ? "사진은 이 기기 안에서만 처리돼요." : "이 기기에는 카메라가 없어요.")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.footnote)
                .frame(height: 24)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: openCaptured) {
            CameraPicker { image in
                captured = image
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editor) { model in
            EditorView(model: model)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .task {
            #if DEBUG
            // 확인용: 절대 경로(시뮬레이터) 또는 앱 Documents 기준 상대 경로(실기기)
            if let path = ProcessInfo.processInfo.environment["MOSAIC_DEMO_IMAGE"] {
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
                if let image = UIImage(contentsOfFile: url.path) {
                    open(image)
                } else {
                    debugLog("사진 없음: \(url.path)")
                }
            }
            #endif
        }
    }

    private func openCaptured() {
        guard let image = captured else { return }
        captured = nil
        open(image)
    }

    private func load(_ item: PhotosPickerItem) async {
        loading = true
        message = nil
        defer {
            loading = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                message = "사진을 열지 못했어요."
                return
            }
            open(image)
        } catch {
            message = "사진을 열지 못했어요: \(error.localizedDescription)"
        }
    }

    private func open(_ image: UIImage) {
        guard let cg = image.normalizedCGImage() else {
            message = "사진을 열지 못했어요."
            return
        }
        #if DEBUG
        debugLog("사진 열기 \(Int(image.size.width))×\(Int(image.size.height))pt ×\(image.scale) 방향 \(image.imageOrientation.rawValue) → \(cg.width)×\(cg.height)")
        #endif
        editor = EditorModel(image: cg)
    }
}

/// 앱 상징: 모자이크 칸 위에 인식 상자 모서리
struct MosaicGlyph: View {
    private let shades: [Double] = [0.55, 0.35, 0.7, 0.45, 0.3, 0.6, 0.4, 0.75, 0.5]

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let cell = side * 0.6 / 3
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { col in
                                Rectangle().fill(Color.accentColor.opacity(shades[row * 3 + col]))
                            }
                        }
                    }
                }
                .frame(width: cell * 3, height: cell * 3)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.06))
                CornerBrackets()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))
                    .padding(side * 0.06)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let l = rect.width * 0.22
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
