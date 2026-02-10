# Swift/SwiftUI Coding Rules (Critical — LLMs commonly get these wrong)

## Modern Patterns Only
- Use `@Observable` (NOT ObservableObject) for all models
- Use `@State` (NOT @StateObject) as owning property wrapper
- Use `@Environment(Type.self)` (NOT @EnvironmentObject)
- Use `NavigationStack` (NOT NavigationView)
- Use `.foregroundStyle()` (NOT .foregroundColor())
- Use `.clipShape(.rect(cornerRadius:))` (NOT .cornerRadius())
- Use `navigationDestination(for:)` with type-safe routing (NOT inline NavigationLink destinations)
- Use `async/await` and structured concurrency (NO DispatchQueue, NO completion handlers)
- Use `@Bindable` for bindings to @Observable properties

## Concurrency
- Use Swift 6 strict concurrency. Never ignore warnings.
- `@MainActor` for all UI code.
- `actor` for shared mutable state.
- NEVER use `@unchecked Sendable` as a quick fix.
- NEVER use DispatchQueue.

## UI
- Use SF Symbols for all iconography.
- Never hardcode font sizes — respect Dynamic Type.
- Use `Button` (NOT onTapGesture) for tappable elements.
- Extract SwiftUI views exceeding 100 lines into sub-views.
- Use `guard` for early exits.

## Testing
- Use Swift Testing (`@Test`, `#expect`) for new unit tests.
- XCUITest with Page Object Model pattern for e2e tests.
- Always set `.accessibilityIdentifier()` on interactive elements.
- NEVER use `Thread.sleep()` — use `waitForExistence(timeout:)`.
