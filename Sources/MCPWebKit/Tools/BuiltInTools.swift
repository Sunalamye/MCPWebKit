//
//  BuiltInTools.swift
//  MCPWebKit
//
//  內建 MCP 工具
//  提供基礎的 JavaScript 執行、狀態查詢、日誌管理功能
//

import Foundation
import MCPKit

// MARK: - Get Status Tool

/// 獲取 MCP Server 狀態
public struct GetStatusTool: MCPTool {
    public static let name = "get_status"
    public static let description = "獲取 MCP Server 狀態和埠號"
    public static let inputSchema = MCPInputSchema.empty

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        let status: [String: Any] = [
            "status": "running",
            "port": context.serverPort,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        return status
    }
}

// MARK: - Get Logs Tool

/// 獲取 Debug 日誌
public struct GetLogsTool: MCPTool {
    public static let name = "get_logs"
    public static let description = "獲取 Debug 日誌（最多 10,000 條）"
    public static let inputSchema = MCPInputSchema.empty

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        let logs = context.getLogs()
        return [
            "logs": logs,
            "count": logs.count
        ]
    }
}

// MARK: - Clear Logs Tool

/// 清空日誌
public struct ClearLogsTool: MCPTool {
    public static let name = "clear_logs"
    public static let description = "清空所有日誌"
    public static let inputSchema = MCPInputSchema.empty

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        context.clearLogs()
        return [
            "success": true,
            "message": "Logs cleared"
        ]
    }
}

// MARK: - Execute JS Tool

/// 執行 JavaScript
public struct ExecuteJSTool: MCPTool {
    public static let name = "execute_js"
    public static let description = """
        在 WebView 中執行 JavaScript 代碼。
        ⚠️ 重要：必須使用 return 語句才能獲取返回值！
        例如：'return 1+1' 返回 2，'return document.title' 返回標題。
        返回 Object 時使用 JSON.stringify()。
        """
    public static let inputSchema = MCPInputSchema(
        properties: [
            "code": .string("要執行的 JavaScript 代碼（函數體格式，需要 return 語句才能獲取返回值）")
        ],
        required: ["code"]
    )

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        guard let code = arguments["code"] as? String, !code.isEmpty else {
            throw MCPToolError.missingParameter("code")
        }

        let result = try await context.executeJavaScript(code)
        return ["result": result ?? NSNull()]
    }
}

// MARK: - Query Selector Tool

/// 使用 CSS 選擇器查詢元素
public struct QuerySelectorTool: MCPTool {
    public static let name = "query_selector"
    public static let description = "使用 CSS 選擇器查詢頁面元素，返回元素信息（tagName, id, className, innerText 等）"
    public static let inputSchema = MCPInputSchema(
        properties: [
            "selector": .string("CSS 選擇器，如 '#myId', '.myClass', 'div.container'"),
            "all": .boolean("是否查詢所有匹配元素（預設 false，只返回第一個）")
        ],
        required: ["selector"]
    )

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        guard let selector = arguments["selector"] as? String else {
            throw MCPToolError.missingParameter("selector")
        }

        let all = arguments["all"] as? Bool ?? false
        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")

        let script: String
        if all {
            script = """
            return JSON.stringify(Array.from(document.querySelectorAll('\(escapedSelector)')).map(el => ({
                tagName: el.tagName,
                id: el.id,
                className: el.className,
                innerText: el.innerText?.substring(0, 100),
                href: el.href,
                src: el.src,
                value: el.value
            })))
            """
        } else {
            script = """
            const el = document.querySelector('\(escapedSelector)');
            if (!el) return JSON.stringify(null);
            return JSON.stringify({
                tagName: el.tagName,
                id: el.id,
                className: el.className,
                innerText: el.innerText?.substring(0, 100),
                href: el.href,
                src: el.src,
                value: el.value,
                rect: el.getBoundingClientRect()
            })
            """
        }

        let result = try await context.executeJavaScript(script)

        // 解析 JSON 結果
        if let jsonString = result as? String,
           let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) {
            return ["elements": parsed]
        }

        return ["elements": result ?? NSNull()]
    }
}

// MARK: - Click Element Tool

/// 點擊頁面元素
public struct ClickElementTool: MCPTool {
    public static let name = "click_element"
    public static let description = "點擊指定的頁面元素（使用 CSS 選擇器）"
    public static let inputSchema = MCPInputSchema(
        properties: [
            "selector": .string("CSS 選擇器，如 '#submitBtn', '.btn-primary'")
        ],
        required: ["selector"]
    )

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        guard let selector = arguments["selector"] as? String else {
            throw MCPToolError.missingParameter("selector")
        }

        let escapedSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        const el = document.querySelector('\(escapedSelector)');
        if (!el) return JSON.stringify({ success: false, error: 'Element not found' });
        el.click();
        return JSON.stringify({ success: true, tagName: el.tagName, id: el.id })
        """

        let result = try await context.executeJavaScript(script)

        if let jsonString = result as? String,
           let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return parsed
        }

        return ["success": false, "error": "Unknown error"]
    }
}

// MARK: - Get Page Info Tool

/// 獲取頁面基本信息
public struct GetPageInfoTool: MCPTool {
    public static let name = "get_page_info"
    public static let description = "獲取當前頁面的基本信息（URL、標題、大小等）"
    public static let inputSchema = MCPInputSchema.empty

    private let context: MCPContext

    public init(context: MCPContext) {
        self.context = context
    }

    public func execute(arguments: [String: Any]) async throws -> Any {
        let script = """
        return JSON.stringify({
            url: window.location.href,
            title: document.title,
            domain: window.location.hostname,
            pathname: window.location.pathname,
            width: window.innerWidth,
            height: window.innerHeight,
            scrollX: window.scrollX,
            scrollY: window.scrollY,
            readyState: document.readyState
        })
        """

        let result = try await context.executeJavaScript(script)

        if let jsonString = result as? String,
           let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return parsed
        }

        return ["error": "Failed to get page info"]
    }
}
