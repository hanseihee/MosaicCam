import SwiftUI

/// 광고 제거 구매 화면 (아래에서 올라오는 시트)
struct RemoveAdsView: View {
    @Environment(\.dismiss) private var dismiss
    private let purchases = Purchases.shared

    var body: some View {
        ZStack {
            BlurredPhotoBackground(strength: 0.8)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("닫기", systemImage: "xmark") { dismiss() }
                        .buttonStyle(.glassCircle)
                }

                VStack(spacing: 14) {
                    Text("**광고 없이**\n바로 저장하기")
                        .font(Theme.headlineLight)
                        .foregroundStyle(.white)
                    Text("저장할 때 나오는 광고를 없애요.\n한 번 사면 이 Apple 계정으로 계속 쓸 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(Theme.mist)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 36)

                VStack(spacing: 12) {
                    if purchases.adsRemoved {
                        GlassChip("광고 없이 쓰고 있어요", systemImage: "checkmark.seal.fill")
                    } else if let product = purchases.product {
                        Button {
                            Task { if await purchases.purchase() { dismiss() } }
                        } label: {
                            Text("\(product.displayPrice)에 광고 제거")
                        }
                        .buttonStyle(.glassPill(prominent: true))
                        .disabled(purchases.busy)

                        Button("전에 샀어요 (구매 복원)") {
                            Task { await purchases.restore() }
                        }
                        .buttonStyle(.glassPill)
                        .disabled(purchases.busy)
                    } else {
                        // 상품을 아직 못 받았거나 받다가 실패한 상태
                        Button {
                            Task { await purchases.loadProduct() }
                        } label: {
                            if purchases.loadingProduct {
                                Text("상품을 불러오는 중…")
                            } else {
                                Text("상품 다시 불러오기")
                            }
                        }
                        .buttonStyle(.glassPill(prominent: true))
                        .disabled(purchases.loadingProduct)
                    }
                }
                .padding(.top, 36)

                Spacer(minLength: 20)

                Group {
                    if purchases.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("App Store와 이야기하는 중…")
                        }
                        .foregroundStyle(Theme.mist)
                    } else if let message = purchases.message {
                        Text(message).foregroundStyle(purchases.adsRemoved ? Theme.mist : Theme.ember)
                    } else {
                        Text("값은 App Store에서 정해져요.").foregroundStyle(Theme.mist)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(minHeight: 24)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
        }
        .preferredColorScheme(.dark)
        .task {
            // 앱 시작 때 못 받았으면(인터넷 없음 등) 열 때 다시 받는다
            if purchases.product == nil { await purchases.loadProduct() }
        }
    }
}
