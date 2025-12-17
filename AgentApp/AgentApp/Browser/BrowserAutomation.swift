import Foundation
import WebKit

// MARK: - Browser Automation Actor

actor BrowserAutomation {
    private weak var webView: WKWebView?
    private var pendingCommands: [String: CheckedContinuation<BrowserResult, Error>] = [:]
    private var isScriptReady = false
    private var scriptReadyContinuations: [CheckedContinuation<Void, Never>] = []

    // Callbacks for external notifications
    private var onNavigationStarted: ((String) -> Void)?
    private var onNavigationComplete: ((String, String) -> Void)?
    private var onScriptReady: (() -> Void)?

    init(webView: WKWebView? = nil) {
        self.webView = webView
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        self.isScriptReady = false
    }

    func setOnScriptReady(_ callback: @escaping () -> Void) {
        self.onScriptReady = callback
    }

    func setOnNavigationStarted(_ callback: @escaping (String) -> Void) {
        self.onNavigationStarted = callback
    }

    func setOnNavigationComplete(_ callback: @escaping (String, String) -> Void) {
        self.onNavigationComplete = callback
    }

    // MARK: - Command Execution

    func execute(_ command: BrowserCommand) async throws -> BrowserResult {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        // Wait for script to be ready
        if !isScriptReady {
            await waitForScriptReady()
        }

        let commandId = UUID().uuidString

        return try await withCheckedThrowingContinuation { continuation in
            pendingCommands[commandId] = continuation

            let js = command.toJavaScript(commandId: commandId)

            Task { @MainActor in
                webView.evaluateJavaScript(js) { [weak self] _, error in
                    if let error = error {
                        Task {
                            await self?.handleJSError(commandId: commandId, error: error)
                        }
                    }
                }
            }

            // Set timeout
            Task {
                try? await Task.sleep(for: .seconds(30))
                await self.handleTimeout(commandId: commandId)
            }
        }
    }

    func executeWithRetry(
        _ command: BrowserCommand,
        maxAttempts: Int = 3,
        retryDelay: Duration = .milliseconds(500)
    ) async throws -> BrowserResult {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await execute(command)
            } catch let error as BrowserError {
                lastError = error

                switch error {
                case .elementNotFound, .scriptError, .invalidCommand:
                    throw error
                default:
                    if attempt < maxAttempts {
                        try await Task.sleep(for: retryDelay)
                    }
                }
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(for: retryDelay)
                }
            }
        }

        throw lastError ?? BrowserError.timeout(operation: "retry", timeoutMs: 0)
    }

    // MARK: - Result Handling

    func handleResult(_ result: BrowserResult) {
        guard let continuation = pendingCommands.removeValue(forKey: result.commandId) else {
            print("[BrowserAutomation] No pending command for ID: \(result.commandId)")
            return
        }

        if result.success {
            continuation.resume(returning: result)
        } else {
            let error = BrowserError.scriptError(message: result.error ?? "Unknown error")
            continuation.resume(throwing: error)
        }
    }

    private func handleJSError(commandId: String, error: Error) {
        guard let continuation = pendingCommands.removeValue(forKey: commandId) else {
            return
        }
        continuation.resume(throwing: BrowserError.scriptError(message: error.localizedDescription))
    }

    private func handleTimeout(commandId: String) {
        guard let continuation = pendingCommands.removeValue(forKey: commandId) else {
            return
        }
        continuation.resume(throwing: BrowserError.timeout(operation: "command", timeoutMs: 30000))
    }

    // MARK: - Navigation Events

    func handleNavigationStarted(url: String) {
        onNavigationStarted?(url)
    }

    func handleNavigationComplete(url: String, title: String) {
        onNavigationComplete?(url, title)
    }

    // MARK: - Script Ready

    func handleScriptReady() {
        isScriptReady = true
        onScriptReady?()

        for continuation in scriptReadyContinuations {
            continuation.resume()
        }
        scriptReadyContinuations.removeAll()
    }

    private func waitForScriptReady() async {
        if isScriptReady { return }

        await withCheckedContinuation { continuation in
            scriptReadyContinuations.append(continuation)
        }
    }

    // MARK: - Convenience Methods

    func snapshot(options: SnapshotOptions = .default) async throws -> AccessibilitySnapshot {
        let result = try await execute(.snapshot(options: options))

        guard case .snapshot(let snapshot) = result.data else {
            throw BrowserError.scriptError(message: "Invalid snapshot result")
        }

        return snapshot
    }

    func click(ref: String, options: ClickOptions = .default) async throws {
        _ = try await execute(.click(ref: ref, options: options))
    }

    func type(ref: String, text: String, options: TypeOptions = .default) async throws {
        _ = try await execute(.type(ref: ref, text: text, options: options))
    }

    func scroll(direction: ScrollDirection, amount: Int = 300) async throws {
        _ = try await execute(.scroll(ref: nil, direction: direction, amount: amount))
    }

    func extractText(ref: String) async throws -> String {
        let result = try await execute(.extractText(ref: ref))

        guard case .text(let text) = result.data else {
            throw BrowserError.scriptError(message: "Invalid extract result")
        }

        return text
    }

    func navigate(to url: String) async throws {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        guard let url = URL(string: url) else {
            throw BrowserError.navigationFailed(url: url, reason: "Invalid URL")
        }

        await MainActor.run {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() async throws {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        await MainActor.run {
            webView.goBack()
        }
    }

    func goForward() async throws {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        await MainActor.run {
            webView.goForward()
        }
    }

    func reload() async throws {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        await MainActor.run {
            webView.reload()
        }
    }

    // MARK: - Screenshot (Native Implementation)

    func screenshot() async throws -> Data {
        guard let webView = webView else {
            throw BrowserError.disconnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let config = WKSnapshotConfiguration()
                webView.takeSnapshot(with: config) { image, error in
                    if let error = error {
                        continuation.resume(throwing: BrowserError.scriptError(message: error.localizedDescription))
                        return
                    }

                    guard let image = image else {
                        continuation.resume(throwing: BrowserError.scriptError(message: "No image captured"))
                        return
                    }

                    guard let tiffData = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiffData),
                          let pngData = bitmap.representation(using: .png, properties: [:]) else {
                        continuation.resume(throwing: BrowserError.scriptError(message: "Failed to convert image"))
                        return
                    }

                    continuation.resume(returning: pngData)
                }
            }
        }
    }

    // MARK: - Status

    var isConnected: Bool {
        webView != nil && isScriptReady
    }
}

// MARK: - Browser Automation Manager

class BrowserAutomationManager: ObservableObject {
    static let shared = BrowserAutomationManager()

    let automation = BrowserAutomation()
    let handler = BrowserAutomationHandler()
    let apiServer: BrowserAPIServer

    @Published var isConnected = false
    @Published var isAPIServerRunning = false
    @Published var lastSnapshot: AccessibilitySnapshot?
    @Published var lastError: String?

    private init() {
        self.apiServer = BrowserAPIServer(automation: automation)
        handler.automation = automation

        Task {
            await setupCallbacks()
            await startAPIServer()
        }
    }

    private func setupCallbacks() async {
        await automation.setOnScriptReady { [weak self] in
            Task { @MainActor in
                self?.isConnected = true
            }
        }
    }

    private func startAPIServer() async {
        do {
            try await apiServer.start()
            await MainActor.run {
                self.isAPIServerRunning = true
            }
        } catch {
            print("[BrowserAutomationManager] Failed to start API server: \(error)")
        }
    }

    func connect(to webView: WKWebView) async {
        await automation.setWebView(webView)
    }

    func captureSnapshot() async {
        do {
            let snapshot = try await automation.snapshot()
            await MainActor.run {
                self.lastSnapshot = snapshot
                self.lastError = nil
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
}
