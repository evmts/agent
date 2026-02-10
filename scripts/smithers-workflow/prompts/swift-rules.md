# Swift/SwiftUI Rules (LLMs get these wrong)

## Modern Patterns Only
- `@Observable` (NOT ObservableObject) for models
- `@State` (NOT @StateObject) as owning wrapper
- `@Environment(Type.self)` (NOT @EnvironmentObject)
- `NavigationStack` (NOT NavigationView)
- `.foregroundStyle()` (NOT .foregroundColor())
- `.clipShape(.rect(cornerRadius:))` (NOT .cornerRadius())
- `navigationDestination(for:)` type-safe routing (NOT inline NavigationLink)
- `async/await` structured concurrency (NO DispatchQueue, NO completion handlers)
- `@Bindable` for bindings to @Observable

## Concurrency
- Swift 6 strict. NEVER ignore warnings.
- `@MainActor` for UI.
- `actor` for shared mutable state.
- NEVER `@unchecked Sendable` as quick fix.
- NEVER DispatchQueue.

## UI
- SF Symbols for icons
- No arbitrary font literals — use design tokens (`type.xs`, `type.base`, etc.) from `design/system-tokens.md`. Prefer SwiftUI text styles (`.caption`, `.body`) where appropriate. macOS does not have iOS Dynamic Type, but support user-configurable font scaling via preferences.
- `Button` (NOT onTapGesture) for tappables
- Extract views >100 lines
- `guard` for early exits

## Testing
- Swift Testing (`@Test`, `#expect`) for new unit tests
- XCUITest + Page Object Model for e2e
- `.accessibilityIdentifier()` on interactive elements
- NEVER `Thread.sleep()` — use `waitForExistence(timeout:)`
