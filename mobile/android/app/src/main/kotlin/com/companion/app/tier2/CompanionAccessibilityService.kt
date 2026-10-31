package com.companion.app.tier2

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat
import com.companion.app.MainActivity
import com.companion.app.R

/**
 * F10 Tier 2 Accessibility Service (sideloaded "demo" flavour only; not declared in the "play" flavour).
 * Off by default; the user enables it in Android settings after a plain-language explanation.
 * Shows a persistent notification while enabled. Never stores or transmits text from other apps.
 */
class CompanionAccessibilityService : AccessibilityService() {

    private var runner: SkillRunner? = null
    private lateinit var overlay: OverlayController
    private var windowChanges = 0
    private var lastPackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        overlay = OverlayController(this)
        showPersistentNotification()
    }

    fun startSkill(skill: Skill, assist: Boolean, lang: String) {
        runner?.stop("replaced")
        val set = SkillRepository.load(this)
        runner = SkillRunner(skill, assist, lang, overlay, set.maxSteps, set.timeoutSeconds * 1000L) { runner = null }
            .also { it.start() }
    }

    fun stopSkill(reason: String) {
        runner?.stop(reason)
        runner = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        // Optional cross-app F2 signal: counts + package names only, never screen text.
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val pkg = event.packageName?.toString()
            if (pkg != null && pkg != lastPackage) {
                lastPackage = pkg
                windowChanges++
                if (windowChanges % 5 == 0) {
                    Tier2Events.emit("signal", extra = mapOf("window_changes" to windowChanges))
                }
            }
        }
        val r = runner ?: return
        r.onEvent(event, rootInActiveWindow)
    }

    override fun onInterrupt() {
        stopSkill("interrupted")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        stopSkill("service_disabled")
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun showPersistentNotification() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, getString(R.string.tier2_channel), NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentTitle(getString(R.string.tier2_notification_title))
            .setContentText(getString(R.string.tier2_notification_text))
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        runCatching { nm.notify(NOTIFICATION_ID, n) } // may be blocked if notifications are denied
    }

    companion object {
        @Volatile var instance: CompanionAccessibilityService? = null
        private const val CHANNEL_ID = "companion_tier2"
        private const val NOTIFICATION_ID = 4201
    }
}
