import Foundation
import AppKit
import CGhostty

/// Configuration for creating a new surface
struct GhosttySurfaceConfiguration {
    var fontSize: Float = 0  // 0 = inherit from app config
    var workingDirectory: String?
    var command: String?
    var environmentVariables: [String: String]?
    var initialInput: String?
    var waitAfterCommand: Bool = false

    init() {}

    /// Create C config struct with proper lifetime management
    func withCValue<T>(view: NSView, scaleFactor: Double, block: (inout ghostty_surface_config_s) -> T) -> T {
        var config = ghostty_surface_config_new()

        // Platform configuration
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        var platformConfig = ghostty_platform_macos_s()
        platformConfig.nsview = Unmanaged.passUnretained(view).toOpaque()
        config.platform = ghostty_platform_u(macos: platformConfig)

        config.scale_factor = scaleFactor
        config.font_size = fontSize
        config.wait_after_command = waitAfterCommand

        // Handle strings with proper lifetime
        var result: T!

        func withOptionalCString<U>(_ string: String?, block: (UnsafePointer<CChar>?) -> U) -> U {
            if let string = string {
                return string.withCString { block($0) }
            } else {
                return block(nil)
            }
        }

        withOptionalCString(workingDirectory) { workingDir in
            withOptionalCString(command) { cmd in
                withOptionalCString(initialInput) { input in
                    config.working_directory = workingDir
                    config.command = cmd
                    config.initial_input = input
                    result = block(&config)
                }
            }
        }

        return result
    }
}

/// Swift wrapper for ghostty_surface_t
@MainActor
final class GhosttySurface {
    /// The underlying C surface pointer
    private(set) var surface: ghostty_surface_t?

    /// The app this surface belongs to
    private weak var app: GhosttyApp?

    /// User data pointer
    var userdata: UnsafeMutableRawPointer?

    init?(app: GhosttyApp, view: NSView, config: GhosttySurfaceConfiguration = GhosttySurfaceConfiguration()) {
        guard let appPtr = app.app else { return nil }
        self.app = app

        let scaleFactor = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0

        surface = config.withCValue(view: view, scaleFactor: scaleFactor) { cConfig in
            cConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
            return ghostty_surface_new(appPtr, &cConfig)
        }

        if surface == nil {
            return nil
        }
    }

    deinit {
        if let surface = surface {
            // Free on main thread to avoid threading issues
            Task { @MainActor in
                ghostty_surface_free(surface)
            }
        }
    }

    // MARK: - Surface Control

    /// Refresh the surface
    func refresh() {
        guard let surface = surface else { return }
        ghostty_surface_refresh(surface)
    }

    /// Draw the surface
    func draw() {
        guard let surface = surface else { return }
        ghostty_surface_draw(surface)
    }

    /// Set the surface size in pixels
    func setSize(width: UInt32, height: UInt32) {
        guard let surface = surface else { return }
        ghostty_surface_set_size(surface, width, height)
    }

    /// Set the content scale factor
    func setContentScale(x: Double, y: Double) {
        guard let surface = surface else { return }
        ghostty_surface_set_content_scale(surface, x, y)
    }

    /// Set focus state
    func setFocus(_ focused: Bool) {
        guard let surface = surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    /// Set occlusion state (whether the surface is visible)
    func setOcclusion(_ occluded: Bool) {
        guard let surface = surface else { return }
        ghostty_surface_set_occlusion(surface, occluded)
    }

    /// Set color scheme
    func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let surface = surface else { return }
        ghostty_surface_set_color_scheme(surface, scheme)
    }

    /// Set display ID (for vsync on macOS)
    func setDisplayId(_ displayId: UInt32) {
        guard let surface = surface else { return }
        ghostty_surface_set_display_id(surface, displayId)
    }

    // MARK: - Input Handling

    /// Send a key event
    func sendKey(_ event: ghostty_input_key_s) -> Bool {
        guard let surface = surface else { return false }
        var key = event
        return ghostty_surface_key(surface, key)
    }

    /// Send text input
    func sendText(_ text: String) {
        guard let surface = surface else { return }
        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(text.utf8.count))
        }
    }

    /// Send preedit text (for IME composition)
    func sendPreedit(_ text: String?) {
        guard let surface = surface else { return }
        if let text = text {
            text.withCString { cstr in
                ghostty_surface_preedit(surface, cstr, UInt(text.utf8.count))
            }
        } else {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    /// Send mouse button event
    func sendMouseButton(state: ghostty_input_mouse_state_e, button: ghostty_input_mouse_button_e, mods: ghostty_input_mods_e) -> Bool {
        guard let surface = surface else { return false }
        return ghostty_surface_mouse_button(surface, state, button, mods)
    }

    /// Send mouse position event
    func sendMousePos(x: Double, y: Double, mods: ghostty_input_mods_e) {
        guard let surface = surface else { return }
        ghostty_surface_mouse_pos(surface, x, y, mods)
    }

    /// Send mouse scroll event
    func sendMouseScroll(x: Double, y: Double, mods: ghostty_input_scroll_mods_t) {
        guard let surface = surface else { return }
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    /// Check if mouse is captured by the terminal
    var mouseCaptured: Bool {
        guard let surface = surface else { return false }
        return ghostty_surface_mouse_captured(surface)
    }

    // MARK: - Selection

    /// Check if there is an active selection
    var hasSelection: Bool {
        guard let surface = surface else { return false }
        return ghostty_surface_has_selection(surface)
    }

    // MARK: - Status

    /// Check if the process has exited
    var processExited: Bool {
        guard let surface = surface else { return true }
        return ghostty_surface_process_exited(surface)
    }

    /// Check if confirmation is needed before quit
    var needsConfirmQuit: Bool {
        guard let surface = surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    /// Get the current surface size
    var size: ghostty_surface_size_s {
        guard let surface = surface else {
            return ghostty_surface_size_s()
        }
        return ghostty_surface_size(surface)
    }
}
