import SwiftUI
import AppKit

struct VimChatInputView: View {
    @StateObject private var vimTerminal = VimChatTerminal()
    @FocusState private var isTerminalFocused: Bool
    
    let onMessageSent: (String) -> Void
    var onMessageUpdated: ((String) -> Void)?
    var onNavigateUp: (() -> Void)?
    var onNavigateDown: (() -> Void)?
    var onPreviousChat: (() -> Void)?
    var onNextChat: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal display area
            VimTerminalDisplayView(vimTerminal: vimTerminal)
                .background(Color.black)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .onTapGesture {
                    print("VimChatInputView: Tap gesture - setting focus")
                    isTerminalFocused = true
                }
            
            // Status line
            statusLineView
        }
        .background(Color.black)
        .overlay(
            Rectangle()
                .stroke(isTerminalFocused ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            print("VimChatInputView: onAppear called, setting up callbacks")
            vimTerminal.onMessageSent = onMessageSent
            vimTerminal.onMessageUpdated = onMessageUpdated
            vimTerminal.onNavigateUp = onNavigateUp
            vimTerminal.onNavigateDown = onNavigateDown
            vimTerminal.onPreviousChat = onPreviousChat
            vimTerminal.onNextChat = onNextChat
            print("VimChatInputView: Callbacks set - onMessageSent: true, onMessageUpdated: \(onMessageUpdated != nil)")
            isTerminalFocused = true
        }
    }
    
    private var statusLineView: some View {
        HStack {
            Text(vimTerminal.statusLine.isEmpty ? " " : vimTerminal.statusLine)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Text(modeIndicator)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(modeColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.8))
    }
    
    private var modeIndicator: String {
        switch vimTerminal.currentMode {
        case .normal:
            return "NORMAL"
        case .insert:
            return "INSERT"
        case .command:
            return "COMMAND"
        }
    }
    
    private var modeColor: Color {
        switch vimTerminal.currentMode {
        case .normal:
            return .green
        case .insert:
            return .blue
        case .command:
            return .yellow
        }
    }
}

struct VimTerminalDisplayView: NSViewRepresentable {
    let vimTerminal: VimChatTerminal
    
    func makeNSView(context: Context) -> VimTerminalNSView {
        let view = VimTerminalNSView(vimTerminal: vimTerminal)
        print("VimTerminalDisplayView: Creating NSView")
        
        return view
    }
    
    func updateNSView(_ nsView: VimTerminalNSView, context: Context) {
        nsView.updateDisplay()
        
        // Try to ensure focus on updates
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                let success = nsView.window?.makeFirstResponder(nsView) ?? false
                if success {
                    print("VimTerminalDisplayView: Successfully made first responder")
                }
            }
        }
    }
}

class VimTerminalNSView: NSView {
    private let vimTerminal: VimChatTerminal
    private let cellWidth: CGFloat = 8.0
    private let cellHeight: CGFloat = 16.0
    private var cursorTimer: Timer?
    private var showCursor = true
    
    init(vimTerminal: VimChatTerminal) {
        self.vimTerminal = vimTerminal
        super.init(frame: .zero)
        
        setupView()
        startCursorBlink()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Force the view to be able to receive key events
        // canBecomeKeyView is read-only, override the property instead
        
        // Add a tracking area for mouse events
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    private func startCursorBlink() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.showCursor.toggle()
            self.needsDisplay = true
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override var canBecomeKeyView: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        print("VimTerminalNSView: keyDown called - characters: '\(event.characters ?? "")', keyCode: \(event.keyCode)")
        vimTerminal.handleKeyPress(event)
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        print("VimTerminalNSView: mouseDown - trying to become first responder")
        print("VimTerminalNSView: Before - first responder: \(String(describing: window?.firstResponder))")
        
        // More aggressive focus grabbing
        window?.makeFirstResponder(nil)  // Clear current responder
        let success = window?.makeFirstResponder(self) ?? false
        
        print("VimTerminalNSView: After - first responder: \(String(describing: window?.firstResponder)), success: \(success)")
        
        // Also try to make this the key view
        window?.makeKey()
        
        super.mouseDown(with: event)
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Try to grab focus when mouse enters
        window?.makeFirstResponder(self)
    }
    
    override func becomeFirstResponder() -> Bool {
        print("VimTerminalNSView: becomeFirstResponder called")
        let result = super.becomeFirstResponder()
        print("VimTerminalNSView: becomeFirstResponder result: \(result)")
        return result
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Clear background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        
        // Draw text content
        drawTextContent(in: context)
        
        // Draw cursor
        if showCursor {
            drawCursor(in: context)
        }
    }
    
    private func drawTextContent(in context: CGContext) {
        let lines = vimTerminal.getDisplayLines()
        
        for (row, line) in lines.enumerated() {
            let y = bounds.height - CGFloat(row + 1) * cellHeight
            
            for (col, char) in line.enumerated() {
                let x = CGFloat(col) * cellWidth
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.white
                ]
                
                let attributedString = NSAttributedString(string: String(char), attributes: attributes)
                attributedString.draw(at: CGPoint(x: x, y: y))
            }
        }
    }
    
    private func drawCursor(in context: CGContext) {
        let (row, col) = vimTerminal.getCursorPosition()
        let x = CGFloat(col) * cellWidth
        let y = bounds.height - CGFloat(row + 1) * cellHeight
        
        context.setFillColor(NSColor.white.cgColor)
        
        switch vimTerminal.currentMode {
        case .normal:
            // Block cursor
            context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            
            // Draw character in black if there's text
            let lines = vimTerminal.getDisplayLines()
            if row < lines.count && col < lines[row].count {
                let char = lines[row][lines[row].index(lines[row].startIndex, offsetBy: col)]
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.black
                ]
                let attributedString = NSAttributedString(string: String(char), attributes: attributes)
                attributedString.draw(at: CGPoint(x: x, y: y))
            }
            
        case .insert:
            // Line cursor
            context.fill(CGRect(x: x, y: y, width: 2, height: cellHeight))
            
        case .command:
            // Underline cursor
            context.fill(CGRect(x: x, y: y, width: cellWidth, height: 2))
        }
    }
    
    func updateDisplay() {
        needsDisplay = true
    }
    
    deinit {
        cursorTimer?.invalidate()
    }
}

#Preview {
    VimChatInputView(
        onMessageSent: { message in
            print("Preview: Message sent: \(message)")
        },
        onMessageUpdated: { message in
            print("Preview: Message updated: \(message)")
        }
    )
    .frame(width: 600, height: 200)
    .padding()
}