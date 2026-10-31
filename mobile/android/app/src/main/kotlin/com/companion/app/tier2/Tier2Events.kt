package com.companion.app.tier2

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Sends outcome events to Flutter. Only ids, step indexes and reason codes - never screen text. */
object Tier2Events {
    @Volatile var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(type: String, skillId: String? = null, step: Int? = null, reason: String? = null, extra: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>()
        payload["type"] = type
        skillId?.let { payload["skillId"] = it }
        step?.let { payload["step"] = it }
        reason?.let { payload["reason"] = it }
        payload.putAll(extra)
        main.post { sink?.success(payload) }
    }
}
