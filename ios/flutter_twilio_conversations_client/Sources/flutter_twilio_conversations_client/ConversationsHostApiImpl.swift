import Foundation
import TwilioConversationsClient
import UIKit

/// Wraps the Twilio iOS SDK. Runs on the main actor: Pigeon calls in on it, and Twilio
/// answers on the main queue because the plugin never sets its own dispatch queue.
@MainActor
final class ConversationsHostApiImpl: NSObject, ConversationsHostApi {
  private let events: ConversationsEvents
  private var client: TwilioConversationsClient?

  /// Uploads in progress, and the background task that keeps them going after the user
  /// leaves the app (api-design §6).
  private var uploadsInProgress = 0

  /// Calls waiting in syncedConversation, by conversation sid.
  private var syncWaiters: [String: [CheckedContinuation<Void, Error>]] = [:]
  private var uploadBackgroundTask: UIBackgroundTaskIdentifier = .invalid

  // Flutter registers plugins on the main thread, but `register` itself isn't main-actor isolated.
  nonisolated init(events: ConversationsEvents) {
    self.events = events
  }

  // MARK: Client

  func connect(token: String, region: String) async throws -> ClientData {
    // Dart refuses a second connect itself, so a client here was left behind by a Dart hot
    // restart, which Dart can no longer reach. Replace it.
    if client != nil { try await shutdown() }
    let properties = TwilioConversationsClientProperties()
    if !region.isEmpty { properties.region = region }

    let client: TwilioConversationsClient = try await withCheckedThrowingContinuation { continuation in
      TwilioConversationsClient.conversationsClient(withToken: token, properties: properties, delegate: self) {
        result, client in
        if result.isSuccessful, let client {
          continuation.resume(returning: client)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
    self.client = client
    return ClientData(
      myIdentity: client.user?.identity ?? "",
      connectionState: client.connectionState.platform,
      syncStatus: client.synchronizationStatus.platform
    )
  }

  func updateToken(token: String) async throws {
    let client = try connectedClient()
    try await completion { client.updateToken(token, completion: $0) }
  }

  /// Safe to call twice: shutting down without a client does nothing.
  func shutdown() async throws {
    client?.delegate = nil  // nothing from the old client reaches a later session
    client?.shutdown()
    client = nil
    syncWaiters.keys.forEach { endSyncWaits($0, throwing: PluginErrors.notConnected) }
  }

  nonisolated func setLogLevel(level: PlatformLogLevel) throws {
    TwilioConversationsClient.setLogLevel(level.twilio)
  }

  // MARK: Conversations

  func myConversations() async throws -> [ConversationData] {
    (try connectedClient().myConversations() ?? []).compactMap { $0.toData() }
  }

  func getConversation(sidOrUniqueName: String) async throws -> ConversationData {
    try data(of: try await conversation(sidOrUniqueName))
  }

  func createConversation(uniqueName: String?, friendlyName: String?, attributesJson: String?) async throws
    -> ConversationData
  {
    let client = try connectedClient()
    let attributes = try attributesJson.map(TCHJsonAttributes.from(json:))
    var options: [String: Any] = [:]
    if let uniqueName { options[TCHConversationOptionUniqueName] = uniqueName }
    if let friendlyName { options[TCHConversationOptionFriendlyName] = friendlyName }
    // The creation option only takes a JSON object; other JSON values are set right after.
    if let dictionary = attributes?.dictionary { options[TCHConversationOptionAttributes] = dictionary }

    let conversation: TCHConversation = try await withCheckedThrowingContinuation { continuation in
      client.createConversation(options: options) { result, conversation in
        if result.isSuccessful, let conversation {
          continuation.resume(returning: conversation)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
    if let attributes, attributes.dictionary == nil {
      try await completion { conversation.setAttributes(attributes, completion: $0) }
    }
    return try data(of: conversation)
  }

  func join(conversationSid: String) async throws -> ConversationData {
    let conversation = try await conversation(conversationSid)
    try await completion { conversation.join(completion: $0) }
    return try data(of: conversation)
  }

  func getParticipantByIdentity(conversationSid: String, identity: String) async throws -> ParticipantData? {
    try await syncedConversation(conversationSid).participant(withIdentity: identity)?.toData()
  }

  // MARK: Messages and read state

  func getMessagesCount(conversationSid: String) async throws -> Int64 {
    let conversation = try await conversation(conversationSid)
    return try await withCheckedThrowingContinuation { continuation in
      conversation.getMessagesCount { result, count in
        continuation.resume(with: result.isSuccessful ? .success(Int64(count)) : .failure(PluginErrors.from(result)))
      }
    }
  }

  func getMessagesBefore(conversationSid: String, index: Int64, count: Int64) async throws -> [MessageData] {
    let conversation = try await syncedConversation(conversationSid)
    return try await messages(in: conversationSid) {
      conversation.getMessagesBefore(UInt(index), withCount: UInt(count), completion: $0)
    }
  }

  func getLastMessages(conversationSid: String, count: Int64) async throws -> [MessageData] {
    let conversation = try await syncedConversation(conversationSid)
    return try await messages(in: conversationSid) { conversation.getLastMessages(withCount: UInt(count), completion: $0) }
  }

  /// nil until the user has read something in this conversation.
  func getUnreadMessagesCount(conversationSid: String) async throws -> Int64? {
    let conversation = try await conversation(conversationSid)
    return try await withCheckedThrowingContinuation { continuation in
      conversation.getUnreadMessagesCount { result, count in
        continuation.resume(with: result.isSuccessful ? .success(count?.int64Value) : .failure(PluginErrors.from(result)))
      }
    }
  }

  /// Returns the unread count after the change.
  func setLastReadMessageIndex(conversationSid: String, index: Int64) async throws -> Int64? {
    let conversation = try await syncedConversation(conversationSid)
    return try await withCheckedThrowingContinuation { continuation in
      conversation.setLastReadMessageIndex(NSNumber(value: index)) { result, count in
        continuation.resume(with: result.isSuccessful ? .success(Int64(count)) : .failure(PluginErrors.from(result)))
      }
    }
  }

  /// Like setLastReadMessageIndex, but never moves the read position back.
  func advanceLastReadMessageIndex(conversationSid: String, index: Int64) async throws -> Int64? {
    let conversation = try await syncedConversation(conversationSid)
    return try await withCheckedThrowingContinuation { continuation in
      conversation.advanceLastReadMessageIndex(NSNumber(value: index)) { result, count in
        continuation.resume(with: result.isSuccessful ? .success(Int64(count)) : .failure(PluginErrors.from(result)))
      }
    }
  }

  func setAllMessagesRead(conversationSid: String) async throws -> Int64? {
    let conversation = try await syncedConversation(conversationSid)
    // Swift only offers the async form of this zero-argument call; the completion form is shadowed.
    let (result, count) = await conversation.setAllMessagesRead()
    guard result.isSuccessful else { throw PluginErrors.from(result) }
    return Int64(count)
  }

  func sendText(conversationSid: String, body: String) async throws -> MessageData {
    let conversation = try await syncedConversation(conversationSid)
    return try await send(conversation.prepareMessage().setBody(body), in: conversationSid)
  }

  func sendMedia(conversationSid: String, uploadId: String, filePath: String, contentType: String, filename: String?)
    async throws -> MessageData
  {
    let conversation = try await syncedConversation(conversationSid)
    // The size comes from URL resource values: attributesOfItem is one of Apple's
    // required-reason APIs, which would need a privacy-manifest declaration.
    guard let stream = InputStream(fileAtPath: filePath),
      let size = (try? URL(fileURLWithPath: filePath).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    else {
      throw PluginErrors.mediaUpload("cannot read \(filePath)")
    }
    let totalBytes = Int64(size)
    uploadStarted()
    defer { uploadEnded() }
    let events = self.events
    let failure = UploadFailure()
    // Twilio reports every few KB; about 100 events per upload is plenty, plus the last one.
    let step = max(Int64(64 * 1024), totalBytes / 100)
    let throttle = ProgressThrottle()
    // Progress may arrive off the main queue; events must reach Flutter on it, and the
    // throttle runs there too, so its counter is only ever touched from one thread.
    let listener = MediaMessageListener(
      onStarted: nil,
      onProgress: { bytes in
        let sent = Int64(bytes)
        DispatchQueue.main.async {
          guard sent - throttle.lastSent >= step || sent >= totalBytes else { return }
          throttle.lastSent = sent
          events.send(UploadProgressEvent(uploadId: uploadId, bytesSent: sent, totalBytes: totalBytes))
        }
      },
      onCompleted: nil,
      onFailed: { error in failure.error = error }
    )
    let builder = conversation.prepareMessage()
      .addMedia(inputStream: stream, contentType: contentType, filename: filename, listener: listener)
    do {
      return try await send(builder, in: conversationSid)
    } catch {
      guard let uploadError = failure.error else { throw error }
      throw PluginErrors.mediaUpload(uploadError.localizedDescription, twilioCode: uploadError.code)
    }
  }

  /// iOS gives a backgrounded app about 30 s; when that runs out it suspends the app, and the
  /// upload fails or resumes when the app comes back. One task covers all uploads.
  private func uploadStarted() {
    uploadsInProgress += 1
    guard uploadBackgroundTask == .invalid else { return }
    uploadBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Twilio media upload") { [weak self] in
      MainActor.assumeIsolated { self?.endUploadBackgroundTask() }
    }
  }

  private func uploadEnded() {
    uploadsInProgress -= 1
    if uploadsInProgress == 0 { endUploadBackgroundTask() }
  }

  private func endUploadBackgroundTask() {
    guard uploadBackgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(uploadBackgroundTask)
    uploadBackgroundTask = .invalid
  }

  func typing(conversationSid: String) async throws {
    try await conversation(conversationSid).typing()
  }

  func getMediaTemporaryUrl(conversationSid: String, messageIndex: Int64, mediaSid: String) async throws -> String {
    let conversation = try await syncedConversation(conversationSid)
    let message: TCHMessage = try await withCheckedThrowingContinuation { continuation in
      conversation.message(withIndex: NSNumber(value: messageIndex)) { result, message in
        if result.isSuccessful, let message {
          continuation.resume(returning: message)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
    guard let media = message.attachedMedia.first(where: { $0.sid == mediaSid }) else {
      throw PluginErrors.twilio("message \(messageIndex) has no media \(mediaSid)")
    }
    return try await withCheckedThrowingContinuation { continuation in
      _ = media.getTemporaryContentUrl { result, url in
        if result.isSuccessful, let url {
          continuation.resume(returning: url.absoluteString)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
  }

  // MARK: Push through Twilio (optional)

  func registerPushToken(type: PlatformPushTokenType, token: String) async throws {
    let client = try connectedClient()
    let data = try apnsToken(type: type, token: token)
    try await completion { client.register(withNotificationToken: data, completion: $0) }
  }

  func unregisterPushToken(type: PlatformPushTokenType, token: String) async throws {
    let client = try connectedClient()
    let data = try apnsToken(type: type, token: token)
    try await completion { client.deregister(withNotificationToken: data, completion: $0) }
  }

  // MARK: Helpers

  private func connectedClient() throws -> TwilioConversationsClient {
    guard let client else { throw PluginErrors.notConnected }
    return client
  }

  /// A conversation whose messages and participants are loaded. A conversation created moments ago is still
  /// loading; until then iOS returns nil for a participant or the read index (Android throws). Waits until it
  /// has synced or failed, as the client delegate reports it (Twilio's demo app waits the same way). The user
  /// leaving or a shutdown fails the call. A conversation this identity hasn't joined never syncs, so it doesn't
  /// wait for one.
  private func syncedConversation(_ sid: String) async throws -> TCHConversation {
    let conversation = try await conversation(sid)
    guard !conversation.isSynced, conversation.status == .joined, let key = conversation.sid else {
      return conversation
    }
    // No suspension between the check above and registering, and delegate calls run on the main actor.
    try await withCheckedThrowingContinuation { syncWaiters[key, default: []].append($0) }
    return conversation
  }

  private func endSyncWaits(_ sid: String, throwing error: Error? = nil) {
    syncWaiters.removeValue(forKey: sid)?.forEach { waiter in
      if let error { waiter.resume(throwing: error) } else { waiter.resume() }
    }
  }

  private func conversation(_ sidOrUniqueName: String) async throws -> TCHConversation {
    let client = try connectedClient()
    return try await withCheckedThrowingContinuation { continuation in
      client.conversation(withSidOrUniqueName: sidOrUniqueName) { result, conversation in
        if result.isSuccessful, let conversation {
          continuation.resume(returning: conversation)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
  }

  private func data(of conversation: TCHConversation) throws -> ConversationData {
    guard let data = conversation.toData() else { throw PluginErrors.twilio("conversation has no sid") }
    return data
  }

  /// Runs a Twilio call that only reports success or failure.
  private func completion(_ call: (@escaping TCHCompletion) -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      call { result in
        continuation.resume(with: result.isSuccessful ? .success(()) : .failure(PluginErrors.from(result)))
      }
    }
  }

  private func messages(in conversationSid: String, _ call: (@escaping TCHMessagesCompletion) -> Void) async throws
    -> [MessageData]
  {
    try await withCheckedThrowingContinuation { continuation in
      call { result, messages in
        if result.isSuccessful {
          continuation.resume(returning: (messages ?? []).compactMap { $0.toData(conversationSid: conversationSid) })
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
  }

  private func send(_ builder: MessageBuilder, in conversationSid: String) async throws -> MessageData {
    try await withCheckedThrowingContinuation { continuation in
      _ = builder.buildAndSend { result, message in
        if result.isSuccessful, let data = message?.toData(conversationSid: conversationSid) {
          continuation.resume(returning: data)
        } else {
          continuation.resume(throwing: PluginErrors.from(result))
        }
      }
    }
  }

  /// APNs tokens arrive as hex strings, the form Flutter push plugins report them in.
  private func apnsToken(type: PlatformPushTokenType, token: String) throws -> Data {
    guard type == .apns else { throw PluginErrors.twilio("iOS registers APNs tokens only") }
    var data = Data(capacity: token.count / 2)
    var index = token.startIndex
    while index < token.endIndex {
      let next = token.index(index, offsetBy: 2, limitedBy: token.endIndex) ?? token.endIndex
      guard let byte = UInt8(token[index..<next], radix: 16) else {
        throw PluginErrors.twilio("APNs token is not a hex string")
      }
      data.append(byte)
      index = next
    }
    return data
  }
}

extension TCHConversation {
  fileprivate var isSynced: Bool { synchronizationStatus == .all || synchronizationStatus == .failed }
}

/// Remembers why a media upload failed, so the send error can say so.
private final class UploadFailure {
  var error: TCHError?
}

/// The last progress value sent to Dart for one upload.
private final class ProgressThrottle {
  var lastSent: Int64 = 0
}

// MARK: - Client events

// Twilio calls the delegate on the main queue (the plugin never sets its own dispatch queue).
extension ConversationsHostApiImpl: TwilioConversationsClientDelegate {
  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, connectionStateUpdated state: TCHClientConnectionState
  ) {
    MainActor.assumeIsolated { events.send(ConnectionStateEvent(state: state.platform)) }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, synchronizationStatusUpdated status: TCHClientSynchronizationStatus
  ) {
    MainActor.assumeIsolated {
      if let status = status.platform { events.send(SyncStatusEvent(status: status)) }
    }
  }

  nonisolated func conversationsClientTokenWillExpire(_ client: TwilioConversationsClient) {
    MainActor.assumeIsolated { events.send(TokenEvent(type: .aboutToExpire)) }
  }

  nonisolated func conversationsClientTokenExpired(_ client: TwilioConversationsClient) {
    MainActor.assumeIsolated { events.send(TokenEvent(type: .expired)) }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversationAdded conversation: TCHConversation
  ) {
    MainActor.assumeIsolated {
      if let data = conversation.toData() { events.send(ConversationAddedEvent(conversation: data)) }
    }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversation: TCHConversation, messageAdded message: TCHMessage
  ) {
    MainActor.assumeIsolated {
      guard let conversationData = conversation.toData(),
        let messageData = message.toData(conversationSid: conversationData.sid)
      else { return }
      events.send(MessageAddedEvent(message: messageData, conversation: conversationData))
    }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversation: TCHConversation, message: TCHMessage,
    updated: TCHMessageUpdate
  ) {
    MainActor.assumeIsolated {
      guard let sid = conversation.sid, let data = message.toData(conversationSid: sid) else { return }
      events.send(MessageUpdatedEvent(message: data))
    }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, typingStartedOn conversation: TCHConversation,
    participant: TCHParticipant
  ) {
    MainActor.assumeIsolated { sendTyping(conversation, participant, started: true) }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, typingEndedOn conversation: TCHConversation,
    participant: TCHParticipant
  ) {
    MainActor.assumeIsolated { sendTyping(conversation, participant, started: false) }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversation: TCHConversation, updated: TCHConversationUpdate
  ) {
    MainActor.assumeIsolated {
      guard let data = conversation.toData(), let reason = updated.platform else { return }
      events.send(ConversationUpdatedEvent(conversation: data, reason: reason))
    }
  }

  /// The current user left or was removed, or the conversation was closed or deleted.
  nonisolated func conversationsClient(_ client: TwilioConversationsClient, conversationDeleted conversation: TCHConversation) {
    MainActor.assumeIsolated {
      guard let sid = conversation.sid else { return }
      endSyncWaits(sid, throwing: PluginErrors.twilio("conversation \(sid) was removed while it was loading"))
      events.send(ConversationDeletedEvent(conversationSid: sid))
    }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversation: TCHConversation, participant: TCHParticipant,
    updated: TCHParticipantUpdate
  ) {
    MainActor.assumeIsolated {
      guard let sid = conversation.sid, let data = participant.toData(), let reason = updated.platform else { return }
      events.send(ParticipantUpdatedEvent(conversationSid: sid, participant: data, reason: reason))
    }
  }

  nonisolated func conversationsClient(
    _ client: TwilioConversationsClient, conversation: TCHConversation,
    synchronizationStatusUpdated status: TCHConversationSynchronizationStatus
  ) {
    MainActor.assumeIsolated {
      guard conversation.isSynced, let sid = conversation.sid else { return }
      endSyncWaits(sid)
    }
  }

  nonisolated func conversationsClient(_ client: TwilioConversationsClient, errorReceived error: TCHError) {
    MainActor.assumeIsolated {
      events.send(ClientErrorEvent(code: "twilio", message: error.localizedDescription, twilioCode: Int64(error.code)))
    }
  }

  private func sendTyping(_ conversation: TCHConversation, _ participant: TCHParticipant, started: Bool) {
    guard let sid = conversation.sid, let data = participant.toData() else { return }
    events.send(TypingEvent(conversationSid: sid, participant: data, started: started))
  }
}
