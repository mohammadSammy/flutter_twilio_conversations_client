package com.identity_solutions.twilio_conversations

import android.content.Context
import com.twilio.conversations.CallbackListener
import com.twilio.conversations.Conversation
import com.twilio.conversations.ConversationListener
import com.twilio.conversations.ConversationsClient
import com.twilio.conversations.ConversationsClientListener
import com.twilio.conversations.MediaUploadListener
import com.twilio.conversations.Message
import com.twilio.conversations.Participant
import com.twilio.conversations.StatusListener
import com.twilio.conversations.User
import com.twilio.conversations.extensions.build
import com.twilio.conversations.extensions.buildAndSend
import com.twilio.conversations.extensions.getConversation
import com.twilio.conversations.extensions.getLastMessages
import com.twilio.conversations.extensions.getMessageByIndex
import com.twilio.conversations.extensions.getMessagesBefore
import com.twilio.conversations.extensions.getTemporaryContentUrl
import com.twilio.conversations.extensions.getUnreadMessagesCount
import com.twilio.conversations.extensions.join
import com.twilio.conversations.extensions.registerFCMToken
import com.twilio.conversations.extensions.setLastReadMessageIndex
import com.twilio.util.ErrorInfo
import com.twilio.util.TwilioException
import java.io.File
import java.io.FileInputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Wraps the Twilio Android SDK. Pigeon calls in on the main thread, and Twilio answers on
 * the thread that created the client, which is also the main thread.
 */
class ConversationsHostApiImpl(
    private val context: Context,
    private val events: ConversationsEvents,
) : ConversationsHostApi {
    private var client: ConversationsClient? = null
    private var syncStatus: PlatformSyncStatus? = null

    /** Android reports messages and typing per conversation, so each one gets [conversationListener] once. */
    private val listenedConversations = mutableSetOf<String>()

    // Client

    override suspend fun connect(token: String, region: String): ClientData {
        if (client != null) throw PluginErrors.alreadyConnected
        val properties = ConversationsClient.Properties.newBuilder()
            .apply { if (region.isNotEmpty()) setRegion(region) }
            .createProperties()
        val client = suspendCancellableCoroutine { continuation ->
            ConversationsClient.create(context, token, properties, object : CallbackListener<ConversationsClient> {
                override fun onSuccess(result: ConversationsClient) {
                    // Added here, not after resuming, so no early connection or sync event is missed.
                    result.addListener(clientListener)
                    continuation.resume(result)
                }

                override fun onError(errorInfo: ErrorInfo) {
                    continuation.resumeWithException(PluginErrors.from(errorInfo))
                }
            })
        }
        this.client = client
        return ClientData(client.myIdentity, client.connectionState.platform, syncStatus)
    }

    override suspend fun updateToken(token: String) {
        val client = connectedClient()
        suspendCancellableCoroutine { continuation -> client.updateToken(token, statusListener(continuation)) }
    }

    /** Safe to call twice: shutting down without a client does nothing. */
    override suspend fun shutdown() {
        client?.let {
            it.myConversations.forEach { conversation -> conversation.removeListener(conversationListener) }
            it.removeListener(clientListener)
            it.shutdown()
        }
        client = null
        syncStatus = null
        listenedConversations.clear()
    }

    override fun setLogLevel(level: PlatformLogLevel) {
        ConversationsClient.setLogLevel(level.twilio)
    }

    // Conversations

    override suspend fun myConversations(): List<ConversationData> =
        connectedClient().myConversations.map { it.toData() }

    override suspend fun getConversation(sidOrUniqueName: String): ConversationData =
        conversation(sidOrUniqueName).toData()

    override suspend fun createConversation(uniqueName: String?, friendlyName: String?, attributesJson: String?): ConversationData {
        val builder = connectedClient().conversationBuilder()
        uniqueName?.let { builder.withUniqueName(it) }
        friendlyName?.let { builder.withFriendlyName(it) }
        attributesJson?.let { builder.withAttributes(attributesFromJson(it)) }
        val conversation = twilio { builder.build() }
        listenTo(conversation)
        return conversation.toData()
    }

    override suspend fun join(conversationSid: String): ConversationData {
        val conversation = conversation(conversationSid)
        twilio { conversation.join() }
        return conversation.toData()
    }

    override suspend fun getParticipantByIdentity(conversationSid: String, identity: String): ParticipantData? =
        conversation(conversationSid).getParticipantByIdentity(identity)?.toData()

    // Messages and read state

    override suspend fun getMessagesCount(conversationSid: String): Long {
        val conversation = conversation(conversationSid)
        return suspendCancellableCoroutine { continuation -> conversation.getMessagesCount(callbackListener(continuation)) }
    }

    override suspend fun getMessagesBefore(conversationSid: String, index: Long, count: Long): List<MessageData> {
        val conversation = conversation(conversationSid)
        return twilio { conversation.getMessagesBefore(index, count.toInt()) }.map { it.toData() }
    }

    override suspend fun getLastMessages(conversationSid: String, count: Long): List<MessageData> {
        val conversation = conversation(conversationSid)
        return twilio { conversation.getLastMessages(count.toInt()) }.map { it.toData() }
    }

    /** null until the user has read something in this conversation. */
    override suspend fun getUnreadMessagesCount(conversationSid: String): Long? {
        val conversation = conversation(conversationSid)
        return twilio { conversation.getUnreadMessagesCount() }
    }

    /** Returns the unread count after the change. */
    override suspend fun setLastReadMessageIndex(conversationSid: String, index: Long): Long? {
        val conversation = conversation(conversationSid)
        return twilio { conversation.setLastReadMessageIndex(index) }
    }

    override suspend fun sendText(conversationSid: String, body: String): MessageData {
        val builder = conversation(conversationSid).prepareMessage().setBody(body)
        return twilio { builder.buildAndSend() }.toData()
    }

    override suspend fun sendMedia(
        conversationSid: String,
        uploadId: String,
        filePath: String,
        contentType: String,
        filename: String?,
    ): MessageData {
        val conversation = conversation(conversationSid)
        val file = File(filePath)
        if (!file.canRead()) throw PluginErrors.mediaUpload("cannot read $filePath")
        val totalBytes = file.length()
        var uploadError: ErrorInfo? = null
        val listener = object : MediaUploadListener {
            override fun onStarted() {}

            override fun onProgress(bytesSent: Long) {
                events.send(UploadProgressEvent(uploadId, bytesSent, totalBytes))
            }

            override fun onCompleted(mediaSid: String) {}

            override fun onFailed(errorInfo: ErrorInfo) {
                uploadError = errorInfo
            }
        }
        return FileInputStream(file).use { stream ->
            val builder = conversation.prepareMessage().addMedia(stream, contentType, filename, listener)
            try {
                builder.buildAndSend().toData()
            } catch (e: TwilioException) {
                val error = uploadError ?: throw PluginErrors.from(e)
                throw PluginErrors.mediaUpload(error.message, error.code)
            }
        }
    }

    override suspend fun typing(conversationSid: String) {
        conversation(conversationSid).typing()
    }

    override suspend fun getMediaTemporaryUrl(conversationSid: String, messageIndex: Long, mediaSid: String): String {
        val conversation = conversation(conversationSid)
        val message = twilio { conversation.getMessageByIndex(messageIndex) }
        val media = message.attachedMedia.firstOrNull { it.sid == mediaSid }
            ?: throw PluginErrors.twilio("message $messageIndex has no media $mediaSid")
        return twilio { media.getTemporaryContentUrl() }
    }

    // Push through Twilio (optional)

    override suspend fun registerPushToken(type: PlatformPushTokenType, token: String) {
        val client = connectedClient()
        val fcmToken = fcmToken(type, token)
        twilio { client.registerFCMToken(fcmToken) }
    }

    override suspend fun unregisterPushToken(type: PlatformPushTokenType, token: String) {
        val client = connectedClient()
        val fcmToken = fcmToken(type, token)
        suspendCancellableCoroutine { continuation -> client.unregisterFCMToken(fcmToken, statusListener(continuation)) }
    }

    // Helpers

    private fun connectedClient(): ConversationsClient = client ?: throw PluginErrors.notConnected

    private suspend fun conversation(sidOrUniqueName: String): Conversation {
        val client = connectedClient()
        val conversation = twilio { client.getConversation(sidOrUniqueName) }
        listenTo(conversation)
        return conversation
    }

    private fun listenTo(conversation: Conversation) {
        if (listenedConversations.add(conversation.sid)) conversation.addListener(conversationListener)
    }

    /** Runs a call to Twilio's coroutine extensions, which fail with [TwilioException]. */
    private inline fun <T> twilio(call: () -> T): T =
        try {
            call()
        } catch (e: TwilioException) {
            throw PluginErrors.from(e)
        }

    private fun <T> callbackListener(continuation: CancellableContinuation<T>) = object : CallbackListener<T> {
        override fun onSuccess(result: T) = continuation.resume(result)

        override fun onError(errorInfo: ErrorInfo) = continuation.resumeWithException(PluginErrors.from(errorInfo))
    }

    private fun statusListener(continuation: CancellableContinuation<Unit>) = object : StatusListener {
        override fun onSuccess() = continuation.resume(Unit)

        override fun onError(errorInfo: ErrorInfo) = continuation.resumeWithException(PluginErrors.from(errorInfo))
    }

    private fun fcmToken(type: PlatformPushTokenType, token: String): ConversationsClient.FCMToken {
        if (type != PlatformPushTokenType.FCM) throw PluginErrors.twilio("Android registers FCM tokens only")
        return ConversationsClient.FCMToken(token)
    }

    // Events

    private val clientListener = object : ConversationsClientListener {
        override fun onConnectionStateChange(state: ConversationsClient.ConnectionState) {
            events.send(ConnectionStateEvent(state.platform))
        }

        override fun onClientSynchronization(status: ConversationsClient.SynchronizationStatus) {
            val platform = status.platform ?: return
            syncStatus = platform
            events.send(SyncStatusEvent(platform))
        }

        override fun onTokenAboutToExpire() {
            events.send(TokenEvent(PlatformTokenEventType.ABOUT_TO_EXPIRE))
        }

        override fun onTokenExpired() {
            events.send(TokenEvent(PlatformTokenEventType.EXPIRED))
        }

        override fun onConversationAdded(conversation: Conversation) {
            listenTo(conversation)
            events.send(ConversationAddedEvent(conversation.toData()))
        }

        override fun onConversationDeleted(conversation: Conversation) {
            listenedConversations.remove(conversation.sid)
        }

        override fun onError(errorInfo: ErrorInfo) {
            events.send(ClientErrorEvent("twilio", errorInfo.message, errorInfo.code.toLong()))
        }

        override fun onConversationUpdated(conversation: Conversation, reason: Conversation.UpdateReason) {}
        override fun onConversationSynchronizationChange(conversation: Conversation) {}
        override fun onUserUpdated(user: User, reason: User.UpdateReason) {}
        override fun onUserSubscribed(user: User) {}
        override fun onUserUnsubscribed(user: User) {}
        override fun onNewMessageNotification(conversationSid: String, messageSid: String, messageIndex: Long) {}
        override fun onAddedToConversationNotification(conversationSid: String) {}
        override fun onRemovedFromConversationNotification(conversationSid: String) {}
        override fun onNotificationSubscribed() {}
        override fun onNotificationFailed(errorInfo: ErrorInfo) {}
    }

    private val conversationListener = object : ConversationListener {
        override fun onMessageAdded(message: Message) {
            val conversation = message.conversation ?: return
            events.send(MessageAddedEvent(message.toData(), conversation.toData()))
        }

        override fun onMessageUpdated(message: Message, reason: Message.UpdateReason) {
            events.send(MessageUpdatedEvent(message.toData()))
        }

        override fun onTypingStarted(conversation: Conversation, participant: Participant) {
            events.send(TypingEvent(conversation.sid, participant.toData(), true))
        }

        override fun onTypingEnded(conversation: Conversation, participant: Participant) {
            events.send(TypingEvent(conversation.sid, participant.toData(), false))
        }

        override fun onMessageDeleted(message: Message) {}
        override fun onParticipantAdded(participant: Participant) {}
        override fun onParticipantUpdated(participant: Participant, reason: Participant.UpdateReason) {}
        override fun onParticipantDeleted(participant: Participant) {}
        override fun onSynchronizationChanged(conversation: Conversation) {}
    }
}
