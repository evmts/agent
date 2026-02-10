import SmithersKit

/// Wraps libsmithers C functions for Swift consumption.
enum SmithersCoreBridge {
    static func smokeInitAndFree() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        if let h = smithers_app_new(&cfg) {
            smithers_app_free(h)
        }
    }
}
