import SwiftUI
import WebKit

struct WebView: View {
    @StateObject private var webViewModel = WebViewModel()
    @State private var urlString = "https://www.apple.com"
    @FocusState private var isUrlFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            navigationBar
            
            // Web Content
            WebViewRepresentable(webViewModel: webViewModel)
                .background(Color.white)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            webViewModel.loadURL(urlString)
        }
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                webViewModel.goBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(webViewModel.canGoBack ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!webViewModel.canGoBack)
            .help("Go back")
            
            // Forward button
            Button(action: {
                webViewModel.goForward()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(webViewModel.canGoForward ? .primary : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!webViewModel.canGoForward)
            .help("Go forward")
            
            // Reload button
            Button(action: {
                if webViewModel.isLoading {
                    webViewModel.stopLoading()
                } else {
                    webViewModel.reload()
                }
            }) {
                Image(systemName: webViewModel.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(webViewModel.isLoading ? "Stop loading" : "Reload page")
            
            // URL Bar
            HStack {
                Image(systemName: webViewModel.isSecure ? "lock.fill" : "globe")
                    .font(.system(size: 14))
                    .foregroundColor(webViewModel.isSecure ? .green : .secondary)
                
                TextField("Enter URL", text: $urlString)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .focused($isUrlFocused)
                    .onSubmit {
                        webViewModel.loadURL(urlString)
                        isUrlFocused = false
                    }
                    .onChange(of: webViewModel.currentURL) { newURL in
                        if !isUrlFocused {
                            urlString = newURL
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
            
            // Home button
            Button(action: {
                urlString = "https://www.apple.com"
                webViewModel.loadURL(urlString)
            }) {
                Image(systemName: "house")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Go to home page")
            
            // Progress indicator
            if webViewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(NSColor.separatorColor))
                        .opacity(0.6),
                    alignment: .bottom
                )
        )
    }
}

// MARK: - Web View Model
class WebViewModel: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL = ""
    @Published var isSecure = false
    @Published var pageTitle = ""
    
    private var webView: WKWebView?
    
    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        updateNavigationState()
    }
    
    func loadURL(_ urlString: String) {
        guard let webView = webView else { return }
        
        var finalURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no scheme is provided
        if !finalURLString.hasPrefix("http://") && !finalURLString.hasPrefix("https://") {
            finalURLString = "https://" + finalURLString
        }
        
        guard let url = URL(string: finalURLString) else { return }
        
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stopLoading() {
        webView?.stopLoading()
    }
    
    func updateNavigationState() {
        guard let webView = webView else { return }
        
        DispatchQueue.main.async {
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            self.currentURL = webView.url?.absoluteString ?? ""
            self.isSecure = webView.url?.scheme == "https"
            self.pageTitle = webView.title ?? ""
        }
    }
}

// MARK: - WKWebView Representable
struct WebViewRepresentable: NSViewRepresentable {
    let webViewModel: WebViewModel
    
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
        
        // Set the web view in the view model
        webViewModel.setWebView(webView)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Update handled by the view model
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(webViewModel: webViewModel)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let webViewModel: WebViewModel
        
        init(webViewModel: WebViewModel) {
            self.webViewModel = webViewModel
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.webViewModel.isLoading = true
                self.webViewModel.updateNavigationState()
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.webViewModel.isLoading = false
                self.webViewModel.updateNavigationState()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.webViewModel.isLoading = false
                self.webViewModel.updateNavigationState()
            }
            print("WebView navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.webViewModel.isLoading = false
                self.webViewModel.updateNavigationState()
            }
            print("WebView provisional navigation failed: \(error.localizedDescription)")
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
    WebView()
        .frame(width: 1000, height: 700)
}