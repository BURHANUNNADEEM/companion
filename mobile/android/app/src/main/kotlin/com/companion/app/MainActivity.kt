package com.companion.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.companion.app.tier2.CompanionAccessibilityService
import com.companion.app.tier2.SkillRepository
import com.companion.app.tier2.Tier2Events

/**
 * Platform channels for F10 Tier 2:
 *  MethodChannel "companion/tier2"        -> isAvailable, isEnabled, openSettings, startSkill, stop
 *  EventChannel  "companion/tier2/events" -> started / step / completed / aborted (+ counts-only signals)
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "companion/tier2").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(BuildConfig.TIER2_ENABLED)
                "isEnabled" -> result.success(BuildConfig.TIER2_ENABLED && isServiceEnabled(this))
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "startSkill" -> {
                    if (!BuildConfig.TIER2_ENABLED) return@setMethodCallHandler result.error("unavailable", null, null)
                    val skillId = call.argument<String>("skillId") ?: ""
                    val mode = call.argument<String>("mode") ?: "guide"
                    val lang = call.argument<String>("lang") ?: "ur"
                    val service = CompanionAccessibilityService.instance
                        ?: return@setMethodCallHandler result.error("service_disabled", null, null)
                    // Only skills bundled in the APK can run; the id is re-validated here.
                    val skill = SkillRepository.load(this).find(skillId)
                        ?: return@setMethodCallHandler result.error("unknown_skill", null, null)
                    if (mode != "guide" && mode != "assist") return@setMethodCallHandler result.error("bad_mode", null, null)
                    service.startSkill(skill, assist = mode == "assist", lang = lang)
                    result.success(null)
                }
                "stop" -> {
                    CompanionAccessibilityService.instance?.stopSkill("user_stop")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "companion/tier2/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Tier2Events.sink = events
            }

            override fun onCancel(arguments: Any?) {
                Tier2Events.sink = null
            }
        })
    }

    companion object {
        fun isServiceEnabled(context: Context): Boolean {
            val expected = ComponentName(context, CompanionAccessibilityService::class.java).flattenToString()
            val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?: return false
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }
    }
}
