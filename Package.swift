// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDiary",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiaryPreview", targets: ["DiaryApp"]),
        .executable(name: "diary-probe", targets: ["DiaryProbe"]),
        .executable(name: "editor-probe", targets: ["EditorProbe"]),
    ],
    dependencies: [
        // Pin the pre-1.0 editor so upstream changes cannot alter editing behavior.
        .package(
            url: "https://github.com/nodes-app/swift-markdown-engine",
            revision: "a0c60907e6df6fa79c056ad75b47ddaa5e2dc014"
        )
    ],
    targets: [
        .target(name: "DiaryCore"),
        .target(name: "DiaryPlatform", dependencies: ["DiaryCore"]),
        .target(name: "DiaryState", dependencies: ["DiaryCore"]),
        .target(
            name: "DiaryEditing",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine")
            ]),
        .executableTarget(
            name: "DiaryApp",
            dependencies: [
                "DiaryCore",
                "DiaryPlatform",
                "DiaryState",
                "DiaryEditing",
            ]
        ),
        .executableTarget(name: "DiaryProbe", dependencies: ["DiaryCore", "DiaryPlatform"]),
        .executableTarget(name: "EditorProbe", dependencies: ["DiaryEditing"]),
        .testTarget(name: "DiaryCoreTests", dependencies: ["DiaryCore"]),
        .testTarget(name: "DiaryPlatformTests", dependencies: ["DiaryPlatform"]),
        .testTarget(name: "DiaryStateTests", dependencies: ["DiaryState"]),
    ],
    swiftLanguageModes: [.v6]
)
