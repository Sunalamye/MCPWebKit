//
//  WebViewMCPContext.swift
//  MCPWebKit
//
//  WebView MCP 上下文實現
//  將回調模式橋接到 MCPKit 的 async/await 介面
//

import Foundation
import MCPKit

// MARK: - WebView MCP Context

/// WebView 專用的 MCP 上下文實現
/// 提供 JavaScript 執行和日誌功能
@MainActor
public final class WebViewMCPContext: MCPContext {

    // MARK: - Properties

    public var serverPort: UInt16 = 8765

    /// 執行 JavaScript 的回調（從外部注入）
    public var executeJavaScriptCallback: ((String, @escaping (Any?, Error?) -> Void) -> Void)?

    /// 獲取自定義狀態的回調
    public var getCustomStatusCallback: (() -> [String: Any])?

    /// 獲取日誌的回調
    public var getLogsCallback: (() -> [String])?

    /// 清空日誌的回調
    public var clearLogsCallback: (() -> Void)?

    /// 記錄日誌的回調
    public var logCallback: ((String) -> Void)?

    /// 內部日誌緩衝區
    private var logBuffer: [String] = []
    private let maxLogCount = 10000

    // MARK: - Initialization

    public init() {}

    // MARK: - MCPContext Implementation

    public func executeJavaScript(_ script: String) async throws -> Any? {
        guard let callback = executeJavaScriptCallback else {
            throw MCPToolError.notAvailable("JavaScript execution")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            callback(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    // Use nonisolated(unsafe) since callback happens on MainActor
                    nonisolated(unsafe) let unsafeResult = result
                    continuation.resume(returning: unsafeResult)
                }
            }
        }
    }

    public func getLogs() -> [String] {
        return getLogsCallback?() ?? logBuffer
    }

    public func clearLogs() {
        clearLogsCallback?()
        logBuffer.removeAll()
    }

    public func log(_ message: String) {
        if let callback = logCallback {
            callback(message)
        } else {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logMessage = "[\(timestamp)] \(message)"
            logBuffer.append(logMessage)
            if logBuffer.count > maxLogCount {
                logBuffer.removeFirst()
            }
            print("[MCPWebKit] \(message)")
        }
    }

    // MARK: - Custom Status

    /// 獲取自定義狀態
    public func getCustomStatus() -> [String: Any]? {
        return getCustomStatusCallback?()
    }
}
