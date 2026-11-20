import MarkdownEngine
import SwiftUI

public struct DiaryEditorSurface: View {
    @Binding private var text: String
    private let documentID: String
    private let showsSource: Bool
    private let isEditable: Bool

    public init(text: Binding<String>, documentID: String, showsSource: Bool = false, isEditable: Bool = true)
    {
        _text = text
        self.documentID = documentID
        self.showsSource = showsSource
        self.isEditable = isEditable
    }

    public var body: some View {
        ClearingEditorHost(
            content: AnyView(
                NativeTextViewWrapper(
                    text: $text,
                    configuration: configuration,
                    fontName: "PingFangSC-Regular", fontSize: 16,
                    documentId: documentID, parkingKey: nil, isEditable: isEditable
                ).background(UndoBindingBridge().frame(width: 0, height: 0)))
        )
        .id(documentID).id(showsSource)
    }

    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration()
        config.rawSourceMode = showsSource
        config.spellChecking = SpellCheckingPolicy(
            continuousSpellChecking: false, grammarChecking: false,
            automaticSpellingCorrection: false, automaticQuoteSubstitution: false)
        config.overscroll.percent = 0.35
        config.theme.link = .systemGreen
        return config
    }
}
