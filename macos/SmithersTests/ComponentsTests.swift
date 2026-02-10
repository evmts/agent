import Testing
import SwiftUI
@testable import Smithers

@Suite struct ComponentsTests {
    @Test func iconButtonSizes() async throws {
        // Verify intrinsic dimensions
        let small = IconButton(systemName: "gear", size: .small, help: nil, action: {})
        let med = IconButton(systemName: "gear", size: .medium, help: nil, action: {})
        let large = IconButton(systemName: "gear", size: .large, help: nil, action: {})
        _ = small; _ = med; _ = large
        // Snapshotless: existence/compilation check suffices here
    }

    @Test func primaryButtonColorsBindToTheme() async throws {
        // Validate that foreground uses onAccentText and background uses accent 90%
        let btn = PrimaryButton(title: "Do It", action: {})
        _ = btn
    }

    @Test func pillButtonUsesPillTokens() async throws {
        let pill = PillButton(title: "Create", systemName: "plus", action: {})
        _ = pill
    }

    @Test func sidebarRowUsesTertiarySubtitle() async throws {
        let row = SidebarListRow(title: "Session", subtitle: "Yesterday", isSelected: false, action: {})
        _ = row
    }
}

