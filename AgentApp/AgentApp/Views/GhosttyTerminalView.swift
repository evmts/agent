import AppKit
import SwiftUI
import CGhostty

// MARK: - Ghostty Modifier Conversion

/// Translate NSEvent modifier flags to ghostty mods enum
func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

    // Handle sided input
    let rawFlags = flags.rawValue
    if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

    return ghostty_input_mods_e(mods)
}

// MARK: - GhosttyNSView

/// NSView subclass that hosts a ghostty terminal surface
class GhosttyNSView: NSView, NSTextInputClient {
    /// The ghostty app instance
    private var ghosttyApp: GhosttyApp?

    /// The surface model
    private var surfaceModel: GhosttySurface?

    /// Surface pointer (convenience)
    private var surface: ghostty_surface_t? { surfaceModel?.surface }

    /// Whether the view has focus
    private var focused: Bool = false

    /// Accumulated text during key event handling
    private var keyTextAccumulator: [String]?

    /// Marked text for IME composition
    private var markedText: NSMutableAttributedString = NSMutableAttributedString()

    /// Selected range for text input
    private var _selectedRange: NSRange = NSRange(location: 0, length: 0)

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 22/255, green: 22/255, blue: 28/255, alpha: 1.0).cgColor

        // Set up tracking area for mouse events
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - Surface Management

    func createSurface(app: GhosttyApp, workingDirectory: String? = nil, command: String? = nil) {
        self.ghosttyApp = app

        var config = GhosttySurfaceConfiguration()
        config.workingDirectory = workingDirectory ?? FileManager.default.currentDirectoryPath
        // Use $SHELL from environment, fallback to /bin/zsh
        config.command = command ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        surfaceModel = GhosttySurface(app: app, view: self, config: config)

        // Set initial size
        if let window = window {
            let scaledSize = convertToBacking(bounds.size)
            surfaceModel?.setSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
            surfaceModel?.setContentScale(x: window.backingScaleFactor, y: window.backingScaleFactor)
        }
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window = window else { return }

        // Set display ID for vsync
        if let screen = window.screen {
            surfaceModel?.setDisplayId(screen.displayID)
        }

        // Update content scale
        surfaceModel?.setContentScale(x: window.backingScaleFactor, y: window.backingScaleFactor)

        // Become first responder
        window.makeFirstResponder(self)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        guard let window = window else { return }
        surfaceModel?.setContentScale(x: window.backingScaleFactor, y: window.backingScaleFactor)

        // Re-set size in backing coordinates
        let scaledSize = convertToBacking(bounds.size)
        surfaceModel?.setSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        let scaledSize = convertToBacking(newSize)
        surfaceModel?.setSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            focused = true
            surfaceModel?.setFocus(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            focused = false
            surfaceModel?.setFocus(false)
        }
        return result
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            super.keyDown(with: event)
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Check if this is a "text" key that should go through IME
        // Control keys, function keys, and keys with no printable characters skip IME
        let shouldUseIME = isTextInputKey(event)

        if shouldUseIME {
            // Begin accumulating text
            keyTextAccumulator = []
            defer { keyTextAccumulator = nil }

            // Let AppKit process for IME support
            interpretKeyEvents([event])

            if let accumulator = keyTextAccumulator, !accumulator.isEmpty {
                // We have composed text from IME
                for text in accumulator {
                    sendKeyEvent(action: action, event: event, text: text)
                }
                return
            }
        }

        // Send key event directly (for control keys or if IME didn't produce text)
        sendKeyEvent(action: action, event: event, text: event.characters)
    }

    /// Determines if a key event should be processed through the IME system
    private func isTextInputKey(_ event: NSEvent) -> Bool {
        // If any of these modifiers are pressed (except shift), it's not a text input key
        let controlMods: NSEvent.ModifierFlags = [.control, .command]
        if !event.modifierFlags.intersection(controlMods).isEmpty {
            return false
        }

        // Check the characters - if empty, not a text key
        guard let chars = event.characters, !chars.isEmpty else {
            return false
        }

        // Check for special characters (function keys, arrows, etc.)
        // These are in the Unicode Private Use Area (PUA)
        if let scalar = chars.unicodeScalars.first {
            // PUA range used by macOS for function keys
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return false
            }
            // Control characters (except tab, which can be text in some contexts)
            if scalar.value < 0x20 && scalar.value != 0x09 {
                return false
            }
        }

        return true
    }

    override func keyUp(with event: NSEvent) {
        sendKeyEvent(action: GHOSTTY_ACTION_RELEASE, event: event, text: nil)
    }

    private func sendKeyEvent(action: ghostty_input_action_e, event: NSEvent, text: String?) {
        guard let surface = surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        // Use raw macOS keycode - ghostty handles the translation internally
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = ghosttyMods(event.modifierFlags)
        // Control and command never contribute to text translation
        keyEvent.consumed_mods = ghosttyMods(event.modifierFlags.subtracting([.control, .command]))
        keyEvent.composing = false

        // Get the unshifted codepoint (character with no modifiers)
        keyEvent.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEvent.unshifted_codepoint = codepoint.value
            }
        }

        // Get text for this key event
        let ghosttyText = getGhosttyCharacters(from: event)

        // Set text for printable characters
        if let text = ghosttyText, !text.isEmpty, action != GHOSTTY_ACTION_RELEASE {
            text.withCString { cstr in
                keyEvent.text = cstr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Returns the text to set for a key event for Ghostty.
    /// Contains logic to avoid control characters, since ghostty handles control character mapping internally.
    private func getGhosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // If we have a single control character, return characters without control pressed
            // Ghostty handles control character encoding internally
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }

            // If we have a single value in the PUA (Private Use Area), it's a function key
            // Don't send PUA ranges to Ghostty
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes if needed
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface = surface else { return }

        // Request focus
        window?.makeFirstResponder(self)

        let pos = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, mods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface = surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, bounds.height - pos.y, ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }

        // Build scroll mods
        let scrollMods = GhosttyScrollMods.from(event: event)

        // Apply multiplier for precision scrolling
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 2.0
        let deltaX = event.scrollingDeltaX * multiplier
        let deltaY = event.scrollingDeltaY * multiplier

        ghostty_surface_mouse_scroll(surface, deltaX, deltaY, scrollMods)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }

        // Clear marked text
        markedText = NSMutableAttributedString()

        // Accumulate the text if we're in a keyDown
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else {
            // Direct text input (e.g., paste)
            surfaceModel?.sendText(text)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: NSAttributedString
        if let str = string as? String {
            text = NSAttributedString(string: str)
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr
        } else {
            return
        }

        markedText = NSMutableAttributedString(attributedString: text)
        self._selectedRange = selectedRange

        // Send preedit to ghostty
        if text.length > 0 {
            surfaceModel?.sendPreedit(text.string)
        } else {
            surfaceModel?.sendPreedit(nil)
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        surfaceModel?.sendPreedit(nil)
    }

    func selectedRange() -> NSRange {
        return _selectedRange
    }

    func markedRange() -> NSRange {
        if markedText.length > 0 {
            return NSRange(location: 0, length: markedText.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        return markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Return cursor position for IME window placement
        guard let surface = surface else { return .zero }

        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let viewRect = NSRect(x: x, y: bounds.height - y - height, width: width, height: height)
        return window?.convertToScreen(convert(viewRect, to: nil)) ?? viewRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }

    // MARK: - Cleanup

    func cleanup() {
        surfaceModel = nil
        ghosttyApp?.cleanup()
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    var displayID: UInt32 {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return screenNumber.uint32Value
    }
}

// MARK: - GhosttyTerminalRepresentable

struct GhosttyTerminalRepresentable: NSViewRepresentable {
    @ObservedObject var ghosttyApp: GhosttyApp
    var workingDirectory: String?
    var command: String?

    func makeNSView(context: Context) -> GhosttyNSView {
        let view = GhosttyNSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: GhosttyNSView, context: Context) {
        // Create surface if app is initialized and surface doesn't exist
        if ghosttyApp.isInitialized {
            nsView.createSurface(
                app: ghosttyApp,
                workingDirectory: workingDirectory,
                command: command
            )
        }
    }

    static func dismantleNSView(_ nsView: GhosttyNSView, coordinator: ()) {
        nsView.cleanup()
    }
}

// MARK: - GhosttyTerminalView

/// SwiftUI view that displays a Ghostty terminal
struct GhosttyTerminalView: View {
    @StateObject private var ghosttyApp = GhosttyApp()

    var workingDirectory: String?
    var command: String?

    var body: some View {
        ZStack {
            if ghosttyApp.isInitialized {
                GhosttyTerminalRepresentable(
                    ghosttyApp: ghosttyApp,
                    workingDirectory: workingDirectory,
                    command: command
                )
            } else if let error = ghosttyApp.initError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Terminal Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: NSColor(red: 22/255, green: 22/255, blue: 28/255, alpha: 1.0)))
            } else {
                ProgressView("Initializing terminal...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: NSColor(red: 22/255, green: 22/255, blue: 28/255, alpha: 1.0)))
            }
        }
        .onAppear {
            ghosttyApp.setFocus(true)
        }
        .onDisappear {
            ghosttyApp.cleanup()
        }
    }
}
