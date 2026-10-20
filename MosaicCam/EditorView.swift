import MosaicCore
import SwiftUI

/// 화면 안에 비율 맞춰 놓인 사진과 좌표 변환
struct FitLayout {
    let frame: CGRect      // 화면에서 사진이 차지하는 영역
    let scale: CGFloat     // 화면 pt / 사진 픽셀

    init(image: CGSize, in container: CGSize) {
        scale = min(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        frame = CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                       width: size.width, height: size.height)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(x: frame.minX + r.minX * scale, y: frame.minY + r.minY * scale,
               width: r.width * scale, height: r.height * scale)
    }

    func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - frame.minX) / scale, y: (p.y - frame.minY) / scale)
    }

    func toImage(_ r: CGRect) -> CGRect {
        let a = toImage(r.origin)
        return CGRect(x: a.x, y: a.y, width: r.width / scale, height: r.height / scale)
    }
}

struct EditorView: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var drawing = false
    @State private var dragRect: CGRect?
    @State private var showBoxes = true
    @State private var busy = false
    @State private var toast: String?
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let fit = FitLayout(image: model.imageSize, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(decorative: model.preview, scale: 1)
                        .resizable()
                        .frame(width: fit.frame.width, height: fit.frame.height)
                        .offset(x: fit.frame.minX, y: fit.frame.minY)
                    // 탭·끌기를 받는 층. 상자를 감싸면 상자들의 접근성 영역이 이 층 전체로 합쳐져서 따로 둔다
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { point in tap(point, fit) }
                        .gesture(drawGesture(fit), including: drawing ? .all : .subviews)
                        .accessibilityHidden(true)
                    if showBoxes {
                        boxes(fit)
                    }
                    if let dragRect {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(width: dragRect.width, height: dragRect.height)
                            .offset(x: dragRect.minX, y: dragRect.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .ignoresSafeArea(edges: .horizontal)
            .safeAreaInset(edge: .top, spacing: 0) { status }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .overlay(alignment: .bottom) { toastView }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .task { await model.detect() }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 상자

    private func boxes(_ fit: FitLayout) -> some View {
        ForEach(model.regions) { region in
            let r = fit.toView(region.rect)
            // 아주 작은 얼굴도 보이도록 최소 10pt
            let w = max(r.width, 10), h = max(r.height, 10)
            // 접근성 영역이 상자 크기가 되도록 위치 지정보다 먼저 붙인다
            RegionBox(kind: region.kind, masked: model.isMasked(region))
                .frame(width: w, height: h)
                .accessibilityElement()
                .accessibilityLabel(RegionBox.name(region.kind))
                .accessibilityValue(model.isMasked(region) ? "가림" : "안 가림")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.toggle(region) }
                .position(x: r.midX, y: r.midY)
        }
        .allowsHitTesting(false)
    }

    private func tap(_ point: CGPoint, _ fit: FitLayout) {
        guard model.phase != .detecting, fit.frame.contains(point) else { return }
        // 손끝 크기(36pt)만큼은 빗나가도 잡히게
        if let region = model.region(at: fit.toImage(point), minSide: 36 / fit.scale) {
            model.toggle(region)
        }
    }

    private func drawGesture(_ fit: FitLayout) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragRect = CGRect(from: value.startLocation, to: value.location).intersection(fit.frame)
            }
            .onEnded { value in
                let rect = CGRect(from: value.startLocation, to: value.location).intersection(fit.frame)
                dragRect = nil
                guard rect.width > 8, rect.height > 8 else { return }
                model.addManual(fit.toImage(rect))
            }
    }

    // MARK: - 위아래 막대

    private var status: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .detecting:
                ProgressView().controlSize(.small)
                Text("번호판과 얼굴을 찾는 중…")
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("찾지 못했어요: \(reason)").lineLimit(2)
            case .ready where drawing:
                Image(systemName: "hand.draw").foregroundStyle(Color.accentColor)
                Text("끌어서 가릴 곳을 그리세요")
            case .ready where model.regions.isEmpty:
                Text("찾은 곳이 없어요. 직접 그려서 가릴 수 있어요.")
            case .ready:
                summary
                Text("· 탭해서 가리기").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.vertical, 8)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            if model.plateCount > 0 {
                Label("번호판 \(model.plateCount)", systemImage: "car.fill").foregroundStyle(RegionBox.color(.plate))
            }
            if model.faceCount > 0 {
                Label("얼굴 \(model.faceCount)", systemImage: "person.fill").foregroundStyle(RegionBox.color(.face))
            }
            if model.plateCount + model.faceCount == 0 {
                Label("직접 그린 곳 \(model.regions.count)", systemImage: "hand.draw")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var bottomBar: some View {
        HStack {
            BarButton(title: "되돌리기", systemImage: "arrow.uturn.backward") {
                model.undo()
            }
            .disabled(!model.canUndo)

            BarButton(title: model.allMasked ? "모두 풀기" : "모두 가리기",
                      systemImage: model.allMasked ? "square.dashed" : "square.grid.3x3.fill") {
                model.toggleAll()
            }
            .disabled(model.regions.isEmpty)

            BarButton(title: "직접 그리기", systemImage: "hand.draw", active: drawing) {
                drawing.toggle()
            }
        }
        .disabled(model.phase == .detecting || busy)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("닫기", systemImage: "xmark") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(showBoxes ? "상자 숨기기" : "상자 보기", systemImage: showBoxes ? "eye" : "eye.slash") {
                showBoxes.toggle()
            }
            Button("공유", systemImage: "square.and.arrow.up") { share() }
                .disabled(busy)
            Button("저장") { Task { await save() } }
                .fontWeight(.semibold)
                .disabled(busy)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 96)
                .transition(.opacity)
        }
    }

    // MARK: - 저장·공유

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            guard let image = model.renderFull() else { throw PhotoSaver.SaveError.encode }
            let jpeg = try PhotoSaver.jpeg(image)
            try await PhotoSaver.saveToPhotos(jpeg)
            #if DEBUG
            debugLog("저장 완료 \(image.width)×\(image.height) · \(jpeg.count / 1024)KB")
            #endif
            show("사진 앱에 저장했어요")
        } catch {
            #if DEBUG
            debugLog("저장 실패 \(error)")
            #endif
            show(error.localizedDescription)
        }
    }

    private func share() {
        busy = true
        defer { busy = false }
        do {
            guard let image = model.renderFull() else { throw PhotoSaver.SaveError.encode }
            shareItem = ShareItem(url: try PhotoSaver.temporaryFile(try PhotoSaver.jpeg(image)))
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

/// 찾은 영역 표시: 가리기 전엔 점선, 가린 뒤엔 얇은 실선
struct RegionBox: View {
    let kind: Region.Kind
    let masked: Bool

    static func name(_ kind: Region.Kind) -> String {
        switch kind {
        case .plate: "번호판"
        case .face: "얼굴"
        case .manual: "직접 그린 곳"
        }
    }

    static func color(_ kind: Region.Kind) -> Color {
        switch kind {
        case .plate: Color(red: 1, green: 0.84, blue: 0.04)
        case .face: Color(red: 0.35, green: 0.82, blue: 1)
        case .manual: .white
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        let color = Self.color(kind)
        if masked {
            shape.stroke(color.opacity(0.9), lineWidth: 1.5)
        } else {
            shape.fill(color.opacity(0.14))
                .overlay(shape.stroke(color, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
        }
    }
}

private struct BarButton: View {
    let title: String
    let systemImage: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(height: 24)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(active ? Color.black : Color.primary)
            .background(active ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
