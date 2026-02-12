import Testing
import AppKit
@testable import Smithers

@Suite @MainActor struct CodeEditorViewTests {
    @Test func instantiateEditor_viewTypeExists() {
        var sample = "let x = 1\nprint(x)"
        let view = CodeEditorView(text: .init(get: { sample }, set: { sample = $0 }))
        #expect(String(describing: type(of: view)) == "CodeEditorView")
    }

    @Test func defaultFontSize_matchesDesignToken() {
        #expect(CodeEditorView.defaultFontSize == DS.Typography.base)
        #expect(DS.Typography.base == 13)
    }

    @Test func defaultFont_isMonospaced() {
        let f = CodeEditorView.defaultFont
        // System monospace fonts have fixed advancement; lightweight check
        #expect(f.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @Test func lineHeightMultiplier_matchesCodeToken() {
        #expect(CodeEditorView.lineHeightMultiplier == DS.Typography.lineHeightCode)
        #expect(DS.Typography.lineHeightCode == 1.4)
    }
}

