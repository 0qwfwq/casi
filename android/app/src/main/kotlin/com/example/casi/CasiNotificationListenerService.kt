package com.example.casi

import android.app.Notification
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.service.notification.NotificationListenerService.Ranking
import android.service.notification.NotificationListenerService.RankingMap
import org.json.JSONArray
import org.json.JSONObject

class CasiNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val PREFS_NAME = "casi_notifications"
        private const val KEY_NOTIFICATIONS = "captured_notifications"
        private const val MAX_NOTIFICATIONS = 200

        // Static instance so MainActivity can call getActiveNotifications()
        var instance: CasiNotificationListenerService? = null
            private set
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val packageName = sbn.packageName ?: return

        // Skip our own notifications and system UI
        if (packageName == "com.example.casi") return
        if (packageName == "android" || packageName == "com.android.systemui") return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        // Skip empty notifications
        if (title.isBlank() && text.isBlank()) return

        // Build notification JSON
        val notifJson = JSONObject().apply {
            put("packageName", packageName)
            put("title", title)
            put("text", text)
            put("bigText", bigText)
            put("subText", subText)
            put("timestamp", sbn.postTime)
            put("key", sbn.key ?: "")
            put("category", notification.category ?: "")
        }

        saveNotification(notifJson)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // No action needed for history — history keeps all notifications.
        // Active notifications are read live via getActiveNotifs().
    }

    /**
     * Returns a JSON array string of currently active (non-dismissed) notifications
     * from the system notification shade.
     */
    fun getActiveNotifs(): String {
        val sbns = try {
            activeNotifications ?: emptyArray()
        } catch (e: Exception) {
            emptyArray<StatusBarNotification>()
        }

        // Get current ranking map for importance levels
        val rankingMap = try { getCurrentRanking() } catch (_: Exception) { null }

        val array = JSONArray()
        for (sbn in sbns) {
            val packageName = sbn.packageName ?: continue
            if (packageName == "com.example.casi") continue
            if (packageName == "android" || packageName == "com.android.systemui") continue

            val notification = sbn.notification ?: continue
            val extras = notification.extras ?: continue

            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
            val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

            if (title.isBlank() && text.isBlank()) continue

            // Determine importance from ranking
            var importance = 3 // default IMPORTANCE_DEFAULT
            if (rankingMap != null) {
                val ranking = Ranking()
                if (rankingMap.getRanking(sbn.key, ranking)) {
                    importance = ranking.importance
                }
            }

            val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
            val isForeground = (notification.flags and Notification.FLAG_FOREGROUND_SERVICE) != 0
            val isGroupSummary = (notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0

            val obj = JSONObject().apply {
                put("packageName", packageName)
                put("title", title)
                put("text", text)
                put("bigText", bigText)
                put("subText", subText)
                put("timestamp", sbn.postTime)
                put("key", sbn.key ?: "")
                put("category", notification.category ?: "")
                put("importance", importance)
                put("isOngoing", isOngoing)
                put("isForeground", isForeground)
                put("isGroupSummary", isGroupSummary)
            }
            array.put(obj)
        }
        return array.toString()
    }

    private fun saveNotification(notifJson: JSONObject) {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val existing = prefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"

        val array = try {
            JSONArray(existing)
        } catch (e: Exception) {
            JSONArray()
        }

        // Deduplicate: skip if same package+title+text already exists within last 5 minutes
        val newPkg = notifJson.optString("packageName")
        val newTitle = notifJson.optString("title")
        val newText = notifJson.optString("text")
        val newTimestamp = notifJson.optLong("timestamp")
        val fiveMinutes = 5 * 60 * 1000L

        for (i in 0 until array.length()) {
            val existingItem = array.optJSONObject(i) ?: continue
            if (existingItem.optString("packageName") == newPkg &&
                existingItem.optString("title") == newTitle &&
                existingItem.optString("text") == newText &&
                (newTimestamp - existingItem.optLong("timestamp")) < fiveMinutes) {
                return // Duplicate, skip
            }
        }

        array.put(notifJson)

        // Trim to max size (keep most recent)
        while (array.length() > MAX_NOTIFICATIONS) {
            array.remove(0)
        }

        prefs.edit().putString(KEY_NOTIFICATIONS, array.toString()).apply()
    }
}
