/// Wraps the Twilio iOS SDK. Each method is replaced with the real Twilio call in C5.
final class ConversationsHostApiImpl: ConversationsHostApi {
  private let events: ConversationsEvents

  init(events: ConversationsEvents) {
    self.events = events
  }

  func connect(token: String, region: String) async throws -> ClientData { throw notYet("connect") }
  func updateToken(token: String) async throws { throw notYet("updateToken") }
  func shutdown() async throws { throw notYet("shutdown") }
  func setLogLevel(level: PlatformLogLevel) throws { throw notYet("setLogLevel") }
  func myConversations() async throws -> [ConversationData] { throw notYet("myConversations") }
  func getConversation(sidOrUniqueName: String) async throws -> ConversationData { throw notYet("getConversation") }
  func createConversation(uniqueName: String?, friendlyName: String?, attributesJson: String?) async throws
    -> ConversationData
  { throw notYet("createConversation") }
  func join(conversationSid: String) async throws -> ConversationData { throw notYet("join") }
  func getParticipantByIdentity(conversationSid: String, identity: String) async throws -> ParticipantData? {
    throw notYet("getParticipantByIdentity")
  }
  func getMessagesCount(conversationSid: String) async throws -> Int64 { throw notYet("getMessagesCount") }
  func getMessagesBefore(conversationSid: String, index: Int64, count: Int64) async throws -> [MessageData] {
    throw notYet("getMessagesBefore")
  }
  func getLastMessages(conversationSid: String, count: Int64) async throws -> [MessageData] {
    throw notYet("getLastMessages")
  }
  func getUnreadMessagesCount(conversationSid: String) async throws -> Int64? { throw notYet("getUnreadMessagesCount") }
  func setLastReadMessageIndex(conversationSid: String, index: Int64) async throws -> Int64? {
    throw notYet("setLastReadMessageIndex")
  }
  func sendText(conversationSid: String, body: String) async throws -> MessageData { throw notYet("sendText") }
  func sendMedia(conversationSid: String, uploadId: String, filePath: String, contentType: String, filename: String?)
    async throws -> MessageData
  { throw notYet("sendMedia") }
  func typing(conversationSid: String) async throws { throw notYet("typing") }
  func getMediaTemporaryUrl(conversationSid: String, messageIndex: Int64, mediaSid: String) async throws -> String {
    throw notYet("getMediaTemporaryUrl")
  }
  func registerPushToken(type: PlatformPushTokenType, token: String) async throws { throw notYet("registerPushToken") }
  func unregisterPushToken(type: PlatformPushTokenType, token: String) async throws {
    throw notYet("unregisterPushToken")
  }

  private func notYet(_ method: String) -> PigeonError {
    PigeonError(code: "unimplemented", message: "\(method) is not implemented yet", details: nil)
  }
}
