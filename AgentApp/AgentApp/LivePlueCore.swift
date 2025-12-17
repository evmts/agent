import Foundation

// Use MockPlueCore for now - will be replaced with Zig FFI later
class LivePlueCore: PlueCoreInterface {
    private let mock = MockPlueCore()

    func getCurrentState() -> AppState {
        return mock.getCurrentState()
    }

    func handleEvent(_ event: AppEvent) {
        mock.handleEvent(event)
    }

    func subscribe(callback: @escaping (AppState) -> Void) {
        mock.subscribe(callback: callback)
    }

    func initialize() -> Bool {
        return mock.initialize()
    }

    func initialize(workingDirectory: String) -> Bool {
        return mock.initialize(workingDirectory: workingDirectory)
    }

    func shutdown() {
        mock.shutdown()
    }
}
