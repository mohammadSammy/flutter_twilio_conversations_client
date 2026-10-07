import Foundation
import TwilioConversationsClient

// Twilio SDK objects → Pigeon data. Dates become epoch milliseconds and attributes
// become JSON strings, so both platforms hand Dart the same shapes (api-design §9).

extension TCHConversation {
  func toData() -> ConversationData? {
    guard let sid else { return nil }
    return ConversationData(
      sid: sid,
      status: status == .joined ? .joined : .notParticipating,
      uniqueName: uniqueName,
      friendlyName: friendlyName,
      attributesJson: attributes()?.jsonString(),
      lastMessageIndex: lastMessageIndex?.int64Value,
      lastMessageDateMillis: lastMessageDate?.epochMillis,
      lastReadMessageIndex: lastReadMessageIndex?.int64Value,
      dateCreatedMillis: dateCreatedAsDate?.epochMillis,
      createdBy: createdBy
    )
  }
}

extension TCHMessage {
  func toData(conversationSid: String) -> MessageData? {
    guard let sid, let index else { return nil }
    return MessageData(
      conversationSid: conversationSid,
      sid: sid,
      index: index.int64Value,
      media: attachedMedia.map { $0.toData() },
      author: author,
      body: body,
      dateCreatedMillis: dateCreatedAsDate?.epochMillis,
      attributesJson: attributes()?.jsonString(),
      participantSid: participantSid
    )
  }
}

extension Media {
  func toData() -> MediaData {
    let platformCategory: PlatformMediaCategory
    switch category {
    case .body: platformCategory = .body
    case .history: platformCategory = .history
    default: platformCategory = .media
    }
    return MediaData(
      sid: sid,
      category: platformCategory,
      contentType: contentType,
      size: Int64(size),
      filename: filename
    )
  }
}

extension TCHParticipant {
  func toData() -> ParticipantData? {
    guard let sid else { return nil }
    return ParticipantData(
      sid: sid,
      identity: identity,
      dateCreatedMillis: dateCreatedAsDate?.epochMillis,
      lastReadMessageIndex: lastReadMessageIndex?.int64Value,
      attributesJson: attributes()?.jsonString()
    )
  }
}

extension TCHJsonAttributes {
  /// Twilio allows any JSON value as attributes, not only objects.
  func jsonString() -> String? {
    let value: Any
    if isNull {
      value = NSNull()
    } else if let dictionary {
      value = dictionary
    } else if let array {
      value = array
    } else if let string {
      value = string
    } else if let number {
      value = number
    } else {
      return nil
    }
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func from(json: String) throws -> TCHJsonAttributes {
    let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    switch value {
    case let dictionary as [String: Any]: return TCHJsonAttributes(dictionary: dictionary)
    case let array as [Any]: return TCHJsonAttributes(array: array)
    case let string as String: return TCHJsonAttributes(string: string)
    case let number as NSNumber: return TCHJsonAttributes(number: number)
    default: throw PluginErrors.twilio("attributes are not valid JSON")
    }
  }
}

extension TCHClientConnectionState {
  var platform: PlatformConnectionState {
    switch self {
    case .connecting: return .connecting
    case .connected: return .connected
    case .disconnected: return .disconnected
    case .denied: return .denied
    case .error: return .error
    case .fatalError: return .fatalError
    default: return .unknown
    }
  }
}

extension TCHClientSynchronizationStatus {
  /// nil for `synchronizationDisabled`, which the plugin never turns on.
  var platform: PlatformSyncStatus? {
    switch self {
    case .started: return .started
    case .conversationsListCompleted: return .conversationsListCompleted
    case .completed: return .completed
    case .failed: return .failed
    default: return nil
    }
  }
}

extension PlatformLogLevel {
  var twilio: TCHLogLevel {
    switch self {
    case .silent: return .silent
    case .fatal: return .fatal
    case .error: return .critical
    case .warning: return .warning
    case .info: return .info
    case .debug: return .debug
    case .trace: return .trace
    }
  }
}

extension Date {
  var epochMillis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

/// The error codes Dart maps to ConversationsException types (see pigeons/conversations_api.dart).
enum PluginErrors {
  static let notConnected = PigeonError(code: "not_connected", message: "connect has not completed, or the client was shut down", details: nil)
  static let alreadyConnected = PigeonError(code: "already_connected", message: "a client is already connected; call shutdown first", details: nil)

  static func conversationNotFound(_ sidOrUniqueName: String) -> PigeonError {
    PigeonError(code: "conversation_not_found", message: "no conversation \(sidOrUniqueName)", details: nil)
  }

  static func mediaUpload(_ message: String, twilioCode: Int? = nil) -> PigeonError {
    PigeonError(code: "media_upload", message: message, details: twilioCode)
  }

  static func twilio(_ message: String) -> PigeonError {
    PigeonError(code: "twilio", message: message, details: nil)
  }

  /// A failed Twilio result. Every Twilio failure is "twilio" for now, keeping Twilio's code in
  /// `details`; which codes mean "token" or "conversation_not_found" is pinned down in C10.
  static func from(_ result: TCHResult) -> PigeonError {
    let error = result.error
    return PigeonError(
      code: "twilio",
      message: error?.localizedDescription ?? result.resultText ?? "Twilio call failed",
      details: error?.code ?? result.resultCode
    )
  }
}
