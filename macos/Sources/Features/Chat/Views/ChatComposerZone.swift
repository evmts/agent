import SwiftUI
import AppKit

// NSTextView wrapper to intercept Return vs Shift+Return
private struct KeyHandlingTextView: NSViewRepresentable {
    @Binding var text: String
    let onSend: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeyHandlingTextView
        init(_ parent: KeyHandlingTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let tv = notification.object as? NSTextView { parent.text = tv.string }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private final class HandlerTextView: NSTextView {
        var onSend: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            // 36 = kVK_Return, 76 = kVK_ANSI_KeypadEnter
            if event.keyCode == 36 || event.keyCode == 76 {
                if event.modifierFlags.contains(.shift) {
                    super.insertNewline(nil)
                } else {
                    onSend?()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        let tv = HandlerTextView()
        tv.drawsBackground = false
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.font = .systemFont(ofSize: CGFloat(DS.Typography.base))
        tv.delegate = context.coordinator
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.string = text
        tv.onSend = self.onSend
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView, tv.string != text {
            tv.string = text
        }
    }
}

struct ChatComposerZone: View {
    @State private var text: String = ""
    @Environment(\.theme) private var theme

    let onSend: (String) -> Void

    private func handleSend() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space._8) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius._10)
                    .fill(Color(nsColor: theme.inputFieldBackground))
                RoundedRectangle(cornerRadius: DS.Radius._10)
                    .stroke(Color(nsColor: DS.Color.overlayWhite06), lineWidth: 1)
                KeyHandlingTextView(text: $text, onSend: handleSend)
                    .frame(minHeight: 22, maxHeight: 100)
                    .padding(DS.Space._10)
                    .accessibilityIdentifier("composer_text")
            }
            HStack {
                Text("Return to send • Shift+Return for newline")
                    .font(.system(size: DS.Typography.xs))
                    .foregroundStyle(Color(nsColor: DS.Color.textTertiary))
                Spacer()
                Button(action: handleSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(nsColor: DS.Color.onAccentText))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius._6)
                                .fill(Color(nsColor: theme.accent))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer_send")
            }
        }
        .padding(.horizontal, DS.Space._12)
        .padding(.vertical, DS.Space._12)
    }
}
