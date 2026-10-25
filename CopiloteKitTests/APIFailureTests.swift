import XCTest
@testable import CopiloteKit

final class APIFailureTests: XCTestCase {
    func test_readsTheErrorBodyOfAFailedHTTPResponse() {
        let body = #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-sonnet-9"}}"#

        let failure = APIFailure(httpStatus: 404, body: Data(body.utf8))

        XCTAssertEqual(failure, APIFailure(type: "not_found_error", message: "model: claude-sonnet-9"))
    }

    func test_fallsBackToTheStatusCodeWhenTheBodyIsNotAnAPIError() {
        let failure = APIFailure(httpStatus: 502, body: Data("<html>Bad gateway</html>".utf8))

        XCTAssertEqual(failure, APIFailure(type: "http_502", message: "HTTP 502"))
    }

    func test_userMessage_explainsTheCommonFailuresInEnglish() {
        XCTAssertEqual(
            APIFailure(type: "authentication_error", message: "invalid x-api-key").userMessage,
            "Anthropic rejected the API key. Check it in Settings."
        )
        XCTAssertEqual(
            APIFailure(type: "not_found_error", message: "model: claude-sonnet-9").userMessage,
            "Model not found (model: claude-sonnet-9). Check the model ID in Settings."
        )
        XCTAssertEqual(
            APIFailure(type: "overloaded_error", message: "Overloaded").userMessage,
            "Anthropic is overloaded. Try again shortly."
        )
        XCTAssertEqual(
            APIFailure(type: "rate_limit_error", message: "Too many requests").userMessage,
            "Rate limit reached. Try again shortly."
        )
        XCTAssertEqual(
            APIFailure(type: "invalid_request_error", message: "max_tokens: too large").userMessage,
            "Request rejected: max_tokens: too large"
        )
        XCTAssertEqual(APIFailure(type: "api_error", message: "Internal server error").userMessage, "API error: Internal server error")
        XCTAssertEqual(APIFailure(type: "http_502", message: "HTTP 502").userMessage, "API error: HTTP 502")
    }

    /// Older models (e.g. Haiku 4.5) reject the effort parameter, which is on by default.
    func test_userMessage_pointsToTheEffortSettingWhenTheModelRejectsIt() {
        let failure = APIFailure(type: "invalid_request_error", message: "output_config.effort: not supported on this model")

        XCTAssertEqual(
            failure.userMessage,
            "This model does not support effort settings. Choose Model default in Settings."
        )
    }
}
