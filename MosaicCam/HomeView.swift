import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var editor: EditorModel?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var captured: UIImage?
    @State private var loading = false
    @State private var message: String?
    @State private var showRemoveAds = false
    private let purchases = Purchases.shared

    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        ZStack {
            BlurredPhotoBackground()

            VStack(spacing: 0) {
                Text(verbatim: "Mosaic")
                    .font(Theme.wordmark)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 12)

                VStack(spacing: 14) {
                    // 굵은 줄은 번역문 안의 마크다운(**…**)으로 정한다
                    Text("**번호판과 얼굴을**\n찾아서 가려 드려요")
                        .font(Theme.headlineLight)
                        .foregroundStyle(.white)
                    Text("가릴 곳을 탭하면 모자이크돼요")
                        .font(.callout)
                        .foregroundStyle(Theme.mist)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 44)

                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("사진 찍기", systemImage: "camera.fill")
                    }
                    .buttonStyle(.glassPill(prominent: true))
                    .disabled(!cameraAvailable)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("앨범에서 고르기", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.glassPill)

                    TextDivider("이 기기 안에서만")
                        .padding(.vertical, 10)

                    HStack(spacing: 12) {
                        GlassChip("서버로 안 보내요", systemImage: "lock.fill")
                        GlassChip("원본은 그대로예요", systemImage: "photo.badge.checkmark")
                    }
                }
                .padding(.top, 40)

                Spacer(minLength: 24)

                footer
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 24)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, Theme.gutter)
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
        .sheet(isPresented: $showRemoveAds) {
            RemoveAdsView()
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

    /// 맨 아래 한 줄: 여는 중 / 오류 / 안내
    @ViewBuilder
    private var footer: some View {
        if loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("사진을 여는 중…")
            }
            .foregroundStyle(Theme.mist)
        } else if let message {
            Text(message).foregroundStyle(Theme.ember)
        } else if !cameraAvailable {
            Text("이 기기에는 카메라가 없어요").foregroundStyle(Theme.mist)
        } else if purchases.adsRemoved {
            Text("광고 없이 쓰고 있어요").foregroundStyle(Theme.mist)
        } else {
            HStack(spacing: 6) {
                Text("저장할 때 광고가 나와요").foregroundStyle(Theme.mist)
                Button("광고 없이 쓰기") { showRemoveAds = true }
                    .foregroundStyle(Theme.ember)
                    .fontWeight(.medium)
            }
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
                message = String(localized: "사진을 열지 못했어요.")
                return
            }
            open(image)
        } catch {
            message = String(localized: "사진을 열지 못했어요: \(error.localizedDescription)")
        }
    }

    private func open(_ image: UIImage) {
        guard let cg = image.normalizedCGImage() else {
            message = String(localized: "사진을 열지 못했어요.")
            return
        }
        #if DEBUG
        debugLog("사진 열기 \(Int(image.size.width))×\(Int(image.size.height))pt ×\(image.scale) 방향 \(image.imageOrientation.rawValue) → \(cg.width)×\(cg.height)")
        #endif
        editor = EditorModel(image: cg)
    }
}
