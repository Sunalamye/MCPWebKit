//
//  MCPWebHandler.swift
//  MCPWebKit
//
//  MCP JSON-RPC 協議處理器
//

import Foundation
import Network
import MCPKit

// MARK: - MCP Web Handler

/// MCP Protocol 處理器
/// 負責處理所有 MCP JSON-RPC 請求
@MainActor
final class MCPWebHandler {

    // MARK: - Properties

    /// 執行上下文
    let context: WebViewMCPContext

    /// 已註冊的工具類型
    private var toolTypes: [String: any MCPTool.Type] = [:]
    private var toolOrder: [String] = []

    /// 發送 HTTP 響應的回調
    var sendResponse: ((NWConnection, Int, String, String) -> Void)?

    /// 已註冊工具數量
    var registeredToolCount: Int { toolOrder.count }

    // MARK: - Initialization

    init() {
        self.context = WebViewMCPContext()
        registerBuiltInTools()
    }

    // MARK: - Context Configuration

    var serverPort: UInt16 {
        get { context.serverPort }
        set { context.serverPort = newValue }
    }

    var executeJavaScript: ((String, @escaping (Any?, Error?) -> Void) -> Void)? {
        get { context.executeJavaScriptCallback }
        set { context.executeJavaScriptCallback = newValue }
    }

    var getCustomStatus: (() -> [String: Any])? {
        get { context.getCustomStatusCallback }
        set { context.getCustomStatusCallback = newValue }
    }

    var getLogs: (() -> [String])? {
        get { context.getLogsCallback }
        set { context.getLogsCallback = newValue }
    }

    var clearLogs: (() -> Void)? {
        get { context.clearLogsCallback }
        set { context.clearLogsCallback = newValue }
    }

    var log: ((String) -> Void)? {
        get { context.logCallback }
        set { context.logCallback = newValue }
    }

    // MARK: - Tool Registration

    /// 註冊工具
    func registerTool<T: MCPTool>(_ toolType: T.Type) {
        let name = T.name
        if toolTypes[name] == nil {
            toolOrder.append(name)
        }
        toolTypes[name] = toolType
    }

    /// 註冊工具（類型擦除版本）
    func registerToolType(_ toolType: any MCPTool.Type) {
        let name = toolType.name
        if toolTypes[name] == nil {
            toolOrder.append(name)
        }
        toolTypes[name] = toolType
    }

    /// 註冊內建工具
    private func registerBuiltInTools() {
        // 系統工具
        registerTool(GetStatusTool.self)
        registerTool(GetLogsTool.self)
        registerTool(ClearLogsTool.self)

        // JavaScript 執行
        registerTool(ExecuteJSTool.self)

        // 頁面操作
        registerTool(QuerySelectorTool.self)
        registerTool(ClickElementTool.self)
        registerTool(GetPageInfoTool.self)
    }

    // MARK: - Tool Access

    /// 獲取工具實例
    func tool(named name: String) -> (any MCPTool)? {
        guard let toolType = toolTypes[name] else { return nil }
        return toolType.init(context: context)
    }

    /// 生成所有工具的定義列表
    func allToolDefinitions() -> [[String: Any]] {
        return toolOrder.compactMap { name -> [String: Any]? in
            guard let toolType = toolTypes[name] else { return nil }
            return [
                "name": toolType.name,
                "description": toolType.description,
                "inputSchema": toolType.inputSchema.toJSON()
            ]
        }
    }

    // MARK: - MCP Request Handler

    func handleRequest(body: String, headers: [String], connection: NWConnection) {
        context.log("MCP request received")

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            sendError(connection: connection, id: nil, code: -32700, message: "Parse error")
            return
        }

        let id = json["id"]
        let params = json["params"] as? [String: Any] ?? [:]

        context.log("MCP method: \(method)")

        switch method {
        case "initialize":
            handleInitialize(id: id, params: params, connection: connection)
        case "initialized":
            sendResult(connection: connection, id: id, result: [:])
        case "tools/list":
            handleToolsList(id: id, connection: connection)
        case "tools/call":
            handleToolsCall(id: id, params: params, connection: connection)
        default:
            sendError(connection: connection, id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Method Handlers

    private func handleInitialize(id: Any?, params: [String: Any], connection: NWConnection) {
        let result: [String: Any] = [
            "protocolVersion": "2025-03-26",
            "serverInfo": [
                "name": "mcpwebkit",
                "version": MCPWebKit.version
            ],
            "capabilities": [
                "tools": [:]
            ]
        ]
        sendResult(connection: connection, id: id, result: result)
    }

    private func handleToolsList(id: Any?, connection: NWConnection) {
        let result: [String: Any] = [
            "tools": allToolDefinitions()
        ]
        sendResult(connection: connection, id: id, result: result)
    }

    private func handleToolsCall(id: Any?, params: [String: Any], connection: NWConnection) {
        guard let toolName = params["name"] as? String else {
            sendError(connection: connection, id: id, code: -32602, message: "Missing tool name")
            return
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        context.log("MCP tools/call: \(toolName)")

        Task { @MainActor in
            let result = await self.execute(toolNamed: toolName, arguments: arguments)

            switch result {
            case .success(let value):
                self.sendToolResult(connection: connection, id: id, content: value)
            case .error(let message):
                self.sendToolError(connection: connection, id: id, message: message)
            }
        }
    }

    /// 執行工具
    private func execute(toolNamed name: String, arguments: [String: Any]) async -> MCPToolResult {
        guard let tool = tool(named: name) else {
            return .error("Unknown tool: \(name)")
        }

        do {
            // Use nonisolated(unsafe) to allow passing to nonisolated execute method
            nonisolated(unsafe) let unsafeTool = tool
            nonisolated(unsafe) let unsafeArgs = arguments
            let result = try await unsafeTool.execute(arguments: unsafeArgs)
            return .success(result)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Response Methods

    private func sendResult(connection: NWConnection, id: Any?, result: [String: Any]) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id = id {
            response["id"] = id
        }
        sendJSON(connection: connection, data: response)
    }

    private func sendToolResult(connection: NWConnection, id: Any?, content: Any) {
        let contentText: String
        if let dict = content as? [String: Any] {
            contentText = (try? JSONSerialization.data(withJSONObject: sanitizeForJSON(dict), options: []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        } else if let array = content as? [Any] {
            contentText = (try? JSONSerialization.data(withJSONObject: sanitizeForJSON(array), options: []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        } else {
            contentText = String(describing: content)
        }

        let result: [String: Any] = [
            "content": [
                ["type": "text", "text": contentText]
            ],
            "isError": false
        ]
        sendResult(connection: connection, id: id, result: result)
    }

    private func sendToolError(connection: NWConnection, id: Any?, message: String) {
        let result: [String: Any] = [
            "content": [
                ["type": "text", "text": message]
            ],
            "isError": true
        ]
        sendResult(connection: connection, id: id, result: result)
    }

    private func sendError(connection: NWConnection, id: Any?, code: Int, message: String) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let id = id {
            response["id"] = id
        }
        sendJSON(connection: connection, data: response)
    }

    private func sendJSON(connection: NWConnection, data: [String: Any]) {
        do {
            let sanitized = sanitizeForJSON(data) as! [String: Any]
            let jsonData = try JSONSerialization.data(withJSONObject: sanitized, options: [])
            let body = String(data: jsonData, encoding: .utf8) ?? "{}"
            sendResponse?(connection, 200, body, "application/json")
        } catch {
            sendResponse?(connection, 500, "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}", "application/json")
        }
    }

    private func sanitizeForJSON(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.mapValues { sanitizeForJSON($0) }
        case let array as [Any]:
            return array.map { sanitizeForJSON($0) }
        case let d as Double where d.isNaN || d.isInfinite:
            return NSNull()
        case let f as Float where f.isNaN || f.isInfinite:
            return NSNull()
        case let n as NSNumber:
            let d = n.doubleValue
            if d.isNaN || d.isInfinite {
                return NSNull()
            }
            return n
        default:
            return value
        }
    }
}
