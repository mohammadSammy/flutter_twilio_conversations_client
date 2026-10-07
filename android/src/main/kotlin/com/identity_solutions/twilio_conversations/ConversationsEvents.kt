package com.identity_solutions.twilio_conversations

import android.os.Handler
import android.os.Looper

/** Holds the Dart listener; native code reports every [PlatformEvent] through [send]. */
class ConversationsEvents : EventsStreamHandler() {
    private var sink: PigeonEventSink<PlatformEvent>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(p0: Any?, sink: PigeonEventSink<PlatformEvent>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    /** Flutter only accepts events on the main thread; upload progress may arrive on another. */
    fun send(event: PlatformEvent) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink?.success(event)
        } else {
            mainHandler.post { sink?.success(event) }
        }
    }
}
