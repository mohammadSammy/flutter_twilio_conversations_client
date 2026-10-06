package com.identity_solutions.twilio_conversations

/** Wraps the Twilio Android SDK. Each method is replaced with the real Twilio call in C6. */
class ConversationsHostApiImpl(private val events: ConversationsEvents) : ConversationsHostApi {
    override suspend fun connect(token: String, region: String): ClientData = notYet("connect")
    override suspend fun updateToken(token: String) = notYet("updateToken")
    override suspend fun shutdown() = notYet("shutdown")
    override fun setLogLevel(level: PlatformLogLevel) = notYet("setLogLevel")
    override suspend fun myConversations(): List<ConversationData> = notYet("myConversations")
    override suspend fun getConversation(sidOrUniqueName: String): ConversationData = notYet("getConversation")
    override suspend fun createConversation(uniqueName: String?, friendlyName: String?, attributesJson: String?): ConversationData =
        notYet("createConversation")
    override suspend fun join(conversationSid: String): ConversationData = notYet("join")
    override suspend fun getParticipantByIdentity(conversationSid: String, identity: String): ParticipantData? =
        notYet("getParticipantByIdentity")
    override suspend fun getMessagesCount(conversationSid: String): Long = notYet("getMessagesCount")
    override suspend fun getMessagesBefore(conversationSid: String, index: Long, count: Long): List<MessageData> =
        notYet("getMessagesBefore")
    override suspend fun getLastMessages(conversationSid: String, count: Long): List<MessageData> = notYet("getLastMessages")
    override suspend fun getUnreadMessagesCount(conversationSid: String): Long? = notYet("getUnreadMessagesCount")
    override suspend fun setLastReadMessageIndex(conversationSid: String, index: Long): Long? = notYet("setLastReadMessageIndex")
    override suspend fun sendText(conversationSid: String, body: String): MessageData = notYet("sendText")
    override suspend fun sendMedia(
        conversationSid: String,
        uploadId: String,
        filePath: String,
        contentType: String,
        filename: String?,
    ): MessageData = notYet("sendMedia")
    override suspend fun typing(conversationSid: String) = notYet("typing")
    override suspend fun getMediaTemporaryUrl(conversationSid: String, messageIndex: Long, mediaSid: String): String =
        notYet("getMediaTemporaryUrl")
    override suspend fun registerPushToken(type: PlatformPushTokenType, token: String) = notYet("registerPushToken")
    override suspend fun unregisterPushToken(type: PlatformPushTokenType, token: String) = notYet("unregisterPushToken")

    private fun notYet(method: String): Nothing = throw FlutterError("unimplemented", "$method is not implemented yet")
}
