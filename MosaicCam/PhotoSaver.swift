import Photos
import SwiftUI
import UIKit

enum PhotoSaver {
    enum SaveError: LocalizedError {
        case encode
        case denied

        var errorDescription: String? {
            switch self {
            case .encode: "사진을 만들지 못했어요."
            case .denied: "설정에서 사진 추가 권한을 허용해 주세요."
            }
        }
    }

    /// JPEG로 굽는다. CGImage에서 새로 만들어 촬영 위치 등 메타데이터는 들어가지 않는다.
    static func jpeg(_ image: CGImage) throws -> Data {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.92) else { throw SaveError.encode }
        return data
    }

    static func saveToPhotos(_ jpeg: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil)
        }
    }

    /// 공유 시트에 넘길 임시 파일
    static func temporaryFile(_ jpeg: Data) throws -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mosaic-\(stamp).jpg")
        try jpeg.write(to: url, options: .atomic)
        return url
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
