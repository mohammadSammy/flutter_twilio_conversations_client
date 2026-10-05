package com.identity_solutions.twilio_conversations

import com.twilio.conversations.ConversationsClient
import kotlin.test.Test
import kotlin.test.assertTrue

/** Proves the Twilio SDK is on the classpath at the version technical-parameters.md pins. */
class TwilioSdkTest {
    @Test
    fun linksTheExpectedTwilioSdk() {
        assertTrue(ConversationsClient.getSdkVersion().startsWith("6.2.1"))
    }
}
