import SwiftUI
import AppKit

// Initialize NSApplication first
let app = NSApplication.shared

// Force the app to behave like a proper GUI app
app.setActivationPolicy(.regular)

// Start the SwiftUI app directly
PlueApp.main()