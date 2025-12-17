import Foundation
import AppKit
import CGhostty

/// Swift wrapper for ghostty_app_t - manages the ghostty application lifecycle
@MainActor
final class GhosttyApp: ObservableObject {
    /// The underlying C app pointer
    @Published private(set) var app: ghostty_app_t?

    /// Configuration for this app
    private var config: GhosttyConfig?

    /// Whether the app has been initialized
    private(set) var isInitialized = false

    /// Error message if initialization failed
    @Published private(set) var initError: String?

    /// Static flag to ensure ghostty_init is only called once
    private static var ghosttyInitialized = false

    init() {
        // CRITICAL: ghostty_init MUST be called before any other ghostty functions
        if !GhosttyApp.ghosttyInitialized {
            let result = ghostty_init(0, nil)
            if result != GHOSTTY_SUCCESS {
                initError = "Failed to initialize Ghostty runtime (error: \(result))"
                return
            }
            GhosttyApp.ghosttyInitialized = true
        }

        let newConfig = GhosttyConfig()
        newConfig.finalize()
        config = newConfig

        // Create runtime config with callbacks
        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true

        // Set callbacks
        runtimeConfig.wakeup_cb = { userdata in
            GhosttyApp.wakeup(userdata)
        }

        runtimeConfig.action_cb = { app, target, action in
            return GhosttyApp.handleAction(app, target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            GhosttyApp.readClipboard(userdata, location: location, state: state)
        }

        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, request in
            GhosttyApp.confirmReadClipboard(userdata, content: content, state: state, request: request)
        }

        runtimeConfig.write_clipboard_cb = { userdata, location, content, len, confirm in
            GhosttyApp.writeClipboard(userdata, location: location, content: content, len: len, confirm: confirm)
        }

        runtimeConfig.close_surface_cb = { userdata, processAlive in
            GhosttyApp.closeSurface(userdata, processAlive: processAlive)
        }

        // Create the app
        app = ghostty_app_new(&runtimeConfig, newConfig.config)

        if app != nil {
            isInitialized = true
            // Set initial focus state
            ghostty_app_set_focus(app, NSApp.isActive)
        } else {
            initError = "Failed to initialize Ghostty"
        }
    }

    // Note: Memory management is handled by the owner
    // The app pointer should be freed when this object is deallocated
    // Since we're @MainActor, ensure cleanup happens properly
    func cleanup() {
        if let appPtr = app {
            ghostty_app_free(appPtr)
            app = nil
        }
    }

    /// Process pending ghostty events
    func tick() {
        guard let app = app else { return }
        ghostty_app_tick(app)
    }

    /// Set application focus state
    func setFocus(_ focused: Bool) {
        guard let app = app else { return }
        ghostty_app_set_focus(app, focused)
    }

    /// Update color scheme
    func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let app = app else { return }
        ghostty_app_set_color_scheme(app, scheme)
    }

    // MARK: - Callbacks

    /// Wakeup callback - schedule tick on main thread
    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata = userdata else { return }
        let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()

        DispatchQueue.main.async {
            app.tick()
        }
    }

    /// Action callback - handle actions from ghostty
    private static func handleAction(
        _ appPtr: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // For now, handle minimal actions
        // Full implementation would handle all action types

        switch action.tag {
        case GHOSTTY_ACTION_QUIT_TIMER:
            // User requested quit
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            // Change cursor shape
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            // Terminal title changed
            return true

        case GHOSTTY_ACTION_RING_BELL:
            // Bell ring - could play sound
            NSSound.beep()
            return true

        default:
            // Unhandled action
            return false
        }
    }

    /// Read clipboard callback
    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        let pasteboard = NSPasteboard.general
        let content = pasteboard.string(forType: .string)

        // Complete the request
        if let content = content, let state = state {
            content.withCString { cstr in
                ghostty_surface_complete_clipboard_request(nil, cstr, state, true)
            }
        } else if let state = state {
            ghostty_surface_complete_clipboard_request(nil, nil, state, false)
        }
    }

    /// Confirm clipboard read callback
    private static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        content: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        // For now, auto-confirm all clipboard reads
        if let state = state {
            ghostty_surface_complete_clipboard_request(nil, content, state, true)
        }
    }

    /// Write clipboard callback
    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content = content, len > 0 else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write the first content item
        if let data = content.pointee.data {
            let str = String(cString: data)
            pasteboard.setString(str, forType: .string)
        }
    }

    /// Close surface callback
    private static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        // Post notification for surface close
        NotificationCenter.default.post(
            name: .ghosttyCloseSurface,
            object: nil,
            userInfo: ["processAlive": processAlive]
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let ghosttyCloseSurface = Notification.Name("ghosttyCloseSurface")
}
