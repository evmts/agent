import Foundation
import AppKit
import CGhostty

// MARK: - Platform Types

extension ghostty_platform_e {
    static let macos = GHOSTTY_PLATFORM_MACOS
    static let ios = GHOSTTY_PLATFORM_IOS
}

// MARK: - Input Types

extension ghostty_input_mouse_state_e {
    static let press = GHOSTTY_MOUSE_PRESS
    static let release = GHOSTTY_MOUSE_RELEASE
}

extension ghostty_input_mouse_button_e {
    static let left = GHOSTTY_MOUSE_LEFT
    static let right = GHOSTTY_MOUSE_RIGHT
    static let middle = GHOSTTY_MOUSE_MIDDLE
    static let unknown = GHOSTTY_MOUSE_UNKNOWN
}

extension ghostty_color_scheme_e {
    static let light = GHOSTTY_COLOR_SCHEME_LIGHT
    static let dark = GHOSTTY_COLOR_SCHEME_DARK
}

// MARK: - Modifier Keys

extension ghostty_input_mods_e: OptionSet {
    public init(rawValue: UInt32) {
        self = ghostty_input_mods_e(rawValue)
    }

    public static let none = GHOSTTY_MODS_NONE
    public static let shift = GHOSTTY_MODS_SHIFT
    public static let ctrl = GHOSTTY_MODS_CTRL
    public static let alt = GHOSTTY_MODS_ALT
    public static let `super` = GHOSTTY_MODS_SUPER
    public static let caps = GHOSTTY_MODS_CAPS
    public static let num = GHOSTTY_MODS_NUM
}

// MARK: - NSEvent to Ghostty Conversion

extension NSEvent {
    /// Convert NSEvent modifier flags to ghostty modifier flags
    var ghosttyMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE

        if modifierFlags.contains(.shift) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SHIFT.rawValue)
        }
        if modifierFlags.contains(.control) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CTRL.rawValue)
        }
        if modifierFlags.contains(.option) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_ALT.rawValue)
        }
        if modifierFlags.contains(.command) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_SUPER.rawValue)
        }
        if modifierFlags.contains(.capsLock) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_CAPS.rawValue)
        }
        if modifierFlags.contains(.numericPad) {
            mods = ghostty_input_mods_e(rawValue: mods.rawValue | GHOSTTY_MODS_NUM.rawValue)
        }

        return mods
    }

    /// Convert NSEvent mouse button to ghostty mouse button
    var ghosttyMouseButton: ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }
}

// MARK: - Scroll Mods Helper

struct GhosttyScrollMods {
    /// Create scroll mods from NSEvent
    static func from(event: NSEvent) -> ghostty_input_scroll_mods_t {
        // The scroll mods is a packed struct, build it up
        var mods: Int32 = 0

        // Pixel scroll (precision scrolling)
        if event.hasPreciseScrollingDeltas {
            mods |= (1 << 0) // precision bit
        }

        // Momentum phase
        switch event.momentumPhase {
        case .began:
            mods |= (1 << 1)
        case .changed:
            mods |= (3 << 1)
        case .ended:
            mods |= (4 << 1)
        case .cancelled:
            mods |= (5 << 1)
        default:
            break
        }

        return mods
    }
}
