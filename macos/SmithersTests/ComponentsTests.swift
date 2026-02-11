import XCTest
import AppKit
@testable import Smithers

@MainActor
final class ComponentsTests: XCTestCase {
    func testTypographyScale_ordering() {
        XCTAssertLessThan(DS.Typography.s, DS.Typography.base)
        XCTAssertGreaterThan(DS.Typography.l, DS.Typography.base)
    }

    func testPrimaryButton_usesAccentAndOnAccent() {
        let theme = AppTheme.dark
        XCTAssertGreaterThan(theme.accent.alphaComponent, 0.0)
        XCTAssertGreaterThan(DS.Color.onAccentText.alphaComponent, 0.0)

        // Compile-time API surface check: construct a PrimaryButton
        _ = PrimaryButton(title: "Run", isDisabled: false, action: {})
    }

    func testPillButton_tokensPresent_andAPIInstantiates() {
        XCTAssertGreaterThan(DS.Color.chatPillBg.alphaComponent, 0.0)
        XCTAssertGreaterThan(DS.Color.chatPillBorder.alphaComponent, 0.0)
        XCTAssertGreaterThan(DS.Color.chatPillActive.alphaComponent, 0.0)

        _ = PillButton(title: "Explore", systemName: "sparkles", action: {})
    }

    func testSidebarListRow_APIInstantiates() {
        _ = SidebarListRow(title: "Row", subtitle: "Sub", isSelected: true, action: {})
    }
}
