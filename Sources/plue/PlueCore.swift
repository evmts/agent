import Foundation
import libplue

/// Swift wrapper for the Zig-based Plue core library
public class PlueCore {
    private var isInitialized = false
    
    /// Initialize the Plue core library
    public init() throws {
        let result = plue_init()
        guard result == 0 else {
            throw PlueError.initializationFailed
        }
        isInitialized = true
    }
    
    deinit {
        if isInitialized {
            plue_deinit()
            isInitialized = false
        }
    }
    
    /// Process a message through the Plue core
    /// - Parameter message: Input message to process
    /// - Returns: Processed response string
    public func processMessage(_ message: String) -> String {
        guard isInitialized else { return "Error: Core not initialized" }
        
        guard let cString = plue_process_message(message) else {
            return "Error: Failed to process message"
        }
        
        let result = String(cString: cString)
        plue_free_string(cString)
        
        return result
    }
}

/// Errors that can occur when working with PlueCore
public enum PlueError: Error {
    case initializationFailed
    
    public var localizedDescription: String {
        switch self {
        case .initializationFailed:
            return "Failed to initialize Plue core library"
        }
    }
}