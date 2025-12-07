# MCPWebKit

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2026.0+-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**MCP + WebView 開發平台** - 讓 AI 工具（如 Claude Code）能夠控制 WebView 應用程式。

## 概述

MCPWebKit 整合了 [MCPKit](https://github.com/Sunalamye/MCPKit) 和 [WebViewBridge](https://github.com/Sunalamye/WebViewBridge)，提供一個完整的框架，讓你能夠：

- 🌐 嵌入任意網頁到你的 macOS 應用
- 🤖 通過 MCP 協議讓 AI 工具控制 WebView
- 🔧 使用內建工具執行 JavaScript、查詢元素、點擊操作
- 🛠️ 輕鬆擴展自定義 MCP 工具

## 架構

```
┌─────────────────────────────────────────────────────────────┐
│                       MCPWebKit                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ MCPWebServer │──│ MCPWebHandler│──│ WebViewMCPContext│  │
│  │ (HTTP 監聽)  │  │ (JSON-RPC)   │  │ (JS 回調橋接)    │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│         ↓                                    ↓              │
│    Claude Code                         WebPage/WKWebView    │
│    調用 MCP 工具                        執行 JavaScript      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   內建工具                           │   │
│  │  • execute_js      執行任意 JavaScript               │   │
│  │  • query_selector  CSS 選擇器查詢元素                │   │
│  │  • click_element   點擊頁面元素                      │   │
│  │  • get_page_info   獲取頁面信息                      │   │
│  │  • get_status      獲取服務器狀態                    │   │
│  │  • get_logs        獲取日誌                          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 安裝

### Swift Package Manager

在你的 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/Sunalamye/MCPWebKit.git", from: "0.1.0")
]
```

或在 Xcode 中：
1. File → Add Package Dependencies
2. 輸入 `https://github.com/Sunalamye/MCPWebKit.git`

## 快速開始

### 1. 創建 MCP Server

```swift
import MCPWebKit

@MainActor
class MyViewModel: ObservableObject {
    let mcpServer = MCPWebServer(port: 8765)
    var webPage: WebPage?

    func setupServer() {
        // 設置 JavaScript 執行回調
        mcpServer.executeJavaScript = { [weak self] script, completion in
            guard let page = self?.webPage else {
                completion(nil, NSError(domain: "App", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "WebPage not available"]))
                return
            }

            Task { @MainActor in
                do {
                    let result = try await page.callJavaScript(script)
                    completion(result, nil)
                } catch {
                    completion(nil, error)
                }
            }
        }

        // 啟動服務器
        mcpServer.start()
    }
}
```

### 2. 配置 Claude Code

在 `~/.claude/settings.json` 中添加：

```json
{
  "mcpServers": {
    "my-app": {
      "url": "http://localhost:8765/mcp"
    }
  }
}
```

### 3. 使用 MCP 工具

現在你可以在 Claude Code 中使用這些工具：

```
# 獲取頁面信息
mcp__my-app__get_page_info

# 執行 JavaScript
mcp__my-app__execute_js({ code: "return document.title" })

# 查詢元素
mcp__my-app__query_selector({ selector: "#myButton" })

# 點擊元素
mcp__my-app__click_element({ selector: ".submit-btn" })
```

## 內建工具

| 工具名稱 | 描述 |
|---------|------|
| `get_status` | 獲取 MCP Server 狀態和埠號 |
| `get_logs` | 獲取 Debug 日誌 |
| `clear_logs` | 清空所有日誌 |
| `execute_js` | 執行任意 JavaScript 代碼 |
| `query_selector` | 使用 CSS 選擇器查詢元素 |
| `click_element` | 點擊指定元素 |
| `get_page_info` | 獲取頁面基本信息（URL、標題等） |

## 自定義工具

你可以輕鬆創建自定義工具：

```swift
import MCPWebKit

struct MyCustomTool: MCPTool {
    static let name = "my_custom_tool"
    static let description = "我的自定義工具"
    static let inputSchema = MCPInputSchema(
        properties: [
            "param1": .string("參數說明")
        ],
        required: ["param1"]
    )

    private let context: MCPContext

    init(context: MCPContext) {
        self.context = context
    }

    func execute(arguments: [String: Any]) async throws -> Any {
        guard let param1 = arguments["param1"] as? String else {
            throw MCPToolError.missingParameter("param1")
        }

        // 執行你的邏輯
        let result = try await context.executeJavaScript("return '\(param1)'")
        return ["result": result ?? ""]
    }
}

// 註冊工具
mcpServer.registerTool(MyCustomTool.self)
```

## 依賴

- [MCPKit](https://github.com/Sunalamye/MCPKit) - MCP 協議實現
- [WebViewBridge](https://github.com/Sunalamye/WebViewBridge) - WebPage API 橋接

## 系統要求

- macOS 26.0+（使用 WebPage API）
- Swift 6.0+
- Xcode 26.0+

## License

MIT License - 詳見 [LICENSE](LICENSE)
