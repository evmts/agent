import SwiftUI
import AppKit

/// CodeEditorView — minimal NSViewRepresentable wrapping an NSTextView.
///
/// Placeholder host for the future STTextView-based editor. It applies
/// AppTheme colors and design-system typography defaults (SF Mono 13pt,
/// line height 1.4) and synchronizes text via a binding.
struct CodeEditorView: NSViewRepresentable {
    // MARK: Model
    @Binding var text: String
    @Environment(\.theme) private var theme

    // MARK: Defaults (exposed for tests)
    static let defaultFontSize: CGFloat = DS.Typography.base // 13
    static let lineHeightMultiplier: CGFloat = DS.Typography.lineHeightCode // 1.4
    static let defaultFont: NSFont = .monospacedSystemFont(ofSize: defaultFontSize, weight: .regular)

    // Allow callers to override; default to SF Mono per tokens
    var font: NSFont = CodeEditorView.defaultFont

    // MARK: Coordinator
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: NSViewRepresentable
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        // Configure text view appearance
        tv.isRichText = false
        tv.font = font
        tv.backgroundColor = theme.background
        tv.textColor = theme.foreground
        tv.string = text
        tv.delegate = context.coordinator
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false

        // Paragraph style for line height
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Self.lineHeightMultiplier
        tv.defaultParagraphStyle = paragraph

        // Selection attributes
        tv.selectedTextAttributes = [
            .backgroundColor: theme.selectionBackground,
            .foregroundColor: theme.foreground,
        ]

        // Scroll view setup
        scroll.backgroundColor = theme.background
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        tv.textContainerInset = NSSize(width: DS.Space._12, height: DS.Space._12)

        // Accessibility for UI tests (reserved)
        scroll.setAccessibilityIdentifier("code_editor")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }

        // Update coordinator parent to keep references fresh
        context.coordinator.parent = self

        // Sync external text changes without disturbing selection unnecessarily
        if tv.string != text { tv.string = text }

        // Re-apply theme when it changes
        tv.backgroundColor = theme.background
        tv.textColor = theme.foreground
        tv.selectedTextAttributes = [
            .backgroundColor: theme.selectionBackground,
            .foregroundColor: theme.foreground,
        ]
        scroll.backgroundColor = theme.background

        // Refresh font if overridden
        if tv.font != font { tv.font = font }
    }
}

