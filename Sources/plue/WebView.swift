import SwiftUI
import WebKit

// MARK: - Browser Tab Model
struct BrowserTab: Identifiable {
    let id: Int
    let title: String
    let url: String
    let isActive: Bool
}

struct WebView: View {
    let appState: AppState
    let core: PlueCoreInterface
    
    @State private var urlString = ""
    @State private var tabs: [BrowserTab] = [BrowserTab(id: 0, title: "New Tab", url: "https://www.apple.com", isActive: true)]
    @State private var selectedTab = 0
    @FocusState private var isUrlFocused: Bool
    @State private var webView: WKWebView?
    
    var body: some View {
        VStack(spacing: 0) {
            // Safari-style Browser Chrome
            safariLikeChrome
            
            // Web Content with proper framing
            ZStack {
                DesignSystem.Colors.surface(for: appState.currentTheme)
                
                WebViewRepresentable(
                    webView: $webView,
                    appState: appState,
                    core: core
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.2), lineWidth: 1)
                )
                .padding(8)
            }
        }
        .background(DesignSystem.Colors.background(for: appState.currentTheme))
        .preferredColorScheme(appState.currentTheme == .dark ? .dark : .light)
        .onAppear {
            urlString = appState.webState.currentURL
            loadURL(urlString)
        }
    }
    
    // MARK: - Safari-like Browser Chrome
    private var safariLikeChrome: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(tabs) { tab in
                            browserTabButton(tab)
                        }
                        
                        // Add Tab Button
                        Button(action: addNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                                .frame(width: 28, height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DesignSystem.Colors.surface(for: appState.currentTheme).opacity(0.5))
                        )
                    }
                    .padding(.horizontal, 12)
                }
                
                Spacer()
                
                // Browser Controls
                HStack(spacing: 8) {
                    Button(action: { goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.webState.canGoBack ? DesignSystem.Colors.textPrimary(for: appState.currentTheme) : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!appState.webState.canGoBack)
                    .help("Go back")
                    
                    Button(action: { goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.webState.canGoForward ? DesignSystem.Colors.textPrimary(for: appState.currentTheme) : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!appState.webState.canGoForward)
                    .help("Go forward")
                    
                    Button(action: {
                        if appState.webState.isLoading {
                            stopLoading()
                        } else {
                            reload()
                        }
                    }) {
                        Image(systemName: appState.webState.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(appState.webState.isLoading ? "Stop loading" : "Reload page")
                }
                .padding(.trailing, 16)
            }
            .frame(height: 40)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Address Bar
            HStack(spacing: 12) {
                // Security Indicator & URL Field
                HStack(spacing: 8) {
                    // Security Lock
                    Image(systemName: appState.webState.currentURL.hasPrefix("https://") ? "lock.fill" : "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(appState.webState.currentURL.hasPrefix("https://") ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    
                    // URL TextField
                    TextField("Search or enter website name", text: $urlString)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textPrimary(for: appState.currentTheme))
                        .focused($isUrlFocused)
                        .onSubmit {
                            loadURL(urlString)
                            isUrlFocused = false
                        }
                        .onChange(of: appState.webState.currentURL) { newURL in
                            if !isUrlFocused {
                                urlString = newURL
                            }
                        }
                    
                    // Loading Indicator
                    if appState.webState.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.background(for: appState.currentTheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Share & Bookmark
                HStack(spacing: 8) {
                    Button(action: {}) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add bookmark")
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Share")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.surface(for: appState.currentTheme))
            
            // Subtle border
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignSystem.Colors.border(for: appState.currentTheme).opacity(0.3))
        }
    }
    
    private func browserTabButton(_ tab: BrowserTab) -> some View {
        Button(action: { selectedTab = tab.id }) {
            HStack(spacing: 6) {
                // Favicon placeholder
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.1))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                    )
                
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        tab.isActive 
                            ? DesignSystem.Colors.textPrimary(for: appState.currentTheme)
                            : DesignSystem.Colors.textSecondary(for: appState.currentTheme)
                    )
                    .lineLimit(1)
                
                if tabs.count > 1 {
                    Button(action: { closeTab(tab.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textTertiary(for: appState.currentTheme))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tab.isActive ? DesignSystem.Colors.background(for: appState.currentTheme) : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Management
    private func addNewTab() {
        let newTab = BrowserTab(
            id: tabs.count,
            title: "New Tab",
            url: "https://www.apple.com",
            isActive: false
        )
        
        // Deactivate current tabs
        tabs = tabs.map { tab in
            BrowserTab(id: tab.id, title: tab.title, url: tab.url, isActive: false)
        }
        
        tabs.append(newTab)
        selectedTab = newTab.id
        
        // Activate the new tab
        if let index = tabs.firstIndex(where: { $0.id == newTab.id }) {
            tabs[index] = BrowserTab(id: newTab.id, title: newTab.title, url: newTab.url, isActive: true)
        }
        
        // Load the default URL
        urlString = newTab.url
        loadURL(urlString)
    }
    
    private func closeTab(_ tabId: Int) {
        guard tabs.count > 1 else { return }
        
        tabs.removeAll { $0.id == tabId }
        
        // If closed tab was active, activate the first tab
        if selectedTab == tabId {
            selectedTab = tabs.first?.id ?? 0
            if let index = tabs.firstIndex(where: { $0.id == selectedTab }) {
                tabs[index] = BrowserTab(
                    id: tabs[index].id,
                    title: tabs[index].title,
                    url: tabs[index].url,
                    isActive: true
                )
                urlString = tabs[index].url
                loadURL(urlString)
            }
        }
    }
    
    // MARK: - Web Navigation Methods
    private func loadURL(_ urlString: String) {
        guard let webView = webView else { return }
        
        var finalURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no scheme is provided
        if !finalURLString.hasPrefix("http://") && !finalURLString.hasPrefix("https://") {
            finalURLString = "https://" + finalURLString
        }
        
        guard let url = URL(string: finalURLString) else { return }
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Send event to Zig
        core.handleEvent(.webNavigate(finalURLString))
    }
    
    private func goBack() {
        webView?.goBack()
        core.handleEvent(.webGoBack)
    }
    
    private func goForward() {
        webView?.goForward()
        core.handleEvent(.webGoForward)
    }
    
    private func reload() {
        webView?.reload()
        core.handleEvent(.webReload)
    }
    
    private func stopLoading() {
        webView?.stopLoading()
    }
}

// MARK: - Web View Model (REMOVED - State now in AppState)
// WebViewModel has been removed in favor of centralized state management

// MARK: - WKWebView Representable
struct WebViewRepresentable: NSViewRepresentable {
    @Binding var webView: WKWebView?
    let appState: AppState
    let core: PlueCoreInterface
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Enable JavaScript
        configuration.preferences.javaScriptEnabled = true
        
        // Enable modern features
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Set navigation delegate
        webView.navigationDelegate = context.coordinator
        
        // Set UI delegate for JavaScript alerts, etc.
        webView.uiDelegate = context.coordinator
        
        // Allow back/forward gestures
        webView.allowsBackForwardNavigationGestures = true
        
        // Store the web view
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Updates handled by coordinator
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, core: core)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let appState: AppState
        let core: PlueCoreInterface
        
        init(appState: AppState, core: PlueCoreInterface) {
            self.appState = appState
            self.core = core
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Notify Zig about loading state
            // In real implementation, Zig would update state and Swift would observe
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Notify Zig about navigation complete
            // In real implementation, Zig would update state and Swift would observe
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error.localizedDescription)")
            // Notify Zig about navigation failure
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView provisional navigation failed: \(error.localizedDescription)")
            // Notify Zig about provisional navigation failure
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation for now
            decisionHandler(.allow)
        }
        
        // MARK: - WKUIDelegate
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            // Handle JavaScript alerts
            let alert = NSAlert()
            alert.messageText = "JavaScript Alert"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            // Handle JavaScript confirm dialogs
            let alert = NSAlert()
            alert.messageText = "JavaScript Confirm"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
        
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            // Handle JavaScript prompt dialogs
            let alert = NSAlert()
            alert.messageText = "JavaScript Prompt"
            alert.informativeText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(textField.stringValue)
            } else {
                completionHandler(nil)
            }
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle new window requests by loading in the same web view
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

#Preview {
    WebView(appState: AppState.initial, core: PlueCore.shared)
        .frame(width: 1000, height: 700)
}