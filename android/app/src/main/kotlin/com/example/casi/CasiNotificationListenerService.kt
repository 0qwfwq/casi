package com.example.casi

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * NotificationListenerService kept for two purposes only:
 *
 *  1. Acting as the registered listener so [android.media.session.MediaSessionManager.getActiveSessions]
 *     can hand back media controllers from any audio app on the device.
 *  2. Tracking active timer notifications posted by the user's default clock
 *     app (Google Clock, Samsung Clock, AOSP DeskClock, etc.) so the launcher
 *     can surface them in the home-screen timer pill.
 *
 * The previous tier-based notification pill / capture system has been
 * removed — there is no longer any general notification ingestion or
 * persistence happening here.
 */
class CasiNotificationListenerService : NotificationListenerService() {

    companion object {
        var instance: CasiNotificationListenerService? = null
            private set

        // Packages whose ongoing notifications we treat as system timers.
        // Add a package here and it will be parsed for HH:MM[:SS] timer text.
        private val CLOCK_PACKAGES = setOf(
            "com.google.android.deskclock",
            "com.android.deskclock",
            "com.sec.android.app.clockpackage",
            "com.oneplus.deskclock",
            "com.coloros.alarmclock",
            "com.miui.misound",
            "com.xiaomi.misettings",
            "com.android.alarmclock",
            "com.htc.android.worldclock",
            "com.lge.clock",
            "com.motorola.blur.alarmclock",
            "com.sonyericsson.organizer",
            "com.asus.deskclock"
        )

        // HH:MM:SS or MM:SS — captures the first time-shaped substring.
        private val TIMER_TIME_REGEX = Regex("""(?:(\d{1,2}):)?(\d{1,2}):(\d{2})""")
    }

    /** Active clock-app timer notifications, keyed by [StatusBarNotification.key]. */
    private val activeTimers = mutableMapOf<String, JSONObject>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        // Seed the in-memory cache from whatever is currently posted so the
        // launcher gets timers immediately on (re)connect rather than waiting
        // for the next post.
        try {
            val current = activeNotifications ?: emptyArray()
            for (sbn in current) ingestTimerIfApplicable(sbn)
        } catch (_: Exception) {}
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
        activeTimers.clear()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        ingestTimerIfApplicable(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val key = sbn.key ?: return
        if (activeTimers.remove(key) != null) {
            // No-op: the next getSystemTimers() call will reflect the removal.
        }
    }

    private fun ingestTimerIfApplicable(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg !in CLOCK_PACKAGES) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        val haystack = "$title\n$text\n$subText"

        // Heuristic — clock apps post separate notifications for alarms vs.
        // timers. The launcher reads alarms via AlarmManager.getNextAlarmClock()
        // already, so reject anything that doesn't *both* contain a time-shaped
        // value AND mention the word "timer" somewhere.
        val mentionsTimer = haystack.contains("timer", ignoreCase = true)
        if (!mentionsTimer) {
            activeTimers.remove(sbn.key)
            return
        }

        val match = TIMER_TIME_REGEX.find(haystack)
        if (match == null) {
            activeTimers.remove(sbn.key)
            return
        }

        val h = match.groupValues[1].toIntOrNull() ?: 0
        val m = match.groupValues[2].toIntOrNull() ?: 0
        val s = match.groupValues[3].toIntOrNull() ?: 0
        val totalSeconds = h * 3600 + m * 60 + s
        if (totalSeconds <= 0) {
            // Either a finished timer (00:00) or unparseable. Either way, drop.
            activeTimers.remove(sbn.key)
            return
        }

        val isPaused = haystack.contains("paused", ignoreCase = true)

        activeTimers[sbn.key ?: pkg] = JSONObject().apply {
            put("packageName", pkg)
            put("key", sbn.key ?: "")
            put("remainingSeconds", totalSeconds)
            put("title", if (title.isNotBlank()) title else "Timer")
            put("isRunning", !isPaused)
            // postTime lets Flutter compute drift-corrected remaining seconds —
            // the notification typically updates every second but we only poll
            // every 1–2 s, so subtracting elapsed-since-post smooths the count.
            put("postTime", sbn.postTime)
        }
    }

    /** Returns a JSON array of currently active clock-app timer notifications. */
    fun getActiveTimers(): String {
        // Re-read live whenever asked so we don't depend on caching alone.
        try {
            val live = activeNotifications ?: emptyArray()
            // Drop entries that have disappeared from the live set.
            val liveKeys = live.mapNotNull { it.key }.toSet()
            val stale = activeTimers.keys.filter { it !in liveKeys }
            for (k in stale) activeTimers.remove(k)
            // Re-ingest the live set to keep parsed values fresh.
            for (sbn in live) ingestTimerIfApplicable(sbn)
        } catch (_: Exception) {}

        val arr = JSONArray()
        for (entry in activeTimers.values) arr.put(entry)
        return arr.toString()
    }
}
