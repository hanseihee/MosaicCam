// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosaicCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "MosaicCore", targets: ["MosaicCore"]),
    ],
    dependencies: [
        // 태그는 v1.19.2가 마지막이라 ORT 1.24.2를 담은 main 커밋으로 고정
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
                 revision: "b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2"),
    ],
    targets: [
        .target(
            name: "MosaicCore",
            dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")],
            resources: [.copy("Models")]
        ),
        .testTarget(
            name: "MosaicCoreTests",
            dependencies: ["MosaicCore"],
            resources: [.copy("Samples")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
