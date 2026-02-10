import XCTest
import SmithersKit

final class SmithersTests: XCTestCase {
    func testSmithersKitLinking() {
        var cfg = smithers_config_s(runtime: smithers_runtime_config_s(wakeup: nil, action: nil, userdata: nil))
        let handle = smithers_app_new(&cfg)
        XCTAssertNotNil(handle)
        if let h = handle { smithers_app_free(h) }
    }
}
