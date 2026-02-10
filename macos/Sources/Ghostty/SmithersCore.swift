import Foundation
import SmithersKit

/// Placeholder C FFI bridge following Ghostty pattern.
/// Will be expanded when libsmithers C API grows.
enum SmithersCoreBridge {
    static func smokeInitAndFree() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        if let h = smithers_app_new(&cfg) {
            smithers_app_free(h)
        }
    }
}
