# 开源依赖

## MarkdownEngine

- 来源：[nodes-app/swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)。
- 固定提交：`a0c60907e6df6fa79c056ad75b47ddaa5e2dc014`，通过 Swift Package Manager 引用；不复制或修改编辑器源码。
- 引用产品：`MarkdownEngine` 核心。未引用 `MarkdownEngineCodeBlocks` 或 `MarkdownEngineLatex`。
- 用途：AppKit / TextKit 2 原生 Markdown 行内样式编辑及 SwiftUI 桥接。
- 许可：[Apache License 2.0](https://github.com/nodes-app/swift-markdown-engine/blob/a0c60907e6df6fa79c056ad75b47ddaa5e2dc014/LICENSE)。完整 LICENSE 随构建应用放入 `Contents/Resources/MarkdownEngine-LICENSE.txt`。
- 调研提交未发现 NOTICE 文件；实际升级时重新核查许可和 NOTICE。
- 核心 target 未声明第三方 target 依赖；上游 Package 仍声明可选 LaTeX 使用的 SwiftMath，包解析结果以 `Package.resolved` 为准。解析/下载与应用实际链接的代码分别记录。
- 本轮解析到 SwiftMath 1.7.3（`fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`）；本应用未引用 LaTeX 产品。构建应用仅分发自身可执行文件、图标、许可与致谢，未包含 SwiftMath 的独立库或字体资源。

## 参考而未引入的项目

FSNotes、妙言、Textual、MarkdownUI 仅作为调研参考，本轮未复制其源码或资产。

## 系统框架

SwiftUI、AppKit、CryptoKit、CommonCrypto、Security、LocalAuthentication 和 Foundation 来自 macOS SDK。Python 和 Swift 编译器用于构建及验证，不作为应用运行时打包。
