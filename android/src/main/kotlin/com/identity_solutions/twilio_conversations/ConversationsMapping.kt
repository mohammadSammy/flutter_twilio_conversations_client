package com.identity_solutions.twilio_conversations

import com.twilio.conversations.Attributes
import com.twilio.conversations.Conversation
import com.twilio.conversations.ConversationsClient
import com.twilio.conversations.Media
import com.twilio.conversations.MediaCategory
import com.twilio.conversations.Message
import com.twilio.conversations.Participant
import com.twilio.util.ErrorInfo
import com.twilio.util.TwilioException
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

// Twilio SDK objects → Pigeon data. Dates become epoch milliseconds and attributes
// become JSON strings, so both platforms hand Dart the same shapes (api-design §9).

fun Conversation.toData() = ConversationData(
    sid = sid,
    status = if (status == Conversation.ConversationStatus.JOINED) {
        PlatformConversationStatus.JOINED
    } else {
        PlatformConversationStatus.NOT_PARTICIPATING
    },
    uniqueName = uniqueName,
    friendlyName = friendlyName,
    attributesJson = attributes?.jsonString(),
    lastMessageIndex = lastMessageIndex,
    lastMessageDateMillis = lastMessageDate?.time,
    lastReadMessageIndex = lastReadMessageIndex,
    dateCreatedMillis = dateCreatedAsDate?.time,
    createdBy = createdBy,
)

fun Message.toData() = MessageData(
    conversationSid = conversationSid,
    sid = sid,
    index = messageIndex,
    media = attachedMedia.map { it.toData() },
    author = author,
    body = body,
    dateCreatedMillis = dateCreatedAsDate?.time,
    attributesJson = attributes?.jsonString(),
    participantSid = participantSid,
)

fun Media.toData() = MediaData(
    sid = sid,
    category = when (category) {
        MediaCategory.BODY -> PlatformMediaCategory.BODY
        MediaCategory.HISTORY -> PlatformMediaCategory.HISTORY
        else -> PlatformMediaCategory.MEDIA
    },
    contentType = contentType,
    size = size,
    filename = filename,
)

fun Participant.toData() = ParticipantData(
    sid = sid,
    identity = identity,
    dateCreatedMillis = dateCreatedAsDate?.time,
    lastReadMessageIndex = lastReadMessageIndex,
    attributesJson = attributes?.jsonString(),
)

/** Twilio allows any JSON value as attributes, not only objects; Attributes keeps it as JSON text. */
fun Attributes.jsonString(): String = toString()

fun attributesFromJson(json: String): Attributes =
    when (val value = runCatching { JSONTokener(json).nextValue() }.getOrNull()) {
        is JSONObject -> Attributes(value)
        is JSONArray -> Attributes(value)
        is String -> Attributes(value)
        is Number -> Attributes(value)
        is Boolean -> Attributes(value)
        JSONObject.NULL -> Attributes.DEFAULT
        else -> throw PluginErrors.twilio("attributes are not valid JSON")
    }

val ConversationsClient.ConnectionState.platform
    get() = when (this) {
        ConversationsClient.ConnectionState.CONNECTING -> PlatformConnectionState.CONNECTING
        ConversationsClient.ConnectionState.CONNECTED -> PlatformConnectionState.CONNECTED
        ConversationsClient.ConnectionState.DISCONNECTED -> PlatformConnectionState.DISCONNECTED
        ConversationsClient.ConnectionState.DENIED -> PlatformConnectionState.DENIED
        ConversationsClient.ConnectionState.ERROR -> PlatformConnectionState.ERROR
        ConversationsClient.ConnectionState.FATAL_ERROR -> PlatformConnectionState.FATAL_ERROR
        else -> PlatformConnectionState.UNKNOWN
    }

/** null for SYNCHRONIZATION_DISABLED, which the plugin never turns on. */
val ConversationsClient.SynchronizationStatus.platform
    get() = when (this) {
        ConversationsClient.SynchronizationStatus.STARTED -> PlatformSyncStatus.STARTED
        ConversationsClient.SynchronizationStatus.CONVERSATIONS_COMPLETED -> PlatformSyncStatus.CONVERSATIONS_LIST_COMPLETED
        ConversationsClient.SynchronizationStatus.COMPLETED -> PlatformSyncStatus.COMPLETED
        ConversationsClient.SynchronizationStatus.FAILED -> PlatformSyncStatus.FAILED
        else -> null
    }

val PlatformLogLevel.twilio
    get() = when (this) {
        PlatformLogLevel.SILENT -> ConversationsClient.LogLevel.SILENT
        PlatformLogLevel.FATAL -> ConversationsClient.LogLevel.ASSERT
        PlatformLogLevel.ERROR -> ConversationsClient.LogLevel.ERROR
        PlatformLogLevel.WARNING -> ConversationsClient.LogLevel.WARN
        PlatformLogLevel.INFO -> ConversationsClient.LogLevel.INFO
        PlatformLogLevel.DEBUG -> ConversationsClient.LogLevel.DEBUG
        PlatformLogLevel.TRACE -> ConversationsClient.LogLevel.VERBOSE
    }

/** The error codes Dart maps to ConversationsException types (see pigeons/conversations_api.dart). */
object PluginErrors {
    val notConnected get() = FlutterError("not_connected", "connect has not completed, or the client was shut down")
    val alreadyConnected get() = FlutterError("already_connected", "a client is already connected; call shutdown first")

    fun mediaUpload(message: String, twilioCode: Int? = null) = FlutterError("media_upload", message, twilioCode)

    fun twilio(message: String) = FlutterError("twilio", message)

    /** A failed Twilio call. Every Twilio failure is "twilio" for now, keeping Twilio's code in
     *  `details`; which codes mean "token" or "conversation_not_found" is pinned down in C10. */
    fun from(error: ErrorInfo) = FlutterError("twilio", error.message, error.code)

    fun from(error: TwilioException) = from(error.errorInfo)
}
