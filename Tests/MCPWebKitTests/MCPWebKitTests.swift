import XCTest
@testable import MCPWebKit

final class MCPWebKitTests: XCTestCase {

    func testVersionInfo() {
        XCTAssertEqual(MCPWebKit.version, "0.1.0")
        XCTAssertFalse(MCPWebKit.description.isEmpty)
    }

    @MainActor
    func testWebViewMCPContextInit() {
        let context = WebViewMCPContext()
        XCTAssertEqual(context.serverPort, 8765)
        XCTAssertNil(context.executeJavaScriptCallback)
    }

    @MainActor
    func testWebViewMCPContextLogging() {
        let context = WebViewMCPContext()

        // Test internal logging
        context.log("Test message")
        let logs = context.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("Test message"))

        // Test clear logs
        context.clearLogs()
        XCTAssertEqual(context.getLogs().count, 0)
    }

    func testToolInputSchema() {
        // Test empty schema
        let emptySchema = MCPInputSchema.empty
        XCTAssertTrue(emptySchema.properties.isEmpty)
        XCTAssertTrue(emptySchema.required.isEmpty)

        // Test schema with properties
        let schema = MCPInputSchema(
            properties: [
                "name": .string("Name parameter"),
                "count": .integer("Count parameter")
            ],
            required: ["name"]
        )
        XCTAssertEqual(schema.properties.count, 2)
        XCTAssertEqual(schema.required, ["name"])

        // Test JSON conversion
        let json = schema.toJSON()
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertNotNil(json["properties"])
        XCTAssertEqual(json["required"] as? [String], ["name"])
    }

    func testBuiltInToolsExist() {
        // Verify tool names
        XCTAssertEqual(GetStatusTool.name, "get_status")
        XCTAssertEqual(GetLogsTool.name, "get_logs")
        XCTAssertEqual(ClearLogsTool.name, "clear_logs")
        XCTAssertEqual(ExecuteJSTool.name, "execute_js")
        XCTAssertEqual(QuerySelectorTool.name, "query_selector")
        XCTAssertEqual(ClickElementTool.name, "click_element")
        XCTAssertEqual(GetPageInfoTool.name, "get_page_info")
    }

    @MainActor
    func testExecuteJSToolValidation() async throws {
        let context = WebViewMCPContext()
        let tool = ExecuteJSTool(context: context)

        // Test missing parameter
        do {
            _ = try await tool.execute(arguments: [:])
            XCTFail("Should throw missing parameter error")
        } catch let error as MCPToolError {
            if case .missingParameter(let param) = error {
                XCTAssertEqual(param, "code")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
}
