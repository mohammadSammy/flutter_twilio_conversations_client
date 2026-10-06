package com.identity_solutions.twilio_conversations

/** Holds the Dart listener; native code reports every [PlatformEvent] through [send]. */
class ConversationsEvents : EventsStreamHandler() {
    private var sink: PigeonEventSink<PlatformEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformEvent>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    fun send(event: PlatformEvent) {
        sink?.success(event)
    }
}
