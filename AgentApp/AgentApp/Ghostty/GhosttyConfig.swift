import Foundation
import CGhostty

/// Swift wrapper for ghostty_config_t
final class GhosttyConfig {
    /// The underlying C config pointer
    private(set) var config: ghostty_config_t?

    /// Whether the config has been finalized
    private(set) var isFinalized = false

    init() {
        config = ghostty_config_new()
    }

    deinit {
        if let config = config {
            ghostty_config_free(config)
        }
    }

    /// Load default configuration files
    func loadDefaultFiles() {
        guard let config = config, !isFinalized else { return }
        ghostty_config_load_default_files(config)
    }

    /// Load command line arguments into config
    func loadCliArgs() {
        guard let config = config, !isFinalized else { return }
        ghostty_config_load_cli_args(config)
    }

    /// Finalize the configuration (must be called before use)
    func finalize() {
        guard let config = config, !isFinalized else { return }
        ghostty_config_finalize(config)
        isFinalized = true
    }

    /// Get the number of configuration diagnostics (errors/warnings)
    var diagnosticsCount: UInt32 {
        guard let config = config else { return 0 }
        return ghostty_config_diagnostics_count(config)
    }

    /// Check if there are any configuration errors
    var hasErrors: Bool {
        return diagnosticsCount > 0
    }
}
