package com.identity_solutions.twilio_conversations

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** The class Flutter registers: connects the generated Pigeon channels to their implementations. */
class FlutterTwilioConversationsClientPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val events = ConversationsEvents()
        ConversationsHostApi.setUp(binding.binaryMessenger, ConversationsHostApiImpl(binding.applicationContext, events))
        EventsStreamHandler.register(binding.binaryMessenger, events)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ConversationsHostApi.setUp(binding.binaryMessenger, null)
    }
}
