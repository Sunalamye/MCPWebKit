//
//  MCPWebServer.swift
//  MCPWebKit
//
//  本地 HTTP MCP Server - 允許 Claude Code 等 AI 工具控制 WebView
//

import Foundation
import Network
import MCPKit

// MARK: - MCP Web Server

/// 本地 HTTP MCP Server
/// 監聽 HTTP 請求，處理 MCP JSON-RPC 協議，執行工具調用
@MainActor
public class MCPWebServer {

    // MARK: - Properties

    private var listener: NWListener?
    private let preferredPort: UInt16
    public private(set) var actualPort: UInt16 = 0
    private var isRunning = false
    private let maxPortRetries = 10

    /// WebView 執行 JavaScript 的回調
    public var executeJavaScript: ((String, @escaping (Any?, Error?) -> Void) -> Void)?

    /// 日誌回調
    public var onLog: ((String) -> Void)?

    /// 端口變更回調
    public var onPortChanged: ((UInt16) -> Void)?

    /// 日誌存儲（最多保留 10000 條）
    private var logBuffer: [String] = []
    private let maxLogCount = 10000

    /// 自定義狀態回調（用於擴展）
    public var getCustomStatus: (() -> [String: Any])?

    /// MCP 協議處理器
    private let mcpHandler: MCPWebHandler

    // MARK: - Initialization

    public init(port: UInt16 = 8765) {
        self.preferredPort = port
        self.actualPort = port
        self.mcpHandler = MCPWebHandler()
        setupMCPHandler()
    }

    /// 設置 MCP Handler 的回調
    private func setupMCPHandler() {
        mcpHandler.serverPort = actualPort
        mcpHandler.executeJavaScript = { [weak self] script, completion in
            self?.executeJavaScript?(script, completion)
        }
        mcpHandler.getCustomStatus = { [weak self] in
            self?.getCustomStatus?() ?? [:]
        }
        mcpHandler.getLogs = { [weak self] in
            self?.logBuffer ?? []
        }
        mcpHandler.clearLogs = { [weak self] in
            self?.logBuffer.removeAll()
        }
        mcpHandler.log = { [weak self] message in
            self?.log(message)
        }
        mcpHandler.sendResponse = { [weak self] connection, status, body, contentType in
            self?.sendResponse(connection: connection, status: status, body: body, contentType: contentType)
        }
    }

    // MARK: - Tool Registration

    /// 註冊自定義工具
    public func registerTool<T: MCPTool>(_ toolType: T.Type) {
        mcpHandler.registerTool(toolType)
    }

    /// 批量註冊工具
    public func registerTools(_ toolTypes: [any MCPTool.Type]) {
        for toolType in toolTypes {
            mcpHandler.registerToolType(toolType)
        }
    }

    // MARK: - Server Control

    /// 啟動 Server（會自動嘗試其他端口如果被佔用）
    public func start() {
        guard !isRunning else {
            log("Server already running on port \(actualPort)")
            return
        }

        startWithPort(preferredPort, retryCount: 0)
    }

    private func startWithPort(_ port: UInt16, retryCount: Int) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.actualPort = port
                        self.isRunning = true
                        self.mcpHandler.serverPort = port
                        self.log("MCP Server started on port \(port)")
                        self.onPortChanged?(port)
                    case .failed(let error):
                        self.log("Server failed: \(error)")
                        if retryCount < self.maxPortRetries {
                            let nextPort = port + 1
                            self.log("Retrying on port \(nextPort)...")
                            self.startWithPort(nextPort, retryCount: retryCount + 1)
                        }
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .main)

        } catch {
            log("Failed to create listener: \(error)")
            if retryCount < maxPortRetries {
                let nextPort = port + 1
                log("Retrying on port \(nextPort)...")
                startWithPort(nextPort, retryCount: retryCount + 1)
            }
        }
    }

    /// 停止 Server
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        log("MCP Server stopped")
    }

    // MARK: - Logging

    public func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        logBuffer.append(logMessage)
        if logBuffer.count > maxLogCount {
            logBuffer.removeFirst()
        }
        onLog?(message)
        print("[MCPWebKit] \(message)")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveData(connection: connection)
    }

    private func receiveData(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    self.processRequest(data: data, connection: connection)
                }

                if !isComplete && error == nil {
                    self.receiveData(connection: connection)
                }
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "Invalid request", contentType: "text/plain")
            return
        }

        // 解析 HTTP 請求
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "Empty request", contentType: "text/plain")
            return
        }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "Invalid HTTP request", contentType: "text/plain")
            return
        }

        let method = parts[0]
        let path = parts[1]

        // 提取請求體
        let bodyIndex = request.range(of: "\r\n\r\n")
        let body = bodyIndex.map { String(request[request.index($0.upperBound, offsetBy: 0)...]) } ?? ""

        // 路由處理
        routeRequest(method: method, path: path, body: body, headers: lines, connection: connection)
    }

    private func routeRequest(method: String, path: String, body: String, headers: [String], connection: NWConnection) {
        switch (method, path) {
        case ("GET", "/"):
            handleRoot(connection: connection)
        case ("GET", "/status"):
            handleStatus(connection: connection)
        case ("POST", "/mcp"):
            mcpHandler.handleRequest(body: body, headers: headers, connection: connection)
        case ("GET", "/health"):
            sendJSON(connection: connection, data: ["status": "ok", "port": actualPort])
        default:
            sendResponse(connection: connection, status: 404, body: "Not Found", contentType: "text/plain")
        }
    }

    // MARK: - Request Handlers

    private func handleRoot(connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>MCPWebKit Server</title></head>
        <body>
        <h1>MCPWebKit MCP Server</h1>
        <p>Port: \(actualPort)</p>
        <p>Status: Running</p>
        <h2>Endpoints:</h2>
        <ul>
        <li>POST /mcp - MCP JSON-RPC endpoint</li>
        <li>GET /status - Server status</li>
        <li>GET /health - Health check</li>
        </ul>
        </body>
        </html>
        """
        sendResponse(connection: connection, status: 200, body: html, contentType: "text/html")
    }

    private func handleStatus(connection: NWConnection) {
        var status: [String: Any] = [
            "server": "MCPWebKit",
            "version": MCPWebKit.version,
            "port": actualPort,
            "isRunning": isRunning,
            "toolsCount": mcpHandler.registeredToolCount
        ]
        if let custom = getCustomStatus?() {
            status["custom"] = custom
        }
        sendJSON(connection: connection, data: status)
    }

    // MARK: - Response Methods

    private func sendResponse(connection: NWConnection, status: Int, body: String, contentType: String) {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func sendJSON(connection: NWConnection, data: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            let body = String(data: jsonData, encoding: .utf8) ?? "{}"
            sendResponse(connection: connection, status: 200, body: body, contentType: "application/json")
        } catch {
            sendResponse(connection: connection, status: 500, body: "{\"error\": \"JSON encoding failed\"}", contentType: "application/json")
        }
    }
}
