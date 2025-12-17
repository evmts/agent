import Foundation
import SwiftUI

/// Terminal backend options
enum TerminalBackend: String, CaseIterable, Codable {
    case ghostty = "Ghostty"
    case swiftterm = "SwiftTerm"

    var description: String {
        switch self {
        case .ghostty:
            return "GPU-accelerated terminal (Ghostty)"
        case .swiftterm:
            return "Software-rendered terminal (SwiftTerm)"
        }
    }
}

/// Application settings stored in UserDefaults
class AppSettings: ObservableObject {
    /// The terminal backend to use
    @AppStorage("terminalBackend") var terminalBackend: TerminalBackend = .ghostty

    /// Whether to show the terminal backend in the UI (for debugging)
    @AppStorage("showTerminalBackendIndicator") var showTerminalBackendIndicator: Bool = false

    /// Get the default shell from environment
    var defaultShell: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Singleton instance
    static let shared = AppSettings()

    private init() {}
}

// Make TerminalBackend work with AppStorage
extension TerminalBackend: RawRepresentable {
    typealias RawValue = String
}
