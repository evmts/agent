import Foundation

// MARK: - Ghostty Terminal C Function Imports
// These functions are defined in GhosttyTerminalSurfaceView.swift to avoid duplicate symbols

// MARK: - Swift-friendly wrapper class

/// A Swift-friendly wrapper around the Ghostty terminal C API
class GhosttyTerminal {
    static let shared = GhosttyTerminal()
    
    private var isInitialized = false
    private var hasSurface = false
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        guard !isInitialized else { return true }
        
        let result = ghostty_terminal_init()
        isInitialized = result == 0
        return isInitialized
    }
    
    /// Create a terminal surface
    func createSurface() -> Bool {
        guard isInitialized else { return false }
        
        let result = ghostty_terminal_create_surface()
        hasSurface = result == 0
        return hasSurface
    }
    
    /// Update terminal size
    func setSize(width: Int, height: Int, scale: Double) {
        guard hasSurface else { return }
        
        ghostty_terminal_set_size(UInt32(width), UInt32(height), scale)
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard hasSurface else { return }
        
        text.withCString { textPtr in
            ghostty_terminal_send_text(textPtr)
        }
    }
    
    /// Send key event to the terminal
    func sendKey(_ key: String, modifiers: UInt32 = 0, action: Int32 = 0) {
        guard hasSurface else { return }
        
        key.withCString { keyPtr in
            ghostty_terminal_send_key(keyPtr, modifiers, action)
        }
    }
    
    /// Write raw data to the terminal
    func write(_ data: Data) -> Int {
        guard hasSurface else { return 0 }
        
        return data.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            return Int(ghostty_terminal_write(buffer.baseAddress!, data.count))
        }
    }
    
    /// Read data from the terminal
    func read(maxBytes: Int = 4096) -> Data? {
        guard hasSurface else { return nil }
        
        var buffer = Data(count: maxBytes)
        let bytesRead = buffer.withUnsafeMutableBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt8.self)
            return Int(ghostty_terminal_read(buffer.baseAddress!, maxBytes))
        }
        
        if bytesRead > 0 {
            return buffer.prefix(bytesRead)
        }
        return nil
    }
    
    /// Trigger terminal redraw
    func draw() {
        guard hasSurface else { return }
        ghostty_terminal_draw()
    }
    
    /// Cleanup terminal resources
    func cleanup() {
        ghostty_terminal_deinit()
        isInitialized = false
        hasSurface = false
    }
    
    deinit {
        cleanup()
    }
}