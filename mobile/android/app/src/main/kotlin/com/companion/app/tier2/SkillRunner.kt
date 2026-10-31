package com.companion.app.tier2

import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Deterministic runner for ONE predefined skill (F10 Tier 2).
 *
 * Safety rules enforced on every accessibility event:
 *  - denylisted package or sensitive window (password/OTP/security) -> abort, no action
 *  - unexpected package (not in the skill's list, not Companion) -> abort, fall back to Guide/Tier 1
 *  - at most [maxSteps] steps and [timeoutMs] per run
 *  - Guide mode: only highlights; Assist mode: taps only `click` steps (never `guide_only`, e.g. WhatsApp Send)
 *  - Stop works at any time (overlay button / Flutter) and takes effect immediately
 *  - matching happens on the device; no screen text is stored or sent anywhere
 */
class SkillRunner(
    private val skill: Skill,
    private val assist: Boolean,
    private val lang: String,
    private val overlay: OverlayController,
    private val maxSteps: Int,
    private val timeoutMs: Long,
    private val onFinished: () -> Unit,
) {
    private var index = 0
    private var finished = false
    private val startedAt = SystemClock.elapsedRealtime()
    private var lastTarget: AccessibilityNodeInfo? = null
    private var lastActionAt = 0L
    private val handler = Handler(Looper.getMainLooper())
    private val timeoutCheck = object : Runnable {
        override fun run() {
            if (finished) return
            if (SystemClock.elapsedRealtime() - startedAt > timeoutMs) abort("timeout") else handler.postDelayed(this, 500)
        }
    }

    fun start() {
        if (skill.steps.size > maxSteps) return abort("too_many_steps")
        overlay.showRunning(assist, skill.steps[0].hint(lang)) { abort("user_stop") }
        Tier2Events.emit("started", skill.id, 0, extra = mapOf("mode" to if (assist) "assist" else "guide"))
        handler.postDelayed(timeoutCheck, 500)
    }

    fun onEvent(event: AccessibilityEvent, root: AccessibilityNodeInfo?) {
        if (finished) return
        val pkg = event.packageName?.toString() ?: root?.packageName?.toString()
        if (pkg == "com.companion.app" || pkg == null) return
        if (pkg == "com.android.systemui") return // notification shade, IME etc.

        if (Denylist.isPackageDenied(pkg)) return abort("denylisted")
        if (pkg !in skill.packages) {
            // Allow a short grace period while the target app is opening.
            if (SystemClock.elapsedRealtime() - startedAt > 4000) abort("unexpected_screen")
            return
        }
        if (Denylist.isSensitiveWindow(root)) return abort("sensitive_screen")

        val step = skill.steps[index]

        // User tapped the highlighted target themselves (Guide mode or guide_only step).
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED && lastTarget != null && matches(event.source, step)) {
            return advance()
        }

        val node = findTarget(root, step) ?: run {
            overlay.clearHighlight()
            return
        }
        if (step.onlyIfUnchecked && node.isCheckable && node.isChecked) return advance() // already on

        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        overlay.highlight(bounds, step.hint(lang))
        lastTarget = node

        val now = SystemClock.elapsedRealtime()
        if (assist && step.action == "click" && now - lastActionAt > 800) {
            lastActionAt = now
            if (performClick(node)) handler.postDelayed({ if (!finished) advance() }, 600)
        } else if (step.action == "wait_for") {
            advance()
        }
    }

    fun stop(reason: String) = abort(reason)

    private fun advance() {
        if (finished) return
        Tier2Events.emit("step", skill.id, index)
        index++
        lastTarget = null
        if (index >= skill.steps.size || index >= maxSteps) {
            finished = true
            handler.removeCallbacksAndMessages(null)
            overlay.hide()
            Tier2Events.emit("completed", skill.id, index)
            onFinished()
        } else {
            overlay.updateHint(skill.steps[index].hint(lang))
        }
    }

    private fun abort(reason: String) {
        if (finished) return
        finished = true
        handler.removeCallbacksAndMessages(null)
        overlay.hide()
        Tier2Events.emit("aborted", skill.id, index, reason)
        onFinished()
    }

    private fun performClick(node: AccessibilityNodeInfo): Boolean {
        var n: AccessibilityNodeInfo? = node
        var depth = 0
        while (n != null && depth < 4) {
            if (n.isPassword) return false
            if (n.isClickable && n.isEnabled) return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            n = n.parent
            depth++
        }
        return false
    }

    private fun matches(node: AccessibilityNodeInfo?, step: SkillStep): Boolean {
        if (node == null) return false
        val id = node.viewIdResourceName ?: ""
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""
        return step.ids.any { id == it || id.endsWith("/$it") } ||
            step.texts.any { text.equals(it, ignoreCase = true) } ||
            step.descs.any { desc.contains(it, ignoreCase = true) }
    }

    /** Several selectors (id, then exact text, then content description), first visible match wins. */
    private fun findTarget(root: AccessibilityNodeInfo?, step: SkillStep): AccessibilityNodeInfo? {
        if (root == null) return null
        for (id in step.ids) {
            val full = if (id.contains(":id/")) listOf(id) else skill.packages.map { "$it:id/$id" } + listOf("android:id/$id")
            for (f in full) root.findAccessibilityNodeInfosByViewId(f)?.firstOrNull { it.isVisibleToUser }?.let { return it }
        }
        for (t in step.texts) {
            root.findAccessibilityNodeInfosByText(t)?.firstOrNull {
                it.isVisibleToUser && it.text?.toString()?.equals(t, ignoreCase = true) == true
            }?.let { return it }
        }
        if (step.descs.isNotEmpty()) {
            val queue = ArrayDeque<AccessibilityNodeInfo>().apply { add(root) }
            var seen = 0
            while (queue.isNotEmpty() && seen < 500) {
                val n = queue.removeFirst(); seen++
                val d = n.contentDescription?.toString() ?: ""
                if (n.isVisibleToUser && step.descs.any { d.contains(it, ignoreCase = true) }) return n
                for (i in 0 until n.childCount) n.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }
}
