import Foundation
import Network

// MARK: - Browser API Server

actor BrowserAPIServer {
    private var listener: NWListener?
    private let automation: BrowserAutomation
    private let port: UInt16
    private var isRunning = false

    private static let DEFAULT_PORT: UInt16 = 48484
    private static let PORT_FILE_PATH = "~/.plue/browser-api.port"

    init(automation: BrowserAutomation, port: UInt16 = DEFAULT_PORT) {
        self.automation = automation
        self.port = port
    }

    // MARK: - Server Lifecycle

    func start() async throws {
        guard !isRunning else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleStateUpdate(state)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
        isRunning = true

        writePortFile()
        print("[BrowserAPIServer] Started on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        removePortFile()
        print("[BrowserAPIServer] Stopped")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[BrowserAPIServer] Ready to accept connections")
        case .failed(let error):
            print("[BrowserAPIServer] Failed: \(error)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    // MARK: - Port File Management

    private func writePortFile() {
        let path = NSString(string: Self.PORT_FILE_PATH).expandingTildeInPath
        let directory = (path as NSString).deletingLastPathComponent

        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
            try "\(port)".write(toFile: path, atomically: true, encoding: .utf8)
            print("[BrowserAPIServer] Wrote port file: \(path)")
        } catch {
            print("[BrowserAPIServer] Failed to write port file: \(error)")
        }
    }

    private func removePortFile() {
        let path = NSString(string: Self.PORT_FILE_PATH).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task {
                    await self.receiveRequest(connection)
                }
            case .failed(let error):
                print("[BrowserAPIServer] Connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveRequest(_ connection: NWConnection) async {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            if let error = error {
                print("[BrowserAPIServer] Receive error: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }

            Task {
                await self.processRequest(data, connection: connection)
            }
        }
    }

    // MARK: - HTTP Request Processing

    private func processRequest(_ data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            await sendErrorResponse(connection, statusCode: 400, message: "Invalid request encoding")
            return
        }

        let request = parseHTTPRequest(requestString)

        let response = await routeRequest(request)

        await sendResponse(connection, response: response)
    }

    private func parseHTTPRequest(_ raw: String) -> HTTPRequest {
        let lines = raw.components(separatedBy: "\r\n")

        guard let requestLine = lines.first else {
            return HTTPRequest(method: "GET", path: "/", headers: [:], body: nil)
        }

        let parts = requestLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : "GET"
        let path = parts.count > 1 ? parts[1] : "/"

        var headers: [String: String] = [:]
        var bodyStartIndex: Int?

        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            }

            if index > 0 {
                let headerParts = line.components(separatedBy: ": ")
                if headerParts.count >= 2 {
                    headers[headerParts[0].lowercased()] = headerParts.dropFirst().joined(separator: ": ")
                }
            }
        }

        var body: Data?
        if let startIndex = bodyStartIndex, startIndex < lines.count {
            let bodyString = lines[startIndex...].joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Request Routing

    private func routeRequest(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/browser/status"):
            return await handleStatus()

        case ("POST", "/browser/snapshot"):
            return await handleSnapshot(request)

        case ("POST", "/browser/click"):
            return await handleClick(request)

        case ("POST", "/browser/type"):
            return await handleType(request)

        case ("POST", "/browser/scroll"):
            return await handleScroll(request)

        case ("POST", "/browser/extract"):
            return await handleExtract(request)

        case ("POST", "/browser/screenshot"):
            return await handleScreenshot()

        case ("POST", "/browser/navigate"):
            return await handleNavigate(request)

        case ("OPTIONS", _):
            return HTTPResponse(
                statusCode: 200,
                headers: corsHeaders(),
                body: nil
            )

        default:
            return HTTPResponse(
                statusCode: 404,
                headers: jsonHeaders(),
                body: encodeJSON(["success": false, "error": "Not found"])
            )
        }
    }

    // MARK: - Route Handlers

    private func handleStatus() async -> HTTPResponse {
        let isConnected = await automation.isConnected

        let response: [String: Any] = [
            "success": true,
            "connected": isConnected
        ]

        return HTTPResponse(
            statusCode: 200,
            headers: jsonHeaders(),
            body: encodeJSON(response)
        )
    }

    private func handleSnapshot(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            var options = SnapshotOptions.default

            if let body = request.body,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if let includeHidden = json["include_hidden"] as? Bool {
                    options = SnapshotOptions(
                        includeHidden: includeHidden,
                        includeBounds: options.includeBounds,
                        maxDepth: options.maxDepth
                    )
                }
                if let maxDepth = json["max_depth"] as? Int {
                    options = SnapshotOptions(
                        includeHidden: options.includeHidden,
                        includeBounds: options.includeBounds,
                        maxDepth: maxDepth
                    )
                }
            }

            let snapshot = try await automation.snapshot(options: options)
            let textTree = snapshot.toTextTree()

            let response: [String: Any] = [
                "success": true,
                "text_tree": textTree,
                "url": snapshot.url,
                "title": snapshot.title,
                "element_count": snapshot.elementCount
            ]

            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(response)
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleClick(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ref = json["ref"] as? String else {
            return HTTPResponse(
                statusCode: 400,
                headers: jsonHeaders(),
                body: encodeJSON(["success": false, "error": "Missing 'ref' parameter"])
            )
        }

        do {
            try await automation.click(ref: ref)
            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true])
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleType(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ref = json["ref"] as? String,
              let text = json["text"] as? String else {
            return HTTPResponse(
                statusCode: 400,
                headers: jsonHeaders(),
                body: encodeJSON(["success": false, "error": "Missing 'ref' or 'text' parameter"])
            )
        }

        let clear = json["clear"] as? Bool ?? false
        let options = TypeOptions(clear: clear)

        do {
            try await automation.type(ref: ref, text: text, options: options)
            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true])
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleScroll(_ request: HTTPRequest) async -> HTTPResponse {
        var direction = ScrollDirection.down
        var amount = 300

        if let body = request.body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let dirStr = json["direction"] as? String {
                switch dirStr.lowercased() {
                case "up": direction = .up
                case "down": direction = .down
                case "left": direction = .left
                case "right": direction = .right
                default: break
                }
            }
            if let amt = json["amount"] as? Int {
                amount = amt
            }
        }

        do {
            try await automation.scroll(direction: direction, amount: amount)
            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true])
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleExtract(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let ref = json["ref"] as? String else {
            return HTTPResponse(
                statusCode: 400,
                headers: jsonHeaders(),
                body: encodeJSON(["success": false, "error": "Missing 'ref' parameter"])
            )
        }

        do {
            let text = try await automation.extractText(ref: ref)
            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true, "text": text])
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleScreenshot() async -> HTTPResponse {
        do {
            let imageData = try await automation.screenshot()
            let base64 = imageData.base64EncodedString()

            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true, "image_base64": base64])
            )
        } catch {
            return errorResponse(error)
        }
    }

    private func handleNavigate(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let url = json["url"] as? String else {
            return HTTPResponse(
                statusCode: 400,
                headers: jsonHeaders(),
                body: encodeJSON(["success": false, "error": "Missing 'url' parameter"])
            )
        }

        do {
            try await automation.navigate(to: url)
            return HTTPResponse(
                statusCode: 200,
                headers: jsonHeaders(),
                body: encodeJSON(["success": true])
            )
        } catch {
            return errorResponse(error)
        }
    }

    // MARK: - Response Helpers

    private func errorResponse(_ error: Error) -> HTTPResponse {
        let message: String
        if let browserError = error as? BrowserError {
            message = browserError.localizedDescription
        } else {
            message = error.localizedDescription
        }

        return HTTPResponse(
            statusCode: 200,
            headers: jsonHeaders(),
            body: encodeJSON(["success": false, "error": message])
        )
    }

    private func jsonHeaders() -> [String: String] {
        var headers = corsHeaders()
        headers["Content-Type"] = "application/json"
        return headers
    }

    private func corsHeaders() -> [String: String] {
        [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        ]
    }

    private func encodeJSON(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }

    private func sendResponse(_ connection: NWConnection, response: HTTPResponse) async {
        var httpResponse = "HTTP/1.1 \(response.statusCode) \(response.statusCode == 200 ? "OK" : "Error")\r\n"

        for (key, value) in response.headers {
            httpResponse += "\(key): \(value)\r\n"
        }

        if let body = response.body {
            httpResponse += "Content-Length: \(body.count)\r\n"
        }

        httpResponse += "\r\n"

        var responseData = httpResponse.data(using: .utf8) ?? Data()
        if let body = response.body {
            responseData.append(body)
        }

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendErrorResponse(_ connection: NWConnection, statusCode: Int, message: String) async {
        let response = HTTPResponse(
            statusCode: statusCode,
            headers: jsonHeaders(),
            body: encodeJSON(["success": false, "error": message])
        )
        await sendResponse(connection, response: response)
    }
}

// MARK: - HTTP Types

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
}

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?
}
