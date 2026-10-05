import TwilioConversationsClient
import XCTest

@testable import flutter_twilio_conversations_client

/// Proves the Twilio SDK links at the major version technical-parameters.md pins.
class RunnerTests: XCTestCase {
  func testLinksTheExpectedTwilioSdk() {
    XCTAssertTrue(TwilioConversationsClient.sdkVersion().hasPrefix("4."))
  }
}
