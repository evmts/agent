import Testing
import SmithersKit

@Suite struct SmithersTests {
    @Test func smithersKitLinking() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        let handle = smithers_app_new(&cfg)
        #expect(handle != nil)
        if let h = handle { smithers_app_free(h) }
    }
}
